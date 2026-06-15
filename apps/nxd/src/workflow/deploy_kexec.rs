use crate::context::RuntimeContext;
use crate::process::{CommandExecutor, Logger};
use std::env;
use std::thread;
use std::time::Duration;

use super::deploy_wait::wait_for_ssh;

pub fn handle_kexec_takeover(
	_ctx: &RuntimeContext,
	initial_ssh: &str,
	post_kexec_ssh: &str,
	low_mem: bool,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	let kexec_boot = env::var("KEXEC_BOOT").unwrap_or_else(|_| "auto".to_string());

	if kexec_boot == "no" {
		info!(logger, "Kexec takeover bypassed by flag settings.");
		return Ok(());
	}

	if kexec_boot == "auto" {
		let check_cmd = "if command -v nixos-install >/dev/null 2>&1; then echo \"NIXOS_LIVE\"; else echo \"OTHER_OS\"; fi";
		match CommandExecutor::execute_ssh(initial_ssh, check_cmd, logger.clone()) {
			Ok(output) => {
				let cleaned = output.trim();
				if cleaned == "NIXOS_LIVE" {
					let fs_cmd = "findmnt / -o FSTYPE -n";
					if let Ok(fs_type) = CommandExecutor::execute_ssh(initial_ssh, fs_cmd, logger.clone()) {
						let fs_type = fs_type.trim();
						if fs_type == "overlay"
							|| fs_type == "squashfs"
							|| fs_type == "tmpfs"
							|| fs_type == "iso9660"
						{
							info!(
								logger,
								"Target is already booted into a live installer/ephemeral OS (FSTYPE={}). Bypassing Kexec.",
								fs_type
							);
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

	info!(logger, "Target requires in-memory boot transition (Kexec). Preparing...");

	let arch_out = CommandExecutor::execute_ssh(initial_ssh, "uname -m", logger.clone())?;
	let arch = arch_out.trim();
	if arch != "x86_64" && arch != "aarch64" {
		return Err(format!("Architecture unsupported for Kexec: {}", arch).into());
	}

	let kexec_url = crate::config::kexec_url(arch);

	info!(logger, "Downloading kexec bundle from {}...", kexec_url);
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
	CommandExecutor::execute_ssh(initial_ssh, &download_cmd, logger.clone())?;

	if low_mem {
		info!(logger, "Tuning target memory parameters for in-memory boot...");
		let sudo_prefix = if initial_ssh.starts_with("root@") { "" } else { "sudo -n " };
		let optimize_cmd = format!(
            "
            {sudo}systemctl stop snapd packagekit unattended-upgrades udisks2 2>/dev/null || true
            sync
            echo 3 | {sudo}tee /proc/sys/vm/drop_caches >/dev/null
            if ! grep -q swap /proc/swaps; then
                {sudo}fallocate -l 1G /swapfile || {sudo}dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
                {sudo}chmod 600 /swapfile
                {sudo}mkswap /swapfile
                {sudo}swapon /swapfile
            fi
        ",
            sudo = sudo_prefix
        );
		let _ = CommandExecutor::execute_ssh(initial_ssh, &optimize_cmd, logger.clone());
	}

	info!(logger, "Launching Kexec kernel takeover...");
	let run_prefix = if initial_ssh.starts_with("root@") { "" } else { "sudo -n " };

	let exec_cmd = if low_mem {
		format!(
			"sed -i 's/zswap.enabled=1/zswap.enabled=0/' run; \
             sed -i 's/--command-line \"/--command-line \"initrd.tmpfs.size=80% /' run; \
             nohup {}./run > kexec.log 2>&1 &",
			run_prefix
		)
	} else {
		format!("nohup {}./run > kexec.log 2>&1 &", run_prefix)
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

	let _ = CommandExecutor::execute_ssh(initial_ssh, &run_kexec, logger.clone());

	info!(logger, "Waiting 15 seconds for Kexec to initialize boot...");
	thread::sleep(Duration::from_secs(15));

	wait_for_ssh(post_kexec_ssh, 300, logger.clone())?;
	info!(logger, "Kexec takeover complete. Live installer is online.");

	Ok(())
}
