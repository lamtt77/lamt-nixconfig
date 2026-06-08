use crate::context::RuntimeContext;

use super::plan::{HostPlan, OperationKind, OperationRisk, ProviderKind};

impl HostPlan {
    pub fn render(&self, ctx: &RuntimeContext, convert_to: Option<&String>) {
        let mode =
            crate::operation::deploy::DeploymentMode::from_context(ctx, convert_to.is_some());
        let install_ctx = if self.operation == OperationKind::Deploy && mode.uses_nix_build() {
            crate::context::resolve_install_context(ctx, &mode, convert_to)
                .unwrap_or_else(|_| ctx.clone())
        } else {
            ctx.clone()
        };
        let provider_name = provider_label(self.provider);
        let strategy_name = self
            .build_strategy
            .as_ref()
            .map(|s| s.label())
            .unwrap_or_else(|| "N/A".to_string());

        println!("Host: {}", self.hostname);
        match self.operation {
            OperationKind::Deploy => {
                println!("  Mode:        {}", mode.label());
                if install_ctx.hostname != ctx.hostname {
                    println!("  Convert To:  {}", install_ctx.hostname);
                }
                println!("  Initial SSH: {}@{}", mode.initial_user(), ctx.target_ip);
                println!("  Target IP:   {}", ctx.target_ip);
                println!("  Provider:    {}", provider_name);
                if let Some(ref reason) = self.skip_reason {
                    println!("  Action:      SKIP ({})", reason);
                } else {
                    let action = match self.risk {
                        OperationRisk::High => "destroy/overwrite and install NixOS",
                        OperationRisk::Medium => "create/convert and verify/install",
                        OperationRisk::Low => "deploy target",
                    };
                    println!("  Action:      {}", action);
                }
                println!("  Build On:    {}", strategy_name);
                let low_mem = if !mode.uses_nix_build() {
                    "N/A".to_string()
                } else if install_ctx.deployment.low_mem.is_empty() {
                    "no".to_string()
                } else {
                    install_ctx.deployment.low_mem.clone()
                };
                println!("  Low Memory:  {}", low_mem);

                if !ctx.deployment.proxmox.cores.is_empty() {
                    println!("  CPU Cores:   {}", ctx.deployment.proxmox.cores);
                }
                if !ctx.deployment.proxmox.memory.is_empty() {
                    println!("  RAM Memory:  {} MB", ctx.deployment.proxmox.memory);
                }
                if !ctx.deployment.disk_size.is_empty() {
                    println!("  Disk Size:   {} GB", ctx.deployment.disk_size);
                }
                if !ctx.deployment.digitalocean.size.is_empty() {
                    println!("  DO Size:     {}", ctx.deployment.digitalocean.size);
                }
                if !ctx.deployment.digitalocean.region.is_empty() {
                    println!("  DO Region:   {}", ctx.deployment.digitalocean.region);
                }
            }
            OperationKind::Switch => {
                println!("  Target IP:   {}", ctx.target_ip);
                println!("  Provider:    {}", provider_name);
                println!("  Build On:    {}", strategy_name);
                let action = self
                    .switch_action
                    .as_deref()
                    .unwrap_or("switch")
                    .to_string();
                println!("  Action:      {}", action);
            }
        }
        println!("  Risk Level:  {:?}", self.risk);
        println!("----------------------------------------------------");
    }
}

pub fn provider_label(kind: ProviderKind) -> &'static str {
    match kind {
        ProviderKind::None => "None (Standard)",
        ProviderKind::Proxmox => "Proxmox VM",
        ProviderKind::Vmware => "VMware VM",
        ProviderKind::DigitalOcean => "DigitalOcean",
        ProviderKind::Detected => "Detected Virtualization",
    }
}

pub fn provider_label_for_context(ctx: &RuntimeContext, has_provider: bool) -> &'static str {
    let kind = super::plan::provider_kind(
        has_provider,
        &ctx.deployment.proxmox.host,
        &ctx.deployment.vmware.vmx_path,
        &ctx.deployment.digitalocean.region,
    );
    provider_label(kind)
}

pub fn confirm_batch(plans: &[HostPlan], force: bool) -> Result<bool, Box<dyn std::error::Error>> {
    let mut has_high_risk = false;
    let mut has_skipped = false;
    let mut skipped_hosts = Vec::new();
    let mut high_risk_hosts = Vec::new();

    for plan in plans {
        if plan.skip_reason.is_some() {
            has_skipped = true;
            skipped_hosts.push(plan.hostname.clone());
        }
        if plan.risk == OperationRisk::High {
            has_high_risk = true;
            high_risk_hosts.push(plan.hostname.clone());
        }
    }

    if has_skipped {
        println!(
            "Warning: The following hosts will be SKIPPED by default: {:?}",
            skipped_hosts
        );
        println!(
            "Use --overwrite to reinstall them in place, or --redeploy to destroy and recreate provider instances."
        );
    }

    let operation_name = if plans.is_empty() {
        "operation"
    } else {
        match plans[0].operation {
            OperationKind::Deploy => "deployment",
            OperationKind::Switch => "switch",
        }
    };

    if force {
        if has_high_risk {
            crate::progress::log::ProgressEvent::new(
                crate::progress::log::StatusLevel::Warning,
                None,
                format!("High-risk operations detected for: {:?}", high_risk_hosts),
            )
            .log(crate::progress::color::ColorMode::Auto);
        }
        println!("Non-interactive mode active (CLI_FORCE=yes). Auto-confirming execution.");
        return Ok(true);
    }

    let prompt = if has_high_risk {
        format!(
            "High-risk actions (destroy/overwrite/NixOS install) detected for {:?}.\nAre you sure you want to proceed with batch {}?",
            high_risk_hosts, operation_name
        )
    } else {
        format!(
            "Are you sure you want to proceed with batch {} for {} hosts?",
            operation_name,
            plans.len()
        )
    };

    let confirmed = dialoguer::Confirm::new()
        .with_prompt(&prompt)
        .default(false)
        .interact()
        .unwrap_or(false);

    Ok(confirmed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_provider_labels() {
        assert_eq!(provider_label(ProviderKind::None), "None (Standard)");
        assert_eq!(provider_label(ProviderKind::Proxmox), "Proxmox VM");
        assert_eq!(provider_label(ProviderKind::Vmware), "VMware VM");
        assert_eq!(provider_label(ProviderKind::DigitalOcean), "DigitalOcean");
        assert_eq!(
            provider_label(ProviderKind::Detected),
            "Detected Virtualization"
        );
    }
}
