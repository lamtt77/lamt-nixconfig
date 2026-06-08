use super::IdentityService;
use crate::context::RuntimeContext;
use crate::process::Logger;
use std::path::Path;

mod host_key_mismatch;
mod host_key_staging;
mod host_key_validation;
pub mod host_keys;
pub mod personal_keys;

pub use host_keys::validate_and_sync_target_host_key;

pub struct SshKeyService {
    logger: Logger,
}

impl SshKeyService {
    pub fn new(logger: Logger) -> Self {
        Self { logger }
    }

    /// Resolves the secrets repository absolute path.
    pub fn get_secrets_repo(&self) -> std::path::PathBuf {
        crate::config::get_secrets_repo()
    }

    pub fn stage_target_host_keys(
        &self,
        ctx: &RuntimeContext,
        mount_path: &Path,
    ) -> Result<(), Box<dyn std::error::Error>> {
        host_keys::stage_target_host_keys(&self.logger, ctx, mount_path)
    }

    /// Syncs user's personal SSH keys from local ~/.ssh to the target.
    /// This is restricted to manual execution ONLY.
    pub fn sync_personal_keys(
        &self,
        ctx: &RuntimeContext,
        mount_path: &Path,
    ) -> Result<(), Box<dyn std::error::Error>> {
        personal_keys::sync_personal_keys(&self.logger, ctx, mount_path)
    }
}

impl IdentityService for SshKeyService {
    fn id(&self) -> &str {
        "ssh"
    }

    fn pre_install(&self, _ctx: &RuntimeContext) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }

    fn post_install(
        &self,
        ctx: &RuntimeContext,
        mount_path: &Path,
    ) -> Result<(), Box<dyn std::error::Error>> {
        self.stage_target_host_keys(ctx, mount_path)?;

        // Clean local known_hosts to prevent warning messages when the user SSHes manually later
        crate::info!(
            self.logger.clone(),
            "Cleaning local known_hosts for target {} and IP {}...",
            ctx.hostname,
            ctx.target_ip
        );
        let _ = crate::remote::known_hosts::remove_known_host_keys(&ctx.target_ip, &ctx.hostname);

        Ok(())
    }
}
