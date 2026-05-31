# LamT Nix Configuration

Modular and automated system management for macOS, Linux, and WSL. This repository features a smart deployment orchestrator that handles cross-architecture builds and cloud provisioning.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Repository Sources](#repository-sources)
- [Quick Start](#quick-start)
- [Deployment & Bootstrap](#deployment--bootstrap)
- [Smart Build Strategies](#smart-build-strategies)
- [Infrastructure & Cloud](#infrastructure--cloud)
- [Secrets & Keys](#secrets--keys)
- [Platform Specifics](#platform-specifics)

## Features

- **Unified Interface**: A thin `Makefile` and direct Rust CLI (`installer-rs`) wrapping all local and remote workflows.
- **Batch/Fleet Concurrent Operations**: Natively supports parallel multi-host concurrent deployments and configuration updates using asynchronous `tokio` threads, isolated per-host log files, and concurrent visual progress indicators (`indicatif`).
- **Smart Builder Broker**: Automatically tests default remote builder (`deploy@utils`) SSH compatibility and architecture compatibility before choosing build strategies.
- **Safety Switch Rollback**: Employs a magic rollback safety switch on target configuration updates; if activation fails or SSH connection drops, the target automatically rolls back to the previous working profile after 60 seconds.
- **Headless Bootstrap**: Automated VM provisioning (Proxmox), cloud Droplet creation (DigitalOcean), and live kexec Linux takeovers.
- **Flexible Orchestration**: Supports local builds, remote builders, native target compilation (directing compilation directories to `/mnt` to prevent `tmpfs` space exhaustion), or remote instantiation (`nix-store --realise` to prevent target OOM).
- **Identity & Secrets Alignment**: Zero-trust key translation (`ssh-to-age`), automatic SOPS encryption alignments, and declarative Tailscale key registrations.

## Prerequisites

- **Target**: Machine booted with [NixOS Minimal ISO](https://nixos.org/download/) (Recommended) or any running Linux system with SSH access (via kexec takeover, e.g., Ubuntu cloud images).
- **Host**: Any machine with Nix installed.

## Repository Sources

Run operations from different sources using `NIXREPO=[local|github|tea]`:

1.  **Local (Default)**: Uses the current directory (requires `git clone`).
2.  **GitHub**: Fetches latest config from GitHub.
3.  **Tea**: Fetches from private Gitea instance.

**Zero Setup (Run without Cloning):**

_Note: When running via `nix run`, use `--` to separate the installer-rs arguments._

```bash
# Run from GitHub
nix run github:lamtt77/lamt-nixconfig#installer-rs -- deploy --target utils

# Run from Tea (Gitea)
nix run 'git+ssh://git@tea.lamhub.com/lamtt77/lamt-nixconfig#installer-rs' -- switch --target host

# Run locally (Help menu)
nix run .#installer-rs -- --help
```

| Command       | Description               | Example                                             |
| :------------ | :------------------------ | :-------------------------------------------------- |
| `make switch` | Update current machine    | `make switch`                                       |
| `make switch` | Update remote host        | `make switch ARGS="--target router-main"`           |
| `make deploy` | **WIPE DISK** & Bootstrap | `make deploy ARGS="--target nas"`                   |
| `make switch` | Verify changes (dry-run)  | `make switch ARGS="--target gaming --action test"`  |
| `make switch` | Build only (no switch)    | `make switch ARGS="--target gaming --action build"` |
| `make switch` | Home Manager only         | `make switch ARGS="--target user@host --hm"`        |

### Target Host Format

Commands that accept target systems (via `--target` / `-t` or `--hosts`) support a flexible specification format:

```
[username@]hostname[=ip]
```

- **Hostname only**: `avon` (autodetects target IP via hypervisor scan or Tailscale)
- **With username**: `nixos@avon` (overrides default user to `nixos`)
- **With IP override**: `avon=192.168.1.18` (forces target IP to `192.168.1.18`, bypassing dynamic scanning)
- **Combined**: `nixos@avon=192.168.1.18` (overrides both target user and IP)

## Deployment & Bootstrap

**⚠️ DANGER**: `make deploy` will **WIPE ALL DATA** on the target's primary disk!

### Bootstrap Workflow

The `installer-rs` orchestrator follows a streamlined, single-stage deployment pipeline to bootstrap target machines:

1. **Partitions Disk**: Automatically runs `disko` on the target to format and partition physical storage under `/mnt`.
2. **Builds Configuration**: Compiles the NixOS system closure. Depending on the resolved `--build-on` strategy, this is done either:
   - Locally on the orchestrator,
   - Delegated to a remote builder (e.g. `deploy@utils`),
   - Via remote realization (instantiates locally, transfers `.drv` recipes, and runs `nix-store --realise` directly on the target to prevent memory exhaustion), or
   - Compiled natively on the target.
3. **Installs NixOS**: Installs the built closure directly onto `/mnt`.
4. **Bootstraps Credentials**: Stages SSH host key pairs, SOPS decryption secrets, and pre-auth Headscale/Tailscale keys once.
5. **Reboots**: Reboots the target machine directly into the final, fully initialized system.

The installer-rs tool automatically detects if the target is a running non-NixOS system (e.g., stock Ubuntu) and uses `kexec` to take over the kernel without a manual reboot. Use `KEXEC_BOOT=yes` to force this behavior.

**Options:**

- `--force` / `-F`: Skip safety warning and destructive confirmation prompts.
- `--repo-src`: Source repository type (`local`, `github`, `tea`). Defaults to `local`.
- `--build-on`: Choose builder strategy (`local`, `builder`, `realise`, `target`). Defaults to automatic resolution.
  - `local`: Builds configuration locally.
  - `builder`: Delegated to a remote builder (defaults to `deploy@utils` or custom `BUILDER` env).
  - `realise` (or `instantiated`): Performs instantiation locally, copies inputs/derivations, and realizes them on target.
  - `target`: Syncs the full configuration repository and compiles natively directly on the target.
- `--plan`: Show dry-run configuration sizing (cores, RAM, disk size) and resolved strategy.
- `--redeploy`: Wipe and recreate virtualization VM/droplet instances from scratch (Proxmox/DigitalOcean).

### Deployment Examples

```bash
# Deploy to generic Cloud Image (e.g. Ubuntu) with kexec takeover
make deploy ARGS="--target gaming"

# Re-provision/Wipe an existing VM with VM recreation (DANGER: Wipes VM & Disk)
make deploy ARGS="--target medo --redeploy"

# Deploy with realization strategy (Solutions B/C) for low-memory environments
make deploy ARGS="--target my-droplet --build-on realise"

# Perform a batch deploy for multiple hosts concurrently
make deploy ARGS="--hosts avon,utils"

# Choose repository source (local, github, tea)
make switch ARGS="--target router --repo-src github"
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
nix run .#installer-rs -- deploy --target avon

# Redeploy (Stop + Destroy + Create + Bootstrap) - DANGER
nix run .#installer-rs -- deploy --target avon --redeploy

# Destroy a VM (DANGER)
nix run .#installer-rs -- destroy --target avon

# Get IP of a running VM
nix run .#installer-rs -- info --target avon --ip
```

**Requirements:**

- Proxmox hypervisor credentials and defaults parsed directly from `defines.nix` (or defaults in `config.rs`).
- SSH access to Proxmox host.
- A NixOS ISO image available on the Proxmox storage.

### DigitalOcean

Convert stock Linux droplets to NixOS via kexec.

- **Requirement**: `doctl` installed and authenticated with your `DO_SSH_KEYS`.

```bash
# Provision and Bootstrap
nix run .#installer-rs -- deploy --target medo

# Destroy a Droplet
nix run .#installer-rs -- destroy --target medo
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
4. If a mismatch or missing host is detected, it registers the new key and automatically re-encrypts the target's secrets configuration using `sops updatekeys` (after user confirmation, or automatically with `FORCE=yes`).
5. Stages the generated private SSH host key to `/mnt/etc/ssh/` on target installation, ensuring the target can decrypt its secrets on first boot without any manual key-scanning or re-keying loops.

To force-update an existing host key on the target, run:

```bash
UPDATE_HOST_KEY=yes make switch ARGS="-t host"
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
    - **Full System**: `make switch` (or `make switch NIXTARGET=user@macair15-m2`)
    - **User Only (Home Manager)**: `make switch/hm` (No sudo required)

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
   sudo nixos-rebuild switch --flake "github:lamtt77/lamt-nixconfig#wsl"
   ```

#### Method 2: Custom Tarball (Recommended)

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

## Credits

- [Virtual machine as macOS terminal workflow](https://github.com/mitchellh/nixos-config)
- [Utility libs and structure](https://github.com/hlissner/dotfiles)
