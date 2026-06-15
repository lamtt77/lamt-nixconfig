use crate::nix::NixBuilder;
use crate::nix::build::{BuildOutput, BuildRequest};
use crate::nix::build_commands::{
	copy_target, execute_copy_with_wsl_retry, remote_builder_build_command, target_ssh,
	target_ssh_for_ip, verify_wsl_route_from_builder,
};
use crate::nix::build_local::build_locally_then_copy;
use crate::nix::eval::{is_builder_target_host, is_current_host_ssh_target};
use crate::process::{CommandExecutor, Logger};

pub fn build(
	builder: &NixBuilder,
	ssh_connection: &str,
	request: &BuildRequest,
	logger: Logger,
) -> Result<BuildOutput, Box<dyn std::error::Error>> {
	let target_ssh = target_ssh(builder);

	if builder.source_store_path.is_some() {
		if is_current_host_ssh_target(ssh_connection) {
			crate::info!(
				logger.clone(),
				"Remote builder {} resolves to the current host; building locally...",
				ssh_connection
			);
			return build_locally_then_copy(builder, request, &target_ssh, logger);
		}

		crate::info!(
			logger.clone(),
			"Delegating store-backed Nix build for {} ({}) to remote builder {}...",
			builder.hostname,
			request.attr,
			ssh_connection
		);
		let t_nix_build = std::time::Instant::now();
		let build_cmd = remote_builder_build_command(builder, &request.attr);
		let out = CommandExecutor::execute_ssh(ssh_connection, &build_cmd, logger.clone())?;
		let store_path = out.trim().to_string();
		crate::debug!(logger.clone(), "Remote Nix build completed in {:?}", t_nix_build.elapsed());

		if is_builder_target_host(ssh_connection, &builder.hostname, &builder.target_ip) {
			crate::info!(
				logger.clone(),
				"Remote builder matches target; skipping redundant store path copy."
			);
		} else {
			crate::info!(logger.clone(), "Copying store path from builder to target...");
			let t_copy = std::time::Instant::now();
			execute_copy_with_wsl_retry(builder, logger.clone(), |refreshed_ip| {
				let copy_ip = refreshed_ip.unwrap_or(&builder.target_ip);
				verify_wsl_route_from_builder(builder, ssh_connection, copy_ip)?;
				let refreshed_target = target_ssh_for_ip(builder, copy_ip);
				let copy_target = copy_target(builder, &refreshed_target, request.mount_point.as_deref());
				let copy_cmd = builder.nix_copy_command_with_log(&copy_target, &store_path, logger.clone());
				CommandExecutor::execute_ssh(ssh_connection, &copy_cmd, logger.clone())
			})?;
			crate::debug!(
				logger.clone(),
				"Store path copied from builder to target in {:?}",
				t_copy.elapsed()
			);
		}

		return Ok(BuildOutput { store_path });
	}

	Err("Non-store-backed builds are no longer supported".into())
}
