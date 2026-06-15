use std::process::Command;

use crate::process::{CommandExecutor, Logger};

/// Clean local known_hosts file of entries matching the IP and hostname
pub fn remove_known_host_keys(ip: &str, hostname: &str) -> Result<(), Box<dyn std::error::Error>> {
	let _ = Command::new("ssh-keygen").args(["-R", ip]).output();
	let _ = Command::new("ssh-keygen").args(["-R", hostname]).output();
	Ok(())
}

pub fn trusted_entries(host: &str) -> Result<String, Box<dyn std::error::Error>> {
	let output =
		CommandExecutor::execute("ssh-keygen", &["-F", host], Logger::silent()).map_err(|error| {
			format!(
				"Windows host '{}' is not available from the orchestrator known_hosts file: {}",
				host, error
			)
		})?;
	let entries = output
		.lines()
		.filter(|line| !line.trim().is_empty() && !line.starts_with('#'))
		.collect::<Vec<_>>()
		.join("\n");
	if entries.is_empty() {
		return Err(
			format!(
				"Windows host '{}' has no trusted known_hosts entry; establish the strict control-plane SSH connection first",
				host
			)
			.into(),
		);
	}
	Ok(format!("{}\n", entries))
}
