use crate::nix::NixBuilder;
use crate::process::{CommandExecutor, Logger};

pub fn run_disko(
    builder: &NixBuilder,
    target_ssh: &str,
    logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
    info!(
        logger,
        "Generating and executing Disko partitioning script..."
    );
    let disko_script_path =
        builder.build_attribute("config.system.build.diskoScript", None, logger.clone())?;

    info!(logger, "Running Disko partitioning on target...");
    let run_disko_cmd = format!("{} --mode disko", disko_script_path);
    CommandExecutor::execute_ssh(target_ssh, &run_disko_cmd, logger.clone())?;
    info!(logger, "Disko partitioning complete.");
    Ok(())
}
