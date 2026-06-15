use crate::config;
use std::cell::RefCell;
use std::collections::HashMap;
use std::io::Write;
use std::process::{Command, Stdio};

pub use crate::progress::stream::{format_output_line, stream_output_lines, write_output_line};
pub use crate::progress::target::LogTarget;
pub use crate::progress::target::Logger;

thread_local! {
		static COMMAND_RECORDER: RefCell<Option<Vec<String>>> = const { RefCell::new(None) };
		static COMMAND_MOCKS: RefCell<HashMap<String, String>> = RefCell::new(HashMap::new());
}

pub struct CommandExecutor;

impl CommandExecutor {
	/// Starts recording executed commands and enables dry-run/mock mode.
	pub fn start_recording() {
		COMMAND_RECORDER.with(|r| {
			*r.borrow_mut() = Some(Vec::new());
		});
	}

	/// Stops recording executed commands and returns the list of recorded commands.
	pub fn stop_recording() -> Option<Vec<String>> {
		COMMAND_RECORDER.with(|r| r.borrow_mut().take())
	}

	/// Returns whether we are currently in recording/dry-run mode.
	pub fn is_recording() -> bool {
		COMMAND_RECORDER.with(|r| r.borrow().is_some())
	}

	/// Registers a mock stdout response for a given command.
	pub fn register_mock(cmd: &str, output: &str) {
		COMMAND_MOCKS.with(|m| {
			m.borrow_mut().insert(cmd.to_string(), output.to_string());
		});
	}

	/// Clears all mock command registrations.
	pub fn clear_mocks() {
		COMMAND_MOCKS.with(|m| {
			m.borrow_mut().clear();
		});
	}

	/// Executes a command locally, streaming stdout and stderr in real-time.
	pub fn execute(
		program: &str,
		args: &[&str],
		logger: Logger,
	) -> Result<String, Box<dyn std::error::Error>> {
		let cmd_str = format!("{} {}", program, args.join(" "));
		let cmd_str = crate::config::redact_token(&cmd_str);
		let is_rec = COMMAND_RECORDER.with(|r| {
			if let Some(ref mut v) = *r.borrow_mut() {
				v.push(cmd_str.clone());
				true
			} else {
				false
			}
		});

		if is_rec {
			let mock_out = COMMAND_MOCKS
				.with(|m| {
					let map = m.borrow();
					if let Some(out) = map.get(&cmd_str) {
						return Some(out.clone());
					}
					for (key, val) in map.iter() {
						if cmd_str.contains(key) {
							return Some(val.clone());
						}
					}
					None
				})
				.unwrap_or_default();
			return Ok(mock_out);
		}

		let mut child_cmd = Command::new(program);
		child_cmd.args(args).stdout(Stdio::piped()).stderr(Stdio::piped());

		// Target-specific NIX_SSHOPTS environment override
		if program == "nix" || program == "rsync" {
			let mut target_ip = None;
			for arg in args {
				let clean_arg =
					if let Some(stripped) = arg.strip_prefix("ssh://") { stripped } else { *arg };
				let parts: Vec<&str> = clean_arg.split('@').collect();
				let host_part = if parts.len() == 2 { parts[1] } else { parts[0] };
				let ip_candidate =
					host_part.split('?').next().unwrap_or(host_part).split(':').next().unwrap_or(host_part);
				if !ip_candidate.is_empty()
					&& (ip_candidate.chars().all(|c| c.is_numeric() || c == '.')
						|| crate::context::find_proxy_jump_for_ip(ip_candidate).is_some())
				{
					target_ip = Some(ip_candidate);
					break;
				}
			}

			if let Some(ip) = target_ip
				&& let Some(proxy) = crate::context::find_proxy_jump_for_ip(ip)
			{
				let mut nix_opts = crate::remote::ssh::SshOptions::nix_copy();
				nix_opts.proxy_jump = Some(proxy);
				child_cmd.env("NIX_SSHOPTS", nix_opts.nix_sshopts());
			}
		}

		let mut child = child_cmd.spawn()?;

		let stdout = child.stdout.take().ok_or("Failed to open stdout")?;
		let stderr = child.stderr.take().ok_or("Failed to open stderr")?;

		let filter_lock_warning = (program == "nix" || program == "ssh")
			&& args.iter().any(|arg| arg.contains(config::SECRET_INPUT_NAME));

		let stdout_handle = stream_output_lines(stdout, logger.clone(), false);
		let stderr_handle = crate::progress::stream::stream_output_lines_filtered(
			stderr,
			logger.clone(),
			true,
			filter_lock_warning,
		);

		let stdout_output = stdout_handle.join().unwrap_or_default();
		let stderr_output = stderr_handle.join().unwrap_or_default();

		let status = child.wait()?;
		if !status.success() {
			let redacted_args = crate::config::redact_token(&args.join(" "));
			let redacted_stderr = crate::config::redact_token(&stderr_output);
			return Err(
				format!(
					"Command '{} {}' failed with status: {}\nError: {}",
					program, redacted_args, status, redacted_stderr
				)
				.into(),
			);
		}

		Ok(stdout_output)
	}

	/// Executes a command remotely over SSH.
	pub fn execute_ssh(
		connection: &str,
		command: &str,
		logger: Logger,
	) -> Result<String, Box<dyn std::error::Error>> {
		let session = crate::remote::ssh::SshSession::parse(connection);
		session.execute(command, logger)
	}

	/// Executes a command locally, feeding content to its stdin.
	pub fn execute_with_stdin(
		program: &str,
		args: &[&str],
		stdin_content: &str,
		logger: Logger,
	) -> Result<String, Box<dyn std::error::Error>> {
		let safe_stdin =
			if stdin_content.contains("PRIVATE KEY") { "<private key hidden>" } else { stdin_content };
		let cmd_str = format!("{} {} [stdin: {}]", program, args.join(" "), safe_stdin);
		let cmd_str = crate::config::redact_token(&cmd_str);
		let is_rec = COMMAND_RECORDER.with(|r| {
			if let Some(ref mut v) = *r.borrow_mut() {
				v.push(cmd_str.clone());
				true
			} else {
				false
			}
		});

		if is_rec {
			let mock_out = COMMAND_MOCKS
				.with(|m| {
					let map = m.borrow();
					if let Some(out) = map.get(&cmd_str) {
						return Some(out.clone());
					}
					for (key, val) in map.iter() {
						if cmd_str.contains(key) {
							return Some(val.clone());
						}
					}
					None
				})
				.unwrap_or_default();
			return Ok(mock_out);
		}

		let mut child = Command::new(program)
			.args(args)
			.stdin(Stdio::piped())
			.stdout(Stdio::piped())
			.stderr(Stdio::piped())
			.spawn()?;

		if let Some(mut stdin) = child.stdin.take() {
			stdin.write_all(stdin_content.as_bytes())?;
			stdin.flush()?;
		}

		let stdout = child.stdout.take().ok_or("Failed to open stdout")?;
		let stderr = child.stderr.take().ok_or("Failed to open stderr")?;

		let filter_lock_warning = (program == "nix" || program == "ssh")
			&& args.iter().any(|arg| arg.contains(config::SECRET_INPUT_NAME));

		let stdout_handle = stream_output_lines(stdout, logger.clone(), false);
		let stderr_handle = crate::progress::stream::stream_output_lines_filtered(
			stderr,
			logger.clone(),
			true,
			filter_lock_warning,
		);

		let stdout_output = stdout_handle.join().unwrap_or_default();
		let stderr_output = stderr_handle.join().unwrap_or_default();

		let status = child.wait()?;
		if !status.success() {
			let redacted_args = crate::config::redact_token(&args.join(" "));
			let redacted_stderr = crate::config::redact_token(&stderr_output);
			return Err(
				format!(
					"Command '{} {}' failed with status: {}\nError: {}",
					program, redacted_args, status, redacted_stderr
				)
				.into(),
			);
		}

		Ok(stdout_output)
	}

	/// Executes an SSH command remotely, feeding content to stdin.
	pub fn execute_ssh_with_stdin(
		connection: &str,
		command: &str,
		stdin_content: &str,
		logger: Logger,
	) -> Result<String, Box<dyn std::error::Error>> {
		let session = crate::remote::ssh::SshSession::parse(connection);
		session.execute_with_stdin(command, stdin_content, logger)
	}
}

pub fn shell_escape(arg: &str) -> String {
	if arg.is_empty() {
		return "''".to_string();
	}

	let is_safe = arg.chars().all(|c| {
		c.is_ascii_alphanumeric()
			|| c == '-'
			|| c == '_'
			|| c == '.'
			|| c == '/'
			|| c == ','
			|| c == ':'
			|| c == '='
	});

	if is_safe { arg.to_string() } else { format!("'{}'", arg.replace('\'', "'\\''")) }
}

#[cfg(test)]
mod tests {
	use super::*;
	use std::fs::File;

	#[test]
	fn test_shell_escape() {
		assert_eq!(shell_escape(""), "''");
		assert_eq!(shell_escape("safe-word_123.txt"), "safe-word_123.txt");
		assert_eq!(shell_escape("unsafe word"), "'unsafe word'");
		assert_eq!(shell_escape("don't"), "'don'\\''t'");
	}

	#[test]
	fn test_command_recording_and_mocks() {
		CommandExecutor::start_recording();
		CommandExecutor::register_mock("echo hello", "mocked_hello");
		CommandExecutor::register_mock("status", "mocked_status");

		let log = Logger::silent();
		let out = CommandExecutor::execute("echo", &["hello"], log.clone()).unwrap();
		assert_eq!(out, "mocked_hello");

		let out_substring = CommandExecutor::execute("qm", &["status", "101"], log.clone()).unwrap();
		assert_eq!(out_substring, "mocked_status");

		let out_unmocked = CommandExecutor::execute("echo", &["world"], log).unwrap();
		assert_eq!(out_unmocked, "");

		let recorded = CommandExecutor::stop_recording().unwrap();
		assert_eq!(recorded.len(), 3);
		assert_eq!(recorded[0], "echo hello");
		assert_eq!(recorded[1], "qm status 101");
		assert_eq!(recorded[2], "echo world");

		CommandExecutor::clear_mocks();
	}

	#[test]
	fn log_status_does_not_infer_level_from_message_text() {
		let path = std::env::temp_dir().join(format!("nxd-log-status-test-{}", std::process::id()));
		let file = File::create(&path).unwrap();
		let mut target = LogTarget::File(file);

		target.log_status("SUCCESS Target host SSH key staged successfully.");
		drop(target);

		let content = std::fs::read_to_string(&path).unwrap();
		let _ = std::fs::remove_file(&path);

		assert_eq!(content, "[INFO] SUCCESS Target host SSH key staged successfully.\n");
	}
}
