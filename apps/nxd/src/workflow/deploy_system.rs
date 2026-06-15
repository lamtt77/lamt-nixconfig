use crate::nix::NixBuilder;
use crate::process::Logger;

pub fn build_system(
	builder: &NixBuilder,
	logger: Logger,
) -> Result<String, Box<dyn std::error::Error>> {
	info!(logger, "Building/realizing target system configuration (toplevel)...");
	let system_path = builder.build_system(Some("/mnt"), logger.clone())?;
	info!(logger, "System toplevel path: {}", system_path);
	Ok(system_path)
}
