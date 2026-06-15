use crate::execution::coordinator::{OperationCoordinator, OperationKind, OperationRequest};

pub struct DeployCmdOptions<'a> {
	pub target: Option<&'a String>,
	pub hosts: Option<&'a String>,
	pub plan: bool,
	pub redeploy: bool,
	pub overwrite: bool,
	pub build_iso: bool,
	pub force: bool,
	pub parallel: usize,
}

pub async fn execute_deploy(opts: DeployCmdOptions<'_>) -> Result<(), Box<dyn std::error::Error>> {
	let req = OperationRequest {
		kind: OperationKind::Deploy,
		target: opts.target.cloned(),
		hosts: opts.hosts.cloned(),
		plan_only: opts.plan,
		redeploy: opts.redeploy,
		overwrite: opts.overwrite,
		force: opts.force,
		parallel: opts.parallel,
		home_manager: false,
	};

	let coord = OperationCoordinator::new(req);
	coord.run().await
}
