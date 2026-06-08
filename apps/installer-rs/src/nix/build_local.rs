use crate::nix::build::{BuildOutput, BuildRequest};
use crate::nix::build_commands::{copy_target, flake_target_attr, target_ssh};
use crate::nix::eval::get_local_nix_lock;
use crate::nix::NixBuilder;
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
    let args = ["build", "--print-out-paths", "--no-link", &target_attr];
    let out = CommandExecutor::execute("nix", &args, logger.clone())?;
    let store_path = out.trim().to_string();

    crate::info!(
        logger.clone(),
        "Transferring compiled store path to target..."
    );
    let copy_target = copy_target(target_ssh, request.mount_point.as_deref());
    let copy_args = builder.nix_copy_args_with_log(&copy_target, &store_path, logger.clone());
    CommandExecutor::execute("nix", &copy_args, logger)?;

    Ok(BuildOutput { store_path })
}
