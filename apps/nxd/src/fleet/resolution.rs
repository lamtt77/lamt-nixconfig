use crate::context::RuntimeContext;
use crate::fleet::local::is_local_target;
use crate::process::Logger;
use crate::providers::{ProviderIpMode, get_provider_ip};

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
) -> Option<Box<dyn crate::providers::Provider>> {
	if ctx.deployment.wsl.enable {
		Some(Box::new(crate::providers::wsl::WslProvider::new(ctx, logger)))
	} else if !ctx.deployment.vmid.is_empty() && !ctx.deployment.proxmox.host.is_empty() {
		Some(Box::new(crate::providers::proxmox::ProxmoxProvider::new(ctx, logger)))
	} else if !ctx.deployment.vmware.vmx_path.is_empty() {
		Some(Box::new(crate::providers::vmware::VmwareProvider::new(ctx, logger)))
	} else if !ctx.deployment.digitalocean.region.is_empty() {
		Some(Box::new(crate::providers::digitalocean::DigitalOceanProvider::new(ctx, logger)))
	} else {
		None
	}
}

pub fn ping_hostname_for_ip(hostname: &str) -> Option<String> {
	use std::process::{Command, Stdio};
	use std::time::{Duration, Instant};

	let mut child = match Command::new("ping")
		.args(["-c", "1", hostname])
		.stdout(Stdio::piped())
		.stderr(Stdio::null())
		.spawn()
	{
		Ok(c) => c,
		Err(_) => return None,
	};

	let start = Instant::now();
	let timeout = Duration::from_millis(1000);

	loop {
		if let Ok(Some(status)) = child.try_wait() {
			if status.success()
				&& let Some(mut stdout) = child.stdout.take()
			{
				use std::io::Read;
				let mut out = String::new();
				if stdout.read_to_string(&mut out).is_ok()
					&& let Some(start_idx) = out.find('(')
					&& let Some(end_idx) = out[start_idx + 1..].find(')')
				{
					let ip = &out[start_idx + 1..start_idx + 1 + end_idx];
					if let Ok(parsed_ip) = ip.parse::<std::net::IpAddr>()
						&& is_valid_target_ip(&parsed_ip)
					{
						return Some(ip.to_string());
					}
				}
			}
			break;
		}

		if start.elapsed() > timeout {
			let _ = child.kill();
			break;
		}
		std::thread::sleep(Duration::from_millis(50));
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
		info!(logger, "Using overridden target IP for {}: {}", ctx.hostname, ctx.target_ip);
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
		&& let Ok(ip_addr) = ctx.target_ip.parse::<std::net::IpAddr>()
		&& is_valid_target_ip(&ip_addr)
		&& is_ssh_reachable(&ctx.target_ip)
	{
		return ctx.target_ip.clone();
	}

	// 1. Try Ping first (resolves via MagicDNS / Tailscale / mDNS)
	let mut dns_ip = None;
	if let Some(ip) = ping_hostname_for_ip(&ctx.hostname) {
		if is_ssh_reachable(&ip) {
			info!(
				logger,
				"Resolved dynamic IP via ping (MagicDNS/Tailscale/LAN) for {}: {}", ctx.hostname, ip
			);
			return ip;
		}
		info!(logger, "Pinged IP {} for {} is unreachable. Trying provider IP...", ip, ctx.hostname);
		dns_ip = Some(ip);
	}

	// 2. Try provider resolution (if Ping failed or was unreachable, or if deploy preferred it)
	if (should_prefer_provider_ip(deploy_active, provider.is_some()) || dns_ip.is_none())
		&& let Some(provider) = provider.as_ref()
		&& let Ok(ip) = get_provider_ip(provider.as_ref(), ProviderIpMode::NonPolling)
		&& !ip.is_empty()
	{
		info!(logger, "Resolved target IP via provider for {}: {}", ctx.hostname, ip);
		return ip;
	}

	// 3. Fall back to provider resolution again (in case ping had an unreachable IP)
	if let Some(provider) = provider
		&& let Ok(ip) = get_provider_ip(provider.as_ref(), ProviderIpMode::NonPolling)
		&& !ip.is_empty()
	{
		info!(logger, "Resolved target IP via provider fallback for {}: {}", ctx.hostname, ip);
		return ip;
	}

	// 4. Last resort: use the Pinged IP if found, otherwise the config target_ip
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
