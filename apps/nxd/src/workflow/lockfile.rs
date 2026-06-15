use crate::process::Logger;
use std::fs;

/// Archives the root flake.lock to the host-specific path under hosts/<host>/flake.lock.
/// Skipping early if we are not using local source, if the root flake.lock is missing,
/// or if the target hosts directory does not exist.
pub fn archive_lockfile(
	hostname: &str,
	flake_ref: &str,
	logger: Logger,
) -> Result<(), Box<dyn std::error::Error>> {
	let Some(flake_root) = crate::config::local_flake_path(flake_ref) else {
		return Ok(());
	};

	let flake_lock = flake_root.join("flake.lock");
	if !flake_lock.exists() {
		return Ok(());
	}

	let dest_dir = flake_root.join("hosts").join(hostname);
	if !dest_dir.exists() {
		crate::warn!(
			logger,
			"Host directory '{}' does not exist; skipping lockfile archival.",
			dest_dir.display()
		);
		return Ok(());
	}

	let dest_lock = dest_dir.join("flake.lock");
	crate::info!(logger, "Archiving flake.lock to {}...", dest_lock.display());

	fs::copy(flake_lock, &dest_lock)?;
	Ok(())
}

#[cfg(test)]
mod tests {
	use super::*;
	use std::env;
	use std::fs;
	use std::sync::Mutex;

	static TEST_MUTEX: Mutex<()> = Mutex::new(());

	#[test]
	fn test_archive_lockfile() {
		let _guard = TEST_MUTEX.lock().unwrap();

		let original_dir = env::current_dir().unwrap();
		let temp_dir = env::temp_dir().join(format!("nxd_test_lockfile_{}", std::process::id()));
		fs::create_dir_all(&temp_dir).unwrap();
		env::set_current_dir(&temp_dir).unwrap();

		let logger = Logger::silent();
		let res = archive_lockfile("gaming", "github:owner/repo", logger.clone());
		assert!(res.is_ok());
		assert!(!temp_dir.join("hosts/gaming/flake.lock").exists());

		let hosts_dir = temp_dir.join("hosts/gaming");
		fs::create_dir_all(&hosts_dir).unwrap();
		fs::write(temp_dir.join("flake.lock"), "test-lockfile-content").unwrap();

		let res = archive_lockfile("gaming", "path:.", logger.clone());
		assert!(res.is_ok());

		let dest_lock = hosts_dir.join("flake.lock");
		assert!(dest_lock.exists());
		let content = fs::read_to_string(dest_lock).unwrap();
		assert_eq!(content, "test-lockfile-content");

		// Cleanup
		env::set_current_dir(original_dir).unwrap();
		let _ = fs::remove_dir_all(temp_dir);
	}
}
