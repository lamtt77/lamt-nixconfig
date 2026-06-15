use crate::nix::NixBuilder;
use crate::nix::build::{BuildOutput, BuildRequest};
use crate::nix::build_commands::{
	copy_target, execute_copy_with_wsl_retry, flake_target_attr, target_ssh, target_ssh_for_ip,
};
use crate::nix::eval::get_local_nix_lock;
use crate::process::{CommandExecutor, Logger};

pub fn build(
	builder: &NixBuilder,
	request: &BuildRequest,
	logger: Logger,
) -> Result<BuildOutput, Box<dyn std::error::Error>> {
	let target_ssh = target_ssh(builder);
	build_locally_then_copy(builder, request, &target_ssh, logger)
}

pub fn build_locally_then_copy(
	builder: &NixBuilder,
	request: &BuildRequest,
	target_ssh: &str,
	logger: Logger,
) -> Result<BuildOutput, Box<dyn std::error::Error>> {
	let _local_guard = get_local_nix_lock().lock().unwrap();
	crate::info!(
		logger.clone(),
		"Executing local Nix build for {} ({})...",
		builder.hostname,
		request.attr
	);
	let target_attr = flake_target_attr(builder, &request.attr);
	let mut args = vec!["build", "--print-out-paths", "--no-link", &target_attr];
	let token_args = crate::config::nix_token_args();
	let token_args_ref: Vec<&str> = token_args.iter().map(|s| s.as_str()).collect();
	args.extend(token_args_ref.iter());

	let extra_args = crate::nix::build_commands::override_input_args(builder);
	let extra_args_ref: Vec<&str> = extra_args.iter().map(|s| s.as_str()).collect();
	args.extend(extra_args_ref.iter());

	let out = CommandExecutor::execute("nix", &args, logger.clone())?;
	let store_path = out.trim().to_string();

	if !crate::nix::eval::is_current_host_ssh_target(target_ssh) {
		crate::info!(logger.clone(), "Transferring compiled store path to target...");
		execute_copy_with_wsl_retry(builder, logger.clone(), |refreshed_ip| {
			let refreshed_target = refreshed_ip
				.map(|ip| target_ssh_for_ip(builder, ip))
				.unwrap_or_else(|| target_ssh.to_string());
			let copy_target = copy_target(builder, &refreshed_target, request.mount_point.as_deref());
			let copy_args = builder.nix_copy_args_with_log(&copy_target, &store_path, logger.clone());
			CommandExecutor::execute("nix", &copy_args, logger.clone())
		})?;
	}

	Ok(BuildOutput { store_path })
}
