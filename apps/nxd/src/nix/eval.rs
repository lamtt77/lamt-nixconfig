use std::process::Command;
use std::sync::{Mutex, OnceLock};

static LOCAL_NIX_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

pub fn get_local_nix_lock() -> &'static Mutex<()> {
	LOCAL_NIX_LOCK.get_or_init(|| Mutex::new(()))
}

pub fn get_current_host_system() -> String {
	static HOST_SYSTEM: OnceLock<String> = OnceLock::new();
	HOST_SYSTEM
		.get_or_init(|| {
			let output =
				Command::new("nix").args(["eval", "--raw", "--expr", "builtins.currentSystem"]).output();
			if let Ok(out) = output
				&& out.status.success()
			{
				return String::from_utf8_lossy(&out.stdout).trim().to_string();
			}

			if cfg!(target_os = "macos") {
				if cfg!(target_arch = "aarch64") {
					"aarch64-darwin".to_string()
				} else {
					"x86_64-darwin".to_string()
				}
			} else {
				"x86_64-linux".to_string()
			}
		})
		.clone()
}

pub fn check_local_nix_binary() -> bool {
	Command::new("nix").arg("--version").output().is_ok()
}

pub fn check_local_can_build(target_system: &str) -> bool {
	let _local_guard = get_local_nix_lock().lock().unwrap();
	let expr = format!(
		"derivation {{ name = \"test\"; builder = \"/bin/sh\"; args = [ \"-c\" \"echo ok > $out\" ]; system = \"{}\"; }}",
		target_system
	);
	let output = Command::new("nix")
		.args(["build", "--expr", &expr, "--no-link", "--max-jobs", "1", "--connect-timeout", "2"])
		.output();

	if let Ok(out) = output { out.status.success() } else { false }
}

pub fn is_current_host_ssh_target(ssh_connection: &str) -> bool {
	let (user, host) = ssh_connection
		.rsplit_once('@')
		.map(|(user, host)| (Some(user), host))
		.unwrap_or((None, ssh_connection));

	let local_user = std::env::var("USER").ok();
	if let (Some(expected), Some(actual)) = (user, local_user.as_deref())
		&& expected != actual
	{
		return false;
	}

	let local_hostname = crate::fleet::local::current_local_hostname();
	if local_hostname.is_empty() {
		return false;
	}

	host == "localhost" || host == "127.0.0.1" || host == local_hostname
}

pub fn is_builder_target_host(ssh_connection: &str, hostname: &str, target_ip: &str) -> bool {
	let (_, host) = ssh_connection
		.rsplit_once('@')
		.map(|(user, host)| (Some(user), host))
		.unwrap_or((None, ssh_connection));

	host == target_ip || host == hostname
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn test_is_builder_target_host() {
		assert!(is_builder_target_host("deploy@192.168.1.19", "utils", "192.168.1.19"));
		assert!(is_builder_target_host("deploy@utils", "utils", "192.168.1.19"));
		assert!(is_builder_target_host("192.168.1.19", "utils", "192.168.1.19"));
		assert!(is_builder_target_host("utils", "utils", "192.168.1.19"));
		assert!(!is_builder_target_host("deploy@otherhost", "utils", "192.168.1.19"));
	}
}
