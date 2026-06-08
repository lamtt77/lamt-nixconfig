use std::sync::Arc;
use std::time::Instant;
use tokio::task;

use crate::context::RuntimeContext;
use crate::fleet::resolution::resolve_target_ip;
use crate::process::Logger;
use crate::progress::color::{self, ColorMode};
use crate::remote::ssh::SshOutputMode;

pub async fn execute_command(
    targets: Vec<RuntimeContext>,
    command: Vec<String>,
    stream: bool,
    parallel: usize,
) -> Result<(), Box<dyn std::error::Error>> {
    if targets.is_empty() {
        return Err("No target hosts specified for execution".into());
    }

    let escaped_parts: Vec<String> = command
        .iter()
        .map(|arg| crate::process::shell_escape(arg))
        .collect();
    let remote_cmd_string = escaped_parts.join(" ");

    if targets.len() == 1 {
        let ctx = &targets[0];
        let target_ip = resolve_target_ip(ctx, Logger::silent());
        let session = crate::remote::ssh::SshSession::new(&ctx.username, &target_ip);
        let res = session.run(&remote_cmd_string, SshOutputMode::Interactive)?;
        if res.status.success() {
            return Ok(());
        } else {
            return Err(format!("Remote command failed with status: {}", res.status).into());
        }
    }

    let semaphore = if parallel > 0 {
        Some(Arc::new(tokio::sync::Semaphore::new(parallel)))
    } else {
        None
    };

    let mut handles = vec![];
    let cmd_str_arc = Arc::new(remote_cmd_string);

    for ctx in targets {
        let hostname = ctx.hostname.clone();
        let hostname_for_thread = hostname.clone();
        let username = ctx.username.clone();
        let cmd_str = cmd_str_arc.clone();

        let permit = if let Some(sem) = &semaphore {
            match sem.clone().acquire_owned().await {
                Ok(p) => Some(p),
                Err(_) => return Err("Failed to acquire concurrency permit".into()),
            }
        } else {
            None
        };

        let handle = task::spawn_blocking(move || -> Result<(), String> {
            let target_ip = resolve_target_ip(&ctx, Logger::silent());
            let session = crate::remote::ssh::SshSession::new(&username, &target_ip);

            let start = Instant::now();

            let mode = if stream {
                let colors = [
                    "31", "32", "33", "34", "35", "36", "91", "92", "93", "94", "95", "96",
                ];
                let hash = hostname_for_thread
                    .chars()
                    .map(|c| c as usize)
                    .sum::<usize>();
                let color_code = colors[hash % colors.len()];
                let prefix = color::colorize(
                    &format!("[{}]", hostname_for_thread),
                    color_code,
                    ColorMode::Auto,
                );
                SshOutputMode::ConsoleStreamed { prefix }
            } else {
                SshOutputMode::Buffered
            };

            let res = session
                .run(&cmd_str, mode)
                .map_err(|e| format!("Failed to run ssh command: {}", e))?;

            let status = res.status;
            let _ = permit;

            if !stream {
                let duration = start.elapsed();
                let status_str = if status.success() {
                    color::colorize("SUCCESS", color::GREEN, ColorMode::Auto)
                } else {
                    color::colorize("FAILED", color::RED, ColorMode::Auto)
                };

                let mut block = format!(
                    "--- Host: {} | Status: {} | Duration: {:.2?} ---\n",
                    hostname_for_thread, status_str, duration
                );
                if !res.stdout.is_empty() {
                    block.push_str(&String::from_utf8_lossy(&res.stdout));
                }
                if !res.stderr.is_empty() {
                    block.push_str(&String::from_utf8_lossy(&res.stderr));
                }
                block.push_str("--------------------------------------------------\n");
                println!("{}", block);
            }

            if status.success() {
                Ok(())
            } else {
                Err(format!("Exit status: {}", status))
            }
        });
        handles.push((hostname, handle));
    }

    let mut failed = vec![];
    for (host, handle) in handles {
        match handle.await {
            Ok(Ok(())) => {}
            Ok(Err(e)) => failed.push((host, e)),
            Err(e) => failed.push((host, format!("Task panicked: {}", e))),
        }
    }

    if !failed.is_empty() {
        let list: Vec<String> = failed
            .iter()
            .map(|(h, e)| format!("{}: {}", h, e))
            .collect();
        return Err(format!("Command execution failed on hosts:\n{}", list.join("\n")).into());
    }

    Ok(())
}
