use crate::process::Logger;

pub use crate::fleet::metadata::{
	CloudInitConfig, CrossConfig, DeploymentConfig, DigitalOceanConfig, FlakeMetadata, ProxmoxConfig,
	VmwareConfig, WslConfig,
};

#[derive(Debug, Clone)]
pub struct RuntimeContext {
	pub hostname: String,
	pub target_ip: String,
	pub username: String,
	pub system: String,
	pub deployment: DeploymentConfig,
	pub is_ip_overridden: bool,
	pub flake_ref: String,
	pub source_store_path: Option<String>,
	pub secret_store_path: Option<String>,
	pub has_disko: bool,
	pub build_system: bool,
	pub wsl: bool,
	pub role: Option<String>,
	pub tags: Vec<String>,
	pub cross: Option<CrossConfig>,
	pub features: Vec<serde_json::Value>,
}

fn get_context_cache()
-> &'static std::sync::Mutex<std::collections::HashMap<String, RuntimeContext>> {
	static CACHE: std::sync::OnceLock<
		std::sync::Mutex<std::collections::HashMap<String, RuntimeContext>>,
	> = std::sync::OnceLock::new();
	CACHE.get_or_init(|| std::sync::Mutex::new(std::collections::HashMap::new()))
}

impl RuntimeContext {
	pub fn load(hostname: &str) -> Result<Self, Box<dyn std::error::Error>> {
		let mut batch = Self::load_batch(&[hostname.to_string()])?;
		batch
			.remove(hostname)
			.ok_or_else(|| format!("Configuration for '{}' not found", hostname).into())
	}

	#[cfg(test)]
	pub fn clear_cache() {
		get_context_cache().lock().unwrap().clear();
	}

	pub fn load_batch(
		hostnames: &[String],
	) -> Result<std::collections::HashMap<String, Self>, Box<dyn std::error::Error>> {
		if hostnames.is_empty() {
			return Ok(std::collections::HashMap::new());
		}

		let mut result = std::collections::HashMap::new();
		let mut to_load = Vec::new();

		{
			let cache = get_context_cache().lock().unwrap();
			for hostname in hostnames {
				if let Some(ctx) = cache.get(hostname) {
					result.insert(hostname.clone(), ctx.clone());
				} else {
					to_load.push(hostname.clone());
				}
			}
		}

		if to_load.is_empty() {
			return Ok(result);
		}

		let loaded = Self::load_batch_uncached(&to_load)?;

		{
			let mut cache = get_context_cache().lock().unwrap();
			for (hostname, ctx) in loaded {
				cache.insert(hostname.clone(), ctx.clone());
				result.insert(hostname, ctx);
			}
		}

		Ok(result)
	}

	fn load_batch_uncached(
		hostnames: &[String],
	) -> Result<std::collections::HashMap<String, Self>, Box<dyn std::error::Error>> {
		let raw_map = crate::fleet::metadata::load_batch_metadata(hostnames)?;
		let flake_ref = crate::config::flake_uri();

		let mut result = std::collections::HashMap::new();
		for hostname in hostnames {
			let Some(maybe_meta) = raw_map.get(hostname) else {
				return Err(format!("Host '{}' not found in Nix evaluation results", hostname).into());
			};
			let Some(metadata) = maybe_meta else {
				return Err(
					format!(
						"Host '{}' was not found in nixosConfigurations or darwinConfigurations",
						hostname
					)
					.into(),
				);
			};

			let target_ip = if metadata.deployment.target_ip.is_empty() {
				hostname.clone()
			} else {
				metadata.deployment.target_ip.clone()
			};

			let mut final_deployment = metadata.deployment.clone();
			let runtime_options = crate::config::get_runtime_options();
			if let Some(builder_override) = runtime_options.builder.as_ref()
				&& !builder_override.is_empty()
			{
				final_deployment.builder = builder_override.clone();
			}
			if let Some(low_mem_override) = runtime_options.low_mem {
				final_deployment.low_mem = if low_mem_override { "yes" } else { "no" }.to_string();
			}
			if !final_deployment.proxmox.bootstrap.subnet.is_empty()
				&& final_deployment.proxmox.bootstrap.static_ip.is_empty()
			{
				final_deployment.proxmox.bootstrap.static_ip = target_ip.clone();
			}

			let ctx = RuntimeContext {
				hostname: hostname.clone(),
				target_ip,
				username: metadata.user.clone(),
				system: metadata.system.clone(),
				deployment: final_deployment,
				is_ip_overridden: false,
				flake_ref: flake_ref.clone(),
				source_store_path: None,
				secret_store_path: None,
				has_disko: metadata.has_disko,
				build_system: metadata.build_system,
				wsl: metadata.wsl,
				role: metadata.role.clone(),
				tags: metadata.tags.clone(),
				cross: metadata.cross.clone(),
				features: metadata.features.clone(),
			};
			ctx.validate()?;
			result.insert(hostname.clone(), ctx);
		}

		Ok(result)
	}

	pub fn validate(&self) -> Result<(), Box<dyn std::error::Error>> {
		// 1. Hostname validation
		if self.hostname.is_empty() {
			return Err("Hostname cannot be empty".into());
		}
		if !self.hostname.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '.' || c == '_')
		{
			return Err(format!("Invalid characters in hostname '{}'", self.hostname).into());
		}

		// 2. Username validation
		if self.username.is_empty() {
			return Err("Username cannot be empty".into());
		}
		if !self.username.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-') {
			return Err(format!("Invalid characters in username '{}'", self.username).into());
		}

		// 3. System (Target Architecture) validation
		if self.system.is_empty() {
			return Err("System architecture cannot be empty".into());
		}
		let valid_systems = ["x86_64-linux", "aarch64-linux", "x86_64-darwin", "aarch64-darwin"];
		if !valid_systems.contains(&self.system.as_str()) {
			return Err(format!("Unsupported system architecture '{}'", self.system).into());
		}

		// 4. Proxmox VMID validation
		if !self.deployment.vmid.is_empty() && self.deployment.vmid.parse::<u32>().is_err() {
			return Err(
				format!("Proxmox VMID must be a valid integer, found '{}'", self.deployment.vmid).into(),
			);
		}

		// 5. Target IP validation (can be IP address or hostname)
		if self.target_ip.is_empty() {
			return Err("Target IP/hostname cannot be empty".into());
		}
		if !self.target_ip.chars().all(|c| {
			c.is_ascii_alphanumeric() || c == '-' || c == '.' || c == '_' || c == ':' || c == '/'
		}) {
			return Err(format!("Invalid characters in target IP/hostname '{}'", self.target_ip).into());
		}

		// 6. Cross build validation
		let runtime_options = crate::config::get_runtime_options();
		if let Some(ref build_strategy) = runtime_options.build_strategy
			&& build_strategy == "cross"
		{
			if self.system.contains("darwin") {
				return Err(
					format!(
						"Cross strategy is not supported on Darwin hosts: target system is '{}'",
						self.system
					)
					.into(),
				);
			}
			if self.cross.is_none() {
				return Err(
					format!(
						"Cross strategy requested for host '{}' but its metadata has no 'cross' configuration",
						self.hostname
					)
					.into(),
				);
			}
		}

		// 7. Proxmox bootstrap validation
		if !self.deployment.proxmox.bootstrap.static_ip.is_empty() {
			let iface = &self.deployment.proxmox.bootstrap.interface;
			if iface != "net0" && iface != "net1" {
				return Err(
					format!(
						"Unsupported bootstrap interface '{}'; only 'net0' and 'net1' are supported",
						iface
					)
					.into(),
				);
			}
			if iface == "net1"
				&& self.deployment.proxmox.net1.is_empty()
				&& self.deployment.proxmox.extra_networks.is_empty()
			{
				return Err(
					"Bootstrap interface is set to 'net1' but net1 and extraNetworks are empty".into(),
				);
			}
		}

		// 8. WSL provider validation
		if self.wsl && !self.deployment.wsl.enable {
			return Err(
				"WSL host requires deployment.wsl.enable and Windows control-plane metadata".into(),
			);
		}
		if self.deployment.wsl.enable {
			let wsl = &self.deployment.wsl;
			if !self.wsl {
				return Err("deployment.wsl.enable requires the host's top-level wsl flag".into());
			}
			if self.system != "x86_64-linux" {
				return Err("WSL provider currently supports only x86_64-linux targets".into());
			}
			if self.has_disko {
				return Err("WSL provider targets must set hasDisko = false".into());
			}
			for (name, value) in [
				("windowsHost", wsl.windows_host.as_str()),
				("windowsUser", wsl.windows_user.as_str()),
				("distribution", wsl.distribution.as_str()),
				("installRoot", wsl.install_root.as_str()),
			] {
				if value.trim().is_empty() {
					return Err(format!("deployment.wsl.{} is required when WSL is enabled", name).into());
				}
			}
			if !matches!(wsl.transport.as_str(), "auto" | "direct" | "windows") {
				return Err(format!("Unsupported deployment.wsl.transport '{}'", wsl.transport).into());
			}
			let conflicting_providers = [
				!self.deployment.proxmox.host.is_empty() || !self.deployment.vmid.is_empty(),
				!self.deployment.vmware.vmx_path.is_empty(),
				!self.deployment.digitalocean.region.is_empty(),
			]
			.into_iter()
			.filter(|configured| *configured)
			.count();
			if conflicting_providers > 0 {
				return Err("WSL provider metadata cannot coexist with another provider".into());
			}
		}

		Ok(())
	}
}

pub fn update_cached_context(ctx: &RuntimeContext) {
	if let Ok(mut cache) = get_context_cache().lock() {
		cache.insert(ctx.hostname.clone(), ctx.clone());
	}
}

pub fn parse_host_spec(spec: &str) -> (String, Option<String>, Option<String>) {
	let parsed = crate::planning::parse_host_spec(spec);
	(parsed.hostname, parsed.username, parsed.ip)
}

pub fn load_context_from_spec(spec: &str) -> Result<RuntimeContext, Box<dyn std::error::Error>> {
	let (hostname, username_override, ip_override) = parse_host_spec(spec);
	let mut ctx = RuntimeContext::load(&hostname)?;
	if let Some(ip) = ip_override {
		ctx.target_ip = ip;
		ctx.is_ip_overridden = true;
	} else if hostname == crate::fleet::local::current_local_hostname() && ctx.target_ip == hostname {
		ctx.target_ip = "127.0.0.1".to_string();
		ctx.is_ip_overridden = true;
	}
	if let Some(username) = username_override {
		if username != ctx.username && username != "root" {
			let is_forced = crate::config::get_runtime_options().force;
			if !is_forced {
				eprintln!(
					"WARNING: Specified username '{}' does not match the user '{}' configured in the NixOS flake for host '{}'.",
					username, ctx.username, hostname
				);
				if !dialoguer::Confirm::new()
					.with_prompt("Do you want to proceed anyway?")
					.default(false)
					.interact()
					.unwrap_or(false)
				{
					return Err("Aborted due to username mismatch.".into());
				}
			}
		}
		ctx.username = username;
	}
	Ok(ctx)
}

pub fn load_batch_contexts(
	host_list: &[String],
	validate_host_keys: bool,
) -> Result<Vec<RuntimeContext>, Box<dyn std::error::Error>> {
	let host_specs: Vec<_> = host_list.iter().map(|spec| parse_host_spec(spec)).collect();
	let hostnames: Vec<String> = host_specs.iter().map(|s| s.0.clone()).collect();

	println!("Loading configurations for {} targets...", hostnames.len());
	let mut batch_contexts = RuntimeContext::load_batch(&hostnames)?;

	let mut planned_hosts = Vec::new();
	for (host_spec_str, (hostname, username_override, ip_override)) in
		host_list.iter().zip(host_specs)
	{
		let mut ctx = batch_contexts
			.remove(&hostname)
			.ok_or_else(|| format!("Error: context for {} not found in batch results", hostname))?;

		if let Some(ip) = ip_override {
			ctx.target_ip = ip;
			ctx.is_ip_overridden = true;
		} else if hostname == crate::fleet::local::current_local_hostname() && ctx.target_ip == hostname
		{
			ctx.target_ip = "127.0.0.1".to_string();
			ctx.is_ip_overridden = true;
		}

		if let Some(username) = username_override {
			if username != ctx.username && username != "root" {
				let is_forced = crate::config::get_runtime_options().force;
				let warning = format!(
					"WARNING: Specified username '{}' does not match the user '{}' configured in the NixOS flake for host '{}'.",
					username, ctx.username, hostname
				);
				if !crate::workflow::confirm::confirm_action(
					"Do you want to proceed anyway?",
					Some(&warning),
					is_forced,
				)
				.unwrap_or(false)
				{
					return Err("Aborted due to username mismatch.".into());
				}
			}
			ctx.username = username;
		}

		let logger = Logger::terminal();
		ctx.target_ip = crate::fleet::resolution::resolve_target_ip(&ctx, logger.clone());

		if validate_host_keys && !ctx.wsl && !crate::fleet::local::is_local_target(&ctx) {
			crate::identity::ssh::validate_and_sync_target_host_key(&ctx, logger.clone()).map_err(
				|e| format!("Error validating/syncing target host key for {}: {}", host_spec_str, e),
			)?;
		}

		planned_hosts.push(ctx);
	}

	Ok(planned_hosts)
}

pub fn create_adhoc_context(
	hostname: &str,
	username: Option<&str>,
	ip: Option<&str>,
) -> RuntimeContext {
	let target_ip = ip.unwrap_or(hostname).to_string();
	let initial_ssh_user = username.unwrap_or("ubuntu").to_string();

	RuntimeContext {
		hostname: hostname.to_string(),
		target_ip: target_ip.clone(),
		username: initial_ssh_user.clone(),
		system: "x86_64-linux".to_string(),
		deployment: DeploymentConfig {
			target_ip: target_ip.clone(),
			ssh_proxy_jump: String::new(),
			builder: String::new(),
			low_mem: String::new(),
			substitute_on_destination: false,
			enable_local_cache: true,
			vmid: String::new(),
			disk_size: String::new(),
			tailscale_namespace: String::new(),
			proxmox: ProxmoxConfig {
				host: String::new(),
				bios: String::new(),
				disk_bus: String::new(),
				scsi_hw: String::new(),
				disk_storage: String::new(),
				network: String::new(),
				net0: String::new(),
				net1: String::new(),
				bootstrap: Default::default(),
				extra_networks: Vec::new(),
				pxe: false,
				cores: String::new(),
				memory: String::new(),
				iso: crate::fleet::metadata::ProxmoxIsoConfig {
					flavor: "std".to_string(),
					storage: String::new(),
					custom_path: String::new(),
				},
				cloud_init: CloudInitConfig {
					image: String::new(),
					user: initial_ssh_user,
					ipconfig0: String::new(),
					ipconfig1: String::new(),
				},
			},
			digitalocean: DigitalOceanConfig {
				region: String::new(),
				size: String::new(),
				image: String::new(),
			},
			vmware: VmwareConfig { vmx_path: String::new() },
			wsl: Default::default(),
		},
		is_ip_overridden: true,
		flake_ref: crate::config::flake_uri(),
		source_store_path: None,
		secret_store_path: None,
		has_disko: false,
		build_system: false,
		wsl: false,
		role: None,
		tags: Vec::new(),
		cross: None,
		features: Vec::new(),
	}
}

pub fn find_proxy_jump_for_ip(host_or_ip: &str) -> Option<String> {
	if let Ok(cache) = get_context_cache().lock() {
		for ctx in cache.values() {
			if (ctx.target_ip == host_or_ip || ctx.hostname == host_or_ip)
				&& !ctx.deployment.ssh_proxy_jump.is_empty()
			{
				return Some(ctx.deployment.ssh_proxy_jump.clone());
			}
		}
	}
	None
}

pub fn find_vmid_for_proxy_jump(proxy_jump: &str) -> Option<String> {
	if proxy_jump.is_empty() {
		return None;
	}
	// Parse user@host or just host
	let host_part = if let Some((_, host)) = proxy_jump.split_once('@') { host } else { proxy_jump };

	// First try the thread-local/global cache of loaded contexts
	if let Ok(cache) = get_context_cache().lock() {
		for ctx in cache.values() {
			if (ctx.hostname == host_part || ctx.target_ip == host_part)
				&& !ctx.deployment.vmid.is_empty()
			{
				return Some(ctx.deployment.vmid.clone());
			}
		}
	}

	// Fall back to loading full inventory to look up the host
	if let Ok(inventory) = crate::fleet::metadata::load_full_inventory() {
		for (hostname, meta) in inventory {
			if (hostname == host_part || meta.deployment.target_ip == host_part)
				&& !meta.deployment.vmid.is_empty()
			{
				return Some(meta.deployment.vmid.clone());
			}
		}
	}

	None
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::context::{
		CloudInitConfig, DeploymentConfig, DigitalOceanConfig, ProxmoxConfig, VmwareConfig,
	};

	fn make_test_ctx(
		hostname: &str,
		username: &str,
		system: &str,
		vmid: &str,
		target_ip: &str,
	) -> RuntimeContext {
		RuntimeContext {
			hostname: hostname.to_string(),
			target_ip: target_ip.to_string(),
			username: username.to_string(),
			system: system.to_string(),
			deployment: DeploymentConfig {
				target_ip: target_ip.to_string(),
				ssh_proxy_jump: String::new(),
				builder: String::new(),
				low_mem: String::new(),
				substitute_on_destination: false,
				enable_local_cache: true,
				vmid: vmid.to_string(),
				disk_size: String::new(),
				tailscale_namespace: String::new(),
				proxmox: ProxmoxConfig {
					host: String::new(),
					bios: String::new(),
					disk_bus: String::new(),
					scsi_hw: String::new(),
					disk_storage: String::new(),
					network: String::new(),
					net0: String::new(),
					net1: String::new(),
					bootstrap: crate::fleet::metadata::ProxmoxBootstrapConfig::default(),
					extra_networks: Vec::new(),
					pxe: false,
					cores: String::new(),
					memory: String::new(),
					iso: crate::fleet::metadata::ProxmoxIsoConfig {
						flavor: "std".to_string(),
						storage: String::new(),
						custom_path: String::new(),
					},
					cloud_init: CloudInitConfig {
						image: String::new(),
						user: String::new(),
						ipconfig0: String::new(),
						ipconfig1: String::new(),
					},
				},
				digitalocean: DigitalOceanConfig {
					region: String::new(),
					size: String::new(),
					image: String::new(),
				},
				vmware: VmwareConfig { vmx_path: String::new() },
				wsl: Default::default(),
			},
			is_ip_overridden: false,
			flake_ref: "path:.".to_string(),
			source_store_path: None,
			secret_store_path: None,
			has_disko: true,
			build_system: true,
			wsl: false,
			role: None,
			tags: Vec::new(),
			cross: None,
			features: Vec::new(),
		}
	}

	#[test]
	fn test_cross_build_validation() {
		// Set strategy to "cross"
		crate::config::set_runtime_options(crate::config::RuntimeOptions {
			build_strategy: Some("cross".to_string()),
			..Default::default()
		});

		// 1. Darwin host should fail
		let ctx_darwin = make_test_ctx("my-host", "nixos", "x86_64-darwin", "123", "10.0.0.1");
		assert!(ctx_darwin.validate().is_err());

		// 2. Linux host without cross metadata should fail
		let mut ctx_linux = make_test_ctx("my-host", "nixos", "x86_64-linux", "123", "10.0.0.1");
		assert!(ctx_linux.validate().is_err());

		// 3. Linux host with cross metadata should pass
		ctx_linux.cross = Some(crate::fleet::metadata::CrossConfig::default());
		assert!(ctx_linux.validate().is_ok());

		// Reset runtime options
		crate::config::set_runtime_options(crate::config::RuntimeOptions::default());
	}

	#[test]
	fn test_valid_context_passes() {
		let ctx = make_test_ctx("my-host", "nixos", "x86_64-linux", "123", "10.0.0.1");
		assert!(ctx.validate().is_ok());
	}

	#[test]
	fn test_wsl_validation_and_conflicts() {
		// 1. WSL disabled by default (no WSL provider config)
		let mut ctx = make_test_ctx("my-host", "nixos", "x86_64-linux", "123", "10.0.0.1");
		ctx.wsl = true;
		// wsl = true but deployment.wsl.enable is false: should fail validation
		assert!(ctx.validate().is_err());

		// 2. WSL enabled, valid config
		ctx.wsl = true;
		ctx.deployment.wsl.enable = true;
		ctx.deployment.wsl.windows_host = "win-host".to_string();
		ctx.deployment.wsl.windows_user = "win-user".to_string();
		ctx.deployment.wsl.distribution = "NixOS".to_string();
		ctx.deployment.wsl.install_root = "C:\\WSL\\NixOS".to_string();
		ctx.deployment.wsl.transport = "auto".to_string();
		ctx.has_disko = false;
		// Proxmox metadata still populated (vmid = "123" and proxmox.host = "proxmox-host"): should fail due to conflict
		ctx.deployment.proxmox.host = "proxmox-host".to_string();
		assert!(ctx.validate().is_err());

		// Clear Proxmox config
		ctx.deployment.vmid = String::new();
		ctx.deployment.proxmox.host = String::new();
		// Now it should pass validation
		assert!(ctx.validate().is_ok());

		// Test conflicting top-level wsl flag without deployment.wsl.enable
		ctx.deployment.wsl.enable = false;
		assert!(ctx.validate().is_err());
	}

	#[test]
	fn test_provider_kind_selection() {
		use crate::providers::ProviderKind;

		let provider_kind = |ctx: &RuntimeContext| {
			crate::fleet::resolution::resolve_provider(ctx, crate::process::Logger::silent())
				.map(|provider| provider.kind())
		};
		let mut ctx = make_test_ctx("my-host", "nixos", "x86_64-linux", "", "10.0.0.1");
		assert_eq!(provider_kind(&ctx), None);

		// WSL provider
		ctx.deployment.wsl.enable = true;
		assert_eq!(provider_kind(&ctx), Some(ProviderKind::Wsl));
		ctx.deployment.wsl.enable = false;

		// Proxmox provider
		ctx.deployment.vmid = "123".to_string();
		ctx.deployment.proxmox.host = "proxmox-host".to_string();
		assert_eq!(provider_kind(&ctx), Some(ProviderKind::Proxmox));

		// VMware provider
		ctx.deployment.vmid = String::new();
		ctx.deployment.proxmox.host = String::new();
		ctx.deployment.vmware.vmx_path = "path.vmx".to_string();
		assert_eq!(provider_kind(&ctx), Some(ProviderKind::Vmware));

		// DigitalOcean provider
		ctx.deployment.vmware.vmx_path = String::new();
		ctx.deployment.digitalocean.region = "nyc3".to_string();
		assert_eq!(provider_kind(&ctx), Some(ProviderKind::DigitalOcean));
	}

	#[test]
	fn test_invalid_hostname_fails() {
		let ctx = make_test_ctx("my host?", "nixos", "x86_64-linux", "123", "10.0.0.1");
		assert!(ctx.validate().is_err());
	}

	#[test]
	fn test_invalid_username_fails() {
		let ctx = make_test_ctx("my-host", "user?", "x86_64-linux", "123", "10.0.0.1");
		assert!(ctx.validate().is_err());
	}

	#[test]
	fn test_unsupported_system_fails() {
		let ctx = make_test_ctx("my-host", "nixos", "invalid-system", "123", "10.0.0.1");
		assert!(ctx.validate().is_err());
	}

	#[test]
	fn test_invalid_vmid_fails() {
		let ctx = make_test_ctx("my-host", "nixos", "x86_64-linux", "abc", "10.0.0.1");
		assert!(ctx.validate().is_err());
	}

	#[test]
	fn test_context_cache() {
		RuntimeContext::clear_cache();
		{
			let cache = get_context_cache().lock().unwrap();
			assert!(cache.is_empty());
		}

		let ctx = make_test_ctx("test-cache-host", "nixos", "x86_64-linux", "123", "10.0.0.1");
		{
			let mut cache = get_context_cache().lock().unwrap();
			cache.insert("test-cache-host".to_string(), ctx.clone());
		}

		let loaded = RuntimeContext::load("test-cache-host").unwrap();
		assert_eq!(loaded.hostname, "test-cache-host");
		assert_eq!(loaded.username, "nixos");
		assert!(loaded.has_disko);
	}

	#[test]
	fn test_create_adhoc_context() {
		let ctx = create_adhoc_context("192.168.1.187", Some("abc"), None);
		assert_eq!(ctx.hostname, "192.168.1.187");
		assert_eq!(ctx.target_ip, "192.168.1.187");
		assert_eq!(ctx.username, "abc");
		assert_eq!(ctx.deployment.proxmox.cloud_init.user, "abc");
		assert!(ctx.is_ip_overridden);
		assert!(!ctx.build_system);
	}
}
