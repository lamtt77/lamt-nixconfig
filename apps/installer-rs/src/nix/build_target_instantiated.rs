use crate::nix::build::{BuildOutput, BuildRequest};
use crate::nix::build_commands::{
    copy_target, flake_target_attr, target_realise_command, target_ssh,
};
use crate::nix::eval::get_local_nix_lock;
use crate::nix::NixBuilder;
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

    let args = ["path-info", "--derivation", &target_attr];
    let drv_out = CommandExecutor::execute("nix", &args, logger.clone())?;
    let drv_path = drv_out.trim().to_string();

    crate::info!(logger.clone(), "Copying derivation and inputs to target...");
    let copy_target = copy_target(&target_ssh, request.mount_point.as_deref());
    let copy_args = builder.nix_copy_args_with_log(&copy_target, &drv_path, logger.clone());
    CommandExecutor::execute("nix", &copy_args, logger.clone())?;

    std::mem::drop(local_guard);

    let realise_cmd =
        target_realise_command(&drv_path, request.mount_point.as_deref(), builder.low_mem);
    let out = CommandExecutor::execute_ssh(&target_ssh, &realise_cmd, logger)?;
    Ok(BuildOutput {
        store_path: out.trim().to_string(),
    })
}
