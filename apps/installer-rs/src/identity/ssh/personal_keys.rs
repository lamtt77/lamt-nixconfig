use crate::context::RuntimeContext;
use crate::process::{CommandExecutor, Logger};
use std::env;
use std::path::Path;

/// Syncs user's personal SSH keys from local ~/.ssh to the target.
/// This is restricted to manual execution ONLY.
pub fn sync_personal_keys(
    logger: &Logger,
    ctx: &RuntimeContext,
    mount_path: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let is_deploy = crate::config::get_runtime_options().deploy_active;
    let target_user = if is_deploy { "root" } else { &ctx.username };
    let ssh_target = format!("{}@{}", target_user, ctx.target_ip);

    let home = env::var("HOME")?;
    let local_user_ssh = Path::new(&home).join(".ssh");
    if local_user_ssh.exists() {
        crate::info!(
            logger,
            "Syncing user's personal SSH keys from {} to target...",
            local_user_ssh.display()
        );

        let target_user_ssh = if ctx.username == "root" {
            mount_path.join("root/.ssh")
        } else {
            mount_path.join("home").join(&ctx.username).join(".ssh")
        };

        let target_persist_ssh = if ctx.username == "root" {
            mount_path.join("persist/root/.ssh")
        } else {
            mount_path
                .join("persist/home")
                .join(&ctx.username)
                .join(".ssh")
        };

        let local_ssh_str = local_user_ssh.to_string_lossy().to_string();
        let target_ssh_str = target_user_ssh.to_string_lossy().to_string();
        let persist_check_str = mount_path.join("persist").to_string_lossy().to_string();
        let target_persist_ssh_str = target_persist_ssh.to_string_lossy().to_string();

        let tar_cmd = format!(
            "tar --exclude=\"config\" --exclude=\"environment\" --exclude=\"known_hosts*\" -czf - -C {} .",
            local_ssh_str
        );

        let owner_cmd = if is_deploy {
            let owner = if ctx.username == "root" {
                "0:0"
            } else {
                "1000:100"
            };
            format!(
                " && chown -R {owner} {dir} && if [ -d {persist} ]; then chown -R {owner} {persist}; fi",
                owner = owner,
                dir = target_ssh_str,
                persist = target_persist_ssh_str
            )
        } else {
            "".to_string()
        };

        let untar_cmd = format!(
            "mkdir -p {} && tar -xzf - -C {} && \
             if [ -d {} ]; then \
                 mkdir -p {} && cp -r {}/. {}/; \
             fi && \
             chmod 700 {} && find {} -type f -exec chmod 600 {{}} + && \
             if [ -d {} ]; then \
                 chmod 700 {} && find {} -type f -exec chmod 600 {{}} +; \
             fi{}",
            target_ssh_str,
            target_ssh_str,
            persist_check_str,
            target_persist_ssh_str,
            target_ssh_str,
            target_persist_ssh_str,
            target_ssh_str,
            target_ssh_str,
            persist_check_str,
            target_persist_ssh_str,
            target_persist_ssh_str,
            owner_cmd
        );

        let pipe_cmd = format!(
            "{} | {} {} \"{}\"",
            tar_cmd,
            crate::remote::ssh::SshOptions::identity_sync().ssh_command_for_shell_pipeline(),
            ssh_target,
            untar_cmd
        );

        CommandExecutor::execute("bash", &["-c", &pipe_cmd], logger.clone())?;
        crate::info!(logger, "User's personal SSH keys synced successfully.");
    } else {
        crate::info!(
            logger,
            "Local user SSH directory not found at {}. Skipping user SSH sync.",
            local_user_ssh.display()
        );
    }

    Ok(())
}
