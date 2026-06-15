use crate::config;
use crate::process::Logger;
use std::io::{BufRead, BufReader, Write};
use std::thread;

use crate::progress::target::LogTarget;

pub fn format_output_line(line: &str) -> String {
	let color_mode = crate::progress::color::ColorMode::Auto;
	if let Some(stripped) = line.strip_prefix("Error:") {
		let label = crate::progress::color::colorize("Error:", crate::progress::color::RED, color_mode);
		format!("{}{}", label, stripped)
	} else if let Some(stripped) = line.strip_prefix("error:") {
		let label = crate::progress::color::colorize("error:", crate::progress::color::RED, color_mode);
		format!("{}{}", label, stripped)
	} else if let Some(stripped) = line.strip_prefix("Warning:") {
		let label =
			crate::progress::color::colorize("Warning:", crate::progress::color::YELLOW, color_mode);
		format!("{}{}", label, stripped)
	} else if let Some(stripped) = line.strip_prefix("warning:") {
		let label =
			crate::progress::color::colorize("warning:", crate::progress::color::YELLOW, color_mode);
		format!("{}{}", label, stripped)
	} else {
		line.to_string()
	}
}

pub fn stream_output_lines<R>(reader: R, logger: Logger, stderr: bool) -> thread::JoinHandle<String>
where
	R: std::io::Read + Send + 'static,
{
	stream_output_lines_filtered(reader, logger, stderr, false)
}

pub fn stream_output_lines_filtered<R>(
	reader: R,
	logger: Logger,
	stderr: bool,
	filter_lock_warning: bool,
) -> thread::JoinHandle<String>
where
	R: std::io::Read + Send + 'static,
{
	thread::spawn(move || {
		let mut captured = String::new();
		let reader = BufReader::new(reader);

		if stderr && filter_lock_warning {
			let mut lines_iter = reader.lines().map_while(Result::ok);
			let mut pending = None;

			while let Some(line) = pending.take().or_else(|| lines_iter.next()) {
				let redacted = crate::config::redact_token(&line);

				if redacted.starts_with("warning: not writing modified lock file of flake ") {
					let mut block = vec![redacted];
					let mut block_bytes = block[0].len();
					let mut matched_secret = false;

					for next_line in lines_iter.by_ref() {
						let next_redacted = crate::config::redact_token(&next_line);
						let is_continuation = next_redacted.trim_start().starts_with('•')
							|| next_redacted.trim_start().starts_with('-')
							|| next_redacted.trim_start().starts_with('+')
							|| next_redacted.starts_with(' ')
							|| next_redacted.is_empty();

						if !is_continuation {
							pending = Some(next_redacted);
							break;
						}

						block_bytes += next_redacted.len();
						if block.len() >= 32 || block_bytes > 16 * 1024 {
							pending = Some(next_redacted);
							break;
						}

						if next_redacted.contains(&format!("Updated input '{}'", config::SECRET_INPUT_NAME)) {
							matched_secret = true;
						}
						block.push(next_redacted);
					}

					for block_line in &block {
						if matched_secret {
							crate::debug!(logger.clone(), "[suppressed nix warning] {}", block_line);
							captured.push_str(block_line);
							captured.push('\n');
						} else {
							write_output_line(block_line, logger.clone(), stderr);
							captured.push_str(block_line);
							captured.push('\n');
						}
					}
				} else {
					write_output_line(&redacted, logger.clone(), stderr);
					captured.push_str(&redacted);
					captured.push('\n');
				}
			}
		} else {
			for line in reader.lines().map_while(Result::ok) {
				let redacted = crate::config::redact_token(&line);
				write_output_line(&redacted, logger.clone(), stderr);
				captured.push_str(&redacted);
				captured.push('\n');
			}
		}
		captured
	})
}

pub fn write_output_line(line: &str, logger: Logger, stderr: bool) {
	let line = crate::config::redact_token(line);
	if let Ok(mut target) = logger.lock() {
		match &mut *target {
			LogTarget::Terminal => {
				if stderr {
					eprintln!("{}", format_output_line(&line));
				} else {
					println!("{}", format_output_line(&line));
				}
			}
			LogTarget::Batch { file, .. } | LogTarget::File(file) => {
				let _ = writeln!(file, "{}", line);
			}
			LogTarget::Silent => {}
		}
	}
}
