#[macro_use]
pub mod progress;

pub mod cli;
pub mod command;
pub mod config;
pub mod context;
pub mod executor;
pub mod fleet;
pub mod identity;
pub mod nix;
pub mod operation;
pub use operation::deploy as pipeline;
pub use operation::plan;
pub mod providers;
pub mod remote;
pub mod workspace;

pub use executor::batch;
pub use executor::host as runner;
pub use executor::process;

use crate::process::Logger;
use clap::{CommandFactory, Parser};
use cli::{Cli, Commands};
use context::load_batch_contexts;

#[tokio::main]
async fn main() {
    workspace::clean_legacy_workspaces();

    let main_start = std::time::Instant::now();
    let args = Cli::parse();
    if args.debug {
        std::env::set_var("INSTALLER_RS_DEBUG", "yes");
        println!("Arguments: {:?}", args);
    }

    // Populate and set global runtime options
    let (redeploy, overwrite, deploy_active) = match &args.command {
        Commands::Deploy {
            redeploy,
            overwrite,
            ..
        } => (*redeploy, *overwrite, true),
        _ => (false, false, false),
    };
    let update_host_key = std::env::var("UPDATE_HOST_KEY").unwrap_or_default() == "yes";
    let update_secrets_key = std::env::var("UPDATE_SECRETS_KEY").unwrap_or_default() == "yes";
    let opts = config::RuntimeOptions {
        debug: args.debug,
        force: args.force,
        low_mem: args.low_mem.as_ref().map(|s| s == "yes" || s == "true"),
        build_strategy: args.build_on.clone(),
        builder: args.builder.clone(),
        repo_src: args.repo_src.clone(),
        redeploy,
        overwrite,
        deploy_active,
        update_host_key,
        update_secrets_key,
    };
    config::set_runtime_options(opts);

    // Set subprocess-facing environment defaults.
    std::env::set_var(
        "NIX_SSHOPTS",
        "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR",
    );
    std::env::set_var("NIX_REPO", &args.repo_src);

    match &args.command {
        Commands::Deploy {
            target,
            hosts,
            plan,
            redeploy,
            overwrite,
            convert_to,
        } => {
            let opts = command::deploy::DeployCmdOptions {
                target: target.as_ref(),
                hosts: hosts.as_ref(),
                plan: *plan,
                redeploy: *redeploy,
                overwrite: *overwrite,
                convert_to: convert_to.as_ref(),
                force: args.force,
                parallel: args.parallel,
            };
            if let Err(e) = command::deploy::execute_deploy(opts).await {
                eprintln!("{}", e);
                std::process::exit(1);
            }
        }
        Commands::Switch {
            target,
            hosts,
            action,
            hm,
        } => {
            if let Err(e) = command::switch::execute_switch(
                target.as_ref(),
                hosts.as_ref(),
                action,
                *hm,
                args.force,
                args.parallel,
            )
            .await
            {
                eprintln!("{}", e);
                std::process::exit(1);
            }
        }
        Commands::Sync { target, keys, repo } => {
            if let Err(e) = command::sync::execute_sync(target, *keys, *repo) {
                eprintln!("{}", e);
                std::process::exit(1);
            }
        }
        Commands::Destroy { target } => {
            if let Err(e) = command::destroy::execute_destroy(target) {
                eprintln!("{}", e);
                std::process::exit(1);
            }
        }
        Commands::Info { target, ip } => {
            if let Err(e) = command::info::execute_info(target, *ip) {
                eprintln!("{}", e);
                std::process::exit(1);
            }
        }
        Commands::Exec {
            hosts,
            target,
            stream,
            command,
        } => {
            if let Err(e) =
                command::hosts::validate_target_and_hosts(target.as_ref(), hosts.as_ref())
            {
                eprintln!("{}", e);
                std::process::exit(1);
            }
            if target.is_none() && hosts.is_none() {
                eprintln!("Error: Must specify either -t/--target or --hosts.");
                std::process::exit(1);
            }

            let resolved_hosts = if let Some(target_str) = target {
                vec![target_str.clone()]
            } else {
                let hosts_str = hosts.as_ref().unwrap();
                match command::hosts::resolve_hosts_arg(hosts_str) {
                    Ok(hosts) => hosts,
                    Err(e) => {
                        eprintln!("{}", e);
                        std::process::exit(1);
                    }
                }
            };

            let planned_hosts = match load_batch_contexts(&resolved_hosts, false) {
                Ok(contexts) => contexts,
                Err(e) => {
                    eprintln!("Error loading host contexts: {}", e);
                    std::process::exit(1);
                }
            };

            if let Err(e) = command::exec::execute_command(
                planned_hosts,
                command.clone(),
                *stream,
                args.parallel,
            )
            .await
            {
                eprintln!("Execution failed:\n{}", e);
                std::process::exit(1);
            }
        }
        Commands::Completions { shell } => {
            let mut cmd = Cli::command();
            clap_complete::generate(*shell, &mut cmd, "lamd", &mut std::io::stdout());
        }
    }

    if args.debug {
        let logger = Logger::terminal();
        crate::debug!(
            logger,
            "Total Rust main execution: {:?}",
            main_start.elapsed()
        );
    }
}
