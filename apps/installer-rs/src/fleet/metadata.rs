use serde::Deserialize;
use std::collections::HashMap;
use std::process::Command;

#[derive(Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct DeploymentConfig {
    pub target_ip: String,
    #[serde(default)]
    pub ssh_proxy_jump: String,
    pub builder: String,
    pub low_mem: String,
    #[serde(default)]
    pub substitute_on_destination: bool,
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
    pub disk_storage: String,
    pub network: String,
    #[serde(default)]
    pub extra_networks: Vec<String>,
    #[serde(default)]
    pub pxe: bool,
    pub cores: String,
    pub memory: String,
    pub iso: ProxmoxIsoConfig,
    pub cloud_init: CloudInitConfig,
}

#[derive(Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ProxmoxIsoConfig {
    /// "std" (default) or "vlan"
    #[serde(rename = "type")]
    pub flavor: String,
    pub storage: String,
    /// Full Proxmox storage path override, e.g. "arthurz2-dir:iso/my.iso". Empty = use type.
    pub custom_path: String,
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

fn default_build_system() -> bool {
    true
}

#[derive(Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct FlakeMetadata {
    pub deployment: DeploymentConfig,
    pub system: String,
    pub user: String,
    pub has_disko: bool,
    #[serde(default = "default_build_system")]
    pub build_system: bool,
    #[serde(default)]
    pub role: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
}

pub fn load_full_inventory() -> Result<HashMap<String, FlakeMetadata>, Box<dyn std::error::Error>> {
    let mut flake_ref = crate::config::flake_uri();
    if flake_ref == "path:." || flake_ref == "." {
        if let Ok(current_dir) = std::env::current_dir() {
            flake_ref = format!("path:{}", current_dir.to_string_lossy());
        }
    } else if flake_ref.starts_with("path:") {
        let path_part = &flake_ref[5..];
        if let Ok(abs_path) = std::fs::canonicalize(path_part) {
            flake_ref = format!("path:{}", abs_path.to_string_lossy());
        }
    }

    let expr = format!(
        r#"let flake = builtins.getFlake "{}"; in if flake ? deploymentHosts then flake.deploymentHosts else {{}}"#,
        flake_ref
    );

    let output = Command::new("nix")
        .args(["eval", "--impure", "--json", "--expr", &expr])
        .output()?;

    if !output.status.success() {
        let err_msg = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Nix evaluation failed for full inventory: {}", err_msg).into());
    }

    let raw_map: HashMap<String, FlakeMetadata> = serde_json::from_slice(&output.stdout)?;
    Ok(raw_map)
}

pub fn load_batch_metadata(
    hostnames: &[String],
) -> Result<HashMap<String, Option<FlakeMetadata>>, Box<dyn std::error::Error>> {
    let mut flake_ref = crate::config::flake_uri();
    if flake_ref == "path:." || flake_ref == "." {
        if let Ok(current_dir) = std::env::current_dir() {
            flake_ref = format!("path:{}", current_dir.to_string_lossy());
        }
    } else if flake_ref.starts_with("path:") {
        let path_part = &flake_ref[5..];
        if let Ok(abs_path) = std::fs::canonicalize(path_part) {
            flake_ref = format!("path:{}", abs_path.to_string_lossy());
        }
    }

    let hostnames_expr = hostnames
        .iter()
        .map(|h| format!("\"{}\"", h))
        .collect::<Vec<String>>()
        .join(" ");

    let raw_template = include_str!("../nix/eval_batch_hosts.template");
    let expr = raw_template
        .replace("@flake_ref@", &flake_ref)
        .replace("@hostnames_expr@", &hostnames_expr);

    let output = Command::new("nix")
        .args(["eval", "--impure", "--json", "--expr", &expr])
        .output()?;

    if !output.status.success() {
        let err_msg = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Nix evaluation failed for batch hosts: {}", err_msg).into());
    }

    let raw_map: HashMap<String, Option<FlakeMetadata>> = serde_json::from_slice(&output.stdout)?;
    Ok(raw_map)
}
