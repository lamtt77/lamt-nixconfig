use crate::context::RuntimeContext;
use crate::nix::BuildStrategy;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};

pub use super::plan_provider::{provider_kind, ProviderKind};
pub use super::plan_render::{confirm_batch, provider_label, provider_label_for_context};
pub use super::plan_risk::{calculate_host_risk, OperationRisk, RiskAssessmentParams};
pub use super::plan_spec::{parse_host_spec, split_hosts, HostSpec};
pub use super::plan_workspace::{
    is_local_context, is_local_target, workspace_mode_for_hosts, workspace_mode_for_targets,
    WorkspaceMode,
};

#[derive(Clone, Debug)]
pub struct RunState {
    pub synced_builders: Arc<Mutex<HashSet<String>>>,
    pub builder_sync_locks: Arc<Mutex<HashMap<String, Arc<Mutex<()>>>>>,
}

impl Default for RunState {
    fn default() -> Self {
        Self {
            synced_builders: Arc::new(Mutex::new(HashSet::new())),
            builder_sync_locks: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OperationKind {
    Deploy,
    Switch,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunPlan<T> {
    pub operation: OperationKind,
    pub targets: Vec<T>,
    pub workspace_mode: WorkspaceMode,
}

#[derive(Debug, Clone)]
pub struct HostPlan {
    pub hostname: String,
    pub target_ip: String,
    pub provider: ProviderKind,
    pub operation: OperationKind,
    pub workspace_mode: WorkspaceMode,
    pub build_strategy: Option<BuildStrategy>,
    pub switch_action: Option<String>,
    pub risk: OperationRisk,
    pub skip_reason: Option<String>,
}

pub fn build_run_plan<T>(
    operation: OperationKind,
    targets: Vec<T>,
    single_host_fast_path_allowed: bool,
    is_local: impl Fn(&T) -> bool,
) -> RunPlan<T> {
    let workspace_mode =
        workspace_mode_for_targets(&targets, single_host_fast_path_allowed, is_local);

    RunPlan {
        operation,
        targets,
        workspace_mode,
    }
}

pub struct PlanHostOptions<'a> {
    pub ctx: &'a RuntimeContext,
    pub operation: OperationKind,
    pub redeploy: bool,
    pub overwrite: bool,
    pub convert_to: Option<&'a String>,
    pub switch_action: Option<&'a str>,
    pub home_manager: bool,
    pub provider_exists: bool,
    pub has_provider: bool,
}

pub fn plan_host(opts: PlanHostOptions<'_>) -> HostPlan {
    let PlanHostOptions {
        ctx,
        operation,
        redeploy,
        overwrite,
        convert_to,
        switch_action,
        home_manager: _home_manager,
        provider_exists,
        has_provider,
    } = opts;
    let mode = crate::operation::deploy::DeploymentMode::from_context(ctx, convert_to.is_some());
    let build_strategy = if operation == OperationKind::Deploy {
        if mode.uses_nix_build() {
            Some(crate::nix::NixBuilder::resolve(ctx, None).strategy)
        } else {
            None
        }
    } else {
        Some(crate::nix::NixBuilder::resolve(ctx, None).strategy)
    };

    let p_kind = provider_kind(
        has_provider,
        &ctx.deployment.proxmox.host,
        &ctx.deployment.vmware.vmx_path,
        &ctx.deployment.digitalocean.region,
    );

    let workspace_mode = if operation == OperationKind::Deploy {
        let install_ctx = if mode.uses_nix_build() {
            crate::context::resolve_install_context(ctx, &mode, convert_to)
                .unwrap_or_else(|_| ctx.clone())
        } else {
            ctx.clone()
        };
        if is_local_target(
            &install_ctx.hostname,
            &install_ctx.target_ip,
            &crate::fleet::local::current_local_hostname(),
        ) {
            WorkspaceMode::SingleHost
        } else {
            WorkspaceMode::CommonBasePerHost
        }
    } else if is_local_target(
        &ctx.hostname,
        &ctx.target_ip,
        &crate::fleet::local::current_local_hostname(),
    ) {
        WorkspaceMode::SingleHost
    } else {
        WorkspaceMode::CommonBasePerHost
    };

    let (risk, skip_reason) = calculate_host_risk(RiskAssessmentParams {
        operation,
        redeploy,
        overwrite,
        provider: p_kind,
        provider_exists,
        mode: &mode,
        is_convert: convert_to.is_some(),
        switch_action,
    });

    HostPlan {
        hostname: ctx.hostname.clone(),
        target_ip: ctx.target_ip.clone(),
        provider: p_kind,
        operation,
        workspace_mode,
        build_strategy,
        switch_action: switch_action.map(str::to_string),
        risk,
        skip_reason,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_plain_host_spec() {
        let spec = parse_host_spec("medo-test");

        assert_eq!(spec.hostname, "medo-test");
        assert_eq!(spec.username, None);
        assert_eq!(spec.ip, None);
    }

    #[test]
    fn parses_user_and_ip_host_spec() {
        let spec = parse_host_spec("nixos@medo-test=100.64.0.26");

        assert_eq!(spec.hostname, "medo-test");
        assert_eq!(spec.username.as_deref(), Some("nixos"));
        assert_eq!(spec.ip.as_deref(), Some("100.64.0.26"));
    }

    #[test]
    fn trims_host_spec_parts() {
        let spec = parse_host_spec(" deploy@ utils = 100.64.0.3 ");

        assert_eq!(spec.hostname, "utils");
        assert_eq!(spec.username.as_deref(), Some("deploy"));
        assert_eq!(spec.ip.as_deref(), Some("100.64.0.3"));
    }

    #[test]
    fn splits_hosts_list() {
        assert_eq!(
            split_hosts(" air15vm,utils, , medo-test "),
            vec!["air15vm", "utils", "medo-test"]
        );
    }

    #[test]
    fn detects_local_targets() {
        assert!(is_local_target("macair15-m2", "macair15-m2", "macair15-m2"));
        assert!(is_local_target("other", "127.0.0.1", "macair15-m2"));
        assert!(is_local_target("other", "localhost", "macair15-m2"));
        assert!(!is_local_target("medo-test", "100.64.0.26", "macair15-m2"));
    }

    #[test]
    fn selects_single_host_workspace_for_one_local_allowed_host() {
        assert_eq!(
            workspace_mode_for_hosts(1, true, true),
            WorkspaceMode::SingleHost
        );
    }

    #[test]
    fn selects_common_base_for_remote_or_multi_host_cases() {
        assert_eq!(
            workspace_mode_for_hosts(1, false, true),
            WorkspaceMode::CommonBasePerHost
        );
        assert_eq!(
            workspace_mode_for_hosts(2, true, true),
            WorkspaceMode::CommonBasePerHost
        );
        assert_eq!(
            workspace_mode_for_hosts(1, true, false),
            WorkspaceMode::CommonBasePerHost
        );
    }

    #[test]
    fn builds_run_plan_with_workspace_mode() {
        let plan = build_run_plan(OperationKind::Switch, vec!["local"], true, |host| {
            *host == "local"
        });

        assert_eq!(plan.operation, OperationKind::Switch);
        assert_eq!(plan.targets, vec!["local"]);
        assert_eq!(plan.workspace_mode, WorkspaceMode::SingleHost);

        let plan = build_run_plan(
            OperationKind::Deploy,
            vec!["local", "remote"],
            true,
            |host| *host == "local",
        );

        assert_eq!(plan.operation, OperationKind::Deploy);
        assert_eq!(plan.workspace_mode, WorkspaceMode::CommonBasePerHost);
    }

    #[test]
    fn classifies_provider_kind_by_metadata_priority() {
        assert_eq!(provider_kind(false, "pve", "", ""), ProviderKind::None);
        assert_eq!(
            provider_kind(true, "pve", "vm.vmx", "syd1"),
            ProviderKind::Proxmox
        );
        assert_eq!(
            provider_kind(true, "", "vm.vmx", "syd1"),
            ProviderKind::Vmware
        );
        assert_eq!(
            provider_kind(true, "", "", "syd1"),
            ProviderKind::DigitalOcean
        );
        assert_eq!(provider_kind(true, "", "", ""), ProviderKind::Detected);
    }
}
