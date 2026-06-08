use crate::context::RuntimeContext;
use crate::pipeline::DeploymentMode;
use crate::process::Logger;
use crate::progress::log::print_elapsed_summary;
use crate::workspace::CommonSourceWorkspace;
use std::io::BufRead;
use std::sync::Arc;
use tokio::task;

pub struct BatchRunner;

fn print_log_tail(log_path: &str, lines_count: usize) {
    if let Ok(file) = std::fs::File::open(log_path) {
        let reader = std::io::BufReader::new(file);
        let lines: Vec<String> = reader.lines().map_while(Result::ok).collect();
        let start = if lines.len() > lines_count {
            lines.len() - lines_count
        } else {
            0
        };
        eprintln!("\n=== Last {} lines of {} ===", lines_count, log_path);
        for line in &lines[start..] {
            eprintln!("{}", line);
        }
        eprintln!("======================================\n");
    }
}

fn print_batch_summary(title: &str, succeeded: usize, failed_hosts: &[(String, String)]) {
    let mode = crate::progress::color::ColorMode::Auto;
    let separator = "=".repeat(title.len());

    println!(
        "\n{}",
        crate::progress::color::colorize(title, crate::progress::color::BOLD, mode)
    );
    println!(
        "Succeeded: {}",
        crate::progress::color::colorize(
            &succeeded.to_string(),
            crate::progress::color::GREEN,
            mode
        )
    );
    if failed_hosts.is_empty() {
        println!(
            "Failed: {}",
            crate::progress::color::colorize("0", crate::progress::color::GREEN, mode)
        );
    } else {
        println!(
            "Failed: {}",
            crate::progress::color::colorize(
                &failed_hosts.len().to_string(),
                crate::progress::color::RED,
                mode
            )
        );
        for (host, err) in failed_hosts {
            println!(
                "  - {}: {}",
                crate::progress::color::colorize(host, crate::progress::color::RED, mode),
                err
            );
            println!("    Log file: .log/installer-rs-{}.log", host);
        }
    }
    println!(
        "{}",
        crate::progress::color::colorize(&separator, crate::progress::color::BOLD, mode)
    );
}

impl BatchRunner {
    pub async fn deploy_batch(
        hosts: Vec<RuntimeContext>,
        redeploy: bool,
        overwrite: bool,
        convert_to: Option<String>,
        common_workspace: Arc<CommonSourceWorkspace>,
        run_state: crate::plan::RunState,
        parallel: usize,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let start_time = std::time::Instant::now();

        // Ensure log directory exists
        if let Err(e) = std::fs::create_dir_all(".log") {
            return Err(format!("Failed to create log directory .log: {}", e).into());
        }

        let semaphore = if parallel > 0 {
            Some(Arc::new(tokio::sync::Semaphore::new(parallel)))
        } else {
            None
        };

        let mut handles = vec![];
        let mut succeeded = 0;
        let mut failed_hosts = vec![];

        for ctx in hosts {
            let host_name = ctx.hostname.clone();
            let host_name_for_thread = host_name.clone();
            let convert_to = convert_to.clone();
            let common_workspace = common_workspace.clone();
            let run_state = run_state.clone();

            let permit = if let Some(sem) = &semaphore {
                match sem.clone().acquire_owned().await {
                    Ok(p) => Some(p),
                    Err(_) => return Err("Failed to acquire concurrency permit".into()),
                }
            } else {
                None
            };

            let handle = task::spawn_blocking(move || -> Result<(), String> {
                let log_path = format!(".log/installer-rs-{}.log", host_name_for_thread);
                let log_file = std::fs::File::create(&log_path)
                    .map_err(|e| format!("Failed to create log file {}: {}", log_path, e))?;

                let logger = Logger::batch(host_name_for_thread.clone(), log_file);

                let mode = DeploymentMode::from_context(&ctx, convert_to.is_some());
                let install_ctx =
                    match crate::context::resolve_install_context(&ctx, &mode, convert_to.as_ref())
                    {
                        Ok(ctx) => ctx,
                        Err(e) => {
                            print_log_tail(&log_path, 20);
                            return Err(format!("Install context resolution failed: {}", e));
                        }
                    };

                let mut install_workspace = common_workspace
                    .prepare_host_context(&install_ctx, logger.clone())
                    .map_err(|e| format!("Workspace preparation failed: {}", e))?;

                let exec_ctx = crate::executor::host::HostExecutionContext {
                    logger: logger.clone(),
                    redeploy,
                    overwrite,
                    convert_to: convert_to.as_ref(),
                    switch_action: None,
                    home_manager: false,
                    run_state: &run_state,
                };

                if let Err(e) = crate::executor::host::execute_host_operation(
                    &ctx,
                    crate::plan::OperationKind::Deploy,
                    &exec_ctx,
                    &mut install_workspace,
                ) {
                    print_log_tail(&log_path, 20);
                    return Err(format!("Deployment failed: {}", e));
                }

                // Explicitly keep the permit alive until the end of execution.
                let _ = permit;
                Ok(())
            });
            handles.push((host_name, handle));
        }

        for (host_name, handle) in handles {
            match handle.await {
                Ok(Ok(())) => {
                    succeeded += 1;
                }
                Ok(Err(e)) => {
                    failed_hosts.push((host_name, e));
                }
                Err(panic_err) => {
                    failed_hosts.push((host_name, format!("Task panicked: {}", panic_err)));
                }
            }
        }

        print_batch_summary("=== Batch Deployment Summary ===", succeeded, &failed_hosts);

        if !failed_hosts.is_empty() {
            return Err(format!("Batch deployment failed for {} hosts", failed_hosts.len()).into());
        }

        print_elapsed_summary("Batch deployment successfully", start_time.elapsed());
        Ok(())
    }

    pub async fn switch_batch(
        hosts: Vec<RuntimeContext>,
        action: String,
        hm: bool,
        common_workspace: Arc<CommonSourceWorkspace>,
        run_state: crate::plan::RunState,
        parallel: usize,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let start_time = std::time::Instant::now();

        // Ensure log directory exists
        if let Err(e) = std::fs::create_dir_all(".log") {
            return Err(format!("Failed to create log directory .log: {}", e).into());
        }

        let semaphore = if parallel > 0 {
            Some(Arc::new(tokio::sync::Semaphore::new(parallel)))
        } else {
            None
        };

        let mut handles = vec![];
        let mut succeeded = 0;
        let mut failed_hosts = vec![];

        for ctx in hosts {
            let host_name = ctx.hostname.clone();
            let host_name_for_thread = host_name.clone();
            let action_clone = action.clone();
            let common_workspace = common_workspace.clone();
            let run_state = run_state.clone();

            let permit = if let Some(sem) = &semaphore {
                match sem.clone().acquire_owned().await {
                    Ok(p) => Some(p),
                    Err(_) => return Err("Failed to acquire concurrency permit".into()),
                }
            } else {
                None
            };

            let handle = task::spawn_blocking(move || -> Result<(), String> {
                let log_path = format!(".log/installer-rs-{}.log", host_name_for_thread);
                let log_file = std::fs::File::create(&log_path)
                    .map_err(|e| format!("Failed to create log file {}: {}", log_path, e))?;

                let logger = Logger::batch(host_name_for_thread.clone(), log_file);

                let mut switch_workspace = common_workspace
                    .prepare_host_context(&ctx, logger.clone())
                    .map_err(|e| format!("Workspace preparation failed: {}", e))?;

                let exec_ctx = crate::executor::host::HostExecutionContext {
                    logger: logger.clone(),
                    redeploy: false,
                    overwrite: false,
                    convert_to: None,
                    switch_action: Some(&action_clone),
                    home_manager: hm,
                    run_state: &run_state,
                };

                if let Err(e) = crate::executor::host::execute_host_operation(
                    &ctx,
                    crate::plan::OperationKind::Switch,
                    &exec_ctx,
                    &mut switch_workspace,
                ) {
                    print_log_tail(&log_path, 20);
                    return Err(format!("Switch failed: {}", e));
                }

                let _ = permit;
                Ok(())
            });
            handles.push((host_name, handle));
        }

        for (host_name, handle) in handles {
            match handle.await {
                Ok(Ok(())) => {
                    succeeded += 1;
                }
                Ok(Err(e)) => {
                    failed_hosts.push((host_name, e));
                }
                Err(panic_err) => {
                    failed_hosts.push((host_name, format!("Task panicked: {}", panic_err)));
                }
            }
        }

        print_batch_summary("=== Batch Switch Summary ===", succeeded, &failed_hosts);

        if !failed_hosts.is_empty() {
            return Err(format!("Batch switch failed for {} hosts", failed_hosts.len()).into());
        }

        print_elapsed_summary("Batch switch successfully", start_time.elapsed());
        Ok(())
    }
}
