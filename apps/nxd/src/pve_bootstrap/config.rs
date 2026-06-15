use serde::Deserialize;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
pub struct Manifest {
	pub schema_version: String,
	pub target_name: String,
	pub expected_hostname: String,
	pub first_boot_protocol_version: String,
}

pub fn validate_manifest(assets_dir: &str) -> Result<Manifest, Box<dyn std::error::Error>> {
	let manifest_path = Path::new(assets_dir).join("manifest.json");
	if !manifest_path.exists() {
		return Err(format!("manifest.json is missing in assets directory: {}", assets_dir).into());
	}

	let content = fs::read_to_string(&manifest_path)?;
	let manifest: Manifest = serde_json::from_str(&content)?;

	if manifest.schema_version != "1.0.0" {
		return Err(format!("Unsupported manifest schema version: {}", manifest.schema_version).into());
	}

	Ok(manifest)
}

pub fn generate_one_time_password() -> String {
	use std::time::{SystemTime, UNIX_EPOCH};
	let seed = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
	let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
	let mut password = String::new();
	let mut val = seed;
	for _ in 0..12 {
		let idx = (val % chars.len() as u128) as usize;
		password.push(chars.chars().nth(idx).unwrap());
		val /= chars.len() as u128;
	}
	password
}

pub fn materialize_answer_file(
	assets_dir: &str,
	password: &str,
	workdir: &Path,
) -> Result<PathBuf, Box<dyn std::error::Error>> {
	let nonsecret_path = Path::new(assets_dir).join("pve-answer-nonsecret.toml");
	if !nonsecret_path.exists() {
		return Err(
			format!("pve-answer-nonsecret.toml is missing in assets directory: {}", assets_dir).into(),
		);
	}

	let content = fs::read_to_string(&nonsecret_path)?;
	let materialized = content.replace("@ROOT_PASSWORD@", password);

	let output_path = workdir.join("pve-answer.toml");
	fs::write(&output_path, materialized)?;

	#[cfg(unix)]
	{
		use std::os::unix::fs::PermissionsExt;
		let mut perms = fs::metadata(&output_path)?.permissions();
		perms.set_mode(0o600);
		fs::set_permissions(&output_path, perms)?;
	}

	Ok(output_path)
}
