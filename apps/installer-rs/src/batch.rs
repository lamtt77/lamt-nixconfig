use crate::context::RuntimeContext;
use crate::pipeline;
use crate::switch;
use crate::log_status;
use std::sync::{Arc, Mutex};
use std::io::BufRead;
use tokio::task;

pub struct BatchRunner;

fn print_log_tail(log_path: &str, lines_count: usize) {
    if let Ok(file) = std::fs::File::open(log_path) {
        let reader = std::io::BufReader::new(file);
        let lines: Vec<String> = reader.lines().filter_map(Result::ok).collect();
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

impl BatchRunner {
    pub async fn deploy_batch(hosts: Vec<RuntimeContext>, redeploy: bool) -> Result<(), Box<dyn std::error::Error>> {
        let start_time = std::time::Instant::now();

        // Ensure log directory exists
        if let Err(e) = std::fs::create_dir_all("_tmp") {
            return Err(format!("Failed to create log directory _tmp: {}", e).into());
        }

        let mut handles = vec![];

        for mut ctx in hosts {
            let host_name = ctx.hostname.clone();
            let handle = task::spawn_blocking(move || -> Result<(), String> {
                let log_path = format!("_tmp/installer-rs-{}.log", host_name);
                let log_file = std::fs::File::create(&log_path)
                    .map_err(|e| format!("Failed to create log file {}: {}", log_path, e))?;

                let log_target = Arc::new(Mutex::new(crate::process::LogTarget::Batch {
                    prefix: host_name.clone(),
                    file: log_file,
                }));

                log_status!(log_target, "Starting deployment...");

                let host_start = std::time::Instant::now();

                // Handle VM provider VM recreation
                if let Some(provider) = crate::resolve_provider(&ctx, Arc::clone(&log_target)) {
                    if redeploy {
                        log_status!(log_target, "Redeploy: Destroying and recreating VM instance...");
                        let _ = provider.destroy();
                        if let Err(e) = provider.create() {
                            print_log_tail(&log_path, 20);
                            return Err(format!("VM creation failed: {}", e));
                        }
                    }
                }

                ctx.target_ip = crate::resolve_target_ip(&ctx, Arc::clone(&log_target));

                if let Err(e) = pipeline::run_deployment(&ctx, Arc::clone(&log_target)) {
                    print_log_tail(&log_path, 20);
                    return Err(format!("Deployment failed: {}", e));
                }
                let host_dur = host_start.elapsed();
                let h_mins = host_dur.as_secs() / 60;
                let h_secs = host_dur.as_secs() % 60;
                log_status!(log_target, "Deployment complete! ({}m {}s)", h_mins, h_secs);
                Ok(())
            });
            handles.push(handle);
        }

        for handle in handles {
            if let Err(e) = handle.await? {
                return Err(e.into());
            }
        }

        let duration = start_time.elapsed();
        let mins = duration.as_secs() / 60;
        let secs = duration.as_secs() % 60;
        println!("Batch deployment successfully completed in {}m {}s!", mins, secs);
        Ok(())
    }

    pub async fn switch_batch(hosts: Vec<RuntimeContext>, action: String, hm: bool) -> Result<(), Box<dyn std::error::Error>> {
        let start_time = std::time::Instant::now();

        // Ensure log directory exists
        if let Err(e) = std::fs::create_dir_all("_tmp") {
            return Err(format!("Failed to create log directory _tmp: {}", e).into());
        }

        let mut handles = vec![];

        for mut ctx in hosts {
            let host_name = ctx.hostname.clone();
            let action_clone = action.clone();
            let handle = task::spawn_blocking(move || -> Result<(), String> {
                let log_path = format!("_tmp/installer-rs-{}.log", host_name);
                let log_file = std::fs::File::create(&log_path)
                    .map_err(|e| format!("Failed to create log file {}: {}", log_path, e))?;

                let log_target = Arc::new(Mutex::new(crate::process::LogTarget::Batch {
                    prefix: host_name.clone(),
                    file: log_file,
                }));

                ctx.target_ip = crate::resolve_target_ip(&ctx, Arc::clone(&log_target));

                log_status!(log_target, "Starting switch...");
                if let Err(e) = switch::run_switch(&ctx, &action_clone, hm, Arc::clone(&log_target)) {
                    print_log_tail(&log_path, 20);
                    return Err(format!("Switch failed: {}", e));
                }
                log_status!(log_target, "Switch complete!");
                Ok(())
            });
            handles.push(handle);
        }

        for handle in handles {
            if let Err(e) = handle.await? {
                return Err(e.into());
            }
        }

        let duration = start_time.elapsed();
        let mins = duration.as_secs() / 60;
        let secs = duration.as_secs() % 60;
        println!("Batch switch successfully completed in {}m {}s!", mins, secs);
        Ok(())
    }
}
