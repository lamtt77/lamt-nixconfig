use crate::nix::NixBuilder;
use crate::nix::build::{BuildOutput, BuildRequest};
use crate::nix::build_commands::{
	copy_target, execute_copy_with_wsl_retry, flake_target_attr, target_realise_command, target_ssh,
	target_ssh_for_ip,
};
use crate::nix::eval::get_local_nix_lock;
use crate::process::{CommandExecutor, Logger};

pub fn build(
	builder: &NixBuilder,
	request: &BuildRequest,
	logger: Logger,
) -> Result<BuildOutput, Box<dyn std::error::Error>> {
	let target_ssh = target_ssh(builder);
	let target_attr = flake_target_attr(builder, &request.attr);
	let local_guard = get_local_nix_lock().lock().unwrap();
	crate::info!(
		logger.clone(),
		"Executing remote instantiation for {} ({})...",
		builder.hostname,
		request.attr
	);

	let mut args = vec!["path-info", "--derivation", &target_attr];
	let token_args = crate::config::nix_token_args();
	let token_args_ref: Vec<&str> = token_args.iter().map(|s| s.as_str()).collect();
	args.extend(token_args_ref.iter());

	let extra_args = crate::nix::build_commands::override_input_args(builder);
	let extra_args_ref: Vec<&str> = extra_args.iter().map(|s| s.as_str()).collect();
	args.extend(extra_args_ref.iter());

	let drv_out = CommandExecutor::execute("nix", &args, logger.clone())?;
	let drv_path = drv_out.trim().to_string();

	crate::info!(logger.clone(), "Copying derivation and inputs to target...");
	execute_copy_with_wsl_retry(builder, logger.clone(), |refreshed_ip| {
		let refreshed_target =
			refreshed_ip.map(|ip| target_ssh_for_ip(builder, ip)).unwrap_or_else(|| target_ssh.clone());
		let copy_target = copy_target(builder, &refreshed_target, request.mount_point.as_deref());
		let copy_args = builder.nix_copy_args_with_log(&copy_target, &drv_path, logger.clone());
		CommandExecutor::execute("nix", &copy_args, logger.clone())
	})?;

	std::mem::drop(local_guard);

	let realise_cmd =
		target_realise_command(&drv_path, request.mount_point.as_deref(), builder.low_mem);
	let out = CommandExecutor::execute_ssh(&target_ssh, &realise_cmd, logger)?;
	Ok(BuildOutput { store_path: out.trim().to_string() })
}
