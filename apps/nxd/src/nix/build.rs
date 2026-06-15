use crate::nix::{BuildStrategy, NixBuilder};
use crate::process::Logger;

pub struct BuildRequest {
	pub attr: String,
	pub mount_point: Option<String>,
}

impl BuildRequest {
	pub fn new(attr: &str, mount_point: Option<&str>) -> Self {
		Self { attr: attr.to_string(), mount_point: mount_point.map(str::to_string) }
	}
}

pub struct BuildOutput {
	pub store_path: String,
}

pub fn build_attribute(
	builder: &NixBuilder,
	attr: &str,
	mount_point: Option<&str>,
	logger: Logger,
) -> Result<String, Box<dyn std::error::Error>> {
	let request = BuildRequest::new(attr, mount_point);
	let output = match &builder.strategy {
		BuildStrategy::Local | BuildStrategy::Cross => {
			crate::nix::build_local::build(builder, &request, logger)?
		}
		BuildStrategy::RemoteBuilder { ssh_connection } => {
			crate::nix::build_remote_builder::build(builder, ssh_connection, &request, logger)?
		}
		BuildStrategy::TargetInstantiated => {
			crate::nix::build_target_instantiated::build(builder, &request, logger)?
		}
		BuildStrategy::TargetNative => {
			crate::nix::build_target_native::build(builder, &request, logger)?
		}
	};

	Ok(output.store_path)
}
