# Architecture & Implementation Plan: `installer-rs`

This document serves as the single unified specification and architecture plan for rewriting the custom NixOS deployment orchestrator (`apps/installer2`) in Rust. It merges the migration rationale, language comparison, and bootstrapping strategies with the final Rust module specifications, CLI interfaces, and codebase optimization recommendations.

---

## 1. Migration Rationale & Comparative Analysis

Migrating the deployment tool from Bash to Rust addresses several fundamental limitations in runtime execution, stability, performance, and maintenance overhead.

### 1.1 Bash vs. Rust Comparison Matrix

| Dimension         | Bash (Current `installer2`)                                                   | Rust (Proposed `installer-rs`)                                             |
| :---------------- | :---------------------------------------------------------------------------- | :------------------------------------------------------------------------- |
| **Type Safety**   | Non-existent. Silent failures occur on typos or unquoted variable expansions. | Strong static typing. Compiler checks prevent runtime type mismatches.     |
| **Data Parsing**  | Spawns external subprocesses (`jq`, `sed`, `awk`, `cut`).                     | Native serialization and deserialization (`serde_json` and `serde_yaml`).  |
| **Concurrency**   | Tricky background subshells (`&`), file locking, and process sync.            | Native async (`tokio`) tasks with progress bars and safe log multiplexing. |
| **Testability**   | Hard to unit test. Testing shell logic requires manual runs.                  | First-class test suite (`cargo test`) with full mocking support.           |
| **Bootstrapping** | Executable on any POSIX system containing `bash`, `ssh`, and `rsync`.         | Compiles to a static binary (recovers easily on any live environment).     |

### 1.2 Running on Nix-enabled Machines

If a host has Nix installed, running the Rust installer is simple:

```bash
nix run github:lamtt77/lamt-nixconfig#installer-rs -- deploy --target nixos@utils
```

- **Binary Caching (Fast):** By setting up Gitea Actions to build and push the package to a free **Cachix** cache (up to 5GB free for public caches), Nix will download the pre-compiled binary in less than 2 seconds, skipping compilation.
- **Source Compilation (Fallback):** If no cache matches, Nix automatically fetches the Rust toolchain and compiles the binary from source in approximately 10 to 25 seconds.

### 1.3 Bare-Metal Recovery (No Nix Installed)

When bootstrapping a brand-new bare-metal target (e.g. from an Ubuntu recovery environment), you can cross-compile `installer-rs` to a static binary (`x86_64-unknown-linux-musl`). This produces a single self-contained file with no `libc` or subprocess dependencies. You can download and execute it instantly in any live environment.

### 1.4 Alternatives Considered (Go vs. Rust)

- **Go:** Compiles faster and has a simpler learning curve, but produces larger binaries (~10MB vs ~3MB) and lacks Rust’s robust compiler guarantees.
- **Rust:** Chosen because of its memory safety, smaller binary size, and excellent integration with the modern Nix ecosystem.

---

## 2. Scan of `apps/installer2` & Code Quality Refactoring

An in-depth analysis of the current Bash implementation in `apps/installer2` reveals several duplicate, inefficient, and brittle patterns. `installer-rs` resolves these issues via standard Rust structures.

### 2.1 Duplicate Logic & Consolidation

1.  **Elimination of Dual-Stage Install Logic:**
    - _Issue:_ The Bash script used a fragile two-stage installation (rebooting into a temporary minimal template system, then running a second deployment stage) to avoid OOM errors during target-side Nix evaluation.
    - _Resolution:_ Rust replaces this entirely with a **unified single-stage installation** using remote evaluation/instantiation (`nix-store --realise`). This eliminates the need for temporary template configurations (`minimal-configuration.nix`, `persistent-net.nix`), dual reboots, and duplicate key staging logic.
2.  **Proxmox VM Creation Redundancy:**
    - _Issue:_ `qm_create` and `qm_create_cloudinit` in `lib/providers.sh` duplicate the setup of CPU cores, RAM size, network bridges (`--net0`), and virtual device arguments.
    - _Resolution:_ Refactored into a unified Proxmox VM builder interface. A struct `ProxmoxVmConfig` holds the properties, and a shared creation driver translates this config into standard command-line flags.

### 2.2 Inefficient Shell-outs & Fragile Parsing

1.  **JSON Value Extraction:**
    - _Issue:_ The shell orchestrator uses a custom regex-based text matcher `json_get` (lines 197-208 of `bin/installer`) to extract fields from `nix eval` outputs.
    - _Resolution:_ Rust uses `serde_json` to deserialize the JSON output of the Nix flake evaluation directly into typed structs. This guarantees structure correctness at compile time.
2.  **VMware Leases Lookup:**
    - _Issue:_ `vmware_get_ip` in `lib/providers.sh` spawns `awk` to scan MAC addresses in `/var/db/vmware/vmnet-dhcpd-*.leases`. This is limited to macOS (VMware Fusion).
    - _Resolution:_ Rust reads lease files natively via standard library file operations, resolving paths dynamically based on the host operating system:
      - **macOS (VMware Fusion):** `/var/db/vmware/vmnet-dhcpd-*.leases`
      - **Linux (VMware Workstation Pro):** `/etc/vmware/vmnet-dhcpd-vmnet8.leases` or `/var/lib/vmware/vmnet-dhcpd-*.leases`
      - **Windows (VMware Workstation Pro):** `C:\ProgramData\VMware\vmnetdhcp.leases`
    - _Parsing:_ Scanning is performed using native regex string scanning in memory instead of spawning external shell pipes.
3.  **Proxmox IP Mapping:**
    - _Issue:_ `qm_scan_ip` calls `nmap` and parses stdout using multiple pipes (`grep`, `sed`, `tr`, `rev`, `cut`).
    - _Resolution:_ Spawns `nmap` but processes its output stream directly inside Rust using line-by-line matches, avoiding the creation of shell pipes.

### 2.3 Filesystem & Decryption Safety Hazards

1.  **Secrets Leakage:**
    - _Issue:_ `stage_secrets_pre` and `stage_secrets_post` in `lib/core.sh` copy SOPS files into the local workspace and delete them on exit. If the script crashes or is terminated early, the secret files remain in the workspace.
    - _Resolution:_ Rust implements automatic cleanup via the `Drop` trait. A custom `SecretsStager` struct automatically deletes temporary secret paths when it goes out of scope, guaranteeing cleanup even during panics.
2.  **Headscale SSH Queries:**
    - _Issue:_ `validate_and_sync_tailscale_preauth_key` in `lib/keys.sh` runs SSH commands with dynamic variable injections to query Headscale users and namespaces.
    - _Resolution:_ Rust abstracts this into a dedicated `HeadscaleClient` struct that builds commands safely, preventing shell injection vulnerabilities.

### 2.4 Architectural & Runtime Design Refinements

To maintain an optimum and practical design without over-engineering, the following architectural choices are enforced in the codebase:

1.  **Batch Flake Evaluation (`src/context.rs`):**
    - To avoid performance penalties from repeatedly calling external `nix eval` processes, the orchestrator retrieves configuration metadata in a single batch query (evaluating the entire `config.deployment` attribute set as a JSON string). This is deserialized once into a typed `DeploymentConfig` struct.
2.  **Dual-Target Command Execution (`src/process.rs`):**
    - To prevent garbled terminal logs during parallel multi-host operations while keeping logging dependencies simple, the shell runner supports a `LogTarget` enum. For single-host (foreground) commands, it streams output directly to stdout; for parallel batch runs, it logs to isolated `/tmp/installer-rs-<host>.log` files.
3.  **Idempotent Takeover Checkpoints (`src/pipeline.rs`):**
    - If an installation is interrupted, restarting from scratch is slow. The orchestrator checks if the target is already booted into the kexec RAM takeover environment (by validating a `/tmp/in_takeover` checkpoint or confirming root filesystem is `tmpfs`). If present, it automatically bypasses the download/kexec boot step.
4.  **Minimal Virtualization Interface (`src/providers/mod.rs`):**
    - The `VirtualizationProvider` trait is kept minimal, defining only shared lifecycle methods: `create`, `destroy`, and `get_ip`. Hypervisor-specific logic (e.g. VMware DHCP lease parses, Proxmox VM ID checks) are encapsulated as private implementation details within their respective provider files rather than cluttering the shared trait interface.

---

## 3. Simplified CLI & Execution Routing

To address the command bloat found in the original design specs, `installer-rs` implements a unified user interface.

### Key Improvements & CLI Simplifications

- **Command Bloat Reduction:** The previous 15+ subcommands are consolidated into 5 clean, primary commands: `deploy`, `switch`, `sync`, `destroy`, and `info`.
- **Dynamic Foreground/Background Routing:**
  - _Single Host:_ If a single host is specified as a target for a command (e.g., `deploy` or `switch`), the command executes directly in the **foreground**. It streams stdout and stderr directly to the terminal, allowing interactive keyboard prompts (such as resolving host key mismatches via `dialoguer` or confirming Tailscale/Headscale pre-auth keys).
  - _Multi-Host (Batch):_ If multiple hosts are specified (for `deploy` or `switch` commands), the command automatically transitions to **background mode**, scheduling asynchronous `tokio` threads, logging outputs to `/tmp` files, and rendering concurrent progress bars using `indicatif`. If any task fails, execution halts and the tool prints the last 30 lines of that host's log file.
- **Unified Switch/Apply Options:** A single `switch` command handles system profiles, boot entries, dry-run test modes, and home-manager configurations using flag modifiers (e.g., `--action [switch|bootentry|test|build]` and `--hm`).

---

### Command Mapping Details

```text
installer-rs <COMMAND> [OPTIONS]
```

1.  **`deploy`**: Provision, partition, and bootstrap host systems.
    - _Foreground vs. Background:_ Automatically routed based on target counts as defined in the routing improvements above.
    - _Flags:_ `--hosts HOST1,HOST2` (or defaults to all configured systems), `--target USER@HOST`, `--plan` (dry-run configurations), and `--redeploy` (recreates existing VMs).
2.  **`switch`**: Rebuild and apply configuration profiles to active nodes.
    - _Foreground vs. Background:_ Automatically routed based on target counts. Supports parallel batch switches (e.g. updating multiple servers concurrently).
    - _Flags:_ `--hosts HOST1,HOST2` (or defaults to active target if omitted), `--target USER@HOST` (for single target override), `--action [switch|bootentry|test|build]` (Default: `switch`), and `--hm` (Triggers home-manager switch).
3.  **`sync`**: Copy directory files or cryptographic keys to targets.
    - _Flags:_ `--target USER@HOST` (Required), `--keys` (Syncs GPG/SSH credential pairs), and `--repo` (Syncs codebase files).
4.  **`destroy`**: Stop and wipe provider VM instances.
    - _Flags:_ `--target USER@HOST` (Required).
5.  **`info`**: Resolve and display target details (e.g. scanning hypervisors for VM IPs).
    - _Flags:_ `--target USER@HOST` (Required) and `--ip` (IP scan filter).

---

## 4. Rust Crate Architecture & Layout

The codebase uses standard Rust module design to keep components clean and maintainable:

```text
apps/installer-rs/
├── Cargo.toml
└── src/
    ├── main.rs          # Coordinates command execution and foreground/background routing
    ├── cli.rs           # clap arguments and subcommands
    ├── config.rs        # Centralized defaults and constants
    ├── context.rs       # Runtime context and Nix Flake metadata loader
    ├── process.rs       # Command wrappers (logging, execution, ssh, rsync)
    ├── keys.rs          # Deprecated monolithic keys file (replaced by identity/ folder)
    ├── nix.rs           # Strategy broker, nix build, nix copy, remote instantiation
    ├── pipeline.rs      # Convergence workflow (kexec, disko, unified single-stage installation)
    ├── batch.rs         # Parallel tokio tasks and indicatif progress bars
    ├── providers/
    │   ├── mod.rs       # Virtualization trait definition
    │   ├── proxmox.rs   # Proxmox driver (qm commands, ip injection)
    │   ├── vmware.rs    # VMware Fusion/Workstation Pro driver (vmrun, dhcp lease parser)
    │   └── digitalocean.rs # DigitalOcean driver (doctl droplet)
    └── identity/        # Modular security, credential, and networking services
        ├── mod.rs       # IdentityService trait definition & registration runner
        ├── ssh.rs       # SSH host keys check & staging to /mnt/etc/ssh/
        ├── gpg.rs       # GPG credentials sync and initialization
        ├── sops.rs      # SOPS age decryption keys staging
        └── tailscale.rs # Tailscale/Headscale registration & pre-auth key handling
```

---

## 5. Implementation & Integration Plan

### Step 1: Create the Cargo Crate

Initialize the project directory `apps/installer-rs` with the following `Cargo.toml`:

```toml
[package]
name = "installer-rs"
version = "0.1.0"
edition = "2021"

[dependencies]
clap = { version = "4.4", features = ["derive"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tokio = { version = "1.35", features = ["full"] }
indicatif = "0.17"
dialoguer = "0.11"
log = "0.4"
env_logger = "0.10"
```

### Step 2: Implement Component Modules (Iterative Porting)

1.  **Stage A (Context & CLI):** Port CLI parsing using `clap` and load metadata using `nix eval`. Verify that running `installer-rs --target avon build --plan` correctly retrieves variables from the Flake without making changes.
2.  **Stage B (Nix & SSH wrappers - Instantiated & Remote Builder Logic):** Write the process command executor. Implement `BuildStrategy` resolution and Nix commands in `src/nix.rs`:
    *   **BuildStrategy Enum:**
        ```rust
        pub enum BuildStrategy {
            Local,
            RemoteBuilder { ssh_connection: String },
            TargetInstantiated,
            TargetNative,
        }
        ```
    *   **NixBuilder Struct:**
        ```rust
        pub struct NixBuilder {
            pub strategy: BuildStrategy,
            pub hostname: String,
            pub target_ip: String,
            pub low_mem: bool,
            pub has_local_nix: bool,
        }
        ```
    *   **Instantiation Execution:** For `TargetInstantiated` (Solution B), evaluate the derivation via `nix path-info --derivation`, copy the `.drv` path and inputs via `nix copy --to "ssh://root@<target_ip>"`, and realize it natively on target via `nix-store --realise` with target-side memory limit configurations (`GC_INITIAL_HEAP_SIZE=1M GC_DONT_GC=1 NIX_DISABLE_AUTO_GC=1`) and `--cores 1 --max-jobs 1` parameters.
3.  **Stage C (Providers & Identity Sync):** Implement the modular `identity/` directory using the `IdentityService` trait. Port GPG credential sync, SSH host key checks/staging, SOPS age key decryption preparation, and Tailscale/Headscale client registration coordinators. Port individual hypervisor drivers under `providers/*`.
4.  **Stage D (Unified State Convergence Pipeline):** Implement the single-stage installation loop in `src/pipeline.rs`. The process performs takeover, runs disko partitioning, initializes **3GB ZRAM swap** on takeover and a **3GB physical swapfile** on `/mnt/swapfile` (for `lowMem` configurations), evaluates/realizes the system store paths directly to `/mnt` (Option B), stages secrets and host SSH keys exactly once, runs `nixos-install --system <store-path>`, and reboots the target directly into the final system.
5.  **Stage E (Tokio Batching):** Implement the parallel async batch logic and `indicatif` progress animations.

### Step 3: Nix Packaging (`apps/installer-rs.nix`)

Expose the Rust binary to the Flake by declaring a derivation using `pkgs.rustPlatform.buildRustPackage`:

```nix
{ pkgs, inputs, ... }:
let
  installerPkg = pkgs.rustPlatform.buildRustPackage {
    pname = "installer-rs";
    version = "0.1.0";

    src = inputs.self;
    sourceRoot = "source/apps/installer-rs";

    cargoLock = {
      lockFile = ./installer-rs/Cargo.lock;
    };

    nativeBuildInputs = [ pkgs.makeWrapper ];

    postInstall = ''
      wrapProgram $out/bin/installer-rs \
        --prefix PATH : ${pkgs.lib.makeBinPath [
          pkgs.git
          pkgs.openssh
          pkgs.nix
          pkgs.jq
          pkgs.rsync
          pkgs.gnumake
          pkgs.coreutils
          pkgs.nmap
          pkgs.hostname
          pkgs.sops
          pkgs.ssh-to-age
        ]}
    '';
  };
in {
  type = "app";
  program = "${installerPkg}/bin/installer-rs";
}
```

### Step 4: Hook into the Flake & CLI Shell Completions

#### Option A: Standalone CLI with Shell Completions & Aliases (Recommended)

Since `installer-rs` uses `clap` for comprehensive parameter parsing, defaults, and validation, keeping a complex variable-to-flag mapper in the `Makefile` is redundant and error-prone.

To avoid typing the verbose `nix run .#installer-rs --` command, you can use two main methods to shorten the command:

1.  **Project-Local Shell Alias:**
    Add a shell alias directly inside the `shellHook` of your [shells/shell.nix](file:///Users/lamt/lamt-nixconfig/shells/shell.nix) development shell:
    ```nix
    shellHook = ''
      alias lamd="nix run .#installer-rs --"
      # ... other hook scripts
    '';
    ```
    Once you enter the dev shell (or if you use `direnv`), you can run commands instantly with `lamd`:
    ```bash
    lamd switch --target avon
    lamd deploy --hosts avon,utils --plan
    ```
2.  **Bin Directory Executable Wrapper:**
    Alternatively, create a small, executable script inside the project's local `bin/` directory named [bin/lamd](file:///Users/lamt/lamt-nixconfig/bin/lamd):
    ```bash
    #!/usr/bin/env bash
    exec nix run .#installer-rs -- "$@"
    ```
    By adding `./bin` to your `PATH` in the dev shell (`export PATH="$PWD/bin:$PATH"`), you can run `./bin/lamd` or just `lamd` globally in the project terminal.

##### Tab Completions Setup

To keep options discoverable, equip the Rust binary with a subcommand to generate shell autocompletions using the `clap_complete` crate:

```rust
// In cli.rs / main.rs
if let Commands::Completions { shell } = args.command {
    clap_complete::generate(shell, &mut Cli::command(), "installer-rs", &mut std::io::stdout());
    return;
}
```

You can generate and source completions dynamically under the shortened alias name:

```bash
source <(nix run .#installer-rs -- completions zsh | sed 's/installer-rs/lamd/g')
```

This gives you full tab-completion for all targets, actions, and flags under the `lamd` shortcut.

#### Option B: Thin, Zero-Logic Makefile Wrapper

If you prefer to preserve the convenience of `make` typing shortcuts (`make switch`, `make deploy`), we should **remove all variable-to-flag mapping** from the `Makefile` and replace it with a simple forwarding block:

```makefile
# Simple forwarding wrapper with no logic
.PHONY: switch deploy sync destroy info

switch deploy sync destroy info:
	nix run .#installer-rs -- $@ $(ARGS)
```

Usage:

```bash
make switch ARGS="--target avon"
make deploy ARGS="--hosts avon,utils --plan"
```

This removes the maintenance overhead of sync'ing flags between the `Makefile` and Rust code while retaining the `make` entrypoint.

---

## 6. Declarative Host Option Schema & Host Review

The option configurations defined in `modules/shared/options.nix` are imported automatically across all systems via `mkSystem`. The Rust orchestrator context (`context.rs`) maps these options to a matching deserialized schema.

### 6.1 Nix Option Declarations (`modules/shared/options.nix`)

- `deployment.targetIp`: FQDN, IP, or dynamic hostname (Default: `""`).
- `deployment.builder`: SSH remote builder targets (Default: `""`).
- `deployment.lowMem`: RAM constraints flag (`"yes"` or `"no"`).
- `deployment.vmid`: Proxmox VM ID string (Default: `""`).
- `deployment.diskSize`: Size in GB for virtual disk provisioners.
- `deployment.proxmox`: Configures Proxmox host hypervisors (`host`, `bios`, `diskBus`), and optional Cloud-Init details (`image`, `user`, `ipconfig0`, `ipconfig1`).
- `deployment.digitalocean`: Configures Droplet size, region, and start image.
- `deployment.vmware`: Configures VMware Fusion (macOS) or VMware Workstation Pro (Windows/Linux) virtual machine file paths (`vmxPath`).

### 6.2 Host Configurations Audit

All active host configs under `hosts/` have been reviewed against the schema. They are fully compatible:

1.  **DigitalOcean Nodes (`medo`, `medo-test`):**
    - `medo/default.nix` defines `lowMem = "yes"` and configures DO details under `deployment.digitalocean`.
    - `medo-test/default.nix` overrides the DO droplet using `lib.mkForce` to test Proxmox configurations locally (exposing `diskBus = "virtio"` to simulate cloud disk interfaces).
2.  **Standard Proxmox Nodes (`avon`, `utils`, `gaming`, `router-main`, `router-backup`):**
    - Correctly map VM IDs and configure Proxmox endpoints. Routers resolve their active LAN IP as `targetIp` dynamically (`config.modules.os.linux.services.router.lanIp`).
3.  **Cloud-Init Templates (`ubuntu-cloudinit-test`):**
    - A non-NixOS placeholder config that defines `deployment.proxmox.cloudInit` image assets for hypervisor provisioning runs.
4.  **VMware VM Configurations (`air15vm`):**
    - Tracks its VM lease files and disk profiles under `deployment.vmware.vmxPath` (specifically tested on macOS via VMware Fusion, with planned support for Workstation Pro directories).
