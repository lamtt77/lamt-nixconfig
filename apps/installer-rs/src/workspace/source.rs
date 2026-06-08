use crate::config;
use crate::context::RuntimeContext;
use crate::process::Logger;
use crate::workspace::local::{
    clean_workspace_except_git, ensure_git_repo_committed, sanitize_component, TempDirGuard,
};
use crate::workspace::remote::rsync_tree;
use crate::workspace::secrets::inject_host_secret;
use crate::workspace::HostWorkspace;
use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;

pub struct CommonSourceWorkspace {
    pub _guard: Arc<TempDirGuard>,
    pub root: PathBuf,
}

impl CommonSourceWorkspace {
    pub fn prepare(logger: Logger) -> Result<Self, Box<dyn std::error::Error>> {
        let flake_ref = config::flake_uri();
        let guard = Arc::new(TempDirGuard::new("base")?);

        info!(logger, "Preparing common source base from {}...", flake_ref);
        info!(
            logger,
            "Common source base workspace: {}",
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

        // Commit base to Git
        ensure_git_repo_committed(guard.path())?;

        Ok(Self {
            root: guard.path().to_path_buf(),
            _guard: guard,
        })
    }

    pub fn prepare_host_context(
        &self,
        ctx: &RuntimeContext,
        logger: Logger,
    ) -> Result<HostWorkspace, Box<dyn std::error::Error>> {
        let guard = TempDirGuard::new(&ctx.hostname)?;
        // Clean dest before copy
        clean_workspace_except_git(guard.path())?;

        rsync_tree(&self.root, guard.path())?;
        info!(
            logger,
            "Host workspace for {}: {}",
            ctx.hostname,
            guard.path().display()
        );

        inject_host_secret(ctx, guard.path(), logger.clone())?;

        // Commit host context to Git
        ensure_git_repo_committed(guard.path())?;

        let mut prepared = ctx.clone();
        prepared.workspace_root = Some(guard.path().to_path_buf());
        prepared.common_base_root = Some(self.root.clone());
        prepared.flake_ref = format!("git+file://{}", guard.path().display());
        prepared.remote_workspace_dir = Some(format!(
            "/tmp/installer-rs-workspace-{}",
            sanitize_component(&ctx.hostname)
        ));

        Ok(HostWorkspace {
            _base_guard: self._guard.clone(),
            _guard: guard,
            ctx: prepared,
        })
    }
}

pub fn is_git_checkout() -> bool {
    Command::new("git")
        .args(["rev-parse", "--is-inside-work-tree"])
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

pub fn snapshot_local_checkout(dest: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let tracked_files = dest.join(".tracked-files");
    let missing_files = dest.join(".missing-tracked-files");
    let tracked_files_arg = tracked_files.to_string_lossy().to_string();
    let missing_files_arg = missing_files.to_string_lossy().to_string();
    let dest_arg = dest.to_string_lossy().to_string();

    let script = r#"
        set -euo pipefail
        list="$1"
        missing="$2"
        dest="$3"

        : > "$missing"
        git ls-files -z > "$list"

        while IFS= read -r -d '' path; do
            if [ ! -e "$path" ]; then
                printf '%s\n' "$path" >> "$missing"
            fi
        done < "$list"

        if [ -s "$missing" ]; then
            exit 23
        fi

        rsync -a --from0 --files-from="$list" ./ "$dest"/
    "#;

    let status = Command::new("bash")
        .args([
            "-c",
            script,
            "bash",
            &tracked_files_arg,
            &missing_files_arg,
            &dest_arg,
        ])
        .status()?;

    if status.code() == Some(23) {
        let missing = fs::read_to_string(&missing_files).unwrap_or_default();
        let listed = missing
            .lines()
            .filter(|line| !line.trim().is_empty())
            .map(|line| format!("  {}", line))
            .collect::<Vec<_>>()
            .join("\n");
        return Err(format!(
            "Missing tracked files detected in the working tree. Stage or restore them before deploying:\n{}",
            listed
        )
        .into());
    }

    if !status.success() {
        return Err("Failed to snapshot tracked files from the local checkout.".into());
    }

    let _ = fs::remove_file(tracked_files);
    let _ = fs::remove_file(missing_files);
    Ok(())
}

pub fn snapshot_plain_checkout(dest: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let status = Command::new("rsync")
        .args([
            "-a",
            "--delete",
            "--exclude=.git",
            "--exclude=result",
            "--exclude=.DS_Store",
            "--exclude=target",
            "--exclude=apps/installer-rs/target",
            "--exclude=secrets",
            "./",
            &format!("{}/", dest.display()),
        ])
        .status()?;

    if !status.success() {
        return Err("Failed to snapshot files from the local checkout.".into());
    }

    Ok(())
}

pub fn materialize_flake_source(
    flake_ref: &str,
    dest: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let output = Command::new("nix")
        .args(["flake", "archive", "--json", flake_ref])
        .output()?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Failed to archive flake source {}: {}", flake_ref, stderr).into());
    }

    let json: Value = serde_json::from_slice(&output.stdout)?;
    let Some(source_path) = json.get("path").and_then(Value::as_str) else {
        return Err("nix flake archive did not return a source path.".into());
    };

    rsync_tree(Path::new(source_path), dest)?;
    Ok(())
}
