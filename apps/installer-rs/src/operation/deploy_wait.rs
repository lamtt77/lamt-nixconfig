use crate::process::{CommandExecutor, Logger};
use std::thread;
use std::time::Duration;

pub fn wait_for_ssh(
    target_ssh: &str,
    timeout_secs: u64,
    logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
    let interval = Duration::from_secs(5);
    let start = std::time::Instant::now();
    let timeout = Duration::from_secs(timeout_secs);

    info!(logger, "Waiting for SSH connection on {}...", target_ssh);

    if CommandExecutor::is_recording() {
        info!(
            logger,
            "SSH connection established successfully (Mock/Dry-Run)."
        );
        let _ = CommandExecutor::execute("ssh-probe", &[target_ssh], logger);
        return Ok(());
    }

    while start.elapsed() < timeout {
        match crate::remote::ssh::verify_ssh_connection(target_ssh, 3) {
            Ok(()) => {
                info!(logger, "SSH connection established successfully.");
                return Ok(());
            }
            Err(err) => {
                let clean_err = if err.contains("Connection refused") {
                    "Connection refused. Retrying...".to_string()
                } else if err.contains("Permission denied") {
                    "Permission denied. Retrying...".to_string()
                } else if err.contains("Operation timed out") {
                    "Operation timed out. Retrying...".to_string()
                } else if err.contains("banner exchange")
                    || err.contains("kex_exchange_identification")
                    || err.contains("Connection reset")
                {
                    "SSH handshake in progress. Retrying...".to_string()
                } else if err.is_empty() {
                    "Connection failed. Retrying...".to_string()
                } else {
                    format!("{}. Retrying...", err)
                };
                info!(logger, "{}", clean_err);
            }
        }

        thread::sleep(interval);
    }

    Err(format!(
        "Timed out waiting for SSH on {} after {} seconds",
        target_ssh, timeout_secs
    )
    .into())
}
