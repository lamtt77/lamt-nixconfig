use super::deploy_disko::run_disko;
use super::deploy_install::run_nixos_install;
use super::deploy_kexec::handle_kexec_takeover;
pub use super::deploy_mode::DeploymentMode;
use super::deploy_reboot::reboot_target;
use super::deploy_swap::{setup_physical_swapfile, setup_zram_swap};
use super::deploy_system::build_system;
use super::deploy_wait::wait_for_ssh;
use crate::config::{LOCAL_CACHE_KEY, LOCAL_CACHE_URL};
use crate::context::RuntimeContext;
use crate::identity::{get_identity_services, ssh::SshKeyService};
use crate::nix::NixBuilder;
use crate::process::{CommandExecutor, Logger};
use crate::providers::{ProviderIpMode, get_provider_ip};
use std::path::Path;

fn live_nix_cache_command(enabled: bool) -> String {
	let update = if enabled {
		format!(
			"if ! grep -qF 'cache.lamhub.com' \"$nix_conf\"; then \
				printf '%s\\n' 'extra-substituters = {LOCAL_CACHE_URL}' \
					'extra-trusted-public-keys = {LOCAL_CACHE_KEY}' >> \"$nix_conf\"; \
			fi"
		)
	} else {
		"sed -i '/cache\\.lamhub\\.com/d' \"$nix_conf\"".to_string()
	};

	format!(
		"set -eu; \
		nix_conf=/etc/nix/nix.conf; \
		if [ -f \"$nix_conf\" ]; then \
			if ! mountpoint -q \"$nix_conf\"; then \
				mkdir -p /run/nxd; \
				cp \"$nix_conf\" /run/nxd/nix.conf; \
				mount --bind /run/nxd/nix.conf \"$nix_conf\"; \
			fi; \
			{update}; \
			systemctl restart nix-daemon 2>/dev/null || true; \
		fi"
	)
}

fn configure_live_nix_cache(target_ssh: &str, enabled: bool, logger: Logger) {
	let command = live_nix_cache_command(enabled);
	if let Err(error) = CommandExecutor::execute_ssh(target_ssh, &command, logger.clone()) {
		warn!(
			logger,
			"Could not {} the local binary cache in the live installer: {}. Continuing with the installer defaults.",
			if enabled { "enable" } else { "disable" },
			error
		);
	}
}

pub fn run_deployment(
	ctx: &RuntimeContext,
	mode: DeploymentMode,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	let start_time = std::time::Instant::now();
	let low_mem = ctx.deployment.low_mem == "yes";

	if let DeploymentMode::CloudInitVerify { user } = &mode {
		info!(logger, "=========================================================================");
		info!(logger, "Starting Cloud-Init VM Template Verification for {}", ctx.hostname);
		info!(logger, "Target IP: {}", ctx.target_ip);
		info!(logger, "Cloud-Init User: {}", user);
		info!(logger, "=========================================================================");

		let ci_ssh = format!("{}@{}", user, ctx.target_ip);

		// Clean local known_hosts to prevent warning messages when connecting or later
		let _ = crate::remote::known_hosts::remove_known_host_keys(&ctx.target_ip, &ctx.hostname);

		info!(logger, "Waiting for SSH on {} to verify cloud-init deployment...", ci_ssh);
		wait_for_ssh(&ci_ssh, 300, logger.clone())?;

		info!(logger, "=========================================================================");
		let duration = start_time.elapsed();
		let mins = duration.as_secs() / 60;
		let secs = duration.as_secs() % 60;
		info!(logger, "Cloud-Init VM Template verification finished in {}m {}s!", mins, secs);
		info!(logger, "=========================================================================");
		return Ok(());
	}

	if !ctx.build_system {
		info!(logger, "=========================================================================");
		info!(logger, "Starting Unattended OS Boot/Poll Pipeline for {}", ctx.hostname);
		info!(logger, "Target IP: {}", ctx.target_ip);
		info!(logger, "=========================================================================");

		// Clean local known_hosts to prevent warning messages when connecting or later
		let _ = crate::remote::known_hosts::remove_known_host_keys(&ctx.target_ip, &ctx.hostname);

		info!(
			logger,
			"Waiting for SSH reachability on root@{} (polling until install finishes)...", ctx.target_ip
		);
		// We use 900 seconds (15 minutes) or a reasonable timeout for Proxmox install
		wait_for_ssh(&format!("root@{}", ctx.target_ip), 900, logger.clone())?;

		info!(logger, "=========================================================================");
		let duration = start_time.elapsed();
		let mins = duration.as_secs() / 60;
		let secs = duration.as_secs() % 60;
		success!(
			logger,
			"Target host {} is fully reachable via SSH! ({}m {}s)",
			ctx.hostname,
			mins,
			secs
		);
		info!(logger, "=========================================================================");
		return Ok(());
	}

	let initial_ssh = format!("{}@{}", mode.initial_user(), ctx.target_ip);
	let target_ssh = format!("root@{}", ctx.target_ip);

	// Clean local known_hosts to prevent warning messages when connecting or later
	let _ = crate::remote::known_hosts::remove_known_host_keys(&ctx.target_ip, &ctx.hostname);

	let builder = NixBuilder::resolve(ctx);
	let strategy_name = builder.strategy.label();

	info!(logger, "=========================================================================");
	info!(logger, "Starting {} Pipeline for {}", mode.label(), ctx.hostname);
	info!(logger, "Target IP: {}", ctx.target_ip);
	info!(logger, "Initial SSH User: {}", mode.initial_user());
	info!(logger, "Low Memory Optimization: {}", if low_mem { "ENABLED" } else { "DISABLED" });
	info!(logger, "Resolved Build Strategy: {}", strategy_name);
	info!(logger, "=========================================================================");

	// Wait for SSH on target to become ready (e.g. if the VM was just recreated/booted)
	wait_for_ssh(&initial_ssh, 300, logger.clone())?;

	// Safety check remote hostname to prevent deploying configuration to the wrong active host
	info!(logger, "Checking target system hostname...");
	if let Ok(actual_host) = CommandExecutor::execute_ssh(&initial_ssh, "hostname", logger.clone()) {
		let actual_host = actual_host.trim().to_string();
		if !actual_host.is_empty()
			&& actual_host != ctx.hostname
			&& !matches!(mode, DeploymentMode::CloudInitConvert { .. })
		{
			let generic_names = ["nixos", "installer", "nixos-installer"];
			if !generic_names.contains(&actual_host.as_str()) {
				let is_forced = crate::config::get_runtime_options().force;
				if !is_forced {
					return Err(format!(
                        "CRITICAL: Mismatched host safety trigger. Target IP {} is running as '{}', but configuration is for '{}'. Deployment would overwrite and erase this machine! Use --force to override.",
                        ctx.target_ip, actual_host, ctx.hostname
                    ).into());
				} else {
					warn!(
						logger,
						"Target hostname mismatch (target is '{}', config is '{}'). Proceeding because --force is enabled.",
						actual_host,
						ctx.hostname
					);
				}
			}
		}
	}

	// Configure DNS resolver on target live installer to ensure outbound internet and substitution resolve correctly
	info!(logger, "Configuring DNS resolver (appending nameserver 1.1.1.1) on target environment...");
	let dns_cmd = "if ! grep -q '1.1.1.1' /etc/resolv.conf; then echo 'nameserver 1.1.1.1' | sudo tee -a /etc/resolv.conf >/dev/null || echo 'nameserver 1.1.1.1' >> /etc/resolv.conf; fi";
	let _ = CommandExecutor::execute_ssh(&initial_ssh, dns_cmd, logger.clone());

	// --- Phase 1: Kexec Takeover Target ---
	handle_kexec_takeover(ctx, &initial_ssh, &target_ssh, low_mem, logger.clone())?;

	// Configure DNS resolver on final live target to append 1.1.1.1 (preserving DHCP nameservers for local cache resolution)
	let dns_setup = "if ! grep -q '1.1.1.1' /etc/resolv.conf; then echo 'nameserver 1.1.1.1' >> /etc/resolv.conf; fi";
	let _ = CommandExecutor::execute_ssh(&target_ssh, dns_setup, logger.clone());

	// Reachability check for cache.lamhub.com
	if ctx.deployment.enable_local_cache {
		info!(logger, "Checking reachability of local binary cache (cache.lamhub.com)...");
		let cache_check_cmd = "curl -s -f --connect-timeout 2 https://cache.lamhub.com/nix-cache-info >/dev/null && echo \"ONLINE\" || echo \"OFFLINE\"";
		let cache_status =
			match CommandExecutor::execute_ssh(&target_ssh, cache_check_cmd, logger.clone()) {
				Ok(output) => output.trim().to_string(),
				Err(_) => "OFFLINE".to_string(),
			};

		if cache_status == "ONLINE" {
			success!(
				logger,
				"Local binary cache (cache.lamhub.com) is ONLINE and reachable. Using it for faster deployment!"
			);
			configure_live_nix_cache(&target_ssh, true, logger.clone());
		} else {
			warn!(
				logger,
				"Local binary cache (cache.lamhub.com) is OFFLINE or unreachable. Disabling it dynamically on live installer."
			);
			configure_live_nix_cache(&target_ssh, false, logger.clone());
		}
	} else {
		info!(
			logger,
			"Local binary cache (cache.lamhub.com) is disabled in meta.nix. Disabling it dynamically on live installer."
		);
		configure_live_nix_cache(&target_ssh, false, logger.clone());
	}

	// --- Phase 2: Setup Swap (ZRAM) for live environment ---
	if low_mem {
		setup_zram_swap(&target_ssh, logger.clone())?;
	}

	// --- Phase 3: Run Identity Services Pre-Install ---
	info!(logger, "Running Identity Services Pre-Install Staging...");
	let identity_services = get_identity_services(logger.clone());
	for service in &identity_services {
		info!(logger, "Executing pre-install for service: {}", service.id());
		service.pre_install(ctx)?;
	}

	// --- Phase 4: Disk Partitioning (Disko) ---
	run_disko(&builder, &target_ssh, logger.clone())?;

	// --- Phase 5: Setup Physical Swapfile on /mnt ---
	if low_mem {
		setup_physical_swapfile(&target_ssh, logger.clone())?;
	}

	// --- Phase 6: Build/Realise System Configuration ---
	let system_path = build_system(&builder, logger.clone())?;

	// --- Phase 7: Run Identity Services Post-Install ---
	info!(logger, "Running Identity Services Post-Install Staging...");
	let mount_path = Path::new("/mnt");
	for service in &identity_services {
		info!(logger, "Executing post-install for service: {}", service.id());
		service.post_install(ctx, mount_path)?;
	}

	// --- Phase 8: NixOS Installation ---
	run_nixos_install(&target_ssh, &system_path, low_mem, logger.clone())?;

	// nixos-install can rebuild /mnt/etc as part of activation. Re-stage the
	// pre-generated host key so first boot uses the same SOPS age identity that
	// was used while installing secrets.
	info!(logger, "Restaging target host SSH key after NixOS installation...");
	SshKeyService::new(logger.clone()).stage_target_host_keys(ctx, mount_path)?;

	// --- Phase 9: Reboot ---
	reboot_target(&target_ssh, logger.clone());

	// --- Phase 10: Post-reboot IP notice ---
	// After a redeploy the VM gets a new MAC and thus a new DHCP lease, so its
	// IP may differ from the one used during installation. Poll here because
	// this is the final post-deployment notice and provider/DHCP state can lag
	// behind the reboot command.
	let final_ip = crate::fleet::resolution::resolve_provider(ctx, logger.clone())
		.and_then(|p| get_provider_ip(p.as_ref(), ProviderIpMode::PollUntilReady).ok())
		.filter(|ip| !ip.is_empty() && ip != &ctx.target_ip);

	if let Some(ref new_ip) = final_ip {
		let _ = crate::remote::known_hosts::remove_known_host_keys(new_ip, &ctx.hostname);
		info!(
			logger,
			"Post-reboot IP for {} resolved to {} (was {} during install). \
             known_hosts updated.",
			ctx.hostname,
			new_ip,
			ctx.target_ip
		);
	} else {
		// Even if IP hasn't changed, clean for the deploy-time IP so any stale
		// installer host key doesn't block post-boot SSH.
		let _ = crate::remote::known_hosts::remove_known_host_keys(&ctx.target_ip, &ctx.hostname);
	}

	info!(logger, "=========================================================================");
	let duration = start_time.elapsed();
	let mins = duration.as_secs() / 60;
	let secs = duration.as_secs() % 60;
	info!(logger, "State Convergence Deployment successfully finished in {}m {}s!", mins, secs);
	let display_ip = final_ip.as_deref().unwrap_or(&ctx.target_ip);
	info!(logger, "Target system ({}) is rebooting. Final IP: {}", ctx.hostname, display_ip);
	if final_ip.is_some() {
		warn!(
			logger,
			"IP changed after reboot. Update ~/.ssh/config or any hardcoded references \
             from {} to {}.",
			ctx.target_ip,
			display_ip
		);
	}
	info!(logger, "=========================================================================");

	Ok(())
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn live_cache_enable_uses_writable_bind_mount() {
		let command = live_nix_cache_command(true);

		assert!(command.contains("cp \"$nix_conf\" /run/nxd/nix.conf"));
		assert!(command.contains("mount --bind /run/nxd/nix.conf \"$nix_conf\""));
		assert!(command.contains(LOCAL_CACHE_URL));
		assert!(command.contains(LOCAL_CACHE_KEY));
	}

	#[test]
	fn live_cache_disable_removes_cache_lines_from_writable_config() {
		let command = live_nix_cache_command(false);

		assert!(command.contains("mount --bind /run/nxd/nix.conf \"$nix_conf\""));
		assert!(command.contains("sed -i '/cache\\.lamhub\\.com/d'"));
	}
}
