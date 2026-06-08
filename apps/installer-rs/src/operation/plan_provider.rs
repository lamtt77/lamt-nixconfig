#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderKind {
    None,
    Proxmox,
    Vmware,
    DigitalOcean,
    Detected,
}

pub fn provider_kind(
    has_provider: bool,
    proxmox_host: &str,
    vmware_vmx_path: &str,
    digitalocean_region: &str,
) -> ProviderKind {
    if !has_provider {
        ProviderKind::None
    } else if !proxmox_host.is_empty() {
        ProviderKind::Proxmox
    } else if !vmware_vmx_path.is_empty() {
        ProviderKind::Vmware
    } else if !digitalocean_region.is_empty() {
        ProviderKind::DigitalOcean
    } else {
        ProviderKind::Detected
    }
}
