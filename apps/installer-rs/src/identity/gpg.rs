use super::IdentityService;
use crate::context::RuntimeContext;
use crate::process::CommandExecutor;
use crate::process::Logger;
use std::env;
use std::path::Path;

pub struct GpgService {
    logger: Logger,
}

impl GpgService {
    pub fn new(logger: Logger) -> Self {
        Self { logger }
    }

    /// Syncs user's personal GnuPG credentials to target.
    /// This is restricted to manual execution ONLY.
    pub fn sync_gpg_credentials(
        &self,
        ctx: &RuntimeContext,
        mount_path: &Path,
    ) -> Result<(), Box<dyn std::error::Error>> {
        // Locate local GPG home directory
        let local_gpg_home = if let Ok(gpg_home) = env::var("GNUPGHOME") {
            Path::new(&gpg_home).to_path_buf()
        } else {
            let home = env::var("HOME")?;
            let standard_path = Path::new(&home).join(".config/gnupg");
            if standard_path.exists() {
                standard_path
            } else {
                Path::new(&home).join(".gnupg")
            }
        };

        if !local_gpg_home.exists() {
            crate::info!(
                &self.logger,
                "Local GnuPG directory not found at {}. Skipping GPG sync.",
                local_gpg_home.display()
            );
            return Ok(());
        }

        crate::info!(
            &self.logger,
            "Syncing GnuPG credentials from {} to target...",
            local_gpg_home.display()
        );

        // Determine target path in the mounted root filesystem
        let target_gpg_dir = if ctx.username == "root" {
            mount_path.join("root/.config/gnupg")
        } else {
            mount_path
                .join("home")
                .join(&ctx.username)
                .join(".config/gnupg")
        };

        let persist_check_path = mount_path.join("persist");
        let target_persist_gpg_dir = if ctx.username == "root" {
            mount_path.join("persist/root/.config/gnupg")
        } else {
            mount_path
                .join("persist/home")
                .join(&ctx.username)
                .join(".config/gnupg")
        };

        let is_deploy = crate::config::get_runtime_options().deploy_active;
        let target_user = if is_deploy { "root" } else { &ctx.username };
        let target_ssh = format!("{}@{}", target_user, ctx.target_ip);

        let local_dir_str = local_gpg_home.to_string_lossy().to_string();
        let target_dir_str = target_gpg_dir.to_string_lossy().to_string();
        let persist_check_str = persist_check_path.to_string_lossy().to_string();
        let target_persist_dir_str = target_persist_gpg_dir.to_string_lossy().to_string();

        let tar_cmd = format!(
            "tar --exclude=\"S.*\" --exclude=\".#*\" --exclude=\"*.conf\" -czf - -C {} .",
            local_dir_str
        );

        let owner_cmd = if is_deploy {
            let owner = if ctx.username == "root" {
                "0:0"
            } else {
                "1000:100"
            };
            format!(
                " && chown -R {owner} {dir} && if [ -d {persist} ]; then chown -R {owner} {persist}; fi && \
                 if [ \"{username}\" != \"root\" ]; then \
                     chown {owner} {mount}/home/{username}/.config && \
                     if [ -d {mount}/persist/home/{username} ]; then \
                         mkdir -p {mount}/persist/home/{username}/.config && \
                         chown {owner} {mount}/persist/home/{username}/.config; \
                     fi; \
                 fi",
                owner = owner,
                dir = target_dir_str,
                persist = target_persist_dir_str,
                username = ctx.username,
                mount = mount_path.to_string_lossy()
            )
        } else {
            "".to_string()
        };

        let untar_cmd = format!(
            "mkdir -p {} && tar -xzf - -C {} && \
             if [ -d {} ]; then \
                 mkdir -p {} && cp -r {}/. {}/; \
             fi && \
             chmod 700 {} && find {} -type f -exec chmod 600 {{}} + && \
             if [ -d {} ]; then \
                 chmod 700 {} && find {} -type f -exec chmod 600 {{}} +; \
             fi{}",
            target_dir_str,
            target_dir_str,
            persist_check_str,
            target_persist_dir_str,
            target_dir_str,
            target_persist_dir_str,
            target_dir_str,
            target_dir_str,
            persist_check_str,
            target_persist_dir_str,
            target_persist_dir_str,
            owner_cmd
        );

        let pipe_cmd = format!(
            "{} | {} {} \"{}\"",
            tar_cmd,
            crate::remote::ssh::SshOptions::identity_sync().ssh_command_for_shell_pipeline(),
            target_ssh,
            untar_cmd
        );

        // Run the pipeline locally using bash
        CommandExecutor::execute("bash", &["-c", &pipe_cmd], self.logger.clone())?;
        crate::info!(&self.logger, "GnuPG credentials synced successfully.");

        Ok(())
    }
}

impl IdentityService for GpgService {
    fn id(&self) -> &str {
        "gpg"
    }

    fn pre_install(&self, _ctx: &RuntimeContext) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }

    fn post_install(
        &self,
        _ctx: &RuntimeContext,
        _mount_path: &Path,
    ) -> Result<(), Box<dyn std::error::Error>> {
        // No-op by default to ensure security. GPG sync is only run manually via sync_gpg_credentials.
        Ok(())
    }
}
