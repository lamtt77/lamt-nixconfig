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

pub const DEFAULT_NIXOS_ISO_VERSION: &str = "25.11.20260522.b77b3de";
pub const DEFAULT_NIXOS_CHANNEL: &str = "nixos-25.11";

pub const KEXEC_BASE_URL: &str = "https://github.com/nix-community/nixos-images/releases/download/nixos-25.05/nixos-kexec-installer-noninteractive";

pub struct HostSopsSource {
    pub path: PathBuf,
    pub description: String,
}

pub fn host_sops_lookup_paths(hostname: &str) -> (PathBuf, PathBuf) {
    let repo_path = get_secrets_repo()
        .join("sops")
        .join(format!("{}.yaml", hostname));

    let local_path = std::env::current_dir()
        .unwrap_or_else(|_| PathBuf::from("."))
        .join("secrets")
        .join("sops")
        .join(format!("{}.yaml", hostname));

    (repo_path, local_path)
}

#[derive(serde::Deserialize, Debug, Default, Clone)]
struct Defines {
    #[serde(rename = "myRepoName")]
    pub my_repo_name: String,
    #[serde(rename = "githubUser")]
    pub github_user: String,
    #[serde(rename = "teaURL")]
    pub tea_url: String,
    #[serde(rename = "mySshAuthKey")]
    pub my_ssh_auth_key: String,
    #[serde(rename = "defaultNetworks")]
    pub default_networks: Vec<String>,
}

fn load_defines() -> &'static Defines {
    static DEFINES: OnceLock<Defines> = OnceLock::new();
    DEFINES.get_or_init(|| {
        let expr = r#"
            let
              defs = import ./defines.nix;
            in
            {
              myRepoName = defs.myRepoName or "";
              githubUser = defs.githubUser or "";
              teaURL = defs.teaURL or "";
              mySshAuthKey = defs.mySshAuthKey or "";
              defaultNetworks = defs.defaultNetworks or [];
            }
        "#;
        let output = std::process::Command::new("nix")
            .args(["eval", "--json", "--impure", "--expr", expr])
            .output();
        match output {
            Ok(out) if out.status.success() => {
                serde_json::from_slice(&out.stdout).unwrap_or_default()
            }
            _ => Defines::default(),
        }
    })
}

/// Helper function to evaluate attributes from defines.nix via `nix eval`
pub fn eval_defines(attr: &str) -> Option<String> {
    let defs = load_defines();
    let val = match attr {
        "myRepoName" => &defs.my_repo_name,
        "githubUser" => &defs.github_user,
        "teaURL" => &defs.tea_url,
        "mySshAuthKey" => &defs.my_ssh_auth_key,
        _ => return None,
    };
    if val.is_empty() {
        None
    } else {
        Some(val.clone())
    }
}

/// Helper function to retrieve approved scan subnets from defines.nix
pub fn default_networks() -> Vec<String> {
    load_defines().default_networks.clone()
}

/// Resolves the secrets repository absolute path.
pub fn get_secrets_repo() -> PathBuf {
    if let Ok(repo) = std::env::var("DEFAULT_SECRETS_REPO") {
        Path::new(&repo).to_path_buf()
    } else {
        let relative_path = Path::new(DEFAULT_SECRETS_REPO);
        if relative_path.exists() {
            relative_path.to_path_buf()
        } else if let Ok(cwd) = std::env::current_dir() {
            let sibling_repo = cwd
                .parent()
                .map(|parent| parent.join("lamt-secrets"))
                .filter(|path| path.exists());

            if let Some(path) = sibling_repo {
                path
            } else {
                relative_path.to_path_buf()
            }
        } else {
            relative_path.to_path_buf()
        }
    }
}

pub fn flake_uri() -> String {
    match std::env::var("NIX_REPO")
        .unwrap_or_else(|_| "local".to_string())
        .as_str()
    {
        "local" => "path:.".to_string(),
        "github" => format!("github:{}/{}", github_user(), nix_cfg()),
        "tea" => format!(
            "git+ssh://{}@{}/{}/{}",
            DEFAULT_TEA_SSH_USER,
            tea_url(),
            github_user(),
            nix_cfg()
        ),
        other => other.to_string(),
    }
}

pub fn is_local_flake_ref(flake_ref: &str) -> bool {
    if flake_ref == "." || flake_ref == "path:." {
        return true;
    }

    if let Ok(current_dir) = std::env::current_dir() {
        flake_ref == format!("path:{}", current_dir.display())
    } else {
        false
    }
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
            format!(
                "Using host secrets from lamt-secrets: {}",
                repo_path.display()
            )
        };

        Some(HostSopsSource {
            path: repo_path,
            description,
        })
    } else if local_path.exists() {
        Some(HostSopsSource {
            path: local_path.clone(),
            description: format!(
                "Using host secrets from repo-local secrets: {}",
                local_path.display()
            ),
        })
    } else {
        None
    }
}

/// Get the configuration repository name (myRepoName in defines.nix)
pub fn nix_cfg() -> String {
    static VAL: OnceLock<String> = OnceLock::new();
    VAL.get_or_init(|| eval_defines("myRepoName").unwrap_or_else(|| DEFAULT_NIX_CFG.to_string()))
        .clone()
}

/// Get the GitHub user (githubUser in defines.nix)
pub fn github_user() -> String {
    static VAL: OnceLock<String> = OnceLock::new();
    VAL.get_or_init(|| {
        eval_defines("githubUser").unwrap_or_else(|| DEFAULT_GITHUB_USER.to_string())
    })
    .clone()
}

/// Get the Gitea/Tea URL (teaURL in defines.nix)
pub fn tea_url() -> String {
    static VAL: OnceLock<String> = OnceLock::new();
    VAL.get_or_init(|| eval_defines("teaURL").unwrap_or_else(|| DEFAULT_TEA_URL.to_string()))
        .clone()
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

/// Get the NixOS ISO version
pub fn nixos_iso_version() -> String {
    DEFAULT_NIXOS_ISO_VERSION.to_string()
}

/// Get the NixOS Channel
pub fn nixos_channel() -> String {
    DEFAULT_NIXOS_CHANNEL.to_string()
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

#[derive(Clone, Debug)]
pub struct RuntimeOptions {
    pub debug: bool,
    pub force: bool,
    pub low_mem: Option<bool>,
    pub build_strategy: Option<String>,
    pub builder: Option<String>,
    pub repo_src: String,
    pub redeploy: bool,
    pub overwrite: bool,
    pub deploy_active: bool,
    pub update_host_key: bool,
    pub update_secrets_key: bool,
}

impl Default for RuntimeOptions {
    fn default() -> Self {
        Self {
            debug: false,
            force: false,
            low_mem: None,
            build_strategy: None,
            builder: None,
            repo_src: "local".to_string(),
            redeploy: false,
            overwrite: false,
            deploy_active: false,
            update_host_key: false,
            update_secrets_key: false,
        }
    }
}

static RUNTIME_OPTIONS: OnceLock<RuntimeOptions> = OnceLock::new();

pub fn set_runtime_options(opts: RuntimeOptions) {
    let _ = RUNTIME_OPTIONS.set(opts);
}

pub fn get_runtime_options() -> &'static RuntimeOptions {
    RUNTIME_OPTIONS.get_or_init(RuntimeOptions::default)
}
