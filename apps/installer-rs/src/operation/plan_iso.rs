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
        &proxmox.iso.flavor,
        &proxmox.iso.storage,
    )
}

pub fn expected_iso_path_from_config(
    proxmox_host: &str,
    cloud_init_image: &str,
    iso_custom_path: &str,
    iso_flavor: &str,
    iso_storage: &str,
) -> Option<String> {
    if proxmox_host.is_empty() || !cloud_init_image.is_empty() {
        return None;
    }
    if let Ok(iso_override) = std::env::var("NIXOS_ISO") {
        if !iso_override.is_empty() {
            return Some(iso_override);
        }
    }
    if !iso_custom_path.is_empty() {
        return Some(iso_custom_path.to_string());
    }
    let suffix = if iso_flavor == "vlan" { "vlan" } else { "qemu" };
    let storage = if iso_storage.is_empty() {
        crate::config::proxmox_default_iso_storage()
    } else {
        iso_storage.to_string()
    };
    Some(format!(
        "{}:iso/nixos-minimal-{}-x86_64-linux-{}.iso",
        storage,
        crate::config::nixos_iso_version(),
        suffix
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
pub fn ensure_proxmox_iso(
    ctx: &RuntimeContext,
    logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
    let iso_path = match expected_iso_path(ctx) {
        Some(p) => p,
        None => return Ok(()), // not a NixOS ISO deploy
    };

    let ssh_target = format!("root@{}", ctx.deployment.proxmox.host);

    // 1. Check if the ISO already exists on Proxmox
    let (resolved, exists) = probe_pvesm(&ssh_target, &iso_path);
    if exists {
        info!(
            logger,
            "[{}] ISO already on Proxmox: {}", ctx.hostname, iso_path
        );
        return Ok(());
    }

    // 2. Try uploading from local workspace
    let flavor = if iso_path.contains("-vlan.iso") {
        "vlan"
    } else {
        "qemu"
    };
    if let Some(ref remote_path) = resolved {
        if let Some(local_iso) = crate::config::find_custom_iso(flavor) {
            info!(
                logger,
                "[{}] Found local workspace ISO: {}. Uploading to Proxmox...",
                ctx.hostname,
                local_iso.display()
            );
            if let Some(parent) = std::path::Path::new(remote_path).parent() {
                let mkdir_cmd = format!("mkdir -p {}", parent.display());
                let _ = CommandExecutor::execute_ssh(&ssh_target, &mkdir_cmd, logger.clone());
            }
            let scp_args = [
                local_iso.to_str().unwrap(),
                &format!("{}:{}", ssh_target, remote_path),
            ];
            if CommandExecutor::execute("scp", &scp_args, logger.clone()).is_ok() {
                info!(logger, "[{}] ISO uploaded successfully.", ctx.hostname);
                return Ok(());
            }
            warn!(
                logger,
                "[{}] SCP upload failed. Falling through to user prompt.", ctx.hostname
            );
        }
    }

    // 3. Interactive prompt — neither found on Proxmox nor in local workspace
    let iso_name = iso_path.split(':').next_back().unwrap_or(&iso_path);
    let flake_target = if flavor == "vlan" {
        ".#nixosConfigurations.minimal-iso-vlan.config.system.build.isoImage"
    } else {
        ".#nixosConfigurations.minimal-iso-x86.config.system.build.isoImage"
    };
    let channel = crate::config::nixos_channel();
    let official_url = format!(
        "https://channels.nixos.org/{}/latest-nixos-minimal-x86_64-linux.iso",
        channel
    );

    println!();
    println!("╔══ ISO not found for host: {} ══╗", ctx.hostname);
    println!("  Expected: {}", iso_path);
    println!("  Proxmox:  {}", ctx.deployment.proxmox.host);
    println!();
    println!("  [1] Build custom ISO locally and upload");
    println!("      (nix build {}  →  scp to Proxmox)", flake_target);
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
        "1" => {
            println!("[{}] Building custom ISO…", ctx.hostname);
            let out_flavor = if flavor == "qemu" { "x86" } else { flavor };
            let build_args = [
                "build",
                flake_target,
                "-o",
                &format!("result-iso-{}", out_flavor),
            ];
            CommandExecutor::execute("nix", &build_args, logger.clone())
                .map_err(|e| format!("[{}] nix build failed: {}", ctx.hostname, e))?;

            // Re-attempt upload after build
            if let Some(local_iso) = crate::config::find_custom_iso(flavor) {
                if let (Some(ref remote_path), _) = probe_pvesm(&ssh_target, &iso_path) {
                    if let Some(parent) = std::path::Path::new(remote_path).parent() {
                        let mkdir_cmd = format!("mkdir -p {}", parent.display());
                        let _ =
                            CommandExecutor::execute_ssh(&ssh_target, &mkdir_cmd, logger.clone());
                    }
                    let scp_args = [
                        local_iso.to_str().unwrap(),
                        &format!("{}:{}", ssh_target, remote_path),
                    ];
                    CommandExecutor::execute("scp", &scp_args, logger.clone())
                        .map_err(|e| format!("[{}] Upload failed: {}", ctx.hostname, e))?;
                    info!(logger, "[{}] Custom ISO built and uploaded.", ctx.hostname);
                    return Ok(());
                }
            }
            Err(format!(
                "[{}] ISO build succeeded but upload path could not be resolved for '{}'.",
                ctx.hostname, iso_path
            )
            .into())
        }

        "2" => {
            println!(
                "[{}] Downloading official NixOS ISO on Proxmox…",
                ctx.hostname
            );
            let (expected_resolved, expected_exists) = probe_pvesm(&ssh_target, &iso_path);
            if expected_exists {
                info!(
                    logger,
                    "[{}] Expected ISO already present: {}", ctx.hostname, iso_path
                );
            } else if let Some(ref remote_path) = expected_resolved {
                if let Some(parent) = std::path::Path::new(remote_path).parent() {
                    let mkdir_cmd = format!("mkdir -p {}", parent.display());
                    let _ = CommandExecutor::execute_ssh(&ssh_target, &mkdir_cmd, logger.clone());
                }
                let download_cmd = format!(
                    "curl -L \"{}\" -o \"{}\" || wget \"{}\" -O \"{}\"",
                    official_url, remote_path, official_url, remote_path
                );
                CommandExecutor::execute_ssh(&ssh_target, &download_cmd, logger.clone())
                    .map_err(|e| format!("[{}] Download failed: {}", ctx.hostname, e))?;
                info!(
                    logger,
                    "[{}] Official ISO downloaded to expected path: {}", ctx.hostname, iso_path
                );
            } else {
                return Err(format!(
                    "[{}] Could not resolve Proxmox path for '{}'.",
                    ctx.hostname, iso_path
                )
                .into());
            }

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
