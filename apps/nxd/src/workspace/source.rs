use crate::config;
use crate::process::{CommandExecutor, Logger};
use serde_json::Value;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

pub struct ShortLivedTempDir {
	pub path: PathBuf,
}

impl ShortLivedTempDir {
	pub fn new(prefix: &str) -> Result<Self, Box<dyn std::error::Error>> {
		let tmp_dir = std::env::var("TMPDIR").unwrap_or_else(|_| "/tmp".to_string());
		let run_id = crate::workspace::local::unique_suffix();
		let path = PathBuf::from(tmp_dir).join(format!("{}-{}-{}", config::APP_NAME, prefix, run_id));
		fs::create_dir_all(&path)?;

		#[cfg(unix)]
		{
			use std::os::unix::fs::PermissionsExt;
			fs::set_permissions(&path, fs::Permissions::from_mode(0o700))?;
		}

		Ok(Self { path })
	}
}

impl Drop for ShortLivedTempDir {
	fn drop(&mut self) {
		if self.path.exists() {
			#[cfg(unix)]
			{
				let _ = std::process::Command::new("chmod")
					.args(["-R", "u+w", &self.path.to_string_lossy()])
					.status();
			}
			let _ = fs::remove_dir_all(&self.path);
		}
	}
}

pub fn nix_store_add(
	name: &str,
	path: &Path,
	logger: &Logger,
) -> Result<String, Box<dyn std::error::Error>> {
	let path_str = path.to_string_lossy().to_string();
	let args = ["store", "add", "--name", name, &path_str];
	crate::info!(logger, "Adding to Nix store: nix store add --name {} {}", name, path.display());
	let output = CommandExecutor::execute("nix", &args, logger.clone())?;
	Ok(output.trim().to_string())
}

#[derive(Debug, Clone)]
pub struct PreparedSourceSet {
	pub run_id: String,
	pub source_store_path: String,
	pub secret_store_paths: std::collections::HashMap<String, String>, // hostname -> secret_store_path
}

fn snapshot_git_files(source: &Path, destination: &Path) -> Result<(), Box<dyn std::error::Error>> {
	let files = Command::new("git")
		.args(["ls-files", "-z", "--cached", "--others", "--exclude-standard"])
		.current_dir(source)
		.output()?;
	if !files.status.success() {
		return Err("Failed to list tracked and untracked Git source files.".into());
	}

	let mut rsync = Command::new("rsync")
		.args(["-a", "--from0", "--files-from=-", "./"])
		.arg(format!("{}/", destination.display()))
		.current_dir(source)
		.stdin(Stdio::piped())
		.spawn()?;
	rsync.stdin.take().ok_or("Failed to open rsync input")?.write_all(&files.stdout)?;
	if !rsync.wait()?.success() {
		return Err("Failed to snapshot tracked and untracked Git source files.".into());
	}
	Ok(())
}

pub fn prepare_source_set(
	flake_arg: Option<&str>,
	hostnames: &[String],
	logger: Logger,
) -> Result<PreparedSourceSet, Box<dyn std::error::Error>> {
	let resolved_flake = config::resolve_flake(flake_arg);
	let run_id = crate::workspace::local::unique_suffix();

	crate::info!(logger, "Preparing store-backed source set for resolved flake: {}", resolved_flake);

	let source_store_path = if config::is_local_flake(&resolved_flake) {
		let path = config::local_flake_path(&resolved_flake)
			.ok_or_else(|| format!("Unable to resolve local flake path '{}'.", resolved_flake))?;
		if !path.exists() {
			return Err(format!("Local flake path does not exist: {}", path.display()).into());
		}
		if !path.join("flake.nix").is_file() {
			return Err(
				format!("Local flake path does not contain flake.nix: {}", path.display()).into(),
			);
		}
		let local_path = fs::canonicalize(path)?;

		let is_git = std::process::Command::new("git")
			.args(["-C", &local_path.to_string_lossy(), "rev-parse", "--is-inside-work-tree"])
			.output()
			.map(|out| out.status.success() && String::from_utf8_lossy(&out.stdout).trim() == "true")
			.unwrap_or(false);

		if is_git {
			let deleted_output = std::process::Command::new("git")
				.args(["-C", &local_path.to_string_lossy(), "ls-files", "--deleted"])
				.output()?;
			let deleted_str = String::from_utf8_lossy(&deleted_output.stdout);
			if !deleted_str.trim().is_empty() {
				let listed = deleted_str
					.lines()
					.filter(|line| !line.trim().is_empty())
					.map(|line| format!("  {}", line))
					.collect::<Vec<_>>()
					.join("\n");
				return Err(format!(
					"Missing tracked files detected in the working tree. Stage or restore them before deploying:\n{}",
					listed
				)
				.into());
			}

			let untracked = Command::new("git")
				.args(["ls-files", "--others", "--exclude-standard"])
				.current_dir(&local_path)
				.output()?;
			if !untracked.status.success() {
				return Err("Failed to inspect untracked Git source files.".into());
			}

			if untracked.stdout.is_empty() {
				let git_url = format!("git+file://{}", local_path.display());
				crate::info!(logger, "Archiving Git flake source {}...", git_url);
				let mut args = vec!["flake", "archive", "--json", &git_url];
				let token_args = config::nix_token_args();
				let token_args_ref: Vec<&str> = token_args.iter().map(|s| s.as_str()).collect();
				args.extend(token_args_ref.iter());

				let out = CommandExecutor::execute("nix", &args, Logger::silent())?;
				let json: Value = serde_json::from_str(&out)?;
				json
					.get("path")
					.and_then(Value::as_str)
					.ok_or("nix flake archive did not return a source path")?
					.to_string()
			} else {
				let temp_dir = ShortLivedTempDir::new("source")?;
				crate::info!(
					logger,
					"Untracked source files detected; staging tracked and untracked non-ignored files."
				);
				snapshot_git_files(&local_path, &temp_dir.path)?;
				nix_store_add(&config::nix_cfg(), &temp_dir.path, &logger)?
			}
		} else {
			let temp_dir = ShortLivedTempDir::new("source")?;
			crate::info!(
				logger,
				"Local source is not a Git checkout; snapshotting checkout files to {}",
				temp_dir.path.display()
			);
			let mut rsync_args = vec!["-a".to_string(), "--delete".to_string()];
			for pattern in config::CHECKOUT_EXCLUDES {
				rsync_args.push(format!("--exclude={}", pattern));
			}
			rsync_args.push(format!("{}/", local_path.display()));
			rsync_args.push(format!("{}/", temp_dir.path.display()));

			let status = std::process::Command::new("rsync").args(&rsync_args).status()?;
			if !status.success() {
				return Err("Failed to snapshot plain checkout files.".into());
			}

			nix_store_add(&config::nix_cfg(), &temp_dir.path, &logger)?
		}
	} else {
		crate::info!(logger, "Materializing remote flake source {}...", resolved_flake);
		let mut args = vec!["flake", "archive", "--json", &resolved_flake];
		let token_args = config::nix_token_args();
		let token_args_ref: Vec<&str> = token_args.iter().map(|s| s.as_str()).collect();
		args.extend(token_args_ref.iter());

		let out = CommandExecutor::execute("nix", &args, Logger::silent())?;
		let json: Value = serde_json::from_str(&out)?;
		json
			.get("path")
			.and_then(Value::as_str)
			.ok_or("nix flake archive did not return a source path")?
			.to_string()
	};

	let mut secret_store_paths = std::collections::HashMap::new();
	for hostname in hostnames {
		if let Some(source) = config::resolve_host_sops_source(hostname) {
			crate::info!(logger, "SOPS for {}: {}", hostname, source.description);
			if !source.path.is_file() {
				return Err(
					format!("SOPS file for {} is not a valid file: {}", hostname, source.path.display())
						.into(),
				);
			}

			let secret_temp_dir = ShortLivedTempDir::new("secret")?;
			let staged_file = secret_temp_dir.path.join(format!("{}.yaml", hostname));
			fs::copy(&source.path, &staged_file)?;

			#[cfg(unix)]
			{
				use std::os::unix::fs::PermissionsExt;
				fs::set_permissions(&staged_file, fs::Permissions::from_mode(0o600))?;
			}

			let secret_store_path =
				nix_store_add(config::SECRET_INPUT_NAME, &secret_temp_dir.path, &logger)?;
			secret_store_paths.insert(hostname.clone(), secret_store_path);
		} else {
			crate::info!(
				logger,
				"SOPS: No secrets file found for {}. Proceeding without secrets.",
				hostname
			);
		}
	}

	let source_set = PreparedSourceSet { run_id, source_store_path, secret_store_paths };

	// Local GC roots registration
	register_local_gc_roots(&source_set, logger)?;

	Ok(source_set)
}

pub fn gc_roots_dir(run_id: &str) -> PathBuf {
	let state_home = std::env::var("XDG_STATE_HOME").map(PathBuf::from).unwrap_or_else(|_| {
		let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
		PathBuf::from(home).join(".local").join("state")
	});
	state_home.join(config::APP_NAME).join("gcroots").join(run_id)
}

pub fn store_input_destinations(
	ctx: &crate::context::RuntimeContext,
	home_manager: bool,
) -> Vec<String> {
	if crate::fleet::local::is_local_target(ctx) {
		return Vec::new();
	}

	let builder = crate::nix::NixBuilder::resolve(ctx);
	let target = crate::nix::build_commands::target_ssh(&builder);
	let mut destinations = if home_manager || ctx.system.contains("darwin") {
		vec![target]
	} else {
		match &builder.strategy {
			crate::nix::BuildStrategy::RemoteBuilder { ssh_connection }
				if !crate::nix::eval::is_current_host_ssh_target(ssh_connection) =>
			{
				vec![ssh_connection.clone()]
			}
			crate::nix::BuildStrategy::TargetNative => vec![target],
			_ => Vec::new(),
		}
	};
	destinations.sort();
	destinations.dedup();
	destinations
}

pub fn remote_builder_destination(ctx: &crate::context::RuntimeContext) -> Option<String> {
	match crate::nix::NixBuilder::resolve(ctx).strategy {
		crate::nix::BuildStrategy::RemoteBuilder { ssh_connection }
			if !crate::nix::eval::is_current_host_ssh_target(&ssh_connection) =>
		{
			Some(ssh_connection)
		}
		_ => None,
	}
}

fn register_local_gc_roots(
	source_set: &PreparedSourceSet,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	let roots_dir = gc_roots_dir(&source_set.run_id);
	fs::create_dir_all(&roots_dir)?;

	let marker_file = roots_dir.join("run.timestamp");
	let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
	fs::write(&marker_file, format!("{}", now))?;

	let source_root = roots_dir.join("source");
	let source_root_str = source_root.to_string_lossy().to_string();
	let args =
		["--realise", &source_set.source_store_path, "--add-root", &source_root_str, "--indirect"];
	CommandExecutor::execute("nix-store", &args, logger.clone())?;

	let mut seen_sanitized = std::collections::HashSet::new();
	for (hostname, secret_path) in &source_set.secret_store_paths {
		let sanitized = crate::workspace::local::sanitize_component(hostname);
		if !seen_sanitized.insert(sanitized.clone()) {
			return Err(format!(
				"Duplicate sanitized hostname '{}' detected in the operation, which conflicts with GC root isolation.",
				sanitized
			)
			.into());
		}
		let secret_root = roots_dir.join(format!("secret-{}", sanitized));
		let secret_root_str = secret_root.to_string_lossy().to_string();
		let args = ["--realise", secret_path, "--add-root", &secret_root_str, "--indirect"];
		CommandExecutor::execute("nix-store", &args, logger.clone())?;
	}

	Ok(())
}

pub fn replace_local_secret_gc_root(
	run_id: &str,
	hostname: &str,
	secret_path: &str,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	let roots_dir = gc_roots_dir(run_id);
	fs::create_dir_all(&roots_dir)?;
	let secret_root =
		roots_dir.join(format!("secret-{}", crate::workspace::local::sanitize_component(hostname)));
	let secret_root_str = secret_root.to_string_lossy().to_string();
	let args = ["--realise", secret_path, "--add-root", &secret_root_str, "--indirect"];
	CommandExecutor::execute("nix-store", &args, logger)?;
	Ok(())
}

fn clean_stale_remote_gc_roots(
	ssh_connection: &str,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	let command = format!(
		r#"
base="${{XDG_STATE_HOME:-$HOME/.local/state}}/{}/gcroots"
now="$(date +%s)"
max_age=604800
if [ -d "$base" ]; then
  for dir in "$base"/*; do
    [ -d "$dir" ] || continue
    timestamp=""
    [ -f "$dir/run.timestamp" ] && timestamp="$(cat "$dir/run.timestamp" 2>/dev/null || true)"
    case "$timestamp" in
      ''|*[!0-9]*) continue ;;
    esac
    if [ "$now" -gt "$((timestamp + max_age))" ]; then
      rm -rf -- "$dir"
    fi
  done
fi
"#,
		config::APP_NAME
	);
	CommandExecutor::execute_ssh(ssh_connection, &command, logger)?;
	Ok(())
}

pub fn create_remote_gc_roots(
	ssh_connection: &str,
	run_id: &str,
	source_path: &str,
	secret_paths: &[(String, String)],
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	clean_stale_remote_gc_roots(ssh_connection, logger.clone())?;
	let setup_script = format!(
		"mkdir -p \"${{XDG_STATE_HOME:-$HOME/.local/state}}/{}/gcroots/{}\"",
		config::APP_NAME,
		run_id
	);
	CommandExecutor::execute_ssh(ssh_connection, &setup_script, logger.clone())?;

	let mut cmd = format!(
		"roots_dir=\"${{XDG_STATE_HOME:-$HOME/.local/state}}/{}/gcroots/{}\" && \
		 echo \"$(date +%s)\" > \"$roots_dir/run.timestamp\" && \
		 nix-store --realise {} --add-root \"$roots_dir/source\" --indirect",
		config::APP_NAME,
		run_id,
		source_path
	);

	for (hostname, secret_path) in secret_paths {
		let sanitized = crate::workspace::local::sanitize_component(hostname);
		cmd.push_str(&format!(
			" && nix-store --realise {} --add-root \"$roots_dir/secret-{}\" --indirect",
			secret_path, sanitized
		));
	}

	CommandExecutor::execute_ssh(ssh_connection, &cmd, logger)?;
	Ok(())
}

pub fn transfer_and_root_secret(
	ssh_connection: &str,
	run_id: &str,
	hostname: &str,
	secret_path: &str,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	let store_uri = if ssh_connection.starts_with("ssh://") {
		ssh_connection.to_string()
	} else {
		format!("ssh://{}", ssh_connection)
	};
	crate::info!(logger, "Copying updated host secret to {}...", ssh_connection);
	CommandExecutor::execute("nix", &["copy", "--to", &store_uri, secret_path], logger.clone())?;

	let roots_dir =
		format!("${{XDG_STATE_HOME:-$HOME/.local/state}}/{}/gcroots/{}", config::APP_NAME, run_id);
	let root_name = format!("secret-{}", crate::workspace::local::sanitize_component(hostname));
	let command = format!(
		"mkdir -p \"{roots_dir}\" && nix-store --realise {secret_path} --add-root \"{roots_dir}/{root_name}\" --indirect"
	);
	CommandExecutor::execute_ssh(ssh_connection, &command, logger)?;
	Ok(())
}

pub fn transfer_and_root_source_set(
	ssh_connection: &str,
	source_set: &PreparedSourceSet,
	hostnames: &[String],
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	let mut secret_paths = Vec::new();
	let store_uri = if ssh_connection.starts_with("ssh://") {
		ssh_connection.to_string()
	} else {
		format!("ssh://{}", ssh_connection)
	};
	let mut copy_args = vec!["copy", "--to", &store_uri, &source_set.source_store_path];
	for host in hostnames {
		if let Some(path) = source_set.secret_store_paths.get(host) {
			copy_args.push(path);
			secret_paths.push((host.clone(), path.clone()));
		}
	}

	let run_copy = || -> Result<(), Box<dyn std::error::Error>> {
		crate::info!(logger, "Copying source set to remote builder/target {}...", ssh_connection);
		CommandExecutor::execute("nix", &copy_args, logger.clone())?;
		Ok(())
	};

	run_copy()?;

	if let Err(e) = create_remote_gc_roots(
		ssh_connection,
		&source_set.run_id,
		&source_set.source_store_path,
		&secret_paths,
		logger.clone(),
	) {
		crate::warn!(
			logger,
			"GC root creation failed on remote: {}. Retrying copy and root registration once...",
			e
		);
		run_copy()?;
		create_remote_gc_roots(
			ssh_connection,
			&source_set.run_id,
			&source_set.source_store_path,
			&secret_paths,
			logger.clone(),
		)?;
	}

	Ok(())
}

pub fn cleanup_gc_roots(run_id: &str, logger: Logger) -> Result<(), Box<dyn std::error::Error>> {
	let roots_dir = gc_roots_dir(run_id);
	if roots_dir.exists() {
		crate::info!(logger, "Cleaning up local GC roots for run {}", run_id);
		let _ = fs::remove_dir_all(&roots_dir);
	}
	Ok(())
}

pub fn cleanup_remote_gc_roots(
	ssh_connection: &str,
	run_id: &str,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	crate::info!(logger, "Cleaning up remote GC roots for run {} on {}", run_id, ssh_connection);
	let cmd = format!(
		"rm -rf \"${{XDG_STATE_HOME:-$HOME/.local/state}}/{}/gcroots/{}\"",
		config::APP_NAME,
		run_id
	);
	let _ = CommandExecutor::execute_ssh(ssh_connection, &cmd, logger);
	Ok(())
}

pub fn clean_stale_gc_roots(logger: Logger) {
	let state_home = std::env::var("XDG_STATE_HOME").map(PathBuf::from).unwrap_or_else(|_| {
		let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
		PathBuf::from(home).join(".local").join("state")
	});
	let gcroots_base = state_home.join(config::APP_NAME).join("gcroots");
	if !gcroots_base.exists() {
		return;
	}

	let Ok(entries) = fs::read_dir(&gcroots_base) else {
		return;
	};

	let seven_days = 7 * 24 * 60 * 60;
	let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();

	for entry in entries.flatten() {
		let path = entry.path();
		if path.is_dir() {
			let marker = path.join("run.timestamp");
			let mut is_stale = false;
			if marker.exists() {
				if fs::read_to_string(&marker)
					.ok()
					.and_then(|c| c.trim().parse::<u64>().ok())
					.filter(|&timestamp| now > timestamp + seven_days)
					.is_some()
				{
					is_stale = true;
				}
			} else if fs::metadata(&path)
				.ok()
				.and_then(|m| m.modified().ok())
				.and_then(|t| SystemTime::now().duration_since(t).ok())
				.filter(|duration| duration.as_secs() > seven_days)
				.is_some()
			{
				is_stale = true;
			}

			if is_stale {
				crate::info!(
					logger.clone(),
					"Cleaning up stale local GC root directory: {}",
					path.display()
				);
				let _ = fs::remove_dir_all(&path);
			}
		}
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn test_extract_local_path() {
		assert_eq!(config::local_flake_path("path:/foo/bar"), Some(PathBuf::from("/foo/bar")));
		assert_eq!(config::local_flake_path("git+file:///foo/bar"), Some(PathBuf::from("/foo/bar")));
		assert_eq!(config::local_flake_path("."), Some(PathBuf::from(".")));
	}

	#[test]
	fn test_is_local_flake() {
		assert!(config::is_local_flake("path:/foo/bar"));
		assert!(config::is_local_flake("git+file:///foo/bar"));
		assert!(config::is_local_flake("."));
		assert!(!config::is_local_flake("nixcfg"));
		assert!(!config::is_local_flake("github:lamtt77/lamt-nixconfig"));
		assert!(!config::is_local_flake("git+ssh://git@github.com/..."));
	}

	#[test]
	fn test_resolve_flake() {
		// github resolving
		let gh = config::resolve_flake(Some("github"));
		assert_eq!(gh, "github:lamtt77/lamt-nixconfig");

		// tea resolving
		let tea = config::resolve_flake(Some("tea"));
		assert_eq!(tea, "git+ssh://git@tea.lamhub.com/lamtt77/lamt-nixconfig");

		// fallback/explicit
		let explicit = config::resolve_flake(Some("github:owner/repo"));
		assert_eq!(explicit, "github:owner/repo");
	}

	#[test]
	fn snapshot_git_files_includes_untracked_non_ignored_files() {
		let source = ShortLivedTempDir::new("test-source").unwrap();
		let destination = ShortLivedTempDir::new("test-destination").unwrap();
		assert!(
			Command::new("git")
				.args(["init", "-q"])
				.current_dir(&source.path)
				.status()
				.unwrap()
				.success()
		);

		fs::write(source.path.join(".gitignore"), "ignored.txt\n").unwrap();
		fs::write(source.path.join("tracked.txt"), "tracked").unwrap();
		fs::write(source.path.join("untracked.txt"), "untracked").unwrap();
		fs::write(source.path.join("ignored.txt"), "ignored").unwrap();
		assert!(
			Command::new("git")
				.args(["add", ".gitignore", "tracked.txt"])
				.current_dir(&source.path)
				.status()
				.unwrap()
				.success()
		);

		snapshot_git_files(&source.path, &destination.path).unwrap();

		assert!(destination.path.join(".gitignore").is_file());
		assert!(destination.path.join("tracked.txt").is_file());
		assert!(destination.path.join("untracked.txt").is_file());
		assert!(!destination.path.join("ignored.txt").exists());
		assert!(!destination.path.join(".git").exists());
	}
}
