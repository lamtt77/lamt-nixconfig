use super::proxmox::ProxmoxProvider;
use crate::fleet::resolution::is_valid_target_ip;
use std::thread;
use std::time::Duration;

pub fn get_ip(
	provider: &ProxmoxProvider,
	poll: bool,
) -> Result<String, Box<dyn std::error::Error>> {
	if provider.pxe || !provider.ssh_proxy_jump.is_empty() {
		return Ok(provider.target_ip.clone());
	}

	// If static bootstrap IP is configured, try checking SSH reachability first
	if !provider.bootstrap.static_ip.is_empty()
		&& crate::fleet::resolution::is_ssh_reachable(&provider.bootstrap.static_ip)
	{
		info!(
			provider.logger,
			"Static bootstrap IP {} is already reachable via SSH. Skipping injection.",
			provider.bootstrap.static_ip
		);
		return Ok(provider.bootstrap.static_ip.clone());
	}

	// Scan for VM MAC address to find assigned DHCP IP
	info!(provider.logger, "Locating Proxmox VM {} IP address...", provider.vmid);
	let mac_cmd =
		format!("qm config {} | grep -E '^{}:'", provider.vmid, provider.bootstrap.interface);
	let config_out = provider.execute_silent(&mac_cmd)?;

	// Extract MAC address dynamically from key=value format (e.g. virtio=BC:24:11:7C:F4:10)
	let mac = config_out
		.split([',', ' ', '\n'])
		.find(|part| part.contains('='))
		.and_then(|part| part.split('=').nth(1))
		.map(|val| val.trim().to_lowercase());

	if let Some(mac_addr) = mac {
		info!(provider.logger, "Found VM MAC address: {}. Querying network tables...", mac_addr);

		// If static bootstrap metadata is present, run injection instead of general DHCP discovery
		if !provider.bootstrap.static_ip.is_empty() {
			info!(provider.logger, "Attempting static IP injection via QEMU guest-agent...");

			let mut injected = false;
			for attempt in 1..=10 {
				info!(provider.logger, "Static IP injection attempt {}/10...", attempt);

				// First check if guest agent is responsive
				if is_guest_agent_responsive(provider) {
					// Guest agent is responsive! Run injection script
					let cidr = if provider.bootstrap.subnet.contains('/') {
						provider.bootstrap.subnet.split('/').nth(1).unwrap_or("24")
					} else {
						"24"
					};

					let script = format!(
						r#"#!/bin/sh
set -e
export PATH=$PATH:/run/current-system/sw/bin:/sbin:/usr/sbin:/bin:/usr/bin
systemctl stop dhcpcd systemd-networkd NetworkManager 2>/dev/null || true
mac="{mac_addr}"
iface=$(ip link | grep -B 1 -i "$mac" | head -n 1 | cut -d: -f2 | tr -d " ")
if [ -z "$iface" ]; then
  if [ "{bootstrap_iface}" = "net1" ]; then
    iface="eth1"
  else
    iface="eth0"
  fi
fi
ip link set "$iface" up
target_iface="$iface"
{vlan_script}
ip addr flush dev "$target_iface" 2>/dev/null || true
ip addr add {static_ip}/{cidr} dev "$target_iface"
ip link set "$target_iface" up
{gateway_script}
"#,
						mac_addr = mac_addr,
						bootstrap_iface = provider.bootstrap.interface,
						vlan_script = if let Some(vlan) = provider.bootstrap.vlan {
							format!(
								r#"vlan="{}"
viface="${{iface}}.${{vlan}}"
ip link add link "$iface" name "$viface" type vlan id "$vlan" 2>/dev/null || true
ip addr flush dev "$iface"
target_iface="$viface"
"#,
								vlan
							)
						} else {
							String::new()
						},
						static_ip = provider.bootstrap.static_ip,
						cidr = cidr,
						gateway_script = if !provider.bootstrap.gateway.is_empty() {
							format!(
								"ip route add default via {} dev \"$target_iface\" 2>/dev/null || true",
								provider.bootstrap.gateway
							)
						} else {
							String::new()
						}
					);

					let encoded = base64_encode(script.as_bytes());
					let exec_cmd = format!(
						"qm guest exec {} -- /bin/sh -c \"echo '{}' | base64 -d | /bin/sh\"",
						provider.vmid, encoded
					);

					match provider.execute(&exec_cmd) {
						Ok(_) => {
							info!(provider.logger, "Static IP injection command sent successfully.");
							injected = true;
							break;
						}
						Err(e) => {
							warn!(provider.logger, "Static IP injection command failed: {}", e);
						}
					}
				} else {
					info!(
						provider.logger,
						"QEMU guest-agent is not responsive yet. Retrying in 3 seconds..."
					);
				}
				thread::sleep(Duration::from_secs(3));
			}

			if injected {
				info!(
					provider.logger,
					"Verifying reachability of injected static IP {}...", provider.bootstrap.static_ip
				);
				for _ in 1..=15 {
					if crate::fleet::resolution::is_ssh_reachable(&provider.bootstrap.static_ip) {
						info!(
							provider.logger,
							"Static IP {} is now reachable via SSH.", provider.bootstrap.static_ip
						);
						return Ok(provider.bootstrap.static_ip.clone());
					}
					thread::sleep(Duration::from_secs(2));
				}
				return Err(
					format!(
						"Injected static IP {} was not reachable via SSH after 30 seconds",
						provider.bootstrap.static_ip
					)
					.into(),
				);
			} else {
				return Err(
					"Failed to inject static IP: QEMU guest-agent did not become responsive".into(),
				);
			}
		}

		// Immediate mode (no active polling)
		if !poll {
			if let Some(ip) = resolve_via_guest_agent(provider, &mac_addr) {
				return Ok(ip);
			}
			if let Some(ip) = resolve_via_neigh(provider, &mac_addr, false) {
				return Ok(ip);
			}
			if let Some(ip) = try_subnet_scan(provider, &mac_addr) {
				return Ok(ip);
			}
			return Err("VM IP not resolved immediately and polling is disabled".into());
		}

		// Polling mode (active wait/verify for VM boot/reboot)
		info!(
			provider.logger,
			"VM IP not resolved immediately. Polling hypervisor for boot network status..."
		);

		for attempt in 1..=30 {
			if is_guest_agent_responsive(provider) {
				if let Some(ip) = resolve_via_guest_agent(provider, &mac_addr) {
					info!(provider.logger, "Resolved VM IP {} via guest agent on attempt {}", ip, attempt);
					if crate::fleet::resolution::is_ssh_reachable(&ip) {
						return Ok(ip);
					} else {
						info!(
							provider.logger,
							"IP {} resolved via guest agent, but SSH is not reachable yet. Polling...", ip
						);
					}
				}
			} else {
				if let Some(ip) = resolve_via_neigh(provider, &mac_addr, true)
					&& crate::fleet::resolution::is_ssh_reachable(&ip)
				{
					info!(
						provider.logger,
						"Resolved VM IP {} via host neighbor table on attempt {}", ip, attempt
					);
					return Ok(ip);
				}
				if let Some(ip) = try_subnet_scan(provider, &mac_addr)
					&& crate::fleet::resolution::is_ssh_reachable(&ip)
				{
					info!(provider.logger, "Resolved VM IP {} via subnet scan on attempt {}", ip, attempt);
					return Ok(ip);
				}
			}
			thread::sleep(Duration::from_secs(2));
		}
	}

	Err("Failed to resolve Proxmox VM IP address".into())
}

fn is_guest_agent_responsive(provider: &ProxmoxProvider) -> bool {
	let ping_cmd = format!("timeout 2 qm guest cmd {} ping 2>/dev/null", provider.vmid);
	provider.execute_silent(&ping_cmd).is_ok()
}

fn resolve_via_guest_agent(provider: &ProxmoxProvider, mac_addr: &str) -> Option<String> {
	let guest_cmd =
		format!("timeout 2 qm guest cmd {} network-get-interfaces 2>/dev/null", provider.vmid);
	if let Ok(guest_out) = provider.execute_silent(&guest_cmd)
		&& let Ok(val) = serde_json::from_str::<serde_json::Value>(&guest_out)
		&& let Some(arr) = val.as_array()
	{
		let mut fallback_ipv6 = None;
		for interface in arr {
			if let Some(hw_addr) = interface.get("hardware-address").and_then(|a| a.as_str()) {
				if hw_addr.to_lowercase() != mac_addr.to_lowercase() {
					continue;
				}
			} else {
				continue;
			}

			if let Some(ips) = interface.get("ip-addresses").and_then(|i| i.as_array()) {
				for ip_info in ips {
					if let Some(ip) = ip_info.get("ip-address").and_then(|ip| ip.as_str())
						&& let Some(parsed_ip) = ip.parse::<std::net::IpAddr>().ok().filter(is_valid_target_ip)
					{
						if parsed_ip.is_ipv4() {
							return Some(ip.to_string());
						} else if fallback_ipv6.is_none() {
							fallback_ipv6 = Some(ip.to_string());
						}
					}
				}
			}
		}
		if let Some(ipv6) = fallback_ipv6 {
			return Some(ipv6);
		}
	}
	None
}

fn resolve_via_neigh(provider: &ProxmoxProvider, mac_addr: &str, poll: bool) -> Option<String> {
	let query_cmd = format!("ip neigh | grep -i '{}'", mac_addr);
	if let Ok(ip_out) = provider.execute_silent(&query_cmd) {
		let mut reachable_ip = None;
		let mut stale_ip = None;

		for line in ip_out.lines() {
			let parts: Vec<&str> = line.split_whitespace().collect();
			if parts.is_empty() {
				continue;
			}

			let ip_str = parts[0];
			let state = parts.last().unwrap_or(&"").to_uppercase();

			if ip_str
				.parse::<std::net::IpAddr>()
				.ok()
				.filter(|p| is_valid_target_ip(p) && p.is_ipv4())
				.is_some()
			{
				if state == "REACHABLE" || state == "DELAY" {
					reachable_ip = Some(ip_str.to_string());
				} else if stale_ip.is_none() {
					stale_ip = Some(ip_str.to_string());
				}
			}
		}

		if poll { reachable_ip } else { reachable_ip.or(stale_ip) }
	} else {
		None
	}
}

fn try_subnet_scan(provider: &ProxmoxProvider, mac_addr: &str) -> Option<String> {
	let networks = crate::config::default_networks();
	let scan_targets =
		if networks.is_empty() { vec!["192.168.1.0/24".to_string()] } else { networks };

	for subnet in scan_targets {
		let scan_cmd = format!(
			"nmap -sn -n {} | grep -i '{}' -B 2 | grep 'Nmap scan report' | awk '{{print $NF}}' | tr -d '()'",
			subnet, mac_addr
		);
		if let Ok(ip_out) = provider.execute_silent(&scan_cmd) {
			let ip = ip_out.trim().to_string();
			if !ip.is_empty() && ip.parse::<std::net::IpAddr>().ok().filter(is_valid_target_ip).is_some()
			{
				return Some(ip);
			}
		}
	}
	None
}

fn base64_encode(bytes: &[u8]) -> String {
	const CHARS: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	let mut result = String::with_capacity(bytes.len() * 4 / 3 + 4);
	for chunk in bytes.chunks(3) {
		match chunk.len() {
			3 => {
				let n = ((chunk[0] as u32) << 16) | ((chunk[1] as u32) << 8) | (chunk[2] as u32);
				result.push(CHARS[((n >> 18) & 63) as usize] as char);
				result.push(CHARS[((n >> 12) & 63) as usize] as char);
				result.push(CHARS[((n >> 6) & 63) as usize] as char);
				result.push(CHARS[(n & 63) as usize] as char);
			}
			2 => {
				let n = ((chunk[0] as u32) << 8) | (chunk[1] as u32);
				result.push(CHARS[((n >> 10) & 63) as usize] as char);
				result.push(CHARS[((n >> 4) & 63) as usize] as char);
				result.push(CHARS[((n << 2) & 63) as usize] as char);
				result.push('=');
			}
			1 => {
				let n = chunk[0] as u32;
				result.push(CHARS[((n >> 2) & 63) as usize] as char);
				result.push(CHARS[((n << 4) & 63) as usize] as char);
				result.push('=');
				result.push('=');
			}
			_ => unreachable!(),
		}
	}
	result
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn test_base64_encode() {
		assert_eq!(base64_encode(b""), "");
		assert_eq!(base64_encode(b"f"), "Zg==");
		assert_eq!(base64_encode(b"fo"), "Zm8=");
		assert_eq!(base64_encode(b"foo"), "Zm9v");
		assert_eq!(base64_encode(b"foob"), "Zm9vYg==");
		assert_eq!(base64_encode(b"fooba"), "Zm9vYmE=");
		assert_eq!(base64_encode(b"foobar"), "Zm9vYmFy");
	}
}
