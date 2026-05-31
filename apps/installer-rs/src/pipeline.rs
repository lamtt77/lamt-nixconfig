use crate::context::RuntimeContext;
use crate::identity::get_identity_services;
use crate::nix::NixBuilder;
use crate::process::{CommandExecutor, LogTarget};
use crate::log_status;
use std::env;
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

pub fn run_deployment(
    ctx: &RuntimeContext,
    log_target: Arc<Mutex<LogTarget>>,
) -> Result<(), Box<dyn std::error::Error>> {
    let start_time = std::time::Instant::now();
    let low_mem = ctx.deployment.low_mem == "yes";

    // For non-NixOS cloud-init templates, bypass the state convergence pipeline and just verify SSH availability
    if !ctx.deployment.proxmox.cloud_init.image.is_empty() {
        log_status!(log_target, "=========================================================================");
        log_status!(log_target, "Starting Cloud-Init VM Template Verification for {}", ctx.hostname);
        log_status!(log_target, "Target IP: {}", ctx.target_ip);
        log_status!(log_target, "Cloud-Init User: {}", ctx.deployment.proxmox.cloud_init.user);
        log_status!(log_target, "=========================================================================");

        let ci_user = if ctx.deployment.proxmox.cloud_init.user.is_empty() {
            "ubuntu"
        } else {
            &ctx.deployment.proxmox.cloud_init.user
        };
        let ci_ssh = format!("{}@{}", ci_user, ctx.target_ip);

        // Clean local known_hosts to prevent warning messages when connecting or later
        let _ = std::process::Command::new("ssh-keygen")
            .args(&["-R", &ctx.target_ip])
            .output();
        let _ = std::process::Command::new("ssh-keygen")
            .args(&["-R", &ctx.hostname])
            .output();

        log_status!(log_target, "Waiting for SSH on {} to verify cloud-init deployment...", ci_ssh);
        wait_for_ssh(&ci_ssh, 300, Arc::clone(&log_target))?;

        log_status!(log_target, "=========================================================================");
        let duration = start_time.elapsed();
        let mins = duration.as_secs() / 60;
        let secs = duration.as_secs() % 60;
        log_status!(log_target, "Cloud-Init VM Template verification finished in {}m {}s!", mins, secs);
        log_status!(log_target, "=========================================================================");
        return Ok(());
    }

    let target_ssh = format!("root@{}", ctx.target_ip);
    
    std::env::set_var("DEPLOY_ACTIVE", "yes");

    // Clean local known_hosts to prevent warning messages when connecting or later
    let _ = std::process::Command::new("ssh-keygen")
        .args(&["-R", &ctx.target_ip])
        .output();
    let _ = std::process::Command::new("ssh-keygen")
        .args(&["-R", &ctx.hostname])
        .output();

    let builder = NixBuilder::resolve(ctx);
    let strategy_name = match &builder.strategy {
        crate::nix::BuildStrategy::Local => "Local (Natively on Orchestrator)".to_string(),
        crate::nix::BuildStrategy::RemoteBuilder { ssh_connection } => {
            format!("RemoteBuilder (Delegated via SSH to {})", ssh_connection)
        }
        crate::nix::BuildStrategy::TargetInstantiated => {
            "TargetInstantiated (Instantiation on Orchestrator -> Realization on Target)".to_string()
        }
        crate::nix::BuildStrategy::TargetNative => {
            "TargetNative (Natively built directly on target)".to_string()
        }
    };

    log_status!(log_target, "=========================================================================");
    log_status!(log_target, "Starting State Convergence Deployment Pipeline for {}", ctx.hostname);
    log_status!(log_target, "Target IP: {}", ctx.target_ip);
    log_status!(log_target, "Low Memory Optimization: {}", if low_mem { "ENABLED" } else { "DISABLED" });
    log_status!(log_target, "Resolved Build Strategy: {}", strategy_name);
    log_status!(log_target, "=========================================================================");

    // Wait for SSH on target to become ready (e.g. if the VM was just recreated/booted)
    wait_for_ssh(&target_ssh, 300, Arc::clone(&log_target))?;

    // Safety check remote hostname to prevent deploying configuration to the wrong active host
    log_status!(log_target, "Checking target system hostname to prevent configuration mismatch...");
    if let Ok(actual_host) = CommandExecutor::execute_ssh(&target_ssh, "hostname", Arc::clone(&log_target)) {
        let actual_host = actual_host.trim().to_string();
        if !actual_host.is_empty() && actual_host != ctx.hostname {
            let generic_names = ["nixos", "installer", "nixos-installer"];
            if !generic_names.contains(&actual_host.as_str()) {
                let is_forced = std::env::var("CLI_FORCE").unwrap_or_default() == "yes";
                if !is_forced {
                    return Err(format!(
                        "CRITICAL: Mismatched host safety trigger. Target IP {} is running as '{}', but configuration is for '{}'. Deployment would overwrite and erase this machine! Use --force to override.",
                        ctx.target_ip, actual_host, ctx.hostname
                    ).into());
                } else {
                    log_status!(log_target, "WARNING: Target hostname mismatch (target is '{}', config is '{}'). Proceeding because --force is enabled.", actual_host, ctx.hostname);
                }
            }
        }
    }

    // Configure DNS resolver on target live installer to ensure outbound internet and substitution resolve correctly
    log_status!(log_target, "Configuring DNS resolver (nameserver 1.1.1.1) on target live environment...");
    let dns_cmd = "echo 'nameserver 1.1.1.1' | sudo tee /etc/resolv.conf >/dev/null || echo 'nameserver 1.1.1.1' > /etc/resolv.conf";
    let _ = CommandExecutor::execute_ssh(&target_ssh, dns_cmd, Arc::clone(&log_target));

    // --- Phase 1: Kexec Takeover Target ---
    handle_kexec_takeover(ctx, &target_ssh, low_mem, Arc::clone(&log_target))?;

    // --- Phase 2: Setup Swap (ZRAM) for live environment ---
    if low_mem {
        setup_zram_swap(&target_ssh, Arc::clone(&log_target))?;
    }

    // --- Phase 3: Run Identity Services Pre-Install ---
    log_status!(log_target, "Running Identity Services Pre-Install Staging...");
    let identity_services = get_identity_services(Arc::clone(&log_target));
    for service in &identity_services {
        log_status!(log_target, "Executing pre-install for service: {}", service.id());
        service.pre_install(ctx)?;
    }

    // --- Phase 4: Disk Partitioning (Disko) ---
    log_status!(log_target, "Generating and executing Disko partitioning script...");
    let disko_script_path = builder.build_attribute(
        "config.system.build.diskoScript",
        None,
        Arc::clone(&log_target),
    )?;

    log_status!(log_target, "Running Disko partitioning on target...");
    let run_disko_cmd = format!("{} --mode disko", disko_script_path);
    CommandExecutor::execute_ssh(&target_ssh, &run_disko_cmd, Arc::clone(&log_target))?;
    log_status!(log_target, "Disko partitioning complete.");

    // --- Phase 5: Setup Physical Swapfile on /mnt ---
    if low_mem {
        setup_physical_swapfile(&target_ssh, Arc::clone(&log_target))?;
    }

    // --- Phase 6: Build/Realise System Configuration ---
    log_status!(log_target, "Building/realizing target system configuration (toplevel)...");
    let system_path = builder.build_system(Some("/mnt"), Arc::clone(&log_target))?;
    log_status!(log_target, "System toplevel path: {}", system_path);

    // --- Phase 7: Run Identity Services Post-Install ---
    log_status!(log_target, "Running Identity Services Post-Install Staging...");
    let mount_path = Path::new("/mnt");
    for service in &identity_services {
        log_status!(log_target, "Executing post-install for service: {}", service.id());
        service.post_install(ctx, mount_path)?;
    }

    // --- Phase 8: NixOS Installation ---
    log_status!(log_target, "Executing nixos-install on target...");
    let gc_env = if low_mem {
        "export GC_INITIAL_HEAP_SIZE=1M GC_DONT_GC=1 NIX_DISABLE_AUTO_GC=1; "
    } else {
        ""
    };
    let install_cmd = format!(
        "{}nixos-install --no-root-password --no-channel-copy --system {}",
        gc_env, system_path
    );
    CommandExecutor::execute_ssh(&target_ssh, &install_cmd, Arc::clone(&log_target))?;
    log_status!(log_target, "Nixos installation complete.");

    // --- Phase 9: Reboot ---
    log_status!(log_target, "Rebooting target system into the new production kernel...");
    let _ = CommandExecutor::execute_ssh(&target_ssh, "reboot", Arc::clone(&log_target));

    log_status!(log_target, "=========================================================================");
    let duration = start_time.elapsed();
    let mins = duration.as_secs() / 60;
    let secs = duration.as_secs() % 60;
    log_status!(log_target, "State Convergence Deployment successfully finished in {}m {}s!", mins, secs);
    log_status!(log_target, "Target system (IP: {}) is rebooting.", ctx.target_ip);
    log_status!(log_target, "=========================================================================");

    Ok(())
}

fn handle_kexec_takeover(
    _ctx: &RuntimeContext,
    target_ssh: &str,
    low_mem: bool,
    log_target: Arc<Mutex<LogTarget>>,
) -> Result<(), Box<dyn std::error::Error>> {
    let kexec_boot = env::var("KEXEC_BOOT").unwrap_or_else(|_| "auto".to_string());

    if kexec_boot == "no" {
        log_status!(log_target, "Kexec takeover bypassed by flag settings.");
        return Ok(());
    }

    if kexec_boot == "auto" {
        // Check if target is already booted into a live environment/installer
        let check_cmd = "if command -v nixos-install >/dev/null 2>&1; then echo \"NIXOS_LIVE\"; else echo \"OTHER_OS\"; fi";
        match CommandExecutor::execute_ssh(target_ssh, check_cmd, Arc::clone(&log_target)) {
            Ok(output) => {
                let cleaned = output.trim();
                if cleaned == "NIXOS_LIVE" {
                    let fs_cmd = "findmnt / -o FSTYPE -n";
                    if let Ok(fs_type) = CommandExecutor::execute_ssh(target_ssh, fs_cmd, Arc::clone(&log_target)) {
                        let fs_type = fs_type.trim();
                        if fs_type == "overlay" || fs_type == "squashfs" || fs_type == "tmpfs" || fs_type == "iso9660" {
                            log_status!(log_target, "Target is already booted into a live installer/ephemeral OS (FSTYPE={}). Bypassing Kexec.", fs_type);
                            return Ok(());
                        }
                    }
                }
            }
            Err(e) => {
                return Err(format!("Failed to connect to target for live OS check: {}", e).into());
            }
        }
    }

    log_status!(log_target, "Target requires in-memory boot transition (Kexec). Preparing...");

    // Query target architecture
    let arch_out = CommandExecutor::execute_ssh(target_ssh, "uname -m", Arc::clone(&log_target))?;
    let arch = arch_out.trim();
    if arch != "x86_64" && arch != "aarch64" {
        return Err(format!("Architecture unsupported for Kexec: {}", arch).into());
    }

    let kexec_base_url = crate::config::KEXEC_BASE_URL;
    let kexec_url = format!("{}-{}-linux.tar.gz", kexec_base_url, arch);

    log_status!(log_target, "Downloading kexec bundle from {}...", kexec_url);
    let download_cmd = format!(
        "mkdir -p /tmp/kexec && cd /tmp/kexec && \
         if command -v curl >/dev/null; then \
             curl -L '{}' -o kexec.tar.gz; \
         else \
             wget -O kexec.tar.gz '{}'; \
         fi && \
         tar -xzf kexec.tar.gz",
        kexec_url, kexec_url
    );
    CommandExecutor::execute_ssh(target_ssh, &download_cmd, Arc::clone(&log_target))?;

    // Optimize target memory if low-memory mode is active
    if low_mem {
        log_status!(log_target, "Tuning target memory parameters for in-memory boot...");
        let optimize_cmd = "
            systemctl stop snapd packagekit unattended-upgrades udisks2 2>/dev/null || true
            sync
            echo 3 | tee /proc/sys/vm/drop_caches >/dev/null
            if ! grep -q swap /proc/swaps; then
                fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
                chmod 600 /swapfile
                mkswap /swapfile
                swapon /swapfile
            fi
        ";
        let _ = CommandExecutor::execute_ssh(target_ssh, optimize_cmd, Arc::clone(&log_target));
    }

    log_status!(log_target, "Launching Kexec kernel takeover...");
    let exec_cmd = if low_mem {
        "sed -i 's/zswap.enabled=1/zswap.enabled=0/' run; \
         sed -i 's/--command-line \"/--command-line \"initrd.tmpfs.size=80% /' run; \
         nohup ./run > kexec.log 2>&1 &"
    } else {
        "nohup ./run > kexec.log 2>&1 &"
    };

    let run_kexec = format!(
        "cd /tmp/kexec && \
         if [ ! -f run ]; then \
             DIR=$(find . -maxdepth 2 -name run -type f -exec dirname {{}} \\; | head -n 1) && \
             [[ -n \"$DIR\" ]] && cd \"$DIR\"; \
         fi && \
         {}",
        exec_cmd
    );

    // Run this asynchronously, as the connection will drop during kexec
    let _ = CommandExecutor::execute_ssh(target_ssh, &run_kexec, Arc::clone(&log_target));

    log_status!(log_target, "Waiting 15 seconds for Kexec to initialize boot...");
    thread::sleep(Duration::from_secs(15));

    // Wait for SSH on root@target_ip
    wait_for_ssh(target_ssh, 300, Arc::clone(&log_target))?;
    log_status!(log_target, "Kexec takeover complete. Live installer is online.");

    Ok(())
}

fn setup_zram_swap(target_ssh: &str, log_target: Arc<Mutex<LogTarget>>) -> Result<(), Box<dyn std::error::Error>> {
    log_status!(log_target, "Low Memory Optimization: Allocating 3GB ZRAM swap space on target...");
    let swap_cmd = "
        modprobe zram 2>/dev/null || true
        echo 3221225472 > /sys/block/zram0/disksize 2>/dev/null || true
        mkswap /dev/zram0 >/dev/null 2>&1 || true
        swapon /dev/zram0 >/dev/null 2>&1 || true
    ";
    let _ = CommandExecutor::execute_ssh(target_ssh, swap_cmd, log_target);
    Ok(())
}

fn setup_physical_swapfile(target_ssh: &str, log_target: Arc<Mutex<LogTarget>>) -> Result<(), Box<dyn std::error::Error>> {
    log_status!(log_target, "Low Memory Optimization: Allocating 3GB physical swapfile on target at /mnt/swapfile...");
    let swap_cmd = "
        fallocate -l 3G /mnt/swapfile || dd if=/dev/zero of=/mnt/swapfile bs=1M count=3072 status=none
        chmod 600 /mnt/swapfile
        mkswap /mnt/swapfile
        swapon /mnt/swapfile
    ";
    let _ = CommandExecutor::execute_ssh(target_ssh, swap_cmd, log_target);
    Ok(())
}

fn wait_for_ssh(target_ssh: &str, timeout_secs: u64, log_target: Arc<Mutex<LogTarget>>) -> Result<(), Box<dyn std::error::Error>> {
    let interval = Duration::from_secs(5);
    let start = std::time::Instant::now();
    let timeout = Duration::from_secs(timeout_secs);

    log_status!(log_target, "Waiting for SSH connection on {}...", target_ssh);

    while start.elapsed() < timeout {
        let output = std::process::Command::new("ssh")
            .args(&[
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "LogLevel=ERROR",
                "-o", "ConnectTimeout=3",
                "-o", "PasswordAuthentication=no",
                target_ssh,
                "true",
            ])
            .output();

        if let Ok(out) = output {
            if out.status.success() {
                log_status!(log_target, "SSH connection established successfully.");
                return Ok(());
            }
        }

        thread::sleep(interval);
        let _ = writeln!(
            log_target.lock().unwrap().get_write_stream(),
            "Waiting... ({}s elapsed)",
            start.elapsed().as_secs()
        );
    }

    Err(format!("Timed out waiting for SSH on {} after {} seconds", target_ssh, timeout_secs).into())
}
