use crate::nix::build::{BuildOutput, BuildRequest};
use crate::nix::build_commands::{copy_target, remote_builder_build_command, target_ssh};
use crate::nix::build_local::build_locally_then_copy;
use crate::nix::eval::is_current_host_ssh_target;
use crate::nix::remote_builder::{get_builder_base_sync, get_builder_lock};
use crate::nix::NixBuilder;
use crate::process::{CommandExecutor, Logger};
use crate::workspace;
use std::sync::{Arc, Mutex};

pub fn build(
    builder: &NixBuilder,
    ssh_connection: &str,
    request: &BuildRequest,
    logger: Logger,
) -> Result<BuildOutput, Box<dyn std::error::Error>> {
    let target_ssh = target_ssh(builder);
    if is_current_host_ssh_target(ssh_connection) {
        crate::info!(
            logger.clone(),
            "Remote builder {} resolves to the current host; using local Nix build for {} ({})...",
            ssh_connection,
            builder.hostname,
            request.attr
        );
        return build_locally_then_copy(builder, request, &target_ssh, logger);
    }

    ensure_builder_base_synced(builder, ssh_connection, logger.clone())?;

    let remote_workspace_dir = builder.remote_workspace_dir().to_string();
    crate::info!(
        logger.clone(),
        "Builder host workspace for {}: {}",
        builder.hostname,
        remote_workspace_dir
    );
    workspace::prepare_remote_builder_workspace(
        ssh_connection,
        builder.builder_base_dir(),
        &remote_workspace_dir,
        logger.clone(),
    )?;

    let local_secrets_dir = builder
        .workspace_root()
        .map(|root| root.join("secrets"))
        .filter(|path| path.exists());
    if let Some(secrets_dir) = local_secrets_dir.as_deref() {
        workspace::sync_workspace_to_remote(
            secrets_dir,
            ssh_connection,
            &format!("{}/secrets", remote_workspace_dir),
        )?;
    }

    let commit_cmd = crate::workspace::remote_git_snapshot_command(&remote_workspace_dir);
    CommandExecutor::execute_ssh(ssh_connection, &commit_cmd, logger.clone())?;

    crate::info!(
        logger.clone(),
        "Delegating Nix build for {} ({}) to remote builder {}...",
        builder.hostname,
        request.attr,
        ssh_connection
    );
    let build_cmd =
        remote_builder_build_command(&remote_workspace_dir, &builder.target_attr(&request.attr));
    let out = CommandExecutor::execute_ssh(ssh_connection, &build_cmd, logger.clone())?;
    let store_path = out.trim().to_string();

    crate::info!(
        logger.clone(),
        "Copying store path from builder to target..."
    );
    let copy_target = copy_target(&target_ssh, request.mount_point.as_deref());
    let copy_cmd = builder.nix_copy_command_with_log(&copy_target, &store_path, logger.clone());
    CommandExecutor::execute_ssh(ssh_connection, &copy_cmd, logger)?;

    Ok(BuildOutput { store_path })
}

fn ensure_builder_base_synced(
    builder: &NixBuilder,
    ssh_connection: &str,
    logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut synced = false;
    let builder_lock_arc;
    let mut base_sync_lock_guard = None;

    builder_lock_arc = if let Some(ref state) = builder.run_state {
        let synced_set = state.synced_builders.lock().unwrap();
        if synced_set.contains(ssh_connection) {
            synced = true;
            None
        } else {
            std::mem::drop(synced_set);

            let mut locks = state.builder_sync_locks.lock().unwrap();
            let builder_lock = locks
                .entry(ssh_connection.to_string())
                .or_insert_with(|| Arc::new(Mutex::new(())))
                .clone();
            std::mem::drop(locks);
            Some(builder_lock)
        }
    } else {
        let builder_lock = get_builder_lock(ssh_connection);
        Some(builder_lock)
    };

    if let Some(ref lock) = builder_lock_arc {
        let guard = lock.lock().unwrap();
        if let Some(ref state) = builder.run_state {
            let synced_set = state.synced_builders.lock().unwrap();
            if synced_set.contains(ssh_connection) {
                synced = true;
            } else {
                base_sync_lock_guard = Some(guard);
            }
        } else {
            let builder_base_sync =
                get_builder_base_sync(ssh_connection, builder.builder_base_dir());
            let synced_bool = builder_base_sync.lock().unwrap();
            if *synced_bool {
                synced = true;
            } else {
                base_sync_lock_guard = Some(guard);
            }
        }
    }

    if !synced {
        crate::info!(
            logger.clone(),
            "Syncing common source base to remote builder {}...",
            ssh_connection
        );
        crate::info!(
            logger.clone(),
            "Remote builder base workspace: {}",
            builder.builder_base_dir()
        );
        if let Some(common_base_root) = builder.common_base_root() {
            workspace::sync_workspace_to_remote(
                common_base_root,
                ssh_connection,
                builder.builder_base_dir(),
            )?;
        }

        if let Some(ref state) = builder.run_state {
            let mut synced_set = state.synced_builders.lock().unwrap();
            synced_set.insert(ssh_connection.to_string());
        } else {
            let builder_base_sync =
                get_builder_base_sync(ssh_connection, builder.builder_base_dir());
            *builder_base_sync.lock().unwrap() = true;
        }
        crate::info!(
            logger.clone(),
            "Common source base sync to builder complete."
        );
    } else {
        crate::info!(
            logger.clone(),
            "Common source base already synced to remote builder {}; reusing {}.",
            ssh_connection,
            builder.builder_base_dir()
        );
    }

    std::mem::drop(base_sync_lock_guard);
    Ok(())
}
