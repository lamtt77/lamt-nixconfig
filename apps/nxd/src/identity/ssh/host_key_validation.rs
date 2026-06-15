use super::host_key_mismatch::{HostKeyMismatch, resolve_host_key_mismatch};
use crate::context::RuntimeContext;
use crate::identity::sops::register_age_key_in_sops;
use crate::process::{CommandExecutor, Logger};
use std::fs;
use std::path::Path;

pub fn validate_and_sync_target_host_key(
	ctx: &RuntimeContext,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	ensure_wsl_distribution_awake(ctx, &logger);
	let is_deploy = crate::config::get_runtime_options().deploy_active;
	let target_user = if ctx.deployment.wsl.enable && is_deploy {
		&ctx.deployment.wsl.bootstrap_user
	} else if is_deploy {
		"root"
	} else {
		&ctx.username
	};
	let ssh_target = format!("{}@{}", target_user, ctx.target_ip);
	let secrets_repo = crate::config::get_secrets_repo();

	let local_key_file = secrets_repo.join("hosts").join(&ctx.hostname).join("ssh_host_ed25519_key");
	let local_pub_file = local_key_file.with_extension("pub");

	if !secrets_repo.exists() || !secrets_repo.join(".sops.yaml").exists() {
		return Ok(());
	}

	crate::info!(&logger, "Checking target host SSH key connection for {}...", ctx.hostname);
	let get_pubkey_cmd = "sudo cat /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null; echo '---HOSTNAME---'; hostname 2>/dev/null";

	let mut active_pub_key = None;
	let mut remote_hostname = None;
	for attempt in 1..=5 {
		let (key, host) = read_target_host_identity(&ssh_target, get_pubkey_cmd);
		if key.is_some() {
			active_pub_key = key;
			remote_hostname = host;
			break;
		}
		if attempt < 5 {
			std::thread::sleep(std::time::Duration::from_secs(1));
		}
	}
	validate_remote_hostname(ctx, remote_hostname.as_deref(), &logger)?;

	let local_pub_key = read_local_public_key(&local_pub_file)?;

	if local_pub_key.is_none() {
		let sync_params = LocalKeySyncParams {
			ctx,
			ssh_target: &ssh_target,
			secrets_repo: &secrets_repo,
			local_key_file: &local_key_file,
			local_pub_file: &local_pub_file,
			active_pub_key: active_pub_key.as_deref(),
			logger: logger.clone(),
		};
		sync_missing_local_key(sync_params)?;
		return Ok(());
	}

	let local_pub_key_val = local_pub_key.unwrap();

	if let Some(ref active_pub_key_val) = active_pub_key {
		if active_pub_key_val != &local_pub_key_val {
			resolve_host_key_mismatch(
				HostKeyMismatch {
					ctx,
					ssh_target: &ssh_target,
					secrets_repo: &secrets_repo,
					local_key_file: &local_key_file,
					local_pub_file: &local_pub_file,
					local_pub_key: &local_pub_key_val,
					active_pub_key: active_pub_key_val,
				},
				logger.clone(),
			)?;
		}
	} else {
		return Err(format!(
            "Target host '{}' ({}) is unreachable over SSH. Please check if the host is online and connected.",
            ctx.hostname, ctx.target_ip
        ).into());
	}

	Ok(())
}

fn read_target_host_identity(
	ssh_target: &str,
	get_pubkey_cmd: &str,
) -> (Option<String>, Option<String>) {
	match crate::remote::ssh::probe_stdout(ssh_target, get_pubkey_cmd, 3) {
		Some(stdout) => {
			let mut parts = stdout.split("---HOSTNAME---");
			let key_part = parts.next().unwrap_or("").trim();
			let hostname_part = parts.next().unwrap_or("").trim();

			let key = normalize_public_key(key_part);
			let resolved_key = if key.is_empty() { None } else { Some(key) };

			let resolved_hostname =
				if hostname_part.is_empty() { None } else { Some(hostname_part.to_string()) };

			(resolved_key, resolved_hostname)
		}
		None => (None, None),
	}
}

fn validate_remote_hostname(
	ctx: &RuntimeContext,
	remote_hostname: Option<&str>,
	logger: &Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	if let Some(actual_host) = remote_hostname
		&& actual_host != ctx.hostname
	{
		let is_deploy = crate::config::get_runtime_options().deploy_active;
		let generic_names = ["nixos", "installer", "nixos-installer"];
		if (is_deploy || ctx.deployment.wsl.enable) && generic_names.contains(&actual_host) {
			crate::info!(
				logger,
				"Allowing generic hostname '{}' for WSL or deployment target (target configuration hostname is '{}').",
				actual_host,
				ctx.hostname
			);
			return Ok(());
		}

		let is_forced = crate::config::get_runtime_options().force;
		if is_forced {
			crate::warn!(
				logger,
				"Target hostname mismatch (target is '{}', config is '{}'). Proceeding because --force is enabled.",
				actual_host,
				ctx.hostname
			);
			return Ok(());
		}

		return Err(format!(
                "Mismatched host safety trigger: Connected to target IP {}, which returned hostname '{}', but the configuration hostname is '{}'. Aborting to prevent configuration overwrite.",
                ctx.target_ip, actual_host, ctx.hostname
            ).into());
	}

	Ok(())
}

fn read_local_public_key(
	local_pub_file: &Path,
) -> Result<Option<String>, Box<dyn std::error::Error>> {
	if local_pub_file.exists() {
		let content = fs::read_to_string(local_pub_file)?;
		let key = normalize_public_key(&content);
		if key.is_empty() { Ok(None) } else { Ok(Some(key)) }
	} else {
		Ok(None)
	}
}

fn normalize_public_key(content: &str) -> String {
	content.split_whitespace().take(2).collect::<Vec<&str>>().join(" ")
}

struct LocalKeySyncParams<'a> {
	ctx: &'a RuntimeContext,
	ssh_target: &'a str,
	secrets_repo: &'a Path,
	local_key_file: &'a Path,
	local_pub_file: &'a Path,
	active_pub_key: Option<&'a str>,
	logger: Logger,
}

fn sync_missing_local_key(
	params: LocalKeySyncParams<'_>,
) -> Result<(), Box<dyn std::error::Error>> {
	let LocalKeySyncParams {
		ctx,
		ssh_target,
		secrets_repo,
		local_key_file,
		local_pub_file,
		active_pub_key,
		logger,
	} = params;
	if let Some(active_key) = active_pub_key {
		crate::info!(
			&logger,
			"Secrets repo is missing host key for '{}', but target host has an active key.",
			ctx.hostname
		);
		match resolve_missing_local_key_choice(logger.clone())? {
			MissingLocalKeyChoice::ImportTarget => {
				import_target_host_key(
					ctx,
					ssh_target,
					secrets_repo,
					local_key_file,
					local_pub_file,
					active_key,
					logger.clone(),
				)?;
			}
			MissingLocalKeyChoice::GenerateFresh => {
				generate_fresh_local_key(ctx, secrets_repo, local_key_file, local_pub_file, logger)?;
			}
			MissingLocalKeyChoice::Abort => {
				return Err(
					format!(
						"Aborted because secrets repo is missing host key material for '{}'.",
						ctx.hostname
					)
					.into(),
				);
			}
		}
	} else {
		generate_fresh_local_key(ctx, secrets_repo, local_key_file, local_pub_file, logger)?;
	}

	Ok(())
}

enum MissingLocalKeyChoice {
	ImportTarget,
	GenerateFresh,
	Abort,
}

fn resolve_missing_local_key_choice(
	logger: Logger,
) -> Result<MissingLocalKeyChoice, Box<dyn std::error::Error>> {
	let runtime_options = crate::config::get_runtime_options();
	if runtime_options.force {
		if runtime_options.update_secrets_key {
			crate::info!(
				&logger,
				"Non-interactive mode active. Importing target host key because UPDATE_SECRETS_KEY=yes."
			);
			return Ok(MissingLocalKeyChoice::ImportTarget);
		}
		return Err(
            "Secrets repo is missing host key material. Re-run interactively or set UPDATE_SECRETS_KEY=yes with --force to import the target key."
                .into(),
        );
	}

	crate::info!(&logger, "How would you like to resolve the missing local host key?");
	crate::info!(&logger, "  1) Import active target key into secrets repo (Target -> Secrets)");
	crate::info!(&logger, "  2) Generate fresh local key for future staging");
	crate::info!(&logger, "  3) Abort");

	print!("  Choice [1/2/3]: ");
	use std::io::Write;
	let _ = std::io::stdout().flush();
	let mut input = String::new();
	let mut choice = "3";
	if std::io::stdin().read_line(&mut input).is_ok() {
		let trimmed = input.trim();
		if trimmed == "1" || trimmed == "2" || trimmed == "3" {
			choice = trimmed;
		}
	}

	Ok(match choice {
		"1" => MissingLocalKeyChoice::ImportTarget,
		"2" => MissingLocalKeyChoice::GenerateFresh,
		_ => MissingLocalKeyChoice::Abort,
	})
}

fn import_target_host_key(
	ctx: &RuntimeContext,
	ssh_target: &str,
	secrets_repo: &Path,
	local_key_file: &Path,
	local_pub_file: &Path,
	active_key: &str,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	ensure_wsl_distribution_awake(ctx, &logger);
	crate::info!(&logger, "Importing active host keys from target...");

	let private_key = CommandExecutor::execute_ssh(
		ssh_target,
		"sudo cat /etc/ssh/ssh_host_ed25519_key",
		Logger::silent(),
	)?;
	write_local_host_keys(
		local_key_file,
		local_pub_file,
		&private_key,
		&format!("{}\n", active_key),
	)?;

	register_age_key_in_sops(&ctx.hostname, active_key, secrets_repo, logger)?;
	Ok(())
}

fn generate_fresh_local_key(
	ctx: &RuntimeContext,
	secrets_repo: &Path,
	local_key_file: &Path,
	local_pub_file: &Path,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	crate::info!(
		&logger,
		"SSH host key for '{}' is missing. Generating fresh Ed25519 key locally...",
		ctx.hostname
	);
	let key_dir = local_key_file.parent().unwrap();
	fs::create_dir_all(key_dir)?;

	let key_file_str = local_key_file.to_string_lossy().to_string();
	let gen_args = ["-t", "ed25519", "-f", &key_file_str, "-N", "", "-q"];
	CommandExecutor::execute("ssh-keygen", &gen_args, logger.clone())?;

	let pub_key_content = fs::read_to_string(local_pub_file)?;
	register_age_key_in_sops(&ctx.hostname, &pub_key_content, secrets_repo, logger)?;
	Ok(())
}

fn write_local_host_keys(
	local_key_file: &Path,
	local_pub_file: &Path,
	private_key: &str,
	public_key: &str,
) -> Result<(), Box<dyn std::error::Error>> {
	let key_dir = local_key_file.parent().unwrap();
	fs::create_dir_all(key_dir)?;
	fs::write(local_key_file, private_key)?;
	fs::write(local_pub_file, public_key)?;

	#[cfg(unix)]
	{
		use std::os::unix::fs::PermissionsExt;
		fs::set_permissions(local_key_file, fs::Permissions::from_mode(0o600))?;
		fs::set_permissions(local_pub_file, fs::Permissions::from_mode(0o644))?;
	}

	Ok(())
}

fn ensure_wsl_distribution_awake(ctx: &RuntimeContext, logger: &Logger) {
	if ctx.deployment.wsl.enable && !ctx.deployment.ssh_proxy_jump.is_empty() {
		crate::info!(logger, "Waking up WSL distribution '{}'...", ctx.deployment.wsl.distribution);
		let wakeup_cmd =
			format!("wsl.exe -d {} --exec /bin/sh -c true", ctx.deployment.wsl.distribution);
		let windows_connection =
			format!("{}@{}", ctx.deployment.wsl.windows_user, ctx.deployment.wsl.windows_host);
		let _ = CommandExecutor::execute_ssh(&windows_connection, &wakeup_cmd, Logger::silent());
	}
}
