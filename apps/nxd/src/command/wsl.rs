use crate::context::load_context_from_spec;
use crate::process::Logger;
use crate::providers::wsl::WslProvider;
use std::path::Path;

pub fn execute_bootstrap_ssh(
	target: &str,
	public_key: Option<&Path>,
) -> Result<(), Box<dyn std::error::Error>> {
	let ctx = load_context_from_spec(target)?;
	if !ctx.deployment.wsl.enable {
		return Err(format!("Target '{}' is not configured as a WSL provider", ctx.hostname).into());
	}

	let (public_key, key_source) = match public_key {
		Some(path) => {
			let key = std::fs::read_to_string(path)
				.map_err(|error| format!("Failed to read public key '{}': {}", path.display(), error))?;
			(key, path.display().to_string())
		}
		None => (
			crate::config::ssh_auth_key(),
			"defines.nix: mySshAuthKey (the minimal-wsl authorized key)".to_string(),
		),
	};
	let public_key = validate_public_key(&public_key)?;

	println!(
		"Bootstrapping Windows OpenSSH access for {}@{} using {}.",
		ctx.deployment.wsl.windows_user, ctx.deployment.wsl.windows_host, key_source
	);
	println!("Enter the Windows account password when SSH prompts.");

	WslProvider::new(&ctx, Logger::terminal()).bootstrap_ssh(public_key)?;
	println!("Windows OpenSSH public-key access verified.");
	Ok(())
}

fn validate_public_key(value: &str) -> Result<&str, Box<dyn std::error::Error>> {
	let value = value.trim();
	if value.contains(['\r', '\n']) {
		return Err("SSH public key file must contain exactly one key".into());
	}
	let key_type = value.split_whitespace().next().unwrap_or_default();
	if !matches!(
		key_type,
		"ssh-ed25519"
			| "ssh-rsa"
			| "ecdsa-sha2-nistp256"
			| "ecdsa-sha2-nistp384"
			| "ecdsa-sha2-nistp521"
			| "sk-ssh-ed25519@openssh.com"
			| "sk-ecdsa-sha2-nistp256@openssh.com"
	) || value.split_whitespace().nth(1).is_none()
	{
		return Err("File does not contain a supported OpenSSH public key".into());
	}
	Ok(value)
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn validates_single_public_key() {
		assert_eq!(
			validate_public_key("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest user@example").unwrap(),
			"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest user@example"
		);
	}

	#[test]
	fn rejects_private_or_multiline_key_material() {
		assert!(validate_public_key("-----BEGIN OPENSSH PRIVATE KEY-----").is_err());
		assert!(validate_public_key("ssh-ed25519 AAAA\nssh-ed25519 BBBB").is_err());
	}
}
