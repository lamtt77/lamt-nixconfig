use crate::context::RuntimeContext;
use crate::process::{CommandExecutor, Logger};

/// Determines which ISO path a host will request based on its meta.nix config.
/// Returns `None` when the host is not a Proxmox NixOS ISO deploy (e.g. cloud-init).
pub fn expected_iso_path(ctx: &RuntimeContext) -> Option<String> {
	let proxmox = &ctx.deployment.proxmox;
	expected_iso_path_from_config(
		&proxmox.host,
		&proxmox.cloud_init.image,
		&proxmox.iso.custom_path,
		&proxmox.iso.storage,
	)
}

pub fn expected_iso_path_from_config(
	proxmox_host: &str,
	cloud_init_image: &str,
	iso_custom_path: &str,
	iso_storage: &str,
) -> Option<String> {
	if proxmox_host.is_empty() || !cloud_init_image.is_empty() {
		return None;
	}
	if let Ok(iso_override) = std::env::var("NIXOS_ISO")
		&& !iso_override.is_empty()
	{
		return Some(iso_override);
	}
	if !iso_custom_path.is_empty() {
		return Some(iso_custom_path.to_string());
	}
	let storage = if iso_storage.is_empty() {
		crate::config::proxmox_default_iso_storage()
	} else {
		iso_storage.to_string()
	};
	Some(format!(
		"{}:iso/nixos-minimal-{}-x86_64-linux-lamt-built.iso",
		storage,
		crate::config::nixos_iso_version(),
	))
}

/// Returns `(resolved_fs_path, exists)` for a Proxmox storage volume path via `pvesm path`.
pub fn probe_pvesm(ssh_target: &str, volume: &str) -> (Option<String>, bool) {
	let pvesm_cmd = format!("pvesm path {}", volume);
	if let Ok(path_out) = CommandExecutor::execute_ssh(ssh_target, &pvesm_cmd, Logger::silent()) {
		let path = path_out.trim().to_string();
		if path.is_empty() {
			return (None, false);
		}
		let test_cmd = format!("[ -f \"{}\" ]", path);
		let exists = CommandExecutor::execute_ssh(ssh_target, &test_cmd, Logger::silent()).is_ok();
		(Some(path), exists)
	} else {
		(None, false)
	}
}

/// Ensures the required ISO is staged on the Proxmox host after deploy confirmation.
///
/// Resolution order:
/// 1. Custom-named ISO already on Proxmox → done.
/// 2. Local workspace ISO found → upload to Proxmox → done.
/// 3. Neither found → prompt user:
///    [1] Build custom ISO locally (nix build) then upload
///    [2] Download official ISO to the expected Proxmox path (requires manual SSH key setup)
///    [q] Abort deployment for this host
///
/// Returns `Ok(())` when the ISO is staged and ready, or `Err` when the user aborts.
/// Ensures the required ISO is staged on the Proxmox host after deploy confirmation.
///
/// Resolution order:
/// 1. If build_iso is true, force rebuild and upload custom ISO.
/// 2. Custom-named ISO already on Proxmox → done.
/// 3. Local workspace ISO found → upload to Proxmox → done.
/// 4. Neither found → prompt user:
///    [1] Build custom ISO (either via remote builder or locally) then upload
///    [2] Download official ISO to the expected Proxmox path (requires manual SSH key setup)
///    [q] Abort deployment for this host
///
/// Returns `Ok(())` when the ISO is staged and ready, or `Err` when the user aborts.
pub fn ensure_proxmox_iso(
	ctx: &RuntimeContext,
	source_store_path: &str,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	let iso_path = match expected_iso_path(ctx) {
		Some(p) => p,
		None => return Ok(()), // not a NixOS ISO deploy
	};

	let ssh_target = format!("root@{}", ctx.deployment.proxmox.host);
	let build_iso = crate::config::get_runtime_options().build_iso;

	// 1. Check if the ISO already exists on Proxmox, unless build_iso is forced
	let (resolved, exists) = if build_iso {
		let (r, _) = probe_pvesm(&ssh_target, &iso_path);
		(r, false)
	} else {
		probe_pvesm(&ssh_target, &iso_path)
	};

	if exists {
		info!(logger, "[{}] ISO already on Proxmox: {}", ctx.hostname, iso_path);
		return Ok(());
	}

	let remote_path = resolved.ok_or_else(|| {
		format!("[{}] Could not resolve Proxmox path for '{}'.", ctx.hostname, iso_path)
	})?;

	// If build_iso is true, build custom ISO and upload immediately without prompting
	if build_iso {
		return build_custom_iso_and_upload(ctx, source_store_path, &remote_path, logger);
	}

	// 2. Try uploading from local workspace
	if let Some(local_iso) = crate::config::find_custom_iso("qemu") {
		info!(
			logger,
			"[{}] Found local workspace ISO: {}. Uploading to Proxmox...",
			ctx.hostname,
			local_iso.display()
		);
		if let Some(parent) = std::path::Path::new(&remote_path).parent() {
			let mkdir_cmd = format!("mkdir -p {}", parent.display());
			let _ = CommandExecutor::execute_ssh(&ssh_target, &mkdir_cmd, logger.clone());
		}
		let scp_args = [local_iso.to_str().unwrap(), &format!("{}:{}", ssh_target, remote_path)];
		if CommandExecutor::execute("scp", &scp_args, logger.clone()).is_ok() {
			info!(logger, "[{}] ISO uploaded successfully.", ctx.hostname);
			return Ok(());
		}
		warn!(logger, "[{}] SCP upload failed. Falling through to user prompt.", ctx.hostname);
	}

	// 3. Interactive prompt — neither found on Proxmox nor in local workspace
	let iso_name = iso_path.split(':').next_back().unwrap_or(&iso_path);
	let flake_target = "nixosConfigurations.minimal-iso-x86.config.system.build.isoImage";
	let channel = crate::config::nixos_channel();
	let official_url =
		format!("https://channels.nixos.org/{}/latest-nixos-minimal-x86_64-linux.iso", channel);

	println!();
	println!("╔══ ISO not found for host: {} ══╗", ctx.hostname);
	println!("  Expected: {}", iso_path);
	println!("  Proxmox:  {}", ctx.deployment.proxmox.host);
	println!();
	println!("  [1] Build custom ISO and upload");
	println!("      (nix build path:{}#{}  →  scp to Proxmox)", source_store_path, flake_target);
	println!("  [2] Download official NixOS ISO to Proxmox");
	println!("      ({})", official_url);
	println!("      ⚠  Official ISO has no embedded SSH key — you must add");
	println!("         your public key via the VM console before first boot.");
	println!("  [q] Skip this host / abort");
	println!();
	print!("  Choice [1/2/q]: ");
	use std::io::Write;
	std::io::stdout().flush()?;

	let mut input = String::new();
	std::io::stdin().read_line(&mut input)?;
	let choice = input.trim();

	match choice {
		"1" => build_custom_iso_and_upload(ctx, source_store_path, &remote_path, logger),

		"2" => {
			if !ctx.deployment.proxmox.bootstrap.static_ip.is_empty() {
				return Err(
					format!(
						"[{}] Cannot download official NixOS ISO because bootstrap.staticIp is set. \
                     Static IP injection requires a custom ISO with QEMU guest-agent enabled.",
						ctx.hostname
					)
					.into(),
				);
			}

			println!("[{}] Downloading official NixOS ISO on Proxmox…", ctx.hostname);
			if let Some(parent) = std::path::Path::new(&remote_path).parent() {
				let mkdir_cmd = format!("mkdir -p {}", parent.display());
				let _ = CommandExecutor::execute_ssh(&ssh_target, &mkdir_cmd, logger.clone());
			}
			let download_cmd = format!(
				"curl -L \"{}\" -o \"{}\" || wget \"{}\" -O \"{}\"",
				official_url, remote_path, official_url, remote_path
			);
			CommandExecutor::execute_ssh(&ssh_target, &download_cmd, logger.clone())
				.map_err(|e| format!("[{}] Download failed: {}", ctx.hostname, e))?;
			info!(logger, "[{}] Official ISO downloaded to expected path: {}", ctx.hostname, iso_path);

			warn!(
				logger,
				"[{}] ⚠  Official ISO will be used for {}.\n\
                 SSH public key: {}\n\
                 Add this key via the VM console once booted, then the installer will connect.",
				ctx.hostname,
				iso_name,
				crate::config::ssh_auth_key()
			);
			Ok(())
		}

		_ => Err(format!("ISO staging aborted for host '{}'.", ctx.hostname).into()),
	}
}

fn build_custom_iso_and_upload(
	ctx: &RuntimeContext,
	source_store_path: &str,
	remote_path: &str,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	let builder = crate::nix::NixBuilder::resolve(ctx);
	let ssh_target = format!("root@{}", ctx.deployment.proxmox.host);

	// Ensure remote directory exists on Proxmox
	if let Some(parent) = std::path::Path::new(remote_path).parent() {
		let mkdir_cmd = format!("mkdir -p {}", parent.display());
		let _ = CommandExecutor::execute_ssh(&ssh_target, &mkdir_cmd, logger.clone());
	}

	match &builder.strategy {
		crate::nix::strategy::BuildStrategy::RemoteBuilder { ssh_connection } => {
			crate::info!(
				logger,
				"[{}] Building custom ISO on remote builder {}...",
				ctx.hostname,
				ssh_connection
			);
			let build_cmd = format!(
				"nix build path:{}#nixosConfigurations.minimal-iso-x86.config.system.build.isoImage --print-out-paths --no-link",
				source_store_path
			);
			let out = CommandExecutor::execute_ssh(ssh_connection, &build_cmd, logger.clone())?;
			let out_path = out.trim().to_string();
			if out_path.is_empty() {
				return Err(
					format!("[{}] nix build on remote builder did not return a path.", ctx.hostname).into(),
				);
			}

			let find_cmd = format!("find {}/iso -name \"*.iso\" | head -n 1", out_path);
			let iso_file = CommandExecutor::execute_ssh(ssh_connection, &find_cmd, logger.clone())?;
			let iso_file = iso_file.trim().to_string();
			if iso_file.is_empty() {
				return Err(
					format!("[{}] No .iso file found in build output on remote builder.", ctx.hostname)
						.into(),
				);
			}

			crate::info!(
				logger,
				"[{}] Copying ISO directly from remote builder {} to Proxmox...",
				ctx.hostname,
				ssh_connection
			);
			let scp_cmd = format!(
				"scp -o {} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null {} root@{}:{}",
				crate::remote::ssh::WARN_WEAK_CRYPTO_OPTION,
				iso_file,
				ctx.deployment.proxmox.host,
				remote_path
			);
			CommandExecutor::execute_ssh(ssh_connection, &scp_cmd, logger.clone())?;
			crate::success!(
				logger,
				"[{}] Custom ISO built on remote builder and uploaded to Proxmox.",
				ctx.hostname
			);
		}
		_ => {
			crate::info!(logger, "[{}] Building custom ISO locally...", ctx.hostname);
			let build_args = [
				"build",
				&format!(
					"path:{}#nixosConfigurations.minimal-iso-x86.config.system.build.isoImage",
					source_store_path
				),
				"-o",
				"result-iso-x86",
			];
			CommandExecutor::execute("nix", &build_args, logger.clone())?;

			if let Some(local_iso) = crate::config::find_custom_iso("qemu") {
				crate::info!(logger, "[{}] Uploading built custom ISO to Proxmox...", ctx.hostname);
				let dest_target = format!("{}:{}", ssh_target, remote_path);
				let scp_args = [local_iso.to_str().unwrap(), dest_target.as_str()];
				CommandExecutor::execute("scp", &scp_args, logger.clone())?;
				crate::success!(
					logger,
					"[{}] Custom ISO built locally and uploaded to Proxmox.",
					ctx.hostname
				);
			} else {
				return Err(
					format!("[{}] Built ISO file could not be found locally in workspace.", ctx.hostname)
						.into(),
				);
			}
		}
	}
	Ok(())
}
