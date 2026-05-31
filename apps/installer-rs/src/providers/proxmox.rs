use super::VirtualizationProvider;
use crate::context::RuntimeContext;
use crate::process::CommandExecutor;
use crate::process::LogTarget;
use crate::log_status;
use std::env;
use std::sync::{Arc, Mutex};
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
    cloud_init_image: String,
    cloud_init_user: String,
    cloud_init_ipconfig0: String,
    cloud_init_ipconfig1: String,
    log_target: Arc<Mutex<LogTarget>>,
}

impl ProxmoxProvider {
    pub fn new(ctx: &RuntimeContext, log_target: Arc<Mutex<LogTarget>>) -> Self {
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
            cloud_init_image: ctx.deployment.proxmox.cloud_init.image.clone(),
            cloud_init_user: ctx.deployment.proxmox.cloud_init.user.clone(),
            cloud_init_ipconfig0: ctx.deployment.proxmox.cloud_init.ipconfig0.clone(),
            cloud_init_ipconfig1: ctx.deployment.proxmox.cloud_init.ipconfig1.clone(),
            log_target,
        }
    }
}

impl VirtualizationProvider for ProxmoxProvider {
    fn exists(&self) -> bool {
        let ssh_target = format!("root@{}", self.pve_host);
        let status_cmd = format!("qm status {}", self.vmid);
        CommandExecutor::execute_ssh(&ssh_target, &status_cmd, Arc::clone(&self.log_target)).is_ok()
    }

    fn create(&self) -> Result<(), Box<dyn std::error::Error>> {
        let ssh_target = format!("root@{}", self.pve_host);

        if self.exists() {
            println!("Proxmox VM {} already exists. Reusing instance.", self.vmid);
            return Ok(());
        }

        let vm_storage = env::var("VM_STORAGE").unwrap_or_else(|_| "arthurz2-lvm".to_string());
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

        let bios_args = if self.bios == "ovmf" {
            format!("--bios ovmf --efidisk0 {}:1", vm_storage)
        } else {
            "--bios seabios".to_string()
        };

        let vm_net0_bridge = env::var("VM_NET0").unwrap_or_else(|_| "virtio,bridge=vmbr1,tag=10".to_string());

        if self.cloud_init_image.is_empty() {
            // NixOS installer ISO flow
            println!("Provisioning NixOS Proxmox VM {} ({}) on {}...", self.vmid, self.hostname, self.pve_host);

            // Determine default ISO based on disk bus config
            let cdrom_val = {
                let default_iso = if self.disk_bus == "virtio" {
                    "arthurz2-dir:iso/nixos-minimal-25.05pre-git-x86_64-linux-qemu.iso".to_string()
                } else {
                    "arthurz2-dir:iso/nixos-minimal-25.05pre-git-x86_64-linux.iso".to_string()
                };
                env::var("NIXOS_ISO").unwrap_or_else(|_| default_iso)
            };

            // Determine disk args and boot disk
            // Use scsi_hw from deployment config (e.g. virtio-scsi-pci, virtio-scsi-single).
            // Falls back to virtio-scsi-pci if not set.
            let (disk_args, boot_disk) = if self.disk_bus == "scsi" {
                let hw = if self.scsi_hw.is_empty() { "virtio-scsi-pci" } else { &self.scsi_hw };
                (format!("--scsihw {} --scsi0 {}:{}", hw, vm_storage, disk_size_val), "scsi0")
            } else {
                (format!("--virtio0 {}:{}", vm_storage, disk_size_val), "virtio0")
            };

            let net1_arg = if let Ok(net1) = env::var("VM_NET1") {
                format!("--net1 {}", net1)
            } else {
                "".to_string()
            };

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
                self.vmid, self.hostname, memory_val, cores_val, vm_net0_bridge, disk_args, bios_args, vm_storage, cdrom_val, boot_disk, net1_arg
            );

            CommandExecutor::execute_ssh(&ssh_target, &create_cmd, Arc::clone(&self.log_target))?;
        } else {
            // Cloud-Init VM templates flow
            println!("Provisioning Cloud-Init Proxmox VM {} ({}) on {}...", self.vmid, self.hostname, self.pve_host);

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
                ssh_key, temp_key_file, self.vmid, self.hostname, memory_val, cores_val,
                vm_net0_bridge, ipconfig0_val, vm_storage, bios_args, ci_scsihw_arg, extra_args, temp_key_file
            );
            CommandExecutor::execute_ssh(&ssh_target, &init_cmd, Arc::clone(&self.log_target))?;

            println!("Importing cloud-init disk image {} to VM {} on storage {}...", self.cloud_init_image, self.vmid, vm_storage);
            let import_cmd = format!("qm importdisk {} {} {}", self.vmid, self.cloud_init_image, vm_storage);
            CommandExecutor::execute_ssh(&ssh_target, &import_cmd, Arc::clone(&self.log_target))?;

            // Find the imported disk name
            let config_cmd = format!("qm config {}", self.vmid);
            let config_out = CommandExecutor::execute_ssh(&ssh_target, &config_cmd, Arc::clone(&self.log_target))?;

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

            println!("Attaching imported disk {} as {}...", imported_disk, root_disk);
            let attach_cmd = format!("qm set {} --{} {}", self.vmid, root_disk, imported_disk);
            CommandExecutor::execute_ssh(&ssh_target, &attach_cmd, Arc::clone(&self.log_target))?;

            let boot_cmd = format!("qm set {} --boot 'order={};ide2;net0'", self.vmid, boot_disk);
            CommandExecutor::execute_ssh(&ssh_target, &boot_cmd, Arc::clone(&self.log_target))?;

            println!("Resizing VM {} root disk to {}GB...", self.vmid, disk_size_val);
            let resize_cmd = format!("qm resize {} {} {}G", self.vmid, root_disk, disk_size_val);
            CommandExecutor::execute_ssh(&ssh_target, &resize_cmd, Arc::clone(&self.log_target))?;

            let clean_cmd = format!("rm -f {}", temp_key_file);
            let _ = CommandExecutor::execute_ssh(&ssh_target, &clean_cmd, Arc::clone(&self.log_target));
        }

        println!("Starting Proxmox VM {} on {}...", self.vmid, self.pve_host);
        let start_cmd = format!("qm start {}", self.vmid);
        CommandExecutor::execute_ssh(&ssh_target, &start_cmd, Arc::clone(&self.log_target))?;

        Ok(())
    }

    fn destroy(&self) -> Result<(), Box<dyn std::error::Error>> {
        let ssh_target = format!("root@{}", self.pve_host);

        println!("Requesting stop for Proxmox VM {} on {}...", self.vmid, self.pve_host);
        let stop_cmd = format!("qm stop {}", self.vmid);
        let _ = CommandExecutor::execute_ssh(&ssh_target, &stop_cmd, Arc::clone(&self.log_target));

        println!("Requesting destroy for Proxmox VM {}...", self.vmid);
        let destroy_cmd = format!("qm destroy {}", self.vmid);
        CommandExecutor::execute_ssh(&ssh_target, &destroy_cmd, Arc::clone(&self.log_target))?;
        Ok(())
    }

    fn get_ip(&self) -> Result<String, Box<dyn std::error::Error>> {
        let ssh_target = format!("root@{}", self.pve_host);
        let silent_log = Arc::new(Mutex::new(LogTarget::Silent));

        // Scan for VM MAC address to find assigned DHCP IP
        log_status!(self.log_target, "Locating Proxmox VM {} IP address...", self.vmid);
        let mac_cmd = format!("qm config {} | grep -E '^net0:'", self.vmid);
        let config_out = CommandExecutor::execute_ssh(&ssh_target, &mac_cmd, silent_log.clone())?;

        // Extract MAC address dynamically from key=value format (e.g. virtio=BC:24:11:7C:F4:10)
        let mac = config_out
            .split(|c| c == ',' || c == ' ' || c == '\n')
            .find(|part| part.contains('='))
            .and_then(|part| part.split('=').nth(1))
            .map(|val| val.trim().to_lowercase());

        if let Some(mac_addr) = mac {
            log_status!(self.log_target, "Found VM MAC address: {}. Scanning subnet...", mac_addr);
            // Execute nmap scan on hypervisor subnet to map MAC to IP
            let scan_cmd = format!(
                "nmap -sn 192.168.1.0/24 | grep -i '{}' -B 2 | grep 'Nmap scan report' | awk '{{print $NF}}' | tr -d '()'",
                mac_addr
            );

            for _ in 0..36 {
                if let Ok(ip_out) = CommandExecutor::execute_ssh(&ssh_target, &scan_cmd, silent_log.clone()) {
                    let ip = ip_out.trim().to_string();
                    if !ip.is_empty() {
                        return Ok(ip);
                    }
                }
                thread::sleep(Duration::from_secs(5));
            }
        }

        Err("Failed to resolve Proxmox VM IP address".into())
    }
}
