pub mod local;
pub mod source;

pub use local::clean_stale_temp_dirs;
pub use source::{
	PreparedSourceSet, ShortLivedTempDir, clean_stale_gc_roots, cleanup_gc_roots,
	cleanup_remote_gc_roots, prepare_source_set, store_input_destinations,
	transfer_and_root_source_set,
};

use crate::config;
use crate::context::RuntimeContext;
use crate::process::Logger;

pub struct HostWorkspace {
	pub ctx: RuntimeContext,
	run_id: String,
	remote_destinations: Vec<String>,
	owned_remote_destinations: Vec<String>,
}

impl HostWorkspace {
	pub fn context(&self) -> &RuntimeContext {
		&self.ctx
	}

	pub fn context_mut(&mut self) -> &mut RuntimeContext {
		&mut self.ctx
	}

	pub fn ensure_store_inputs(
		&mut self,
		home_manager: bool,
		logger: Logger,
	) -> Result<(), Box<dyn std::error::Error>> {
		let required = crate::workspace::source::store_input_destinations(&self.ctx, home_manager);
		let mut secret_store_paths = std::collections::HashMap::new();
		if let Some(secret_path) = &self.ctx.secret_store_path {
			secret_store_paths.insert(self.ctx.hostname.clone(), secret_path.clone());
		}
		let source_set = PreparedSourceSet {
			run_id: self.run_id.clone(),
			source_store_path: self
				.ctx
				.source_store_path
				.clone()
				.ok_or("Prepared workspace is missing its source store path")?,
			secret_store_paths,
		};

		for destination in required {
			if self.remote_destinations.contains(&destination) {
				continue;
			}
			crate::workspace::source::transfer_and_root_source_set(
				&destination,
				&source_set,
				std::slice::from_ref(&self.ctx.hostname),
				logger.clone(),
			)?;
			self.remote_destinations.push(destination);
			self
				.owned_remote_destinations
				.push(self.remote_destinations.last().expect("destination was just inserted").clone());
		}
		Ok(())
	}

	pub fn refresh_host_secret(&mut self, logger: Logger) -> Result<(), Box<dyn std::error::Error>> {
		if let Some(source) =
			config::resolve_host_sops_source(&self.ctx.hostname).filter(|s| s.path.is_file())
		{
			let secret_temp_dir = ShortLivedTempDir::new("secret")?;
			let staged_file = secret_temp_dir.path.join(format!("{}.yaml", self.ctx.hostname));
			std::fs::copy(&source.path, &staged_file)?;
			#[cfg(unix)]
			{
				use std::os::unix::fs::PermissionsExt;
				std::fs::set_permissions(&staged_file, std::fs::Permissions::from_mode(0o600))?;
			}
			let secret_store_path = crate::workspace::source::nix_store_add(
				config::SECRET_INPUT_NAME,
				&secret_temp_dir.path,
				&logger,
			)?;
			crate::workspace::source::replace_local_secret_gc_root(
				&self.run_id,
				&self.ctx.hostname,
				&secret_store_path,
				logger.clone(),
			)?;
			self.ctx.secret_store_path = Some(secret_store_path.clone());

			for destination in &self.remote_destinations {
				crate::workspace::source::transfer_and_root_secret(
					destination,
					&self.run_id,
					&self.ctx.hostname,
					&secret_store_path,
					logger.clone(),
				)?;
			}
		}
		Ok(())
	}
}

pub fn prepare_store_workspace(
	ctx: &RuntimeContext,
	source_set: &PreparedSourceSet,
	remote_destinations: Vec<String>,
	_logger: Logger,
) -> Result<HostWorkspace, Box<dyn std::error::Error>> {
	let mut prepared = ctx.clone();
	prepared.source_store_path = Some(source_set.source_store_path.clone());
	prepared.secret_store_path = source_set.secret_store_paths.get(&ctx.hostname).cloned();
	Ok(HostWorkspace {
		ctx: prepared,
		run_id: source_set.run_id.clone(),
		remote_destinations,
		owned_remote_destinations: Vec::new(),
	})
}

impl Drop for HostWorkspace {
	fn drop(&mut self) {
		for destination in &self.owned_remote_destinations {
			let _ = crate::workspace::source::cleanup_remote_gc_roots(
				destination,
				&self.run_id,
				Logger::silent(),
			);
		}
	}
}
