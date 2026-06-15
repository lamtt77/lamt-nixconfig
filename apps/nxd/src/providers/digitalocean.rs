use super::{Provider, ProviderKind, ProviderState};
use crate::context::RuntimeContext;
use crate::process::CommandExecutor;
use crate::process::Logger;

pub struct DigitalOceanProvider {
	hostname: String,
	region: String,
	size: String,
	image: String,
	logger: Logger,
}

impl DigitalOceanProvider {
	pub fn new(ctx: &RuntimeContext, logger: Logger) -> Self {
		Self {
			hostname: ctx.hostname.clone(),
			region: ctx.deployment.digitalocean.region.clone(),
			size: ctx.deployment.digitalocean.size.clone(),
			image: ctx.deployment.digitalocean.image.clone(),
			logger,
		}
	}
}

impl Provider for DigitalOceanProvider {
	fn kind(&self) -> ProviderKind {
		ProviderKind::DigitalOcean
	}

	fn resource_identity(&self) -> String {
		format!("droplet {}", self.hostname)
	}

	fn inspect(&self) -> Result<ProviderState, Box<dyn std::error::Error>> {
		let check_args = ["compute", "droplet", "get", &self.hostname];
		let silent_log = Logger::silent();
		match CommandExecutor::execute("doctl", &check_args, silent_log) {
			Ok(_) => Ok(ProviderState::Present),
			Err(error) if error.to_string().contains("not found") => Ok(ProviderState::Missing),
			Err(error) => Err(error),
		}
	}

	fn create(&self) -> Result<(), Box<dyn std::error::Error>> {
		info!(self.logger, "Checking if droplet '{}' already exists...", self.hostname);

		info!(
			self.logger,
			"Provisioning new DigitalOcean droplet '{}' ({}, {})...",
			self.hostname,
			self.region,
			self.size
		);

		let create_args = [
			"compute",
			"droplet",
			"create",
			&self.hostname,
			"--region",
			&self.region,
			"--size",
			&self.size,
			"--image",
			&self.image,
			"--tag-names",
			"nixos,installer",
			"--wait",
		];

		CommandExecutor::execute("doctl", &create_args, self.logger.clone())?;
		Ok(())
	}

	fn destroy(&self) -> Result<(), Box<dyn std::error::Error>> {
		info!(self.logger, "Requesting destroy for DigitalOcean droplet '{}'...", self.hostname);
		let delete_args = ["compute", "droplet", "delete", &self.hostname, "--force"];

		CommandExecutor::execute("doctl", &delete_args, self.logger.clone())?;
		Ok(())
	}

	fn get_ip(&self, _poll: bool) -> Result<String, Box<dyn std::error::Error>> {
		info!(self.logger, "Resolving public IP for droplet '{}'...", self.hostname);
		let args =
			["compute", "droplet", "get", &self.hostname, "--format", "PublicIPv4", "--no-header"];
		let silent_log = Logger::silent();
		let ip_out = CommandExecutor::execute("doctl", &args, silent_log)?;
		let ip = ip_out.trim().to_string();

		if ip.is_empty() {
			return Err("DigitalOcean returned empty Public IP".into());
		}

		Ok(ip)
	}
}
