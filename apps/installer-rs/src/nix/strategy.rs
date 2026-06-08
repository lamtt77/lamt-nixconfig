use crate::context::RuntimeContext;
use crate::nix::eval::{check_local_can_build, check_local_nix_binary, get_current_host_system};
use crate::nix::remote_builder::check_builder_compatible;
use crate::workspace;
use std::path::PathBuf;
use std::sync::Mutex;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BuildStrategy {
    Local,
    RemoteBuilder { ssh_connection: String },
    TargetInstantiated,
    TargetNative,
}

impl BuildStrategy {
    pub fn label(&self) -> String {
        match self {
            Self::Local => "Local (Natively on Orchestrator)".to_string(),
            Self::RemoteBuilder { ssh_connection } => {
                format!("RemoteBuilder (Delegated via SSH to {})", ssh_connection)
            }
            Self::TargetInstantiated => {
                "TargetInstantiated (Instantiation on Orchestrator -> Realization on Target)"
                    .to_string()
            }
            Self::TargetNative => "TargetNative (Natively built directly on target)".to_string(),
        }
    }
}

pub struct NixBuilder {
    pub strategy: BuildStrategy,
    pub hostname: String,
    pub target_ip: String,
    pub username: String,
    pub system: String,
    pub low_mem: bool,
    pub substitute_on_destination: bool,
    pub has_local_nix: bool,
    pub synced_to_builder: Mutex<bool>,
    pub flake_ref: String,
    pub common_base_root: Option<PathBuf>,
    pub workspace_root: Option<PathBuf>,
    pub remote_workspace: Option<workspace::RemoteWorkspace>,
    pub run_state: Option<crate::plan::RunState>,
}

impl NixBuilder {
    pub fn strategy_label(ctx: &RuntimeContext) -> String {
        Self::resolve(ctx, None).strategy.label()
    }

    pub fn resolve(ctx: &RuntimeContext, run_state: Option<crate::plan::RunState>) -> Self {
        let low_mem = ctx.deployment.low_mem == "yes";
        let substitute_on_destination = ctx.deployment.substitute_on_destination;
        let target_system = &ctx.system;
        let host_system = get_current_host_system();
        let has_local_nix = check_local_nix_binary();

        // Determine if local architecture matches the target
        let arch_match = host_system == *target_system;

        // Determine if local Nix is capable of building for the target platform
        let local_compatible =
            has_local_nix && (arch_match || check_local_can_build(target_system));

        let runtime_options = crate::config::get_runtime_options();
        let build_on_override = runtime_options
            .build_strategy
            .as_deref()
            .unwrap_or_default();
        let builder_override = runtime_options.builder.as_deref().unwrap_or_default();
        let config_builder = &ctx.deployment.builder;

        let active_builder = if !builder_override.is_empty() {
            builder_override.to_string()
        } else if !config_builder.is_empty() {
            config_builder.clone()
        } else {
            crate::config::DEFAULT_BUILDER.to_string()
        };

        let strategy = if !build_on_override.is_empty() && build_on_override != "auto" {
            match build_on_override {
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
                    } else if !active_builder.is_empty()
                        && check_builder_compatible(&active_builder, target_system)
                    {
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
            let is_local = crate::fleet::local::is_local_target(ctx);

            if !builder_override.is_empty() {
                // Command-line override takes top precedence
                BuildStrategy::RemoteBuilder {
                    ssh_connection: builder_override.to_string(),
                }
            } else if is_local {
                // Local target priority: local -> builder -> target
                if local_compatible {
                    BuildStrategy::Local
                } else if !active_builder.is_empty()
                    && check_builder_compatible(&active_builder, target_system)
                {
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
                if !active_builder.is_empty()
                    && check_builder_compatible(&active_builder, target_system)
                {
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

        let remote_workspace = ctx.remote_workspace_dir.as_ref().map(|path| {
            let connection = match &strategy {
                BuildStrategy::RemoteBuilder { ssh_connection } => ssh_connection.clone(),
                BuildStrategy::TargetNative => {
                    let is_deploy = crate::config::get_runtime_options().deploy_active;
                    let target_user = if is_deploy { "root" } else { &ctx.username };
                    format!("{}@{}", target_user, ctx.target_ip)
                }
                _ => "".to_string(),
            };
            workspace::RemoteWorkspace::new(connection, path.clone())
        });

        Self {
            strategy,
            hostname: ctx.hostname.clone(),
            target_ip: ctx.target_ip.clone(),
            username: ctx.username.clone(),
            system: ctx.system.clone(),
            low_mem,
            substitute_on_destination,
            has_local_nix,
            synced_to_builder: Mutex::new(false),
            flake_ref: ctx.flake_ref.clone(),
            common_base_root: ctx.common_base_root.clone(),
            workspace_root: ctx.workspace_root.clone(),
            remote_workspace,
            run_state,
        }
    }
}
