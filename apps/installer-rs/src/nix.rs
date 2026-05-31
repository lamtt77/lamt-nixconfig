use std::process::Command;
use std::sync::{Arc, Mutex, OnceLock};
use std::collections::HashMap;
use crate::context::RuntimeContext;
use crate::process::{CommandExecutor, LogTarget};

static BUILDER_LOCKS: OnceLock<Mutex<HashMap<String, Arc<Mutex<()>>>>> = OnceLock::new();

fn get_builder_lock(connection: &str) -> Arc<Mutex<()>> {
    let map_mutex = BUILDER_LOCKS.get_or_init(|| Mutex::new(HashMap::new()));
    let mut map = map_mutex.lock().unwrap();
    map.entry(connection.to_string())
        .or_insert_with(|| Arc::new(Mutex::new(())))
        .clone()
}

static LOCAL_NIX_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

fn get_local_nix_lock() -> &'static Mutex<()> {
    LOCAL_NIX_LOCK.get_or_init(|| Mutex::new(()))
}

pub enum BuildStrategy {
    Local,
    RemoteBuilder { ssh_connection: String },
    TargetInstantiated,
    TargetNative,
}

pub struct NixBuilder {
    pub strategy: BuildStrategy,
    pub hostname: String,
    pub target_ip: String,
    pub username: String,
    pub low_mem: bool,
    pub has_local_nix: bool,
    pub synced_to_builder: Mutex<bool>,
}

impl NixBuilder {
    pub fn resolve(ctx: &RuntimeContext) -> Self {
        let low_mem = ctx.deployment.low_mem == "yes";
        let target_system = &ctx.system;
        let host_system = get_current_host_system();
        let has_local_nix = check_local_nix_binary();

        // Determine if local architecture matches the target
        let arch_match = host_system == *target_system;

        // Determine if local Nix is capable of building for the target platform
        let local_compatible = has_local_nix && (arch_match || check_local_can_build(target_system));

        // Read build_on and builder overrides from environment (populated by main.rs from CLI flags)
        let build_on_env = std::env::var("BUILD_ON").unwrap_or_default();
        let builder_env = std::env::var("BUILDER").unwrap_or_default();
        let config_builder = &ctx.deployment.builder;

        let active_builder = if !builder_env.is_empty() {
            builder_env.clone()
        } else if !config_builder.is_empty() {
            config_builder.clone()
        } else {
            crate::config::DEFAULT_BUILDER.to_string()
        };

        let strategy = if !build_on_env.is_empty() && build_on_env != "auto" {
            match build_on_env.as_str() {
                "local" => BuildStrategy::Local,
                "builder" => {
                    if active_builder.is_empty() {
                        if local_compatible {
                            BuildStrategy::Local
                        } else if low_mem {
                            BuildStrategy::TargetInstantiated
                        } else {
                            BuildStrategy::TargetNative
                        }
                    } else {
                        BuildStrategy::RemoteBuilder {
                            ssh_connection: active_builder.clone(),
                        }
                    }
                }
                "target" => {
                    if low_mem {
                        BuildStrategy::TargetInstantiated
                    } else {
                        BuildStrategy::TargetNative
                    }
                }
                "instantiated" | "realise" | "realization" => BuildStrategy::TargetInstantiated,
                "native" => BuildStrategy::TargetNative,
                _ => {
                    if local_compatible {
                        BuildStrategy::Local
                    } else if !active_builder.is_empty() && check_builder_compatible(&active_builder, target_system) {
                        BuildStrategy::RemoteBuilder {
                            ssh_connection: active_builder.clone(),
                        }
                    } else if low_mem {
                        BuildStrategy::TargetInstantiated
                    } else {
                        BuildStrategy::TargetNative
                    }
                }
            }
        } else {
            let local_hostname = get_local_hostname();
            let is_local = ctx.hostname == local_hostname || ctx.target_ip == "127.0.0.1" || ctx.target_ip == "localhost";

            if !builder_env.is_empty() {
                // Command-line override takes top precedence
                BuildStrategy::RemoteBuilder {
                    ssh_connection: builder_env.clone(),
                }
            } else if is_local {
                // Local target priority: local -> builder -> target
                if local_compatible {
                    BuildStrategy::Local
                } else if !active_builder.is_empty() && check_builder_compatible(&active_builder, target_system) {
                    BuildStrategy::RemoteBuilder {
                        ssh_connection: active_builder.clone(),
                    }
                } else if low_mem {
                    BuildStrategy::TargetInstantiated
                } else {
                    BuildStrategy::TargetNative
                }
            } else {
                // Remote target priority: builder -> local -> target
                if !active_builder.is_empty() && check_builder_compatible(&active_builder, target_system) {
                    BuildStrategy::RemoteBuilder {
                        ssh_connection: active_builder.clone(),
                    }
                } else if local_compatible {
                    BuildStrategy::Local
                } else if low_mem {
                    BuildStrategy::TargetInstantiated
                } else {
                    BuildStrategy::TargetNative
                }
            }
        };

        Self {
            strategy,
            hostname: ctx.hostname.clone(),
            target_ip: ctx.target_ip.clone(),
            username: ctx.username.clone(),
            low_mem,
            has_local_nix,
            synced_to_builder: Mutex::new(false),
        }
    }

    /// Build a target configuration attribute suffix (e.g. "config.system.build.toplevel")
    /// and return the final store path.
    pub fn build_attribute(&self, attr: &str, mount_point: Option<&str>, log_target: Arc<Mutex<LogTarget>>) -> Result<String, Box<dyn std::error::Error>> {
        let target_attr = format!("path:.#nixosConfigurations.{}.{}", self.hostname, attr);

        let is_deploy = std::env::var("DEPLOY_ACTIVE").unwrap_or_default() == "yes";
        let target_user = if is_deploy { "root" } else { &self.username };
        let target_ssh = format!("{}@{}", target_user, self.target_ip);

        match &self.strategy {
            BuildStrategy::Local => {
                let _local_guard = get_local_nix_lock().lock().unwrap();
                println!("Executing local Nix build for {} ({})...", self.hostname, attr);
                let args = ["build", "--print-out-paths", "--no-link", &target_attr];
                let out = CommandExecutor::execute("nix", &args, Arc::clone(&log_target))?;
                let store_path = out.trim().to_string();

                // Copy store path to target
                println!("Transferring compiled store path to target...");
                let copy_target = if let Some(mnt) = mount_point {
                    format!("ssh://{}?remote-store=local?root={}", target_ssh, mnt)
                } else {
                    format!("ssh://{}", target_ssh)
                };
                let copy_args = ["copy", "--to", &copy_target, &store_path];
                CommandExecutor::execute("nix", &copy_args, log_target)?;

                Ok(store_path)
            }
            BuildStrategy::RemoteBuilder { ssh_connection } => {
                let builder_lock = get_builder_lock(ssh_connection);
                let _guard = builder_lock.lock().unwrap();

                // Sync codebase repository to remote builder if not already done
                let mut synced = self.synced_to_builder.lock().unwrap();
                if !*synced {
                    println!("Syncing codebase repository to remote builder {}...", ssh_connection);
                    let target_dir = crate::config::nix_cfg();
                    let tar_cmd = "tar --exclude=\".git\" --exclude=\"result\" --exclude=\".DS_Store\" --exclude=\"target\" --exclude=\"apps/installer-rs/target\" -czf - -C . .";
                    let untar_cmd = format!("rm -rf {} && mkdir -p {} && tar -xzf - -C {}", target_dir, target_dir, target_dir);
                    let pipe_cmd = format!(
                        "{} | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -A {} \"{}\"",
                        tar_cmd, ssh_connection, untar_cmd
                    );
                    CommandExecutor::execute("bash", &["-c", &pipe_cmd], Arc::clone(&log_target))?;
                    *synced = true;
                    println!("Repository codebase sync to builder complete.");
                }

                println!("Delegating Nix build for {} ({}) to remote builder {}...", self.hostname, attr, ssh_connection);
                let build_cmd = format!(
                    "export NIX_SSHOPTS=\"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR\" && \
                     cd {} && \
                     nix build --print-out-paths --no-link path:.#nixosConfigurations.{}.{}",
                    crate::config::nix_cfg(), self.hostname, attr
                );
                let out = CommandExecutor::execute_ssh(ssh_connection, &build_cmd, Arc::clone(&log_target))?;
                let store_path = out.trim().to_string();

                // Copy from builder to target
                println!("Copying store path from builder to target...");
                let copy_target = if let Some(mnt) = mount_point {
                    format!("ssh://{}?remote-store=local?root={}", target_ssh, mnt)
                } else {
                    format!("ssh://{}", target_ssh)
                };

                // We run nix copy on the remote builder pushing to target
                let copy_cmd = format!(
                    "export NIX_SSHOPTS=\"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR\" && \
                     cd {} && \
                     nix copy --to \"{}\" {}",
                    crate::config::nix_cfg(), copy_target, store_path
                );
                CommandExecutor::execute_ssh(ssh_connection, &copy_cmd, log_target)?;

                Ok(store_path)
            }
            BuildStrategy::TargetInstantiated => {
                let local_guard = get_local_nix_lock().lock().unwrap();
                println!("Executing remote instantiation (Solution B) for {} ({})...", self.hostname, attr);

                // 1. Evaluate .drv path on orchestrator
                let args = ["path-info", "--derivation", &target_attr];
                let drv_out = CommandExecutor::execute("nix", &args, Arc::clone(&log_target))?;
                let drv_path = drv_out.trim().to_string();

                // 2. Copy the .drv and inputs to target
                println!("Copying derivation and inputs to target...");
                let copy_target = if let Some(mnt) = mount_point {
                    format!("ssh://{}?remote-store=local?root={}", target_ssh, mnt)
                } else {
                    format!("ssh://{}", target_ssh)
                };
                let copy_args = ["copy", "--to", &copy_target, &drv_path];
                CommandExecutor::execute("nix", &copy_args, Arc::clone(&log_target))?;

                std::mem::drop(local_guard);

                // 3. Realise on target using memory tuning variables
                let gc_env = if self.low_mem {
                    "export GC_INITIAL_HEAP_SIZE=1M GC_DONT_GC=1 NIX_DISABLE_AUTO_GC=1; "
                } else {
                    ""
                };

                let store_arg = if let Some(mnt) = mount_point {
                    format!("--store {}", mnt)
                } else {
                    "".to_string()
                };

                let realise_cmd = format!(
                    "{}nix-store --realise {} --cores 1 --max-jobs 1 {}",
                    gc_env, drv_path, store_arg
                );

                let out = CommandExecutor::execute_ssh(&target_ssh, &realise_cmd, log_target)?;
                Ok(out.trim().to_string())
            }
            BuildStrategy::TargetNative => {
                let nix_repo = std::env::var("NIX_REPO").unwrap_or_else(|_| "local".to_string());
                if nix_repo == "local" {
                    println!("Syncing codebase repository to target {}...", self.target_ip);
                    let target_dir = crate::config::nix_cfg();
                    let tar_cmd = "tar --exclude=\".git\" --exclude=\"result\" --exclude=\".DS_Store\" --exclude=\"target\" --exclude=\"apps/installer-rs/target\" -czf - -C . .";
                    let untar_cmd = format!("rm -rf {} && mkdir -p {} && tar -xzf - -C {}", target_dir, target_dir, target_dir);
                    let pipe_cmd = format!(
                        "{} | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -A {} \"{}\"",
                        tar_cmd, target_ssh, untar_cmd
                    );
                    CommandExecutor::execute("bash", &["-c", &pipe_cmd], Arc::clone(&log_target))?;
                    println!("Repository codebase sync to target complete.");
                }

                let store_arg = if let Some(mnt) = mount_point {
                    format!("--store {} ", mnt)
                } else {
                    "".to_string()
                };

                println!("Executing native Nix build directly on target {} ({})...", self.hostname, attr);
                let build_cmd = if nix_repo == "local" {
                    format!(
                        "cd {} && \
                         nix build {}--print-out-paths --no-link path:.#nixosConfigurations.{}.{}",
                        crate::config::nix_cfg(), store_arg, self.hostname, attr
                    )
                } else if nix_repo == "github" {
                    format!(
                        "nix build {}--print-out-paths --no-link github:{}/{}#nixosConfigurations.{}.{}",
                        store_arg, crate::config::github_user(), crate::config::nix_cfg(), self.hostname, attr
                    )
                } else if nix_repo == "tea" {
                    format!(
                        "nix build {}--print-out-paths --no-link git+ssh://{}@{}/{}/{}#nixosConfigurations.{}.{}",
                        store_arg, crate::config::DEFAULT_TEA_SSH_USER, crate::config::tea_url(), crate::config::github_user(), crate::config::nix_cfg(), self.hostname, attr
                    )
                } else {
                    format!(
                        "nix build {}--print-out-paths --no-link {}#nixosConfigurations.{}.{}",
                        store_arg, nix_repo, self.hostname, attr
                    )
                };

                let out = CommandExecutor::execute_ssh(&target_ssh, &build_cmd, log_target)?;
                Ok(out.trim().to_string())
            }
        }
    }

    /// Helper to preserve backward compatibility (calls build_attribute for toplevel).
    pub fn build_system(&self, mount_point: Option<&str>, log_target: Arc<Mutex<LogTarget>>) -> Result<String, Box<dyn std::error::Error>> {
        self.build_attribute("config.system.build.toplevel", mount_point, log_target)
    }
}

fn get_current_host_system() -> String {
    static HOST_SYSTEM: OnceLock<String> = OnceLock::new();
    HOST_SYSTEM.get_or_init(|| {
        let output = Command::new("nix")
            .args(&["eval", "--raw", "--expr", "builtins.currentSystem"])
            .output();
        if let Ok(out) = output {
            if out.status.success() {
                return String::from_utf8_lossy(&out.stdout).trim().to_string();
            }
        }

        if cfg!(target_os = "macos") {
            if cfg!(target_arch = "aarch64") {
                "aarch64-darwin".to_string()
            } else {
                "x86_64-darwin".to_string()
            }
        } else {
            "x86_64-linux".to_string()
        }
    }).clone()
}

fn check_local_nix_binary() -> bool {
    Command::new("nix")
        .arg("--version")
        .output()
        .is_ok()
}

fn check_local_can_build(target_system: &str) -> bool {
    let _local_guard = get_local_nix_lock().lock().unwrap();
    let expr = format!(
        "derivation {{ name = \"test\"; builder = \"/bin/sh\"; args = [ \"-c\" \"echo ok > $out\" ]; system = \"{}\"; }}",
        target_system
    );
    let output = Command::new("nix")
        .args(&["build", "--expr", &expr, "--no-link", "--max-jobs", "1", "--connect-timeout", "2"])
        .output();
    
    if let Ok(out) = output {
        out.status.success()
    } else {
        false
    }
}

fn get_local_hostname() -> String {
    let output = Command::new("hostname")
        .arg("-s")
        .output();
    if let Ok(out) = output {
        if out.status.success() {
            return String::from_utf8_lossy(&out.stdout).trim().to_string();
        }
    }
    "".to_string()
}

fn check_builder_compatible(builder_ssh: &str, target_system: &str) -> bool {
    let args = [
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
        "-o", "ConnectTimeout=2",
        "-o", "PasswordAuthentication=no",
        builder_ssh,
        "uname -m",
    ];
    let output = Command::new("ssh")
        .args(&args)
        .output();
    if let Ok(out) = output {
        if out.status.success() {
            let arch = String::from_utf8_lossy(&out.stdout).trim().to_string();
            let builder_system = match arch.as_str() {
                "x86_64" => "x86_64-linux",
                "aarch64" | "arm64" => "aarch64-linux",
                _ => "",
            };
            return builder_system == target_system;
        }
    }
    false
}
