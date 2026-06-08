use clap::Parser;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use tokio::signal;

#[path = "../pve_bootstrap/config.rs"]
mod config;
#[path = "../pve_bootstrap/dnsmasq.rs"]
mod dnsmasq;
#[path = "../pve_bootstrap/interface.rs"]
mod interface;

#[derive(Parser, Debug)]
#[command(
    name = "pve-bootstrap-server",
    about = "Portable Proxmox VE bootstrap server providing DHCP, TFTP, and HTTP"
)]
struct Args {
    #[arg(long, required = true)]
    target: String,

    #[arg(long, required = true)]
    interface: String,

    #[arg(long, required = true)]
    listen_ip: String,

    #[arg(long, required = true)]
    dhcp_range: String,

    #[arg(long)]
    assets_dir: Option<String>,

    #[arg(long, default_value = "/run/pve-bootstrap")]
    workdir: String,

    #[arg(long)]
    dry_run: bool,

    #[arg(long, short = 'F')]
    force: bool,

    #[arg(long, short = 'd')]
    debug: bool,
}

fn resolve_pve_answer_server_path() -> Result<PathBuf, Box<dyn std::error::Error>> {
    // Check path first
    if let Ok(output) = Command::new("which").arg("pve-answer-server").output() {
        if output.status.success() {
            let path_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
            return Ok(PathBuf::from(path_str));
        }
    }

    // Fallback to nix build
    println!("Building pve-answer-server via nix...");
    let output = Command::new("nix")
        .args([
            "build",
            ".#pve-answer-server",
            "--no-link",
            "--print-out-paths",
        ])
        .output()?;

    if !output.status.success() {
        return Err(format!(
            "Failed to resolve pve-answer-server: {}",
            String::from_utf8_lossy(&output.stderr)
        )
        .into());
    }

    let path_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
    Ok(PathBuf::from(path_str).join("bin/pve-answer-server"))
}

fn build_assets(target: &str, listen_ip: &str) -> Result<PathBuf, Box<dyn std::error::Error>> {
    println!(
        "Building custom PXE assets for target '{}' with bootstrap IP '{}'...",
        target, listen_ip
    );
    let expr = format!(
        "(builtins.getFlake \"path:.\").packages.x86_64-linux.pve-pxe-assets.passthru.mkPvePxeAssets {{ target = \"{}\"; bootstrapIp = \"{}\"; }}",
        target, listen_ip
    );
    let output = Command::new("nix")
        .args([
            "build",
            "--impure",
            "--expr",
            &expr,
            "--no-link",
            "--print-out-paths",
        ])
        .output()?;

    if !output.status.success() {
        return Err(format!(
            "Failed to build PXE assets: {}",
            String::from_utf8_lossy(&output.stderr)
        )
        .into());
    }

    let path_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
    Ok(PathBuf::from(path_str))
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 1. Linux check
    if env::consts::OS != "linux" {
        eprintln!("Error: pve-bootstrap-server must run on Linux.");
        std::process::exit(1);
    }

    let args = Args::parse();

    // 2. Privilege check
    if !args.dry_run {
        let uid_output = Command::new("id").arg("-u").output()?;
        let uid_str = String::from_utf8_lossy(&uid_output.stdout)
            .trim()
            .to_string();
        if uid_str != "0" {
            eprintln!("Error: pve-bootstrap-server must run as root (UID 0 / sudo).");
            std::process::exit(1);
        }
    }

    // 3. Interface validation
    if !args.dry_run {
        interface::validate_interface(&args.interface, &args.listen_ip, args.force)?;
        dnsmasq::check_ports_available(&args.listen_ip)?;
    }

    // 4. Resolve assets directory
    let assets_path = match &args.assets_dir {
        Some(dir) => PathBuf::from(dir),
        None => {
            if args.dry_run {
                PathBuf::from("/tmp/pve-pxe-assets")
            } else {
                build_assets(&args.target, &args.listen_ip)?
            }
        }
    };
    let assets_dir_str = assets_path.to_string_lossy().to_string();

    // 5. Validate manifest schema
    if !args.dry_run {
        let manifest = config::validate_manifest(&assets_dir_str)?;
        println!(
            "Loaded manifest for target '{}' (hostname '{}'). Manifest schema: {}.",
            manifest.target_name, manifest.expected_hostname, manifest.schema_version
        );
    }

    // 6. Materialize work directory and answer file
    let workdir_path = Path::new(&args.workdir);
    if !args.dry_run {
        fs::create_dir_all(workdir_path)?;
    }

    let password = config::generate_one_time_password();
    println!("=== SECURE ONE-TIME INSTALLER CREDENTIALS ===");
    println!("Root Password: {}", password);
    println!("=============================================");

    let answer_file = if args.dry_run {
        workdir_path.join("pve-answer.toml")
    } else {
        config::materialize_answer_file(&assets_dir_str, &password, workdir_path)?
    };

    if args.dry_run {
        println!("Dry run complete. No processes started.");
        return Ok(());
    }

    // 7. Resolve Python answer server path
    let python_server_bin = resolve_pve_answer_server_path()?;

    // 8. Start dnsmasq (DHCP + TFTP)
    let mut dnsmasq_child = dnsmasq::start_dnsmasq(
        &args.interface,
        &args.listen_ip,
        &args.dhcp_range,
        &assets_dir_str,
        workdir_path,
    )?;

    // 9. Start Python Answer HTTP Server
    println!("Starting pve-answer-server...");
    let mut python_child = Command::new(python_server_bin)
        .arg("--host")
        .arg(&args.listen_ip)
        .arg("--port")
        .arg("80")
        .arg("--static-dir")
        .arg(&assets_dir_str)
        .arg("--answer-file")
        .arg(&answer_file)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;

    println!("PXE Bootstrap Services are running! Press Ctrl+C to stop...");

    // Wait for Ctrl+C
    tokio::select! {
        _ = signal::ctrl_c() => {
            println!("\nShutdown signal received. Terminating child processes...");
        }
    }

    // Clean up child processes
    let _ = dnsmasq_child.kill();
    let _ = python_child.kill();

    // Clean up temporary materialized answer file
    if answer_file.exists() {
        let _ = fs::remove_file(answer_file);
    }

    println!("Bootstrap services terminated cleanly.");
    Ok(())
}
