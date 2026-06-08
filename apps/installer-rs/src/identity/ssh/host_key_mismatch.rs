use crate::context::RuntimeContext;
use crate::identity::sops::register_age_key_in_sops;
use crate::process::{CommandExecutor, Logger};
use std::fs;
use std::path::Path;

pub struct HostKeyMismatch<'a> {
    pub ctx: &'a RuntimeContext,
    pub ssh_target: &'a str,
    pub secrets_repo: &'a Path,
    pub local_key_file: &'a Path,
    pub local_pub_file: &'a Path,
    pub local_pub_key: &'a str,
    pub active_pub_key: &'a str,
}

pub fn resolve_host_key_mismatch(
    mismatch: HostKeyMismatch<'_>,
    logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
    crate::warn!(
        &logger,
        "Target host '{}' SSH key mismatch detected!",
        mismatch.ctx.hostname
    );
    crate::info!(
        &logger,
        "  Local key (in lamt-secrets): {}",
        mismatch.local_pub_key
    );
    crate::info!(
        &logger,
        "  Target key (active on host): {}",
        mismatch.active_pub_key
    );

    let choice = resolve_mismatch_choice(logger.clone());

    match choice.as_str() {
        "1" => overwrite_target_key(&mismatch, logger.clone())?,
        "2" => update_secrets_key(&mismatch, logger.clone())?,
        "3" => {
            crate::warn!(
                &logger,
                "Proceeding anyway. Secrets decryption may fail on target."
            );
        }
        _ => {
            return Err("Aborted by user due to SSH host key mismatch.".into());
        }
    }

    Ok(())
}

fn resolve_mismatch_choice(logger: Logger) -> String {
    let mut choice = "3".to_string();
    let runtime_options = crate::config::get_runtime_options();

    if !runtime_options.force {
        crate::info!(&logger, "How would you like to resolve this mismatch?");
        crate::info!(
            &logger,
            "  1) Overwrite target key to match secrets (Secrets -> Target)"
        );
        crate::info!(
            &logger,
            "  2) Update secrets to match target key (Target -> Secrets)"
        );
        crate::info!(&logger, "  3) Proceed anyway (decryption may fail)");
        crate::info!(&logger, "  4) Abort deployment");

        print!("  Choice [1/2/3/4]: ");
        use std::io::Write;
        let _ = std::io::stdout().flush();
        let mut input = String::new();
        if std::io::stdin().read_line(&mut input).is_ok() {
            let trimmed = input.trim();
            if ["1", "2", "3", "4"].contains(&trimmed) {
                choice = trimmed.to_string();
            } else {
                choice = "4".to_string();
            }
        } else {
            choice = "4".to_string();
        }
    } else {
        if runtime_options.update_host_key {
            choice = "1".to_string();
        }
        if runtime_options.update_secrets_key {
            choice = "2".to_string();
        }
        crate::info!(
            &logger,
            "Non-interactive mode active (CLI_FORCE=yes). Auto-selected choice: {}",
            choice
        );
    }

    choice
}

fn overwrite_target_key(
    mismatch: &HostKeyMismatch<'_>,
    logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
    crate::info!(
        &logger,
        "Updating SSH host key on target to match local key..."
    );
    let private_key = fs::read_to_string(mismatch.local_key_file)?;
    let public_key = fs::read_to_string(mismatch.local_pub_file)?;

    let stage_priv_cmd = "\
        sudo tee /etc/ssh/ssh_host_ed25519_key >/dev/null && \
        sudo chmod 600 /etc/ssh/ssh_host_ed25519_key";
    CommandExecutor::execute_ssh_with_stdin(
        mismatch.ssh_target,
        stage_priv_cmd,
        &private_key,
        logger.clone(),
    )?;

    let stage_pub_cmd = "\
        sudo tee /etc/ssh/ssh_host_ed25519_key.pub >/dev/null && \
        sudo chmod 644 /etc/ssh/ssh_host_ed25519_key.pub";
    CommandExecutor::execute_ssh_with_stdin(
        mismatch.ssh_target,
        stage_pub_cmd,
        &public_key,
        logger.clone(),
    )?;

    if target_has_distinct_persist_ssh_dir(mismatch.ssh_target)? {
        let stage_persist_priv_cmd = "\
            sudo mkdir -p /persist/etc/ssh && \
            sudo tee /persist/etc/ssh/ssh_host_ed25519_key >/dev/null && \
            sudo chmod 600 /persist/etc/ssh/ssh_host_ed25519_key";
        CommandExecutor::execute_ssh_with_stdin(
            mismatch.ssh_target,
            stage_persist_priv_cmd,
            &private_key,
            logger.clone(),
        )?;

        let stage_persist_pub_cmd = "\
            sudo tee /persist/etc/ssh/ssh_host_ed25519_key.pub >/dev/null && \
            sudo chmod 644 /persist/etc/ssh/ssh_host_ed25519_key.pub";
        CommandExecutor::execute_ssh_with_stdin(
            mismatch.ssh_target,
            stage_persist_pub_cmd,
            &public_key,
            logger.clone(),
        )?;
    }

    let reload_ssh_cmd = "sudo systemctl reload sshd || sudo systemctl restart ssh || true";
    CommandExecutor::execute_ssh(mismatch.ssh_target, reload_ssh_cmd, logger.clone())?;
    crate::info!(&logger, "Target host key updated successfully.");

    let _ = crate::remote::known_hosts::remove_known_host_keys(
        &mismatch.ctx.target_ip,
        &mismatch.ctx.hostname,
    );

    Ok(())
}

fn target_has_distinct_persist_ssh_dir(
    ssh_target: &str,
) -> Result<bool, Box<dyn std::error::Error>> {
    let has_persist_check = r#"
        if [ -d /persist/etc/ssh ] && [ "$(stat -c %i /persist/etc/ssh 2>/dev/null)" != "$(stat -c %i /etc/ssh 2>/dev/null)" ]; then
            echo 1
        else
            echo 0
        fi
    "#;
    let has_persist_out = CommandExecutor::execute_ssh(
        ssh_target,
        &format!("sudo bash -c '{}'", has_persist_check),
        Logger::silent(),
    )?;
    Ok(has_persist_out.trim() == "1")
}

fn update_secrets_key(
    mismatch: &HostKeyMismatch<'_>,
    logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
    crate::info!(
        &logger,
        "Updating secrets repository with target host key..."
    );
    let silent_log = Logger::silent();
    let private_key = CommandExecutor::execute_ssh(
        mismatch.ssh_target,
        "sudo cat /etc/ssh/ssh_host_ed25519_key",
        silent_log,
    )?;

    fs::write(mismatch.local_key_file, &private_key)?;
    fs::write(
        mismatch.local_pub_file,
        format!("{}\n", mismatch.active_pub_key),
    )?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(mismatch.local_key_file, fs::Permissions::from_mode(0o600))?;
        fs::set_permissions(mismatch.local_pub_file, fs::Permissions::from_mode(0o644))?;
    }

    register_age_key_in_sops(
        &mismatch.ctx.hostname,
        mismatch.active_pub_key,
        mismatch.secrets_repo,
        logger.clone(),
    )?;

    Ok(())
}
