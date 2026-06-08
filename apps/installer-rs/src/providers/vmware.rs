use super::VirtualizationProvider;
use crate::context::RuntimeContext;
use crate::process::CommandExecutor;
use crate::process::Logger;
use std::env;
use std::fs;
use std::path::Path;
use std::thread;
use std::time::Duration;

pub struct VmwareProvider {
    vmx_path: String,
    hostname: String,
    system: String,
    disk_size: String,
    vmrun_bin: String,
    logger: Logger,
}

impl VmwareProvider {
    pub fn new(ctx: &RuntimeContext, logger: Logger) -> Self {
        let vmx_path = ctx.deployment.vmware.vmx_path.clone();
        let vmrun_bin = resolve_vmrun_path();

        Self {
            vmx_path,
            hostname: ctx.hostname.clone(),
            system: ctx.system.clone(),
            disk_size: ctx.deployment.disk_size.clone(),
            vmrun_bin,
            logger,
        }
    }

    fn is_running(&self) -> bool {
        let args = ["-T", "fusion", "list"];
        let silent_log = Logger::silent();
        if let Ok(out) = CommandExecutor::execute(&self.vmrun_bin, &args, silent_log) {
            out.contains(&self.vmx_path)
        } else {
            false
        }
    }
}

impl VirtualizationProvider for VmwareProvider {
    fn exists(&self) -> bool {
        if self.vmx_path.is_empty() {
            false
        } else {
            Path::new(&self.vmx_path).exists()
        }
    }

    fn create(&self) -> Result<(), Box<dyn std::error::Error>> {
        if self.vmx_path.is_empty() {
            return Err("VMware VMX path is not configured".into());
        }

        if self.is_running() || self.exists() {
            info!(
                self.logger,
                "VMware VM is already running or configuration exists."
            );
            return Ok(());
        }

        let vmx_path = Path::new(&self.vmx_path);
        let vmx_dir = vmx_path
            .parent()
            .ok_or_else(|| format!("Invalid VMX path: {}", self.vmx_path))?;
        let vm_name = vmx_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or(&self.hostname);

        // Determine CPU architecture
        let target_arch = if self.system.contains("x86_64") {
            "x86_64"
        } else {
            "aarch64"
        };

        // Find or download NixOS Minimal ISO
        let iso_dir_str = env::var("DEFAULT_VMW_ISO_DIR")
            .unwrap_or_else(|_| crate::config::DEFAULT_VMW_ISO_DIR.to_string());
        let iso_dir = Path::new(&iso_dir_str);
        fs::create_dir_all(iso_dir)?;

        let custom_iso_name = format!(
            "nixos-minimal-{}-{}-linux.iso",
            crate::config::nixos_iso_version(),
            target_arch
        );
        let custom_iso = iso_dir.join(&custom_iso_name);
        let official_iso_name = format!("latest-nixos-minimal-{}-linux.iso", target_arch);
        let official_iso = iso_dir.join(&official_iso_name);
        let mut local_iso = None;

        // 1. Check workspace own-built ISO first (using config.rs helper)
        if let Some(workspace_iso) = crate::config::find_custom_iso(target_arch) {
            info!(
                self.logger,
                "Found workspace own-built NixOS ISO: {}",
                workspace_iso.display()
            );
            let target_dest = iso_dir.join(workspace_iso.file_name().unwrap());
            if !target_dest.exists() {
                info!(
                    self.logger,
                    "Copying workspace own-built ISO to target directory: {}...",
                    target_dest.display()
                );
                if let Err(e) = fs::copy(&workspace_iso, &target_dest) {
                    warn!(
                        self.logger,
                        "Warning: Failed to copy own-built ISO from workspace: {:?}", e
                    );
                }
            }
            if target_dest.exists() {
                local_iso = Some(target_dest);
            }
        }

        // 2. Fallback to custom ISO name in default ISO dir
        if local_iso.is_none() && custom_iso.exists() {
            info!(
                self.logger,
                "Own-built custom NixOS ISO found: {}",
                custom_iso.display()
            );
            local_iso = Some(custom_iso);
        }

        // 3. Fallback to official ISO name in default ISO dir
        if local_iso.is_none() && official_iso.exists() {
            info!(
                self.logger,
                "Official NixOS ISO found: {}",
                official_iso.display()
            );
            local_iso = Some(official_iso.clone());
        }

        // 4. Wildcard fallback search in default ISO dir
        if local_iso.is_none() {
            if let Ok(entries) = fs::read_dir(iso_dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.is_file() {
                        if let Some(filename) = path.file_name().and_then(|s| s.to_str()) {
                            let match_custom = filename.starts_with("nixos-minimal-")
                                && filename.contains(target_arch)
                                && filename.ends_with(".iso");
                            let match_generic =
                                filename.contains(target_arch) && filename.ends_with(".iso");
                            if match_custom || match_generic {
                                info!(self.logger, "Fallback NixOS ISO found: {}", path.display());
                                local_iso = Some(path);
                                break;
                            }
                        }
                    }
                }
            }
        }

        let selected_iso = match local_iso {
            Some(iso) => iso,
            None => {
                let channel = crate::config::nixos_channel();
                let download_url = format!(
                    "https://channels.nixos.org/{}/latest-nixos-minimal-{}-linux.iso",
                    channel, target_arch
                );
                if !official_iso.exists() {
                    warn!(
                        self.logger,
                        "WARNING: Custom built ISO not found in {}. Downloading official NixOS minimal ISO.\n\
                         Because the official ISO does not contain your SSH public key, you MUST log in to the VM console once booted and run:\n\n\
                         mkdir -p ~/.ssh && echo '{}' >> ~/.ssh/authorized_keys\n\n\
                         The installer will poll and wait for up to 5 minutes for the SSH connection to become available.",
                        iso_dir.display(),
                        crate::config::ssh_auth_key()
                    );

                    let curl_args = ["-L", &download_url, "-o", &official_iso.to_string_lossy()];
                    CommandExecutor::execute("curl", &curl_args, self.logger.clone())?;

                    if !official_iso.exists() {
                        return Err(
                            format!("Failed to download NixOS ISO from {}", download_url).into(),
                        );
                    }
                } else {
                    warn!(
                        self.logger,
                        "WARNING: Custom built ISO not found. Using existing official NixOS minimal ISO.\n\
                         Because the official ISO does not contain your SSH public key, you MUST log in to the VM console once booted and run:\n\n\
                         mkdir -p ~/.ssh && echo '{}' >> ~/.ssh/authorized_keys\n\n\
                         The installer will poll and wait for up to 5 minutes for the SSH connection to become available.",
                        crate::config::ssh_auth_key()
                    );
                }
                official_iso
            }
        };

        info!(
            self.logger,
            "NixOS ISO selected: {}",
            selected_iso.display()
        );

        // Always use "Virtual Disk.vmdk" for the disk name
        let disk_name = "Virtual Disk.vmdk";

        // Create Virtual Disk (.vmdk) using vmware-vdiskmanager
        let vdiskmanager = resolve_vdiskmanager_path();
        let env_disk_size = env::var("VM_DISK_SIZE").unwrap_or_else(|_| {
            if self.disk_size.is_empty() {
                "50".to_string()
            } else {
                self.disk_size.clone()
            }
        });

        info!(
            self.logger,
            "Creating {}GB VMware virtual disk ({}) at {:?}...", env_disk_size, disk_name, vmx_dir
        );
        fs::create_dir_all(vmx_dir)?;

        let size_arg = format!("{}GB", env_disk_size);
        let disk_path = vmx_dir.join(disk_name);

        let manager_args = [
            "-c",
            "-s",
            &size_arg,
            "-a",
            "lsilogic",
            "-t",
            "0",
            &disk_path.to_string_lossy(),
        ];

        CommandExecutor::execute(&vdiskmanager, &manager_args, self.logger.clone())?;

        // Generate VMX file content from scratch
        let cores = env::var("VM_CORES").unwrap_or_else(|_| "4".to_string());
        let memory = env::var("VM_MEMORY").unwrap_or_else(|_| "4096".to_string());

        info!(
            self.logger,
            "Generating VMX configuration file at {}...", self.vmx_path
        );
        let vmx_content = generate_vmx_content(
            vm_name,
            disk_name,
            &selected_iso.to_string_lossy(),
            target_arch,
            &cores,
            &memory,
        );
        fs::write(vmx_path, vmx_content)?;
        info!(
            self.logger,
            "VMware VMX configuration generated successfully."
        );

        info!(
            self.logger,
            "Starting VMware VM from VMX path: {}...", self.vmx_path
        );
        let args = ["-T", "fusion", "start", &self.vmx_path, "gui"];
        CommandExecutor::execute(&self.vmrun_bin, &args, self.logger.clone())?;
        Ok(())
    }

    fn destroy(&self) -> Result<(), Box<dyn std::error::Error>> {
        if self.is_running() {
            info!(self.logger, "Stopping VMware VM...");
            let stop_args = ["-T", "fusion", "stop", &self.vmx_path, "hard"];
            let _ = CommandExecutor::execute(&self.vmrun_bin, &stop_args, self.logger.clone());
        }

        info!(self.logger, "Deleting VMware VM configurations...");
        let delete_args = ["-T", "fusion", "deleteVM", &self.vmx_path];
        let _ = CommandExecutor::execute(&self.vmrun_bin, &delete_args, self.logger.clone());

        // Clean directory files (vmdk, logs, locks)
        let vmx_path = Path::new(&self.vmx_path);
        if vmx_path.exists() {
            let _ = fs::remove_file(vmx_path);
        }
        if let Some(parent) = vmx_path.parent() {
            if parent.exists() {
                info!(self.logger, "Removing VM directory manually: {:?}", parent);
                let _ = fs::remove_dir_all(parent);
            }
        }

        Ok(())
    }

    fn get_ip(&self, poll: bool) -> Result<String, Box<dyn std::error::Error>> {
        // 1. Parse MAC Address from .vmx file
        let mac = parse_mac_from_vmx(&self.vmx_path).ok_or_else(|| {
            format!(
                "Failed to read ethernet MAC address from VMX file at {}",
                self.vmx_path
            )
        })?;

        info!(
            self.logger,
            "Locating DHCP lease for MAC address: {}...", mac
        );

        if !poll {
            if let Some(ip) = find_ip_in_leases(&mac) {
                return Ok(ip);
            }
            return Err("VM IP not immediately available in DHCP leases".into());
        }

        // 2. Poll lease files for MAC matching IP address (up to 60 times / 60 seconds)
        for _ in 0..60 {
            if let Some(ip) = find_ip_in_leases(&mac) {
                return Ok(ip);
            }
            thread::sleep(Duration::from_secs(1));
        }

        Err("Failed to resolve VMware VM IP address from DHCP lease files".into())
    }
}

fn resolve_vmrun_path() -> String {
    let paths = [
        "/Applications/VMware Fusion.app/Contents/Public/vmrun",
        "/Applications/VMware Fusion.app/Contents/Library/vmrun",
    ];

    for path in &paths {
        if Path::new(path).exists() {
            return path.to_string();
        }
    }

    "vmrun".to_string() // Fallback to PATH search
}

fn resolve_vdiskmanager_path() -> String {
    let paths = [
        "/Applications/VMware Fusion.app/Contents/Library/vmware-vdiskmanager",
        "/Applications/VMware Fusion.app/Contents/Public/vmware-vdiskmanager",
    ];

    for path in &paths {
        if Path::new(path).exists() {
            return path.to_string();
        }
    }

    "vmware-vdiskmanager".to_string() // Fallback to PATH search
}

fn generate_vmx_content(
    name: &str,
    disk_name: &str,
    iso_path: &str,
    arch: &str,
    cores: &str,
    memory: &str,
) -> String {
    let guest_os = if arch == "x86_64" {
        "other6xlinux-64"
    } else {
        "arm-other6xlinux-64"
    };
    let net_dev = if arch == "x86_64" {
        "e1000e"
    } else {
        "vmxnet3"
    };

    let raw_template = include_str!("vmx_config.template");
    raw_template
        .replace("@name@", name)
        .replace("@guest_os@", guest_os)
        .replace("@cores@", cores)
        .replace("@memory@", memory)
        .replace("@disk_name@", disk_name)
        .replace("@iso_path@", iso_path)
        .replace("@net_dev@", net_dev)
}

fn parse_mac_from_vmx(vmx_path: &str) -> Option<String> {
    let content = fs::read_to_string(vmx_path).ok()?;
    for line in content.lines() {
        if line
            .to_lowercase()
            .starts_with("ethernet0.generatedaddress")
        {
            let parts: Vec<&str> = line.split('=').collect();
            if parts.len() >= 2 {
                let mac = parts[1].trim().trim_matches('"').trim().to_lowercase();
                return Some(mac);
            }
        }
    }
    None
}

fn find_ip_in_leases(mac: &str) -> Option<String> {
    let lease_dir = "/var/db/vmware";
    let mut lease_files = Vec::new();

    if let Ok(entries) = fs::read_dir(lease_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.starts_with("vmnet-dhcpd-") && name.ends_with(".leases") {
                    lease_files.push(path);
                }
            }
        }
    }

    for path in lease_files {
        if let Ok(content) = fs::read_to_string(&path) {
            let mut current_ip = String::new();
            for line in content.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with("lease ") {
                    if let Some(ip) = trimmed.split_whitespace().nth(1) {
                        current_ip = ip.to_string();
                    }
                } else if trimmed.starts_with("hardware ethernet ") {
                    let parts: Vec<&str> = trimmed.split_whitespace().collect();
                    if parts.len() >= 3 {
                        let file_mac = parts[2].trim_end_matches(';').trim().to_lowercase();
                        if file_mac == mac {
                            return Some(current_ip);
                        }
                    }
                }
            }
        }
    }

    None
}
