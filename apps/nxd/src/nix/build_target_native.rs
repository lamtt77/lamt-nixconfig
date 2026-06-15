use crate::nix::NixBuilder;
use crate::nix::build::{BuildOutput, BuildRequest};
use crate::nix::build_commands::{target_native_build_command, target_ssh};
use crate::process::{CommandExecutor, Logger};

pub fn build(
	builder: &NixBuilder,
	request: &BuildRequest,
	logger: Logger,
) -> Result<BuildOutput, Box<dyn std::error::Error>> {
	let target_ssh = target_ssh(builder);

	if builder.source_store_path.is_some() {
		crate::info!(
			logger.clone(),
			"Executing store-backed native Nix build directly on target {} ({})...",
			builder.hostname,
			request.attr
		);

		let build_cmd =
			target_native_build_command(builder, &request.attr, request.mount_point.as_deref());

		let out = CommandExecutor::execute_ssh(&target_ssh, &build_cmd, logger)?;
		return Ok(BuildOutput { store_path: out.trim().to_string() });
	}

	Err("Non-store-backed builds are no longer supported".into())
}
