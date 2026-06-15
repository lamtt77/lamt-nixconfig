pub(crate) mod commands;

use super::{Provider, ProviderKind, ProviderState, TargetEndpoint};
use crate::context::RuntimeContext;
use crate::process::{CommandExecutor, Logger};
use crate::remote::ssh::{SshOptions, SshOutputMode, SshSession, WARN_WEAK_CRYPTO_OPTION};
use crate::workflow::artifact::DeploymentArtifact;
use commands::sanitize_name;
use std::sync::Mutex;

const WSL_OPERATION_KEEPALIVE_SECS: u32 = 21_600;

pub struct WslKeepalive {
	child: Option<std::process::Child>,
}

impl WslKeepalive {
	fn recorded() -> Self {
		Self { child: None }
	}
}

impl Drop for WslKeepalive {
	fn drop(&mut self) {
		if let Some(mut child) = self.child.take() {
			let _ = child.kill();
			let _ = child.wait();
		}
	}
}

pub fn start_keepalive_session(
	windows_connection: &str,
	distribution: &str,
	timeout_secs: u32,
) -> Result<WslKeepalive, Box<dyn std::error::Error>> {
	if CommandExecutor::is_recording() {
		return Ok(WslKeepalive::recorded());
	}

	let command = commands::start_keepalive(distribution, timeout_secs);
	let mut child = SshSession::parse_with_options(windows_connection, SshOptions::control_plane())
		.spawn_silent(&command)?;
	std::thread::sleep(std::time::Duration::from_secs(1));
	if let Some(status) = child.try_wait()? {
		return Err(
			format!("WSL keepalive session on {} exited immediately with {}", windows_connection, status)
				.into(),
		);
	}
	Ok(WslKeepalive { child: Some(child) })
}

pub struct WslProvider {
	ctx: RuntimeContext,
	windows_connection: String,
	windows_host: String,
	distribution: String,
	install_root: String,
	guest_host: String,
	bootstrap_user: String,
	transport: String,
	keepalive_session: Mutex<Option<WslKeepalive>>,
	logger: Logger,
}

impl WslProvider {
	pub fn new(ctx: &RuntimeContext, logger: Logger) -> Self {
		let config = &ctx.deployment.wsl;
		Self {
			ctx: ctx.clone(),
			windows_connection: format!("{}@{}", config.windows_user, config.windows_host),
			windows_host: config.windows_host.clone(),
			distribution: config.distribution.clone(),
			install_root: config.install_root.clone(),
			guest_host: config.guest_host.clone(),
			bootstrap_user: config.bootstrap_user.clone(),
			transport: config.transport.clone(),
			keepalive_session: Mutex::new(None),
			logger,
		}
	}

	fn execute(&self, command: &str, logger: Logger) -> Result<String, Box<dyn std::error::Error>> {
		SshSession::parse_with_options(&self.windows_connection, SshOptions::control_plane())
			.execute(command, logger)
	}

	fn remote_archive_name(&self, checksum: &str) -> String {
		format!("nxd-{}-{}.tar.gz", sanitize_name(&self.distribution), checksum)
	}

	fn ensure_operation_keepalive(&self) -> Result<(), Box<dyn std::error::Error>> {
		let mut session = self.keepalive_session.lock().map_err(|_| "WSL keepalive lock poisoned")?;
		if session.is_some() {
			return Ok(());
		}
		*session = Some(start_keepalive_session(
			&self.windows_connection,
			&self.distribution,
			WSL_OPERATION_KEEPALIVE_SECS,
		)?);
		Ok(())
	}

	pub fn preflight(&self) -> Result<(), Box<dyn std::error::Error>> {
		self.execute("cmd.exe /d /c exit 0", Logger::silent()).map_err(|error| {
			format!("Windows preflight failed at OpenSSH public-key authentication: {}", error)
		})?;
		for (label, command) in [
			("PowerShell", commands::check_powershell()),
			("wsl.exe availability", commands::check_wsl_command()),
			("supported WSL version", commands::check_wsl_version()),
			("WSL distribution access", commands::check_wsl_access()),
			("install-root permission", commands::check_install_root(&self.install_root)),
		] {
			self
				.execute(&command, self.logger.clone())
				.map_err(|error| format!("Windows preflight failed at {}: {}", label, error))?;
		}
		Ok(())
	}

	pub fn bootstrap_ssh(&self, public_key: &str) -> Result<(), Box<dyn std::error::Error>> {
		let session =
			SshSession::parse_with_options(&self.windows_connection, SshOptions::password_bootstrap());
		let result = session
			.run(&commands::install_windows_authorized_key(public_key), SshOutputMode::Interactive)?;
		if !result.status.success() {
			return Err(
				format!(
					"Windows SSH bootstrap failed with status {}; see the SSH diagnostic above. The configured target is {}",
					result.status
					, self.windows_connection
				)
				.into(),
			);
		}

		self
			.execute("cmd.exe /d /c exit 0", Logger::silent())
			.map(|_| ())
			.map_err(|error| {
				format!(
					"Public key was installed but key-only verification failed: {}. Check the Windows OpenSSH authorized-key path and ACL.",
					error
				)
				.into()
			})
	}

	fn normalized_lines(output: &str) -> impl Iterator<Item = String> + '_ {
		output
			.lines()
			.map(|line| line.replace('\0', "").trim().to_string())
			.filter(|line| !line.is_empty())
	}

	fn distribution_state(&self, all: &str, running: &str) -> ProviderState {
		let exists =
			Self::normalized_lines(all).any(|line| line.eq_ignore_ascii_case(&self.distribution));
		if !exists {
			return ProviderState::Missing;
		}
		if Self::normalized_lines(running).any(|line| line.eq_ignore_ascii_case(&self.distribution)) {
			ProviderState::Running
		} else {
			ProviderState::Present
		}
	}

	fn cleanup_remote_archive(&self, archive_name: &str) {
		let _ = self.execute(&commands::remove_archive(archive_name), Logger::silent());
	}

	fn transfer_artifact(
		&self,
		artifact: &DeploymentArtifact,
		destination_name: &str,
	) -> Result<(), Box<dyn std::error::Error>> {
		let destination = format!("{}:{}", self.windows_connection, destination_name);
		match artifact {
			DeploymentArtifact::Local { path, .. } => {
				let source = path.to_string_lossy().to_string();
				let args = SshOptions::control_plane().scp_args(&source, &destination);
				let args_ref = args.iter().map(String::as_str).collect::<Vec<_>>();
				CommandExecutor::execute("scp", &args_ref, self.logger.clone())?;
			}
			DeploymentArtifact::Remote { connection, path, checksum, .. } => {
				let known_hosts = crate::remote::known_hosts::trusted_entries(&self.windows_host)?;
				let known_hosts_path = format!(
					"/tmp/nxd-windows-known-hosts-{}-{}",
					checksum,
					crate::workspace::local::unique_suffix()
				);
				let prepare_known_hosts =
					format!("umask 077 && cat > {}", crate::process::shell_escape(&known_hosts_path));
				CommandExecutor::execute_ssh_with_stdin(
					connection,
					&prepare_known_hosts,
					&known_hosts,
					Logger::silent(),
				)?;
				let size_command = commands::archive_size(destination_name);
				let progress_probe = format!(
					"ssh -o {} -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile={} -o LogLevel=ERROR {} {}",
					WARN_WEAK_CRYPTO_OPTION,
					crate::process::shell_escape(&known_hosts_path),
					crate::process::shell_escape(&self.windows_connection),
					crate::process::shell_escape(&size_command)
				);
				let command = format!(
					"total=$(stat -c %s {source}) || exit 1; \
					 echo \"WSL artifact transfer: 0/$total bytes (0%)\"; \
					 scp -o {warn_weak_crypto} -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile={known_hosts} -o LogLevel=ERROR {source} {destination} & \
					 pid=$!; \
					 while kill -0 \"$pid\" 2>/dev/null; do \
					   sleep 3; \
					   current=$({progress_probe} 2>/dev/null | tr -d '\\r\\000' | tail -n 1); \
					   case \"$current\" in ''|*[!0-9]*) continue ;; esac; \
					   if [ \"$total\" -gt 0 ]; then percent=$((current * 100 / total)); else percent=0; fi; \
					   echo \"WSL artifact transfer: $current/$total bytes ($percent%)\"; \
					 done; \
					 wait \"$pid\"; \
					 echo \"WSL artifact transfer: $total/$total bytes (100%)\"",
					source = crate::process::shell_escape(path),
					warn_weak_crypto = WARN_WEAK_CRYPTO_OPTION,
					known_hosts = crate::process::shell_escape(&known_hosts_path),
					destination = crate::process::shell_escape(&destination),
					progress_probe = progress_probe
				);
				let transfer = CommandExecutor::execute_ssh(connection, &command, self.logger.clone())
					.map_err(|error| -> Box<dyn std::error::Error> {
						format!(
							"Direct WSL artifact transfer from {} to {} failed: {}",
							connection, self.windows_connection, error
						)
						.into()
					});
				let cleanup = format!("rm -f {}", crate::process::shell_escape(&known_hosts_path));
				let _ = CommandExecutor::execute_ssh(connection, &cleanup, Logger::silent());
				transfer?;
			}
		}
		Ok(())
	}
}

impl Provider for WslProvider {
	fn kind(&self) -> ProviderKind {
		ProviderKind::Wsl
	}

	fn resource_identity(&self) -> String {
		format!("WSL distribution '{}' on {}", self.distribution, self.windows_host)
	}

	fn inspect(&self) -> Result<ProviderState, Box<dyn std::error::Error>> {
		let output = self.execute(&commands::list_distributions(), Logger::silent())?;
		let running = self.execute(&commands::list_running_distributions(), Logger::silent())?;
		Ok(self.distribution_state(&output, &running))
	}

	fn create(&self) -> Result<(), Box<dyn std::error::Error>> {
		self.preflight()?;
		let artifact =
			crate::workflow::artifact::build_minimal_wsl_for_deployment(&self.ctx, self.logger.clone())?;
		let archive_name = self.remote_archive_name(artifact.checksum());
		let partial_name =
			format!("{}.{}.partial", archive_name, crate::workspace::local::unique_suffix());
		let result = (|| -> Result<(), Box<dyn std::error::Error>> {
			let state = self.execute(
				&commands::prepare_archive(&archive_name, artifact.checksum()),
				Logger::silent(),
			)?;
			if state.replace('\0', "").trim() == "MATCH" {
				info!(
					self.logger,
					"Reusing checksum-matched WSL bootstrap artifact on {} from {}.",
					self.windows_host,
					artifact.producer_label()
				);
			} else {
				info!(
					self.logger,
					"Transferring WSL bootstrap artifact directly from {} to {}...",
					artifact.producer_label(),
					self.windows_host
				);
				self.cleanup_remote_archive(&partial_name);
				self.transfer_artifact(&artifact, &partial_name)?;
				self.execute(
					&commands::promote_archive(&partial_name, &archive_name, artifact.checksum()),
					self.logger.clone(),
				)?;
			}

			self.execute(
				&commands::verify_archive(&archive_name, artifact.checksum()),
				self.logger.clone(),
			)?;
			self.execute(
				&commands::import_distribution(&self.distribution, &self.install_root, &archive_name),
				self.logger.clone(),
			)?;
			self.execute(
				&commands::cleanup_archive_cache(&self.distribution, &archive_name),
				Logger::silent(),
			)?;
			Ok(())
		})();
		self.cleanup_remote_archive(&partial_name);
		artifact.cleanup(Logger::silent());
		result?;
		self.execute(&commands::start_distribution(&self.distribution), self.logger.clone())?;
		Ok(())
	}

	fn destroy(&self) -> Result<(), Box<dyn std::error::Error>> {
		if self.inspect()? != ProviderState::Missing {
			self.execute(&commands::unregister_distribution(&self.distribution), self.logger.clone())?;
		}
		Ok(())
	}

	fn get_ip(&self, poll: bool) -> Result<String, Box<dyn std::error::Error>> {
		if !self.guest_host.is_empty() {
			return Ok(self.guest_host.clone());
		}
		if !self.ctx.target_ip.is_empty()
			&& self.ctx.target_ip != self.ctx.hostname
			&& crate::fleet::resolution::is_ssh_reachable(&self.ctx.target_ip)
		{
			return Ok(self.ctx.target_ip.clone());
		}
		let attempts = if poll { 30 } else { 1 };
		for _ in 0..attempts {
			if let Ok(output) = self.execute(&commands::guest_ip(&self.distribution), Logger::silent()) {
				let ip = output.replace('\0', "").trim().to_string();
				if let Ok(address) = ip.parse::<std::net::IpAddr>()
					&& crate::fleet::resolution::is_valid_target_ip(&address)
				{
					return Ok(ip);
				}
			}
			if poll {
				std::thread::sleep(std::time::Duration::from_secs(2));
			}
		}
		Err(format!("WSL distribution '{}' returned no guest IP", self.distribution).into())
	}

	fn endpoint(&self, poll: bool) -> Result<TargetEndpoint, Box<dyn std::error::Error>> {
		let host = self.get_ip(poll)?;
		let transport = self.transport_mode(&host);
		if transport == WslTransport::WindowsJump {
			self.ensure_operation_keepalive()?;
		}
		let windows_jump = self.windows_connection.clone();
		let proxy_jump = match transport {
			WslTransport::Direct => None,
			WslTransport::WindowsJump => Some(windows_jump),
		};
		if poll && transport == WslTransport::WindowsJump {
			wait_for_guest_ssh(&self.bootstrap_user, &host, proxy_jump.as_deref())?;
		}
		Ok(TargetEndpoint::Ssh { host, port: 22, proxy_jump })
	}
}

impl Drop for WslProvider {
	fn drop(&mut self) {
		if let Ok(session) = self.keepalive_session.get_mut() {
			drop(session.take());
		}
	}
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum WslTransport {
	Direct,
	WindowsJump,
}

impl WslProvider {
	fn transport_mode(&self, guest_host: &str) -> WslTransport {
		if self.transport == "windows"
			|| (self.transport == "auto" && !crate::fleet::resolution::is_ssh_reachable(guest_host))
		{
			WslTransport::WindowsJump
		} else {
			WslTransport::Direct
		}
	}
}

fn wait_for_guest_ssh(
	user: &str,
	host: &str,
	proxy_jump: Option<&str>,
) -> Result<(), Box<dyn std::error::Error>> {
	let connection = format!("{}@{}", user, host);
	let options = SshOptions::probe(3).with_proxy_jump(proxy_jump.map(str::to_string));
	let mut last_error = String::new();
	for _ in 0..30 {
		match crate::remote::ssh::verify_ssh_connection_with_opts(&connection, &options) {
			Ok(()) => return Ok(()),
			Err(error) => last_error = error,
		}
		std::thread::sleep(std::time::Duration::from_secs(2));
	}
	Err(format!("WSL guest SSH did not become ready at {}: {}", host, last_error).into())
}

#[cfg(test)]
mod tests {
	use super::*;

	fn make_test_ctx(
		hostname: &str,
		username: &str,
		system: &str,
		distribution: &str,
	) -> RuntimeContext {
		RuntimeContext {
			hostname: hostname.to_string(),
			target_ip: "10.0.0.1".to_string(),
			username: username.to_string(),
			system: system.to_string(),
			deployment: crate::fleet::metadata::DeploymentConfig {
				target_ip: "10.0.0.1".to_string(),
				ssh_proxy_jump: String::new(),
				builder: String::new(),
				low_mem: String::new(),
				substitute_on_destination: false,
				enable_local_cache: true,
				vmid: String::new(),
				disk_size: String::new(),
				tailscale_namespace: String::new(),
				proxmox: crate::fleet::metadata::ProxmoxConfig {
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
					cloud_init: crate::fleet::metadata::CloudInitConfig {
						image: String::new(),
						user: String::new(),
						ipconfig0: String::new(),
						ipconfig1: String::new(),
					},
					iso: crate::fleet::metadata::ProxmoxIsoConfig {
						flavor: "std".to_string(),
						storage: String::new(),
						custom_path: String::new(),
					},
				},
				digitalocean: crate::fleet::metadata::DigitalOceanConfig {
					region: String::new(),
					size: String::new(),
					image: String::new(),
				},
				vmware: crate::fleet::metadata::VmwareConfig { vmx_path: String::new() },
				wsl: crate::fleet::metadata::WslConfig {
					enable: true,
					windows_host: "win-host".to_string(),
					windows_user: "win-user".to_string(),
					distribution: distribution.to_string(),
					install_root: "C:\\WSL\\NixOS".to_string(),
					..Default::default()
				},
			},

			is_ip_overridden: false,
			flake_ref: "path:.".to_string(),
			source_store_path: None,
			secret_store_path: None,
			has_disko: false,
			build_system: true,
			wsl: true,
			role: None,
			tags: Vec::new(),
			cross: None,
			features: Vec::new(),
		}
	}

	#[test]
	fn sanitizes_remote_archive_names() {
		assert_eq!(sanitize_name("NixOS Test_1"), "NixOS-Test-1");
	}

	#[test]
	fn archive_names_are_content_addressed() {
		let ctx = make_test_ctx("my-host", "nixos", "x86_64-linux", "NixOS Target");
		let provider = WslProvider::new(&ctx, Logger::silent());

		assert_eq!(provider.remote_archive_name("abc123"), "nxd-NixOS-Target-abc123.tar.gz");
		assert_eq!(provider.windows_connection, "win-user@win-host");
	}

	#[test]
	fn remote_artifacts_transfer_from_builder_directly_to_windows() {
		CommandExecutor::start_recording();
		CommandExecutor::register_mock(
			"ssh-keygen -F win-host",
			"win-host ssh-ed25519 AAAAC3NzaDirectTransfer\n",
		);

		let ctx = make_test_ctx("my-host", "nixos", "x86_64-linux", "NixOS-Target");
		let provider = WslProvider::new(&ctx, Logger::silent());
		let artifact = DeploymentArtifact::Remote {
			connection: "deploy@utils".to_string(),
			path: "/tmp/nxd-minimal-wsl-test.tar.gz".to_string(),
			checksum: "abc123".to_string(),
			persistent: true,
		};

		provider.transfer_artifact(&artifact, "nxd-NixOS-Target-abc123.tar.gz").unwrap();
		let commands = CommandExecutor::stop_recording().unwrap();
		CommandExecutor::clear_mocks();

		assert!(commands.iter().any(|command| {
			command.contains("deploy@utils")
				&& command
					.contains("scp -o WarnWeakCrypto=no-pq-kex -o BatchMode=yes -o StrictHostKeyChecking=yes")
				&& command.matches("WarnWeakCrypto=no-pq-kex").count() >= 2
				&& command.contains("win-user@win-host:nxd-NixOS-Target-abc123.tar.gz")
				&& command.contains("WSL artifact transfer:")
		}));
		assert!(commands.iter().any(|command| {
			command.contains("deploy@utils")
				&& command.contains("rm -f /tmp/nxd-windows-known-hosts-abc123-")
		}));
		assert!(!commands.iter().any(|command| command.starts_with("scp ")));
	}

	#[test]
	fn test_wsl_provider_inspect_states() {
		let ctx = make_test_ctx("my-host", "nixos", "x86_64-linux", "NixOS-Target");
		let provider = WslProvider::new(&ctx, Logger::silent());

		assert_eq!(provider.distribution_state("Ubuntu\nDebian\n", ""), ProviderState::Missing);
		assert_eq!(
			provider.distribution_state("Ubuntu\nNixOS-Target\nDebian\n", ""),
			ProviderState::Present
		);
		assert_eq!(
			provider.distribution_state(
				"U\0b\0u\0n\0t\0u\0\nN\0i\0x\0O\0S\0-\0T\0a\0r\0g\0e\0t\0\n",
				"N\0i\0x\0O\0S\0-\0T\0a\0r\0g\0e\0t\0\n"
			),
			ProviderState::Running
		);
	}

	#[test]
	fn test_wsl_provider_preflight() {
		CommandExecutor::start_recording();

		let ctx = make_test_ctx("my-host", "nixos", "x86_64-linux", "NixOS-Target");
		let provider = WslProvider::new(&ctx, Logger::silent());
		assert!(provider.preflight().is_ok());

		CommandExecutor::stop_recording();
		CommandExecutor::clear_mocks();
	}
}
