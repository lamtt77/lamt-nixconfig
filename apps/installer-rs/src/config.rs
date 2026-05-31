use std::path::{Path, PathBuf};
use std::sync::OnceLock;

pub const DEFAULT_SECRETS_REPO: &str = "../lamt-secrets";
pub const DEFAULT_BUILDER: &str = "deploy@utils";
pub const DEFAULT_VMW_ISO_DIR: &str = "/Users/lamt/Virtual Machines.localized/VMWIsoImages";

pub const DEFAULT_NIX_CFG: &str = "lamt-nixconfig";
pub const DEFAULT_TEA_URL: &str = "tea.lamhub.com";
pub const DEFAULT_GITHUB_USER: &str = "lamtt77";
pub const DEFAULT_TEA_SSH_USER: &str = "git";

pub const KEXEC_BASE_URL: &str = "https://github.com/nix-community/nixos-images/releases/download/nixos-25.05/nixos-kexec-installer-noninteractive";

/// Helper function to evaluate attributes from defines.nix via `nix eval`
pub fn eval_defines(attr: &str) -> Option<String> {
    let expr = format!("let defs = import ./defines.nix; in defs.{}", attr);
    let output = std::process::Command::new("nix")
        .args(&["eval", "--raw", "--impure", "--expr", &expr])
        .output();
    if let Ok(out) = output {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !s.is_empty() {
                return Some(s);
            }
        }
    }
    None
}

/// Resolves the secrets repository absolute path.
pub fn get_secrets_repo() -> PathBuf {
    if let Ok(repo) = std::env::var("DEFAULT_SECRETS_REPO") {
        Path::new(&repo).to_path_buf()
    } else {
        let relative_path = Path::new(DEFAULT_SECRETS_REPO);
        if relative_path.exists() {
            relative_path.to_path_buf()
        } else {
            Path::new("/Users/lamt/lamt-secrets").to_path_buf()
        }
    }
}

/// Get the configuration repository name (myRepoName in defines.nix)
pub fn nix_cfg() -> String {
    static VAL: OnceLock<String> = OnceLock::new();
    VAL.get_or_init(|| {
        eval_defines("myRepoName").unwrap_or_else(|| DEFAULT_NIX_CFG.to_string())
    }).clone()
}

/// Get the GitHub user (githubUser in defines.nix)
pub fn github_user() -> String {
    static VAL: OnceLock<String> = OnceLock::new();
    VAL.get_or_init(|| {
        eval_defines("githubUser").unwrap_or_else(|| DEFAULT_GITHUB_USER.to_string())
    }).clone()
}

/// Get the Gitea/Tea URL (teaURL in defines.nix)
pub fn tea_url() -> String {
    static VAL: OnceLock<String> = OnceLock::new();
    VAL.get_or_init(|| {
        eval_defines("teaURL").unwrap_or_else(|| DEFAULT_TEA_URL.to_string())
    }).clone()
}

/// Get the SSH authorized key (mySshAuthKey in defines.nix)
pub fn ssh_auth_key() -> String {
    static VAL: OnceLock<String> = OnceLock::new();
    VAL.get_or_init(|| {
        eval_defines("mySshAuthKey").unwrap_or_else(|| {
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJCiBimBlJYNvMmk8F/UPvBjtgBR8tDIgXyeaUOIEtOA lamt".to_string()
        })
    }).clone()
}

/// Finds a custom own-built NixOS ISO in the current workspace.
pub fn find_custom_iso(target_arch: &str) -> Option<PathBuf> {
    let result_link = format!("result-iso-{}-flake", target_arch);
    let result_path = Path::new(&result_link).join("iso");
    if result_path.exists() {
        if let Ok(entries) = std::fs::read_dir(result_path) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_file() {
                    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                        if ext == "iso" {
                            return Some(path);
                        }
                    }
                }
            }
        }
    }
    None
}
