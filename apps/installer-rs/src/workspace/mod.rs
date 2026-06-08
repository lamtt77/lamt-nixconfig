pub mod local;
pub mod remote;
pub mod secrets;
pub mod source;

pub use local::clean_legacy_workspaces;
pub use remote::RemoteWorkspace;
pub use remote::{
    prepare_remote_builder_workspace, remote_git_snapshot_command, rsync_tree,
    sync_checkout_to_remote, sync_workspace_to_remote,
};
pub use source::CommonSourceWorkspace;

use crate::config;
use crate::context::RuntimeContext;
use crate::plan::WorkspaceMode;
use crate::process::Logger;
use local::{
    clean_workspace_except_git, ensure_git_repo_committed, sanitize_component, TempDirGuard,
};
use secrets::inject_host_secret;
use source::{
    is_git_checkout, materialize_flake_source, snapshot_local_checkout, snapshot_plain_checkout,
};

use std::sync::Arc;

pub struct HostWorkspace {
    pub _base_guard: Arc<TempDirGuard>,
    pub _guard: TempDirGuard,
    pub ctx: RuntimeContext,
}

impl HostWorkspace {
    pub fn context(&self) -> &RuntimeContext {
        &self.ctx
    }

    pub fn context_mut(&mut self) -> &mut RuntimeContext {
        &mut self.ctx
    }

    pub fn refresh_host_secret(&self, logger: Logger) -> Result<(), Box<dyn std::error::Error>> {
        inject_host_secret(&self.ctx, self._guard.path(), logger)?;
        ensure_git_repo_committed(self._guard.path())?;
        Ok(())
    }
}

pub fn prepare_single_host_workspace(
    ctx: &RuntimeContext,
    logger: Logger,
) -> Result<HostWorkspace, Box<dyn std::error::Error>> {
    let flake_ref = config::flake_uri();
    let base_guard = Arc::new(TempDirGuard::new("single-base")?);
    let guard = TempDirGuard::new(&ctx.hostname)?;

    info!(
        logger,
        "Preparing single-host workspace from {}...", flake_ref
    );
    info!(
        logger,
        "Host workspace for {}: {}",
        ctx.hostname,
        guard.path().display()
    );

    // Clean dest before copy
    clean_workspace_except_git(guard.path())?;

    if config::is_local_flake_ref(&flake_ref) {
        if is_git_checkout() {
            snapshot_local_checkout(guard.path())?;
        } else {
            info!(
                logger,
                "Local source is not a Git checkout; snapshotting checkout files with excludes."
            );
            snapshot_plain_checkout(guard.path())?;
        }
    } else {
        materialize_flake_source(&flake_ref, guard.path())?;
    }

    inject_host_secret(ctx, guard.path(), logger.clone())?;

    // Commit changes to Git in the workspace
    ensure_git_repo_committed(guard.path())?;

    let mut prepared = ctx.clone();
    prepared.workspace_root = Some(guard.path().to_path_buf());
    prepared.common_base_root = Some(guard.path().to_path_buf());
    prepared.flake_ref = format!("git+file://{}", guard.path().display());
    prepared.remote_workspace_dir = Some(format!(
        "/tmp/installer-rs-workspace-{}",
        sanitize_component(&ctx.hostname)
    ));

    Ok(HostWorkspace {
        _base_guard: base_guard,
        _guard: guard,
        ctx: prepared,
    })
}

pub fn prepare_workspace_for_context(
    ctx: &RuntimeContext,
    mode: WorkspaceMode,
    logger: Logger,
) -> Result<HostWorkspace, Box<dyn std::error::Error>> {
    match mode {
        WorkspaceMode::SingleHost => prepare_single_host_workspace(ctx, logger),
        WorkspaceMode::CommonBasePerHost => {
            let common_workspace = CommonSourceWorkspace::prepare(logger.clone())?;
            common_workspace.prepare_host_context(ctx, logger)
        }
    }
}
