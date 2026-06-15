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
	#[serde(default = "default_enable_local_cache")]
	pub enable_local_cache: bool,
	pub vmid: String,
	pub disk_size: String,
	pub tailscale_namespace: String,
	pub proxmox: ProxmoxConfig,
	pub digitalocean: DigitalOceanConfig,
	pub vmware: VmwareConfig,
	#[serde(default)]
	pub wsl: WslConfig,
}

fn default_enable_local_cache() -> bool {
	true
}

#[derive(Deserialize, Debug, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct ProxmoxBootstrapConfig {
	#[serde(default = "default_bootstrap_interface")]
	pub interface: String,
	#[serde(default)]
	pub static_ip: String,
	#[serde(default)]
	pub subnet: String,
	#[serde(default)]
	pub gateway: String,
	#[serde(default)]
	pub vlan: Option<u16>,
}

fn default_bootstrap_interface() -> String {
	"net0".to_string()
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
	pub net0: String,
	#[serde(default)]
	pub net1: String,
	#[serde(default)]
	pub bootstrap: ProxmoxBootstrapConfig,
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
	/// ISO type; only "qemu" is supported.
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

#[derive(Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct WslConfig {
	#[serde(default)]
	pub enable: bool,
	#[serde(default)]
	pub windows_host: String,
	#[serde(default)]
	pub windows_user: String,
	#[serde(default = "default_wsl_distribution")]
	pub distribution: String,
	#[serde(default)]
	pub install_root: String,
	#[serde(default = "default_wsl_bootstrap_user")]
	pub bootstrap_user: String,
	#[serde(default)]
	pub guest_host: String,
	#[serde(default = "default_wsl_transport")]
	pub transport: String,
}

impl Default for WslConfig {
	fn default() -> Self {
		Self {
			enable: false,
			windows_host: String::new(),
			windows_user: String::new(),
			distribution: default_wsl_distribution(),
			install_root: String::new(),
			bootstrap_user: default_wsl_bootstrap_user(),
			guest_host: String::new(),
			transport: default_wsl_transport(),
		}
	}
}

fn default_wsl_distribution() -> String {
	"NixOS".to_string()
}

fn default_wsl_bootstrap_user() -> String {
	"nixos".to_string()
}

fn default_wsl_transport() -> String {
	"auto".to_string()
}

#[derive(Deserialize, Debug, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct CrossConfig {
	#[serde(default)]
	pub local_system: Option<serde_json::Value>,
	#[serde(default)]
	pub cross_system: Option<serde_json::Value>,
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
	pub wsl: bool,
	#[serde(default)]
	pub role: Option<String>,
	#[serde(default)]
	pub tags: Vec<String>,
	#[serde(default)]
	pub cross: Option<CrossConfig>,
	#[serde(default)]
	pub features: Vec<serde_json::Value>,
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

	let mut args = vec!["eval", "--impure", "--json", "--expr", &expr];
	let token_args = crate::config::nix_token_args();
	let token_args_ref: Vec<&str> = token_args.iter().map(|s| s.as_str()).collect();
	args.extend(token_args_ref.iter());

	let output = Command::new("nix").args(&args).output()?;

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

	let hostnames_expr =
		hostnames.iter().map(|h| format!("\"{}\"", h)).collect::<Vec<String>>().join(" ");

	let raw_template = include_str!("../nix/eval_batch_hosts.template");
	let expr =
		raw_template.replace("@flake_ref@", &flake_ref).replace("@hostnames_expr@", &hostnames_expr);

	let mut args = vec!["eval", "--impure", "--json", "--expr", &expr];
	let token_args = crate::config::nix_token_args();
	let token_args_ref: Vec<&str> = token_args.iter().map(|s| s.as_str()).collect();
	args.extend(token_args_ref.iter());

	let output = Command::new("nix").args(&args).output()?;

	if !output.status.success() {
		let err_msg = String::from_utf8_lossy(&output.stderr);
		return Err(format!("Nix evaluation failed for batch hosts: {}", err_msg).into());
	}

	let raw_map: HashMap<String, Option<FlakeMetadata>> = serde_json::from_slice(&output.stdout)?;
	Ok(raw_map)
}
