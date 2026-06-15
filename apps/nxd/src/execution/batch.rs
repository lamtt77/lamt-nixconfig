use crate::context::RuntimeContext;
use crate::execution::host::HostExecutionContext;
use crate::planning::OperationKind;
use crate::process::Logger;
use crate::progress::log::print_elapsed_summary;
use crate::workspace::PreparedSourceSet;
use std::io::BufRead;
use std::sync::Arc;
use tokio::task;

pub struct PreparedHostJob {
	pub context: RuntimeContext,
	pub transfer_destinations: Vec<String>,
	pub operation: OperationKind,
	pub execution: HostExecutionContext,
}

pub struct BatchRunner;

fn print_log_tail(log_path: &str, lines_count: usize) {
	if let Ok(file) = std::fs::File::open(log_path) {
		let reader = std::io::BufReader::new(file);
		let lines: Vec<String> = reader.lines().map_while(Result::ok).collect();
		let start = lines.len().saturating_sub(lines_count);
		eprintln!("\n=== Last {} lines of {} ===", lines_count, log_path);
		for line in &lines[start..] {
			eprintln!("{}", line);
		}
		eprintln!("======================================\n");
	}
}

fn print_batch_summary(title: &str, succeeded: usize, failed_hosts: &[(String, String)]) {
	let mode = crate::progress::color::ColorMode::Auto;
	let separator = "=".repeat(title.len());

	println!("\n{}", crate::progress::color::colorize(title, crate::progress::color::BOLD, mode));
	println!(
		"Succeeded: {}",
		crate::progress::color::colorize(&succeeded.to_string(), crate::progress::color::GREEN, mode)
	);
	if failed_hosts.is_empty() {
		println!(
			"Failed: {}",
			crate::progress::color::colorize("0", crate::progress::color::GREEN, mode)
		);
	} else {
		println!(
			"Failed: {}",
			crate::progress::color::colorize(
				&failed_hosts.len().to_string(),
				crate::progress::color::RED,
				mode
			)
		);
		for (host, error) in failed_hosts {
			println!(
				"  - {}: {}",
				crate::progress::color::colorize(host, crate::progress::color::RED, mode),
				error
			);
			println!("    Log file: .log/nxd-{}.log", host);
		}
	}
	println!("{}", crate::progress::color::colorize(&separator, crate::progress::color::BOLD, mode));
}

impl BatchRunner {
	pub async fn run(
		jobs: Vec<PreparedHostJob>,
		source_set: Arc<PreparedSourceSet>,
		parallel: usize,
	) -> Result<(), Box<dyn std::error::Error>> {
		let start_time = std::time::Instant::now();
		std::fs::create_dir_all(".log")
			.map_err(|error| format!("Failed to create log directory .log: {}", error))?;

		let operation = jobs.first().map(|job| job.operation).unwrap_or(OperationKind::Switch);
		let semaphore = (parallel > 0).then(|| Arc::new(tokio::sync::Semaphore::new(parallel)));
		let mut handles = Vec::new();

		for job in jobs {
			let host_name = job.context.hostname.clone();
			let source_set = source_set.clone();
			let permit = if let Some(semaphore) = &semaphore {
				Some(
					semaphore
						.clone()
						.acquire_owned()
						.await
						.map_err(|_| "Failed to acquire concurrency permit")?,
				)
			} else {
				None
			};

			let task_host_name = host_name.clone();
			let handle = task::spawn_blocking(move || -> Result<(), String> {
				let log_path = format!(".log/nxd-{}.log", task_host_name);
				let log_file = std::fs::File::create(&log_path)
					.map_err(|error| format!("Failed to create log file {}: {}", log_path, error))?;
				let logger = Logger::batch(task_host_name, log_file);
				let mut execution = job.execution;
				execution.logger = logger.clone();

				let mut workspace = crate::workspace::prepare_store_workspace(
					&job.context,
					&source_set,
					job.transfer_destinations,
					logger,
				)
				.map_err(|error| format!("Workspace preparation failed: {}", error))?;

				crate::execution::host::execute_host_operation(job.operation, &execution, &mut workspace)
					.map_err(|error| {
					print_log_tail(&log_path, 20);
					format!("Host operation failed: {}", error)
				})?;

				let _permit = permit;
				Ok(())
			});
			handles.push((host_name, handle));
		}

		let mut succeeded = 0;
		let mut failed_hosts = Vec::new();
		for (host_name, handle) in handles {
			match handle.await {
				Ok(Ok(())) => succeeded += 1,
				Ok(Err(error)) => failed_hosts.push((host_name, error)),
				Err(error) => failed_hosts.push((host_name, format!("Task panicked: {}", error))),
			}
		}

		let title = match operation {
			OperationKind::Deploy => "=== Batch Deployment Summary ===",
			OperationKind::Switch => "=== Batch Switch Summary ===",
		};
		print_batch_summary(title, succeeded, &failed_hosts);
		if !failed_hosts.is_empty() {
			return Err(format!("Batch operation failed for {} hosts", failed_hosts.len()).into());
		}

		let label = match operation {
			OperationKind::Deploy => "Batch deployment successfully",
			OperationKind::Switch => "Batch switch successfully",
		};
		print_elapsed_summary(label, start_time.elapsed());
		Ok(())
	}
}
