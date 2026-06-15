use crate::context::{RuntimeContext, create_adhoc_context, parse_host_spec};
use crate::process::Logger;
use crate::workflow::deploy::{DeploymentMode, run_deployment};
use crate::workspace::prepare_store_workspace;
use crate::workspace::source::prepare_source_set;
use std::collections::BTreeSet;

struct SourceCleanupGuard {
	run_id: String,
	remote_destinations: BTreeSet<String>,
	logger: Logger,
}

impl SourceCleanupGuard {
	fn new(run_id: String, logger: Logger) -> Self {
		Self { run_id, remote_destinations: BTreeSet::new(), logger }
	}

	fn track_remote(&mut self, destination: &str) {
		self.remote_destinations.insert(destination.to_string());
	}
}

impl Drop for SourceCleanupGuard {
	fn drop(&mut self) {
		for destination in &self.remote_destinations {
			let _ = crate::workspace::source::cleanup_remote_gc_roots(
				destination,
				&self.run_id,
				self.logger.clone(),
			);
		}
		let _ = crate::workspace::source::cleanup_gc_roots(&self.run_id, self.logger.clone());
	}
}

pub async fn execute_convert(
	target_spec: &str,
	to_host: &str,
	_parallel: usize,
) -> Result<(), Box<dyn std::error::Error>> {
	let logger = Logger::terminal();

	// 1. Resolve source context as an ad-hoc/ephemeral target spec
	let (hostname, username, ip) = parse_host_spec(target_spec);
	let source_ctx = create_adhoc_context(&hostname, username.as_deref(), ip.as_deref());

	// 2. Resolve destination context
	let dest_ctx = RuntimeContext::load(to_host).map_err(|e| {
		format!("Error: Destination host '{}' not found in configuration: {}", to_host, e)
	})?;

	if !dest_ctx.has_disko {
		return Err(
			format!(
				"Error: Destination host '{}' does not have a Disko partition layout configured.",
				to_host
			)
			.into(),
		);
	}

	let source_disk_bus = source_ctx.deployment.proxmox.disk_bus.trim();
	let dest_disk_bus = dest_ctx.deployment.proxmox.disk_bus.trim();
	if !source_disk_bus.is_empty() && !dest_disk_bus.is_empty() && source_disk_bus != dest_disk_bus {
		return Err(format!(
            "Source '{}' uses Proxmox diskBus='{}', but install host '{}' expects diskBus='{}'. These expose different Linux disk names and can make Disko target a missing disk. Use a convert target with matching diskBus or recreate the VM with the install host's disk bus.",
            source_ctx.hostname,
            source_disk_bus,
            dest_ctx.hostname,
            dest_disk_bus
        )
        .into());
	}

	// 3. Construct install context by merging destination with source VM properties
	let mut install_ctx = dest_ctx;
	install_ctx.target_ip = source_ctx.target_ip.clone();
	install_ctx.is_ip_overridden = true;

	// Preserve source VM deployment identity for correct connection/provider resolution
	install_ctx.deployment.vmid = source_ctx.deployment.vmid.clone();
	install_ctx.deployment.proxmox = source_ctx.deployment.proxmox.clone();
	install_ctx.deployment.vmware = source_ctx.deployment.vmware.clone();
	install_ctx.deployment.digitalocean = source_ctx.deployment.digitalocean.clone();
	install_ctx.deployment.wsl = source_ctx.deployment.wsl.clone();

	// 4. Print Planning Summary
	println!("================ Planning for Convert ================");
	println!("Source Target:  {}", target_spec);
	println!("Convert To:     {}", to_host);
	println!("Initial SSH:    {}@{}", source_ctx.username, install_ctx.target_ip);
	println!("Target IP:      {}", install_ctx.target_ip);
	if !install_ctx.deployment.vmid.is_empty() {
		println!("Provider VMID:  {}", install_ctx.deployment.vmid);
	}
	println!("Build On:       RemoteBuilder (Delegated via SSH to deploy@utils)");
	println!("======================================================");

	let is_forced = crate::config::get_runtime_options().force;
	if !crate::workflow::confirm::confirm_action(
		"Are you sure you want to proceed with conversion?",
		None,
		is_forced,
	)
	.unwrap_or(false)
	{
		return Err("Aborted by user.".into());
	}

	// 5. Build and stage the source set and secrets for destination host
	let source_set = prepare_source_set(
		crate::config::get_runtime_options().flake.as_deref(),
		&[install_ctx.hostname.clone()],
		logger.clone(),
	)?;
	let mut cleanup_guard = SourceCleanupGuard::new(source_set.run_id.clone(), logger.clone());

	// 6. Setup store workspace and transfer inputs to remote builder
	let destinations = crate::workspace::source::store_input_destinations(&install_ctx, false);
	for dest in &destinations {
		cleanup_guard.track_remote(dest);
	}

	let mut workspace =
		prepare_store_workspace(&install_ctx, &source_set, Vec::new(), logger.clone())?;
	workspace.ensure_store_inputs(false, logger.clone())?;

	// 7. Resolve the conversion mode and run the takeover deployment
	let mode = DeploymentMode::from_context(workspace.context(), true);
	run_deployment(workspace.context(), mode, logger.clone())?;

	Ok(())
}
