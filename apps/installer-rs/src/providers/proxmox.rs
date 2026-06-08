use super::VirtualizationProvider;
use crate::context::RuntimeContext;
use crate::fleet::resolution::is_valid_target_ip;
use crate::process::CommandExecutor;
use crate::process::Logger;
use std::env;
use std::thread;
use std::time::Duration;

pub struct ProxmoxProvider {
    vmid: String,
    hostname: String,
    pve_host: String,
    bios: String,
    disk_bus: String,
    scsi_hw: String,
    disk_size: String,
    cores: String,
    memory: String,
    iso_flavor: String,
    iso_storage: String,
    iso_custom_path: String,
    disk_storage: String,
    network: String,
    extra_networks: Vec<String>,
    pxe: bool,
    target_ip: String,
    ssh_proxy_jump: String,
    cloud_init_image: String,
    cloud_init_user: String,
    cloud_init_ipconfig0: String,
    cloud_init_ipconfig1: String,
    logger: Logger,
}

impl ProxmoxProvider {
    pub fn new(ctx: &RuntimeContext, logger: Logger) -> Self {
        Self {
            vmid: ctx.deployment.vmid.clone(),
            hostname: ctx.hostname.clone(),
            pve_host: ctx.deployment.proxmox.host.clone(),
            bios: ctx.deployment.proxmox.bios.clone(),
            disk_bus: ctx.deployment.proxmox.disk_bus.clone(),
            scsi_hw: ctx.deployment.proxmox.scsi_hw.clone(),
            disk_size: ctx.deployment.disk_size.clone(),
            cores: ctx.deployment.proxmox.cores.clone(),
            memory: ctx.deployment.proxmox.memory.clone(),
            iso_flavor: ctx.deployment.proxmox.iso.flavor.clone(),
            iso_storage: ctx.deployment.proxmox.iso.storage.clone(),
            iso_custom_path: ctx.deployment.proxmox.iso.custom_path.clone(),
            disk_storage: ctx.deployment.proxmox.disk_storage.clone(),
            network: ctx.deployment.proxmox.network.clone(),
            extra_networks: ctx.deployment.proxmox.extra_networks.clone(),
            pxe: ctx.deployment.proxmox.pxe,
            target_ip: ctx.target_ip.clone(),
            ssh_proxy_jump: ctx.deployment.ssh_proxy_jump.clone(),
            cloud_init_image: ctx.deployment.proxmox.cloud_init.image.clone(),
            cloud_init_user: ctx.deployment.proxmox.cloud_init.user.clone(),
            cloud_init_ipconfig0: ctx.deployment.proxmox.cloud_init.ipconfig0.clone(),
            cloud_init_ipconfig1: ctx.deployment.proxmox.cloud_init.ipconfig1.clone(),
            logger,
        }
    }
}

impl VirtualizationProvider for ProxmoxProvider {
    fn exists(&self) -> bool {
        let ssh_target = format!("root@{}", self.pve_host);
        let status_cmd = format!("qm status {}", self.vmid);
        let silent_log = Logger::silent();
        CommandExecutor::execute_ssh(&ssh_target, &status_cmd, silent_log).is_ok()
    }

    fn create(&self) -> Result<(), Box<dyn std::error::Error>> {
        let ssh_target = format!("root@{}", self.pve_host);

        // Preflight checks: verify that all configured network bridges exist on Proxmox
        let mut bridges = Vec::new();
        if let Some(b) = extract_bridge_name(&self.network) {
            bridges.push(b);
        }
        for net in &self.extra_networks {
            if let Some(b) = extract_bridge_name(net) {
                bridges.push(b);
            }
        }

        if !bridges.is_empty() {
            bridges.sort_unstable();
            bridges.dedup();

            info!(
                self.logger,
                "Performing preflight checks on Proxmox host {} for bridges: {:?}",
                self.pve_host,
                bridges
            );
            for bridge in &bridges {
                let bridge_cmd = format!("ip link show {}", bridge);
                if let Err(e) =
                    CommandExecutor::execute_ssh(&ssh_target, &bridge_cmd, Logger::silent())
                {
                    return Err(format!(
                        "Preflight check failed: Bridge '{}' does not exist or is inactive on Proxmox host {}: {}",
                        bridge, self.pve_host, e
                    ).into());
                }

                // If this is an isolated bridge, check for host IP and physical ports
                if *bridge == "vmbrPxe" || *bridge == "vmbrTestWan" {
                    // Check for host IP address (IPv4 or IPv6, excluding link-local)
                    let ip_check_cmd = format!("ip -o addr show dev {}", bridge);
                    if let Ok(ip_out) =
                        CommandExecutor::execute_ssh(&ssh_target, &ip_check_cmd, Logger::silent())
                    {
                        if ip_out.contains("inet ")
                            || (ip_out.contains("inet6 ") && !ip_out.contains(" fe80::"))
                        {
                            return Err(format!(
                                "Preflight check failed: Isolated bridge '{}' has a host IP address assigned: {}",
                                bridge, ip_out.trim()
                            ).into());
                        }
                    }

                    // Check for physical ports on the bridge using sysfs
                    let port_check_cmd = format!(
                        "for p in /sys/class/net/{}/brif/*; do [ -d \"$p\" ] && [ -e \"/sys/class/net/$(basename \"$p\")/device\" ] && echo \"$(basename \"$p\")\"; done",
                        bridge
                    );
                    if let Ok(port_out) =
                        CommandExecutor::execute_ssh(&ssh_target, &port_check_cmd, Logger::silent())
                    {
                        let ports: Vec<&str> = port_out
                            .lines()
                            .map(|l| l.trim())
                            .filter(|l| !l.is_empty())
                            .collect();
                        if !ports.is_empty() {
                            return Err(format!(
                                "Preflight check failed: Isolated bridge '{}' has physical ports attached: {:?}",
                                bridge, ports
                            ).into());
                        }
                    }
                }
            }
        }

        // If the VM has a proxy jump configured, ensure the proxy jump VM is active
        if !self.ssh_proxy_jump.is_empty() {
            if let Some(jump_vmid) = crate::context::find_vmid_for_proxy_jump(&self.ssh_proxy_jump)
            {
                info!(
                    self.logger,
                    "Checking if proxy jump VM (VMID {}) is running...", jump_vmid
                );
                let jump_status_cmd = format!("qm status {}", jump_vmid);
                let jump_status =
                    CommandExecutor::execute_ssh(&ssh_target, &jump_status_cmd, Logger::silent())?;
                if !jump_status.contains("status: running") {
                    return Err(format!(
                        "Preflight check failed: Proxy jump VM (VMID {}) is not running on Proxmox host {}. Found status: {}",
                        jump_vmid, self.pve_host, jump_status.trim()
                    ).into());
                }
            }
        }

        if self.exists() {
            info!(
                self.logger,
                "Proxmox VM {} already exists. Reusing instance.", self.vmid
            );
            return Ok(());
        }

        let vm_storage = env::var("VM_STORAGE").unwrap_or_else(|_| {
            if self.disk_storage.is_empty() {
                crate::config::proxmox_default_disk_storage()
            } else {
                self.disk_storage.clone()
            }
        });
        let disk_size_val = if self.disk_size.is_empty() {
            "50"
        } else {
            &self.disk_size
        };

        let cores_val = if self.cores.is_empty() {
            "4"
        } else {
            &self.cores
        };

        let memory_val = if self.memory.is_empty() {
            "4096"
        } else {
            &self.memory
        };
        let vga_val = match env::var("VM_VGA").as_deref() {
            Ok("serial0") => "serial0",
            Ok("std") | Err(_) => "std",
            Ok(value) => {
                return Err(format!(
                    "Unsupported VM_VGA value '{}'; expected 'std' or 'serial0'",
                    value
                )
                .into());
            }
        };

        let bios_args = if self.bios == "ovmf" {
            format!("--bios ovmf --efidisk0 {}:1", vm_storage)
        } else {
            "--bios seabios".to_string()
        };

        let vm_net0_bridge = if self.network.is_empty() {
            crate::config::proxmox_default_network()
        } else {
            self.network.clone()
        };

        if self.pxe {
            // PXE-Boot Proxmox VM flow
            info!(
                self.logger,
                "Provisioning PXE-Boot Proxmox VM {} ({}) on {}...",
                self.vmid,
                self.hostname,
                self.pve_host
            );

            let disk_args = format!("--virtio0 {}:{}", vm_storage, disk_size_val);

            let mut extra_net_args = String::new();
            if !self.extra_networks.is_empty() {
                for (i, net_config) in self.extra_networks.iter().enumerate() {
                    extra_net_args.push_str(&format!(" --net{} {}", i + 1, net_config));
                }
            }

            let create_cmd = format!(
                "qm create {} \
                 --name {} \
                 --memory {} \
                 --cores {} \
                 --net0 {} \
                 {} \
                 --bios seabios \
                 --boot order=virtio0\\;net0 \
                 --serial0 socket \
                 --vga {} \
                 --agent enabled=1 \
                 --autostart 1 \
                 --rng0 source=/dev/urandom{}",
                self.vmid,
                self.hostname,
                memory_val,
                cores_val,
                vm_net0_bridge,
                disk_args,
                vga_val,
                extra_net_args
            );

            CommandExecutor::execute_ssh(&ssh_target, &create_cmd, self.logger.clone())?;
        } else if self.cloud_init_image.is_empty() {
            // NixOS installer ISO flow
            info!(
                self.logger,
                "Provisioning NixOS Proxmox VM {} ({}) on {}...",
                self.vmid,
                self.hostname,
                self.pve_host
            );

            let cdrom_val = crate::operation::plan_iso::expected_iso_path_from_config(
                &self.pve_host,
                &self.cloud_init_image,
                &self.iso_custom_path,
                &self.iso_flavor,
                &self.iso_storage,
            )
            .ok_or("Proxmox ISO path could not be determined for NixOS installer flow")?;
            let (_, iso_exists) = crate::operation::plan_iso::probe_pvesm(&ssh_target, &cdrom_val);
            if !iso_exists {
                return Err(format!(
                    "ISO '{}' is not staged on Proxmox. Re-run deploy and approve ISO staging after confirmation.",
                    cdrom_val
                )
                .into());
            }

            // Determine disk args and boot disk
            // Use scsi_hw from deployment config (e.g. virtio-scsi-pci, virtio-scsi-single).
            // Falls back to virtio-scsi-pci if not set.
            let (disk_args, boot_disk) = {
                let hw = if self.scsi_hw.is_empty() {
                    "virtio-scsi-pci"
                } else {
                    &self.scsi_hw
                };
                if self.disk_bus == "scsi" {
                    (
                        format!("--scsihw {} --scsi0 {}:{}", hw, vm_storage, disk_size_val),
                        "scsi0",
                    )
                } else {
                    (
                        format!("--scsihw {} --virtio0 {}:{}", hw, vm_storage, disk_size_val),
                        "virtio0",
                    )
                }
            };

            let mut extra_net_args = String::new();
            if !self.extra_networks.is_empty() {
                for (i, net_config) in self.extra_networks.iter().enumerate() {
                    extra_net_args.push_str(&format!(" --net{} {}", i + 1, net_config));
                }
            }

            let create_cmd = format!(
                "qm create {} \
                 --name {} \
                 --memory {} \
                 --cores {} \
                 --net0 {} \
                 {} \
                 {} \
                 --ide0 {}:cloudinit \
                 --ipconfig0 ip=dhcp \
                 --cdrom {},media=cdrom \
                 --boot order={}\\;ide2\\;net0 \
                 --serial0 socket \
                 --agent enabled=1 \
                 --autostart 1 \
                 --rng0 source=/dev/urandom{}",
                self.vmid,
                self.hostname,
                memory_val,
                cores_val,
                vm_net0_bridge,
                disk_args,
                bios_args,
                vm_storage,
                cdrom_val,
                boot_disk,
                extra_net_args
            );

            CommandExecutor::execute_ssh(&ssh_target, &create_cmd, self.logger.clone())?;
        } else {
            // Cloud-Init VM templates flow
            info!(
                self.logger,
                "Provisioning Cloud-Init Proxmox VM {} ({}) on {}...",
                self.vmid,
                self.hostname,
                self.pve_host
            );

            let ssh_key = crate::config::ssh_auth_key();

            let ipconfig0_val = if !self.cloud_init_ipconfig0.is_empty() {
                &self.cloud_init_ipconfig0
            } else {
                "ip=dhcp"
            };

            let mut extra_args = String::new();
            if !self.cloud_init_ipconfig1.is_empty() {
                extra_args.push_str(&format!(" --ipconfig1 {}", self.cloud_init_ipconfig1));
            }
            if !self.cloud_init_user.is_empty() {
                extra_args.push_str(&format!(" --ciuser {}", self.cloud_init_user));
            }

            let temp_key_file = format!("/tmp/ssh_key_{}.pub", self.vmid);

            // For cloud-init VMs using scsi disk bus, set the SCSI controller type from
            // deployment config (scsiHw). Without a VirtIO SCSI controller, Proxmox
            // defaults to lsi, causing the kernel to hang at "crng init done".
            // When diskBus is not "scsi" (or empty), use virtio0 — no scsihw needed
            // (matches installer2 behaviour).
            let ci_scsihw_arg = if self.disk_bus == "scsi" && !self.scsi_hw.is_empty() {
                format!(" --scsihw {}", self.scsi_hw)
            } else {
                String::new()
            };

            let init_cmd = format!(
                "echo '{}' > {} && \
                 qm create {} \
                 --name {} \
                 --memory {} \
                 --cores {} \
                 --net0 {} \
                 --ipconfig0 {} \
                 --ide2 {}:cloudinit \
                 --serial0 socket \
                 --agent enabled=1 \
                 --autostart 1 \
                 {} \
                 {} \
                 {} \
                 --sshkeys {} \
                 --rng0 source=/dev/urandom",
                ssh_key,
                temp_key_file,
                self.vmid,
                self.hostname,
                memory_val,
                cores_val,
                vm_net0_bridge,
                ipconfig0_val,
                vm_storage,
                bios_args,
                ci_scsihw_arg,
                extra_args,
                temp_key_file
            );
            CommandExecutor::execute_ssh(&ssh_target, &init_cmd, self.logger.clone())?;

            info!(
                self.logger,
                "Importing cloud-init disk image {} to VM {} on storage {}...",
                self.cloud_init_image,
                self.vmid,
                vm_storage
            );
            let import_cmd = format!(
                "qm importdisk {} {} {}",
                self.vmid, self.cloud_init_image, vm_storage
            );
            CommandExecutor::execute_ssh(&ssh_target, &import_cmd, self.logger.clone())?;

            // Find the imported disk name
            let config_cmd = format!("qm config {}", self.vmid);
            let config_out =
                CommandExecutor::execute_ssh(&ssh_target, &config_cmd, self.logger.clone())?;

            // Find line matching `unused[0-9]+:`
            let imported_disk = config_out.lines()
                .find(|line| line.trim().starts_with("unused"))
                .and_then(|line| line.split_once(':'))
                .map(|(_, val)| val.split(',').next().unwrap_or("").trim().to_string())
                .ok_or_else(|| {
                    format!("Failed to locate imported disk in VM {} configuration. qm config output:\n{}", self.vmid, config_out)
                })?;

            // Cloud-init VMs: use virtio0 by default (no scsihw needed, matches installer2).
            // Only use scsi0 when disk_bus is explicitly set to "scsi".
            let (root_disk, boot_disk) = if self.disk_bus == "scsi" {
                ("scsi0", "scsi0")
            } else {
                ("virtio0", "virtio0")
            };

            info!(
                self.logger,
                "Attaching imported disk {} as {}...", imported_disk, root_disk
            );
            let attach_cmd = format!("qm set {} --{} {}", self.vmid, root_disk, imported_disk);
            CommandExecutor::execute_ssh(&ssh_target, &attach_cmd, self.logger.clone())?;

            let boot_cmd = format!(
                "qm set {} --boot 'order={};ide2;net0'",
                self.vmid, boot_disk
            );
            CommandExecutor::execute_ssh(&ssh_target, &boot_cmd, self.logger.clone())?;

            info!(
                self.logger,
                "Resizing VM {} root disk to {}GB...", self.vmid, disk_size_val
            );
            let resize_cmd = format!("qm resize {} {} {}G", self.vmid, root_disk, disk_size_val);
            CommandExecutor::execute_ssh(&ssh_target, &resize_cmd, self.logger.clone())?;

            let clean_cmd = format!("rm -f {}", temp_key_file);
            let _ = CommandExecutor::execute_ssh(&ssh_target, &clean_cmd, self.logger.clone());
        }

        info!(
            self.logger,
            "Starting Proxmox VM {} on {}...", self.vmid, self.pve_host
        );
        let start_cmd = format!("qm start {}", self.vmid);
        CommandExecutor::execute_ssh(&ssh_target, &start_cmd, self.logger.clone())?;

        Ok(())
    }

    fn destroy(&self) -> Result<(), Box<dyn std::error::Error>> {
        let ssh_target = format!("root@{}", self.pve_host);

        info!(
            self.logger,
            "Requesting stop for Proxmox VM {} on {}...", self.vmid, self.pve_host
        );
        let stop_cmd = format!("qm stop {}", self.vmid);
        let _ = CommandExecutor::execute_ssh(&ssh_target, &stop_cmd, self.logger.clone());

        info!(
            self.logger,
            "Requesting destroy for Proxmox VM {}...", self.vmid
        );
        let destroy_cmd = format!("qm destroy {}", self.vmid);
        CommandExecutor::execute_ssh(&ssh_target, &destroy_cmd, self.logger.clone())?;
        Ok(())
    }

    fn get_ip(&self, poll: bool) -> Result<String, Box<dyn std::error::Error>> {
        if self.pxe || !self.ssh_proxy_jump.is_empty() {
            return Ok(self.target_ip.clone());
        }

        let ssh_target = format!("root@{}", self.pve_host);
        let silent_log = Logger::silent();

        // Scan for VM MAC address to find assigned DHCP IP
        info!(
            self.logger,
            "Locating Proxmox VM {} IP address...", self.vmid
        );
        let mac_cmd = format!("qm config {} | grep -E '^net0:'", self.vmid);
        let config_out = CommandExecutor::execute_ssh(&ssh_target, &mac_cmd, silent_log.clone())?;

        // Extract MAC address dynamically from key=value format (e.g. virtio=BC:24:11:7C:F4:10)
        let mac = config_out
            .split([',', ' ', '\n'])
            .find(|part| part.contains('='))
            .and_then(|part| part.split('=').nth(1))
            .map(|val| val.trim().to_lowercase());

        if let Some(mac_addr) = mac {
            info!(
                self.logger,
                "Found VM MAC address: {}. Querying network tables...", mac_addr
            );

            // 1. Try immediate resolution (no sleep)
            if let Some(ip) =
                try_fast_resolve(&ssh_target, &mac_addr, &self.vmid, silent_log.clone())
            {
                return Ok(ip);
            }
            if let Some(ip) = try_subnet_scan(&ssh_target, &mac_addr, silent_log.clone()) {
                return Ok(ip);
            }

            if !poll {
                return Err("VM IP not resolved immediately and polling is disabled".into());
            }

            // 2. Fall back to polling only if VM is booting/not yet resolved (up to 30 times with 2-second sleep)
            info!(
                self.logger,
                "VM IP not resolved immediately. Polling hypervisor for boot network status..."
            );

            for _ in 0..30 {
                thread::sleep(Duration::from_secs(2));
                if let Some(ip) =
                    try_fast_resolve(&ssh_target, &mac_addr, &self.vmid, silent_log.clone())
                {
                    return Ok(ip);
                }
                if let Some(ip) = try_subnet_scan(&ssh_target, &mac_addr, silent_log.clone()) {
                    return Ok(ip);
                }
            }
        }

        Err("Failed to resolve Proxmox VM IP address".into())
    }
}

fn try_fast_resolve(
    ssh_target: &str,
    mac_addr: &str,
    vmid: &str,
    silent_log: Logger,
) -> Option<String> {
    // Try ip neigh cache
    let query_cmd = format!("ip neigh | grep -i '{}' | awk '{{print $1}}'", mac_addr);
    if let Ok(ip_out) = CommandExecutor::execute_ssh(ssh_target, &query_cmd, silent_log.clone()) {
        let mut fallback_ipv6 = None;
        for line in ip_out.lines() {
            let ip = line.trim().to_string();
            if !ip.is_empty() {
                if let Ok(parsed_ip) = ip.parse::<std::net::IpAddr>() {
                    if is_valid_target_ip(&parsed_ip) {
                        if parsed_ip.is_ipv4() {
                            return Some(ip);
                        } else if fallback_ipv6.is_none() {
                            fallback_ipv6 = Some(ip);
                        }
                    }
                }
            }
        }
        if let Some(ipv6) = fallback_ipv6 {
            return Some(ipv6);
        }
    }

    // Try qm guest cmd network-get-interfaces
    let guest_cmd = format!("qm guest cmd {} network-get-interfaces 2>/dev/null", vmid);
    if let Ok(guest_out) = CommandExecutor::execute_ssh(ssh_target, &guest_cmd, silent_log) {
        if let Ok(val) = serde_json::from_str::<serde_json::Value>(&guest_out) {
            if let Some(arr) = val.as_array() {
                let mut fallback_ipv6 = None;
                for interface in arr {
                    if let Some(ips) = interface.get("ip-addresses").and_then(|i| i.as_array()) {
                        for ip_info in ips {
                            if let Some(ip) = ip_info.get("ip-address").and_then(|ip| ip.as_str()) {
                                if let Ok(parsed_ip) = ip.parse::<std::net::IpAddr>() {
                                    if is_valid_target_ip(&parsed_ip) {
                                        if parsed_ip.is_ipv4() {
                                            return Some(ip.to_string());
                                        } else if fallback_ipv6.is_none() {
                                            fallback_ipv6 = Some(ip.to_string());
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if let Some(ipv6) = fallback_ipv6 {
                    return Some(ipv6);
                }
            }
        }
    }

    None
}

fn try_subnet_scan(ssh_target: &str, mac_addr: &str, silent_log: Logger) -> Option<String> {
    let networks = crate::config::default_networks();
    let scan_targets = if networks.is_empty() {
        vec!["192.168.1.0/24".to_string()]
    } else {
        networks
    };

    for subnet in scan_targets {
        let scan_cmd = format!(
            "nmap -sn -n {} | grep -i '{}' -B 2 | grep 'Nmap scan report' | awk '{{print $NF}}' | tr -d '()'",
            subnet, mac_addr
        );
        if let Ok(ip_out) = CommandExecutor::execute_ssh(ssh_target, &scan_cmd, silent_log.clone())
        {
            let ip = ip_out.trim().to_string();
            if !ip.is_empty() {
                if let Ok(parsed_ip) = ip.parse::<std::net::IpAddr>() {
                    if is_valid_target_ip(&parsed_ip) {
                        return Some(ip);
                    }
                }
            }
        }
    }
    None
}

fn extract_bridge_name(net_str: &str) -> Option<&str> {
    if let Some(pos) = net_str.find("bridge=") {
        let after_bridge = &net_str[pos + 7..];
        if let Some(comma_pos) = after_bridge.find(',') {
            Some(&after_bridge[..comma_pos])
        } else {
            Some(after_bridge)
        }
    } else {
        None
    }
}
