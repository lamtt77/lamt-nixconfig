use crate::config;
use crate::context::RuntimeContext;
use crate::nix::NixBuilder;
use crate::planning;
use crate::process::{CommandExecutor, Logger};
use crate::providers::{ProviderState, TargetEndpoint};
use crate::workflow::deploy::{self, DeploymentMode};
use crate::workspace::HostWorkspace;

use std::thread;
use std::time::Duration;

#[derive(Clone)]
pub struct HostExecutionContext {
	pub logger: Logger,
	pub redeploy: bool,
	pub overwrite: bool,
	pub switch_action: Option<String>,
	pub home_manager: bool,
}

/// Executes the full switch or deploy lifecycle for a single host.
pub fn execute_host_operation(
	operation: planning::OperationKind,
	exec_ctx: &HostExecutionContext,
	local_workspace: &mut HostWorkspace,
) -> Result<(), Box<dyn std::error::Error>> {
	let start_time = std::time::Instant::now();
	let logger = exec_ctx.logger.clone();
	let hostname = local_workspace.context().hostname.clone();

	match operation {
		planning::OperationKind::Deploy => {
			info!(logger, "Starting deployment for {}...", hostname);

			let mode = DeploymentMode::from_context(local_workspace.context(), false);
			// 1. Resolve provider and ensure instance exists. Existing provider-backed
			// deploy targets are skipped unless the caller explicitly asks to overwrite,
			// recreate, or convert a cloud-init source to another install host.
			let provider =
				crate::fleet::resolution::resolve_provider(local_workspace.context(), logger.clone());
			let provider_snapshot =
				provider.as_deref().map(crate::providers::inspect_provider).transpose()?;
			let provider_exists =
				provider_snapshot.is_some_and(|snapshot| snapshot.state != ProviderState::Missing);
			if crate::providers::should_skip_existing_provider_deploy(
				provider_exists,
				exec_ctx.redeploy,
				exec_ctx.overwrite,
			) {
				info!(
					logger,
					"Provider instance for {} already exists. Skipping deploy; use --overwrite to reinstall in place or --redeploy to recreate.",
					hostname
				);
				return Ok(());
			}

			if exec_ctx.redeploy
				&& provider_snapshot.is_some_and(|snapshot| !snapshot.capabilities.supports_recreate)
			{
				return Err(format!("Provider for '{}' does not support recreation", hostname).into());
			}

			let provider = crate::providers::ensure_instance(
				provider,
				provider_snapshot.map(|snapshot| snapshot.state),
				exec_ctx.redeploy,
				logger.clone(),
			)?;

			// 2. Update dynamic IP in the workspace context
			if let Some(ref provider) = provider {
				apply_provider_endpoint(
					local_workspace.context_mut(),
					provider.endpoint(true)?,
					logger.clone(),
				);
			} else {
				local_workspace.context_mut().target_ip =
					crate::fleet::resolution::resolve_target_ip_for_deploy(
						local_workspace.context(),
						logger.clone(),
					);
			}

			// 3. Stage and run the deployment pipeline
			if provider_snapshot.is_some_and(|snapshot| snapshot.capabilities.requires_bootstrap_artifact)
			{
				execute_switch_workflow(local_workspace, "switch", false, logger.clone())?;
			} else {
				local_workspace.ensure_store_inputs(false, logger.clone())?;
				deploy::run_deployment(local_workspace.context(), mode, logger.clone())?;
			}

			let elapsed = start_time.elapsed();
			let mins = elapsed.as_secs() / 60;
			let secs = elapsed.as_secs() % 60;
			success!(logger, "Deployment complete! ({}m {}s)", mins, secs);
		}
		planning::OperationKind::Switch => {
			let action = exec_ctx.switch_action.as_deref().unwrap_or("switch");
			info!(logger, "Starting switch ({}) for {}...", action, hostname);
			execute_switch_workflow(local_workspace, action, exec_ctx.home_manager, logger.clone())?;
		}
	}

	// 4. Archive host lockfile after successful operation
	let should_archive = local_workspace.context().build_system
		&& match operation {
			planning::OperationKind::Deploy => true,
			planning::OperationKind::Switch => {
				let action = exec_ctx.switch_action.as_deref().unwrap_or("switch");
				action == "switch" || action == "bootentry"
			}
		};

	if should_archive
		&& let Err(e) = crate::workflow::lockfile::archive_lockfile(
			&hostname,
			&local_workspace.context().flake_ref,
			logger.clone(),
		) {
		crate::warn!(logger, "Failed to archive lockfile: {}", e);
	}

	Ok(())
}

fn execute_switch_workflow(
	local_workspace: &mut HostWorkspace,
	action: &str,
	home_manager: bool,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	let t_ip_start = std::time::Instant::now();
	let resolved_ip =
		crate::fleet::resolution::resolve_target_ip(local_workspace.context(), logger.clone());
	local_workspace.context_mut().target_ip = resolved_ip;
	let provider_keepalive =
		crate::fleet::resolution::resolve_provider(local_workspace.context(), logger.clone());
	if let Some(ref provider) = provider_keepalive {
		// For providers that require a startup wait (WSL), poll until the guest SSH is
		// reachable before proceeding. Other providers (Proxmox, VMware) are assumed
		// already running during a switch and do not need IP/SSH polling.
		let poll = provider.capabilities().requires_bootstrap_artifact;
		if poll {
			apply_provider_endpoint(
				local_workspace.context_mut(),
				provider.endpoint(poll)?,
				logger.clone(),
			);
		}
	}
	local_workspace.ensure_store_inputs(home_manager, logger.clone())?;
	debug!(logger, "Dynamic IP resolved in {:?}", t_ip_start.elapsed());

	info!(logger, "Running Identity Services Pre-Install Staging...");
	let t_identity_start = std::time::Instant::now();
	let identity_services = crate::identity::get_identity_services(logger.clone());
	for service in &identity_services {
		service.pre_install(local_workspace.context())?;
	}
	debug!(logger, "Identity staging completed in {:?}", t_identity_start.elapsed());

	if !planning::is_local_context(
		local_workspace.context(),
		&crate::fleet::local::current_local_hostname(),
	) {
		let t_key_start = std::time::Instant::now();
		if local_workspace.context().deployment.wsl.enable
			&& crate::config::get_runtime_options().deploy_active
		{
			crate::identity::ssh::stage_wsl_host_keys(&logger, local_workspace.context())?;
		}

		if let Err(e) = crate::identity::ssh::validate_and_sync_target_host_key(
			local_workspace.context(),
			logger.clone(),
		) {
			return Err(format!("Error validating/syncing target host key: {}", e).into());
		}
		debug!(
			logger,
			"Target host SSH key connection validated/synced in {:?}",
			t_key_start.elapsed()
		);

		let t_refresh_start = std::time::Instant::now();
		local_workspace.refresh_host_secret(logger.clone())?;
		debug!(logger, "Workspace host secret refreshed in {:?}", t_refresh_start.elapsed());
	}

	let t_switch_start = std::time::Instant::now();
	let switch_result = run_switch(local_workspace.context(), action, home_manager, logger.clone());
	drop(provider_keepalive);
	switch_result?;
	debug!(logger, "Switch operation (run_switch) completed in {:?}", t_switch_start.elapsed());
	Ok(())
}

fn apply_provider_endpoint(ctx: &mut RuntimeContext, endpoint: TargetEndpoint, logger: Logger) {
	let TargetEndpoint::Ssh { host, port: _, proxy_jump } = endpoint;
	ctx.target_ip = host;
	if let Some(proxy) = proxy_jump {
		ctx.deployment.ssh_proxy_jump = proxy;
		info!(logger, "Using provider control host as SSH jump host for {}", ctx.target_ip);
	}
	crate::context::update_cached_context(ctx);
}

fn get_os_type() -> &'static str {
	if cfg!(target_os = "macos") { "darwin" } else { "linux" }
}

fn store_flake_uri(ctx: &RuntimeContext, attr: &str) -> String {
	if let Some(source_path) = &ctx.source_store_path {
		format!("path:{}#{}", source_path, attr)
	} else {
		format!("{}#{}", ctx.flake_ref, attr)
	}
}

fn append_secret_override(args: &mut Vec<String>, ctx: &RuntimeContext) {
	if let Some(secret_path) = &ctx.secret_store_path {
		args.extend([
			"--override-input".to_string(),
			config::SECRET_INPUT_NAME.to_string(),
			format!("path:{}", secret_path),
		]);
	}
}

fn remote_secret_override(ctx: &RuntimeContext) -> String {
	ctx
		.secret_store_path
		.as_ref()
		.map(|path| format!(" --override-input {} path:{}", config::SECRET_INPUT_NAME, path))
		.unwrap_or_default()
}

pub fn run_switch(
	ctx: &RuntimeContext,
	action: &str,
	hm: bool,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	let start_time = std::time::Instant::now();
	let is_deploy = crate::config::get_runtime_options().deploy_active;
	let target_user = if ctx.deployment.wsl.enable && is_deploy {
		&ctx.deployment.wsl.bootstrap_user
	} else {
		&ctx.username
	};
	let target_ssh = format!("{}@{}", target_user, ctx.target_ip);

	let is_local = crate::fleet::local::is_local_target(ctx);

	if hm {
		let hm_attr = format!("{}_{}", ctx.username, ctx.hostname);
		info!(logger, "Starting Home Manager Switch user profile activation ({})", hm_attr);
		let flake_uri = store_flake_uri(ctx, &hm_attr);

		if is_local {
			let mut args = vec![
				"run".to_string(),
				"--".to_string(),
				"home-manager".to_string(),
				"switch".to_string(),
				"--flake".to_string(),
				flake_uri,
			];
			append_secret_override(&mut args, ctx);
			let args_ref: Vec<&str> = args.iter().map(String::as_str).collect();
			CommandExecutor::execute("nix", &args_ref, logger.clone())?;
		} else {
			let target_dest = format!("{}@{}", ctx.username, ctx.target_ip);
			info!(logger, "Running home-manager switch on target...");
			let remote_switch_cmd = format!(
				"nix run -- home-manager switch --flake \"{}\"{}",
				flake_uri,
				remote_secret_override(ctx)
			);
			CommandExecutor::execute_ssh(&target_dest, &remote_switch_cmd, logger.clone())?;
		}
	} else if is_local {
		info!(logger, "Detected local system switch configuration...");
		let os_type = get_os_type();
		let action_arg = if os_type == "darwin" && action == "bootentry" {
			info!(logger, "Warning: Darwin does not support bootentry action; falling back to switch.");
			"switch"
		} else if os_type == "darwin" && action == "test" {
			info!(logger, "Warning: Darwin does not support test action; falling back to check.");
			"check"
		} else {
			action
		};
		let flake_uri = store_flake_uri(ctx, &ctx.hostname);

		if os_type == "darwin" {
			let mut args = vec![
				"-H".to_string(),
				"darwin-rebuild".to_string(),
				action_arg.to_string(),
				"--flake".to_string(),
				flake_uri,
			];
			append_secret_override(&mut args, ctx);
			let args_ref: Vec<&str> = args.iter().map(String::as_str).collect();
			CommandExecutor::execute("sudo", &args_ref, logger.clone())?;
		} else {
			let mut args =
				vec!["nixos-rebuild".to_string(), action_arg.to_string(), "--flake".to_string(), flake_uri];
			append_secret_override(&mut args, ctx);
			let args_ref: Vec<&str> = args.iter().map(String::as_str).collect();
			CommandExecutor::execute("sudo", &args_ref, logger.clone())?;
		}
	} else {
		info!(logger, "Detected remote system switch deployment on {}...", ctx.target_ip);

		// Verify SSH connection first
		let t_ssh_verify = std::time::Instant::now();
		if let Err(err) = crate::remote::ssh::verify_ssh_connection(&target_ssh, 3) {
			return Err(
				format!("Cannot establish SSH connection to target {}: {}", target_ssh, err).into(),
			);
		}
		debug!(logger, "Target SSH connectivity verified in {:?}", t_ssh_verify.elapsed());

		let target_is_darwin = ctx.system.contains("darwin");
		if target_is_darwin {
			let darwin_action = if action == "bootentry" {
				info!(logger, "Warning: Darwin does not support bootentry action; falling back to switch.");
				"switch"
			} else if action == "test" {
				info!(logger, "Warning: Darwin does not support test action; falling back to check.");
				"check"
			} else {
				action
			};

			let flake_uri = store_flake_uri(ctx, &ctx.hostname);
			let remote_cmd = format!(
				"sudo nix run nix-darwin -- {} --flake \"{}\"{}",
				darwin_action,
				flake_uri,
				remote_secret_override(ctx)
			);

			if action == "build" {
				info!(logger, "Running Darwin build on target...");
			} else {
				info!(logger, "Running Darwin rebuild on target...");
			}
			CommandExecutor::execute_ssh(&target_ssh, &remote_cmd, logger.clone())?;
			return Ok(());
		}

		// Build system configuration
		let t_build = std::time::Instant::now();
		let builder = NixBuilder::resolve(ctx);
		let system_path = builder.build_system(None, logger.clone())?;
		debug!(logger, "Nix system configuration build completed in {:?}", t_build.elapsed());

		if action == "build" {
			info!(logger, "Build complete. Store path: {}", system_path);
			return Ok(());
		}

		// Skip activation if the target is already running this exact generation
		let current_profile = CommandExecutor::execute_ssh(
			&target_ssh,
			"readlink -f /nix/var/nix/profiles/system",
			logger.clone(),
		)
		.map(|out| out.trim().to_string())
		.unwrap_or_default();

		if system_path == current_profile && !crate::config::get_runtime_options().force {
			info!(
				logger,
				"Target system is already active on build generation {}. Skipping activation.", system_path
			);
			let duration = start_time.elapsed();
			let mins = duration.as_secs() / 60;
			let secs = duration.as_secs() % 60;
			success!(
				logger,
				"Switch operation successfully completed on {} (IP: {}) in {}m {}s!",
				ctx.hostname,
				ctx.target_ip,
				mins,
				secs
			);
			return Ok(());
		}

		// Magic Rollback Safety Switch
		let is_deploy = crate::config::get_runtime_options().deploy_active;
		let use_rollback = !is_deploy && action != "bootentry";

		if use_rollback {
			info!(
				logger,
				"Scheduling fallback rollback command (Magic Revert) on target in 60 seconds..."
			);
			let rollback_cmd =
				"sleep 60 && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration rollback";
			let setup_rollback =
				format!("nohup bash -c '{}' >/dev/null 2>&1 & echo $! > /tmp/rollback.pid", rollback_cmd);
			let _ = CommandExecutor::execute_ssh(&target_ssh, &setup_rollback, logger.clone());
		}

		info!(logger, "Registering system profile generation & activating configuration...");
		let t_activate = std::time::Instant::now();
		let activate_cmd = format!(
			"sudo nix-env -p /nix/var/nix/profiles/system --set {} && \
             sudo {}/bin/switch-to-configuration {}",
			system_path, system_path, action
		);

		let activation_result =
			CommandExecutor::execute_ssh(&target_ssh, &activate_cmd, logger.clone());
		debug!(logger, "System profile activation completed in {:?}", t_activate.elapsed());

		if use_rollback {
			match activation_result {
				Ok(_) => {
					info!(logger, "Activation successful. Cancelling scheduled rollback...");
					let cleanup_cmd = "if [ -f /tmp/rollback.pid ]; then sudo kill $(cat /tmp/rollback.pid) 2>/dev/null; rm -f /tmp/rollback.pid; fi";
					let _ = CommandExecutor::execute_ssh(&target_ssh, cleanup_cmd, logger.clone());
				}
				Err(e) => {
					info!(
						logger,
						"Activation command returned failure. Checking if target is still reachable via SSH..."
					);
					thread::sleep(Duration::from_secs(5));

					// Check if we can still SSH to target
					let ping_ssh = crate::remote::ssh::verify_ssh_connection(&target_ssh, 3).is_ok();

					if ping_ssh {
						info!(
							logger,
							"Target is still reachable via SSH. Cancelling auto-rollback to avoid false revert."
						);
						let cleanup_cmd = "if [ -f /tmp/rollback.pid ]; then sudo kill $(cat /tmp/rollback.pid) 2>/dev/null; rm -f /tmp/rollback.pid; fi";
						let _ = CommandExecutor::execute_ssh(&target_ssh, cleanup_cmd, logger.clone());
					} else {
						info!(
							logger,
							"Target is UNREACHABLE. Allowing auto-rollback to trigger in background."
						);
					}

					return Err(e);
				}
			}
		}
	}

	let duration = start_time.elapsed();
	let mins = duration.as_secs() / 60;
	let secs = duration.as_secs() % 60;
	success!(
		logger,
		"Switch operation successfully completed on {} (IP: {}) in {}m {}s!",
		ctx.hostname,
		ctx.target_ip,
		mins,
		secs
	);
	Ok(())
}
