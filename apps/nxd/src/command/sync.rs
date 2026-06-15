use crate::context::load_context_from_spec;
use crate::fleet::resolution::resolve_target_ip;
use crate::identity;
use crate::process::{CommandExecutor, Logger};
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
		let target_dir = crate::config::nix_cfg();
		let checkout_root = std::env::current_dir()?;

		CommandExecutor::execute_ssh(
			&target_dest,
			&format!("mkdir -p {}", target_dir),
			logger.clone(),
		)?;

		let mut ssh_options = crate::remote::ssh::SshOptions::rsync();
		if let Some(proxy) = crate::context::find_proxy_jump_for_ip(&ctx.target_ip) {
			ssh_options.proxy_jump = Some(proxy);
		}
		let source = format!("{}/", checkout_root.display());
		let destination = format!("{}:{}/", target_dest, target_dir);
		let rsync_shell = ssh_options.rsync_remote_shell();
		let mut rsync_args = vec!["-avh".to_string(), "--delete".to_string()];
		for pattern in crate::config::CHECKOUT_EXCLUDES {
			rsync_args.push(format!("--exclude={}", pattern));
		}
		rsync_args.push("-e".to_string());
		rsync_args.push(rsync_shell);
		rsync_args.push(source);
		rsync_args.push(destination);

		let args_ref: Vec<&str> = rsync_args.iter().map(|s| s.as_str()).collect();
		CommandExecutor::execute("rsync", &args_ref, logger.clone())?;

		println!("Repository codebase sync complete.");
	}

	Ok(())
}
