# LamT Nix Configuration

Declarative system management for NixOS, nix-darwin, Home Manager, and WSL, with a Rust deployment orchestrator for real machines, VMs, and cloud hosts.

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Repository Sources](#repository-sources)
- [Deployment & Bootstrap](#deployment--bootstrap)
- [Infrastructure & Cloud](#infrastructure--cloud)
- [Secrets & Keys](#secrets--keys)
- [Platform Specifics](#platform-specifics)
- [Maintenance](#maintenance)
- [Design Documents](#design-documents)

## Features

- **One command surface**: `nxd` drives local switches, remote switches, destructive bootstraps, fleet plans, syncs, and provider lifecycle actions.
- **Secret-aware deployments**: The installer stages exactly one host SOPS file as a separate Nix store input and aligns SSH host keys with age recipients.
- **Safe remote switching**: Remote system switches schedule an automatic rollback before activation and cancel it only after the new profile succeeds.
- **Smart build routing**: Builds can run locally, on a compatible remote builder such as `deploy@utils`, through target-instantiated realization for low-memory hosts, natively on the target, or via explicit cross-compilation.
- **Parallel fleet operations**: Multi-host deploys and switches run concurrently with isolated logs, immutable source inputs, and per-host secret store paths.
- **Fast fleet planning**: Lightweight `hosts/<name>/meta.nix` data feeds `deploymentHosts`, so planning does not need to evaluate every full NixOS system.
- **Store-backed source transport**: Source snapshots and host-scoped secret inputs move through normal Nix store copy and substitution paths without remote workspace caches.
- **Headless infrastructure**: Proxmox VM provisioning with dynamic bootstrap networking, DigitalOcean droplet conversion, kexec takeovers, Disko installs, and Tailscale enrollment are handled from the same CLI.

## Quick Start

This is the shortest path from a fresh machine to a managed host. The headline workflow is a single installer command: point it at a declared host, let it snapshot the source, stage the host secret when available, build through the best strategy, install NixOS, and reboot into the managed system.

For a host that is already declared in this flake:

```bash
nix run github:lamtt77/lamt-nixconfig#nxd -- deploy -t <host>
```

For secret-backed hosts, run from a local checkout with `../lamt-secrets` beside it:

```bash
nix run '.#nxd' -- deploy -t <host>
```

Use `nix run` for the first run; after a successful switch, managed systems provide `nxd`.
The old `lamd` command and `.#installer-rs` flake entry remain temporary compatibility aliases.

1. Install Nix on the machine that will run the deployment. On macOS, the Determinate installer is recommended:

   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```

   On Linux, install Nix with your preferred installer or the official multi-user installer:

   ```bash
   sh <(curl -L https://nixos.org/nix/install) --daemon
   ```

2. Clone this repository and place the secrets repository next to it.

   ```bash
   git clone git@github.com:lamtt77/lamt-nixconfig.git
   cd lamt-nixconfig

   # Expected by the installer when host secrets are needed:
   # ../lamt-secrets/sops/<host>.yaml
   # ../lamt-secrets/.sops.yaml
   ```

3. Check what would happen before touching a machine.

   ```bash
   nix run '.#nxd' -- deploy --hosts <host> --plan
   ```

4. Bootstrap a new NixOS host. The target must be reachable over SSH and this command can wipe the target disk.

   ```bash
   nix run '.#nxd' -- deploy -t <host>
   ```

5. Update an existing managed host.

   ```bash
   nix run '.#nxd' -- switch -t <host>
   # After the host has this config installed:
   nxd switch -t <host>
   ```

Common safe checks:

```bash
# Build without switching
nxd build -t <host>

# Test activation path (reverts on reboot)
nxd test -t <host>

# Show the exact Nix copy command and timing details
nxd switch -t <host> -d
```

To optimize performance, `nxd switch`, `nxd boot`, and `nxd test` compare the newly built configuration path with the active generation on the target system. If they match, the orchestrator skips the profile generation registration, service activation, and rollback scheduling phases. You can bypass this optimization and force reactivation by passing the `-F` or `--force` flag.

Fleet operations use the same command shape with `--hosts`. The installer plans all targets first, prepares one immutable source store path plus isolated per-host secret paths, and runs hosts in parallel. `--plan` is side-effect free: it may query metadata and provider state, but it does not stage ISOs, create/destroy instances, mutate secrets, or prepare store inputs.

By default, batch deploy creates and deploys missing provider-backed hosts, but skips provider instances that already exist. Existing hosts are reported in the plan and run output so you can decide whether to reinstall them in place with `--overwrite` or destroy/recreate them with `--redeploy`.

```bash
# Preview multiple hosts without changing them
nxd deploy --hosts avon,utils,router-main --plan

# Create/deploy missing hosts concurrently; skip existing provider instances
nxd deploy --hosts avon,utils

# Reinstall existing provider instances in place
nxd deploy --hosts avon,utils --overwrite

# Switch multiple existing hosts concurrently
nxd switch --hosts avon,utils,router-main
```

## Prerequisites

- **Orchestrator**: Any machine with Nix installed and SSH access to the target.
- **Target for deploy**: A machine booted with the [NixOS Minimal ISO](https://nixos.org/download/) or a running Linux system that can be converted through kexec, such as an Ubuntu cloud image.
- **Target for switch**: An already managed NixOS, nix-darwin, Home Manager, or WSL host.
- **Secrets**: Hosts that use SOPS secrets resolve the private secrets repository path in the following priority:
  1. The `--secrets-repo <path>` CLI option.
  2. The `DEFAULT_SECRETS_REPO` environment variable.
  3. Automatic home directory detection (`$HOME/lamt-secrets`, `/Users/lamt/lamt-secrets`, or `/home/lamt/lamt-secrets`).
  4. Sibling directory relative lookup (`../lamt-secrets`).

## Flake Sources

Run operations from different source flakes using `--flake <flake-ref>`. When omitted, `nxd` resolves the flake path in the following priority:

1. The `--flake <flake-ref>` CLI option.
2. The `DEFAULT_FLAKE_REPO` environment variable.
3. Discovering the nearest parent `flake.nix` in the current working directory tree.
4. Automatic home directory detection (`$HOME/lamt-nixconfig`, `/Users/lamt/lamt-nixconfig`, or `/home/lamt/lamt-nixconfig`).

5. **Local (Default)**: Discovers local checkout or paths (e.g. `--flake .` or path).
6. **GitHub Alias**: `--flake github` resolves to the configured GitHub repository.
7. **Tea Alias**: `--flake tea` resolves to the Gitea instance repository.
8. **Any Flake URL**: `--flake github:owner/repo` or other standard Nix flake references.

**Run without cloning:**

_Note: Managed systems install `nxd` from the switched flake. Use direct `nix run` mainly for first bootstrap or remote execution before your shell environment is loaded._

```bash
# Run from GitHub for bootstrap or remote execution
nix run github:lamtt77/lamt-nixconfig#nxd -- deploy --target utils

# Run from Tea (Gitea)
nix run 'git+ssh://git@tea.lamhub.com/lamtt77/lamt-nixconfig#nxd' -- switch --target host

# Run configured shell alias after a switch
nxd --help

# Fallback before the alias is available
nix run '.#nxd' -- --help
```

| Command      | Description                   | Example                              |
| :----------- | :---------------------------- | :----------------------------------- |
| `nxd switch` | Update current machine        | `nxd switch`                         |
| `nxd switch` | Update remote host            | `nxd switch -t router-main`          |
| `nxd deploy` | Create/deploy missing host    | `nxd deploy -t nas`                  |
| `nxd deploy` | Reinstall existing host       | `nxd deploy -t nas --overwrite`      |
| `nxd deploy` | Plan a deploy without running | `nxd deploy --hosts nas --plan`      |
| `nxd test`   | Verify activation path        | `nxd test -t gaming`                 |
| `nxd build`  | Build only (dry run)          | `nxd build -t gaming`                |
| `nxd switch` | Home Manager only             | `nxd switch -t user@host --hm`       |
| `nxd exec`   | Run a command on hosts        | `nxd exec --hosts @router -- uptime` |

The root `Makefile` forwards to `nix run '.#nxd' --` by default. You can override `NXD` explicitly when using another entrypoint. `make switch` defaults to the current host just like `nxd switch`.

### Target Host Format

Commands that accept target systems (via `--target` / `-t` or `--hosts`) support a flexible specification format. For `nxd switch`, omitting both `--target` and `--hosts` defaults to the current short hostname.

```
[username@]hostname[=ip]
```

- **Hostname only**: `avon` (autodetects target IP via hypervisor scan or Tailscale)
- **With username**: `nixos@avon` (overrides default user to `nixos`)
- **With IP override**: `avon=192.168.1.18` (forces target IP to `192.168.1.18`, bypassing dynamic scanning)
- **Combined**: `nixos@avon=192.168.1.18` (overrides both target user and IP)

## Deployment & Bootstrap

> [!WARNING]
> `nxd deploy` and `make deploy` can wipe the target's primary disk. Run `nxd deploy --hosts <host> --plan` first when checking a target.

### Bootstrap Workflow

The `nxd` orchestrator follows a streamlined, single-stage deployment pipeline to bootstrap target machines:

1. **Partitions Disk**: Automatically runs `disko` on the target to format and partition physical storage under `/mnt`.
2. **Builds Configuration**: Compiles the NixOS system closure. Depending on the resolved `--build-on` strategy, this is done either:
   - Locally on the orchestrator,
   - Delegated to a remote builder (e.g. `deploy@utils`),
   - Via remote realization (instantiates locally, transfers `.drv` recipes, and runs `nix-store --realise` directly on the target to prevent memory exhaustion), or
   - Compiled natively on the target.
3. **Installs NixOS**: Installs the built closure directly onto `/mnt`.
4. **Bootstraps Credentials**: Stages SSH host key pairs, SOPS decryption secrets, and pre-auth Headscale/Tailscale keys.
5. **Installs and Restages Identity**: Runs `nixos-install` and restages the target SSH host key after installation in case activation rewrites `/mnt/etc`.
6. **Reboots and Reports Final IP**: Reboots the target machine directly into the final system, then polls provider IP discovery for the post-reboot final IP when available.

The `nxd` tool automatically detects if the target is a running non-NixOS system (e.g., stock Ubuntu) and uses `kexec` to take over the kernel without a manual reboot. Use `KEXEC_BOOT=yes` to force this behavior.

**Options:**

- `--force` / `-F`: Skip safety warning and destructive confirmation prompts.
- `--flake <flake-ref>`: Flake source reference (e.g. `.`, `github`, `tea`, or a standard URL). Defaults to discovering the nearest local parent `flake.nix`.
- `--github-token <token>`: Set the GitHub access token used for evaluating/building flakes with private inputs (overrides `GITHUB_TOKEN` environment variable).
- `--build-on`: Choose builder strategy (`local`, `builder`, `realise`/`instantiated`, `target`/`native`, `cross`). Defaults to automatic resolution.
  - `local`: Builds configuration locally.
  - `builder`: Delegated to a remote builder (defaults to host metadata or `deploy@utils`; override with `--builder <ssh-target>`).
  - `realise` (or `instantiated`): Performs instantiation locally, copies inputs/derivations, and realizes them on target.
  - `target`: Syncs the full configuration repository and compiles natively directly on the target.
  - `cross`: Builds NixOS configuration locally on orchestrator using cross-compilation (targets `crossNixosConfigurations`).
- `--plan`: Show dry-run configuration sizing (cores, RAM, disk size) and resolved strategy.
- `--overwrite`: Reinstall an existing provider-backed host in place. This can repartition disks and erase data, but does not destroy/recreate the VM or droplet.
- `--redeploy`: Destroy and recreate provider-backed VM/droplet instances from scratch before deployment.

### Deployment Examples

```bash
# Deploy to generic Cloud Image (e.g. Ubuntu) with kexec takeover
nxd deploy -t gaming

# Reinstall an existing VM in place. This can wipe the VM disk.
nxd deploy -t medo --overwrite

# Re-provision an existing VM from scratch. This destroys and recreates the VM.
nxd deploy -t medo --redeploy

# Deploy with target realization for low-memory environments
nxd deploy -t my-droplet --build-on realise

# Convert a cloud-init/bootstrap source or raw target into a NixOS host
nxd convert -t abc@192.168.1.187 --to medo


# Perform a batch deploy for multiple hosts concurrently
nxd deploy --hosts avon,utils

# Choose flake source reference
nxd switch -t router --flake github
```

## Infrastructure & Cloud

### Proxmox (Headless IaC)

The orchestrator handles the entire VM lifecycle including specialized network configurations.

**Advanced Networking:**

- **Declarative VM NIC Layout**: Maps multi-NIC topologies (e.g., WAN/LAN interfaces via `net0` and `net1`) directly from metadata.
- **Static IP & VLAN Injection**: Dynamic live ISO bootstrap network configuration (assigned interface, subnet, VLAN ID, and gateway) configured via QEMU guest-agent (`qm guest exec`) in environments without DHCP.
- **ARP Cache Warming**: Automatically ensures builder-to-target connectivity for newly created VMs.

```bash
# Deploy 'avon' configuration (automatically provisions Proxmox VM based on declarative flake metadata)
nxd deploy -t avon

# Redeploy from scratch. This stops, destroys, recreates, and bootstraps the VM.
nxd deploy -t avon --redeploy

# Destroy a VM
nxd destroy -t avon

# Get IP of a running VM
nxd info -t avon --ip
```

**Requirements:**

- Proxmox hypervisor credentials and defaults parsed directly from `defines.nix` (or defaults in `config.rs`).
- SSH access to Proxmox host.
- A NixOS ISO image available on the Proxmox storage. For NixOS ISO deploys, missing ISO staging is handled only after the deploy plan is confirmed.
  - **ISO Override**: You can override the default ISO volume path using the `NIXOS_ISO` environment variable, e.g.:
    ```bash
    NIXOS_ISO="local:iso/nixos-minimal-24.11.iso" nxd deploy -t avon
    ```
  - If the expected ISO is missing, the installer can prompt to build and upload the custom ISO, download the official minimal ISO to Proxmox, or abort. Official ISOs do not embed your SSH key, so you must add your public key through the VM console before first SSH.

### DigitalOcean

Convert stock Linux droplets to NixOS via kexec.

- **Requirement**: `doctl` installed and authenticated with your `DO_SSH_KEYS`.

```bash
# Provision and Bootstrap
nxd deploy -t medo

# Destroy a Droplet
nxd destroy -t medo
```

### Bare Metal

- **`modules.os.linux.services.pxe-ipxe`**: Deploys a complete PXE boot environment (iPXE, Nginx, TFTP) capable of:
  - Auto-installing Proxmox VE (via `proxmox-auto-installer`).
  - Auto-installing Ubuntu (via `cloud-init` / `autoinstall`).
  - Serving custom post-install scripts and network configurations.
- **`modules.os.linux.services.refind-booter`**: Generates a custom rEFInd bootable USB image.
  - **Use Case**: Chainloading EFI bootloaders on NVMe drives for legacy servers (like the Dell R720) that cannot natively boot from NVMe.
  - **Usage**:
    1.  **Build the image**:
        ```bash
        nix build '.#nixosConfigurations.<host>.config.system.build.refindBootImg'
        ```
    2.  **Flash to USB**:
        ```bash
        sudo dd if=result of=/dev/sdX bs=1M status=progress
        ```

## Secrets & Keys

### Secrets Management (`sops-nix`)

The installer automatically stages `../lamt-secrets/sops/<host>.yaml` during deployment.

**Zero-Trust Automated Re-Keying:**
For new or updated hosts, the orchestrator automatically handles host key and secrets alignment:

1. Pre-generates the target's SSH host key locally if missing.
2. Translates the SSH public key to an `age` key.
3. Validates that the host and its key are correctly registered in the secrets configuration (`../lamt-secrets/.sops.yaml`).
4. If a missing recipient or host-key mismatch is detected, it asks how to resolve it: overwrite the target key from secrets, update secrets from the target key, proceed anyway, or abort. Non-interactive updates require `-F/--force` plus the relevant update environment variable.
5. Stages the generated private SSH host key to `/mnt/etc/ssh/` on target installation, ensuring the target can decrypt its secrets on first boot without any manual key-scanning or re-keying loops.

To force-update an existing host key on the target from the secrets repository, run:

```bash
UPDATE_HOST_KEY=yes nxd switch -t <host> -F
```

To import the active target host key into the secrets repository in non-interactive mode, run:

```bash
UPDATE_SECRETS_KEY=yes nxd switch -t <host> -F
```

**Tailscale Pre-auth Key Auto-Registration:**
For hosts utilizing declarative Tailscale enrollment, the orchestrator manages pre-auth keys:

1. Validates the pre-auth key in `../lamt-secrets/sops/<host>.yaml` by querying your Headscale server (`avon`).
2. Checks if the key is missing, expired, or invalid.
3. Automatically prompts (or uses non-interactive defaults) to generate a new 1-year (365d) reusable pre-auth key for the corresponding namespace (`lamt`, `cloud`, or `fcm`), updates the sops file, and stages it on the host.
4. Auto-enrolls the host during activation using the native `services.tailscale.authKeyFile` option.

### Utility Commands

- **Sync keys**: `make sync ARGS="--target router-main --keys"`
- **Sync repo**: `make sync ARGS="--target router-main --repo"`

## Platform Specifics

### macOS / Darwin

1.  **Install Nix**: Recommended via [Determinate Systems](https://determinate.systems/posts/determinate-nix-installer/):
    ```bash
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    ```
2.  **Apply Configuration**:
    - **Full System**: `nxd switch` or `make switch`
    - **Remote/explicit target**: `nxd switch -t user@macair15-m2` or `make switch ARGS="-t user@macair15-m2"`
    - **User Only (Home Manager)**: `nxd switch -t user@macair15-m2 --hm` (No sudo required)

> [!TIP]
> Alternatively, use the official installer: `sh <(curl -L https://nixos.org/nix/install)`.

### WSL (Windows Subsystem for Linux)

1. **Prerequisites**: Enable WSL 2 and Windows OpenSSH Server on the Windows host.
2. **Authorize SSH Key**: Run `nxd wsl bootstrap-ssh -t wsl` to authorize your workstation public key on the Windows host.
3. **Apply Configuration**:
   - **Full Deployment (first time)**: `nxd deploy -t wsl`
   - **Apply Updates**: `nxd switch -t wsl`
   - **Offline Artifact Build**: `nxd build --artifact minimal-wsl`

For detailed setup, metadata options, keepalive service, and recovery details, see the [WSL Deployment Guide](file:///Users/lamt/lamt-nixconfig/docs/Installer%20Rust%20Architecture%20and%20Implementation%20Plan.md#wsl-deployment-guide).

## Maintenance

The system automatically handles background maintenance (garbage collection and store optimization) for both system-wide and user/Home Manager profiles.

### Automated Maintenance

Scheduled weekly tasks are defined in [modules/os/base/services/maintenance.nix](file:///Users/lamt/lamt-nixconfig/modules/os/base/services/maintenance.nix):

- **System & User Garbage Collection**: Automatically cleans up generations older than 14 days for the system profile, and iterates through `/home/*` and `/Users/*` to clean up user-specific and Home Manager profiles (executed safely as each corresponding user via `sudo -u`).
  - **Linux (NixOS)**: Triggered weekly via `nix.gc.automatic` and extended via `systemd.services.nix-gc.postStart`.
  - **macOS (nix-darwin)**: Triggered weekly via a custom root-level `launchd` daemon wrapper (`darwin-gc`).
- **Store Optimization**: Deduplicates and hard-links Nix store files to optimize disk usage.
  - **Linux (NixOS)**: Real-time store optimization (`nix.settings.auto-optimise-store = true`).
  - **macOS (nix-darwin)**: Weekly optimization via custom root-level `launchd` service.

### Manual Cleanup (GC & Optimise)

If you need to reclaim disk space immediately without waiting for the weekly schedule:

1. **User / Home Manager generations** (run as your normal user):
   ```bash
   nix-collect-garbage --delete-older-than 14d
   ```
2. **System generations** (run with root privileges):
   ```bash
   sudo nix-collect-garbage --delete-older-than 14d
   ```
3. **Store Optimization** (deduplicate and hard-link Nix store files):
   ```bash
   nix-store --optimise
   ```

## Design Documents

Installer behavior and implementation details are tracked in:

- [Installer Requirements Specification](docs/Installer%20Requirements%20Specification.md)
- [Installer Rust Architecture and Implementation Plan](docs/Installer%20Rust%20Architecture%20and%20Implementation%20Plan.md)

For deployment validation involving secrets, use `nxd switch`, `nxd deploy`, or `nix run '.#nxd' -- ...`. Avoid direct `nixos-rebuild` or bare `nix build '.#nixosConfigurations...'` validation paths for secret-backed hosts because they bypass installer workspace preparation and host-secret staging.
