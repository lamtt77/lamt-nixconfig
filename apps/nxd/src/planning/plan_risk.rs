use super::OperationKind;
use crate::providers::{ProviderCapabilities, ProviderKind};
use crate::workflow::deploy::DeploymentMode;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OperationRisk {
	Low,
	Medium,
	High,
}

pub struct RiskAssessmentParams<'a> {
	pub operation: OperationKind,
	pub redeploy: bool,
	pub overwrite: bool,
	pub provider: Option<ProviderKind>,
	pub provider_exists: bool,
	pub mode: &'a DeploymentMode,
	pub is_convert: bool,
	pub switch_action: Option<&'a str>,
	pub provider_capabilities: Option<ProviderCapabilities>,
}

pub fn calculate_host_risk(params: RiskAssessmentParams<'_>) -> (OperationRisk, Option<String>) {
	let RiskAssessmentParams {
		operation,
		redeploy,
		overwrite,
		provider,
		provider_exists,
		mode,
		is_convert,
		switch_action,
		provider_capabilities,
	} = params;
	let mut risk = OperationRisk::Low;
	let mut skip_reason = None;

	match operation {
		OperationKind::Deploy => {
			if redeploy {
				risk = OperationRisk::High;
			} else if provider.is_some() && provider_exists {
				if is_convert {
					risk = OperationRisk::Medium;
				} else if overwrite {
					if provider_capabilities
						.is_some_and(|capabilities| capabilities.requires_bootstrap_artifact)
					{
						risk = OperationRisk::Medium;
					} else if mode.is_destructive() {
						risk = OperationRisk::High;
					} else {
						risk = OperationRisk::Medium;
					}
				} else {
					let resource = if provider == Some(ProviderKind::Wsl) {
						"WSL distribution"
					} else {
						"provider instance"
					};
					skip_reason = Some(format!(
						"Host {} already exists. Use --overwrite to converge it in place, or --redeploy to recreate it.",
						resource
					));
				}
			} else if provider_capabilities
				.is_some_and(|capabilities| capabilities.requires_bootstrap_artifact)
			{
				risk = OperationRisk::Medium;
			} else if mode.is_destructive() {
				risk = OperationRisk::High;
			} else {
				risk = OperationRisk::Medium;
			}
		}
		OperationKind::Switch => {
			if matches!(switch_action, Some("switch" | "bootentry")) {
				risk = OperationRisk::Medium;
			}
		}
	}

	(risk, skip_reason)
}

#[cfg(test)]
mod tests {
	use super::*;

	fn wsl_capabilities() -> ProviderCapabilities {
		ProviderCapabilities { requires_bootstrap_artifact: true, supports_recreate: true }
	}

	fn mode() -> DeploymentMode {
		DeploymentMode::NixosInstall { initial_user: "root".to_string() }
	}

	#[test]
	fn missing_wsl_provider_plans_create_without_bare_metal_risk() {
		let deployment_mode = mode();
		let (risk, skip) = calculate_host_risk(RiskAssessmentParams {
			operation: OperationKind::Deploy,
			redeploy: false,
			overwrite: false,
			provider: Some(ProviderKind::Wsl),
			provider_exists: false,
			mode: &deployment_mode,
			is_convert: false,
			switch_action: None,
			provider_capabilities: Some(wsl_capabilities()),
		});
		assert_eq!(risk, OperationRisk::Medium);
		assert_eq!(skip, None);
	}

	#[test]
	fn existing_wsl_provider_skips_without_explicit_policy() {
		let deployment_mode = mode();
		let (_, skip) = calculate_host_risk(RiskAssessmentParams {
			operation: OperationKind::Deploy,
			redeploy: false,
			overwrite: false,
			provider: Some(ProviderKind::Wsl),
			provider_exists: true,
			mode: &deployment_mode,
			is_convert: false,
			switch_action: None,
			provider_capabilities: Some(wsl_capabilities()),
		});
		assert!(skip.is_some());
	}

	#[test]
	fn wsl_redeploy_is_high_risk() {
		let deployment_mode = mode();
		let (risk, skip) = calculate_host_risk(RiskAssessmentParams {
			operation: OperationKind::Deploy,
			redeploy: true,
			overwrite: false,
			provider: Some(ProviderKind::Wsl),
			provider_exists: true,
			mode: &deployment_mode,
			is_convert: false,
			switch_action: None,
			provider_capabilities: Some(wsl_capabilities()),
		});
		assert_eq!(risk, OperationRisk::High);
		assert_eq!(skip, None);
	}

	#[test]
	fn wsl_overwrite_is_in_place_medium_risk() {
		let deployment_mode = mode();
		let (risk, skip) = calculate_host_risk(RiskAssessmentParams {
			operation: OperationKind::Deploy,
			redeploy: false,
			overwrite: true,
			provider: Some(ProviderKind::Wsl),
			provider_exists: true,
			mode: &deployment_mode,
			is_convert: false,
			switch_action: None,
			provider_capabilities: Some(wsl_capabilities()),
		});
		assert_eq!(risk, OperationRisk::Medium);
		assert_eq!(skip, None);
	}
}
