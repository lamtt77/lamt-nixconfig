use crate::context::load_context_from_spec;
use crate::fleet::resolution::{resolve_provider, resolve_target_ip};
use crate::process::Logger;

pub fn execute_info(target: &str, ip_only: bool) -> Result<(), Box<dyn std::error::Error>> {
	let mut ctx = load_context_from_spec(target)?;
	let logger = if ip_only { Logger::silent() } else { Logger::terminal() };

	ctx.target_ip = resolve_target_ip(&ctx, logger.clone());
	let provider = resolve_provider(&ctx, logger);

	if ip_only {
		println!("{}", ctx.target_ip);
	} else {
		println!("Hostname: {}", ctx.hostname);
		println!("Target IP: {}", ctx.target_ip);
		println!("System: {}", ctx.system);
		println!("Primary User: {}", ctx.username);
		println!("Low Memory: {}", ctx.deployment.low_mem);
		println!("VMID: {}", ctx.deployment.vmid);
		println!("Disk Size: {}", ctx.deployment.disk_size);
		if provider.is_some() {
			println!("Virtualization Provider: Yes");
		} else {
			println!("Virtualization Provider: No");
		}
	}
	Ok(())
}
