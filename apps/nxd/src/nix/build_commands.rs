use crate::Logger;
use crate::config;
use crate::nix::NixBuilder;
use crate::process::CommandExecutor;

const WSL_COPY_ATTEMPTS: u8 = 3;
const WSL_KEEPALIVE_TIMEOUT_SECS: u32 = 21_600;
const WSL_RETRY_DELAY_SECS: u64 = 5;

pub fn target_ssh(builder: &NixBuilder) -> String {
	target_ssh_for_ip(builder, &builder.target_ip)
}

pub fn target_ssh_for_ip(builder: &NixBuilder, target_ip: &str) -> String {
	let is_deploy = crate::config::get_runtime_options().deploy_active;
	let target_user = if is_deploy {
		if let Some(ref wsl_user) = builder.wsl_bootstrap_user { wsl_user } else { "root" }
	} else {
		&builder.username
	};
	format!("{}@{}", target_user, target_ip)
}

pub fn copy_target(builder: &NixBuilder, target_ssh: &str, mount_point: Option<&str>) -> String {
	let mut params = Vec::new();
	if let Some(mnt) = mount_point {
		params.push("remote-store=local".to_string());
		params.push(format!("root={}", mnt));
	}
	if builder.wsl_bootstrap_user.is_some() {
		params.push("remote-program=sudo%20nix-store".to_string());
	}

	if params.is_empty() {
		format!("ssh://{}", target_ssh)
	} else {
		format!("ssh://{}?{}", target_ssh, params.join("?"))
	}
}

pub fn flake_target_attr(builder: &NixBuilder, attr: &str) -> String {
	let src_path = builder.source_store_path.as_deref().unwrap_or_default();
	format!("path:{}#{}", src_path, builder.target_attr(attr))
}

pub fn override_input_args(builder: &NixBuilder) -> Vec<String> {
	let mut extra = Vec::new();
	if let Some(ref sec_path) = builder.secret_store_path {
		extra.push("--override-input".to_string());
		extra.push(config::SECRET_INPUT_NAME.to_string());
		extra.push(format!("path:{}", sec_path));
	}
	extra
}

pub fn remote_builder_build_command(builder: &NixBuilder, attr: &str) -> String {
	let token_opts = crate::config::nix_token_args().join(" ");
	let token_str = if token_opts.is_empty() { String::new() } else { format!("{} ", token_opts) };

	let src_path = builder.source_store_path.as_deref().unwrap_or_default();
	let override_str = if let Some(ref sec_path) = builder.secret_store_path {
		format!("--override-input {} path:{} ", config::SECRET_INPUT_NAME, sec_path)
	} else {
		String::new()
	};
	format!(
		"export NIX_SSHOPTS=\"{}\" && nix build {}{}--print-out-paths --no-link path:{}#{}",
		crate::remote::ssh::SshOptions::nix_copy().nix_sshopts(),
		token_str,
		override_str,
		src_path,
		builder.target_attr(attr)
	)
}

pub fn target_native_build_command(
	builder: &NixBuilder,
	attr: &str,
	mount_point: Option<&str>,
) -> String {
	let store_arg =
		if let Some(mnt) = mount_point { format!("--store {} ", mnt) } else { String::new() };

	let token_opts = crate::config::nix_token_args().join(" ");
	let token_str = if token_opts.is_empty() { String::new() } else { format!("{} ", token_opts) };

	let src_path = builder.source_store_path.as_deref().unwrap_or_default();
	let override_str = if let Some(ref sec_path) = builder.secret_store_path {
		format!("--override-input {} path:{} ", config::SECRET_INPUT_NAME, sec_path)
	} else {
		String::new()
	};
	format!(
		"nix build {}{}{}--print-out-paths --no-link path:{}#{}",
		store_arg,
		token_str,
		override_str,
		src_path,
		builder.target_attr(attr)
	)
}

pub fn target_realise_command(drv_path: &str, mount_point: Option<&str>, low_mem: bool) -> String {
	let gc_env = if low_mem {
		"export GC_INITIAL_HEAP_SIZE=1M GC_DONT_GC=1 NIX_DISABLE_AUTO_GC=1; "
	} else {
		""
	};

	let store_arg =
		if let Some(mnt) = mount_point { format!("--store {}", mnt) } else { String::new() };

	format!("{}nix-store --realise {} --cores 1 --max-jobs 1 {}", gc_env, drv_path, store_arg)
}

fn start_wsl_copy_keepalive(
	builder: &NixBuilder,
	logger: Logger,
) -> Result<Option<crate::providers::wsl::WslKeepalive>, Box<dyn std::error::Error>> {
	if let Some(ref windows_connection) = builder.wsl_windows_connection
		&& let Some(ref distribution) = builder.wsl_distribution
	{
		crate::info!(
			logger,
			"Waking up WSL distribution '{}' on {} before transferring store path...",
			distribution,
			windows_connection
		);
		let session = crate::providers::wsl::start_keepalive_session(
			windows_connection,
			distribution,
			WSL_KEEPALIVE_TIMEOUT_SECS,
		)?;
		return Ok(Some(session));
	}
	Ok(None)
}

fn summarize_wsl_copy_error(error: &dyn std::error::Error) -> String {
	let message = error.to_string();
	let mut lines = message
		.lines()
		.filter(|line| !line.trim_start().starts_with("copying path '"))
		.collect::<Vec<_>>();
	const MAX_LINES: usize = 12;
	if lines.len() > MAX_LINES {
		let first = lines[0];
		let tail = lines.split_off(lines.len() - (MAX_LINES - 1));
		lines = std::iter::once(first).chain(tail).collect();
	}
	lines.join("\n")
}

fn current_wsl_guest_ip(
	builder: &NixBuilder,
) -> Result<Option<String>, Box<dyn std::error::Error>> {
	let Some(windows_connection) = builder.wsl_windows_connection.as_deref() else {
		return Ok(None);
	};
	let Some(distribution) = builder.wsl_distribution.as_deref() else {
		return Ok(None);
	};
	let command = crate::providers::wsl::commands::guest_ip(distribution);
	let mut last_error = None;
	for _ in 0..30 {
		match CommandExecutor::execute_ssh(windows_connection, &command, Logger::silent()) {
			Ok(output) => {
				let ip = output.replace('\0', "").trim().to_string();
				if ip.parse::<std::net::IpAddr>().is_ok() {
					return Ok(Some(ip));
				}
				last_error = Some(format!("invalid address '{}'", ip));
			}
			Err(error) => last_error = Some(error.to_string()),
		}
		std::thread::sleep(std::time::Duration::from_secs(2));
	}
	Err(
		format!(
			"WSL distribution '{}' returned no usable guest address after wakeup: {}",
			distribution,
			last_error.unwrap_or_else(|| "unknown error".to_string())
		)
		.into(),
	)
}

pub fn verify_wsl_route_from_builder(
	builder: &NixBuilder,
	ssh_connection: &str,
	target_ip: &str,
) -> Result<(), Box<dyn std::error::Error>> {
	let Some(windows_connection) = builder.wsl_windows_connection.as_deref() else {
		return Ok(());
	};
	let target = target_ssh_for_ip(builder, target_ip);
	let proxy_command = format!(
		"ssh -o {} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p {}",
		crate::remote::ssh::WARN_WEAK_CRYPTO_OPTION,
		windows_connection
	);
	let command = format!(
		"ssh -o {} -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o {} {} true",
		crate::remote::ssh::WARN_WEAK_CRYPTO_OPTION,
		crate::process::shell_escape(&format!("ProxyCommand {}", proxy_command)),
		crate::process::shell_escape(&target)
	);
	CommandExecutor::execute_ssh(ssh_connection, &command, Logger::silent()).map(|_| ()).map_err(
		|error| {
			format!(
				"WSL guest {} is not ready through builder {} and Windows jump {}: {}",
				target, ssh_connection, windows_connection, error
			)
			.into()
		},
	)
}

pub fn execute_copy_with_wsl_retry<T, F>(
	builder: &NixBuilder,
	logger: Logger,
	mut copy: F,
) -> Result<T, Box<dyn std::error::Error>>
where
	F: FnMut(Option<&str>) -> Result<T, Box<dyn std::error::Error>>,
{
	let attempts = if builder.wsl_windows_connection.is_some() { WSL_COPY_ATTEMPTS } else { 1 };
	for attempt in 1..=attempts {
		let keepalive_session = start_wsl_copy_keepalive(builder, logger.clone())?;
		let refreshed_ip = current_wsl_guest_ip(builder);
		if let Ok(Some(ref ip)) = refreshed_ip
			&& ip != &builder.target_ip
		{
			crate::info!(
				logger.clone(),
				"WSL guest address changed from {} to {}; refreshing copy destination.",
				builder.target_ip,
				ip
			);
		}
		let result = refreshed_ip.and_then(|ip| copy(ip.as_deref()));
		drop(keepalive_session);

		match result {
			Ok(output) => return Ok(output),
			Err(error) if attempt < attempts => {
				let summary = summarize_wsl_copy_error(error.as_ref());
				crate::warn!(
					logger.clone(),
					"WSL store transfer failed on attempt {}/{}; waking the distribution and resuming in {} seconds: {}",
					attempt,
					attempts,
					WSL_RETRY_DELAY_SECS,
					summary
				);
				std::thread::sleep(std::time::Duration::from_secs(WSL_RETRY_DELAY_SECS));
			}
			Err(error) => return Err(summarize_wsl_copy_error(error.as_ref()).into()),
		}
	}
	unreachable!("copy attempt loop always returns")
}

#[cfg(test)]
mod tests {
	use super::*;

	fn dummy_builder(source_store_path: Option<&str>, secret_store_path: Option<&str>) -> NixBuilder {
		NixBuilder {
			strategy: crate::nix::strategy::BuildStrategy::Local,
			hostname: "host-a".to_string(),
			target_ip: "10.0.0.1".to_string(),
			username: "root".to_string(),
			system: "x86_64-linux".to_string(),
			low_mem: false,
			substitute_on_destination: false,
			has_local_nix: true,
			source_store_path: source_store_path.map(String::from),
			secret_store_path: secret_store_path.map(String::from),
			wsl_bootstrap_user: None,
			wsl_windows_connection: None,
			wsl_distribution: None,
		}
	}

	#[test]
	fn renders_copy_targets() {
		let builder = dummy_builder(None, None);
		assert_eq!(copy_target(&builder, "root@10.0.0.2", None), "ssh://root@10.0.0.2");
		assert_eq!(
			copy_target(&builder, "root@10.0.0.2", Some("/mnt")),
			"ssh://root@10.0.0.2?remote-store=local?root=/mnt"
		);
	}

	#[test]
	fn renders_wsl_copy_targets() {
		let mut builder = dummy_builder(None, None);
		builder.wsl_bootstrap_user = Some("nixos".to_string());
		assert_eq!(
			copy_target(&builder, "nixos@10.0.0.2", None),
			"ssh://nixos@10.0.0.2?remote-program=sudo%20nix-store"
		);
		assert_eq!(
			copy_target(&builder, "nixos@10.0.0.2", Some("/mnt")),
			"ssh://nixos@10.0.0.2?remote-store=local?root=/mnt?remote-program=sudo%20nix-store"
		);
	}

	#[test]
	fn remote_builder_build_uses_store_paths() {
		let builder = dummy_builder(Some("/nix/store/source-hash"), Some("/nix/store/secret-hash"));
		let command = remote_builder_build_command(&builder, "config.system.build.toplevel");

		assert!(!command.contains("cd "));
		assert!(command.contains("nix build"));
		assert!(command.contains(&format!(
			"--override-input {} path:/nix/store/secret-hash",
			config::SECRET_INPUT_NAME
		)));
		assert!(command.contains(
			"path:/nix/store/source-hash#nixosConfigurations.host-a.config.system.build.toplevel"
		));
	}

	#[test]
	fn target_native_build_adds_store_only_when_mounted() {
		let builder = dummy_builder(Some("/nix/store/source-hash"), None);
		let mounted =
			target_native_build_command(&builder, "config.system.build.toplevel", Some("/mnt"));
		let unmounted = target_native_build_command(&builder, "config.system.build.toplevel", None);

		assert!(mounted.contains("nix build --store /mnt --print-out-paths"));
		assert!(unmounted.contains("nix build --print-out-paths"));
		assert!(!unmounted.contains("--store"));
	}

	#[test]
	fn target_native_build_uses_store_paths() {
		let builder = dummy_builder(Some("/nix/store/source-hash"), Some("/nix/store/secret-hash"));
		let command =
			target_native_build_command(&builder, "config.system.build.toplevel", Some("/mnt"));

		assert!(!command.contains("cd "));
		assert!(command.contains("nix build --store /mnt"));
		assert!(command.contains(&format!(
			"--override-input {} path:/nix/store/secret-hash",
			config::SECRET_INPUT_NAME
		)));
		assert!(command.contains(
			"path:/nix/store/source-hash#nixosConfigurations.host-a.config.system.build.toplevel"
		));
	}

	#[test]
	fn target_realise_command_adds_low_memory_env_only_when_requested() {
		let low_mem = target_realise_command("/nix/store/example.drv", Some("/mnt"), true);
		let normal = target_realise_command("/nix/store/example.drv", None, false);

		assert!(low_mem.starts_with("export GC_INITIAL_HEAP_SIZE=1M"));
		assert!(low_mem.contains("--store /mnt"));
		assert!(!normal.contains("GC_INITIAL_HEAP_SIZE"));
		assert!(!normal.contains("--store"));
	}

	#[test]
	fn verifies_wsl_guest_through_exact_builder_route() {
		CommandExecutor::start_recording();
		crate::config::set_runtime_options(crate::config::RuntimeOptions {
			deploy_active: true,
			..Default::default()
		});
		let mut builder = dummy_builder(None, None);
		builder.wsl_bootstrap_user = Some("nixos".to_string());
		builder.wsl_windows_connection = Some("lamt@windows".to_string());

		verify_wsl_route_from_builder(&builder, "deploy@utils", "172.30.55.44").unwrap();
		let commands = CommandExecutor::stop_recording().unwrap();
		CommandExecutor::clear_mocks();

		assert!(commands.iter().any(|command| {
			command.contains("deploy@utils")
				&& command.contains("ProxyCommand ssh")
				&& command.matches("WarnWeakCrypto=no-pq-kex").count() >= 2
				&& command.contains("lamt@windows")
				&& command.contains("nixos@172.30.55.44")
				&& command.contains(" true")
		}));
	}

	#[test]
	fn wsl_copy_error_summary_drops_replayed_progress() {
		let error = std::io::Error::other(
			"Command 'nix copy' failed\n\
			 copying path '/nix/store/one' from 'https://cache.example'...\n\
			 copying path '/nix/store/two' from 'https://cache.example'...\n\
			 Connection to 172.30.55.32 closed by remote host.\n\
			 error: unexpected end-of-file",
		);

		let summary = summarize_wsl_copy_error(&error);
		assert!(summary.contains("Command 'nix copy' failed"));
		assert!(summary.contains("closed by remote host"));
		assert!(summary.contains("unexpected end-of-file"));
		assert!(!summary.contains("copying path"));
	}
}
