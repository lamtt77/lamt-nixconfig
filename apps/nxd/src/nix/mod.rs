pub mod build;
pub mod build_commands;
pub mod build_local;
mod build_remote_builder;
mod build_target_instantiated;
mod build_target_native;
pub mod copy;
pub mod eval;
pub mod remote_builder;
pub mod strategy;

pub use strategy::{BuildStrategy, NixBuilder};

use crate::process::Logger;

impl NixBuilder {
	pub fn config_kind(&self) -> &'static str {
		if self.strategy == BuildStrategy::Cross {
			"crossNixosConfigurations"
		} else if self.system.contains("darwin") {
			"darwinConfigurations"
		} else {
			"nixosConfigurations"
		}
	}

	pub fn target_attr(&self, attr: &str) -> String {
		if self.strategy == BuildStrategy::Cross {
			format!("crossNixosConfigurations.{}.{}", self.hostname, attr)
		} else if self.system.contains("darwin") && attr == "config.system.build.toplevel" {
			format!("{}.{}.system", self.config_kind(), self.hostname)
		} else {
			format!("{}.{}.{}", self.config_kind(), self.hostname, attr)
		}
	}

	pub fn nix_copy_args_with_log<'a>(
		&self,
		copy_target: &'a str,
		source: &'a str,
		logger: Logger,
	) -> Vec<&'a str> {
		copy::nix_copy_args_with_log(self, copy_target, source, logger)
	}

	pub fn nix_copy_command_with_log(
		&self,
		copy_target: &str,
		source: &str,
		logger: Logger,
	) -> String {
		copy::nix_copy_command_with_log(self, copy_target, source, logger)
	}

	pub fn build_attribute(
		&self,
		attr: &str,
		mount_point: Option<&str>,
		logger: Logger,
	) -> Result<String, Box<dyn std::error::Error>> {
		build::build_attribute(self, attr, mount_point, logger)
	}

	pub fn build_system(
		&self,
		mount_point: Option<&str>,
		logger: Logger,
	) -> Result<String, Box<dyn std::error::Error>> {
		self.build_attribute("config.system.build.toplevel", mount_point, logger)
	}
}

#[cfg(test)]
mod tests {
	use super::BuildStrategy;

	#[test]
	fn renders_build_strategy_labels() {
		assert_eq!(BuildStrategy::Local.label(), "Local (Natively on Orchestrator)");
		assert_eq!(
			BuildStrategy::RemoteBuilder { ssh_connection: "deploy@utils".to_string() }.label(),
			"RemoteBuilder (Delegated via SSH to deploy@utils)"
		);
		assert_eq!(
			BuildStrategy::TargetInstantiated.label(),
			"TargetInstantiated (Instantiation on Orchestrator -> Realization on Target)"
		);
		assert_eq!(
			BuildStrategy::TargetNative.label(),
			"TargetNative (Natively built directly on target)"
		);
		assert_eq!(
			BuildStrategy::Cross.label(),
			"Cross (Cross-compiled from Orchestrator via crossNixosConfigurations)"
		);
	}

	#[test]
	fn renders_cross_build_strategy_target_attrs() {
		use super::NixBuilder;

		let builder = NixBuilder {
			strategy: BuildStrategy::Cross,
			hostname: "gaming".to_string(),
			target_ip: "10.0.0.5".to_string(),
			username: "root".to_string(),
			system: "x86_64-linux".to_string(),
			low_mem: false,
			substitute_on_destination: false,
			has_local_nix: true,
			source_store_path: None,
			secret_store_path: None,
			wsl_bootstrap_user: None,
			wsl_windows_connection: None,
			wsl_distribution: None,
		};

		assert_eq!(
			builder.target_attr("config.system.build.toplevel"),
			"crossNixosConfigurations.gaming.config.system.build.toplevel"
		);
		assert_eq!(
			builder.target_attr("config.system.build.diskoScript"),
			"crossNixosConfigurations.gaming.config.system.build.diskoScript"
		);
	}
}
