pub mod cli;
pub mod config;
pub mod context;
pub mod process;
pub mod nix;
pub mod pipeline;
pub mod batch;
pub mod providers;
pub mod identity;
pub mod switch;

use clap::{Parser, CommandFactory};
use cli::{Cli, Commands, SwitchAction};
use context::RuntimeContext;
use nix::{NixBuilder, BuildStrategy};
use process::{LogTarget, CommandExecutor};
use std::path::Path;
use std::sync::{Arc, Mutex};

pub fn resolve_provider(
    ctx: &RuntimeContext,
    log_target: Arc<Mutex<LogTarget>>,
) -> Option<Box<dyn providers::VirtualizationProvider>> {
    if !ctx.deployment.vmid.is_empty() && !ctx.deployment.proxmox.host.is_empty() {
        Some(Box::new(providers::proxmox::ProxmoxProvider::new(ctx, log_target)))
    } else if !ctx.deployment.vmware.vmx_path.is_empty() {
        Some(Box::new(providers::vmware::VmwareProvider::new(ctx, log_target)))
    } else if !ctx.deployment.digitalocean.region.is_empty() {
        Some(Box::new(providers::digitalocean::DigitalOceanProvider::new(ctx, log_target)))
    } else {
        None
    }
}

pub fn resolve_magic_dns_or_tailscale(hostname: &str) -> Option<String> {
    // 1. Try tailscale CLI
    let ts_output = std::process::Command::new("tailscale")
        .args(&["ip", hostname])
        .output();
    if let Ok(out) = ts_output {
        if out.status.success() {
            let ip = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !ip.is_empty() {
                if let Some(first_ip) = ip.lines().next() {
                    let cleaned = first_ip.trim().to_string();
                    if !cleaned.is_empty() {
                        return Some(cleaned);
                    }
                }
            }
        }
    }

    // 2. Try standard DNS resolution (respects local host search domains)
    use std::net::ToSocketAddrs;
    if let Ok(mut addrs) = format!("{}:0", hostname).to_socket_addrs() {
        if let Some(addr) = addrs.next() {
            let ip = addr.ip().to_string();
            // Ignore loopback addresses
            if ip != "127.0.0.1" && ip != "::1" {
                return Some(ip);
            }
        }
    }

    None
}

pub fn resolve_target_ip(ctx: &RuntimeContext, log_target: Arc<Mutex<LogTarget>>) -> String {
    if ctx.is_ip_overridden {
        log_status!(log_target, "Using overridden target IP for {}: {}", ctx.hostname, ctx.target_ip);
        return ctx.target_ip.clone();
    }

    // 1. Try MagicDNS / Tailscale first (before invoking provider)
    if let Some(ip) = resolve_magic_dns_or_tailscale(&ctx.hostname) {
        log_status!(log_target, "Resolved dynamic IP via MagicDNS/Tailscale for {}: {}", ctx.hostname, ip);
        return ip;
    }

    // 2. Fall back to provider resolution
    if let Some(provider) = resolve_provider(ctx, Arc::clone(&log_target)) {
        if let Ok(ip) = provider.get_ip() {
            if !ip.is_empty() {
                return ip;
            }
        }
    }

    ctx.target_ip.clone()
}

pub fn parse_host_spec(spec: &str) -> (String, Option<String>, Option<String>) {
    let mut username = None;
    let mut hostname = spec.trim().to_string();
    let mut ip = None;

    if let Some(at_pos) = hostname.find('@') {
        let u = hostname[..at_pos].trim().to_string();
        if !u.is_empty() {
            username = Some(u);
        }
        hostname = hostname[at_pos + 1..].trim().to_string();
    }

    if let Some(eq_pos) = hostname.find('=') {
        let i = hostname[eq_pos + 1..].trim().to_string();
        if !i.is_empty() {
            ip = Some(i);
        }
        hostname = hostname[..eq_pos].trim().to_string();
    }

    (hostname, username, ip)
}

pub fn load_context_from_spec(spec: &str) -> Result<RuntimeContext, Box<dyn std::error::Error>> {
    let (hostname, username_override, ip_override) = parse_host_spec(spec);
    let mut ctx = RuntimeContext::load(&hostname)?;
    if let Some(ip) = ip_override {
        ctx.target_ip = ip;
        ctx.is_ip_overridden = true;
    }
    if let Some(username) = username_override {
        if username != ctx.username && username != "root" {
            let is_forced = std::env::var("CLI_FORCE").unwrap_or_default() == "yes";
            if !is_forced {
                eprintln!(
                    "WARNING: Specified username '{}' does not match the user '{}' configured in the NixOS flake for host '{}'.",
                    username, ctx.username, hostname
                );
                if !dialoguer::Confirm::new()
                    .with_prompt("Do you want to proceed anyway?")
                    .default(false)
                    .interact()
                    .unwrap_or(false)
                {
                    return Err("Aborted due to username mismatch.".into());
                }
            }
        }
        ctx.username = username;
    }
    Ok(ctx)
}

#[tokio::main]
async fn main() {
    let args = Cli::parse();
    if args.debug {
        println!("Arguments: {:?}", args);
    }

    // Set overrides from global arguments in the environment
    std::env::set_var("NIX_SSHOPTS", "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR");
    if args.force {
        std::env::set_var("CLI_FORCE", "yes");
    }
    if let Some(ref low_mem) = args.low_mem {
        std::env::set_var("LOW_MEM", low_mem);
    }
    if let Some(ref build_on) = args.build_on {
        std::env::set_var("BUILD_ON", build_on);
    }
    if let Some(ref builder) = args.builder {
        std::env::set_var("BUILDER", builder);
    }
    std::env::set_var("NIX_REPO", &args.repo_src);

    match &args.command {
        Commands::Deploy { target, hosts, plan, redeploy } => {
            // Check if we are running in batch mode
            if let Some(hosts_str) = hosts {
                std::env::set_var("BATCH_HOSTS", hosts_str);
                let host_list: Vec<String> = hosts_str
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect();

                if host_list.is_empty() {
                    eprintln!("Error: --hosts list is empty.");
                    std::process::exit(1);
                }

                // Load configurations for all targets
                let mut planned_hosts = Vec::new();
                for host in &host_list {
                    println!("Loading configuration for target {}...", host);
                    match load_context_from_spec(host) {
                        Ok(mut ctx) => {
                            // Resolve target IP upfront
                            let log_target = Arc::new(Mutex::new(LogTarget::Terminal));
                            ctx.target_ip = resolve_target_ip(&ctx, log_target);
                            planned_hosts.push(ctx);
                        }
                        Err(e) => {
                            eprintln!("Error loading target context for {}: {}", host, e);
                            std::process::exit(1);
                        }
                    }
                }

                // 1. Dry run / planning output
                let log_target = Arc::new(Mutex::new(LogTarget::Terminal));
                println!("================ Planning for Batch/Fleet Deployment ================");
                for ctx in &planned_hosts {
                    let provider = resolve_provider(ctx, Arc::clone(&log_target));
                    let provider_name = if provider.is_some() {
                        if !ctx.deployment.proxmox.host.is_empty() {
                            "Proxmox VM".to_string()
                        } else if !ctx.deployment.vmware.vmx_path.is_empty() {
                            "VMware VM".to_string()
                        } else if !ctx.deployment.digitalocean.region.is_empty() {
                            "DigitalOcean".to_string()
                        } else {
                            "Detected Virtualization".to_string()
                        }
                    } else {
                        "None (Standard)".to_string()
                    };

                    let builder = NixBuilder::resolve(ctx);
                    let strategy_name = match &builder.strategy {
                        BuildStrategy::Local => "Local (Natively on Orchestrator)".to_string(),
                        BuildStrategy::RemoteBuilder { ssh_connection } => {
                            format!("RemoteBuilder (Delegated via SSH to {})", ssh_connection)
                        }
                        BuildStrategy::TargetInstantiated => {
                            "TargetInstantiated (Instantiation on Orchestrator -> Realization on Target)".to_string()
                        }
                        BuildStrategy::TargetNative => {
                            "TargetNative (Natively built directly on target)".to_string()
                        }
                    };

                    println!("Host: {}", ctx.hostname);
                    println!("  Target IP:   {}", ctx.target_ip);
                    println!("  Provider:    {}", provider_name);
                    println!("  Build On:    {}", strategy_name);
                    println!("  Low Memory:  {}", ctx.deployment.low_mem);

                    if !ctx.deployment.proxmox.cores.is_empty() {
                        println!("  CPU Cores:   {}", ctx.deployment.proxmox.cores);
                    }
                    if !ctx.deployment.proxmox.memory.is_empty() {
                        println!("  RAM Memory:  {} MB", ctx.deployment.proxmox.memory);
                    }
                    if !ctx.deployment.disk_size.is_empty() {
                        println!("  Disk Size:   {} GB", ctx.deployment.disk_size);
                    }
                    if !ctx.deployment.digitalocean.size.is_empty() {
                        println!("  DO Size:     {}", ctx.deployment.digitalocean.size);
                    }
                    if !ctx.deployment.digitalocean.region.is_empty() {
                        println!("  DO Region:   {}", ctx.deployment.digitalocean.region);
                    }
                    println!("----------------------------------------------------");
                }
                println!("====================================================================");

                if *plan {
                    return;
                }

                let mut existing_hosts = Vec::new();
                for ctx in &planned_hosts {
                    let provider = resolve_provider(ctx, Arc::clone(&log_target));
                    if let Some(ref p) = provider {
                        if p.exists() {
                            existing_hosts.push(ctx.hostname.clone());
                        }
                    }
                }

                if *redeploy {
                    if !args.force {
                        println!("WARNING: Redeployment is a destructive action that will DESTROY and RE-CREATE VM/Droplet instances for the planned hosts!");
                        if !dialoguer::Confirm::new()
                            .with_prompt("Are you sure you want to proceed with batch redeployment?")
                            .default(false)
                            .interact()
                            .unwrap_or(false)
                        {
                            println!("Batch redeployment aborted by user.");
                            std::process::exit(0);
                        }
                    }
                } else {
                    if !args.force {
                        if !existing_hosts.is_empty() {
                            println!("WARNING: Existing VM/Droplet instances were detected for the following hosts: {:?}", existing_hosts);
                            println!("Running deploy without --redeploy will STILL format and perform a clean NixOS installation over these existing VMs, erasing their disks!");
                            if !dialoguer::Confirm::new()
                                .with_prompt("Are you sure you want to proceed with batch deployment?")
                                .default(false)
                                .interact()
                                .unwrap_or(false)
                            {
                                println!("Batch deployment aborted by user.");
                                std::process::exit(0);
                            }
                        } else {
                            if !dialoguer::Confirm::new()
                                .with_prompt("Do you want to proceed with batch deployment?")
                                .default(false)
                                .interact()
                                .unwrap_or(false)
                            {
                                println!("Batch deployment aborted by user.");
                                std::process::exit(0);
                            }
                        }
                    }
                }

                println!("Launching batch deployment...");
                if let Err(e) = batch::BatchRunner::deploy_batch(planned_hosts, *redeploy).await {
                    eprintln!("Batch deployment failed: {}", e);
                    std::process::exit(1);
                }
            } else if let Some(host) = target {
                println!("Loading configuration for target {}...", host);
                match load_context_from_spec(host) {
                    Ok(mut ctx) => {
                        let log_target = Arc::new(Mutex::new(LogTarget::Terminal));
                        let provider = resolve_provider(&ctx, Arc::clone(&log_target));

                        // 1. Dry run / planning output
                        if *plan {
                            println!("================ Planning for {} ================", ctx.hostname);
                            println!("Target IP: {}", ctx.target_ip);
                            println!("Target System Architecture: {}", ctx.system);
                            println!("Primary User: {}", ctx.username);
                            println!("Low Memory Mode: {}", ctx.deployment.low_mem);

                            if !ctx.deployment.proxmox.cores.is_empty() {
                                println!("CPU Cores: {}", ctx.deployment.proxmox.cores);
                            }
                            if !ctx.deployment.proxmox.memory.is_empty() {
                                println!("RAM Memory: {} MB", ctx.deployment.proxmox.memory);
                            }
                            if !ctx.deployment.disk_size.is_empty() {
                                println!("Disk Size: {} GB", ctx.deployment.disk_size);
                            }
                            if !ctx.deployment.digitalocean.size.is_empty() {
                                println!("DigitalOcean Size: {}", ctx.deployment.digitalocean.size);
                            }
                            if !ctx.deployment.digitalocean.region.is_empty() {
                                println!("DigitalOcean Region: {}", ctx.deployment.digitalocean.region);
                            }

                            let ip = resolve_target_ip(&ctx, Arc::clone(&log_target));
                            if provider.is_some() {
                                println!("Virtualization Provider: Detected");
                                println!("  Resolved Dynamic IP: {}", ip);
                            } else {
                                println!("Virtualization Provider: None");
                                if ip != ctx.hostname {
                                    println!("  Resolved DNS/Tailscale IP: {}", ip);
                                }
                            }

                            let builder = NixBuilder::resolve(&ctx);
                            let strategy_name = match &builder.strategy {
                                BuildStrategy::Local => "Local (Natively on Orchestrator)".to_string(),
                                BuildStrategy::RemoteBuilder { ssh_connection } => {
                                    format!("RemoteBuilder (Delegated via SSH to {})", ssh_connection)
                                }
                                BuildStrategy::TargetInstantiated => {
                                    "TargetInstantiated (Instantiation on Orchestrator -> Realization on Target)".to_string()
                                }
                                BuildStrategy::TargetNative => {
                                    "TargetNative (Natively built directly on target)".to_string()
                                }
                            };
                            println!("Resolved Build Strategy: {}", strategy_name);
                            println!("==================================================");
                            return;
                        }

                        // 2. Perform redeploy (recreate VM/droplet) if VM provider exists
                        if *redeploy {
                            if !args.force {
                                let prompt = format!("WARNING: Redeployment is a destructive action that will DESTROY and RE-CREATE VM instance for {}. Are you sure you want to proceed?", host);
                                if !dialoguer::Confirm::new()
                                    .with_prompt(&prompt)
                                    .default(false)
                                    .interact()
                                    .unwrap_or(false)
                                {
                                    println!("Redeployment aborted by user.");
                                    std::process::exit(0);
                                }
                            }

                            if let Some(ref p) = provider {
                                println!("Redeploy: Destroying existing instance...");
                                let _ = p.destroy();
                                println!("Redeploy: Re-creating instance...");
                                if let Err(e) = p.create() {
                                    eprintln!("Error recreating instance: {}", e);
                                    std::process::exit(1);
                                }
                            }
                        } else {
                            if let Some(ref p) = provider {
                                if p.exists() && !args.force {
                                    let prompt = format!("WARNING: Host VM for {} already exists on the hypervisor. Running deploy without --redeploy will STILL format and perform a clean NixOS installation over the existing VM, erasing its disks. Are you sure you want to proceed?", host);
                                    if !dialoguer::Confirm::new()
                                        .with_prompt(&prompt)
                                        .default(false)
                                        .interact()
                                        .unwrap_or(false)
                                    {
                                        println!("Deployment aborted by user.");
                                        std::process::exit(0);
                                    }
                                }
                            }
                        }

                        // 3. Resolve dynamic IP
                        ctx.target_ip = resolve_target_ip(&ctx, Arc::clone(&log_target));

                        // 4. Execute deployment
                        if let Err(e) = pipeline::run_deployment(&ctx, Arc::clone(&log_target)) {
                            eprintln!("Deployment failed: {}", e);
                            std::process::exit(1);
                        }
                    }
                    Err(e) => {
                        eprintln!("Error loading target context: {}", e);
                        std::process::exit(1);
                    }
                }
            } else {
                eprintln!("Error: Specify either --target <hostname> or --hosts <comma-separated-list>.");
                std::process::exit(1);
            }
        }
        Commands::Switch { target, hosts, action, hm } => {
            let action_str = match action {
                SwitchAction::Switch => "switch",
                SwitchAction::Bootentry => "bootentry",
                SwitchAction::Test => "test",
                SwitchAction::Build => "build",
            };

            if let Some(hosts_str) = hosts {
                std::env::set_var("BATCH_HOSTS", hosts_str);
                let host_list: Vec<String> = hosts_str
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect();

                if host_list.is_empty() {
                    eprintln!("Error: --hosts list is empty.");
                    std::process::exit(1);
                }

                // Load configurations for all targets
                let mut planned_hosts = Vec::new();
                for host in &host_list {
                    println!("Loading configuration for target {}...", host);
                    match load_context_from_spec(host) {
                        Ok(mut ctx) => {
                            // Resolve target IP upfront if provider exists and is running
                            let log_target = Arc::new(Mutex::new(LogTarget::Terminal));
                            ctx.target_ip = resolve_target_ip(&ctx, Arc::clone(&log_target));
                            // Validate and sync host key
                            if let Err(e) = identity::ssh::validate_and_sync_target_host_key(&ctx, Arc::clone(&log_target)) {
                                eprintln!("Error validating/syncing target host key for {}: {}", host, e);
                                std::process::exit(1);
                            }
                            planned_hosts.push(ctx);
                        }
                        Err(e) => {
                            eprintln!("Error loading target context for {}: {}", host, e);
                            std::process::exit(1);
                        }
                    }
                }

                // 1. Dry run / planning output for Batch Switch
                let log_target = Arc::new(Mutex::new(LogTarget::Terminal));
                println!("================ Planning for Batch/Fleet Switch ================");
                for ctx in &planned_hosts {
                    let provider = resolve_provider(ctx, Arc::clone(&log_target));
                    let provider_name = if provider.is_some() {
                        if !ctx.deployment.proxmox.host.is_empty() {
                            "Proxmox VM".to_string()
                        } else if !ctx.deployment.vmware.vmx_path.is_empty() {
                            "VMware VM".to_string()
                        } else if !ctx.deployment.digitalocean.region.is_empty() {
                            "DigitalOcean".to_string()
                        } else {
                            "Detected Virtualization".to_string()
                        }
                    } else {
                        "None (Standard)".to_string()
                    };

                    let builder = NixBuilder::resolve(ctx);
                    let strategy_name = match &builder.strategy {
                        BuildStrategy::Local => "Local (Natively on Orchestrator)".to_string(),
                        BuildStrategy::RemoteBuilder { ssh_connection } => {
                            format!("RemoteBuilder (Delegated via SSH to {})", ssh_connection)
                        }
                        BuildStrategy::TargetInstantiated => {
                            "TargetInstantiated (Instantiation on Orchestrator -> Realization on Target)".to_string()
                        }
                        BuildStrategy::TargetNative => {
                            "TargetNative (Natively built directly on target)".to_string()
                        }
                    };

                    println!("Host: {}", ctx.hostname);
                    println!("  Target IP:   {}", ctx.target_ip);
                    println!("  Provider:    {}", provider_name);
                    println!("  Build On:    {}", strategy_name);
                    println!("  Action:      {}", action_str);
                    println!("  HomeManager: {}", if *hm { "Yes" } else { "No" });
                    println!("----------------------------------------------------");
                }
                println!("=================================================================");

                // Prompt user for confirmation before batch switch
                if !args.force {
                    let prompt = format!("Are you sure you want to proceed with batch/fleet switch for hosts: {:?}?", host_list);
                    if !dialoguer::Confirm::new()
                        .with_prompt(&prompt)
                        .default(false)
                        .interact()
                        .unwrap_or(false)
                    {
                        println!("Batch switch aborted by user.");
                        std::process::exit(0);
                    }
                }

                println!("Launching batch switch...");
                if let Err(e) = batch::BatchRunner::switch_batch(planned_hosts, action_str.to_string(), *hm).await {
                    eprintln!("Batch switch failed: {}", e);
                    std::process::exit(1);
                }
            } else if let Some(host) = target {
                match load_context_from_spec(host) {
                    Ok(mut ctx) => {
                        let log_target = Arc::new(Mutex::new(LogTarget::Terminal));
                        ctx.target_ip = resolve_target_ip(&ctx, Arc::clone(&log_target));
                        // Validate and sync target host key
                        if let Err(e) = identity::ssh::validate_and_sync_target_host_key(&ctx, Arc::clone(&log_target)) {
                            eprintln!("Error validating/syncing target host key: {}", e);
                            std::process::exit(1);
                        }
                        if let Err(e) = switch::run_switch(&ctx, action_str, *hm, Arc::clone(&log_target)) {
                            eprintln!("Switch failed: {}", e);
                            std::process::exit(1);
                        }
                    }
                    Err(e) => {
                        eprintln!("Error loading target context: {}", e);
                        std::process::exit(1);
                    }
                }
            } else {
                eprintln!("Error: Specify either --target <hostname> or --hosts <comma-separated-list>.");
                std::process::exit(1);
            }
        }
        Commands::Sync { target, keys, repo } => {
            match load_context_from_spec(target) {
                Ok(mut ctx) => {
                    let log_target = Arc::new(Mutex::new(LogTarget::Terminal));
                    ctx.target_ip = resolve_target_ip(&ctx, Arc::clone(&log_target));

                    if *keys {
                        println!("Syncing SSH and GPG keys to target {}...", target);
                        // Validate and sync target host key
                        if let Err(e) = identity::ssh::validate_and_sync_target_host_key(&ctx, Arc::clone(&log_target)) {
                            eprintln!("Error validating/syncing target host key: {}", e);
                            std::process::exit(1);
                        }

                        let ssh_service = identity::ssh::SshKeyService::new(Arc::clone(&log_target));
                        let gpg_service = identity::gpg::GpgService::new(Arc::clone(&log_target));

                        if let Err(e) = ssh_service.sync_personal_keys(&ctx, Path::new("/")) {
                            eprintln!("Failed to sync SSH keys: {}", e);
                            std::process::exit(1);
                        }
                        if let Err(e) = gpg_service.sync_gpg_credentials(&ctx, Path::new("/")) {
                            eprintln!("Failed to sync GPG keys: {}", e);
                            std::process::exit(1);
                        }
                        println!("Credentials sync complete.");
                    }

                    if *repo {
                        println!("Syncing codebase repository to target {}...", target);
                        let target_dest = format!("root@{}", ctx.target_ip);
                        let target_dir = crate::config::nix_cfg();
                        let tar_cmd = "tar --exclude=\".git\" --exclude=\"result\" --exclude=\".DS_Store\" --exclude=\"target\" -czf - -C . .";
                        let untar_cmd = format!("rm -rf {} && mkdir -p {} && tar -xzf - -C {}", target_dir, target_dir, target_dir);
                        let pipe_cmd = format!("{} | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -A {} \"{}\"",
                            tar_cmd, target_dest, untar_cmd
                        );

                        if let Err(e) = CommandExecutor::execute("bash", &["-c", &pipe_cmd], log_target) {
                            eprintln!("Failed to sync codebase repository: {}", e);
                            std::process::exit(1);
                        }
                        println!("Repository codebase sync complete.");
                    }
                }
                Err(e) => {
                    eprintln!("Error loading target context: {}", e);
                    std::process::exit(1);
                }
            }
        }
        Commands::Destroy { target } => {
            match load_context_from_spec(target) {
                Ok(ctx) => {
                    let log_target = Arc::new(Mutex::new(LogTarget::Terminal));
                    if let Some(provider) = resolve_provider(&ctx, log_target) {
                        println!("Requesting destruction of instance {}...", target);
                        if let Err(e) = provider.destroy() {
                            eprintln!("Destroy failed: {}", e);
                            std::process::exit(1);
                        }
                        println!("Destruction complete.");
                    } else {
                        eprintln!("Error: Target {} is not managed by a VM provider.", target);
                        std::process::exit(1);
                    }
                }
                Err(e) => {
                    eprintln!("Error loading target context: {}", e);
                    std::process::exit(1);
                }
            }
        }
        Commands::Info { target, ip } => {
            match load_context_from_spec(target) {
                Ok(mut ctx) => {
                    let log_target = if *ip {
                        Arc::new(Mutex::new(LogTarget::Silent))
                    } else {
                        Arc::new(Mutex::new(LogTarget::Terminal))
                    };

                    // Resolve target IP (dynamic scans/dns will run silently if --ip is requested)
                    ctx.target_ip = resolve_target_ip(&ctx, Arc::clone(&log_target));

                    let provider = resolve_provider(&ctx, log_target);

                    if *ip {
                        println!("{}", ctx.target_ip);
                    } else {
                        println!("Hostname: {}", ctx.hostname);
                        println!("Target IP: {}", ctx.target_ip);
                        println!("System: {}", ctx.system);
                        println!("Primary User: {}", ctx.username);
                        println!("Low Memory: {}", ctx.deployment.low_mem);
                        println!("VMID: {}", ctx.deployment.vmid);
                        println!("Disk Size: {}", ctx.deployment.disk_size);
                        if provider.is_some() {
                            println!("Virtualization Provider: Yes");
                        } else {
                            println!("Virtualization Provider: No");
                        }
                    }
                }
                Err(e) => {
                    eprintln!("Error loading target context: {}", e);
                    std::process::exit(1);
                }
            }
        }
        Commands::Completions { shell } => {
            let mut cmd = Cli::command();
            clap_complete::generate(*shell, &mut cmd, "lamd", &mut std::io::stdout());
        }
    }
}
