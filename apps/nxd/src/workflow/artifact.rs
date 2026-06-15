use crate::config;
use crate::context::RuntimeContext;
use crate::process::{CommandExecutor, Logger};
use crate::workspace;
use std::path::{Path, PathBuf};

const MINIMAL_WSL_ATTR: &str =
	"nixosConfigurations.minimal-wsl-x86.config.system.build.tarballBuilder";
const DEFAULT_WSL_OUTPUT: &str = "result-wsl/nixos-wsl-custom.tar.gz";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DeploymentArtifact {
	Local { path: PathBuf, checksum: String },
	Remote { connection: String, path: String, checksum: String, persistent: bool },
}

impl DeploymentArtifact {
	pub fn checksum(&self) -> &str {
		match self {
			Self::Local { checksum, .. } | Self::Remote { checksum, .. } => checksum,
		}
	}

	pub fn producer_label(&self) -> &str {
		match self {
			Self::Local { .. } => "local orchestrator",
			Self::Remote { connection, .. } => connection,
		}
	}

	pub fn cleanup(&self, logger: Logger) {
		match self {
			Self::Local { path, .. } => {
				let _ = std::fs::remove_file(path);
			}
			Self::Remote { connection, path, persistent, .. } if !persistent => {
				let command = format!("sudo rm -f {}", crate::process::shell_escape(path));
				let _ = CommandExecutor::execute_ssh(connection, &command, logger);
			}
			Self::Remote { .. } => {}
		}
	}
}

pub fn ensure_minimal_wsl(
	output: &Path,
	logger: Logger,
) -> Result<PathBuf, Box<dyn std::error::Error>> {
	if output.is_file() && output.metadata()?.len() > 0 {
		info!(logger, "Reusing minimal WSL artifact: {}", output.display());
		return Ok(output.to_path_buf());
	}
	build_minimal_wsl(Some(output), logger)
}

pub fn build_minimal_wsl(
	output: Option<&Path>,
	logger: Logger,
) -> Result<PathBuf, Box<dyn std::error::Error>> {
	let output = output.map(PathBuf::from).unwrap_or_else(|| PathBuf::from(DEFAULT_WSL_OUTPUT));
	let output = if output.is_absolute() { output } else { std::env::current_dir()?.join(output) };
	if let Some(parent) = output.parent() {
		std::fs::create_dir_all(parent)?;
	}

	let source_set = workspace::source::prepare_source_set(
		config::get_runtime_options().flake.as_deref(),
		&[],
		logger.clone(),
	)?;
	let result = if cfg!(target_os = "linux") && cfg!(target_arch = "x86_64") {
		build_local(&source_set.source_store_path, &output, logger.clone())
	} else {
		let builder = config::get_runtime_options()
			.builder
			.clone()
			.unwrap_or_else(|| config::DEFAULT_BUILDER.to_string());
		build_remote(&source_set, &builder, &output, logger.clone())
	};

	let _ = workspace::source::cleanup_gc_roots(&source_set.run_id, logger.clone());
	result?;

	let output_str = output.to_string_lossy().to_string();
	let digest = CommandExecutor::execute(
		"nix",
		&["hash", "file", "--type", "sha256", &output_str],
		logger.clone(),
	)?;
	success!(logger, "Minimal WSL artifact: {}", output.display());
	info!(logger, "SHA-256: {}", digest.trim());
	Ok(output)
}

pub fn build_minimal_wsl_for_deployment(
	ctx: &RuntimeContext,
	logger: Logger,
) -> Result<DeploymentArtifact, Box<dyn std::error::Error>> {
	let source_store_path = ctx
		.source_store_path
		.as_deref()
		.ok_or("Prepared WSL deployment workspace is missing its source store path")?;
	let run_id = crate::workspace::local::unique_suffix();

	if cfg!(target_os = "linux") && cfg!(target_arch = "x86_64") {
		build_local_deployment_artifact(source_store_path, &run_id, logger)
	} else {
		let runtime_builder = config::get_runtime_options().builder.as_deref().unwrap_or_default();
		let builder = if !runtime_builder.is_empty() {
			runtime_builder
		} else if !ctx.deployment.builder.is_empty() {
			&ctx.deployment.builder
		} else {
			config::DEFAULT_BUILDER
		};
		build_remote_deployment_artifact(source_store_path, builder, &run_id, true, logger)
	}
}

fn build_local(
	source_store_path: &str,
	output: &Path,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	let flake_attr = format!("path:{}#{}", source_store_path, MINIMAL_WSL_ATTR);
	let builder_path = CommandExecutor::execute(
		"nix",
		&["build", &flake_attr, "--no-link", "--print-out-paths"],
		logger.clone(),
	)?;
	run_tarball_builder(None, builder_path.trim(), &output.to_string_lossy(), logger)
}

fn build_local_deployment_artifact(
	source_store_path: &str,
	run_id: &str,
	logger: Logger,
) -> Result<DeploymentArtifact, Box<dyn std::error::Error>> {
	let output = std::env::temp_dir().join(format!("nxd-minimal-wsl-{}.tar.gz", run_id));
	build_local(source_store_path, &output, logger.clone())?;
	let output_string = output.to_string_lossy().to_string();
	let checksum = hash_file(None, &output_string, logger)?;
	Ok(DeploymentArtifact::Local { path: output, checksum })
}

fn build_remote(
	source_set: &workspace::source::PreparedSourceSet,
	builder: &str,
	output: &Path,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	if !crate::nix::remote_builder::check_builder_compatible(builder, "x86_64-linux") {
		return Err(
			format!("Remote builder '{}' is not a reachable x86_64-linux host", builder).into(),
		);
	}

	(|| -> Result<(), Box<dyn std::error::Error>> {
		let artifact = build_remote_deployment_artifact(
			&source_set.source_store_path,
			builder,
			&source_set.run_id,
			false,
			logger.clone(),
		)?;
		let DeploymentArtifact::Remote { connection, path, .. } = &artifact else {
			unreachable!("remote artifact builder returned a local artifact")
		};
		let source = format!("{}:{}", connection, path);
		let destination = output.to_string_lossy().to_string();
		let copy_result = CommandExecutor::execute(
			"scp",
			&[
				"-o",
				crate::remote::ssh::WARN_WEAK_CRYPTO_OPTION,
				"-o",
				"StrictHostKeyChecking=no",
				"-o",
				"UserKnownHostsFile=/dev/null",
				&source,
				&destination,
			],
			logger.clone(),
		);
		artifact.cleanup(Logger::silent());
		copy_result?;
		Ok(())
	})()
}

fn build_remote_deployment_artifact(
	source_store_path: &str,
	builder: &str,
	run_id: &str,
	source_already_staged: bool,
	logger: Logger,
) -> Result<DeploymentArtifact, Box<dyn std::error::Error>> {
	if !crate::nix::remote_builder::check_builder_compatible(builder, "x86_64-linux") {
		return Err(
			format!("Remote builder '{}' is not a reachable x86_64-linux host", builder).into(),
		);
	}

	if !source_already_staged {
		let source_set = workspace::source::PreparedSourceSet {
			run_id: run_id.to_string(),
			source_store_path: source_store_path.to_string(),
			secret_store_paths: std::collections::HashMap::new(),
		};
		if let Err(error) =
			workspace::source::transfer_and_root_source_set(builder, &source_set, &[], logger.clone())
		{
			let _ = workspace::source::cleanup_remote_gc_roots(builder, run_id, Logger::silent());
			return Err(error);
		}
	}

	let result = (|| -> Result<DeploymentArtifact, Box<dyn std::error::Error>> {
		let flake_attr = format!("path:{}#{}", source_store_path, MINIMAL_WSL_ATTR);
		info!(logger, "Building minimal WSL tarball builder on {}...", builder);
		let build_command = format!(
			"nix build {} --no-link --print-out-paths",
			crate::process::shell_escape(&flake_attr)
		);
		let builder_path = CommandExecutor::execute_ssh(builder, &build_command, logger.clone())?;
		let builder_path = builder_path.trim();
		let cache_key = builder_path
			.rsplit('/')
			.next()
			.filter(|value| !value.is_empty())
			.ok_or("Minimal WSL tarball builder returned an invalid store path")?;
		let remote_home =
			CommandExecutor::execute_ssh(builder, "printf '%s' \"$HOME\"", Logger::silent())?;
		let cache_dir =
			format!("{}/.cache/{}/artifacts/minimal-wsl", remote_home.trim(), config::APP_NAME);
		let cached_output = format!("{}/{}.tar.gz", cache_dir, cache_key);
		let prepare_cache = format!(
			"mkdir -p \"{}\" && if [ -s \"{}\" ]; then echo HIT; else echo MISS; fi",
			cache_dir, cached_output
		);
		let cache_state = CommandExecutor::execute_ssh(builder, &prepare_cache, Logger::silent())?;
		if cache_state.trim() == "HIT" {
			info!(logger, "Reusing cached minimal WSL archive on {}.", builder);
		} else {
			let temporary_output = format!("{}/.{}.{}.partial", cache_dir, cache_key, run_id);
			info!(logger, "Creating compressed minimal WSL archive on {}...", builder);
			let build_result =
				run_tarball_builder(Some(builder), builder_path, &temporary_output, logger.clone());
			if let Err(error) = build_result {
				let cleanup = format!("sudo rm -f {}", crate::process::shell_escape(&temporary_output));
				let _ = CommandExecutor::execute_ssh(builder, &cleanup, Logger::silent());
				return Err(error);
			}
			CommandExecutor::execute_ssh(
				builder,
				&format!(
					"sudo chmod 0644 {} && mv -f {} {}",
					crate::process::shell_escape(&temporary_output),
					crate::process::shell_escape(&temporary_output),
					crate::process::shell_escape(&cached_output)
				),
				logger.clone(),
			)?;
		}
		info!(logger, "Hashing minimal WSL archive on {}...", builder);
		let checksum = hash_file(Some(builder), &cached_output, logger)?;
		CommandExecutor::execute_ssh(
			builder,
			&format!("find \"{}\" -maxdepth 1 -type f -name '*.tar.gz' -mtime +30 -delete", cache_dir),
			Logger::silent(),
		)?;
		Ok(DeploymentArtifact::Remote {
			connection: builder.to_string(),
			path: cached_output,
			checksum,
			persistent: true,
		})
	})();
	if !source_already_staged {
		let _ = workspace::source::cleanup_remote_gc_roots(builder, run_id, Logger::silent());
	}
	result
}

fn hash_file(
	remote: Option<&str>,
	path: &str,
	logger: Logger,
) -> Result<String, Box<dyn std::error::Error>> {
	let output = if let Some(connection) = remote {
		let command =
			format!("nix hash file --type sha256 --base16 {}", crate::process::shell_escape(path));
		CommandExecutor::execute_ssh(connection, &command, logger)?
	} else {
		CommandExecutor::execute(
			"nix",
			&["hash", "file", "--type", "sha256", "--base16", path],
			logger,
		)?
	};
	Ok(output.trim().to_string())
}

fn run_tarball_builder(
	remote: Option<&str>,
	builder_path: &str,
	output: &str,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	let script = format!("{}/bin/nixos-wsl-tarball-builder", builder_path);
	if let Some(connection) = remote {
		let command = format!(
			"sudo {} {}",
			crate::process::shell_escape(&script),
			crate::process::shell_escape(output)
		);
		CommandExecutor::execute_ssh(connection, &command, logger)?;
	} else {
		CommandExecutor::execute("sudo", &[&script, output], logger)?;
	}
	Ok(())
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn remote_artifact_cleanup_runs_on_the_producer() {
		CommandExecutor::start_recording();
		let artifact = DeploymentArtifact::Remote {
			connection: "deploy@utils".to_string(),
			path: "/tmp/nxd-minimal-wsl-test.tar.gz".to_string(),
			checksum: "abc123".to_string(),
			persistent: false,
		};

		artifact.cleanup(Logger::silent());
		let commands = CommandExecutor::stop_recording().unwrap();
		CommandExecutor::clear_mocks();

		assert_eq!(artifact.checksum(), "abc123");
		assert_eq!(artifact.producer_label(), "deploy@utils");
		assert!(commands.iter().any(|command| {
			command.contains("deploy@utils")
				&& command.contains("sudo rm -f /tmp/nxd-minimal-wsl-test.tar.gz")
		}));
	}
}
