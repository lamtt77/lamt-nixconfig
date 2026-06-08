use crate::pipeline::DeploymentMode;
use crate::process::Logger;
use std::path::PathBuf;

pub use crate::fleet::metadata::{
    CloudInitConfig, DeploymentConfig, DigitalOceanConfig, FlakeMetadata, ProxmoxConfig,
    VmwareConfig,
};

#[derive(Debug, Clone)]
pub struct RuntimeContext {
    pub hostname: String,
    pub target_ip: String,
    pub username: String,
    pub system: String,
    pub deployment: DeploymentConfig,
    pub is_ip_overridden: bool,
    pub flake_ref: String,
    pub common_base_root: Option<PathBuf>,
    pub workspace_root: Option<PathBuf>,
    pub remote_workspace_dir: Option<String>,
    pub has_disko: bool,
    pub build_system: bool,
    pub role: Option<String>,
    pub tags: Vec<String>,
}

fn get_context_cache(
) -> &'static std::sync::Mutex<std::collections::HashMap<String, RuntimeContext>> {
    static CACHE: std::sync::OnceLock<
        std::sync::Mutex<std::collections::HashMap<String, RuntimeContext>>,
    > = std::sync::OnceLock::new();
    CACHE.get_or_init(|| std::sync::Mutex::new(std::collections::HashMap::new()))
}

impl RuntimeContext {
    pub fn load(hostname: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let mut batch = Self::load_batch(&[hostname.to_string()])?;
        batch
            .remove(hostname)
            .ok_or_else(|| format!("Configuration for '{}' not found", hostname).into())
    }

    #[cfg(test)]
    pub fn clear_cache() {
        get_context_cache().lock().unwrap().clear();
    }

    pub fn load_batch(
        hostnames: &[String],
    ) -> Result<std::collections::HashMap<String, Self>, Box<dyn std::error::Error>> {
        if hostnames.is_empty() {
            return Ok(std::collections::HashMap::new());
        }

        let mut result = std::collections::HashMap::new();
        let mut to_load = Vec::new();

        {
            let cache = get_context_cache().lock().unwrap();
            for hostname in hostnames {
                if let Some(ctx) = cache.get(hostname) {
                    result.insert(hostname.clone(), ctx.clone());
                } else {
                    to_load.push(hostname.clone());
                }
            }
        }

        if to_load.is_empty() {
            return Ok(result);
        }

        let loaded = Self::load_batch_uncached(&to_load)?;

        {
            let mut cache = get_context_cache().lock().unwrap();
            for (hostname, ctx) in loaded {
                cache.insert(hostname.clone(), ctx.clone());
                result.insert(hostname, ctx);
            }
        }

        Ok(result)
    }

    fn load_batch_uncached(
        hostnames: &[String],
    ) -> Result<std::collections::HashMap<String, Self>, Box<dyn std::error::Error>> {
        let raw_map = crate::fleet::metadata::load_batch_metadata(hostnames)?;
        let flake_ref = crate::config::flake_uri();

        let mut result = std::collections::HashMap::new();
        for hostname in hostnames {
            let Some(maybe_meta) = raw_map.get(hostname) else {
                return Err(
                    format!("Host '{}' not found in Nix evaluation results", hostname).into(),
                );
            };
            let Some(metadata) = maybe_meta else {
                return Err(format!(
                    "Host '{}' was not found in nixosConfigurations or darwinConfigurations",
                    hostname
                )
                .into());
            };

            let target_ip = if metadata.deployment.target_ip.is_empty() {
                hostname.clone()
            } else {
                metadata.deployment.target_ip.clone()
            };

            let mut final_deployment = metadata.deployment.clone();
            let runtime_options = crate::config::get_runtime_options();
            if let Some(builder_override) = runtime_options.builder.as_ref() {
                if !builder_override.is_empty() {
                    final_deployment.builder = builder_override.clone();
                }
            }
            if let Some(low_mem_override) = runtime_options.low_mem {
                final_deployment.low_mem = if low_mem_override { "yes" } else { "no" }.to_string();
            }

            let ctx = RuntimeContext {
                hostname: hostname.clone(),
                target_ip,
                username: metadata.user.clone(),
                system: metadata.system.clone(),
                deployment: final_deployment,
                is_ip_overridden: false,
                flake_ref: flake_ref.clone(),
                common_base_root: None,
                workspace_root: None,
                remote_workspace_dir: None,
                has_disko: metadata.has_disko,
                build_system: metadata.build_system,
                role: metadata.role.clone(),
                tags: metadata.tags.clone(),
            };
            ctx.validate()?;
            result.insert(hostname.clone(), ctx);
        }

        Ok(result)
    }

    pub fn validate(&self) -> Result<(), Box<dyn std::error::Error>> {
        // 1. Hostname validation
        if self.hostname.is_empty() {
            return Err("Hostname cannot be empty".into());
        }
        if !self
            .hostname
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '.' || c == '_')
        {
            return Err(format!("Invalid characters in hostname '{}'", self.hostname).into());
        }

        // 2. Username validation
        if self.username.is_empty() {
            return Err("Username cannot be empty".into());
        }
        if !self
            .username
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        {
            return Err(format!("Invalid characters in username '{}'", self.username).into());
        }

        // 3. System (Target Architecture) validation
        if self.system.is_empty() {
            return Err("System architecture cannot be empty".into());
        }
        let valid_systems = [
            "x86_64-linux",
            "aarch64-linux",
            "x86_64-darwin",
            "aarch64-darwin",
        ];
        if !valid_systems.contains(&self.system.as_str()) {
            return Err(format!("Unsupported system architecture '{}'", self.system).into());
        }

        // 4. Proxmox VMID validation
        if !self.deployment.vmid.is_empty() && self.deployment.vmid.parse::<u32>().is_err() {
            return Err(format!(
                "Proxmox VMID must be a valid integer, found '{}'",
                self.deployment.vmid
            )
            .into());
        }

        // 5. Target IP validation (can be IP address or hostname)
        if self.target_ip.is_empty() {
            return Err("Target IP/hostname cannot be empty".into());
        }
        if !self.target_ip.chars().all(|c| {
            c.is_ascii_alphanumeric() || c == '-' || c == '.' || c == '_' || c == ':' || c == '/'
        }) {
            return Err(format!(
                "Invalid characters in target IP/hostname '{}'",
                self.target_ip
            )
            .into());
        }

        Ok(())
    }
}

pub fn parse_host_spec(spec: &str) -> (String, Option<String>, Option<String>) {
    let parsed = crate::plan::parse_host_spec(spec);
    (parsed.hostname, parsed.username, parsed.ip)
}

pub fn load_context_from_spec(spec: &str) -> Result<RuntimeContext, Box<dyn std::error::Error>> {
    let (hostname, username_override, ip_override) = parse_host_spec(spec);
    let mut ctx = RuntimeContext::load(&hostname)?;
    if let Some(ip) = ip_override {
        ctx.target_ip = ip;
        ctx.is_ip_overridden = true;
    } else if hostname == crate::fleet::local::current_local_hostname() && ctx.target_ip == hostname
    {
        ctx.target_ip = "127.0.0.1".to_string();
        ctx.is_ip_overridden = true;
    }
    if let Some(username) = username_override {
        if username != ctx.username && username != "root" {
            let is_forced = crate::config::get_runtime_options().force;
            if !is_forced {
                eprintln!(
                    "WARNING: Specified username '{}' does not match the user '{}' configured in the NixOS flake for host '{}'.",
                    username, ctx.username, hostname
                );
                if !dialoguer::Confirm::new()
                    .with_prompt("Do you want to proceed anyway?")
                    .default(false)
                    .interact()
                    .unwrap_or(false)
                {
                    return Err("Aborted due to username mismatch.".into());
                }
            }
        }
        ctx.username = username;
    }
    Ok(ctx)
}

pub fn load_batch_contexts(
    host_list: &[String],
    validate_host_keys: bool,
) -> Result<Vec<RuntimeContext>, Box<dyn std::error::Error>> {
    let host_specs: Vec<_> = host_list.iter().map(|spec| parse_host_spec(spec)).collect();
    let hostnames: Vec<String> = host_specs.iter().map(|s| s.0.clone()).collect();

    println!("Loading configurations for {} targets...", hostnames.len());
    let mut batch_contexts = RuntimeContext::load_batch(&hostnames)?;

    let mut planned_hosts = Vec::new();
    for (host_spec_str, (hostname, username_override, ip_override)) in
        host_list.iter().zip(host_specs)
    {
        let mut ctx = batch_contexts
            .remove(&hostname)
            .ok_or_else(|| format!("Error: context for {} not found in batch results", hostname))?;

        if let Some(ip) = ip_override {
            ctx.target_ip = ip;
            ctx.is_ip_overridden = true;
        } else if hostname == crate::fleet::local::current_local_hostname()
            && ctx.target_ip == hostname
        {
            ctx.target_ip = "127.0.0.1".to_string();
            ctx.is_ip_overridden = true;
        }

        if let Some(username) = username_override {
            if username != ctx.username && username != "root" {
                let is_forced = crate::config::get_runtime_options().force;
                let warning = format!(
                    "WARNING: Specified username '{}' does not match the user '{}' configured in the NixOS flake for host '{}'.",
                    username, ctx.username, hostname
                );
                if !crate::operation::confirm::confirm_action(
                    "Do you want to proceed anyway?",
                    Some(&warning),
                    is_forced,
                )
                .unwrap_or(false)
                {
                    return Err("Aborted due to username mismatch.".into());
                }
            }
            ctx.username = username;
        }

        let logger = Logger::terminal();
        ctx.target_ip = crate::fleet::resolution::resolve_target_ip(&ctx, logger.clone());

        if validate_host_keys && !crate::fleet::local::is_local_target(&ctx) {
            crate::identity::ssh::validate_and_sync_target_host_key(&ctx, logger.clone()).map_err(
                |e| {
                    format!(
                        "Error validating/syncing target host key for {}: {}",
                        host_spec_str, e
                    )
                },
            )?;
        }

        planned_hosts.push(ctx);
    }

    Ok(planned_hosts)
}

pub fn resolve_install_context(
    source_ctx: &RuntimeContext,
    mode: &DeploymentMode,
    convert_to: Option<&String>,
) -> Result<RuntimeContext, Box<dyn std::error::Error>> {
    if !matches!(mode, DeploymentMode::CloudInitConvert { .. }) {
        if let Some(host) = convert_to {
            return Err(format!("--convert-to is only valid for cloud-init conversion targets. Unexpected install host: {}", host).into());
        }
        return Ok(source_ctx.clone());
    }

    let install_name = convert_to
        .map(|host| host.as_str())
        .ok_or("--convert-to <nixos-host> is required for cloud-init conversion.")?;

    let install_ctx = if install_name == source_ctx.hostname {
        source_ctx.clone()
    } else {
        RuntimeContext::load(install_name)?
    };

    if !install_ctx.has_disko {
        return Err(format!(
            "Cloud-init conversion needs an installable NixOS configuration, but '{}' does not provide config.system.build.diskoScript.",
            install_name
        )
        .into());
    }

    let source_disk_bus = source_ctx.deployment.proxmox.disk_bus.trim();
    let install_disk_bus = install_ctx.deployment.proxmox.disk_bus.trim();
    if !source_disk_bus.is_empty()
        && !install_disk_bus.is_empty()
        && source_disk_bus != install_disk_bus
    {
        return Err(format!(
            "cloud-init source '{}' uses Proxmox diskBus='{}', but install host '{}' expects diskBus='{}'. These expose different Linux disk names and can make Disko target a missing disk. Use a convert-to host with matching diskBus or recreate the cloud-init VM with the install host's disk bus.",
            source_ctx.hostname,
            source_disk_bus,
            install_ctx.hostname,
            install_disk_bus
        )
        .into());
    }

    let mut install_ctx = install_ctx;
    install_ctx.target_ip = source_ctx.target_ip.clone();
    install_ctx.is_ip_overridden = true;
    Ok(install_ctx)
}

pub fn find_proxy_jump_for_ip(host_or_ip: &str) -> Option<String> {
    if let Ok(cache) = get_context_cache().lock() {
        for ctx in cache.values() {
            if (ctx.target_ip == host_or_ip || ctx.hostname == host_or_ip)
                && !ctx.deployment.ssh_proxy_jump.is_empty()
            {
                return Some(ctx.deployment.ssh_proxy_jump.clone());
            }
        }
    }
    None
}

pub fn find_vmid_for_proxy_jump(proxy_jump: &str) -> Option<String> {
    if proxy_jump.is_empty() {
        return None;
    }
    // Parse user@host or just host
    let host_part = if let Some((_, host)) = proxy_jump.split_once('@') {
        host
    } else {
        proxy_jump
    };

    // First try the thread-local/global cache of loaded contexts
    if let Ok(cache) = get_context_cache().lock() {
        for ctx in cache.values() {
            if ctx.hostname == host_part || ctx.target_ip == host_part {
                if !ctx.deployment.vmid.is_empty() {
                    return Some(ctx.deployment.vmid.clone());
                }
            }
        }
    }

    // Fall back to loading full inventory to look up the host
    if let Ok(inventory) = crate::fleet::metadata::load_full_inventory() {
        for (hostname, meta) in inventory {
            if hostname == host_part || meta.deployment.target_ip == host_part {
                if !meta.deployment.vmid.is_empty() {
                    return Some(meta.deployment.vmid.clone());
                }
            }
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::context::{
        CloudInitConfig, DeploymentConfig, DigitalOceanConfig, ProxmoxConfig, VmwareConfig,
    };

    fn make_test_ctx(
        hostname: &str,
        username: &str,
        system: &str,
        vmid: &str,
        target_ip: &str,
    ) -> RuntimeContext {
        RuntimeContext {
            hostname: hostname.to_string(),
            target_ip: target_ip.to_string(),
            username: username.to_string(),
            system: system.to_string(),
            deployment: DeploymentConfig {
                target_ip: target_ip.to_string(),
                ssh_proxy_jump: String::new(),
                builder: String::new(),
                low_mem: String::new(),
                substitute_on_destination: false,
                vmid: vmid.to_string(),
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
                        image: String::new(),
                        user: String::new(),
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
    fn test_valid_context_passes() {
        let ctx = make_test_ctx("my-host", "nixos", "x86_64-linux", "123", "10.0.0.1");
        assert!(ctx.validate().is_ok());
    }

    #[test]
    fn test_invalid_hostname_fails() {
        let ctx = make_test_ctx("my host?", "nixos", "x86_64-linux", "123", "10.0.0.1");
        assert!(ctx.validate().is_err());
    }

    #[test]
    fn test_invalid_username_fails() {
        let ctx = make_test_ctx("my-host", "user?", "x86_64-linux", "123", "10.0.0.1");
        assert!(ctx.validate().is_err());
    }

    #[test]
    fn test_unsupported_system_fails() {
        let ctx = make_test_ctx("my-host", "nixos", "invalid-system", "123", "10.0.0.1");
        assert!(ctx.validate().is_err());
    }

    #[test]
    fn test_invalid_vmid_fails() {
        let ctx = make_test_ctx("my-host", "nixos", "x86_64-linux", "abc", "10.0.0.1");
        assert!(ctx.validate().is_err());
    }

    #[test]
    fn test_context_cache() {
        RuntimeContext::clear_cache();
        {
            let cache = get_context_cache().lock().unwrap();
            assert!(cache.is_empty());
        }

        let ctx = make_test_ctx(
            "test-cache-host",
            "nixos",
            "x86_64-linux",
            "123",
            "10.0.0.1",
        );
        {
            let mut cache = get_context_cache().lock().unwrap();
            cache.insert("test-cache-host".to_string(), ctx.clone());
        }

        let loaded = RuntimeContext::load("test-cache-host").unwrap();
        assert_eq!(loaded.hostname, "test-cache-host");
        assert_eq!(loaded.username, "nixos");
        assert!(loaded.has_disko);
    }
}
