use crate::context::RuntimeContext;
use crate::nix::NixBuilder;
use crate::pipeline::{self, DeploymentMode};
use crate::plan;
use crate::process::{CommandExecutor, Logger};
use crate::providers::{get_provider_ip, ProviderIpMode};
use crate::workspace;
use crate::workspace::HostWorkspace;

use std::thread;
use std::time::Duration;

pub struct HostExecutionContext<'a> {
    pub logger: Logger,
    pub redeploy: bool,
    pub overwrite: bool,
    pub convert_to: Option<&'a String>,
    pub switch_action: Option<&'a str>, // "switch", "bootentry", "test", "build"
    pub home_manager: bool,
    pub run_state: &'a plan::RunState,
}

/// Executes the full switch or deploy lifecycle for a single host.
pub fn execute_host_operation(
    ctx: &RuntimeContext,
    operation: plan::OperationKind,
    exec_ctx: &HostExecutionContext,
    local_workspace: &mut HostWorkspace,
) -> Result<(), Box<dyn std::error::Error>> {
    let start_time = std::time::Instant::now();
    let logger = exec_ctx.logger.clone();

    match operation {
        plan::OperationKind::Deploy => {
            info!(logger, "Starting deployment for {}...", ctx.hostname);

            let mode = DeploymentMode::from_context(ctx, exec_ctx.convert_to.is_some());

            // 1. Resolve provider and ensure instance exists. Existing provider-backed
            // deploy targets are skipped unless the caller explicitly asks to overwrite,
            // recreate, or convert a cloud-init source to another install host.
            let provider = crate::fleet::resolution::resolve_provider(ctx, logger.clone());
            let provider_exists = provider.as_ref().is_some_and(|provider| provider.exists());
            if crate::providers::should_skip_existing_provider_deploy(
                provider_exists,
                exec_ctx.redeploy,
                exec_ctx.overwrite,
                exec_ctx.convert_to.is_some(),
            ) {
                info!(
                    logger,
                    "Provider instance for {} already exists. Skipping deploy; use --overwrite to reinstall in place or --redeploy to recreate.",
                    ctx.hostname
                );
                return Ok(());
            }

            let provider =
                crate::providers::ensure_instance(provider, exec_ctx.redeploy, logger.clone())?;

            // 2. Update dynamic IP in the workspace context
            let resolved_ip = if let Some(ref p) = provider {
                match get_provider_ip(p.as_ref(), ProviderIpMode::PollUntilReady) {
                    Ok(ip) if !ip.is_empty() => ip,
                    _ => {
                        crate::fleet::resolution::resolve_target_ip_for_deploy(ctx, logger.clone())
                    }
                }
            } else {
                crate::fleet::resolution::resolve_target_ip_for_deploy(ctx, logger.clone())
            };
            local_workspace.context_mut().target_ip = resolved_ip;

            // 3. Stage and run the deployment pipeline
            pipeline::run_deployment(
                local_workspace.context(),
                mode,
                logger.clone(),
                Some(exec_ctx.run_state.clone()),
            )?;

            let elapsed = start_time.elapsed();
            let mins = elapsed.as_secs() / 60;
            let secs = elapsed.as_secs() % 60;
            success!(logger, "Deployment complete! ({}m {}s)", mins, secs);
        }
        plan::OperationKind::Switch => {
            let action = exec_ctx.switch_action.unwrap_or("switch");
            info!(
                logger,
                "Starting switch ({}) for {}...", action, ctx.hostname
            );

            // 1. Resolve dynamic IP and update it in workspace context
            let resolved_ip = crate::fleet::resolution::resolve_target_ip(ctx, logger.clone());
            local_workspace.context_mut().target_ip = resolved_ip;

            // 2. Validate and sync target host key
            if !plan::is_local_context(
                local_workspace.context(),
                &crate::fleet::local::current_local_hostname(),
            ) {
                if let Err(e) = crate::identity::ssh::validate_and_sync_target_host_key(
                    local_workspace.context(),
                    logger.clone(),
                ) {
                    return Err(format!("Error validating/syncing target host key: {}", e).into());
                }

                // Key validation may re-encrypt the source secret for the target's
                // active host key, so refresh the workspace snapshot before building.
                local_workspace.refresh_host_secret(logger.clone())?;
            }

            // 3. Run the switch operation
            run_switch(
                local_workspace.context(),
                action,
                exec_ctx.home_manager,
                logger,
                Some(exec_ctx.run_state.clone()),
            )?;
        }
    }

    Ok(())
}

struct RemoteWorkspaceCleanup {
    _connection: String,
    _workspace_dir: Option<String>,
}

impl RemoteWorkspaceCleanup {
    fn new(connection: String, workspace_dir: Option<String>) -> Self {
        Self {
            _connection: connection,
            _workspace_dir: workspace_dir,
        }
    }
}

impl Drop for RemoteWorkspaceCleanup {
    fn drop(&mut self) {
        // Do not delete persistent remote workspaces to allow Nix evaluation/build caching!
    }
}

fn get_os_type() -> &'static str {
    if cfg!(target_os = "macos") {
        "darwin"
    } else {
        "linux"
    }
}

pub fn run_switch(
    ctx: &RuntimeContext,
    action: &str,
    hm: bool,
    logger: Logger,
    run_state: Option<plan::RunState>,
) -> Result<(), Box<dyn std::error::Error>> {
    let start_time = std::time::Instant::now();
    let target_ssh = format!("{}@{}", ctx.username, ctx.target_ip);

    let is_local = crate::fleet::local::is_local_target(ctx);

    if !is_local {
        // Clean local known_hosts to prevent warning messages when connecting or later
        let _ = crate::remote::known_hosts::remove_known_host_keys(&ctx.target_ip, &ctx.hostname);
    }

    if hm {
        let hm_attr = format!("{}_{}", ctx.username, ctx.hostname);
        info!(
            logger,
            "Starting Home Manager Switch user profile activation ({})", hm_attr
        );

        if is_local {
            let args = [
                "run",
                "--",
                "home-manager",
                "switch",
                "--flake",
                &format!("{}#{}", ctx.flake_ref, hm_attr),
            ];
            CommandExecutor::execute("nix", &args, logger.clone())?;
        } else {
            let target_dest = format!("{}@{}", ctx.username, ctx.target_ip);
            let _cleanup =
                RemoteWorkspaceCleanup::new(target_dest.clone(), ctx.remote_workspace_dir.clone());
            let target_dir = ctx
                .remote_workspace_dir
                .as_deref()
                .unwrap_or(crate::config::DEFAULT_NIX_CFG);
            if let Some(workspace_root) = ctx.workspace_root.as_deref() {
                info!(
                    logger,
                    "Syncing prepared workspace to target for remote Home Manager switch..."
                );
                workspace::sync_workspace_to_remote(workspace_root, &target_dest, target_dir)?;
            }

            let commit_cmd = workspace::remote_git_snapshot_command(target_dir);
            CommandExecutor::execute_ssh(&target_dest, &commit_cmd, logger.clone())?;

            info!(logger, "Running home-manager switch on target...");
            let remote_switch_cmd = format!(
                "cd {} && nix run -- home-manager switch --flake \"git+file://$PWD#{}\"",
                target_dir, hm_attr
            );
            CommandExecutor::execute_ssh(&target_dest, &remote_switch_cmd, logger.clone())?;
        }
    } else if is_local {
        info!(logger, "Detected local system switch configuration...");
        let os_type = get_os_type();
        let action_arg = if os_type == "darwin" && action == "bootentry" {
            info!(
                logger,
                "Warning: Darwin does not support bootentry action; falling back to switch."
            );
            "switch"
        } else {
            action
        };

        if os_type == "darwin" {
            let args = [
                "-H",
                "darwin-rebuild",
                action_arg,
                "--flake",
                &format!("{}#{}", ctx.flake_ref, ctx.hostname),
            ];
            CommandExecutor::execute("sudo", &args, logger.clone())?;
        } else {
            let args = [
                "nixos-rebuild",
                action_arg,
                "--flake",
                &format!("{}#{}", ctx.flake_ref, ctx.hostname),
            ];
            CommandExecutor::execute("sudo", &args, logger.clone())?;
        }
    } else {
        info!(
            logger,
            "Detected remote system switch deployment on {}...", ctx.target_ip
        );

        // Verify SSH connection first
        if let Err(err) = crate::remote::ssh::verify_ssh_connection(&target_ssh, 3) {
            return Err(format!(
                "Cannot establish SSH connection to target {}: {}",
                target_ssh, err
            )
            .into());
        }

        let target_is_darwin = ctx.system.contains("darwin");
        if target_is_darwin {
            let _cleanup =
                RemoteWorkspaceCleanup::new(target_ssh.clone(), ctx.remote_workspace_dir.clone());
            let target_dir = ctx
                .remote_workspace_dir
                .as_deref()
                .unwrap_or(crate::config::DEFAULT_NIX_CFG);

            if let Some(workspace_root) = ctx.workspace_root.as_deref() {
                info!(
                    logger,
                    "Syncing prepared workspace to target for remote Darwin switch..."
                );
                workspace::sync_workspace_to_remote(workspace_root, &target_ssh, target_dir)?;
            }

            let darwin_action = if action == "bootentry" {
                info!(
                    logger,
                    "Warning: Darwin does not support bootentry action; falling back to switch."
                );
                "switch"
            } else {
                action
            };

            let commit_cmd = workspace::remote_git_snapshot_command(target_dir);
            CommandExecutor::execute_ssh(&target_ssh, &commit_cmd, logger.clone())?;

            let remote_cmd = format!(
                "cd {} && sudo nix run nix-darwin -- {} --flake \"git+file://$PWD#{}\"",
                target_dir, darwin_action, ctx.hostname
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
        let builder = NixBuilder::resolve(ctx, run_state);
        let system_path = builder.build_system(None, logger.clone())?;

        if action == "build" {
            info!(logger, "Build complete. Store path: {}", system_path);
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
            let rollback_cmd = "sleep 60 && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration rollback";
            let setup_rollback = format!(
                "nohup bash -c '{}' >/dev/null 2>&1 & echo $! > /tmp/rollback.pid",
                rollback_cmd
            );
            let _ = CommandExecutor::execute_ssh(&target_ssh, &setup_rollback, logger.clone());
        }

        info!(
            logger,
            "Registering system profile generation & activating configuration..."
        );
        let activate_cmd = format!(
            "sudo nix-env -p /nix/var/nix/profiles/system --set {} && \
             sudo {}/bin/switch-to-configuration {}",
            system_path, system_path, action
        );

        let activation_result =
            CommandExecutor::execute_ssh(&target_ssh, &activate_cmd, logger.clone());

        if use_rollback {
            match activation_result {
                Ok(_) => {
                    info!(
                        logger,
                        "Activation successful. Cancelling scheduled rollback..."
                    );
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
                    let ping_ssh =
                        crate::remote::ssh::verify_ssh_connection(&target_ssh, 3).is_ok();

                    if ping_ssh {
                        info!(
                            logger,
                            "Target is still reachable via SSH. Cancelling auto-rollback to avoid false revert."
                        );
                        let cleanup_cmd = "if [ -f /tmp/rollback.pid ]; then sudo kill $(cat /tmp/rollback.pid) 2>/dev/null; rm -f /tmp/rollback.pid; fi";
                        let _ =
                            CommandExecutor::execute_ssh(&target_ssh, cleanup_cmd, logger.clone());
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
