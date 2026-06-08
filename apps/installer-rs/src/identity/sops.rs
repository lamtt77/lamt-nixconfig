use super::IdentityService;
use crate::context::RuntimeContext;
use crate::process::{CommandExecutor, Logger};
use std::path::Path;

pub struct SopsService {
    _logger: Logger,
}

impl SopsService {
    pub fn new(logger: Logger) -> Self {
        Self { _logger: logger }
    }

    /// Resolves the secrets repository absolute path.
    pub fn get_secrets_repo(&self) -> std::path::PathBuf {
        crate::config::get_secrets_repo()
    }
}

impl IdentityService for SopsService {
    fn id(&self) -> &str {
        "sops"
    }

    fn pre_install(&self, ctx: &RuntimeContext) -> Result<(), Box<dyn std::error::Error>> {
        let _ = ctx;
        Ok(())
    }

    fn post_install(
        &self,
        ctx: &RuntimeContext,
        _mount_path: &Path,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let _ = ctx;
        Ok(())
    }
}

pub fn register_age_key_in_sops(
    hostname: &str,
    pub_key_content: &str,
    secrets_repo: &Path,
    logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut child = std::process::Command::new("ssh-to-age")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()?;

    use std::io::Write;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(pub_key_content.as_bytes())?;
    }
    let output = child.wait_with_output()?;
    let age_key = String::from_utf8_lossy(&output.stdout).trim().to_string();

    if age_key.is_empty() {
        crate::warn!(
            &logger,
            "Failed to resolve age key from SSH public key. Skipping SOPS registration."
        );
        return Ok(());
    }

    let sops_mgr = secrets_repo.join("bin").join("sops-host-key-manager");
    if sops_mgr.exists() {
        crate::info!(
            &logger,
            "Registering/updating host '{}' age key in .sops.yaml...",
            hostname
        );
        let sops_mgr_str = sops_mgr.to_string_lossy().to_string();
        let silent_log = Logger::silent();
        CommandExecutor::execute(&sops_mgr_str, &["set-key", hostname, &age_key], silent_log)?;
        crate::info!(
            &logger,
            "Successfully registered/synced keys in secrets repository."
        );
    } else {
        crate::warn!(
            &logger,
            "sops-host-key-manager not found at {}. Skipping SOPS registration.",
            sops_mgr.display()
        );
    }

    Ok(())
}
