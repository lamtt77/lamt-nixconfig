use clap::{Parser, Subcommand, ValueEnum};

#[derive(Parser, Debug)]
#[command(
    name = "lamd",
    version,
    about = "NixOS deployment orchestrator in Rust"
)]
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

    #[arg(long, global = true, default_value = "local")]
    pub repo_src: String,

    #[arg(long, global = true, default_value_t = 5)]
    pub parallel: usize,

    #[command(subcommand)]
    pub command: Commands,
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
        convert_to: Option<String>,
    },
    /// Rebuild and apply configuration profiles to active nodes
    Switch {
        #[arg(long)]
        hosts: Option<String>,

        #[arg(long, short)]
        target: Option<String>,

        #[arg(long, default_value = "switch")]
        action: SwitchAction,

        #[arg(long)]
        hm: bool,
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
    /// Generate shell completions
    Completions {
        #[arg(value_enum)]
        shell: clap_complete::Shell,
    },
}

#[derive(ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum SwitchAction {
    Switch,
    Bootentry,
    Test,
    Build,
}
