use crate::context::RuntimeContext;
use crate::nix::NixBuilder;
use crate::process::{CommandExecutor, LogTarget};
use crate::log_status;
use std::env;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use std::path::Path;
use crate::identity::IdentityService;

struct SopsStagingGuard<'a> {
    service: crate::identity::sops::SopsService,
    ctx: &'a RuntimeContext,
    staged: bool,
}

impl<'a> SopsStagingGuard<'a> {
    fn stage(service: crate::identity::sops::SopsService, ctx: &'a RuntimeContext) -> Result<Self, Box<dyn std::error::Error>> {
        service.pre_install(ctx)?;
        Ok(Self {
            service,
            ctx,
            staged: true,
        })
    }
}

impl<'a> Drop for SopsStagingGuard<'a> {
    fn drop(&mut self) {
        if self.staged {
            let _ = self.service.post_install(self.ctx, Path::new("/"));
        }
    }
}

pub fn run_switch(
    ctx: &RuntimeContext,
    action: &str,
    hm: bool,
    log_target: Arc<Mutex<LogTarget>>,
) -> Result<(), Box<dyn std::error::Error>> {
    let start_time = std::time::Instant::now();
    let target_ssh = format!("{}@{}", ctx.username, ctx.target_ip);

    let local_hostname = get_local_hostname()?;
    let is_local = ctx.hostname == local_hostname || ctx.target_ip == "127.0.0.1" || ctx.target_ip == "localhost";

    if !is_local {
        // Clean local known_hosts to prevent warning messages when connecting or later
        let _ = std::process::Command::new("ssh-keygen")
            .args(&["-R", &ctx.target_ip])
            .output();
        let _ = std::process::Command::new("ssh-keygen")
            .args(&["-R", &ctx.hostname])
            .output();
    }

    // Stage SOPS secrets to local worktree before building/switching configuration
    log_status!(log_target, "Staging SOPS secrets for {} configuration...", ctx.hostname);
    let sops_service = crate::identity::sops::SopsService::new(Arc::clone(&log_target));
    let _sops_guard = SopsStagingGuard::stage(sops_service, ctx)?;

    if hm {
        let hm_attr = format!("{}_{}", ctx.username, ctx.hostname);
        log_status!(log_target, "Starting Home Manager Switch user profile activation ({})", hm_attr);

        if is_local {
            let args = ["run", "--", "home-manager", "switch", "--flake", &format!("path:.#{}", hm_attr)];
            CommandExecutor::execute("nix", &args, Arc::clone(&log_target))?;
        } else {
            log_status!(log_target, "Syncing repository to target for remote Home Manager switch...");
            let target_dest = format!("{}@{}", ctx.username, ctx.target_ip);
            let target_dir = crate::config::nix_cfg();

            let tar_cmd = "tar --exclude=\".git\" --exclude=\"result\" --exclude=\".DS_Store\" --exclude=\"target\" -czf - -C . .";
            let untar_cmd = format!("rm -rf {} && mkdir -p {} && tar -xzf - -C {}", target_dir, target_dir, target_dir);
            let pipe_cmd = format!("{} | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o PasswordAuthentication=no -A {} \"{}\"",
                tar_cmd, target_dest, untar_cmd
            );
            CommandExecutor::execute("bash", &["-c", &pipe_cmd], Arc::clone(&log_target))?;

            log_status!(log_target, "Running home-manager switch on target...");
            let remote_switch_cmd = format!("cd {} && nix run -- home-manager switch --flake \"path:.#{}\"", target_dir, hm_attr);
            CommandExecutor::execute_ssh(&target_dest, &remote_switch_cmd, Arc::clone(&log_target))?;
        }
    } else {
        if is_local {
            log_status!(log_target, "Detected local system switch configuration...");
            let os_type = get_os_type();
            let action_arg = if os_type == "darwin" && action == "bootentry" {
                log_status!(log_target, "Warning: Darwin does not support bootentry action; falling back to switch.");
                "switch"
            } else {
                action
            };

            if os_type == "darwin" {
                let args = ["run", "nix-darwin", "--", "darwin-rebuild", action_arg, "--flake", &format!("path:.#{}", ctx.hostname)];
                CommandExecutor::execute("nix", &args, Arc::clone(&log_target))?;
            } else {
                let args = ["nixos-rebuild", action_arg, "--flake", &format!("path:.#{}", ctx.hostname)];
                CommandExecutor::execute("sudo", &args, Arc::clone(&log_target))?;
            }
        } else {
            log_status!(log_target, "Detected remote system switch deployment on {}...", ctx.target_ip);

            // Verify SSH connection first
            let ssh_check = std::process::Command::new("ssh")
                .args(&[
                    "-o", "StrictHostKeyChecking=no",
                    "-o", "UserKnownHostsFile=/dev/null",
                    "-o", "LogLevel=ERROR",
                    "-o", "ConnectTimeout=3",
                    "-o", "PasswordAuthentication=no",
                    &target_ssh,
                    "true",
                ])
                .status()
                .map(|s| s.success())
                .unwrap_or(false);
            if !ssh_check {
                return Err(format!("Cannot establish SSH connection to target {}", target_ssh).into());
            }

            // Build system configuration
            let builder = NixBuilder::resolve(ctx);
            let system_path = builder.build_system(None, Arc::clone(&log_target))?;

            if action == "build" {
                log_status!(log_target, "Build complete. Store path: {}", system_path);
                return Ok(());
            }

            // Magic Rollback Safety Switch
            let is_deploy = env::var("DEPLOY_ACTIVE").unwrap_or_default() == "yes";
            let use_rollback = !is_deploy && action != "bootentry";

            if use_rollback {
                log_status!(log_target, "Scheduling fallback rollback command (Magic Revert) on target in 60 seconds...");
                let rollback_cmd = "sleep 60 && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration rollback";
                let setup_rollback = format!("nohup bash -c '{}' >/dev/null 2>&1 & echo $! > /tmp/rollback.pid", rollback_cmd);
                let _ = CommandExecutor::execute_ssh(&target_ssh, &setup_rollback, Arc::clone(&log_target));
            }

            log_status!(log_target, "Registering system profile generation & activating configuration...");
            let activate_cmd = format!(
                "sudo nix-env -p /nix/var/nix/profiles/system --set {} && \
                 sudo {}/bin/switch-to-configuration {}",
                system_path, system_path, action
            );

            let activation_result = CommandExecutor::execute_ssh(&target_ssh, &activate_cmd, Arc::clone(&log_target));

            if use_rollback {
                match activation_result {
                    Ok(_) => {
                        log_status!(log_target, "Activation successful. Cancelling scheduled rollback...");
                        let cleanup_cmd = "if [ -f /tmp/rollback.pid ]; then sudo kill $(cat /tmp/rollback.pid) 2>/dev/null; rm -f /tmp/rollback.pid; fi";
                        let _ = CommandExecutor::execute_ssh(&target_ssh, cleanup_cmd, Arc::clone(&log_target));
                    }
                    Err(e) => {
                        log_status!(log_target, "Activation command returned failure. Checking if target is still reachable via SSH...");
                        thread::sleep(Duration::from_secs(5));

                        // Check if we can still SSH to target
                        let ping_ssh = std::process::Command::new("ssh")
                            .args(&[
                                "-o", "StrictHostKeyChecking=no",
                                "-o", "UserKnownHostsFile=/dev/null",
                                "-o", "LogLevel=ERROR",
                                "-o", "ConnectTimeout=3",
                                "-o", "PasswordAuthentication=no",
                                &target_ssh,
                                "true",
                            ])
                            .status()
                            .map(|s| s.success())
                            .unwrap_or(false);

                        if ping_ssh {
                            log_status!(log_target, "Target is still reachable via SSH. Cancelling auto-rollback to avoid false revert.");
                            let cleanup_cmd = "if [ -f /tmp/rollback.pid ]; then sudo kill $(cat /tmp/rollback.pid) 2>/dev/null; rm -f /tmp/rollback.pid; fi";
                            let _ = CommandExecutor::execute_ssh(&target_ssh, cleanup_cmd, Arc::clone(&log_target));
                        } else {
                            log_status!(log_target, "Target is UNREACHABLE. Allowing auto-rollback to trigger in background.");
                        }

                        return Err(e);
                    }
                }
            }
        }
    }

    let duration = start_time.elapsed();
    let mins = duration.as_secs() / 60;
    let secs = duration.as_secs() % 60;
    log_status!(log_target, "Switch operation successfully completed on {} (IP: {}) in {}m {}s!", ctx.hostname, ctx.target_ip, mins, secs);
    Ok(())
}

fn get_local_hostname() -> Result<String, Box<dyn std::error::Error>> {
    let output = std::process::Command::new("hostname")
        .arg("-s")
        .output()?;
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        Err("Failed to get local hostname".into())
    }
}

fn get_os_type() -> &'static str {
    if cfg!(target_os = "macos") {
        "darwin"
    } else {
        "linux"
    }
}
