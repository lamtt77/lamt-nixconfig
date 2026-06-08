use crate::operation::deploy::DeploymentMode;
use crate::plan::{OperationKind, ProviderKind};

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
    pub provider: ProviderKind,
    pub provider_exists: bool,
    pub mode: &'a DeploymentMode,
    pub is_convert: bool,
    pub switch_action: Option<&'a str>,
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
    } = params;
    let mut risk = OperationRisk::Low;
    let mut skip_reason = None;

    match operation {
        OperationKind::Deploy => {
            if redeploy {
                risk = OperationRisk::High;
            } else if provider != ProviderKind::None && provider_exists {
                if is_convert {
                    risk = OperationRisk::Medium;
                } else if overwrite {
                    if mode.is_destructive() {
                        risk = OperationRisk::High;
                    } else {
                        risk = OperationRisk::Medium;
                    }
                } else {
                    skip_reason = Some("Host VM/Droplet already exists. Use --overwrite to reinstall, or --redeploy to recreate.".to_string());
                }
            } else if mode.is_destructive() {
                risk = OperationRisk::High;
            } else {
                risk = OperationRisk::Medium;
            }
        }
        OperationKind::Switch => {
            if let Some(act) = switch_action {
                if act == "switch" || act == "bootentry" {
                    risk = OperationRisk::Medium;
                }
            }
        }
    }

    (risk, skip_reason)
}
