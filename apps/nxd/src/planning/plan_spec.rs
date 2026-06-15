#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostSpec {
	pub hostname: String,
	pub username: Option<String>,
	pub ip: Option<String>,
}

pub fn parse_host_spec(spec: &str) -> HostSpec {
	let mut username = None;
	let mut hostname = spec.trim().to_string();
	let mut ip = None;

	if let Some(at_pos) = hostname.find('@') {
		let parsed_user = hostname[..at_pos].trim().to_string();
		if !parsed_user.is_empty() {
			username = Some(parsed_user);
		}
		hostname = hostname[at_pos + 1..].trim().to_string();
	}

	if let Some(eq_pos) = hostname.find('=') {
		let parsed_ip = hostname[eq_pos + 1..].trim().to_string();
		if !parsed_ip.is_empty() {
			ip = Some(parsed_ip);
		}
		hostname = hostname[..eq_pos].trim().to_string();
	}

	HostSpec { hostname, username, ip }
}

pub fn split_hosts(hosts: &str) -> Vec<String> {
	hosts.split(',').map(|host| host.trim().to_string()).filter(|host| !host.is_empty()).collect()
}
