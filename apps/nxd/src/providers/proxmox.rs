use super::{Provider, ProviderKind, ProviderState};
use crate::context::RuntimeContext;
use crate::process::CommandExecutor;
use crate::process::Logger;

pub struct ProxmoxProvider {
	pub(crate) vmid: String,
	pub(crate) hostname: String,
	pub(crate) pve_host: String,
	pub(crate) bios: String,
	pub(crate) disk_bus: String,
	pub(crate) scsi_hw: String,
	pub(crate) disk_size: String,
	pub(crate) cores: String,
	pub(crate) memory: String,
	pub(crate) iso_storage: String,
	pub(crate) iso_custom_path: String,
	pub(crate) disk_storage: String,
	pub(crate) network: String,
	pub(crate) net0: String,
	pub(crate) net1: String,
	pub(crate) bootstrap: crate::fleet::metadata::ProxmoxBootstrapConfig,
	pub(crate) extra_networks: Vec<String>,
	pub(crate) pxe: bool,
	pub(crate) target_ip: String,
	pub(crate) ssh_proxy_jump: String,
	pub(crate) cloud_init_image: String,
	pub(crate) cloud_init_user: String,
	pub(crate) cloud_init_ipconfig0: String,
	pub(crate) cloud_init_ipconfig1: String,
	pub(crate) logger: Logger,
}

impl ProxmoxProvider {
	pub fn new(ctx: &RuntimeContext, logger: Logger) -> Self {
		let net0 = if !ctx.deployment.proxmox.net0.is_empty() {
			ctx.deployment.proxmox.net0.clone()
		} else if !ctx.deployment.proxmox.network.is_empty() {
			ctx.deployment.proxmox.network.clone()
		} else {
			crate::config::proxmox_default_network()
		};
		let cores = if ctx.deployment.proxmox.cores.is_empty() {
			"4".to_string()
		} else {
			ctx.deployment.proxmox.cores.clone()
		};
		let memory = if ctx.deployment.proxmox.memory.is_empty() {
			"4096".to_string()
		} else {
			ctx.deployment.proxmox.memory.clone()
		};
		let disk_size = if ctx.deployment.disk_size.is_empty() {
			"50".to_string()
		} else {
			ctx.deployment.disk_size.clone()
		};

		Self {
			vmid: ctx.deployment.vmid.clone(),
			hostname: ctx.hostname.clone(),
			pve_host: ctx.deployment.proxmox.host.clone(),
			bios: ctx.deployment.proxmox.bios.clone(),
			disk_bus: ctx.deployment.proxmox.disk_bus.clone(),
			scsi_hw: ctx.deployment.proxmox.scsi_hw.clone(),
			disk_size,
			cores,
			memory,
			iso_storage: ctx.deployment.proxmox.iso.storage.clone(),
			iso_custom_path: ctx.deployment.proxmox.iso.custom_path.clone(),
			disk_storage: ctx.deployment.proxmox.disk_storage.clone(),
			network: ctx.deployment.proxmox.network.clone(),
			net0,
			net1: ctx.deployment.proxmox.net1.clone(),
			bootstrap: ctx.deployment.proxmox.bootstrap.clone(),
			extra_networks: ctx.deployment.proxmox.extra_networks.clone(),
			pxe: ctx.deployment.proxmox.pxe,
			target_ip: ctx.target_ip.clone(),
			ssh_proxy_jump: ctx.deployment.ssh_proxy_jump.clone(),
			cloud_init_image: ctx.deployment.proxmox.cloud_init.image.clone(),
			cloud_init_user: ctx.deployment.proxmox.cloud_init.user.clone(),
			cloud_init_ipconfig0: ctx.deployment.proxmox.cloud_init.ipconfig0.clone(),
			cloud_init_ipconfig1: ctx.deployment.proxmox.cloud_init.ipconfig1.clone(),
			logger,
		}
	}

	pub fn execute(&self, cmd: &str) -> Result<String, Box<dyn std::error::Error>> {
		self.execute_with_log(cmd, self.logger.clone())
	}

	pub fn execute_silent(&self, cmd: &str) -> Result<String, Box<dyn std::error::Error>> {
		self.execute_with_log(cmd, Logger::silent())
	}

	pub fn execute_with_log(
		&self,
		cmd: &str,
		logger: Logger,
	) -> Result<String, Box<dyn std::error::Error>> {
		let ssh_target = format!("root@{}", self.pve_host);
		CommandExecutor::execute_ssh(&ssh_target, cmd, logger)
	}

	pub fn extra_net_args(&self) -> String {
		let mut args = String::new();
		if !self.net1.is_empty() {
			args.push_str(&format!(" --net1 {}", self.net1));
		} else if !self.extra_networks.is_empty() {
			for (i, net_config) in self.extra_networks.iter().enumerate() {
				args.push_str(&format!(" --net{} {}", i + 1, net_config));
			}
		}
		args
	}
}

impl Provider for ProxmoxProvider {
	fn kind(&self) -> ProviderKind {
		ProviderKind::Proxmox
	}

	fn resource_identity(&self) -> String {
		format!("VMID {} on {}", self.vmid, self.pve_host)
	}

	fn inspect(&self) -> Result<ProviderState, Box<dyn std::error::Error>> {
		let status_cmd = format!("qm status {}", self.vmid);
		match self.execute_silent(&status_cmd) {
			Ok(output) if output.contains("running") => Ok(ProviderState::Running),
			Ok(_) => Ok(ProviderState::Present),
			Err(error) if error.to_string().contains("does not exist") => Ok(ProviderState::Missing),
			Err(error) => Err(error),
		}
	}

	fn create(&self) -> Result<(), Box<dyn std::error::Error>> {
		super::proxmox_preflight::run_preflight_checks(self)?;

		super::proxmox_create::create_vm(self)?;

		info!(self.logger, "Starting Proxmox VM {} on {}...", self.vmid, self.pve_host);
		let start_cmd = format!("qm start {}", self.vmid);
		self.execute(&start_cmd)?;

		Ok(())
	}

	fn destroy(&self) -> Result<(), Box<dyn std::error::Error>> {
		info!(self.logger, "Requesting stop for Proxmox VM {} on {}...", self.vmid, self.pve_host);
		let stop_cmd = format!("qm stop {}", self.vmid);
		let _ = self.execute(&stop_cmd);

		info!(self.logger, "Requesting destroy for Proxmox VM {}...", self.vmid);
		let destroy_cmd = format!("qm destroy {}", self.vmid);
		self.execute(&destroy_cmd)?;
		Ok(())
	}

	fn get_ip(&self, poll: bool) -> Result<String, Box<dyn std::error::Error>> {
		super::proxmox_ip::get_ip(self, poll)
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn test_proxmox_provider_network_resolution() {
		use crate::context::{DeploymentConfig, ProxmoxConfig, RuntimeContext};

		let mut ctx = RuntimeContext {
			hostname: "test-router".to_string(),
			target_ip: "10.0.0.1".to_string(),
			username: "root".to_string(),
			system: "x86_64-linux".to_string(),
			deployment: DeploymentConfig {
				target_ip: "10.0.0.1".to_string(),
				ssh_proxy_jump: String::new(),
				builder: String::new(),
				low_mem: String::new(),
				substitute_on_destination: false,
				enable_local_cache: true,
				vmid: "900".to_string(),
				disk_size: "20".to_string(),
				tailscale_namespace: String::new(),
				proxmox: ProxmoxConfig {
					host: "10.0.0.100".to_string(),
					bios: "seabios".to_string(),
					disk_bus: "virtio".to_string(),
					scsi_hw: String::new(),
					disk_storage: "local-lvm".to_string(),
					network: "virtio,bridge=vmbr0".to_string(),
					net0: "virtio,bridge=vmbr0,tag=10".to_string(),
					net1: "virtio,bridge=vmbr1".to_string(),
					bootstrap: crate::fleet::metadata::ProxmoxBootstrapConfig {
						interface: "net1".to_string(),
						static_ip: "10.0.0.2".to_string(),
						subnet: "10.0.0.0/24".to_string(),
						gateway: "10.0.0.1".to_string(),
						vlan: Some(20),
					},
					extra_networks: Vec::new(),
					pxe: false,
					cores: "2".to_string(),
					memory: "2048".to_string(),
					iso: crate::fleet::metadata::ProxmoxIsoConfig {
						flavor: "qemu".to_string(),
						storage: "local".to_string(),
						custom_path: String::new(),
					},
					cloud_init: crate::fleet::metadata::CloudInitConfig {
						image: String::new(),
						user: String::new(),
						ipconfig0: String::new(),
						ipconfig1: String::new(),
					},
				},
				digitalocean: crate::fleet::metadata::DigitalOceanConfig {
					region: String::new(),
					size: String::new(),
					image: String::new(),
				},
				vmware: crate::fleet::metadata::VmwareConfig { vmx_path: String::new() },
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
		};

		assert!(ctx.validate().is_ok());

		let provider = ProxmoxProvider::new(&ctx, Logger::silent());
		assert_eq!(provider.net0, "virtio,bridge=vmbr0,tag=10");
		assert_eq!(provider.net1, "virtio,bridge=vmbr1");
		assert_eq!(provider.bootstrap.interface, "net1");
		assert_eq!(provider.bootstrap.vlan, Some(20));

		ctx.deployment.proxmox.net0 = String::new();
		let provider2 = ProxmoxProvider::new(&ctx, Logger::silent());
		assert_eq!(provider2.net0, "virtio,bridge=vmbr0");
	}
}
