use std::path::{Path, PathBuf};
use std::sync::OnceLock;

pub const DEFAULT_SECRETS_REPO: &str = "../lamt-secrets";
pub const DEFAULT_BUILDER: &str = "deploy@utils";
pub const DEFAULT_VMW_ISO_DIR: &str = "/Users/lamt/Virtual Machines.localized/VMWIsoImages";
pub const DEFAULT_PROXMOX_ISO_STORAGE: &str = "arthurz2-dir";
pub const DEFAULT_PROXMOX_DISK_STORAGE: &str = "arthurz2-lvm";
pub const DEFAULT_PROXMOX_NETWORK: &str = "virtio,bridge=vmbr1,tag=10";

pub const DEFAULT_NIX_CFG: &str = "lamt-nixconfig";
pub const DEFAULT_TEA_URL: &str = "tea.lamhub.com";
pub const DEFAULT_GITHUB_USER: &str = "lamtt77";
pub const DEFAULT_TEA_SSH_USER: &str = "git";

pub const APP_NAME: &str = "nxd";
pub const SECRET_INPUT_NAME: &str = "installer-secret";
pub const CHECKOUT_EXCLUDES: &[&str] =
	&[".git", "result", ".DS_Store", "target", "apps/nxd/target", "secrets"];
pub const LOCAL_CACHE_URL: &str = "https://cache.lamhub.com?priority=10";
pub const LOCAL_CACHE_KEY: &str = "cache.lamhub.com-1:D/ywCfChYM7EGJ3UbQsH2YX8Svq2okabE+qdalC4fdw=";

pub const FALLBACK_TARGET_NIXOS_ISO_VERSION: &str = "26.05.20260603.6b31628";
pub const FALLBACK_TARGET_NIXOS_CHANNEL: &str = "nixos-26.05";

// Note: We deliberately pin the default kexec installer channel to a stable, older release
// (nixos-25.05) rather than matching the target NixOS version (26.05).
// Newer kexec kernels/initrds can fail to load on older target hosts (e.g. Ubuntu VMs)
// due to compatibility issues with host-level `kexec-tools`.
pub const PRIMARY_KEXEC_INSTALLER_CHANNEL: &str = "nixos-25.05";

pub struct HostSopsSource {
	pub path: PathBuf,
	pub description: String,
}

pub fn host_sops_lookup_paths(hostname: &str) -> (PathBuf, PathBuf) {
	let repo_path = get_secrets_repo().join("sops").join(format!("{}.yaml", hostname));

	let base_dir = get_flake_dir()
		.unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));

	let local_path = base_dir.join("secrets").join("sops").join(format!("{}.yaml", hostname));

	(repo_path, local_path)
}

#[derive(serde::Deserialize, Debug, Default, Clone)]
struct Defines {
	#[serde(rename = "myRepoName")]
	my_repo_name: String,
	#[serde(rename = "githubUser")]
	github_user: String,
	#[serde(rename = "teaURL")]
	tea_url: String,
	#[serde(rename = "mySshAuthKey")]
	my_ssh_auth_key: String,
	#[serde(rename = "defaultNetworks")]
	default_networks: Vec<String>,
}

fn load_defines() -> &'static Defines {
	static DEFINES: OnceLock<Defines> = OnceLock::new();
	DEFINES.get_or_init(|| {
		let defines_path = if let Some(dir) = get_flake_dir() {
			dir.join("defines.nix").to_string_lossy().to_string()
		} else {
			"./defines.nix".to_string()
		};

		let expr = format!(
			r#"
            let
              defs = import {};
            in
            {{
              myRepoName = defs.myRepoName or "";
              githubUser = defs.githubUser or "";
              teaURL = defs.teaURL or "";
              mySshAuthKey = defs.mySshAuthKey or "";
              defaultNetworks = defs.defaultNetworks or [];
            }}
            "#,
			defines_path
		);

		let output = std::process::Command::new("nix")
			.args(["eval", "--json", "--impure", "--expr", &expr])
			.output();
		match output {
			Ok(out) if out.status.success() => serde_json::from_slice(&out.stdout).unwrap_or_default(),
			_ => Defines::default(),
		}
	})
}

fn define_value(attr: &str) -> Option<String> {
	let definitions = load_defines();
	let value = match attr {
		"myRepoName" => &definitions.my_repo_name,
		"githubUser" => &definitions.github_user,
		"teaURL" => &definitions.tea_url,
		"mySshAuthKey" => &definitions.my_ssh_auth_key,
		_ => return None,
	};
	(!value.is_empty()).then(|| value.clone())
}

/// Resolves the secrets repository absolute path.
pub fn get_secrets_repo() -> PathBuf {
	let opts = get_runtime_options();
	if let Some(ref secrets_ref) = opts.secrets_repo
		&& !secrets_ref.is_empty()
	{
		return Path::new(secrets_ref).to_path_buf();
	}

	if let Ok(repo) = std::env::var("DEFAULT_SECRETS_REPO") {
		Path::new(&repo).to_path_buf()
	} else {
		// Try detected locations for lamt-secrets
		let mut detected_path = None;
		if let Ok(home) = std::env::var("HOME") {
			let p = Path::new(&home).join("lamt-secrets");
			if p.exists() {
				detected_path = Some(p);
			}
		}
		if detected_path.is_none() {
			let p = Path::new("/Users/lamt/lamt-secrets");
			if p.exists() {
				detected_path = Some(p.to_path_buf());
			}
		}
		if detected_path.is_none() {
			let p = Path::new("/home/lamt/lamt-secrets");
			if p.exists() {
				detected_path = Some(p.to_path_buf());
			}
		}

		if let Some(path) = detected_path {
			path
		} else {
			let relative_path = Path::new(DEFAULT_SECRETS_REPO);
			if relative_path.exists() {
				relative_path.to_path_buf()
			} else if let Ok(cwd) = std::env::current_dir() {
				let sibling_repo =
					cwd.parent().map(|parent| parent.join("lamt-secrets")).filter(|path| path.exists());

				if let Some(path) = sibling_repo { path } else { relative_path.to_path_buf() }
			} else {
				relative_path.to_path_buf()
			}
		}
	}
}

/// Walks up from `start` looking for a `flake.nix`, returning the first
/// directory that contains one. Returns `None` if the filesystem root is
/// reached without finding one.
fn find_flake_root(start: &std::path::Path) -> Option<std::path::PathBuf> {
	let mut dir = start;
	loop {
		if dir.join("flake.nix").exists() {
			return Some(dir.to_path_buf());
		}
		match dir.parent() {
			Some(parent) => dir = parent,
			None => return None,
		}
	}
}

/// Resolves the configuration flake directory path.
pub fn get_flake_dir() -> Option<PathBuf> {
	let opts = get_runtime_options();
	if let Some(ref flake_ref) = opts.flake
		&& !flake_ref.is_empty()
		&& let Some(local_path) = local_flake_path(flake_ref)
		&& local_path.exists()
	{
		return Some(local_path);
	}

	if let Ok(repo) = std::env::var("DEFAULT_FLAKE_REPO") {
		Some(PathBuf::from(repo))
	} else if let Ok(cwd) = std::env::current_dir()
		&& let Some(root) = find_flake_root(&cwd)
	{
		Some(root)
	} else {
		let mut detected_path = None;
		if let Ok(home) = std::env::var("HOME") {
			let p = Path::new(&home).join("lamt-nixconfig");
			if p.exists() {
				detected_path = Some(p);
			}
		}
		if detected_path.is_none() {
			let p = Path::new("/Users/lamt/lamt-nixconfig");
			if p.exists() {
				detected_path = Some(p.to_path_buf());
			}
		}
		if detected_path.is_none() {
			let p = Path::new("/home/lamt/lamt-nixconfig");
			if p.exists() {
				detected_path = Some(p.to_path_buf());
			}
		}
		detected_path
	}
}

pub fn resolve_flake(flake_arg: Option<&str>) -> String {
	let flake_val = match flake_arg {
		Some(val) if !val.is_empty() => val.to_string(),
		_ => {
			if let Some(root) = get_flake_dir() {
				format!("path:{}", root.display())
			} else {
				"path:.".to_string()
			}
		}
	};

	match flake_val.as_str() {
		"github" => format!("github:{}/{}", github_user(), nix_cfg()),
		"tea" => {
			format!("git+ssh://{}@{}/{}/{}", DEFAULT_TEA_SSH_USER, tea_url(), github_user(), nix_cfg())
		}
		other => other.to_string(),
	}
}

pub fn flake_uri() -> String {
	let opts = get_runtime_options();
	resolve_flake(opts.flake.as_deref())
}

pub fn is_local_flake(flake_ref: &str) -> bool {
	flake_ref.starts_with("path:")
		|| flake_ref.starts_with("git+file:")
		|| flake_ref == "."
		|| flake_ref == ".."
		|| flake_ref.starts_with("./")
		|| flake_ref.starts_with("../")
		|| flake_ref.starts_with('/')
}

pub fn local_flake_path(flake_ref: &str) -> Option<PathBuf> {
	let path = if let Some(path) = flake_ref.strip_prefix("path:") {
		path
	} else if let Some(path) = flake_ref.strip_prefix("git+file:") {
		path.strip_prefix("//").unwrap_or(path).split('?').next().unwrap_or(path)
	} else if is_local_flake(flake_ref) {
		flake_ref
	} else {
		return None;
	};
	Some(PathBuf::from(path))
}

pub fn resolve_host_sops_source(hostname: &str) -> Option<HostSopsSource> {
	let (repo_path, local_path) = host_sops_lookup_paths(hostname);

	if repo_path.exists() {
		let description = if local_path.exists() {
			format!(
				"Found host secrets in both locations; preferring lamt-secrets: {}",
				repo_path.display()
			)
		} else {
			format!("Using host secrets from lamt-secrets: {}", repo_path.display())
		};

		Some(HostSopsSource { path: repo_path, description })
	} else if local_path.exists() {
		Some(HostSopsSource {
			path: local_path.clone(),
			description: format!("Using host secrets from repo-local secrets: {}", local_path.display()),
		})
	} else {
		None
	}
}

/// Get the configuration repository name.
pub fn nix_cfg() -> String {
	static VALUE: OnceLock<String> = OnceLock::new();
	VALUE
		.get_or_init(|| define_value("myRepoName").unwrap_or_else(|| DEFAULT_NIX_CFG.to_string()))
		.clone()
}

/// Get the GitHub user.
pub fn github_user() -> String {
	static VALUE: OnceLock<String> = OnceLock::new();
	VALUE
		.get_or_init(|| define_value("githubUser").unwrap_or_else(|| DEFAULT_GITHUB_USER.to_string()))
		.clone()
}

/// Get the Gitea/Tea URL.
pub fn tea_url() -> String {
	static VALUE: OnceLock<String> = OnceLock::new();
	VALUE
		.get_or_init(|| define_value("teaURL").unwrap_or_else(|| DEFAULT_TEA_URL.to_string()))
		.clone()
}

/// Get the SSH authorized key.
pub fn ssh_auth_key() -> String {
	static VALUE: OnceLock<String> = OnceLock::new();
	VALUE
		.get_or_init(|| {
			define_value("mySshAuthKey").unwrap_or_else(|| {
				"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJCiBimBlJYNvMmk8F/UPvBjtgBR8tDIgXyeaUOIEtOA lamt"
					.to_string()
			})
		})
		.clone()
}

/// Retrieve approved scan subnets from defines.nix.
pub fn default_networks() -> Vec<String> {
	load_defines().default_networks.clone()
}

fn parse_nixpkgs_version_from_flake() -> Option<String> {
	let flake_dir = get_flake_dir()?;
	let flake_path = flake_dir.join("flake.nix");
	if let Ok(content) = std::fs::read_to_string(&flake_path) {
		for line in content.lines() {
			if let Some(pos) = line.find("github:nixos/nixpkgs/nixos-") {
				let start = pos + "github:nixos/nixpkgs/nixos-".len();
				let end_chars = ['"', '\'', ';', ' ', '\t'];
				if let Some(end_offset) = line[start..].find(|c| end_chars.contains(&c)) {
					let version = line[start..start + end_offset].trim().to_string();
					if !version.is_empty() {
						return Some(version);
					}
				}
			}
		}
	}
	None
}

/// Get the NixOS ISO version dynamically by querying the flake metadata.
pub fn nixos_iso_version() -> String {
	static VERSION: OnceLock<String> = OnceLock::new();
	VERSION
		.get_or_init(|| {
			// 1. Try local parser first
			if let Some(version) = parse_nixpkgs_version_from_flake() {
				if FALLBACK_TARGET_NIXOS_ISO_VERSION.starts_with(&version) {
					return FALLBACK_TARGET_NIXOS_ISO_VERSION.to_string();
				}
				// If version changed, try to get the exact release from nix eval
				let flake_ref = if let Some(local_path) = local_flake_path(&flake_uri()) {
					format!(
						"{}#nixosConfigurations.minimal-iso-x86.config.system.nixos.release",
						local_path.display()
					)
				} else {
					".#nixosConfigurations.minimal-iso-x86.config.system.nixos.release".to_string()
				};
				let output = std::process::Command::new("nix")
					.args(["eval", &flake_ref, "--raw", "--offline"])
					.output();
				if let Ok(out) = output
					&& out.status.success()
				{
					let version = String::from_utf8_lossy(&out.stdout).trim().to_string();
					if !version.is_empty() {
						return version;
					}
				}
				return format!("{}.unknown", version);
			}

			// 2. Fall back to nix eval --offline
			let flake_ref = if let Some(local_path) = local_flake_path(&flake_uri()) {
				format!(
					"{}#nixosConfigurations.minimal-iso-x86.config.system.nixos.release",
					local_path.display()
				)
			} else {
				".#nixosConfigurations.minimal-iso-x86.config.system.nixos.release".to_string()
			};
			let output =
				std::process::Command::new("nix").args(["eval", &flake_ref, "--raw", "--offline"]).output();
			if let Ok(out) = output
				&& out.status.success()
			{
				let version = String::from_utf8_lossy(&out.stdout).trim().to_string();
				if !version.is_empty() {
					return version;
				}
			}

			// 3. Fall back to hardcoded default
			FALLBACK_TARGET_NIXOS_ISO_VERSION.to_string()
		})
		.clone()
}

/// Get the NixOS Channel dynamically by querying the flake metadata.
pub fn nixos_channel() -> String {
	static CHANNEL: OnceLock<String> = OnceLock::new();
	CHANNEL
		.get_or_init(|| {
			// 1. Try local parser first
			if let Some(version) = parse_nixpkgs_version_from_flake() {
				return format!("nixos-{}", version);
			}

			// 2. Fall back to nix eval --offline
			let flake_ref = if let Some(local_path) = local_flake_path(&flake_uri()) {
				format!(
					"{}#nixosConfigurations.minimal-iso-x86.config.system.nixos.release",
					local_path.display()
				)
			} else {
				".#nixosConfigurations.minimal-iso-x86.config.system.nixos.release".to_string()
			};
			let output =
				std::process::Command::new("nix").args(["eval", &flake_ref, "--raw", "--offline"]).output();
			if let Ok(out) = output
				&& out.status.success()
			{
				let release = String::from_utf8_lossy(&out.stdout).trim().to_string();
				if !release.is_empty() {
					return format!("nixos-{}", release);
				}
			}

			// 3. Fall back to hardcoded default
			FALLBACK_TARGET_NIXOS_CHANNEL.to_string()
		})
		.clone()
}

/// Get the NixOS Channel for the kexec installer, prioritizing environment override.
pub fn kexec_channel() -> String {
	std::env::var("DEFAULT_KEXEC_INSTALLER_CHANNEL")
		.or_else(|_| std::env::var("DEFAULT_KEXEC_CHANNEL"))
		.unwrap_or_else(|_| PRIMARY_KEXEC_INSTALLER_CHANNEL.to_string())
}

/// Dynamically construct the kexec image download URL based on the configured kexec channel.
pub fn kexec_url(arch: &str) -> String {
	let channel = kexec_channel();
	format!(
		"https://github.com/nix-community/nixos-images/releases/download/{}/nixos-kexec-installer-noninteractive-{}-linux.tar.gz",
		channel, arch
	)
}

/// Get the default Proxmox ISO storage pool
pub fn proxmox_default_iso_storage() -> String {
	DEFAULT_PROXMOX_ISO_STORAGE.to_string()
}

/// Get the default Proxmox disk storage pool
pub fn proxmox_default_disk_storage() -> String {
	DEFAULT_PROXMOX_DISK_STORAGE.to_string()
}

/// Get the default Proxmox network net0 configuration
pub fn proxmox_default_network() -> String {
	DEFAULT_PROXMOX_NETWORK.to_string()
}

/// Finds a custom own-built NixOS ISO in the current workspace.
pub fn find_custom_iso(flavor: &str) -> Option<PathBuf> {
	let workspace_flavor = match flavor {
		"x86_64" => "x86",
		"qemu" => "x86",
		other => other,
	};
	let result_link = format!("result-iso-{}", workspace_flavor);
	let result_path = Path::new(&result_link).join("iso");
	if result_path.exists()
		&& let Ok(entries) = std::fs::read_dir(result_path)
	{
		for entry in entries.flatten() {
			let path = entry.path();
			if path.is_file()
				&& let Some(ext) = path.extension().and_then(|e| e.to_str())
				&& ext == "iso"
			{
				return Some(path);
			}
		}
	}
	None
}

#[derive(Clone, Debug, Default)]
pub struct RuntimeOptions {
	pub debug: bool,
	pub force: bool,
	pub low_mem: Option<bool>,
	pub build_strategy: Option<String>,
	pub builder: Option<String>,
	pub flake: Option<String>,
	pub secrets_repo: Option<String>,
	pub github_token: Option<String>,
	pub redeploy: bool,
	pub overwrite: bool,
	pub build_iso: bool,
	pub deploy_active: bool,
	pub update_host_key: bool,
	pub update_secrets_key: bool,
}

#[cfg(not(test))]
static RUNTIME_OPTIONS: OnceLock<RuntimeOptions> = OnceLock::new();

#[cfg(not(test))]
pub fn set_runtime_options(opts: RuntimeOptions) {
	let _ = RUNTIME_OPTIONS.set(opts);
}

#[cfg(not(test))]
pub fn get_runtime_options() -> &'static RuntimeOptions {
	RUNTIME_OPTIONS.get_or_init(RuntimeOptions::default)
}

#[cfg(test)]
thread_local! {
		static TEST_RUNTIME_OPTIONS: std::cell::RefCell<Option<&'static RuntimeOptions>> =
				const { std::cell::RefCell::new(None) };
}

#[cfg(test)]
pub fn set_runtime_options(opts: RuntimeOptions) {
	let leaked = Box::leak(Box::new(opts));
	TEST_RUNTIME_OPTIONS.with(|cell| {
		*cell.borrow_mut() = Some(leaked);
	});
}

#[cfg(test)]
pub fn get_runtime_options() -> &'static RuntimeOptions {
	TEST_RUNTIME_OPTIONS.with(|cell| {
		if let Some(opts) = *cell.borrow() {
			opts
		} else {
			static DEFAULT_OPTS: OnceLock<RuntimeOptions> = OnceLock::new();
			DEFAULT_OPTS.get_or_init(RuntimeOptions::default)
		}
	})
}

#[cfg(test)]
thread_local! {
		pub static TEST_GITHUB_TOKEN: std::cell::RefCell<Option<Option<String>>> = const { std::cell::RefCell::new(None) };
}

#[cfg(test)]
pub fn set_test_github_token(token: Option<String>) {
	TEST_GITHUB_TOKEN.with(|t| {
		*t.borrow_mut() = Some(token);
	});
}

#[cfg(not(test))]
static GITHUB_TOKEN_CACHE: OnceLock<Option<String>> = OnceLock::new();

#[cfg(test)]
pub fn get_github_token() -> Option<String> {
	let mut token = None;
	let has_override = TEST_GITHUB_TOKEN.with(|t| {
		if let Some(ref val) = *t.borrow() {
			token = val.clone();
			true
		} else {
			false
		}
	});
	if has_override { token } else { None }
}

#[cfg(not(test))]
pub fn get_github_token() -> Option<String> {
	GITHUB_TOKEN_CACHE
		.get_or_init(|| {
			// 1. CLI option
			let opts = get_runtime_options();
			if let Some(ref token) = opts.github_token
				&& !token.is_empty()
			{
				return Some(token.clone());
			}

			// 2. Environment variable
			if let Ok(token) = std::env::var("GITHUB_TOKEN")
				&& !token.is_empty()
			{
				return Some(token);
			}

			// 3. gh auth token fallback
			let output = std::process::Command::new("gh").args(["auth", "token"]).output();
			match output {
				Ok(out) if out.status.success() => {
					let token = String::from_utf8_lossy(&out.stdout).trim().to_string();
					if !token.is_empty() {
						return Some(token);
					}
				}
				_ => {
					eprintln!(
						"[WARNING] gh CLI is not installed or not authenticated; skipping gh auth token fallback."
					);
				}
			}
			None
		})
		.clone()
}

pub fn nix_token_args() -> Vec<String> {
	if let Some(token) = get_github_token() {
		vec!["--option".to_string(), "access-tokens".to_string(), format!("github.com={}", token)]
	} else {
		vec![]
	}
}

pub fn redact_token(input: &str) -> String {
	if let Some(token) = get_github_token()
		&& !token.is_empty()
	{
		return input.replace(&token, "<github_token_redacted>");
	}
	input.to_string()
}

#[cfg(test)]
mod tests {
	use super::*;

	static ENV_MUTEX: std::sync::Mutex<()> = std::sync::Mutex::new(());

	#[test]
	fn test_github_token_redaction() {
		set_test_github_token(Some("my_secret_token_1234".to_string()));
		assert_eq!(get_github_token(), Some("my_secret_token_1234".to_string()));

		let token_args = nix_token_args();
		assert_eq!(
			token_args,
			vec![
				"--option".to_string(),
				"access-tokens".to_string(),
				"github.com=my_secret_token_1234".to_string()
			]
		);

		let log_msg =
			"Running: nix build --option access-tokens github.com=my_secret_token_1234 --print-out-paths";
		let redacted = redact_token(log_msg);
		assert_eq!(
			redacted,
			"Running: nix build --option access-tokens github.com=<github_token_redacted> --print-out-paths"
		);

		// Reset
		set_test_github_token(None);
		assert_eq!(get_github_token(), None);
		assert!(nix_token_args().is_empty());
		assert_eq!(redact_token("my_secret_token_1234"), "my_secret_token_1234");
	}

	#[test]
	fn test_env_var_overrides() {
		let _guard = ENV_MUTEX.lock().unwrap();
		unsafe {
			std::env::set_var("DEFAULT_SECRETS_REPO", "/tmp/mock-secrets");
		}
		assert_eq!(get_secrets_repo(), PathBuf::from("/tmp/mock-secrets"));
		unsafe {
			std::env::remove_var("DEFAULT_SECRETS_REPO");
		}

		unsafe {
			std::env::set_var("DEFAULT_FLAKE_REPO", "/tmp/mock-flake");
		}
		assert_eq!(get_flake_dir(), Some(PathBuf::from("/tmp/mock-flake")));
		unsafe {
			std::env::remove_var("DEFAULT_FLAKE_REPO");
		}
	}

	#[test]
	fn test_parse_nixpkgs_version() {
		let _guard = ENV_MUTEX.lock().unwrap();
		let temp_dir = std::env::temp_dir().join("nxd-test-flake");
		std::fs::create_dir_all(&temp_dir).unwrap();
		let flake_path = temp_dir.join("flake.nix");
		std::fs::write(
			&flake_path,
			r#"{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  };
}"#,
		)
		.unwrap();

		unsafe {
			std::env::set_var("DEFAULT_FLAKE_REPO", temp_dir.to_str().unwrap());
		}
		assert_eq!(parse_nixpkgs_version_from_flake(), Some("26.05".to_string()));

		// Test with single quotes and different spaces
		std::fs::write(
			&flake_path,
			r#"{
  inputs = {
    nixpkgs.url = 'github:nixos/nixpkgs/nixos-27.05';
  };
}"#,
		)
		.unwrap();
		assert_eq!(parse_nixpkgs_version_from_flake(), Some("27.05".to_string()));

		unsafe {
			std::env::remove_var("DEFAULT_FLAKE_REPO");
		}
		let _ = std::fs::remove_dir_all(&temp_dir);
	}

	#[test]
	fn test_secrets_repo_cli_override() {
		set_runtime_options(RuntimeOptions {
			secrets_repo: Some("/tmp/cli-mock-secrets".to_string()),
			..Default::default()
		});
		assert_eq!(get_secrets_repo(), PathBuf::from("/tmp/cli-mock-secrets"));

		set_runtime_options(RuntimeOptions::default());
	}
}
