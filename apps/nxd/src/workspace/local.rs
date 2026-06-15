use crate::config;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn sanitize_component(input: &str) -> String {
	input
		.chars()
		.map(|ch| match ch {
			'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' => ch,
			_ => '-',
		})
		.collect()
}

pub fn unique_suffix() -> String {
	use std::sync::atomic::{AtomicUsize, Ordering};
	static COUNTER: AtomicUsize = AtomicUsize::new(0);
	let pid = std::process::id();
	let nanos = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().subsec_nanos();
	let count = COUNTER.fetch_add(1, Ordering::SeqCst);
	format!("{}-{}-{}", pid, nanos, count)
}

pub fn clean_stale_temp_dirs() {
	let mut dirs_to_clean = vec![PathBuf::from("/tmp")];
	if let Ok(tmp_val) = std::env::var("TMPDIR") {
		dirs_to_clean.push(PathBuf::from(tmp_val));
	}
	dirs_to_clean.dedup();

	let app_prefix = format!("{}-", config::APP_NAME);
	let workspace_prefix = format!("{}-workspace-", config::APP_NAME);

	for dir in dirs_to_clean {
		if let Ok(entries) = fs::read_dir(&dir) {
			for entry in entries.flatten() {
				let name = entry.file_name().to_string_lossy().into_owned();
				if name.starts_with(&app_prefix) && !name.starts_with(&workspace_prefix) {
					let full_path = entry.path();
					if full_path.is_dir() {
						let _ = fs::remove_dir_all(&full_path);
					}
				}
			}
		}
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn test_sanitize_component() {
		assert_eq!(sanitize_component("my-host"), "my-host");
		assert_eq!(sanitize_component("my host?"), "my-host-");
		assert_eq!(sanitize_component("abc_123-DEF"), "abc_123-DEF");
	}

	#[test]
	fn test_unique_suffix_non_empty() {
		let s = unique_suffix();
		assert!(!s.is_empty());
		assert_ne!(unique_suffix(), s);
	}
}
