pub fn validate_target_and_hosts(
	target: Option<&String>,
	hosts: Option<&String>,
) -> Result<(), Box<dyn std::error::Error>> {
	if target.is_some() && hosts.is_some() {
		return Err("Error: Cannot specify both -t/--target and --hosts.".into());
	}
	Ok(())
}

pub fn resolve_hosts_arg(hosts_str: &str) -> Result<Vec<String>, Box<dyn std::error::Error>> {
	if hosts_str.trim().is_empty() {
		return Err("Error: --hosts list is empty.".into());
	}

	let inventory = crate::fleet::metadata::load_full_inventory()?;
	crate::fleet::selectors::resolve_host_selectors(&inventory, hosts_str)
		.map_err(|e| format!("Error resolving selectors: {}", e).into())
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn rejects_target_and_hosts_together() {
		let target = "router-main".to_string();
		let hosts = "@router".to_string();

		assert!(validate_target_and_hosts(Some(&target), Some(&hosts)).is_err());
		assert!(validate_target_and_hosts(Some(&target), None).is_ok());
		assert!(validate_target_and_hosts(None, Some(&hosts)).is_ok());
	}
}
