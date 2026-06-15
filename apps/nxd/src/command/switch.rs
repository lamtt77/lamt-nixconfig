use crate::execution::coordinator::{OperationCoordinator, OperationKind, OperationRequest};

pub async fn execute_switch(
	target: Option<&String>,
	hosts: Option<&String>,
	action: &str,
	hm: bool,
	force: bool,
	parallel: usize,
) -> Result<(), Box<dyn std::error::Error>> {
	let req = OperationRequest {
		kind: OperationKind::Switch { action: action.to_string() },
		target: target.cloned(),
		hosts: hosts.cloned(),
		plan_only: false,
		redeploy: false,
		overwrite: false,
		force,
		parallel,
		home_manager: hm,
	};

	let coord = OperationCoordinator::new(req);
	coord.run().await
}
