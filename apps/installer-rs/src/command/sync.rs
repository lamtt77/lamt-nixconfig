use crate::context::load_context_from_spec;
use crate::fleet::resolution::resolve_target_ip;
use crate::identity;
use crate::process::Logger;
use crate::workspace;
use std::path::Path;

pub fn execute_sync(
    target: &str,
    keys: bool,
    repo: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut ctx = load_context_from_spec(target)?;
    let logger = Logger::terminal();
    ctx.target_ip = resolve_target_ip(&ctx, logger.clone());

    if keys {
        println!("Syncing SSH and GPG keys to target {}...", target);
        // Validate and sync target host key
        identity::ssh::validate_and_sync_target_host_key(&ctx, logger.clone())?;

        let ssh_service = identity::ssh::SshKeyService::new(logger.clone());
        let gpg_service = identity::gpg::GpgService::new(logger.clone());

        ssh_service.sync_personal_keys(&ctx, Path::new("/"))?;
        gpg_service.sync_gpg_credentials(&ctx, Path::new("/"))?;
        println!("Credentials sync complete.");
    }

    if repo {
        println!("Syncing codebase repository to target {}...", target);
        let target_dest = format!("{}@{}", ctx.username, ctx.target_ip);
        let target_dir = ctx
            .remote_workspace_dir
            .as_deref()
            .unwrap_or(crate::config::DEFAULT_NIX_CFG);
        let checkout_root = std::env::current_dir()?;

        workspace::sync_checkout_to_remote(
            &checkout_root,
            &target_dest,
            target_dir,
            logger.clone(),
        )?;

        println!("Repository codebase sync complete.");
    }

    Ok(())
}
