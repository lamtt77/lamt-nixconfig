#[macro_use]
pub mod progress;

pub mod cli;
pub mod command;
pub mod config;
pub mod context;
pub mod execution;
pub mod fleet;
pub mod identity;
pub mod nix;
pub mod planning;
pub mod process;
pub mod providers;
pub mod remote;
pub mod workflow;
pub mod workspace;

use crate::process::Logger;
use clap::{CommandFactory, Parser};
use cli::{Cli, Commands, WslCommands};
use context::load_batch_contexts;

async fn execute_exec(
	hosts: Option<&String>,
	target: Option<&String>,
	stream: bool,
	command: &[String],
	parallel: usize,
) -> Result<(), Box<dyn std::error::Error>> {
	command::hosts::validate_target_and_hosts(target, hosts)?;
	if target.is_none() && hosts.is_none() {
		return Err("Error: Must specify either -t/--target or --hosts.".into());
	}

	let resolved_hosts = if let Some(target_str) = target {
		vec![target_str.clone()]
	} else {
		let hosts_str = hosts.unwrap();
		command::hosts::resolve_hosts_arg(hosts_str)?
	};

	let planned_hosts = load_batch_contexts(&resolved_hosts, false)
		.map_err(|e| format!("Error loading host contexts: {}", e))?;

	command::exec::execute_command(planned_hosts, command.to_vec(), stream, parallel)
		.await
		.map_err(|e| format!("Execution failed:\n{}", e).into())
}

#[tokio::main]
async fn main() {
	workspace::clean_stale_temp_dirs();
	workspace::clean_stale_gc_roots(Logger::terminal());

	let main_start = std::time::Instant::now();
	let args = Cli::parse();
	if args.debug {
		unsafe {
			std::env::set_var("NXD_DEBUG", "yes");
		}
		println!("Arguments: {:?}", args);
	}

	// Populate and set global runtime options
	let (redeploy, overwrite, build_iso, deploy_active) = match &args.command {
		Commands::Deploy { redeploy, overwrite, build_iso, .. } => {
			(*redeploy, *overwrite, *build_iso, true)
		}
		Commands::Convert { .. } => (false, false, false, true),
		_ => (false, false, false, false),
	};
	let update_host_key = std::env::var("UPDATE_HOST_KEY").unwrap_or_default() == "yes";
	let update_secrets_key = std::env::var("UPDATE_SECRETS_KEY").unwrap_or_default() == "yes";
	let opts = config::RuntimeOptions {
		debug: args.debug,
		force: args.force,
		low_mem: args.low_mem.as_ref().map(|s| s == "yes" || s == "true"),
		build_strategy: args.build_on.clone(),
		builder: args.builder.clone(),
		flake: args.flake.clone(),
		secrets_repo: args.secrets_repo.clone(),
		github_token: args.github_token.clone(),
		redeploy,
		overwrite,
		build_iso,
		deploy_active,
		update_host_key,
		update_secrets_key,
	};
	config::set_runtime_options(opts);

	// Set subprocess-facing environment defaults.
	unsafe {
		std::env::set_var(
			"NIX_SSHOPTS",
			format!(
				"-o {} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR",
				crate::remote::ssh::WARN_WEAK_CRYPTO_OPTION
			),
		);
	}

	let show_duration = matches!(
		&args.command,
		Commands::Deploy { .. }
			| Commands::Switch { .. }
			| Commands::Boot { .. }
			| Commands::Test { .. }
			| Commands::Build { .. }
			| Commands::Destroy { .. }
			| Commands::Convert { .. }
	);

	let cmd_result = match &args.command {
		Commands::Deploy { target, hosts, plan, redeploy, overwrite, build_iso } => {
			let opts = command::deploy::DeployCmdOptions {
				target: target.as_ref(),
				hosts: hosts.as_ref(),
				plan: *plan,
				redeploy: *redeploy,
				overwrite: *overwrite,
				build_iso: *build_iso,
				force: args.force,
				parallel: args.parallel,
			};
			command::deploy::execute_deploy(opts).await
		}
		Commands::Convert { target, to } => {
			command::convert::execute_convert(target, to, args.parallel).await
		}
		Commands::Switch { args: target_args } => {
			command::switch::execute_switch(
				target_args.target.as_ref(),
				target_args.hosts.as_ref(),
				"switch",
				target_args.hm,
				args.force,
				args.parallel,
			)
			.await
		}
		Commands::Boot { args: target_args } => {
			command::switch::execute_switch(
				target_args.target.as_ref(),
				target_args.hosts.as_ref(),
				"bootentry",
				target_args.hm,
				args.force,
				args.parallel,
			)
			.await
		}
		Commands::Test { args: target_args } => {
			command::switch::execute_switch(
				target_args.target.as_ref(),
				target_args.hosts.as_ref(),
				"test",
				target_args.hm,
				args.force,
				args.parallel,
			)
			.await
		}
		Commands::Build { args: target_args, artifact, output } => {
			if let Some(artifact) = artifact {
				if target_args.target.is_some() || target_args.hosts.is_some() || target_args.hm {
					Err("--artifact is mutually exclusive with --target, --hosts, and --hm".into())
				} else {
					match artifact {
						cli::ArtifactKind::MinimalWsl => {
							workflow::artifact::build_minimal_wsl(output.as_deref(), Logger::terminal())
								.map(|_| ())
						}
					}
				}
			} else {
				command::switch::execute_switch(
					target_args.target.as_ref(),
					target_args.hosts.as_ref(),
					"build",
					target_args.hm,
					args.force,
					args.parallel,
				)
				.await
			}
		}
		Commands::Sync { target, keys, repo } => command::sync::execute_sync(target, *keys, *repo),
		Commands::Destroy { target, plan } => command::destroy::execute_destroy(target, *plan),
		Commands::Info { target, ip } => command::info::execute_info(target, *ip),
		Commands::Exec { hosts, target, stream, command } => {
			execute_exec(hosts.as_ref(), target.as_ref(), *stream, command, args.parallel).await
		}
		Commands::Wsl { command: WslCommands::BootstrapSsh { target, public_key } } => {
			command::wsl::execute_bootstrap_ssh(target, public_key.as_deref())
		}
		Commands::Completions { shell } => {
			let mut cmd = Cli::command();
			clap_complete::generate(*shell, &mut cmd, "nxd", &mut std::io::stdout());
			Ok(())
		}
	};

	let elapsed = main_start.elapsed();
	let mins = elapsed.as_secs() / 60;
	let secs = elapsed.as_secs() % 60;

	if show_duration {
		let logger = Logger::terminal();
		match &cmd_result {
			Ok(()) => {
				success!(logger, "Total execution time: {}m {}s", mins, secs);
			}
			Err(e) => {
				eprintln!("{}", e);
				error!(logger, "Operation failed after {}m {}s", mins, secs);
				std::process::exit(1);
			}
		}
	} else if let Err(e) = cmd_result {
		eprintln!("{}", e);
		std::process::exit(1);
	}

	if args.debug {
		let logger = Logger::terminal();
		crate::debug!(logger, "Total Rust main execution: {:?}", main_start.elapsed());
	}
}
