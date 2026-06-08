use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub struct TempDirGuard {
    pub path: PathBuf,
}

impl TempDirGuard {
    pub fn new(label: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let tmp_dir = std::env::var("TMPDIR").unwrap_or_else(|_| "/tmp".to_string());
        let path = PathBuf::from(tmp_dir).join(format!(
            "installer-rs-workspace-{}",
            sanitize_component(label)
        ));
        fs::create_dir_all(&path)?;
        let path = fs::canonicalize(path)?;
        Ok(Self { path })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDirGuard {
    fn drop(&mut self) {
        // Do not delete persistent directories to allow Git evaluation caching!
    }
}

pub fn clean_workspace_except_git(dest: &Path) -> Result<(), Box<dyn std::error::Error>> {
    if !dest.exists() {
        return Ok(());
    }
    for entry in fs::read_dir(dest)? {
        let entry = entry?;
        let path = entry.path();
        let name = entry.file_name();
        if name != ".git" {
            if path.is_dir() {
                fs::remove_dir_all(&path)?;
            } else {
                fs::remove_file(&path)?;
            }
        }
    }
    Ok(())
}

pub fn ensure_git_repo_committed(path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let git_dir = path.join(".git");
    // Also check HEAD: a missing HEAD means the .git dir is corrupted (e.g. from a
    // previous interrupted run) and git commands will fail with "not in a git directory".
    let needs_init = !git_dir.exists() || !git_dir.join("HEAD").exists();
    if needs_init {
        let status = Command::new("git")
            .args(["init", "-q"])
            .current_dir(path)
            .status()?;
        if !status.success() {
            return Err("Failed to initialize git in workspace".into());
        }
    }

    // Configure git dummy identity locally
    let _ = Command::new("git")
        .args(["config", "user.name", "Installer"])
        .current_dir(path)
        .status();
    let _ = Command::new("git")
        .args(["config", "user.email", "installer@local"])
        .current_dir(path)
        .status();
    let _ = Command::new("git")
        .args(["config", "commit.gpgsign", "false"])
        .current_dir(path)
        .status();

    // Check if there are changes
    let output = Command::new("git")
        .args(["status", "--porcelain"])
        .current_dir(path)
        .output()?;
    let status_str = String::from_utf8_lossy(&output.stdout);
    if !status_str.trim().is_empty() {
        // There are changes, commit them
        let status = Command::new("git")
            .args(["add", "-A"])
            .current_dir(path)
            .status()?;
        if !status.success() {
            return Err("Failed to git add in workspace".into());
        }

        let status = Command::new("git")
            .args(["commit", "-q", "-m", "workspace snapshot"])
            .current_dir(path)
            .status()?;
        if !status.success() {
            return Err("Failed to commit changes in workspace".into());
        }
    }

    Ok(())
}

pub fn sanitize_component(input: &str) -> String {
    input
        .chars()
        .map(|ch| match ch {
            'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' => ch,
            _ => '-',
        })
        .collect()
}

#[allow(dead_code)]
pub fn unique_suffix() -> String {
    use std::sync::atomic::{AtomicUsize, Ordering};
    static COUNTER: AtomicUsize = AtomicUsize::new(0);
    let pid = std::process::id();
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .subsec_nanos();
    let count = COUNTER.fetch_add(1, Ordering::SeqCst);
    format!("{}-{}-{}", pid, nanos, count)
}

pub fn clean_legacy_workspaces() {
    let mut dirs_to_clean = vec![PathBuf::from("/tmp")];
    if let Ok(tmp_val) = std::env::var("TMPDIR") {
        dirs_to_clean.push(PathBuf::from(tmp_val));
    }
    dirs_to_clean.dedup();

    for dir in dirs_to_clean {
        if let Ok(entries) = fs::read_dir(&dir) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().into_owned();
                if name.starts_with("installer-rs-") && !name.starts_with("installer-rs-workspace-")
                {
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
