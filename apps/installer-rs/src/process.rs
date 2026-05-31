use std::fs::File;
use std::io::{Write, BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;

pub enum LogTarget {
    Terminal,
    File(File),
    Batch { prefix: String, file: File },
    Silent,
}

impl LogTarget {
    pub fn log_status(&mut self, message: &str) {
        match self {
            LogTarget::Terminal => {
                println!("{}", message);
            }
            LogTarget::Batch { prefix, file } => {
                println!("[{}] {}", prefix, message);
                let _ = writeln!(file, "[STATUS] {}", message);
            }
            LogTarget::File(file) => {
                let _ = writeln!(file, "[STATUS] {}", message);
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

#[macro_export]
macro_rules! log_status {
    ($target:expr, $fmt:expr) => {
        if let Ok(mut lock) = $target.lock() {
            lock.log_status($fmt);
        }
    };
    ($target:expr, $fmt:expr, $($arg:tt)*) => {
        if let Ok(mut lock) = $target.lock() {
            lock.log_status(&format!($fmt, $($arg)*));
        }
    };
}

pub struct CommandExecutor;

impl CommandExecutor {
    /// Executes a command locally, streaming stdout and stderr in real-time.
    pub fn execute(
        program: &str,
        args: &[&str],
        log_target: Arc<Mutex<LogTarget>>,
    ) -> Result<String, Box<dyn std::error::Error>> {
        let mut child = Command::new(program)
            .args(args)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;

        let stdout = child.stdout.take().ok_or("Failed to open stdout")?;
        let stderr = child.stderr.take().ok_or("Failed to open stderr")?;

        // Thread to read stdout
        let log_target_out = Arc::clone(&log_target);
        let stdout_handle = thread::spawn(move || {
            let mut captured = String::new();
            let reader = BufReader::new(stdout);
            for line in reader.lines() {
                if let Ok(l) = line {
                    if let Ok(mut target) = log_target_out.lock() {
                        match &mut *target {
                            LogTarget::Terminal => {
                                println!("{}", l);
                            }
                            LogTarget::Batch { file, .. } => {
                                let _ = writeln!(file, "{}", l);
                            }
                            LogTarget::File(file) => {
                                let _ = writeln!(file, "{}", l);
                            }
                            LogTarget::Silent => {}
                        }
                    }
                    captured.push_str(&l);
                    captured.push('\n');
                }
            }
            captured
        });

        // Thread to read stderr
        let log_target_err = Arc::clone(&log_target);
        let stderr_handle = thread::spawn(move || {
            let mut captured = String::new();
            let reader = BufReader::new(stderr);
            for line in reader.lines() {
                if let Ok(l) = line {
                    if let Ok(mut target) = log_target_err.lock() {
                        match &mut *target {
                            LogTarget::Terminal => {
                                eprintln!("{}", l);
                            }
                            LogTarget::Batch { file, .. } => {
                                let _ = writeln!(file, "{}", l);
                            }
                            LogTarget::File(file) => {
                                let _ = writeln!(file, "{}", l);
                            }
                            LogTarget::Silent => {}
                        }
                    }
                    captured.push_str(&l);
                    captured.push('\n');
                }
            }
            captured
        });

        let stdout_output = stdout_handle.join().unwrap_or_default();
        let stderr_output = stderr_handle.join().unwrap_or_default();

        let status = child.wait()?;
        if !status.success() {
            return Err(format!(
                "Command '{} {}' failed with status: {}\nError: {}",
                program,
                args.join(" "),
                status,
                stderr_output
            ).into());
        }

        Ok(stdout_output)
    }

    /// Executes a command remotely over SSH.
    pub fn execute_ssh(
        connection: &str,
        command: &str,
        log_target: Arc<Mutex<LogTarget>>,
    ) -> Result<String, Box<dyn std::error::Error>> {
        let args = [
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "PasswordAuthentication=no",
            "-A",
            connection,
            command,
        ];
        Self::execute("ssh", &args, log_target)
    }

    /// Executes a command locally, feeding content to its stdin.
    pub fn execute_with_stdin(
        program: &str,
        args: &[&str],
        stdin_content: &str,
        log_target: Arc<Mutex<LogTarget>>,
    ) -> Result<String, Box<dyn std::error::Error>> {
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

        let log_target_out = Arc::clone(&log_target);
        let stdout_handle = thread::spawn(move || {
            let mut captured = String::new();
            let reader = BufReader::new(stdout);
            for line in reader.lines() {
                if let Ok(l) = line {
                    if let Ok(mut target) = log_target_out.lock() {
                        match &mut *target {
                            LogTarget::Terminal => {
                                println!("{}", l);
                            }
                            LogTarget::Batch { file, .. } => {
                                let _ = writeln!(file, "{}", l);
                            }
                            LogTarget::File(file) => {
                                let _ = writeln!(file, "{}", l);
                            }
                            LogTarget::Silent => {}
                        }
                    }
                    captured.push_str(&l);
                    captured.push('\n');
                }
            }
            captured
        });

        let log_target_err = Arc::clone(&log_target);
        let stderr_handle = thread::spawn(move || {
            let mut captured = String::new();
            let reader = BufReader::new(stderr);
            for line in reader.lines() {
                if let Ok(l) = line {
                    if let Ok(mut target) = log_target_err.lock() {
                        match &mut *target {
                            LogTarget::Terminal => {
                                eprintln!("{}", l);
                            }
                            LogTarget::Batch { file, .. } => {
                                let _ = writeln!(file, "{}", l);
                            }
                            LogTarget::File(file) => {
                                let _ = writeln!(file, "{}", l);
                            }
                            LogTarget::Silent => {}
                        }
                    }
                    captured.push_str(&l);
                    captured.push('\n');
                }
            }
            captured
        });

        let stdout_output = stdout_handle.join().unwrap_or_default();
        let stderr_output = stderr_handle.join().unwrap_or_default();

        let status = child.wait()?;
        if !status.success() {
            return Err(format!(
                "Command '{} {}' failed with status: {}\nError: {}",
                program,
                args.join(" "),
                status,
                stderr_output
            ).into());
        }

        Ok(stdout_output)
    }

    /// Executes an SSH command remotely, feeding content to stdin.
    pub fn execute_ssh_with_stdin(
        connection: &str,
        command: &str,
        stdin_content: &str,
        log_target: Arc<Mutex<LogTarget>>,
    ) -> Result<String, Box<dyn std::error::Error>> {
        let args = [
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "PasswordAuthentication=no",
            "-A",
            connection,
            command,
        ];
        Self::execute_with_stdin("ssh", &args, stdin_content, log_target)
    }
}
