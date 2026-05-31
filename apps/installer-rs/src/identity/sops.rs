use super::IdentityService;
use crate::context::RuntimeContext;
use crate::process::LogTarget;
use std::fs;
use std::path::Path;
use std::sync::{Arc, Mutex};

pub struct SopsService {
    log_target: Arc<Mutex<LogTarget>>,
}

impl SopsService {
    pub fn new(log_target: Arc<Mutex<LogTarget>>) -> Self {
        Self { log_target }
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
        let secrets_repo = self.get_secrets_repo();
        let secrets_src = secrets_repo.join("sops").join(format!("{}.yaml", ctx.hostname));

        if secrets_src.exists() {
            println!("SOPS: Found secrets file for {} at {}. Copying to build context...", ctx.hostname, secrets_src.display());

            let dest_dir = Path::new("./secrets/sops");
            fs::create_dir_all(dest_dir)?;

            let dest_file = dest_dir.join(format!("{}.yaml", ctx.hostname));
            fs::copy(&secrets_src, &dest_file)?;
        } else {
            println!("SOPS: No secrets file found for {} at {}. Proceeding without secrets.", ctx.hostname, secrets_src.display());
        }

        Ok(())
    }

    fn post_install(&self, ctx: &RuntimeContext, _mount_path: &Path) -> Result<(), Box<dyn std::error::Error>> {
        let dest_file = Path::new("./secrets/sops").join(format!("{}.yaml", ctx.hostname));

        if dest_file.exists() {
            println!("SOPS: Cleaning up copied secrets file...");
            let _ = fs::remove_file(&dest_file);
        }

        // Clean up empty directories
        let sops_dir = Path::new("./secrets/sops");
        if sops_dir.exists() {
            let _ = fs::remove_dir(sops_dir);
        }
        let secrets_dir = Path::new("./secrets");
        if secrets_dir.exists() {
            let _ = fs::remove_dir(secrets_dir);
        }

        Ok(())
    }
}
