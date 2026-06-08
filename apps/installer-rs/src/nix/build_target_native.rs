use crate::nix::build::{BuildOutput, BuildRequest};
use crate::nix::build_commands::{target_native_build_command, target_ssh};
use crate::nix::NixBuilder;
use crate::process::{CommandExecutor, Logger};
use crate::workspace;

pub fn build(
    builder: &NixBuilder,
    request: &BuildRequest,
    logger: Logger,
) -> Result<BuildOutput, Box<dyn std::error::Error>> {
    let target_ssh = target_ssh(builder);

    if let Some(workspace_root) = builder.workspace_root() {
        crate::info!(
            logger.clone(),
            "Target host workspace for {}: {}",
            builder.hostname,
            builder.remote_workspace_dir()
        );
        crate::info!(
            logger.clone(),
            "Syncing prepared workspace to target {}...",
            builder.target_ip
        );
        workspace::sync_workspace_to_remote(
            workspace_root,
            &target_ssh,
            builder.remote_workspace_dir(),
        )?;
        crate::info!(
            logger.clone(),
            "Prepared workspace sync to target complete."
        );
    }

    let commit_cmd = crate::workspace::remote_git_snapshot_command(builder.remote_workspace_dir());
    CommandExecutor::execute_ssh(&target_ssh, &commit_cmd, logger.clone())?;

    crate::info!(
        logger.clone(),
        "Executing native Nix build directly on target {} ({})...",
        builder.hostname,
        request.attr
    );
    let build_cmd = target_native_build_command(
        builder.remote_workspace_dir(),
        &builder.target_attr(&request.attr),
        request.mount_point.as_deref(),
    );

    let out = CommandExecutor::execute_ssh(&target_ssh, &build_cmd, logger)?;
    Ok(BuildOutput {
        store_path: out.trim().to_string(),
    })
}
