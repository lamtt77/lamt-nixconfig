use super::proxmox::ProxmoxProvider;

pub fn run_preflight_checks(provider: &ProxmoxProvider) -> Result<(), Box<dyn std::error::Error>> {
	// Preflight checks: verify that all configured network bridges exist on Proxmox
	let mut bridges = Vec::new();
	if let Some(b) = extract_bridge_name(&provider.network) {
		bridges.push(b);
	}
	for net in &provider.extra_networks {
		if let Some(b) = extract_bridge_name(net) {
			bridges.push(b);
		}
	}

	if !bridges.is_empty() {
		bridges.sort_unstable();
		bridges.dedup();

		info!(
			provider.logger,
			"Performing preflight checks on Proxmox host {} for bridges: {:?}",
			provider.pve_host,
			bridges
		);
		for bridge in &bridges {
			let bridge_cmd = format!("ip link show {}", bridge);
			if let Err(e) = provider.execute_silent(&bridge_cmd) {
				return Err(
					format!(
						"Preflight check failed: Bridge '{}' does not exist or is inactive on Proxmox host {}: {}",
						bridge, provider.pve_host, e
					)
					.into(),
				);
			}

			// If this is an isolated bridge, check for host IP and physical ports
			if *bridge == "vmbrPxe" || *bridge == "vmbrTestWan" {
				// Check for host IP address (IPv4 or IPv6, excluding link-local)
				let ip_check_cmd = format!("ip -o addr show dev {}", bridge);
				if let Ok(ip_out) = provider.execute_silent(&ip_check_cmd)
					&& (ip_out.contains("inet ")
						|| (ip_out.contains("inet6 ") && !ip_out.contains(" fe80::")))
				{
					return Err(
						format!(
							"Preflight check failed: Isolated bridge '{}' has a host IP address assigned: {}",
							bridge,
							ip_out.trim()
						)
						.into(),
					);
				}

				// Check for physical ports on the bridge using sysfs
				let port_check_cmd = format!(
					"for p in /sys/class/net/{}/brif/*; do [ -d \"$p\" ] && [ -e \"/sys/class/net/$(basename \"$p\")/device\" ] && echo \"$(basename \"$p\")\"; done",
					bridge
				);
				if let Ok(port_out) = provider.execute_silent(&port_check_cmd) {
					let ports: Vec<&str> =
						port_out.lines().map(|l| l.trim()).filter(|l| !l.is_empty()).collect();
					if !ports.is_empty() {
						return Err(
							format!(
								"Preflight check failed: Isolated bridge '{}' has physical ports attached: {:?}",
								bridge, ports
							)
							.into(),
						);
					}
				}
			}
		}
	}

	// If the VM has a proxy jump configured, ensure the proxy jump VM is active
	if !provider.ssh_proxy_jump.is_empty()
		&& let Some(jump_vmid) = crate::context::find_vmid_for_proxy_jump(&provider.ssh_proxy_jump)
	{
		info!(provider.logger, "Checking if proxy jump VM (VMID {}) is running...", jump_vmid);
		let jump_status_cmd = format!("qm status {}", jump_vmid);
		let jump_status = provider.execute_silent(&jump_status_cmd)?;
		if !jump_status.contains("status: running") {
			return Err(format!(
					"Preflight check failed: Proxy jump VM (VMID {}) is not running on Proxmox host {}. Found status: {}",
					jump_vmid, provider.pve_host, jump_status.trim()
				).into());
		}
	}

	Ok(())
}

fn extract_bridge_name(net_str: &str) -> Option<&str> {
	if let Some(pos) = net_str.find("bridge=") {
		let after_bridge = &net_str[pos + 7..];
		if let Some(comma_pos) = after_bridge.find(',') {
			Some(&after_bridge[..comma_pos])
		} else {
			Some(after_bridge)
		}
	} else {
		None
	}
}
