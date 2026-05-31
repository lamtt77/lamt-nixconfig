use super::IdentityService;
use crate::context::RuntimeContext;
use crate::process::CommandExecutor;
use crate::process::LogTarget;
use std::env;
use std::fs;
use std::path::Path;
use std::sync::{Arc, Mutex};

pub struct SshKeyService {
    log_target: Arc<Mutex<LogTarget>>,
}

impl SshKeyService {
    pub fn new(log_target: Arc<Mutex<LogTarget>>) -> Self {
        Self { log_target }
    }

    /// Resolves the secrets repository absolute path.
    pub fn get_secrets_repo(&self) -> std::path::PathBuf {
        crate::config::get_secrets_repo()
    }

    /// Syncs user's personal SSH keys from local ~/.ssh to the target.
    /// This is restricted to manual execution ONLY.
    pub fn sync_personal_keys(&self, ctx: &RuntimeContext, mount_path: &Path) -> Result<(), Box<dyn std::error::Error>> {
        let is_deploy = env::var("DEPLOY_ACTIVE").unwrap_or_default() == "yes";
        let target_user = if is_deploy { "root" } else { &ctx.username };
        let ssh_target = format!("{}@{}", target_user, ctx.target_ip);

        let home = env::var("HOME")?;
        let local_user_ssh = Path::new(&home).join(".ssh");
        if local_user_ssh.exists() {
            println!("Syncing user's personal SSH keys from {} to target...", local_user_ssh.display());
            
            let target_user_ssh = if ctx.username == "root" {
                mount_path.join("root/.ssh")
            } else {
                mount_path.join("home").join(&ctx.username).join(".ssh")
            };

            let target_persist_ssh = if ctx.username == "root" {
                mount_path.join("persist/root/.ssh")
            } else {
                mount_path.join("persist/home").join(&ctx.username).join(".ssh")
            };

            let local_ssh_str = local_user_ssh.to_string_lossy().to_string();
            let target_ssh_str = target_user_ssh.to_string_lossy().to_string();
            let persist_check_str = mount_path.join("persist").to_string_lossy().to_string();
            let target_persist_ssh_str = target_persist_ssh.to_string_lossy().to_string();
            
            let tar_cmd = format!(
                "tar --exclude=\"config\" --exclude=\"environment\" --exclude=\"known_hosts*\" -czf - -C {} .",
                local_ssh_str
            );
            
            let owner_cmd = if is_deploy {
                let owner = if ctx.username == "root" { "0:0" } else { "1000:100" };
                format!(
                    " && chown -R {owner} {dir} && if [ -d {persist} ]; then chown -R {owner} {persist}; fi",
                    owner = owner,
                    dir = target_ssh_str,
                    persist = target_persist_ssh_str
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
                target_ssh_str, target_ssh_str,
                persist_check_str,
                target_persist_ssh_str, target_ssh_str, target_persist_ssh_str,
                target_ssh_str, target_ssh_str,
                persist_check_str,
                target_persist_ssh_str, target_persist_ssh_str,
                owner_cmd
            );

            let pipe_cmd = format!("{} | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -A {} \"{}\"", 
                tar_cmd, ssh_target, untar_cmd
            );

            CommandExecutor::execute("bash", &["-c", &pipe_cmd], Arc::clone(&self.log_target))?;
            println!("User's personal SSH keys synced successfully.");
        } else {
            println!("Local user SSH directory not found at {}. Skipping user SSH sync.", local_user_ssh.display());
        }

        Ok(())
    }
}

impl IdentityService for SshKeyService {
    fn id(&self) -> &str {
        "ssh"
    }

    fn pre_install(&self, _ctx: &RuntimeContext) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }

    fn post_install(&self, ctx: &RuntimeContext, mount_path: &Path) -> Result<(), Box<dyn std::error::Error>> {
        let is_deploy = env::var("DEPLOY_ACTIVE").unwrap_or_default() == "yes";
        let target_user = if is_deploy { "root" } else { &ctx.username };
        let ssh_target = format!("{}@{}", target_user, ctx.target_ip);
        let secrets_repo = self.get_secrets_repo();
        
        let local_key_path = secrets_repo.join("hosts").join(&ctx.hostname).join("ssh_host_ed25519_key");
        let local_pub_path = local_key_path.with_extension("pub");
        
        // 1. Stage target host keys (only during initial deployment/bootstrap)
        if is_deploy && local_key_path.exists() {
            println!("Zero-Trust: Staging pre-generated target host SSH key pair...");
            
            let target_ssh_dir = mount_path.join("etc/ssh");
            let target_ssh_file = target_ssh_dir.join("ssh_host_ed25519_key");
            let target_ssh_file_str = target_ssh_file.to_string_lossy().to_string();
            
            let persist_ssh_dir = mount_path.join("persist/etc/ssh");
            let persist_ssh_file = persist_ssh_dir.join("ssh_host_ed25519_key");
            let persist_ssh_file_str = persist_ssh_file.to_string_lossy().to_string();
            let persist_check_str = mount_path.join("persist").to_string_lossy().to_string();
 
            // Stage private key to both locations
            let stage_key_script = format!(
                "tee /tmp/ssh_key_tmp >/dev/null && \
                 mkdir -p {} && cp /tmp/ssh_key_tmp {} && chmod 600 {} && \
                 if [ -d {} ]; then \
                     mkdir -p {} && cp /tmp/ssh_key_tmp {} && chmod 600 {}; \
                 fi && \
                 rm -f /tmp/ssh_key_tmp",
                target_ssh_dir.to_string_lossy(), target_ssh_file_str, target_ssh_file_str,
                persist_check_str,
                persist_ssh_dir.to_string_lossy(), persist_ssh_file_str, persist_ssh_file_str
            );
            
            let private_key = fs::read_to_string(&local_key_path)?;
            CommandExecutor::execute_ssh_with_stdin(&ssh_target, &stage_key_script, &private_key, Arc::clone(&self.log_target))?;
            
            // Stage public key if it exists
            if local_pub_path.exists() {
                let target_pub_file = target_ssh_dir.join("ssh_host_ed25519_key.pub");
                let target_pub_file_str = target_pub_file.to_string_lossy().to_string();
                let persist_pub_file = persist_ssh_dir.join("ssh_host_ed25519_key.pub");
                let persist_pub_file_str = persist_pub_file.to_string_lossy().to_string();
 
                let stage_pub_script = format!(
                    "tee /tmp/ssh_pub_tmp >/dev/null && \
                     mkdir -p {} && cp /tmp/ssh_pub_tmp {} && chmod 644 {} && \
                     if [ -d {} ]; then \
                         mkdir -p {} && cp /tmp/ssh_pub_tmp {} && chmod 644 {}; \
                     fi && \
                     rm -f /tmp/ssh_pub_tmp",
                    target_ssh_dir.to_string_lossy(), target_pub_file_str, target_pub_file_str,
                    persist_check_str,
                    persist_ssh_dir.to_string_lossy(), persist_pub_file_str, persist_pub_file_str
                );
                
                let public_key = fs::read_to_string(&local_pub_path)?;
                CommandExecutor::execute_ssh_with_stdin(&ssh_target, &stage_pub_script, &public_key, Arc::clone(&self.log_target))?;
            }
            
            println!("Target host SSH key staged successfully.");
        } else if !is_deploy {
            println!("Target is already deployed. Skipping target host SSH key pair staging.");
        } else {
            println!("No pre-generated local SSH host key found at {}. Skipping host key staging.", local_key_path.display());
        }
 
        // 2. Clean local known_hosts to prevent warning messages when the user SSHes manually later
        println!("Cleaning local known_hosts for target {} and IP {}...", ctx.hostname, ctx.target_ip);
        let _ = std::process::Command::new("ssh-keygen")
            .args(&["-R", &ctx.target_ip])
            .output();
        let _ = std::process::Command::new("ssh-keygen")
            .args(&["-R", &ctx.hostname])
            .output();
 
        Ok(())
    }
}

pub fn validate_and_sync_target_host_key(
    ctx: &RuntimeContext,
    log_target: Arc<Mutex<LogTarget>>,
) -> Result<(), Box<dyn std::error::Error>> {
    let is_deploy = std::env::var("DEPLOY_ACTIVE").unwrap_or_default() == "yes";
    let target_user = if is_deploy { "root" } else { &ctx.username };
    let ssh_target = format!("{}@{}", target_user, ctx.target_ip);
    let secrets_repo = crate::config::get_secrets_repo();

    let local_key_file = secrets_repo.join("hosts").join(&ctx.hostname).join("ssh_host_ed25519_key");
    let local_pub_file = local_key_file.with_extension("pub");

    // Only validate/sync if the secrets repo exists
    if !secrets_repo.exists() || !secrets_repo.join(".sops.yaml").exists() {
        return Ok(());
    }

    // Determine target active public key over SSH if reachable
    println!("Checking target host SSH key connection for {}...", ctx.hostname);
    let get_pubkey_cmd = "sudo cat /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null; echo '---HOSTNAME---'; hostname 2>/dev/null";
    
    // Attempt to read target public key with a short timeout
    let ssh_check_args = [
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
        "-o", "ConnectTimeout=3",
        "-o", "PasswordAuthentication=no",
        &ssh_target,
        get_pubkey_cmd,
    ];
    let output = std::process::Command::new("ssh").args(&ssh_check_args).output();
    
    let (active_pub_key, remote_hostname) = match output {
        Ok(out) if out.status.success() => {
            let s = String::from_utf8_lossy(&out.stdout);
            let mut parts = s.split("---HOSTNAME---");
            let key_part = parts.next().unwrap_or("").trim();
            let hostname_part = parts.next().unwrap_or("").trim();
            
            let key = key_part.split_whitespace().take(2).collect::<Vec<&str>>().join(" ");
            let resolved_key = if key.is_empty() { None } else { Some(key) };
            
            let resolved_hostname = if hostname_part.is_empty() { None } else { Some(hostname_part.to_string()) };
            
            (resolved_key, resolved_hostname)
        }
        _ => (None, None),
    };

    if let Some(ref actual_host) = remote_hostname {
        if actual_host != &ctx.hostname {
            return Err(format!(
                "Mismatched host safety trigger: Connected to target IP {}, which returned hostname '{}', but the configuration hostname is '{}'. Aborting to prevent configuration overwrite.",
                ctx.target_ip, actual_host, ctx.hostname
            ).into());
        }
    }

    // Load local public key from secrets if it exists
    let local_pub_key = if local_pub_file.exists() {
        let content = fs::read_to_string(&local_pub_file)?;
        let key = content.trim().split_whitespace().take(2).collect::<Vec<&str>>().join(" ");
        if key.is_empty() { None } else { Some(key) }
    } else {
        None
    };

    // Scenario A: Local secrets repo is missing the host key file
    if local_pub_key.is_none() {
        if let Some(ref active_key) = active_pub_key {
            println!("Secrets repo is missing host key for '{}', but target host has an active key.", ctx.hostname);
            println!("Importing active host keys from target...");
            
            // Read target private & public keys
            let silent_log = Arc::new(Mutex::new(LogTarget::Silent));
            let private_key = CommandExecutor::execute_ssh(&ssh_target, "sudo cat /etc/ssh/ssh_host_ed25519_key", silent_log.clone())?;
            let public_key = CommandExecutor::execute_ssh(&ssh_target, get_pubkey_cmd, silent_log)?;

            let key_dir = local_key_file.parent().unwrap();
            fs::create_dir_all(key_dir)?;
            fs::write(&local_key_file, &private_key)?;
            fs::write(&local_pub_file, &public_key)?;

            // Set correct permissions on Unix (600 for private, 644 for public)
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                fs::set_permissions(&local_key_file, fs::Permissions::from_mode(0o600))?;
                fs::set_permissions(&local_pub_file, fs::Permissions::from_mode(0o644))?;
            }

            // Register in .sops.yaml using sops-host-key-manager
            register_age_key_in_sops(&ctx.hostname, active_key, &secrets_repo, Arc::clone(&log_target))?;
        } else {
            // Generate a fresh key pair locally since both are missing
            println!("SSH host key for '{}' is missing. Generating fresh Ed25519 key locally...", ctx.hostname);
            let key_dir = local_key_file.parent().unwrap();
            fs::create_dir_all(key_dir)?;
            
            let key_file_str = local_key_file.to_string_lossy().to_string();
            let gen_args = ["-t", "ed25519", "-f", &key_file_str, "-N", "", "-q"];
            CommandExecutor::execute("ssh-keygen", &gen_args, Arc::clone(&log_target))?;

            let pub_key_content = fs::read_to_string(&local_pub_file)?;
            register_age_key_in_sops(&ctx.hostname, &pub_key_content, &secrets_repo, Arc::clone(&log_target))?;
        }
        return Ok(());
    }

    let local_pub_key_val = local_pub_key.unwrap();

    // Scenario B: Target is reachable, and public key mismatch is detected
    if let Some(ref active_pub_key_val) = active_pub_key {
        if active_pub_key_val != &local_pub_key_val {
            println!("WARNING: Target host '{}' SSH key mismatch detected!", ctx.hostname);
            println!("  Local key (in lamt-secrets): {}", local_pub_key_val);
            println!("  Target key (active on host): {}", active_pub_key_val);

            // Determine resolution choice
            let mut choice = "3".to_string();
            let is_force = std::env::var("CLI_FORCE").unwrap_or_default() == "yes";
            
            if !is_force {
                println!("How would you like to resolve this mismatch?");
                println!("  1) Overwrite target key to match secrets (Secrets -> Target)");
                println!("  2) Update secrets to match target key (Target -> Secrets)");
                println!("  3) Proceed anyway (decryption may fail)");
                println!("  4) Abort deployment");
                
                let selections = &[
                    "Overwrite target key to match secrets (Secrets -> Target)",
                    "Update secrets to match target key (Target -> Secrets)",
                    "Proceed anyway (decryption may fail)",
                    "Abort deployment",
                ];
                let selection = dialoguer::Select::new()
                    .with_prompt("Select option")
                    .items(selections)
                    .default(0)
                    .interact()
                    .unwrap_or(3);
                
                choice = (selection + 1).to_string();
            } else {
                if let Ok(update_host) = std::env::var("UPDATE_HOST_KEY") {
                    if update_host == "yes" { choice = "1".to_string(); }
                }
                if let Ok(update_sec) = std::env::var("UPDATE_SECRETS_KEY") {
                    if update_sec == "yes" { choice = "2".to_string(); }
                }
                println!("Non-interactive mode active (CLI_FORCE=yes). Auto-selected choice: {}", choice);
            }

            match choice.as_str() {
                "1" => {
                    // Overwrite target key to match secrets
                    println!("Updating SSH host key on target to match local key...");
                    let private_key = fs::read_to_string(&local_key_file)?;
                    let public_key = fs::read_to_string(&local_pub_file)?;
                    
                    let stage_priv_cmd = "sudo tee /etc/ssh/ssh_host_ed25519_key >/dev/null && sudo chmod 600 /etc/ssh/ssh_host_ed25519_key";
                    CommandExecutor::execute_ssh_with_stdin(&ssh_target, stage_priv_cmd, &private_key, Arc::clone(&log_target))?;

                    let stage_pub_cmd = "sudo tee /etc/ssh/ssh_host_ed25519_key.pub >/dev/null && sudo chmod 644 /etc/ssh/ssh_host_ed25519_key.pub";
                    CommandExecutor::execute_ssh_with_stdin(&ssh_target, stage_pub_cmd, &public_key, Arc::clone(&log_target))?;

                    // Determine if we use persistence / impermanence path
                    let has_persist_check = "if [ -d /persist/etc/ssh ] && [ \"$(stat -c %i /persist/etc/ssh 2>/dev/null)\" != \"$(stat -c %i /etc/ssh 2>/dev/null)\" ]; then echo 1; else echo 0; fi";
                    let has_persist_out = CommandExecutor::execute_ssh(&ssh_target, &format!("sudo bash -c '{}'", has_persist_check), Arc::clone(&log_target))?;
                    let has_persist = has_persist_out.trim() == "1";

                    if has_persist {
                        let stage_persist_priv_cmd = "sudo mkdir -p /persist/etc/ssh && sudo tee /persist/etc/ssh/ssh_host_ed25519_key >/dev/null && sudo chmod 600 /persist/etc/ssh/ssh_host_ed25519_key";
                        CommandExecutor::execute_ssh_with_stdin(&ssh_target, stage_persist_priv_cmd, &private_key, Arc::clone(&log_target))?;

                        let stage_persist_pub_cmd = "sudo tee /persist/etc/ssh/ssh_host_ed25519_key.pub >/dev/null && sudo chmod 644 /persist/etc/ssh/ssh_host_ed25519_key.pub";
                        CommandExecutor::execute_ssh_with_stdin(&ssh_target, stage_persist_pub_cmd, &public_key, Arc::clone(&log_target))?;
                    }

                    let reload_ssh_cmd = "sudo systemctl reload sshd || sudo systemctl restart ssh || true";
                    CommandExecutor::execute_ssh(&ssh_target, reload_ssh_cmd, Arc::clone(&log_target))?;
                    println!("Target host key updated successfully.");

                    // Clean local known_hosts to prevent warning messages when connecting
                    let _ = std::process::Command::new("ssh-keygen").args(&["-R", &ctx.target_ip]).output();
                    let _ = std::process::Command::new("ssh-keygen").args(&["-R", &ctx.hostname]).output();
                }
                "2" => {
                    // Update secrets to match target key
                    println!("Updating secrets repository with target host key...");
                    let silent_log = Arc::new(Mutex::new(LogTarget::Silent));
                    let private_key = CommandExecutor::execute_ssh(&ssh_target, "sudo cat /etc/ssh/ssh_host_ed25519_key", silent_log.clone())?;
                    let public_key = CommandExecutor::execute_ssh(&ssh_target, get_pubkey_cmd, silent_log)?;

                    fs::write(&local_key_file, &private_key)?;
                    fs::write(&local_pub_file, &public_key)?;

                    #[cfg(unix)]
                    {
                        use std::os::unix::fs::PermissionsExt;
                        fs::set_permissions(&local_key_file, fs::Permissions::from_mode(0o600))?;
                        fs::set_permissions(&local_pub_file, fs::Permissions::from_mode(0o644))?;
                    }

                    register_age_key_in_sops(&ctx.hostname, active_pub_key_val, &secrets_repo, Arc::clone(&log_target))?;
                }
                "3" => {
                    println!("Proceeding anyway. Secrets decryption may fail on target.");
                }
                _ => {
                    return Err("Aborted by user due to SSH host key mismatch.".into());
                }
            }
        }
    }

    Ok(())
}

fn register_age_key_in_sops(
    hostname: &str,
    pub_key_content: &str,
    secrets_repo: &Path,
    _log_target: Arc<Mutex<LogTarget>>,
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
        println!("Warning: Failed to resolve age key from SSH public key. Skipping SOPS registration.");
        return Ok(());
    }

    let sops_mgr = secrets_repo.join("bin").join("sops-host-key-manager");
    if sops_mgr.exists() {
        println!("Registering/updating host '{}' age key in .sops.yaml...", hostname);
        let sops_mgr_str = sops_mgr.to_string_lossy().to_string();
        let silent_log = Arc::new(Mutex::new(LogTarget::Silent));
        CommandExecutor::execute(&sops_mgr_str, &["set-key", hostname, &age_key], silent_log)?;
        println!("Successfully registered/synced keys in secrets repository.");
    } else {
        println!("Warning: sops-host-key-manager not found at {}. Skipping SOPS registration.", sops_mgr.display());
    }

    Ok(())
}
