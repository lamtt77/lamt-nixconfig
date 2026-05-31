use serde::Deserialize;
use std::process::Command;

#[derive(Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct DeploymentConfig {
    pub target_ip: String,
    pub builder: String,
    pub low_mem: String,
    pub vmid: String,
    pub disk_size: String,
    pub tailscale_namespace: String,
    pub proxmox: ProxmoxConfig,
    pub digitalocean: DigitalOceanConfig,
    pub vmware: VmwareConfig,
}

#[derive(Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ProxmoxConfig {
    pub host: String,
    pub bios: String,
    pub disk_bus: String,
    pub scsi_hw: String,
    pub cores: String,
    pub memory: String,
    pub cloud_init: CloudInitConfig,
}

#[derive(Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct CloudInitConfig {
    pub image: String,
    pub user: String,
    pub ipconfig0: String,
    pub ipconfig1: String,
}

#[derive(Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct DigitalOceanConfig {
    pub region: String,
    pub size: String,
    pub image: String,
}

#[derive(Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct VmwareConfig {
    pub vmx_path: String,
}

#[derive(Deserialize, Debug, Clone)]
pub struct FlakeMetadata {
    pub deployment: DeploymentConfig,
    pub system: String,
    pub user: String,
}

#[derive(Debug, Clone)]
pub struct RuntimeContext {
    pub hostname: String,
    pub target_ip: String,
    pub username: String,
    pub system: String,
    pub deployment: DeploymentConfig,
    pub is_ip_overridden: bool,
}

impl RuntimeContext {
    pub fn load(hostname: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let apply_expr = "c: { deployment = c.deployment; user = c.user; system = let sys = builtins.tryEval c.nixpkgs.hostPlatform.system; in if sys.success then sys.value else \"\"; }";
        let target_attr = format!("path:.#nixosConfigurations.{}.config", hostname);

        let output = Command::new("nix")
            .args(&[
                "eval",
                "--json",
                &target_attr,
                "--apply",
                apply_expr,
            ])
            .output()?;

        if !output.status.success() {
            let err_msg = String::from_utf8_lossy(&output.stderr);
            return Err(format!("Nix evaluation failed for target {}: {}", hostname, err_msg).into());
        }

        let mut metadata: FlakeMetadata = serde_json::from_slice(&output.stdout)?;

        // Resolve target IP. If empty in config, default to hostname.
        let target_ip = if metadata.deployment.target_ip.is_empty() {
            hostname.to_string()
        } else {
            metadata.deployment.target_ip.clone()
        };

        // Override settings with environment variables if set via command-line flags
        if let Ok(builder_override) = std::env::var("BUILDER") {
            if !builder_override.is_empty() {
                metadata.deployment.builder = builder_override;
            }
        }
        if let Ok(low_mem_override) = std::env::var("LOW_MEM") {
            if !low_mem_override.is_empty() {
                metadata.deployment.low_mem = low_mem_override;
            }
        }

        Ok(RuntimeContext {
            hostname: hostname.to_string(),
            target_ip,
            username: metadata.user.clone(),
            system: metadata.system.clone(),
            deployment: metadata.deployment,
            is_ip_overridden: false,
        })
    }
}
