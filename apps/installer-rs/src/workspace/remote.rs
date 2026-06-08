use crate::process::{CommandExecutor, Logger};
use std::path::Path;

pub fn rsync_tree(source: &Path, dest: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let logger = Logger::silent();
    let args = [
        "-a",
        "--delete",
        "--exclude=.git",
        &format!("{}/", source.display()),
        &format!("{}/", dest.display()),
    ];
    CommandExecutor::execute("rsync", &args, logger)?;
    Ok(())
}

pub fn sync_workspace_to_remote(
    source: &Path,
    connection: &str,
    remote_dir: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let logger = Logger::silent();
    rsync_to_remote(
        source,
        connection,
        remote_dir,
        &["-a", "--delete"],
        &[],
        logger,
    )
}

pub fn sync_checkout_to_remote(
    source: &Path,
    connection: &str,
    remote_dir: &str,
    logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
    rsync_to_remote(
        source,
        connection,
        remote_dir,
        &["-avh", "--delete"],
        &[
            ".git",
            "result",
            ".DS_Store",
            "target",
            "apps/installer-rs/target",
            "secrets",
        ],
        logger,
    )
}

pub fn prepare_remote_builder_workspace(
    connection: &str,
    base_dir: &str,
    workspace_dir: &str,
    logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
    CommandExecutor::execute_ssh(
        connection,
        &remote_builder_prepare_command(base_dir, workspace_dir),
        logger,
    )?;
    Ok(())
}

fn remote_builder_prepare_command(base_dir: &str, workspace_dir: &str) -> String {
    format!(
        "mkdir -p {temp} && rsync -a --delete --exclude=.git {base}/ {temp}/",
        temp = workspace_dir,
        base = base_dir
    )
}

fn rsync_to_remote(
    source: &Path,
    connection: &str,
    remote_dir: &str,
    flags: &[&str],
    excludes: &[&str],
    logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
    let parts: Vec<&str> = connection.split('@').collect();
    let ip = if parts.len() == 2 {
        parts[1]
    } else {
        connection
    };
    let mut ssh_opts = crate::remote::ssh::SshOptions::rsync();
    if let Some(proxy) = crate::context::find_proxy_jump_for_ip(ip) {
        ssh_opts.proxy_jump = Some(proxy);
    }
    ensure_remote_dir(connection, remote_dir, &ssh_opts)?;

    let remote_target = format!("{}:{}/", connection, remote_dir);
    let rsync_ssh = ssh_opts.rsync_remote_shell();
    let source_path = format!("{}/", source.display());
    let mut args: Vec<String> = flags.iter().map(|flag| flag.to_string()).collect();
    args.extend(
        excludes
            .iter()
            .map(|pattern| format!("--exclude={}", pattern)),
    );
    args.push("-e".to_string());
    args.push(rsync_ssh);
    args.push(source_path);
    args.push(remote_target);

    let args_ref: Vec<&str> = args.iter().map(|arg| arg.as_str()).collect();
    CommandExecutor::execute("rsync", &args_ref, logger)?;

    Ok(())
}

fn ensure_remote_dir(
    connection: &str,
    remote_dir: &str,
    ssh_opts: &crate::remote::ssh::SshOptions,
) -> Result<(), Box<dyn std::error::Error>> {
    let logger = Logger::silent();
    let mut mkdir_args = ssh_opts.ssh_args_before_target();
    mkdir_args.push(connection.to_string());
    mkdir_args.push(format!("mkdir -p {}", remote_dir));

    let args_ref: Vec<&str> = mkdir_args.iter().map(|arg| arg.as_str()).collect();
    CommandExecutor::execute("ssh", &args_ref, logger)?;
    Ok(())
}

pub struct RemoteWorkspace {
    pub ssh_connection: String,
    pub path: String,
}

impl RemoteWorkspace {
    pub fn new(ssh_connection: String, path: String) -> Self {
        Self {
            ssh_connection,
            path,
        }
    }

    pub fn path(&self) -> &str {
        &self.path
    }

    pub fn prepare(
        &self,
        base_dir: &str,
        logger: Logger,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let prepare_remote_workspace = format!(
            "rm -rf {temp} && mkdir -p {temp} && rsync -a --delete {base}/ {temp}/",
            temp = self.path,
            base = base_dir
        );
        CommandExecutor::execute_ssh(&self.ssh_connection, &prepare_remote_workspace, logger)?;
        Ok(())
    }

    pub fn sync_local_secrets(
        &self,
        local_secrets_dir: &Path,
    ) -> Result<(), Box<dyn std::error::Error>> {
        sync_workspace_to_remote(
            local_secrets_dir,
            &self.ssh_connection,
            &format!("{}/secrets", self.path),
        )?;
        Ok(())
    }
}

impl Drop for RemoteWorkspace {
    fn drop(&mut self) {
        // Do not delete persistent remote workspaces to allow Nix evaluation/build caching!
    }
}

pub fn remote_git_snapshot_command(directory: &str) -> String {
    format!(
        "cd {} && \
         git init -q && \
         git config user.name \"Installer\" && \
         git config user.email \"installer@local\" && \
         git config commit.gpgsign false && \
         git add -A && \
         (git rev-parse --verify HEAD >/dev/null 2>&1 && \
          (git diff --cached --quiet || git commit -q -m \"workspace snapshot\") || \
          git commit -q -m \"workspace snapshot\")",
        directory
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_remote_builder_prepare_command() {
        assert_eq!(
            remote_builder_prepare_command("lamt-nixconfig", "/tmp/installer-rs-workspace-utils"),
            "mkdir -p /tmp/installer-rs-workspace-utils && rsync -a --delete --exclude=.git lamt-nixconfig/ /tmp/installer-rs-workspace-utils/"
        );
    }
}
