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
- [Design Documents](#design-documents)

## Features

- **One command surface**: `lamd` drives local switches, remote switches, destructive bootstraps, fleet plans, syncs, and VM/cloud lifecycle actions.
- **Secret-aware deployments**: The installer prepares per-host workspaces, stages SOPS material, aligns SSH host keys with age recipients, and avoids direct `nixos-rebuild` paths that cannot stage secrets correctly.
- **Safe remote switching**: Remote system switches schedule an automatic rollback before activation and cancel it only after the new profile succeeds.
- **Smart build routing**: Builds can run locally, on a compatible remote builder such as `deploy@utils`, through target-instantiated realization for low-memory hosts, or natively on the target.
- **Parallel fleet operations**: Multi-host deploys and switches run concurrently while keeping per-host workspaces, logs, secret staging, and builder synchronization isolated to avoid cross-host races.
- **Fast fleet planning**: Lightweight `hosts/<name>/meta.nix` data feeds `deploymentHosts`, so planning does not need to evaluate every full NixOS system.
- **Persistent workspaces**: Local, target, and builder workspaces are refreshed between runs, preserving Nix and Git evaluation cache behavior while keeping per-host secret material isolated.
- **Headless infrastructure**: Proxmox VM provisioning, DigitalOcean droplet conversion, kexec takeovers, Disko installs, and Tailscale enrollment are handled from the same CLI.

## Quick Start

This is the shortest path from a fresh machine to a managed host. The headline workflow is a single installer command: point it at a declared host, let it prepare the workspace, stage host secrets when available, build through the best strategy, install NixOS, and reboot into the managed system.

For a host that is already declared in this flake:

```bash
nix run github:lamtt77/lamt-nixconfig#installer-rs -- deploy -t <host>
```

For secret-backed hosts, run from a local checkout with `../lamt-secrets` beside it:

```bash
nix run .#installer-rs -- deploy -t <host>
```

Use `nix run` for the first run; after a successful switch, managed systems provide the shorter `lamd` alias.

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
   nix run .#installer-rs -- deploy --hosts <host> --plan
   ```

4. Bootstrap a new NixOS host. The target must be reachable over SSH and this command can wipe the target disk.

   ```bash
   nix run .#installer-rs -- deploy -t <host>
   ```

5. Update an existing managed host.

   ```bash
   nix run .#installer-rs -- switch -t <host>
   # After the host has this config installed:
   lamd switch -t <host>
   ```

Common safe checks:

```bash
# Build without switching
lamd switch -t <host> --action build

# Test activation path
lamd switch -t <host> --action test

# Show the exact Nix copy command and timing details
lamd switch -t <host> -d
```

Fleet operations use the same command shape with `--hosts`. The installer plans all targets first, prepares isolated host workspaces, and runs hosts in parallel while coordinating shared builder syncs so one host cannot corrupt another host's staged secrets, logs, or workspace state. `--plan` is side-effect free: it may query metadata and provider state, but it does not stage ISOs, create/destroy instances, mutate secrets, or prepare install workspaces.

By default, batch deploy creates and deploys missing provider-backed hosts, but skips provider instances that already exist. Existing hosts are reported in the plan and run output so you can decide whether to reinstall them in place with `--overwrite` or destroy/recreate them with `--redeploy`.

```bash
# Preview multiple hosts without changing them
lamd deploy --hosts avon,utils,router-main --plan

# Create/deploy missing hosts concurrently; skip existing provider instances
lamd deploy --hosts avon,utils

# Reinstall existing provider instances in place
lamd deploy --hosts avon,utils --overwrite

# Switch multiple existing hosts concurrently
lamd switch --hosts avon,utils,router-main
```

## Prerequisites

- **Orchestrator**: Any machine with Nix installed and SSH access to the target.
- **Target for deploy**: A machine booted with the [NixOS Minimal ISO](https://nixos.org/download/) or a running Linux system that can be converted through kexec, such as an Ubuntu cloud image.
- **Target for switch**: An already managed NixOS, nix-darwin, Home Manager, or WSL host.
- **Secrets**: Hosts that use SOPS secrets expect the private secrets repository beside this checkout at `../lamt-secrets`.

## Repository Sources

Run operations from different sources using `--repo-src local|github|tea`:

1.  **Local (Default)**: Uses the current directory (requires `git clone`).
2.  **GitHub**: Fetches latest config from GitHub.
3.  **Tea**: Fetches from private Gitea instance.

**Run without cloning:**

_Note: Managed systems expose `lamd` as a shell alias that runs `nix run <switched-flake>#installer-rs --`. Use direct `nix run` mainly for first bootstrap or remote execution before your shell environment is loaded._

```bash
# Run from GitHub for bootstrap or remote execution
nix run github:lamtt77/lamt-nixconfig#installer-rs -- deploy --target utils

# Run from Tea (Gitea)
nix run 'git+ssh://git@tea.lamhub.com/lamtt77/lamt-nixconfig#installer-rs' -- switch --target host

# Run configured shell alias after a switch
lamd --help

# Fallback before the alias is available
nix run .#installer-rs -- --help
```

| Command       | Description                   | Example                                |
| :------------ | :---------------------------- | :------------------------------------- |
| `lamd switch` | Update current machine        | `lamd switch`                          |
| `lamd switch` | Update remote host            | `lamd switch -t router-main`           |
| `lamd deploy` | Create/deploy missing host    | `lamd deploy -t nas`                   |
| `lamd deploy` | Reinstall existing host       | `lamd deploy -t nas --overwrite`       |
| `lamd deploy` | Plan a deploy without running | `lamd deploy --hosts nas --plan`       |
| `lamd switch` | Verify activation path        | `lamd switch -t gaming --action test`  |
| `lamd switch` | Build only                    | `lamd switch -t gaming --action build` |
| `lamd switch` | Home Manager only             | `lamd switch -t user@host --hm`        |
| `lamd exec`   | Run a command on hosts        | `lamd exec --hosts @router -- uptime`  |

The root `Makefile` forwards to `nix run .#installer-rs --` by default. You can still override `LAMD` explicitly if you want a different entrypoint. `make switch` therefore defaults to the current host just like `lamd switch`.

### Target Host Format

Commands that accept target systems (via `--target` / `-t` or `--hosts`) support a flexible specification format. For `lamd switch`, omitting both `--target` and `--hosts` defaults to the current short hostname.

```
[username@]hostname[=ip]
```

- **Hostname only**: `avon` (autodetects target IP via hypervisor scan or Tailscale)
- **With username**: `nixos@avon` (overrides default user to `nixos`)
- **With IP override**: `avon=192.168.1.18` (forces target IP to `192.168.1.18`, bypassing dynamic scanning)
- **Combined**: `nixos@avon=192.168.1.18` (overrides both target user and IP)

## Deployment & Bootstrap

> [!WARNING]
> `lamd deploy` and `make deploy` can wipe the target's primary disk. Run `lamd deploy --hosts <host> --plan` first when checking a target.

### Bootstrap Workflow

The `lamd` orchestrator follows a streamlined, single-stage deployment pipeline to bootstrap target machines:

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

The `lamd` tool automatically detects if the target is a running non-NixOS system (e.g., stock Ubuntu) and uses `kexec` to take over the kernel without a manual reboot. Use `KEXEC_BOOT=yes` to force this behavior.

**Options:**

- `--force` / `-F`: Skip safety warning and destructive confirmation prompts.
- `--repo-src`: Source repository type (`local`, `github`, `tea`). Defaults to `local`.
- `--build-on`: Choose builder strategy (`local`, `builder`, `realise`/`instantiated`, `target`/`native`). Defaults to automatic resolution.
  - `local`: Builds configuration locally.
  - `builder`: Delegated to a remote builder (defaults to host metadata or `deploy@utils`; override with `--builder <ssh-target>`).
  - `realise` (or `instantiated`): Performs instantiation locally, copies inputs/derivations, and realizes them on target.
  - `target`: Syncs the full configuration repository and compiles natively directly on the target.
- `--plan`: Show dry-run configuration sizing (cores, RAM, disk size) and resolved strategy.
- `--overwrite`: Reinstall an existing provider-backed host in place. This can repartition disks and erase data, but does not destroy/recreate the VM or droplet.
- `--redeploy`: Destroy and recreate provider-backed VM/droplet instances from scratch before deployment.
- `--convert-to <host>`: Use a cloud-init/bootstrap source host as the install environment and install the separate declared NixOS host configuration.

### Deployment Examples

```bash
# Deploy to generic Cloud Image (e.g. Ubuntu) with kexec takeover
lamd deploy -t gaming

# Reinstall an existing VM in place. This can wipe the VM disk.
lamd deploy -t medo --overwrite

# Re-provision an existing VM from scratch. This destroys and recreates the VM.
lamd deploy -t medo --redeploy

# Deploy with target realization for low-memory environments
lamd deploy -t my-droplet --build-on realise

# Convert a cloud-init/bootstrap source into a declared NixOS host
lamd deploy -t ubuntu-cloudinit-test --convert-to medo

# Perform a batch deploy for multiple hosts concurrently
lamd deploy --hosts avon,utils

# Choose repository source (local, github, tea)
lamd switch -t router --repo-src github
```

## Infrastructure & Cloud

### Proxmox (Headless IaC)

The orchestrator handles the entire VM lifecycle including specialized network configurations.

**Advanced Networking:**

- **Router Provisioning**: Hosts named `router-*` automatically receive two interfaces: WAN (`vmbr0`) and LAN (`vmbr1`).
- **Static IP & VLAN Injection**: Bootstrapping in environments without DHCP via `STATIC_IP` and `BOOTSTRAP_VLAN`.
- **ARP Cache Warming**: Automatically ensures builder-to-target connectivity for newly created VMs.

```bash
# Deploy 'avon' configuration (automatically provisions Proxmox VM based on declarative flake metadata)
lamd deploy -t avon

# Redeploy from scratch. This stops, destroys, recreates, and bootstraps the VM.
lamd deploy -t avon --redeploy

# Destroy a VM
lamd destroy -t avon

# Get IP of a running VM
lamd info -t avon --ip
```

**Requirements:**

- Proxmox hypervisor credentials and defaults parsed directly from `defines.nix` (or defaults in `config.rs`).
- SSH access to Proxmox host.
- A NixOS ISO image available on the Proxmox storage. For NixOS ISO deploys, missing ISO staging is handled only after the deploy plan is confirmed.
  - **ISO Override**: You can override the default ISO volume path using the `NIXOS_ISO` environment variable, e.g.:
    ```bash
    NIXOS_ISO="local:iso/nixos-minimal-24.11.iso" lamd deploy -t avon
    ```
  - If the expected ISO is missing, the installer can prompt to build and upload the custom ISO, download the official minimal ISO to Proxmox, or abort. Official ISOs do not embed your SSH key, so you must add your public key through the VM console before first SSH.

### DigitalOcean

Convert stock Linux droplets to NixOS via kexec.

- **Requirement**: `doctl` installed and authenticated with your `DO_SSH_KEYS`.

```bash
# Provision and Bootstrap
lamd deploy -t medo

# Destroy a Droplet
lamd destroy -t medo
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
        nix build .#nixosConfigurations.<host>.config.system.build.refindBootImg
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
UPDATE_HOST_KEY=yes lamd switch -t <host> -F
```

To import the active target host key into the secrets repository in non-interactive mode, run:

```bash
UPDATE_SECRETS_KEY=yes lamd switch -t <host> -F
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
    - **Full System**: `lamd switch` or `make switch`
    - **Remote/explicit target**: `lamd switch -t user@macair15-m2` or `make switch ARGS="-t user@macair15-m2"`
    - **User Only (Home Manager)**: `lamd switch -t user@macair15-m2 --hm` (No sudo required)

> [!TIP]
> Alternatively, use the official installer: `sh <(curl -L https://nixos.org/nix/install)`.

### WSL

#### Method 1: Pre-built (NixOS-WSL)

1. Download the latest `nixos-wsl.tar.gz` from [NixOS-WSL releases](https://github.com/nix-community/NixOS-WSL/releases).
2. Import and switch:
   ```bash
   wsl --import NixOS %USERPROFILE%\NixOS\ nixos-wsl.tar.gz
   wsl -d NixOS
   # Inside WSL:
   nix run github:lamtt77/lamt-nixconfig#installer-rs -- switch -t wsl
   ```

#### Method 2: Custom Tarball

1. Build the tarball (handles remote builds automatically if on ARM Mac):
   ```bash
   make wsl
   ```
2. Import the generated image in Windows:
   ```bash
   wsl --import NixOS %USERPROFILE%\NixOS\ nixos-wsl-custom.tar.gz
   ```
3. Initialize user:
   ```bash
   su lamt # First-start is probably root
   ```

## Design Documents

Installer behavior and implementation details are tracked in:

- [Installer Requirements Specification](docs/Installer%20Requirements%20Specification.md)
- [Installer Rust Architecture and Implementation Plan](docs/Installer%20Rust%20Architecture%20and%20Implementation%20Plan.md)
- [New Features Coding Plan](docs/New%20Features%20Coding%20Plan.md)

For deployment validation involving secrets, use `lamd switch`, `lamd deploy`, or `nix run .#installer-rs -- ...`. Avoid direct `nixos-rebuild` or bare `nix build .#nixosConfigurations...` validation paths for secret-backed hosts because they bypass installer workspace preparation and host-secret staging.
