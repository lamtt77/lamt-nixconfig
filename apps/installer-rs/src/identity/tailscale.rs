use super::IdentityService;
use crate::context::RuntimeContext;
use crate::process::CommandExecutor;
use crate::process::LogTarget;
use dialoguer::Confirm;
use serde::Deserialize;
use std::env;
use std::path::Path;
use std::sync::{Arc, Mutex};

pub struct TailscaleService {
    _log_target: Arc<Mutex<LogTarget>>,
}

impl TailscaleService {
    pub fn new(log_target: Arc<Mutex<LogTarget>>) -> Self {
        Self { _log_target: log_target }
    }

    /// Resolves the secrets repository absolute path.
    pub fn get_secrets_repo(&self) -> std::path::PathBuf {
        crate::config::get_secrets_repo()
    }

    fn get_tailscale_preauth_key(&self, secrets_file: &Path) -> Option<String> {
        if !secrets_file.exists() {
            return None;
        }
        let output = std::process::Command::new("sops")
            .args(&["-d", "--extract", "[\"tailscale_preauth_key\"]", &secrets_file.to_string_lossy()])
            .output();
        if let Ok(out) = output {
            if out.status.success() {
                let key = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if !key.is_empty() && key != "null" {
                    return Some(key.trim_matches('"').to_string());
                }
            }
        }
        None
    }

    fn set_tailscale_preauth_key(&self, secrets_file: &Path, new_key: &str) -> Result<(), Box<dyn std::error::Error>> {
        let set_expr = format!("[\"tailscale_preauth_key\"] \"{}\"", new_key);
        let output = std::process::Command::new("sops")
            .args(&["--set", &set_expr, &secrets_file.to_string_lossy()])
            .output()?;
        if !output.status.success() {
            let err_msg = String::from_utf8_lossy(&output.stderr);
            return Err(format!("Failed to update tailscale_preauth_key in SOPS file: {}", err_msg).into());
        }
        Ok(())
    }
}

#[derive(Deserialize, Debug)]
struct HeadscaleUser {
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
    expiration: Option<HeadscaleTimestamp>,
}

impl IdentityService for TailscaleService {
    fn id(&self) -> &str {
        "tailscale"
    }

    fn pre_install(&self, ctx: &RuntimeContext) -> Result<(), Box<dyn std::error::Error>> {
        let secrets_repo = self.get_secrets_repo();
        let host_secret_file = secrets_repo.join("sops").join(format!("{}.yaml", ctx.hostname));

        if !host_secret_file.exists() {
            return Ok(());
        }

        let existing_key = self.get_tailscale_preauth_key(&host_secret_file);
        if existing_key.is_none() {
            // Host does not use tailscale pre-auth keys. Skip.
            return Ok(());
        }
        let existing_key = existing_key.unwrap();

        let avon_ip = env::var("HEADSCALE_COORDINATOR_IP").unwrap_or_else(|_| "100.64.0.1".to_string());
        let avon_user = env::var("HEADSCALE_COORDINATOR_USER").unwrap_or_else(|_| "nixos".to_string());
        let avon_ssh = format!("{}@{}", avon_user, avon_ip);

        // Ping check to avoid long SSH timeouts if coordinator is unreachable
        println!("Checking Headscale coordinator status at {}...", avon_ip);
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
            println!("Warning: Headscale coordinator ({}) is unreachable. Skipping pre-auth key validation.", avon_ip);
            return Ok(());
        }

        println!("Validating Tailscale pre-auth key for {} on Headscale...", ctx.hostname);
        
        // Fetch all users
        let users_json = CommandExecutor::execute(
            "ssh",
            &[
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "LogLevel=ERROR",
                "-o", "ConnectTimeout=3",
                "-o", "PasswordAuthentication=no",
                &avon_ssh,
                "sudo headscale users list --output json",
            ],
            Arc::new(Mutex::new(LogTarget::Silent)),
        )?;

        let users: Vec<HeadscaleUser> = match serde_json::from_str(&users_json) {
            Ok(u) => u,
            Err(e) => {
                println!("Error parsing Headscale users JSON: {:?}", e);
                println!("Raw JSON was:\n{}", users_json);
                Vec::new()
            }
        };
        let mut found_username = String::new();
        let mut key_invalid = false;
        let now_seconds = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;

        // Scan keys for all users to verify validity of the existing key
        for user in &users {
            let user_id_str = match &user.id {
                serde_json::Value::Number(n) => n.to_string(),
                serde_json::Value::String(s) => s.clone(),
                _ => String::new(),
            };
            let list_cmd = format!("sudo headscale preauthkeys list -u {} --output json", user_id_str);
            if let Ok(keys_json) = CommandExecutor::execute(
                "ssh",
                &[
                    "-o", "StrictHostKeyChecking=no",
                    "-o", "UserKnownHostsFile=/dev/null",
                    "-o", "LogLevel=ERROR",
                    "-o", "ConnectTimeout=3",
                    "-o", "PasswordAuthentication=no",
                    &avon_ssh,
                    &list_cmd,
                ],
                Arc::new(Mutex::new(LogTarget::Silent)),
            ) {
                let keys: Vec<HeadscalePreauthKey> = match serde_json::from_str(&keys_json) {
                    Ok(k) => k,
                    Err(e) => {
                        println!("Error parsing Headscale keys JSON: {:?}", e);
                        println!("Raw JSON was:\n{}", keys_json);
                        Vec::new()
                    }
                };
                if let Some(key_match) = keys.into_iter().find(|k| k.key == existing_key) {
                    found_username = user.name.clone();
                    
                    if let Some(exp) = key_match.expiration {
                        let exp_seconds = match &exp.seconds {
                            serde_json::Value::Number(n) => n.as_i64().unwrap_or(0),
                            serde_json::Value::String(s) => s.parse::<i64>().unwrap_or(0),
                            _ => 0,
                        };
                        if exp_seconds < now_seconds {
                            println!("Warning: Tailscale pre-auth key is EXPIRED for user '{}'.", user.name);
                            key_invalid = true;
                        }
                    }
                    break;
                }
            }
        }

        if found_username.is_empty() {
            println!("Warning: Tailscale pre-auth key not found or revoked on Headscale coordinator.");
            key_invalid = true;
        } else if !ctx.deployment.tailscale_namespace.is_empty() && found_username != ctx.deployment.tailscale_namespace {
            println!(
                "Warning: Tailscale pre-auth key is registered under namespace '{}', but target namespace is '{}'. Key is mismatched.",
                found_username, ctx.deployment.tailscale_namespace
            );
            key_invalid = true;
        }

        if key_invalid {
            let cli_force = env::var("CLI_FORCE").unwrap_or_default() == "yes";
            let mut regenerate = false;

            if cli_force {
                println!("Tailscale: Force mode is active. Auto-confirming key regeneration.");
                regenerate = true;
            } else {
                if Confirm::new()
                    .with_prompt("Would you like to automatically generate a new 1-year (365d) reusable pre-auth key on Headscale?")
                    .default(false)
                    .interact()
                    .unwrap_or(false)
                {
                    regenerate = true;
                }
            }

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
                    let namespaces = vec!["lamt", "cloud", "fcm"];
                    let default_idx = namespaces.iter()
                        .position(|&ns| ns == target_namespace)
                        .unwrap_or(0);

                    println!("Select Headscale user namespace for the pre-auth key:");
                    if let Ok(selection) = dialoguer::Select::new()
                        .items(&namespaces)
                        .default(default_idx)
                        .interact()
                    {
                        target_namespace = namespaces[selection].to_string();
                    }
                }

                // Resolve numeric/string ID for the chosen namespace (username)
                let user_id = users.iter()
                    .find(|u| u.name == target_namespace)
                    .map(|u| match &u.id {
                        serde_json::Value::Number(n) => n.to_string(),
                        serde_json::Value::String(s) => s.clone(),
                        _ => String::new(),
                    })
                    .unwrap_or_default();

                if user_id.is_empty() {
                    return Err(format!("User namespace '{}' not found in Headscale coordinator.", target_namespace).into());
                }

                println!("Generating new pre-auth key on Headscale for user '{}'...", target_namespace);
                let create_cmd = format!("sudo headscale preauthkeys create -u {} --reusable --expiration 365d", user_id);
                let new_key = CommandExecutor::execute(
                    "ssh",
                    &[
                        "-o", "StrictHostKeyChecking=no",
                        "-o", "UserKnownHostsFile=/dev/null",
                        "-o", "LogLevel=ERROR",
                        "-o", "ConnectTimeout=10",
                        "-o", "PasswordAuthentication=no",
                        &avon_ssh,
                        &create_cmd,
                    ],
                    Arc::new(Mutex::new(LogTarget::Silent)),
                )?;
                let new_key = new_key.trim().to_string();

                if new_key.is_empty() || new_key.contains("Error") {
                    return Err("Failed to generate pre-auth key on Headscale coordinator. Check coordinator server logs.".into());
                }

                self.set_tailscale_preauth_key(&host_secret_file, &new_key)?;
                let staged_secrets_file = Path::new("secrets/sops").join(format!("{}.yaml", ctx.hostname));
                if staged_secrets_file.exists() {
                    self.set_tailscale_preauth_key(&staged_secrets_file, &new_key)?;
                }
                println!("Successfully updated tailscale_preauth_key in secrets.");
            } else {
                println!("Warning: Skipping pre-auth key update. Declarative Tailscale registration may fail.");
            }
        } else {
            println!("Tailscale pre-auth key is valid (expires after current local time).");
        }

        Ok(())
    }

    fn post_install(&self, _ctx: &RuntimeContext, _mount_path: &Path) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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

