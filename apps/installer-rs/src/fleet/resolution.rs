use crate::context::RuntimeContext;
use crate::fleet::local::is_local_target;
use crate::process::Logger;
use crate::providers::{get_provider_ip, ProviderIpMode};

pub fn is_valid_target_ip(ip: &std::net::IpAddr) -> bool {
    if ip.is_loopback() || ip.is_unspecified() || ip.is_multicast() {
        return false;
    }
    match ip {
        std::net::IpAddr::V4(ipv4) => {
            let octets = ipv4.octets();
            if octets[0] == 169 && octets[1] == 254 {
                return false;
            }
            true
        }
        std::net::IpAddr::V6(ipv6) => {
            let segments = ipv6.segments();
            if (segments[0] & 0xffc0) == 0xfe80 {
                return false;
            }
            true
        }
    }
}

pub fn resolve_provider(
    ctx: &RuntimeContext,
    logger: Logger,
) -> Option<Box<dyn crate::providers::VirtualizationProvider>> {
    if !ctx.deployment.vmid.is_empty() && !ctx.deployment.proxmox.host.is_empty() {
        Some(Box::new(crate::providers::proxmox::ProxmoxProvider::new(
            ctx, logger,
        )))
    } else if !ctx.deployment.vmware.vmx_path.is_empty() {
        Some(Box::new(crate::providers::vmware::VmwareProvider::new(
            ctx, logger,
        )))
    } else if !ctx.deployment.digitalocean.region.is_empty() {
        Some(Box::new(
            crate::providers::digitalocean::DigitalOceanProvider::new(ctx, logger),
        ))
    } else {
        None
    }
}

pub fn resolve_magic_dns_or_tailscale(hostname: &str) -> Option<String> {
    // Try standard DNS resolution (respects local host search domains and MagicDNS)
    use std::net::ToSocketAddrs;
    if let Ok(addrs) = format!("{}:0", hostname).to_socket_addrs() {
        let mut fallback_ipv6 = None;
        for addr in addrs {
            let ip_addr = addr.ip();
            if is_valid_target_ip(&ip_addr) {
                if ip_addr.is_ipv4() {
                    return Some(ip_addr.to_string());
                } else if fallback_ipv6.is_none() {
                    fallback_ipv6 = Some(ip_addr.to_string());
                }
            }
        }
        if let Some(ipv6) = fallback_ipv6 {
            return Some(ipv6);
        }
    }

    None
}

fn should_prefer_provider_ip(deploy_active: bool, has_provider: bool) -> bool {
    deploy_active && has_provider && !crate::config::get_runtime_options().redeploy
}

pub fn is_ssh_reachable(ip: &str) -> bool {
    use std::net::{SocketAddr, TcpStream};
    use std::time::Duration;

    let port = 22;
    if let Ok(ip_addr) = ip.parse::<std::net::IpAddr>() {
        let addr = SocketAddr::new(ip_addr, port);
        TcpStream::connect_timeout(&addr, Duration::from_millis(500)).is_ok()
    } else {
        use std::net::ToSocketAddrs;
        if let Ok(addrs) = format!("{}:{}", ip, port).to_socket_addrs() {
            for addr in addrs {
                if is_valid_target_ip(&addr.ip())
                    && TcpStream::connect_timeout(&addr, Duration::from_millis(500)).is_ok()
                {
                    return true;
                }
            }
        }
        false
    }
}

fn resolve_target_ip_with_deploy_mode(
    ctx: &RuntimeContext,
    deploy_active: bool,
    logger: Logger,
) -> String {
    if ctx.is_ip_overridden {
        info!(
            logger,
            "Using overridden target IP for {}: {}", ctx.hostname, ctx.target_ip
        );
        return ctx.target_ip.clone();
    }

    if is_local_target(ctx) {
        return ctx.target_ip.clone();
    }

    let provider = resolve_provider(ctx, logger.clone());

    // Optimization: if ctx.target_ip is already a valid IP address and is reachable, use it!
    // We bypass this cache optimization if deployment is active and has a provider,
    // as recreation or redeployment may provision a fresh IP we must retrieve from the provider.
    if !should_prefer_provider_ip(deploy_active, provider.is_some())
        && !ctx.target_ip.is_empty()
        && ctx.target_ip != ctx.hostname
    {
        if let Ok(ip_addr) = ctx.target_ip.parse::<std::net::IpAddr>() {
            if is_valid_target_ip(&ip_addr) && is_ssh_reachable(&ctx.target_ip) {
                return ctx.target_ip.clone();
            }
        }
    }

    if should_prefer_provider_ip(deploy_active, provider.is_some()) {
        if let Some(provider) = provider.as_ref() {
            if let Ok(ip) = get_provider_ip(provider.as_ref(), ProviderIpMode::NonPolling) {
                if !ip.is_empty() {
                    info!(
                        logger,
                        "Resolved target IP via provider for {}: {}", ctx.hostname, ip
                    );
                    return ip;
                }
            }
        }
    }

    // 1. Try MagicDNS / Tailscale first for non-provider-first flows
    let mut dns_ip = None;
    if let Some(ip) = resolve_magic_dns_or_tailscale(&ctx.hostname) {
        if is_ssh_reachable(&ip) {
            info!(
                logger,
                "Resolved dynamic IP via MagicDNS/Tailscale for {}: {}", ctx.hostname, ip
            );
            return ip;
        }
        info!(
            logger,
            "MagicDNS/Tailscale IP {} for {} is unreachable. Trying provider IP...",
            ip,
            ctx.hostname
        );
        dns_ip = Some(ip);
    }

    // 2. Fall back to provider resolution
    if let Some(provider) = provider {
        if let Ok(ip) = get_provider_ip(provider.as_ref(), ProviderIpMode::NonPolling) {
            if !ip.is_empty() {
                info!(
                    logger,
                    "Resolved target IP via provider fallback for {}: {}", ctx.hostname, ip
                );
                return ip;
            }
        }
    }

    // 3. Last resort: use the MagicDNS IP if found, otherwise the config target_ip
    if let Some(ip) = dns_ip {
        return ip;
    }

    ctx.target_ip.clone()
}

pub fn resolve_target_ip(ctx: &RuntimeContext, logger: Logger) -> String {
    resolve_target_ip_with_deploy_mode(
        ctx,
        crate::config::get_runtime_options().deploy_active,
        logger,
    )
}

pub fn resolve_target_ip_for_deploy(ctx: &RuntimeContext, logger: Logger) -> String {
    resolve_target_ip_with_deploy_mode(ctx, true, logger)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prefers_provider_ip_only_for_provider_backed_deploys() {
        assert!(should_prefer_provider_ip(true, true));
        assert!(!should_prefer_provider_ip(true, false));
        assert!(!should_prefer_provider_ip(false, true));
        assert!(!should_prefer_provider_ip(false, false));
    }

    #[test]
    fn test_is_ssh_reachable_fails_for_unreachable_ip() {
        assert!(!is_ssh_reachable("192.0.2.1"));
    }
}
