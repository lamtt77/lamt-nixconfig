use crate::context::RuntimeContext;
use crate::process::LogTarget;
use std::path::Path;
use std::sync::{Arc, Mutex};

pub trait IdentityService {
    fn id(&self) -> &str;
    fn pre_install(&self, ctx: &RuntimeContext) -> Result<(), Box<dyn std::error::Error>>;
    fn post_install(&self, ctx: &RuntimeContext, mount_path: &Path) -> Result<(), Box<dyn std::error::Error>>;
}

pub mod ssh;
pub mod gpg;
pub mod sops;
pub mod tailscale;

pub fn get_identity_services(log_target: Arc<Mutex<LogTarget>>) -> Vec<Box<dyn IdentityService>> {
    vec![
        Box::new(sops::SopsService::new(Arc::clone(&log_target))),
        Box::new(tailscale::TailscaleService::new(Arc::clone(&log_target))),
        Box::new(ssh::SshKeyService::new(Arc::clone(&log_target))),
        Box::new(gpg::GpgService::new(Arc::clone(&log_target))),
    ]
}
