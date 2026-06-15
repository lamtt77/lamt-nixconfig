use crate::process::{CommandExecutor, Logger};

pub fn reboot_target(target_ssh: &str, logger: Logger) {
	info!(logger, "Rebooting target system into the new production kernel...");
	let _ = CommandExecutor::execute_ssh(target_ssh, "sync && reboot -f", logger);
}
