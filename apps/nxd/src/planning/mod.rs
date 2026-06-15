pub mod plan_iso;
pub mod plan_local;
pub mod plan_render;
pub mod plan_risk;
pub mod plan_spec;

use crate::context::RuntimeContext;
use crate::nix::BuildStrategy;
pub use crate::providers::{ProviderKind, ProviderSnapshot};
pub use plan_local::{is_local_context, is_local_target};
pub use plan_render::{confirm_batch, provider_label};
pub use plan_risk::{OperationRisk, RiskAssessmentParams, calculate_host_risk};
pub use plan_spec::{HostSpec, parse_host_spec, split_hosts};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OperationKind {
	Deploy,
	Switch,
}

#[derive(Debug, Clone)]
pub struct HostPlan {
	pub hostname: String,
	pub target_ip: String,
	pub provider: Option<ProviderKind>,
	pub provider_state: Option<crate::providers::ProviderState>,
	pub operation: OperationKind,
	pub build_strategy: Option<BuildStrategy>,
	pub switch_action: Option<String>,
	pub risk: OperationRisk,
	pub skip_reason: Option<String>,
}

pub struct PlanHostOptions<'a> {
	pub ctx: &'a RuntimeContext,
	pub operation: OperationKind,
	pub redeploy: bool,
	pub overwrite: bool,
	pub switch_action: Option<&'a str>,
	pub home_manager: bool,
	pub provider: Option<ProviderSnapshot>,
}

pub fn plan_host(opts: PlanHostOptions<'_>) -> HostPlan {
	let PlanHostOptions {
		ctx,
		operation,
		redeploy,
		overwrite,
		switch_action,
		home_manager: _home_manager,
		provider,
	} = opts;
	let mode = crate::workflow::deploy::DeploymentMode::from_context(ctx, false);
	let build_strategy = if operation == OperationKind::Deploy {
		if mode.uses_nix_build() { Some(crate::nix::NixBuilder::resolve(ctx).strategy) } else { None }
	} else {
		Some(crate::nix::NixBuilder::resolve(ctx).strategy)
	};

	let p_kind = provider.map(|snapshot| snapshot.kind);
	let provider_exists =
		provider.is_some_and(|snapshot| snapshot.state != crate::providers::ProviderState::Missing);

	let (risk, skip_reason) = calculate_host_risk(RiskAssessmentParams {
		operation,
		redeploy,
		overwrite,
		provider: p_kind,
		provider_exists,
		mode: &mode,
		is_convert: false,
		switch_action,
		provider_capabilities: provider.map(|snapshot| snapshot.capabilities),
	});

	HostPlan {
		hostname: ctx.hostname.clone(),
		target_ip: ctx.target_ip.clone(),
		provider: p_kind,
		provider_state: provider.map(|snapshot| snapshot.state),
		operation,
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
		assert_eq!(split_hosts(" air15vm,utils, , medo-test "), vec!["air15vm", "utils", "medo-test"]);
	}

	#[test]
	fn detects_local_targets() {
		assert!(is_local_target("macair15-m2", "macair15-m2", "macair15-m2"));
		assert!(is_local_target("other", "127.0.0.1", "macair15-m2"));
		assert!(is_local_target("other", "localhost", "macair15-m2"));
		assert!(!is_local_target("medo-test", "100.64.0.26", "macair15-m2"));
	}
}
