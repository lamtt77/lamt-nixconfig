use clap::{Parser, Subcommand, ValueEnum};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "nxd", version, about = "NixOS deployment orchestrator in Rust")]
pub struct Cli {
	#[arg(short, long, global = true)]
	pub debug: bool,

	#[arg(short = 'F', long, global = true)]
	pub force: bool,

	#[arg(long, global = true)]
	pub low_mem: Option<String>,

	#[arg(long, global = true)]
	pub build_on: Option<String>,

	#[arg(long, global = true)]
	pub builder: Option<String>,

	#[arg(long, global = true)]
	pub flake: Option<String>,

	#[arg(long, global = true)]
	pub secrets_repo: Option<String>,

	#[arg(long, global = true)]
	pub github_token: Option<String>,

	#[arg(long, global = true, default_value_t = 5)]
	pub parallel: usize,

	#[command(subcommand)]
	pub command: Commands,
}

#[derive(Parser, Clone, Debug)]
pub struct TargetArgs {
	#[arg(long)]
	pub hosts: Option<String>,

	#[arg(long, short)]
	pub target: Option<String>,

	#[arg(long)]
	pub hm: bool,
}

#[derive(Clone, Copy, Debug, ValueEnum)]
pub enum ArtifactKind {
	MinimalWsl,
}

#[derive(Subcommand, Clone, Debug)]
pub enum WslCommands {
	/// Install a local public key on the Windows OpenSSH control plane
	BootstrapSsh {
		#[arg(long, short, required = true)]
		target: String,

		/// Override defines.nix mySshAuthKey with a public-key file
		#[arg(long)]
		public_key: Option<PathBuf>,
	},
}

#[derive(Subcommand, Clone, Debug)]
pub enum Commands {
	/// Provision, partition, and bootstrap target systems
	Deploy {
		#[arg(long)]
		hosts: Option<String>,

		#[arg(long, short)]
		target: Option<String>,

		#[arg(long)]
		plan: bool,

		#[arg(long)]
		redeploy: bool,

		#[arg(long)]
		overwrite: bool,

		#[arg(long)]
		build_iso: bool,
	},
	/// Rebuild and apply configuration profiles to active nodes
	Switch {
		#[command(flatten)]
		args: TargetArgs,
	},
	/// Build configuration profiles and set them as default boot entry
	Boot {
		#[command(flatten)]
		args: TargetArgs,
	},
	/// Build and activate configuration profiles temporarily
	Test {
		#[command(flatten)]
		args: TargetArgs,
	},
	/// Build configuration profiles without activating them
	Build {
		#[command(flatten)]
		args: TargetArgs,

		#[arg(long, value_enum)]
		artifact: Option<ArtifactKind>,

		#[arg(long, requires = "artifact")]
		output: Option<PathBuf>,
	},
	/// Copy directory files or cryptographic keys to targets
	Sync {
		#[arg(long, short, required = true)]
		target: String,

		#[arg(long)]
		keys: bool,

		#[arg(long)]
		repo: bool,
	},
	/// Stop and wipe provider VM instances
	Destroy {
		#[arg(long, short, required = true)]
		target: String,

		#[arg(long)]
		plan: bool,
	},
	/// Resolve and display target details (e.g. hypervisor IP scan)
	Info {
		#[arg(long, short, required = true)]
		target: String,

		#[arg(long)]
		ip: bool,
	},
	/// Execute a command remotely over SSH across one or more hosts
	Exec {
		#[arg(long)]
		hosts: Option<String>,

		#[arg(long, short)]
		target: Option<String>,

		#[arg(long)]
		stream: bool,

		#[arg(last = true, required = true)]
		command: Vec<String>,
	},
	/// Convert an existing Linux target system in-place to a NixOS host
	Convert {
		/// The source VM connection details (username@ip or username@host or inventory hostname)
		#[arg(long, short)]
		target: String,

		/// The destination NixOS configuration host to convert to
		#[arg(long)]
		to: String,
	},
	/// Bootstrap and manage WSL provider prerequisites
	Wsl {
		#[command(subcommand)]
		command: WslCommands,
	},
	/// Generate shell completions
	Completions {
		#[arg(value_enum)]
		shell: clap_complete::Shell,
	},
}
