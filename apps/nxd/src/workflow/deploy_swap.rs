use crate::process::{CommandExecutor, Logger};

pub fn setup_zram_swap(target_ssh: &str, logger: Logger) -> Result<(), Box<dyn std::error::Error>> {
	info!(logger, "Low Memory Optimization: Allocating 3GB ZRAM swap space on target...");
	let swap_cmd = "
        modprobe zram 2>/dev/null || true
        echo 3221225472 > /sys/block/zram0/disksize 2>/dev/null || true
        mkswap /dev/zram0 >/dev/null 2>&1 || true
        swapon /dev/zram0 >/dev/null 2>&1 || true
    ";
	let _ = CommandExecutor::execute_ssh(target_ssh, swap_cmd, logger);
	Ok(())
}

pub fn setup_physical_swapfile(
	target_ssh: &str,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	info!(
		logger,
		"Low Memory Optimization: Allocating 3GB physical swapfile on target at /mnt/swapfile..."
	);
	let swap_cmd = "
        fallocate -l 3G /mnt/swapfile || dd if=/dev/zero of=/mnt/swapfile bs=1M count=3072 status=none
        chmod 600 /mnt/swapfile
        mkswap /mnt/swapfile
        swapon /mnt/swapfile
    ";
	let _ = CommandExecutor::execute_ssh(target_ssh, swap_cmd, logger);
	Ok(())
}
