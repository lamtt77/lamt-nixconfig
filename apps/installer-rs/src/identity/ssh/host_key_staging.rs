use crate::context::RuntimeContext;
use crate::process::{CommandExecutor, Logger};
use std::fs;
use std::path::Path;

pub fn stage_target_host_keys(
    logger: &Logger,
    ctx: &RuntimeContext,
    mount_path: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let is_deploy = crate::config::get_runtime_options().deploy_active;
    let target_user = if is_deploy { "root" } else { &ctx.username };
    let ssh_target = format!("{}@{}", target_user, ctx.target_ip);
    let secrets_repo = crate::config::get_secrets_repo();

    let local_key_path = secrets_repo
        .join("hosts")
        .join(&ctx.hostname)
        .join("ssh_host_ed25519_key");
    let local_pub_path = local_key_path.with_extension("pub");

    if is_deploy && local_key_path.exists() {
        crate::info!(
            logger,
            "Zero-Trust: Staging pre-generated target host SSH key pair..."
        );

        let target_ssh_dir = mount_path.join("etc/ssh");
        let target_ssh_file = target_ssh_dir.join("ssh_host_ed25519_key");
        let target_ssh_file_str = target_ssh_file.to_string_lossy().to_string();

        let persist_ssh_dir = mount_path.join("persist/etc/ssh");
        let persist_ssh_file = persist_ssh_dir.join("ssh_host_ed25519_key");
        let persist_ssh_file_str = persist_ssh_file.to_string_lossy().to_string();
        let persist_check_str = mount_path.join("persist").to_string_lossy().to_string();

        let stage_key_script = format!(
            "tee /tmp/ssh_key_tmp >/dev/null && \
             mkdir -p {} && cp /tmp/ssh_key_tmp {} && chmod 600 {} && \
             if [ -d {} ]; then \
                 mkdir -p {} && cp /tmp/ssh_key_tmp {} && chmod 600 {}; \
             fi && \
             rm -f /tmp/ssh_key_tmp",
            target_ssh_dir.to_string_lossy(),
            target_ssh_file_str,
            target_ssh_file_str,
            persist_check_str,
            persist_ssh_dir.to_string_lossy(),
            persist_ssh_file_str,
            persist_ssh_file_str
        );

        let private_key = fs::read_to_string(&local_key_path)?;
        CommandExecutor::execute_ssh_with_stdin(
            &ssh_target,
            &stage_key_script,
            &private_key,
            logger.clone(),
        )?;

        if local_pub_path.exists() {
            let target_pub_file = target_ssh_dir.join("ssh_host_ed25519_key.pub");
            let target_pub_file_str = target_pub_file.to_string_lossy().to_string();
            let persist_pub_file = persist_ssh_dir.join("ssh_host_ed25519_key.pub");
            let persist_pub_file_str = persist_pub_file.to_string_lossy().to_string();

            let stage_pub_script = format!(
                "tee /tmp/ssh_pub_tmp >/dev/null && \
                 mkdir -p {} && cp /tmp/ssh_pub_tmp {} && chmod 644 {} && \
                 if [ -d {} ]; then \
                     mkdir -p {} && cp /tmp/ssh_pub_tmp {} && chmod 644 {}; \
                 fi && \
                 rm -f /tmp/ssh_pub_tmp",
                target_ssh_dir.to_string_lossy(),
                target_pub_file_str,
                target_pub_file_str,
                persist_check_str,
                persist_ssh_dir.to_string_lossy(),
                persist_pub_file_str,
                persist_pub_file_str
            );

            let public_key = fs::read_to_string(&local_pub_path)?;
            CommandExecutor::execute_ssh_with_stdin(
                &ssh_target,
                &stage_pub_script,
                &public_key,
                logger.clone(),
            )?;
        }

        crate::info!(logger, "Target host SSH key staged successfully.");
    } else if !is_deploy {
        crate::info!(
            logger,
            "Target is already deployed. Skipping target host SSH key pair staging."
        );
    } else {
        crate::info!(
            logger,
            "No pre-generated local SSH host key found at {}. Skipping host key staging.",
            local_key_path.display()
        );
    }

    Ok(())
}
