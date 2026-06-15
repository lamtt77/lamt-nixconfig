use crate::context::{load_batch_contexts, load_context_from_spec};
use crate::execution::batch;
use crate::fleet::local::current_local_hostname;
use crate::fleet::resolution::{resolve_provider, resolve_target_ip, resolve_target_ip_for_deploy};
use crate::planning::{self, OperationKind as PlanOperationKind, PlanHostOptions};
use crate::process::Logger;
use crate::workspace;
use std::collections::BTreeSet;
use std::sync::Arc;

#[derive(Clone, Debug)]
pub enum OperationKind {
	Deploy,
	Switch { action: String },
}

#[derive(Clone, Debug)]
pub struct OperationRequest {
	pub kind: OperationKind,
	pub target: Option<String>,
	pub hosts: Option<String>,
	pub plan_only: bool,
	pub redeploy: bool,
	pub overwrite: bool,
	pub force: bool,
	pub parallel: usize,
	pub home_manager: bool,
}

pub struct OperationCoordinator {
	pub request: OperationRequest,
}

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
			let _ =
				workspace::source::cleanup_remote_gc_roots(destination, &self.run_id, self.logger.clone());
		}
		let _ = workspace::source::cleanup_gc_roots(&self.run_id, self.logger.clone());
	}
}

impl OperationCoordinator {
	pub fn new(request: OperationRequest) -> Self {
		Self { request }
	}

	pub async fn run(&self) -> Result<(), Box<dyn std::error::Error>> {
		crate::command::hosts::validate_target_and_hosts(
			self.request.target.as_ref(),
			self.request.hosts.as_ref(),
		)?;

		let is_deploy = matches!(self.request.kind, OperationKind::Deploy);
		let logger = Logger::terminal();

		// 1. Load contexts
		let mut planned_hosts = if let Some(hosts_str) = &self.request.hosts {
			let host_list = crate::command::hosts::resolve_hosts_arg(hosts_str)?;
			let validate_host_keys = matches!(&self.request.kind, OperationKind::Switch { .. });
			load_batch_contexts(&host_list, validate_host_keys)?
		} else {
			let target_host = self.request.target.clone().unwrap_or_else(current_local_hostname);
			if target_host.is_empty() {
				return Err("Error: Could not determine current hostname for default target.".into());
			}
			let mut ctx = load_context_from_spec(&target_host)?;
			ctx.target_ip = if is_deploy {
				resolve_target_ip_for_deploy(&ctx, logger.clone())
			} else {
				resolve_target_ip(&ctx, logger.clone())
			};
			vec![ctx]
		};

		// 2. Resolve provider states & build host plans
		let mut plans = Vec::new();
		for ctx in &planned_hosts {
			let provider = resolve_provider(ctx, logger.clone());
			let provider_snapshot =
				provider.as_deref().map(crate::providers::inspect_provider).transpose().map_err(
					|error| format!("Failed to inspect provider for '{}': {}", ctx.hostname, error),
				)?;

			let switch_action = match &self.request.kind {
				OperationKind::Switch { action } => Some(action.as_str()),
				_ => None,
			};
			let plan_kind = match &self.request.kind {
				OperationKind::Deploy => PlanOperationKind::Deploy,
				OperationKind::Switch { .. } => PlanOperationKind::Switch,
			};

			let plan = planning::plan_host(PlanHostOptions {
				ctx,
				operation: plan_kind,
				redeploy: self.request.redeploy,
				overwrite: self.request.overwrite,
				switch_action,
				home_manager: self.request.home_manager,
				provider: provider_snapshot,
			});
			plans.push(plan);
		}

		// 3. Render host plans
		if is_deploy {
			println!("================ Planning for Deploy ================");
		} else {
			println!("================ Planning for Switch ================");
		}
		for (ctx, plan) in planned_hosts.iter().zip(&plans) {
			plan.render(ctx);
		}
		println!("====================================================");

		// 4. Exit if plan-only requested
		if self.request.plan_only {
			return Ok(());
		}

		// For single host deploy, if skip reason exists, exit early
		if is_deploy
			&& self.request.hosts.is_none()
			&& planned_hosts.len() == 1
			&& let Some(ref reason) = plans[0].skip_reason
		{
			println!("{}", reason);
			return Ok(());
		}

		// 5. Confirm operation
		let should_confirm = match &self.request.kind {
			OperationKind::Deploy => true,
			OperationKind::Switch { .. } => plans.len() > 1,
		};

		if should_confirm && !planning::confirm_batch(&plans, self.request.force)? {
			if is_deploy {
				if self.request.redeploy {
					println!("Redeployment aborted by user.");
				} else {
					println!("Deployment aborted by user.");
				}
			} else {
				println!("Switch aborted by user.");
			}
			return Ok(());
		}

		let mut executable_hosts = Vec::new();
		for (ctx, plan) in planned_hosts.into_iter().zip(&plans) {
			if plan.skip_reason.is_none() {
				executable_hosts.push(ctx);
			}
		}
		planned_hosts = executable_hosts;
		if planned_hosts.is_empty() {
			println!("No hosts require execution.");
			return Ok(());
		}

		// 6. Prepare source set
		println!("Preparing source set...");
		let flake_arg = crate::config::get_runtime_options().flake.clone();
		let hostnames: Vec<String> = planned_hosts.iter().map(|ctx| ctx.hostname.clone()).collect();

		let source_set = Arc::new(workspace::source::prepare_source_set(
			flake_arg.as_deref(),
			&hostnames,
			logger.clone(),
		)?);
		let mut cleanup_guard = SourceCleanupGuard::new(source_set.run_id.clone(), logger.clone());

		// 7. Group hosts by remote builder destination and pre-transfer source set
		let mut dest_to_hosts: std::collections::HashMap<String, Vec<String>> =
			std::collections::HashMap::new();
		for ctx in &planned_hosts {
			let pretransfer_destination = if self.request.home_manager || ctx.system.contains("darwin") {
				None
			} else {
				workspace::source::remote_builder_destination(ctx)
			};
			if let Some(destination) = pretransfer_destination {
				dest_to_hosts.entry(destination).or_default().push(ctx.hostname.clone());
			}
		}
		for (dest, host_list) in &dest_to_hosts {
			workspace::source::transfer_and_root_source_set(
				dest,
				&source_set,
				host_list,
				logger.clone(),
			)?;
			cleanup_guard.track_remote(dest);
		}

		// 8. Stage Proxmox ISOs if deploying
		if is_deploy {
			for ctx in &planned_hosts {
				crate::planning::plan_iso::ensure_proxmox_iso(
					ctx,
					&source_set.source_store_path,
					logger.clone(),
				)?;
			}
		}

		// 9. Prepare one execution shape for both single-host and batch paths.
		let plan_kind = match &self.request.kind {
			OperationKind::Deploy => PlanOperationKind::Deploy,
			OperationKind::Switch { .. } => PlanOperationKind::Switch,
		};
		let switch_action = match &self.request.kind {
			OperationKind::Switch { action } => Some(action.clone()),
			OperationKind::Deploy => None,
		};
		let mut jobs = Vec::new();
		for ctx in planned_hosts {
			let transfer_destinations =
				if !is_deploy && (self.request.home_manager || ctx.system.contains("darwin")) {
					Vec::new()
				} else {
					workspace::source::remote_builder_destination(&ctx).into_iter().collect()
				};
			jobs.push(batch::PreparedHostJob {
				context: ctx,
				transfer_destinations,
				operation: plan_kind,
				execution: crate::execution::host::HostExecutionContext {
					logger: logger.clone(),
					redeploy: self.request.redeploy,
					overwrite: self.request.overwrite,
					switch_action: switch_action.clone(),
					home_manager: self.request.home_manager,
				},
			});
		}

		if jobs.len() == 1 {
			let job = jobs.pop().expect("single prepared job");
			let mut host_workspace = workspace::prepare_store_workspace(
				&job.context,
				&source_set,
				job.transfer_destinations,
				logger.clone(),
			)?;
			crate::execution::host::execute_host_operation(
				job.operation,
				&job.execution,
				&mut host_workspace,
			)
		} else {
			batch::BatchRunner::run(jobs, source_set, self.request.parallel).await
		}
	}
}
