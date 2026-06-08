use crate::process::{CommandExecutor, Logger};

pub fn run_nixos_install(
    target_ssh: &str,
    system_path: &str,
    low_mem: bool,
    logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
    info!(logger, "Executing nixos-install on target...");
    let gc_env = if low_mem {
        "export GC_INITIAL_HEAP_SIZE=1M GC_DONT_GC=1 NIX_DISABLE_AUTO_GC=1; "
    } else {
        ""
    };
    let install_cmd = format!(
        "{}nixos-install --no-root-password --no-channel-copy --system {}",
        gc_env, system_path
    );
    CommandExecutor::execute_ssh(target_ssh, &install_cmd, logger.clone())?;
    info!(logger, "Nixos installation complete.");
    Ok(())
}
