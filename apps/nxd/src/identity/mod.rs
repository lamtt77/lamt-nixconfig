use crate::context::RuntimeContext;
use crate::process::Logger;
use std::path::Path;

pub trait IdentityService {
	fn id(&self) -> &str;
	fn pre_install(&self, ctx: &RuntimeContext) -> Result<(), Box<dyn std::error::Error>>;
	fn post_install(
		&self,
		ctx: &RuntimeContext,
		mount_path: &Path,
	) -> Result<(), Box<dyn std::error::Error>>;
}

pub mod gpg;
pub mod sops;
pub mod ssh;
pub mod tailscale;

pub fn get_identity_services(logger: Logger) -> Vec<Box<dyn IdentityService>> {
	vec![
		Box::new(sops::SopsService::new(logger.clone())),
		Box::new(tailscale::TailscaleService::new(logger.clone())),
		Box::new(ssh::SshKeyService::new(logger.clone())),
		Box::new(gpg::GpgService::new(logger.clone())),
	]
}
