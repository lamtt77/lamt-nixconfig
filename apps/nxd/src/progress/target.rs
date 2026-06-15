use std::fs::File;
use std::io::Write;
use std::sync::{Arc, Mutex};

use crate::progress::color::ColorMode;
use crate::progress::log::{ProgressEvent, StatusLevel, normalize_multiline_message};

pub enum LogTarget {
	Terminal,
	File(File),
	Batch { prefix: String, file: File },
	Silent,
}

impl LogTarget {
	pub fn log_event(&mut self, level: StatusLevel, message: &str) {
		self.write_event(level, message, message);
	}

	pub fn log_status(&mut self, message: &str) {
		self.write_event(StatusLevel::Info, message, message);
	}

	pub fn log_debug(&mut self, message: &str) {
		self.write_event(StatusLevel::Debug, message, message);
	}

	fn write_event(&mut self, level: StatusLevel, message: &str, file_message: &str) {
		let message = normalize_multiline_message(message);
		let message = crate::config::redact_token(&message);
		let file_message = normalize_multiline_message(file_message);
		let file_message = crate::config::redact_token(&file_message);
		let message_lines: Vec<&str> =
			if message.is_empty() { vec![""] } else { message.lines().collect() };
		let file_lines: Vec<&str> =
			if file_message.is_empty() { vec![""] } else { file_message.lines().collect() };

		match self {
			LogTarget::Terminal => {
				for line in message_lines {
					let event = ProgressEvent::new(level, None, line);
					event.log(ColorMode::Auto);
				}
			}
			LogTarget::Batch { prefix, file } => {
				for line in message_lines {
					let event = ProgressEvent::new(level, Some(prefix), line);
					event.log(ColorMode::Auto);
				}
				for line in file_lines {
					let _ = writeln!(file, "[{}] {}", level.label(), line);
				}
			}
			LogTarget::File(file) => {
				for line in file_lines {
					let _ = writeln!(file, "[{}] {}", level.label(), line);
				}
			}
			LogTarget::Silent => {}
		}
	}

	pub fn get_write_stream(&mut self) -> Box<dyn std::io::Write + '_> {
		match self {
			LogTarget::Terminal => Box::new(std::io::stdout()),
			LogTarget::File(file) => Box::new(file),
			LogTarget::Batch { file, .. } => Box::new(file),
			LogTarget::Silent => Box::new(std::io::sink()),
		}
	}
}

#[derive(Clone)]
pub struct Logger {
	pub target: Arc<Mutex<LogTarget>>,
}

impl Logger {
	pub fn new(target: Arc<Mutex<LogTarget>>) -> Self {
		Self { target }
	}

	pub fn lock(&self) -> std::sync::LockResult<std::sync::MutexGuard<'_, LogTarget>> {
		self.target.lock()
	}

	pub fn silent() -> Self {
		Self::new(Arc::new(Mutex::new(LogTarget::Silent)))
	}

	pub fn terminal() -> Self {
		Self::new(Arc::new(Mutex::new(LogTarget::Terminal)))
	}

	pub fn file(file: File) -> Self {
		Self::new(Arc::new(Mutex::new(LogTarget::File(file))))
	}

	pub fn batch(prefix: String, file: File) -> Self {
		Self::new(Arc::new(Mutex::new(LogTarget::Batch { prefix, file })))
	}

	pub fn event(&self, level: StatusLevel, message: &str) {
		if level == StatusLevel::Debug && !crate::config::get_runtime_options().debug {
			return;
		}
		if let Ok(mut lock) = self.target.lock() {
			lock.log_event(level, message);
		}
	}

	pub fn info(&self, message: &str) {
		self.event(StatusLevel::Info, message);
	}

	pub fn success(&self, message: &str) {
		self.event(StatusLevel::Success, message);
	}

	pub fn warn(&self, message: &str) {
		self.event(StatusLevel::Warning, message);
	}

	pub fn error(&self, message: &str) {
		self.event(StatusLevel::Error, message);
	}

	pub fn failure(&self, message: &str) {
		self.event(StatusLevel::Failure, message);
	}

	pub fn debug(&self, message: &str) {
		self.event(StatusLevel::Debug, message);
	}
}

#[macro_export]
macro_rules! info {
    ($logger:expr, $fmt:literal) => { $logger.info(&format!($fmt)) };
    ($logger:expr, $msg:expr) => { $logger.info($msg) };
    ($logger:expr, $fmt:literal, $($arg:tt)*) => { $logger.info(&format!($fmt, $($arg)*)) };
}

#[macro_export]
macro_rules! success {
    ($logger:expr, $fmt:literal) => { $logger.success(&format!($fmt)) };
    ($logger:expr, $msg:expr) => { $logger.success($msg) };
    ($logger:expr, $fmt:literal, $($arg:tt)*) => { $logger.success(&format!($fmt, $($arg)*)) };
}

#[macro_export]
macro_rules! warn {
    ($logger:expr, $fmt:literal) => { $logger.warn(&format!($fmt)) };
    ($logger:expr, $msg:expr) => { $logger.warn($msg) };
    ($logger:expr, $fmt:literal, $($arg:tt)*) => { $logger.warn(&format!($fmt, $($arg)*)) };
}

#[macro_export]
macro_rules! error {
    ($logger:expr, $fmt:literal) => { $logger.error(&format!($fmt)) };
    ($logger:expr, $msg:expr) => { $logger.error($msg) };
    ($logger:expr, $fmt:literal, $($arg:tt)*) => { $logger.error(&format!($fmt, $($arg)*)) };
}

#[macro_export]
macro_rules! failure {
    ($logger:expr, $fmt:literal) => { $logger.failure(&format!($fmt)) };
    ($logger:expr, $msg:expr) => { $logger.failure($msg) };
    ($logger:expr, $fmt:literal, $($arg:tt)*) => { $logger.failure(&format!($fmt, $($arg)*)) };
}

#[macro_export]
macro_rules! debug {
    ($logger:expr, $fmt:literal) => { $logger.debug(&format!($fmt)) };
    ($logger:expr, $msg:expr) => { $logger.debug($msg) };
    ($logger:expr, $fmt:literal, $($arg:tt)*) => { $logger.debug(&format!($fmt, $($arg)*)) };
}

#[cfg(test)]
mod tests {
	use super::*;
	use std::fs;
	use std::time::{SystemTime, UNIX_EPOCH};

	#[test]
	fn file_target_writes_multiline_events_line_by_line() {
		let path = std::env::temp_dir().join(format!(
			"nxd-log-target-{}.log",
			SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()
		));
		let file = File::create(&path).unwrap();
		let mut target = LogTarget::File(file);

		target.log_status(
			"
            first line
              second line
            ",
		);

		drop(target);
		let contents = fs::read_to_string(&path).unwrap();
		let _ = fs::remove_file(&path);

		assert_eq!(contents, "[INFO] first line\n[INFO]   second line\n");
	}

	#[test]
	fn event_macro_supports_captured_multiline_literals() {
		let path = std::env::temp_dir().join(format!(
			"nxd-log-macro-{}.log",
			SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()
		));
		let file = File::create(&path).unwrap();
		let logger = Logger::file(file);
		let host = "air15vm";
		let ip = "172.16.138.138";

		crate::info!(
			logger,
			"
            Target:
              Host: {host}
              IP:   {ip}
            "
		);

		drop(logger);
		let contents = fs::read_to_string(&path).unwrap();
		let _ = fs::remove_file(&path);

		assert_eq!(contents, "[INFO] Target:\n[INFO]   Host: air15vm\n[INFO]   IP:   172.16.138.138\n");
	}

	#[test]
	fn event_macro_supports_explicit_levels() {
		let path = std::env::temp_dir().join(format!(
			"nxd-event-macro-{}.log",
			SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()
		));
		let file = File::create(&path).unwrap();
		let logger = Logger::file(file);
		let phase = "activation";

		crate::success!(logger, "Completed {phase}");

		drop(logger);
		let contents = fs::read_to_string(&path).unwrap();
		let _ = fs::remove_file(&path);

		assert_eq!(contents, "[SUCCESS] Completed activation\n");
	}
}
