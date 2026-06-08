use crate::context::RuntimeContext;

#[derive(Clone, Debug)]
pub enum DeploymentMode {
    NixosInstall { initial_user: String },
    CloudInitVerify { user: String },
    CloudInitConvert { initial_user: String },
}

impl DeploymentMode {
    pub fn from_context(ctx: &RuntimeContext, convert: bool) -> Self {
        if !ctx.deployment.proxmox.cloud_init.image.is_empty() {
            let user = if ctx.deployment.proxmox.cloud_init.user.is_empty() {
                "ubuntu".to_string()
            } else {
                ctx.deployment.proxmox.cloud_init.user.clone()
            };

            if convert {
                Self::CloudInitConvert { initial_user: user }
            } else {
                Self::CloudInitVerify { user }
            }
        } else {
            Self::NixosInstall {
                initial_user: "root".to_string(),
            }
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Self::NixosInstall { .. } => "NixOS Install",
            Self::CloudInitVerify { .. } => "Cloud-Init Verification",
            Self::CloudInitConvert { .. } => "Cloud-Init Convert to NixOS",
        }
    }

    pub fn is_destructive(&self) -> bool {
        matches!(
            self,
            Self::NixosInstall { .. } | Self::CloudInitConvert { .. }
        )
    }

    pub fn uses_nix_build(&self) -> bool {
        !matches!(self, Self::CloudInitVerify { .. })
    }

    pub fn initial_user(&self) -> &str {
        match self {
            Self::NixosInstall { initial_user } => initial_user,
            Self::CloudInitVerify { user } => user,
            Self::CloudInitConvert { initial_user } => initial_user,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::context::{
        CloudInitConfig, DeploymentConfig, DigitalOceanConfig, ProxmoxConfig, RuntimeContext,
        VmwareConfig,
    };

    fn context_with_cloud_init(image: &str, user: &str) -> RuntimeContext {
        RuntimeContext {
            hostname: "test-host".to_string(),
            target_ip: "127.0.0.1".to_string(),
            username: "nixos".to_string(),
            system: "x86_64-linux".to_string(),
            deployment: DeploymentConfig {
                target_ip: String::new(),
                ssh_proxy_jump: String::new(),
                builder: String::new(),
                low_mem: String::new(),
                substitute_on_destination: false,
                vmid: String::new(),
                disk_size: String::new(),
                tailscale_namespace: String::new(),
                proxmox: ProxmoxConfig {
                    host: String::new(),
                    bios: String::new(),
                    disk_bus: String::new(),
                    scsi_hw: String::new(),
                    disk_storage: String::new(),
                    network: String::new(),
                    extra_networks: Vec::new(),
                    pxe: false,
                    cores: String::new(),
                    memory: String::new(),
                    iso: crate::fleet::metadata::ProxmoxIsoConfig {
                        flavor: "std".to_string(),
                        storage: String::new(),
                        custom_path: String::new(),
                    },
                    cloud_init: CloudInitConfig {
                        image: image.to_string(),
                        user: user.to_string(),
                        ipconfig0: String::new(),
                        ipconfig1: String::new(),
                    },
                },
                digitalocean: DigitalOceanConfig {
                    region: String::new(),
                    size: String::new(),
                    image: String::new(),
                },
                vmware: VmwareConfig {
                    vmx_path: String::new(),
                },
            },
            is_ip_overridden: false,
            flake_ref: "path:.".to_string(),
            common_base_root: None,
            workspace_root: None,
            remote_workspace_dir: None,
            has_disko: true,
            build_system: true,
            role: None,
            tags: Vec::new(),
        }
    }

    #[test]
    fn deployment_mode_defaults_to_nixos_install_without_cloud_init() {
        let ctx = context_with_cloud_init("", "");
        let mode = DeploymentMode::from_context(&ctx, false);

        assert_eq!(mode.label(), "NixOS Install");
        assert_eq!(mode.initial_user(), "root");
        assert!(mode.is_destructive());
        assert!(mode.uses_nix_build());
    }

    #[test]
    fn deployment_mode_verifies_cloud_init_with_default_user() {
        let ctx = context_with_cloud_init("ubuntu.img", "");
        let mode = DeploymentMode::from_context(&ctx, false);

        assert_eq!(mode.label(), "Cloud-Init Verification");
        assert_eq!(mode.initial_user(), "ubuntu");
        assert!(!mode.is_destructive());
        assert!(!mode.uses_nix_build());
    }

    #[test]
    fn deployment_mode_converts_cloud_init_with_configured_user() {
        let ctx = context_with_cloud_init("ubuntu.img", "deploy");
        let mode = DeploymentMode::from_context(&ctx, true);

        assert_eq!(mode.label(), "Cloud-Init Convert to NixOS");
        assert_eq!(mode.initial_user(), "deploy");
        assert!(mode.is_destructive());
        assert!(mode.uses_nix_build());
    }
}
