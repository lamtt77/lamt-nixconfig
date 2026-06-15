use super::IdentityService;
use crate::context::RuntimeContext;
use crate::process::CommandExecutor;
use crate::process::Logger;
use serde::Deserialize;
use std::env;
use std::path::Path;

pub struct TailscaleService {
	_logger: Logger,
}

impl TailscaleService {
	pub fn new(logger: Logger) -> Self {
		Self { _logger: logger }
	}

	/// Resolves the secrets repository absolute path.
	pub fn get_secrets_repo(&self) -> std::path::PathBuf {
		crate::config::get_secrets_repo()
	}

	fn get_tailscale_preauth_key(&self, secrets_file: &Path, key_name: &str) -> Option<String> {
		if !secrets_file.exists() {
			return None;
		}
		let extract_expr = format!("[\"{}\"]", key_name);
		let output = std::process::Command::new("sops")
			.args(["-d", "--extract", &extract_expr, &secrets_file.to_string_lossy()])
			.output();
		if let Ok(out) = output
			&& out.status.success()
		{
			let key = String::from_utf8_lossy(&out.stdout).trim().to_string();
			if !key.is_empty() && key != "null" {
				return Some(key.trim_matches('"').to_string());
			}
		}
		None
	}

	fn set_tailscale_preauth_key(
		&self,
		secrets_file: &Path,
		key_name: &str,
		new_key: &str,
	) -> Result<(), Box<dyn std::error::Error>> {
		let set_expr = format!("[\"{}\"] \"{}\"", key_name, new_key);
		let output = std::process::Command::new("sops")
			.args(["--set", &set_expr, &secrets_file.to_string_lossy()])
			.output()?;
		if !output.status.success() {
			let err_msg = String::from_utf8_lossy(&output.stderr);
			return Err(
				format!("Failed to update tailscale_preauth_key in SOPS file: {}", err_msg).into(),
			);
		}
		Ok(())
	}
}

#[derive(Deserialize, Debug)]
struct HeadscaleUser {
	#[allow(dead_code)]
	id: serde_json::Value,
	name: String,
}

#[derive(Deserialize, Debug)]
struct HeadscaleTimestamp {
	seconds: serde_json::Value,
}

#[derive(Deserialize, Debug)]
struct HeadscalePreauthKey {
	key: String,
	user: Option<HeadscaleUser>,
	expiration: Option<HeadscaleTimestamp>,
}

fn declared_auth_key(features: &[serde_json::Value]) -> Option<String> {
	features.iter().find_map(|feature| {
		let feature = feature.as_object()?;
		let module = feature.get("module").or_else(|| feature.get("name"))?.as_str()?;
		if !module.contains("services/tailscale.nix") {
			return None;
		}

		feature.get("args")?.get("authKey")?.as_str().map(str::to_owned)
	})
}

impl IdentityService for TailscaleService {
	fn id(&self) -> &str {
		"tailscale"
	}

	fn pre_install(&self, ctx: &RuntimeContext) -> Result<(), Box<dyn std::error::Error>> {
		let Some(key_name) = declared_auth_key(&ctx.features) else {
			// Pre-auth provisioning is opt-in through the feature metadata.
			return Ok(());
		};

		let Some(source) = crate::config::resolve_host_sops_source(&ctx.hostname) else {
			return Ok(());
		};
		let host_secret_file = source.path;

		let existing_key =
			self.get_tailscale_preauth_key(&host_secret_file, &key_name).unwrap_or_default();

		let avon_ip = env::var("HEADSCALE_COORDINATOR_IP").unwrap_or_else(|_| "100.64.0.1".to_string());
		let avon_user = env::var("HEADSCALE_COORDINATOR_USER").unwrap_or_else(|_| "nixos".to_string());
		let avon_ssh = format!("{}@{}", avon_user, avon_ip);

		// Ping check to avoid long SSH timeouts if coordinator is unreachable
		crate::info!(&self._logger, "Checking Headscale coordinator status at {}...", avon_ip);
		let ping_args = if cfg!(target_os = "macos") {
			vec!["-c", "1", "-t", "2", &avon_ip]
		} else {
			vec!["-c", "1", "-W", "2", &avon_ip]
		};
		let ping_success = std::process::Command::new("ping")
			.args(&ping_args)
			.status()
			.map(|s| s.success())
			.unwrap_or(false);

		if !ping_success {
			crate::warn!(
				&self._logger,
				"Headscale coordinator ({}) is unreachable. Skipping pre-auth key validation.",
				avon_ip
			);
			return Ok(());
		}

		// Automatically check for and delete stale node with the same hostname
		let list_nodes_cmd = "sudo headscale nodes list --output json".to_string();
		let mut list_nodes_args = crate::remote::ssh::SshOptions::probe(3).ssh_args_before_target();
		list_nodes_args.push(avon_ssh.to_string());
		list_nodes_args.push(list_nodes_cmd);
		let list_nodes_args_str: Vec<&str> = list_nodes_args.iter().map(|s| s.as_str()).collect();

		if let Ok(nodes_json) = CommandExecutor::execute("ssh", &list_nodes_args_str, Logger::silent())
		{
			#[derive(Deserialize, Debug)]
			struct HeadscaleNode {
				id: u64,
				name: String,
				online: bool,
			}

			if let Ok(nodes) = serde_json::from_str::<Vec<HeadscaleNode>>(&nodes_json)
				&& let Some(stale_node) = nodes.into_iter().find(|n| n.name == ctx.hostname)
			{
				let is_deploy = crate::config::get_runtime_options().deploy_active;
				if is_deploy || !stale_node.online {
					crate::info!(
						&self._logger,
						"Stale Tailscale node '{}' (ID {}) detected on Headscale. Deleting to prevent naming conflict...",
						stale_node.name,
						stale_node.id
					);
					let delete_cmd = format!("sudo headscale nodes delete -i {} --force", stale_node.id);
					let mut delete_args = crate::remote::ssh::SshOptions::probe(5).ssh_args_before_target();
					delete_args.push(avon_ssh.to_string());
					delete_args.push(delete_cmd);
					let delete_args_str: Vec<&str> = delete_args.iter().map(|s| s.as_str()).collect();
					if let Err(e) = CommandExecutor::execute("ssh", &delete_args_str, Logger::silent()) {
						crate::warn!(&self._logger, "Failed to delete stale node: {:?}", e);
					}
				}
			}
		}

		crate::info!(
			&self._logger,
			"Validating Tailscale pre-auth key for {} on Headscale...",
			ctx.hostname
		);

		let mut found_username = String::new();
		let mut key_invalid = false;
		let now_seconds = std::time::SystemTime::now()
			.duration_since(std::time::UNIX_EPOCH)
			.unwrap_or_default()
			.as_secs() as i64;

		// Fetch all preauth keys globally
		let list_cmd = "sudo headscale preauthkeys list --output json".to_string();
		let mut list_args = crate::remote::ssh::SshOptions::probe(3).ssh_args_before_target();
		list_args.push(avon_ssh.to_string());
		list_args.push(list_cmd);
		let list_args_str: Vec<&str> = list_args.iter().map(|s| s.as_str()).collect();

		if let Ok(keys_json) = CommandExecutor::execute("ssh", &list_args_str, Logger::silent()) {
			let keys: Vec<HeadscalePreauthKey> = match serde_json::from_str(&keys_json) {
				Ok(k) => k,
				Err(e) => {
					crate::error!(&self._logger, "Error parsing Headscale keys JSON: {:?}", e);
					crate::info!(&self._logger, "Raw JSON was:\n{}", keys_json);
					Vec::new()
				}
			};

			if let Some(key_match) = keys.into_iter().find(|k| {
				if k.key.ends_with("***") {
					let prefix = k.key.trim_end_matches("***");
					existing_key.starts_with(prefix)
				} else {
					k.key == existing_key
				}
			}) {
				// In Headscale 0.28, the user is nested inside the key object
				if let Some(user_name) = key_match.user.as_ref().map(|u| u.name.clone()) {
					found_username = user_name;
				} else {
					// Fallback to legacy structure matching if needed, though 0.28+ provides it directly
					found_username = "unknown".to_string();
				}

				if let Some(exp) = key_match.expiration {
					let exp_seconds = match &exp.seconds {
						serde_json::Value::Number(n) => n.as_i64().unwrap_or(0),
						serde_json::Value::String(s) => s.parse::<i64>().unwrap_or(0),
						_ => 0,
					};
					if exp_seconds > 0 && exp_seconds < now_seconds {
						crate::warn!(
							&self._logger,
							"Tailscale pre-auth key is EXPIRED for user '{}'.",
							found_username
						);
						key_invalid = true;
					}
				}
			}
		}

		if found_username.is_empty() {
			crate::warn!(
				&self._logger,
				"Tailscale pre-auth key not found or revoked on Headscale coordinator."
			);
			key_invalid = true;
		} else if !ctx.deployment.tailscale_namespace.is_empty()
			&& found_username != ctx.deployment.tailscale_namespace
		{
			crate::warn!(
				&self._logger,
				"Tailscale pre-auth key is registered under namespace '{}', but target namespace is '{}'. Key is mismatched.",
				found_username,
				ctx.deployment.tailscale_namespace
			);
			key_invalid = true;
		}

		if key_invalid {
			let cli_force = crate::config::get_runtime_options().force;
			let regenerate = crate::workflow::confirm::confirm_action(
                "Would you like to automatically generate a new 1-year (365d) reusable pre-auth key on Headscale?",
                Some("Tailscale: Force mode is active. Auto-confirming key regeneration."),
                cli_force,
            ).unwrap_or(false);

			if regenerate {
				let mut target_namespace = if !ctx.deployment.tailscale_namespace.is_empty() {
					ctx.deployment.tailscale_namespace.clone()
				} else if !found_username.is_empty() {
					found_username
				} else {
					env::var("DEFAULT_TAILSCALE_NAMESPACE").unwrap_or_else(|_| "lamt".to_string())
				};

				// Select user namespace if not in force/headless mode
				if !cli_force {
					crate::info!(&self._logger, "Select Headscale user namespace for the pre-auth key:");
					crate::info!(&self._logger, "  1) lamt");
					crate::info!(&self._logger, "  2) cloud");
					crate::info!(&self._logger, "  3) fcm");

					print!("  Choice [1/2/3]: ");
					use std::io::Write;
					let _ = std::io::stdout().flush();
					let mut input = String::new();
					if std::io::stdin().read_line(&mut input).is_ok() {
						let trimmed = input.trim();
						match trimmed {
							"1" => target_namespace = "lamt".to_string(),
							"2" => target_namespace = "cloud".to_string(),
							"3" => target_namespace = "fcm".to_string(),
							_ => {}
						}
					}
				}

				// Resolve username to user ID via coordinator query
				let user_list_cmd = "sudo headscale user list --output json".to_string();
				let mut user_list_args = crate::remote::ssh::SshOptions::probe(5).ssh_args_before_target();
				user_list_args.push(avon_ssh.to_string());
				user_list_args.push(user_list_cmd);
				let user_list_args_str: Vec<&str> = user_list_args.iter().map(|s| s.as_str()).collect();

				let mut target_user_id = target_namespace.clone();
				if let Ok(users_json) =
					CommandExecutor::execute("ssh", &user_list_args_str, Logger::silent())
					&& let Ok(users) = serde_json::from_str::<Vec<HeadscaleUser>>(&users_json)
					&& let Some(user) = users.into_iter().find(|u| u.name == target_namespace)
				{
					target_user_id = match &user.id {
						serde_json::Value::Number(n) => n.to_string(),
						serde_json::Value::String(s) => s.clone(),
						_ => target_namespace.clone(),
					};
					crate::info!(
						&self._logger,
						"Resolved Headscale username '{}' to ID '{}'",
						target_namespace,
						target_user_id
					);
				}

				crate::info!(
					&self._logger,
					"Generating new pre-auth key on Headscale for user '{}' (ID '{}')...",
					target_namespace,
					target_user_id
				);
				let create_cmd = format!(
					"sudo headscale preauthkeys create --user {} --reusable --expiration 365d",
					target_user_id
				);
				let mut create_args = crate::remote::ssh::SshOptions::probe(10).ssh_args_before_target();
				create_args.push(avon_ssh.to_string());
				create_args.push(create_cmd.clone());
				let create_args_str: Vec<&str> = create_args.iter().map(|s| s.as_str()).collect();
				let new_key = CommandExecutor::execute("ssh", &create_args_str, Logger::silent())?;
				let new_key = new_key.trim().to_string();

				if new_key.is_empty() || new_key.contains("Error") {
					return Err("Failed to generate pre-auth key on Headscale coordinator. Check coordinator server logs.".into());
				}

				self.set_tailscale_preauth_key(&host_secret_file, &key_name, &new_key)?;
				let staged_secrets_file = Path::new("secrets/sops").join(format!("{}.yaml", ctx.hostname));
				if staged_secrets_file.exists() {
					self.set_tailscale_preauth_key(&staged_secrets_file, &key_name, &new_key)?;
				}
				crate::info!(&self._logger, "Successfully updated tailscale_preauth_key in secrets.");
			} else {
				crate::warn!(
					&self._logger,
					"Skipping pre-auth key update. Declarative Tailscale registration may fail."
				);
			}
		} else {
			crate::info!(
				&self._logger,
				"Tailscale pre-auth key is valid (expires after current local time)."
			);
		}

		Ok(())
	}

	fn post_install(
		&self,
		_ctx: &RuntimeContext,
		_mount_path: &Path,
	) -> Result<(), Box<dyn std::error::Error>> {
		Ok(())
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn declared_auth_key_requires_explicit_feature_argument() {
		let path_only = serde_json::json!("/nix/store/source/modules/os/feat/services/tailscale.nix");
		let without_auth_key = serde_json::json!({
			"module": "/nix/store/source/modules/os/feat/services/tailscale.nix",
			"args": {}
		});
		let with_auth_key = serde_json::json!({
			"module": "/nix/store/source/modules/os/feat/services/tailscale.nix",
			"args": {
				"authKey": "custom_preauth_key"
			}
		});

		assert_eq!(declared_auth_key(&[path_only, without_auth_key]), None);
		assert_eq!(declared_auth_key(&[with_auth_key]), Some("custom_preauth_key".to_string()));
	}

	#[test]
	fn test_deserialize_users() {
		let json = r#"
[
	{
		"id": 1,
		"name": "lamt",
		"created_at": {
			"seconds": 1779974185,
			"nanos": 703963153
		}
	},
	{
		"id": 2,
		"name": "cloud",
		"created_at": {
			"seconds": 1779974185,
			"nanos": 736461459
		}
	}
]
        "#;
		let users: Result<Vec<HeadscaleUser>, _> = serde_json::from_str(json);
		assert!(users.is_ok(), "Failed to parse: {:?}", users.err());
		let users = users.unwrap();
		assert_eq!(users.len(), 2);
		assert_eq!(users[0].name, "lamt");
	}

	#[test]
	fn test_deserialize_keys() {
		let json = r#"
[
	{
		"user": {
			"id": 1,
			"name": "lamt",
			"created_at": {
				"seconds": 1779974185,
				"nanos": 703963153
			}
		},
		"id": 6,
		"key": "mock-preauth-key-value-1111111111111111",
		"reusable": true,
		"expiration": {
			"seconds": 1811641935,
			"nanos": 919877820
		},
		"created_at": {
			"seconds": 1780105935,
			"nanos": 921794693
		}
	}
]
        "#;
		let keys: Result<Vec<HeadscalePreauthKey>, _> = serde_json::from_str(json);
		assert!(keys.is_ok(), "Failed to parse keys: {:?}", keys.err());
		let keys = keys.unwrap();
		assert_eq!(keys.len(), 1);
		assert_eq!(keys[0].key, "mock-preauth-key-value-1111111111111111");
		let exp = keys[0].expiration.as_ref().unwrap();
		assert_eq!(exp.seconds.as_i64().unwrap(), 1811641935);
	}
}
