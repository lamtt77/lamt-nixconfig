use crate::process::Logger;

pub const WARN_WEAK_CRYPTO_OPTION: &str = "WarnWeakCrypto=no-pq-kex";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SshTarget {
	pub user: String,
	pub host: String,
}

impl SshTarget {
	pub fn new(user: impl Into<String>, host: impl Into<String>) -> Self {
		Self { user: user.into(), host: host.into() }
	}

	pub fn to_connection_string(&self) -> String {
		if self.user.is_empty() { self.host.clone() } else { format!("{}@{}", self.user, self.host) }
	}
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum KnownHostsMode {
	Disabled,
	File(String),
	Default,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SshOptions {
	pub connect_timeout: Option<u16>,
	pub connection_attempts: Option<u8>,
	pub strict_host_key_checking: bool,
	pub known_hosts: KnownHostsMode,
	pub log_level: Option<String>,
	pub batch_mode: bool,
	pub forward_agent: bool,
	pub password_authentication: bool,
	pub kbd_interactive_authentication: bool,
	pub preferred_authentications: Option<String>,
	pub server_alive_interval: Option<u16>,
	pub server_alive_count_max: Option<u8>,
	pub proxy_jump: Option<String>,
	pub proxy_command: Option<String>,
}

impl SshOptions {
	pub fn password_bootstrap() -> Self {
		Self {
			connect_timeout: Some(10),
			connection_attempts: Some(1),
			strict_host_key_checking: true,
			known_hosts: KnownHostsMode::Default,
			log_level: None,
			batch_mode: false,
			forward_agent: false,
			password_authentication: true,
			kbd_interactive_authentication: true,
			preferred_authentications: Some("password,keyboard-interactive".to_string()),
			server_alive_interval: Some(30),
			server_alive_count_max: Some(3),
			proxy_jump: None,
			proxy_command: None,
		}
	}

	pub fn control_plane() -> Self {
		Self {
			connect_timeout: Some(10),
			connection_attempts: Some(1),
			strict_host_key_checking: true,
			known_hosts: KnownHostsMode::Default,
			log_level: Some("ERROR".to_string()),
			batch_mode: true,
			forward_agent: false,
			password_authentication: false,
			kbd_interactive_authentication: false,
			preferred_authentications: Some("publickey".to_string()),
			server_alive_interval: Some(30),
			server_alive_count_max: Some(3),
			proxy_jump: None,
			proxy_command: None,
		}
	}

	pub fn deployment() -> Self {
		Self {
			connect_timeout: Some(10),
			connection_attempts: Some(1),
			strict_host_key_checking: false,
			known_hosts: KnownHostsMode::Disabled,
			log_level: Some("ERROR".to_string()),
			batch_mode: true,
			forward_agent: true,
			password_authentication: false,
			kbd_interactive_authentication: false,
			preferred_authentications: Some("publickey".to_string()),
			server_alive_interval: Some(30),
			server_alive_count_max: Some(3),
			proxy_jump: None,
			proxy_command: None,
		}
	}

	pub fn probe(timeout_secs: u16) -> Self {
		Self {
			connect_timeout: Some(timeout_secs),
			connection_attempts: Some(1),
			strict_host_key_checking: false,
			known_hosts: KnownHostsMode::Disabled,
			log_level: Some("ERROR".to_string()),
			batch_mode: true,
			forward_agent: false,
			password_authentication: false,
			kbd_interactive_authentication: false,
			preferred_authentications: Some("publickey".to_string()),
			server_alive_interval: None,
			server_alive_count_max: None,
			proxy_jump: None,
			proxy_command: None,
		}
	}

	pub fn rsync() -> Self {
		Self {
			connect_timeout: None,
			connection_attempts: None,
			strict_host_key_checking: false,
			known_hosts: KnownHostsMode::Disabled,
			log_level: Some("ERROR".to_string()),
			batch_mode: false,
			forward_agent: true,
			password_authentication: false,
			kbd_interactive_authentication: false,
			preferred_authentications: None,
			server_alive_interval: None,
			server_alive_count_max: None,
			proxy_jump: None,
			proxy_command: None,
		}
	}

	pub fn nix_copy() -> Self {
		Self {
			connect_timeout: None,
			connection_attempts: None,
			strict_host_key_checking: false,
			known_hosts: KnownHostsMode::Disabled,
			log_level: Some("ERROR".to_string()),
			batch_mode: false,
			forward_agent: false,
			password_authentication: false,
			kbd_interactive_authentication: false,
			preferred_authentications: None,
			server_alive_interval: None,
			server_alive_count_max: None,
			proxy_jump: None,
			proxy_command: None,
		}
	}

	pub fn identity_sync() -> Self {
		Self {
			connect_timeout: None,
			connection_attempts: None,
			strict_host_key_checking: false,
			known_hosts: KnownHostsMode::Disabled,
			log_level: None,
			batch_mode: false,
			forward_agent: true,
			password_authentication: false,
			kbd_interactive_authentication: false,
			preferred_authentications: None,
			server_alive_interval: None,
			server_alive_count_max: None,
			proxy_jump: None,
			proxy_command: None,
		}
	}

	pub fn with_proxy_jump(mut self, proxy: Option<String>) -> Self {
		if let Some(p) = proxy.filter(|p| !p.is_empty()) {
			self.proxy_jump = Some(p);
		}
		self
	}

	pub fn with_proxy_command(mut self, command: Option<String>) -> Self {
		if let Some(c) = command.filter(|c| !c.is_empty()) {
			self.proxy_command = Some(c);
		}
		self
	}

	pub fn ssh_args_before_target(&self) -> Vec<String> {
		let mut args = Vec::new();

		args.push("-o".to_string());
		args.push(WARN_WEAK_CRYPTO_OPTION.to_string());

		if let Some(timeout) = self.connect_timeout {
			args.push("-o".to_string());
			args.push(format!("ConnectTimeout={}", timeout));
		}
		if let Some(attempts) = self.connection_attempts {
			args.push("-o".to_string());
			args.push(format!("ConnectionAttempts={}", attempts));
		}

		args.push("-o".to_string());
		if self.strict_host_key_checking {
			args.push("StrictHostKeyChecking=yes".to_string());
		} else {
			args.push("StrictHostKeyChecking=no".to_string());
		}

		match &self.known_hosts {
			KnownHostsMode::Disabled => {
				args.push("-o".to_string());
				args.push("UserKnownHostsFile=/dev/null".to_string());
			}
			KnownHostsMode::File(path) => {
				args.push("-o".to_string());
				args.push(format!("UserKnownHostsFile={}", path));
			}
			KnownHostsMode::Default => {}
		}

		if let Some(ref level) = self.log_level {
			args.push("-o".to_string());
			args.push(format!("LogLevel={}", level));
		}

		if self.batch_mode {
			args.push("-o".to_string());
			args.push("BatchMode=yes".to_string());
		}

		if self.forward_agent {
			args.push("-A".to_string());
		}

		if !self.password_authentication {
			args.push("-o".to_string());
			args.push("PasswordAuthentication=no".to_string());
		}

		if !self.kbd_interactive_authentication {
			args.push("-o".to_string());
			args.push("KbdInteractiveAuthentication=no".to_string());
		}

		if let Some(ref preferred) = self.preferred_authentications {
			args.push("-o".to_string());
			args.push(format!("PreferredAuthentications={}", preferred));
		}

		if let Some(interval) = self.server_alive_interval {
			args.push("-o".to_string());
			args.push(format!("ServerAliveInterval={}", interval));
		}

		if let Some(count) = self.server_alive_count_max {
			args.push("-o".to_string());
			args.push(format!("ServerAliveCountMax={}", count));
		}

		if let Some(ref proxy) = self.proxy_jump {
			args.push("-J".to_string());
			args.push(proxy.clone());
		}
		if let Some(ref command) = self.proxy_command {
			args.push("-o".to_string());
			args.push(format!("ProxyCommand={}", command));
		}

		args
	}

	pub fn ssh_command_for_shell_pipeline(&self) -> String {
		let args = self.ssh_args_before_target();
		let mut parts = vec!["ssh".to_string()];
		parts.extend(args);
		parts.join(" ")
	}

	pub fn rsync_remote_shell(&self) -> String {
		self.ssh_command_for_shell_pipeline()
	}

	pub fn nix_sshopts(&self) -> String {
		let args = self.ssh_args_before_target();
		let mut opts = Vec::new();
		let mut iter = args.iter();
		while let Some(arg) = iter.next() {
			if let Some(val) = (arg == "-o").then(|| iter.next()).flatten() {
				if val.starts_with("ProxyCommand=") {
					let cmd = val.strip_prefix("ProxyCommand=").unwrap();
					opts.push(format!("-o 'ProxyCommand {}'", cmd));
				} else {
					opts.push(format!("-o {}", val));
				}
			} else if arg == "-A" {
				opts.push("-A".to_string());
			} else if let Some(val) = (arg == "-J").then(|| iter.next()).flatten() {
				opts.push(format!("-J {}", val));
			}
		}
		opts.join(" ")
	}

	pub fn scp_args(&self, source: &str, destination: &str) -> Vec<String> {
		let mut args = self.ssh_args_before_target();
		args.push(source.to_string());
		args.push(destination.to_string());
		args
	}
}

pub fn verify_ssh_connection(connection: &str, timeout_secs: u16) -> Result<(), String> {
	let parts: Vec<&str> = connection.split('@').collect();
	let ip = if parts.len() == 2 { parts[1] } else { connection };
	let mut opts = SshOptions::probe(timeout_secs);
	if let Some(proxy) = crate::context::find_proxy_jump_for_ip(ip) {
		opts.proxy_jump = Some(proxy);
	}
	verify_ssh_connection_with_opts(connection, &opts)
}

pub fn verify_ssh_connection_with_opts(
	connection: &str,
	options: &SshOptions,
) -> Result<(), String> {
	use std::time::{Duration, Instant};

	let mut child = match std::process::Command::new("ssh")
		.args(probe_args_with_opts(connection, "true", options))
		.stdout(std::process::Stdio::piped())
		.stderr(std::process::Stdio::piped())
		.spawn()
	{
		Ok(c) => c,
		Err(e) => return Err(e.to_string()),
	};

	let timeout_secs = options.connect_timeout.unwrap_or(10) as u64;
	// We add a 2 second buffer on top of the ConnectTimeout so SSH has time to fail naturally first
	let timeout = Duration::from_secs(timeout_secs + 2);
	let start = Instant::now();

	loop {
		if let Ok(Some(status)) = child.try_wait() {
			if status.success() {
				return Ok(());
			} else {
				let mut err_msg = String::new();
				if let Some(mut stderr) = child.stderr.take() {
					use std::io::Read;
					let _ = stderr.read_to_string(&mut err_msg);
				}
				return Err(err_msg.trim().to_string());
			}
		}

		if start.elapsed() > timeout {
			let _ = child.kill();
			let _ = child.wait(); // Reap zombie
			return Err("Operation timed out (Killed hanging SSH process)".to_string());
		}

		std::thread::sleep(Duration::from_millis(50));
	}
}

pub fn probe_stdout(connection: &str, cmd: &str, timeout_secs: u16) -> Option<String> {
	let parts: Vec<&str> = connection.split('@').collect();
	let ip = if parts.len() == 2 { parts[1] } else { connection };
	let mut opts = SshOptions::probe(timeout_secs);
	if let Some(proxy) = crate::context::find_proxy_jump_for_ip(ip) {
		opts.proxy_jump = Some(proxy);
	}
	let output = std::process::Command::new("ssh")
		.args(probe_args_with_opts(connection, cmd, &opts))
		.output()
		.ok()?;

	if !output.status.success() {
		return None;
	}

	Some(String::from_utf8_lossy(&output.stdout).to_string())
}

fn probe_args_with_opts(connection: &str, cmd: &str, options: &SshOptions) -> Vec<String> {
	let mut args = options.ssh_args_before_target();
	args.push(connection.to_string());
	args.push(cmd.to_string());
	args
}

#[cfg(test)]
fn probe_args(connection: &str, cmd: &str, timeout_secs: u16) -> Vec<String> {
	let parts: Vec<&str> = connection.split('@').collect();
	let ip = if parts.len() == 2 { parts[1] } else { connection };
	let mut opts = SshOptions::probe(timeout_secs);
	if let Some(proxy) = crate::context::find_proxy_jump_for_ip(ip) {
		opts.proxy_jump = Some(proxy);
	}
	probe_args_with_opts(connection, cmd, &opts)
}

pub struct SshResult {
	pub status: std::process::ExitStatus,
	pub stdout: Vec<u8>,
	pub stderr: Vec<u8>,
}

pub enum SshOutputMode {
	/// Redirects standard streams directly to/from the parent process.
	Interactive,

	/// Buffers all stdout/stderr into memory and returns them as bytes.
	Buffered,

	/// Streams lines real-time with a custom prefix string to standard console out.
	ConsoleStreamed { prefix: String },

	/// Routes real-time stdout/stderr lines through a configured Logger.
	LoggerStreamed { logger: Logger },
}

pub struct SshSession {
	pub target: String,
	pub options: SshOptions,
}

impl SshSession {
	pub fn new(username: &str, ip: &str) -> Self {
		let target = if username.is_empty() { ip.to_string() } else { format!("{}@{}", username, ip) };
		let mut options = SshOptions::deployment();
		if let Some(proxy) = crate::context::find_proxy_jump_for_ip(ip) {
			options.proxy_jump = Some(proxy);
		}
		Self { target, options }
	}

	pub fn new_with_options(username: &str, ip: &str, mut options: SshOptions) -> Self {
		let target = if username.is_empty() { ip.to_string() } else { format!("{}@{}", username, ip) };
		if let Some(proxy) =
			crate::context::find_proxy_jump_for_ip(ip).filter(|_| options.proxy_jump.is_none())
		{
			options.proxy_jump = Some(proxy);
		}
		Self { target, options }
	}

	/// Parse connection string user@ip or ip
	pub fn parse(connection: &str) -> Self {
		let parts: Vec<&str> = connection.split('@').collect();
		let (user, ip) = if parts.len() == 2 { (parts[0], parts[1]) } else { ("", connection) };
		Self::new(user, ip)
	}

	pub fn parse_with_options(connection: &str, options: SshOptions) -> Self {
		let parts: Vec<&str> = connection.split('@').collect();
		let (user, ip) = if parts.len() == 2 { (parts[0], parts[1]) } else { ("", connection) };
		Self::new_with_options(user, ip, options)
	}

	fn ssh_args(&self, cmd: &str) -> Vec<String> {
		let mut args = self.options.ssh_args_before_target();
		args.push(self.target.clone());
		args.push(cmd.to_string());
		args
	}

	fn build_ssh_command(&self, cmd: &str) -> std::process::Command {
		let mut command = std::process::Command::new("ssh");
		command.args(self.ssh_args(cmd));
		command
	}

	pub fn spawn_silent(&self, cmd: &str) -> Result<std::process::Child, Box<dyn std::error::Error>> {
		Ok(
			self
				.build_ssh_command(cmd)
				.stdin(std::process::Stdio::null())
				.stdout(std::process::Stdio::null())
				.stderr(std::process::Stdio::null())
				.spawn()?,
		)
	}

	/// Execute a command and buffer/return stdout
	pub fn execute(&self, cmd: &str, log: Logger) -> Result<String, Box<dyn std::error::Error>> {
		let args = self.ssh_args(cmd);
		let args_ref: Vec<&str> = args.iter().map(|s| s.as_str()).collect();
		crate::process::CommandExecutor::execute("ssh", &args_ref, log)
	}

	/// Execute a command with stdin data piped in
	pub fn execute_with_stdin(
		&self,
		cmd: &str,
		stdin: &str,
		log: Logger,
	) -> Result<String, Box<dyn std::error::Error>> {
		let args = self.ssh_args(cmd);
		let args_ref: Vec<&str> = args.iter().map(|s| s.as_str()).collect();
		crate::process::CommandExecutor::execute_with_stdin("ssh", &args_ref, stdin, log)
	}

	/// Dispatch SSH command under a specific output mode
	pub fn run(
		&self,
		cmd: &str,
		mode: SshOutputMode,
	) -> Result<SshResult, Box<dyn std::error::Error>> {
		let mut command = self.build_ssh_command(cmd);

		match mode {
			SshOutputMode::Interactive => {
				let mut child = command.spawn()?;
				let status = child.wait()?;
				Ok(SshResult { status, stdout: Vec::new(), stderr: Vec::new() })
			}
			SshOutputMode::Buffered => {
				let output = command
					.stdout(std::process::Stdio::piped())
					.stderr(std::process::Stdio::piped())
					.output()?;
				Ok(SshResult { status: output.status, stdout: output.stdout, stderr: output.stderr })
			}
			SshOutputMode::ConsoleStreamed { prefix } => {
				let mut child = command
					.stdout(std::process::Stdio::piped())
					.stderr(std::process::Stdio::piped())
					.spawn()?;

				let stdout = child.stdout.take().ok_or("Failed to open stdout")?;
				let stderr = child.stderr.take().ok_or("Failed to open stderr")?;

				let prefix_clone = prefix.clone();
				let t_stdout = std::thread::spawn(move || {
					use std::io::BufRead;
					let reader = std::io::BufReader::new(stdout);
					for line in reader.lines().map_while(Result::ok) {
						println!("{} {}", prefix_clone, line);
					}
				});

				let prefix_clone2 = prefix;
				let t_stderr = std::thread::spawn(move || {
					use std::io::BufRead;
					let reader = std::io::BufReader::new(stderr);
					for line in reader.lines().map_while(Result::ok) {
						eprintln!("{} {}", prefix_clone2, line);
					}
				});

				t_stdout.join().unwrap();
				t_stderr.join().unwrap();

				let status = child.wait()?;
				Ok(SshResult { status, stdout: Vec::new(), stderr: Vec::new() })
			}
			SshOutputMode::LoggerStreamed { logger } => {
				let mut child = command
					.stdout(std::process::Stdio::piped())
					.stderr(std::process::Stdio::piped())
					.spawn()?;

				let stdout = child.stdout.take().ok_or("Failed to open stdout")?;
				let stderr = child.stderr.take().ok_or("Failed to open stderr")?;

				let stdout_handle = crate::process::stream_output_lines(stdout, logger.clone(), false);
				let stderr_handle = crate::process::stream_output_lines(stderr, logger, true);

				let _ = stdout_handle.join();
				let _ = stderr_handle.join();

				let status = child.wait()?;
				Ok(SshResult { status, stdout: Vec::new(), stderr: Vec::new() })
			}
		}
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn test_ssh_target_connection_string() {
		let target = SshTarget::new("nixos", "1.2.3.4");
		assert_eq!(target.to_connection_string(), "nixos@1.2.3.4");

		let target_no_user = SshTarget::new("", "1.2.3.4");
		assert_eq!(target_no_user.to_connection_string(), "1.2.3.4");
	}

	#[test]
	fn test_ssh_options_rendering() {
		let opts = SshOptions::probe(3);
		let args = opts.ssh_args_before_target();
		assert!(args.contains(&"ConnectTimeout=3".to_string()));
		assert!(args.contains(&WARN_WEAK_CRYPTO_OPTION.to_string()));
		assert!(args.contains(&"StrictHostKeyChecking=no".to_string()));
		assert!(args.contains(&"UserKnownHostsFile=/dev/null".to_string()));

		let nix_opts = opts.nix_sshopts();
		assert!(nix_opts.contains("-o ConnectTimeout=3"));
		assert!(nix_opts.contains("-o WarnWeakCrypto=no-pq-kex"));
		assert!(nix_opts.contains("-o StrictHostKeyChecking=no"));
		assert!(nix_opts.contains("-o UserKnownHostsFile=/dev/null"));
	}

	#[test]
	fn control_plane_requires_known_host_verification() {
		let opts = SshOptions::control_plane();
		let args = opts.ssh_args_before_target();
		assert!(args.contains(&"StrictHostKeyChecking=yes".to_string()));
		assert!(!args.contains(&"UserKnownHostsFile=/dev/null".to_string()));
		assert!(!args.contains(&"-A".to_string()));
	}

	#[test]
	fn proxy_jump_uses_native_jump_option() {
		let opts = SshOptions::probe(3).with_proxy_jump(Some("user@windows".to_string()));
		let args = opts.ssh_args_before_target();
		let jump_index = args.iter().position(|arg| arg == "-J").unwrap();
		assert_eq!(args[jump_index + 1], "user@windows");
		assert!(!args.iter().any(|arg| arg.starts_with("ProxyCommand=")));
	}

	#[test]
	fn proxy_command_uses_native_option() {
		let opts =
			SshOptions::probe(3).with_proxy_command(Some("ssh -W %h:%p user@bastion".to_string()));
		let args = opts.ssh_args_before_target();
		let idx = args.iter().position(|arg| arg == "ProxyCommand=ssh -W %h:%p user@bastion").unwrap();
		assert_eq!(args[idx - 1], "-o");

		let nix_opts = opts.nix_sshopts();
		assert!(nix_opts.contains("-o 'ProxyCommand ssh -W %h:%p user@bastion'"));
	}

	#[test]
	fn test_probe_args_append_target_and_command() {
		let args = probe_args("deploy@builder", "uname -m", 2);

		assert!(args.contains(&"ConnectTimeout=2".to_string()));
		assert_eq!(args[args.len() - 2], "deploy@builder");
		assert_eq!(args[args.len() - 1], "uname -m");
	}
}
