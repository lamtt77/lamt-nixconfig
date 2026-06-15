use crate::context::FlakeMetadata;
use crate::planning::parse_host_spec;
use std::collections::HashMap;

fn glob_match(pattern: &str, text: &str) -> bool {
	fn match_helper(p: &[char], t: &[char]) -> bool {
		if p.is_empty() {
			return t.is_empty();
		}
		if p[0] == '*' {
			if match_helper(&p[1..], t) {
				return true;
			}
			if !t.is_empty() && match_helper(p, &t[1..]) {
				return true;
			}
			return false;
		}
		if t.is_empty() {
			return false;
		}
		if p[0] == '?' || p[0] == t[0] {
			return match_helper(&p[1..], &t[1..]);
		}
		false
	}

	let p_chars: Vec<char> = pattern.chars().collect();
	let t_chars: Vec<char> = text.chars().collect();
	match_helper(&p_chars, &t_chars)
}

pub fn resolve_host_selectors(
	inventory: &HashMap<String, FlakeMetadata>,
	selectors: &str,
) -> Result<Vec<String>, String> {
	if selectors.trim().is_empty() {
		return Err("Selector list cannot be empty".to_string());
	}

	let mut result = Vec::new();
	let mut seen: HashMap<String, (usize, bool)> = HashMap::new();

	fn add_resolved_host(
		result: &mut Vec<String>,
		seen: &mut HashMap<String, (usize, bool)>,
		hostname: String,
		spec: String,
		is_exact: bool,
	) {
		if let Some((index, existing_is_exact)) = seen.get_mut(&hostname) {
			if is_exact {
				result[*index] = spec;
				*existing_is_exact = true;
			}
			return;
		}

		seen.insert(hostname, (result.len(), is_exact));
		result.push(spec);
	}

	for selector in selectors.split(',') {
		let trimmed = selector.trim();
		if trimmed.is_empty() {
			return Err("Empty selector element is invalid".to_string());
		}

		if trimmed.starts_with('@') && trimmed.len() > 1 {
			let tag = &trimmed[1..];
			let mut matches = Vec::new();
			for (hostname, meta) in inventory {
				if meta.tags.iter().any(|t| t == tag) {
					matches.push(hostname.clone());
				}
			}
			if matches.is_empty() {
				return Err(format!("Tag selector '{}' matched no hosts", trimmed));
			}
			matches.sort();
			for host in matches {
				add_resolved_host(&mut result, &mut seen, host.clone(), host, false);
			}
		} else if trimmed.contains('*') || trimmed.contains('?') {
			let mut matches = Vec::new();
			for hostname in inventory.keys() {
				if glob_match(trimmed, hostname) {
					matches.push(hostname.clone());
				}
			}
			if matches.is_empty() {
				return Err(format!("Glob selector '{}' matched no hosts", trimmed));
			}
			matches.sort();
			for host in matches {
				add_resolved_host(&mut result, &mut seen, host.clone(), host, false);
			}
		} else {
			let spec = parse_host_spec(trimmed);
			if !inventory.contains_key(&spec.hostname) {
				return Err(format!("Host '{}' not found in inventory", spec.hostname));
			}
			add_resolved_host(&mut result, &mut seen, spec.hostname.clone(), trimmed.to_string(), true);
		}
	}

	Ok(result)
}

#[cfg(test)]
mod tests {
	use super::*;

	fn make_dummy_metadata(role: Option<&str>, tags: &[&str]) -> FlakeMetadata {
		use crate::context::{
			CloudInitConfig, DeploymentConfig, DigitalOceanConfig, ProxmoxConfig, VmwareConfig,
		};
		FlakeMetadata {
			deployment: DeploymentConfig {
				target_ip: String::new(),
				ssh_proxy_jump: String::new(),
				builder: String::new(),
				low_mem: String::new(),
				substitute_on_destination: false,
				enable_local_cache: true,
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
					net0: String::new(),
					net1: String::new(),
					bootstrap: crate::fleet::metadata::ProxmoxBootstrapConfig::default(),
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
				vmware: VmwareConfig { vmx_path: String::new() },
				wsl: Default::default(),
			},
			system: "x86_64-linux".to_string(),
			user: "nixos".to_string(),
			has_disko: false,
			build_system: true,
			wsl: false,
			role: role.map(String::from),
			tags: tags.iter().map(|t| t.to_string()).collect(),
			cross: None,
			features: Vec::new(),
		}
	}

	#[test]
	fn test_glob_match() {
		assert!(glob_match("router-*", "router-main"));
		assert!(glob_match("router-*", "router-backup"));
		assert!(!glob_match("router-?", "router-main"));
		assert!(glob_match("router-?", "router-a"));
	}

	#[test]
	fn test_resolve_selectors() {
		let mut inventory = HashMap::new();
		inventory
			.insert("router-main".to_string(), make_dummy_metadata(Some("router"), &["router", "infra"]));
		inventory.insert(
			"router-backup".to_string(),
			make_dummy_metadata(Some("router"), &["router", "infra"]),
		);
		inventory.insert("medo".to_string(), make_dummy_metadata(Some("server"), &["server"]));

		// Exact match
		let res = resolve_host_selectors(&inventory, "medo").unwrap();
		assert_eq!(res, vec!["medo"]);

		// Exact selectors preserve user order
		let res = resolve_host_selectors(&inventory, "medo,router-main").unwrap();
		assert_eq!(res, vec!["medo", "router-main"]);

		// Glob match
		let res = resolve_host_selectors(&inventory, "router-*").unwrap();
		assert_eq!(res, vec!["router-backup", "router-main"]);

		// Tag match
		let res = resolve_host_selectors(&inventory, "@infra").unwrap();
		assert_eq!(res, vec!["router-backup", "router-main"]);

		// Precedence override
		let res = resolve_host_selectors(&inventory, "@infra,deploy@router-main=10.0.0.1").unwrap();
		assert_eq!(res, vec!["router-backup", "deploy@router-main=10.0.0.1"]);

		// Mixed selectors preserve selector order while keeping sorted expansion per selector.
		let res = resolve_host_selectors(&inventory, "medo,@infra").unwrap();
		assert_eq!(res, vec!["medo", "router-backup", "router-main"]);
	}

	#[test]
	fn test_rejects_empty_selector_elements() {
		let inventory = HashMap::new();
		assert!(resolve_host_selectors(&inventory, "").is_err());
		assert!(resolve_host_selectors(&inventory, "router-main,").is_err());
	}

	#[test]
	fn test_rejects_unknown_selectors() {
		let mut inventory = HashMap::new();
		inventory
			.insert("router-main".to_string(), make_dummy_metadata(Some("router"), &["router", "infra"]));

		assert!(resolve_host_selectors(&inventory, "missing").is_err());
		assert!(resolve_host_selectors(&inventory, "server-*").is_err());
		assert!(resolve_host_selectors(&inventory, "@server").is_err());
	}
}
