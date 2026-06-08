use crate::config;
use crate::context::RuntimeContext;
use crate::process::Logger;
use std::fs;
use std::path::Path;

pub fn inject_host_secret(
    ctx: &RuntimeContext,
    workspace_root: &Path,
    logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
    if let Some(source) = config::resolve_host_sops_source(&ctx.hostname) {
        info!(logger, "SOPS: {}", source.description);
        let dest_dir = workspace_root.join("secrets").join("sops");
        fs::create_dir_all(&dest_dir)?;
        fs::copy(
            &source.path,
            dest_dir.join(format!("{}.yaml", ctx.hostname)),
        )?;
    } else {
        let (repo_path, local_path) = config::host_sops_lookup_paths(&ctx.hostname);
        info!(
            logger,
            "SOPS: No secrets file found for {}. Checked {} and {}. Proceeding without secrets.",
            ctx.hostname,
            repo_path.display(),
            local_path.display()
        );
    }

    Ok(())
}
