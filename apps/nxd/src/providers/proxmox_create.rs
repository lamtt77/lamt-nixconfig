use super::proxmox::ProxmoxProvider;
use std::env;

pub fn create_vm(provider: &ProxmoxProvider) -> Result<(), Box<dyn std::error::Error>> {
	let vm_storage = env::var("VM_STORAGE").unwrap_or_else(|_| {
		if provider.disk_storage.is_empty() {
			crate::config::proxmox_default_disk_storage()
		} else {
			provider.disk_storage.clone()
		}
	});

	let vga_val = match env::var("VM_VGA").as_deref() {
		Ok("serial0") => "serial0",
		Ok("std") | Err(_) => "std",
		Ok(value) => {
			return Err(
				format!("Unsupported VM_VGA value '{}'; expected 'std' or 'serial0'", value).into(),
			);
		}
	};

	let bios_args = if provider.bios == "ovmf" {
		format!("--bios ovmf --efidisk0 {}:1", vm_storage)
	} else {
		"--bios seabios".to_string()
	};

	let vm_net0_bridge = &provider.net0;

	if provider.pxe {
		// PXE-Boot Proxmox VM flow
		info!(
			provider.logger,
			"Provisioning PXE-Boot Proxmox VM {} ({}) on {}...",
			provider.vmid,
			provider.hostname,
			provider.pve_host
		);

		let disk_args = format!("--virtio0 {}:{}", vm_storage, provider.disk_size);
		let extra_net_args = provider.extra_net_args();

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
			provider.vmid,
			provider.hostname,
			provider.memory,
			provider.cores,
			vm_net0_bridge,
			disk_args,
			vga_val,
			extra_net_args
		);

		provider.execute(&create_cmd)?;
	} else if provider.cloud_init_image.is_empty() {
		// NixOS installer ISO flow
		info!(
			provider.logger,
			"Provisioning NixOS Proxmox VM {} ({}) on {}...",
			provider.vmid,
			provider.hostname,
			provider.pve_host
		);

		let cdrom_val = crate::planning::plan_iso::expected_iso_path_from_config(
			&provider.pve_host,
			&provider.cloud_init_image,
			&provider.iso_custom_path,
			&provider.iso_storage,
		)
		.ok_or("Proxmox ISO path could not be determined for NixOS installer flow")?;

		let ssh_target = format!("root@{}", provider.pve_host);
		let (_, iso_exists) = crate::planning::plan_iso::probe_pvesm(&ssh_target, &cdrom_val);
		if !iso_exists {
			return Err(
				format!(
					"ISO '{}' is not staged on Proxmox. Re-run deploy and approve ISO staging after confirmation.",
					cdrom_val
				)
				.into(),
			);
		}

		// Determine disk args and boot disk
		let (disk_args, boot_disk) = {
			let hw = if provider.scsi_hw.is_empty() { "virtio-scsi-pci" } else { &provider.scsi_hw };
			if provider.disk_bus == "scsi" {
				(format!("--scsihw {} --scsi0 {}:{}", hw, vm_storage, provider.disk_size), "scsi0")
			} else {
				(format!("--scsihw {} --virtio0 {}:{}", hw, vm_storage, provider.disk_size), "virtio0")
			}
		};

		let extra_net_args = provider.extra_net_args();

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
			provider.vmid,
			provider.hostname,
			provider.memory,
			provider.cores,
			vm_net0_bridge,
			disk_args,
			bios_args,
			vm_storage,
			cdrom_val,
			boot_disk,
			extra_net_args
		);

		provider.execute(&create_cmd)?;
	} else {
		// Cloud-Init VM templates flow
		info!(
			provider.logger,
			"Provisioning Cloud-Init Proxmox VM {} ({}) on {}...",
			provider.vmid,
			provider.hostname,
			provider.pve_host
		);

		let ssh_key = crate::config::ssh_auth_key();

		let ipconfig0_val = if !provider.cloud_init_ipconfig0.is_empty() {
			&provider.cloud_init_ipconfig0
		} else {
			"ip=dhcp"
		};

		let mut extra_args = provider.extra_net_args();
		if !provider.cloud_init_ipconfig1.is_empty() {
			extra_args.push_str(&format!(" --ipconfig1 {}", provider.cloud_init_ipconfig1));
		}
		if !provider.cloud_init_user.is_empty() {
			extra_args.push_str(&format!(" --ciuser {}", provider.cloud_init_user));
		}

		let temp_key_file = format!("/tmp/ssh_key_{}.pub", provider.vmid);

		let ci_scsihw_arg = if provider.disk_bus == "scsi" && !provider.scsi_hw.is_empty() {
			format!(" --scsihw {}", provider.scsi_hw)
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
			provider.vmid,
			provider.hostname,
			provider.memory,
			provider.cores,
			vm_net0_bridge,
			ipconfig0_val,
			vm_storage,
			bios_args,
			ci_scsihw_arg,
			extra_args,
			temp_key_file
		);
		provider.execute(&init_cmd)?;

		info!(
			provider.logger,
			"Importing cloud-init disk image {} to VM {} on storage {}...",
			provider.cloud_init_image,
			provider.vmid,
			vm_storage
		);
		let import_cmd =
			format!("qm importdisk {} {} {}", provider.vmid, provider.cloud_init_image, vm_storage);
		provider.execute(&import_cmd)?;

		// Find the imported disk name
		let config_cmd = format!("qm config {}", provider.vmid);
		let config_out = provider.execute(&config_cmd)?;

		// Find line matching `unused[0-9]+:`
		let imported_disk = config_out
			.lines()
			.find(|line| line.trim().starts_with("unused"))
			.and_then(|line| line.split_once(':'))
			.map(|(_, val)| val.split(',').next().unwrap_or("").trim().to_string())
			.ok_or_else(|| {
				format!(
					"Failed to locate imported disk in VM {} configuration. qm config output:\n{}",
					provider.vmid, config_out
				)
			})?;

		// Cloud-init VMs: use virtio0 by default. Only use scsi0 when disk_bus is explicitly "scsi"
		let (root_disk, boot_disk) =
			if provider.disk_bus == "scsi" { ("scsi0", "scsi0") } else { ("virtio0", "virtio0") };

		info!(provider.logger, "Attaching imported disk {} as {}...", imported_disk, root_disk);
		let attach_cmd = format!("qm set {} --{} {}", provider.vmid, root_disk, imported_disk);
		provider.execute(&attach_cmd)?;

		let boot_cmd = format!("qm set {} --boot 'order={};ide2;net0'", provider.vmid, boot_disk);
		provider.execute(&boot_cmd)?;

		info!(
			provider.logger,
			"Resizing VM {} root disk to {}GB...", provider.vmid, provider.disk_size
		);
		let resize_cmd = format!("qm resize {} {} {}G", provider.vmid, root_disk, provider.disk_size);
		provider.execute(&resize_cmd)?;

		let clean_cmd = format!("rm -f {}", temp_key_file);
		let _ = provider.execute(&clean_cmd);
	}

	Ok(())
}
