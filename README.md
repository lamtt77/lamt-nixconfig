# LamT NixOS System Configurations

This repository is my NixOS system configuration. I have slowly but fully migrated my legacy
dotfiles configuration (arch/freebsd/...) to Nix.
All Linux, WSL, and macOS configurations will be managed by Nix.

## Table of Contents

- [Features](#features)
- [Security Features](#security-features)
- [Prerequisites](#prerequisites)
- [Installation and Deployment](#installation-and-deployment)
- [Post-Deployment Verification](#post-deployment-verification)
- [Platform-Specific Setup](#platform-specific-setup)
- [Operations](#operations)
- [Credits](#credits)

## Features

- Super one-liner system deployment
- Unified config for macOS (Apple Silicon & Intel), Linux, and Windows WSL2
- Modules/Services can easily enable/disable on demand
- home-manager integrated as nixos modules + standalone support
- Flexible deployment: Local builds with remote copying, remote builds, cross-compilation support
- Kexec boot acceleration and low-memory optimizations
- Automated Proxmox VM provisioning and NixOS bootstrapping
- Secrets Management

## Security Features

- **Pre-commit Git Hook**: Automatically prevents accidental commits of sensitive files in the
  `secrets/` directory. The hook detects staged secrets files, unstages them, and aborts the
  commit with a clear error message. Use `git commit --no-verify` to intentionally commit secrets
  when necessary.

## Prerequisites

- Boot with EFI BIOS using the [NixOS Minimal ISO](https://nixos.org/download/)

## Installation and Deployment

### Non-Secrets Host Deployment

Format and build a brand new Host. One-liner headless installation!

_WARNING_: This will ERASE ALL DATA on the machine's hard disk! Use at your own risk!!!

- Method 1: Directly from GitHub:

_One-liner_:

```bash
$ nix run --extra-experimental-features "nix-command flakes" \
    github:lamtt77/lamt-nixconfig#installer-staging -- --build-on local utils
```

_Alternatively_:

```bash
$ sudo su
$ passwd <set-temp-root-psw>
$ nix run --extra-experimental-features "nix-command flakes" \
    github:lamtt77/lamt-nixconfig#installer-staging gaming && reboot
After logged in back:
$ cd lamt-nixconfig && nixos-rebuild switch --flake .#gaming
```

### Installer Options

The installer supports various options for different deployment scenarios:

- **`--build-on <mode>`**: Build location - `local` (build on deployment machine, copy to target), `remote` (build on target), `auto` (default: remote), `cross` (enable cross-compilation)
- **`--cross`**: Shortcut for `--build-on cross`
- **`--cross-hosts <hosts>`**: Space-separated list of hosts requiring cross-compilation on aarch64-linux
- **`--kexec <mode>`**: Kexec boot for faster deployment - `yes`, `no`, `auto` (default: auto)
- **`--low-mem <mode>`**: Low memory optimizations - `yes` (for <4GB RAM), `no` (default)
- **`--full <mode>`**: Full build mode - `yes` (build full system), `no` (staged), `auto` (default based on build-on)
- **`--log-level <level>`**: Logging verbosity - `debug`, `info`, `warn`, `error` (default: info)

#### BUILD_ON Mode Behavior

- **BUILD_ON=auto + systems match**: BUILD_ON=local, FLAKE_CONFIG_ATTR=nixosConfigurations (no cross).
- **BUILD_ON=auto + systems differ**: BUILD_ON=local, FLAKE_CONFIG_ATTR=crossNixosConfigurations (local cross-build).
- **BUILD_ON=remote (explicit)**: BUILD_ON=remote, FLAKE_CONFIG_ATTR=nixosConfigurations (native build on target, no cross).
- **BUILD_ON=cross (explicit)**: BUILD_ON=local, FLAKE_CONFIG_ATTR=crossNixosConfigurations.

For cross-compilation scenarios (e.g., deploying arm64 from x86_64), use `--build-on local` with `--cross-hosts` to enable build progress logs and efficient remote store copying.

Notes:

- Connect and set up the above in a remote SSH terminal (for copy & paste)
- Clear nix cache if getting old code:

```bash
$ rm -rf ~/.cache/nix/
```

- Method 2: Locally:

From the target host:

```bash
$ sudo su
$ passwd <set-temp-root-psw>
$ ip addr; note the IP address of this host (example: 192.168.1.100)
```

From the main deployment machine:

```bash
$ git clone https://github.com/lamtt77/lamt-nixconfig && cd lamt-nixconfig
$ NIXADDR=192.168.1.100 NIXHOST=gaming make remote/bootstrap
```

The remote bootstrap process uses a flexible installer supporting both local and remote builds:

- **BUILD_ON=remote** (default): Builds on the target machine. Uses two-stage installation for reliability.
  - **Stage 0**: Disk partitioning (via disko), minimal NixOS install, repo persistence, SSH setup.
  - **Stage 1**: Switches to full configuration after reboot.
- **BUILD_ON=local**: Builds on deployment machine, copies to target. Performs full installation in one stage, skips unnecessary reboot for direct installs.

Features include cross-compilation support, build progress logs, remote store for efficient copying, kexec boot acceleration, and low-memory optimizations. Automatically handles SSH keys, flake.lock syncing, and GITHUB_TOKEN for authenticated builds.

### Low Memory Mode

For systems with limited RAM (< 4GB), use `LOW_MEM=yes` (or `--low-mem yes` in the installer) to apply memory optimizations:

- Disables binary caches/substituters to reduce memory usage
- Uses disk-based temporary files instead of RAM
- Reduces Nix GC heap size and disables auto-GC
- Creates swap space during installation (5GB on /var/swapfile or 1GB on /swapfile)
- Limits parallel jobs to 1 core

Example usage:

```bash
$ NIXADDR=192.168.1.100 NIXHOST=gaming LOW_MEM=yes make remote/bootstrap
```

Or with the installer:

```bash
$ nix run github:lamtt77/lamt-nixconfig#installer-staging -- --low-mem yes --target-host root@192.168.1.100 gaming
```

For Proxmox VMs with low memory:

```bash
$ VMID=103 VM_MEMORY=1024 NIXHOST=gaming LOW_MEM=yes make proxmox/deploy
```

### Secrets Host Deployment:

#### Follow the non-secrets host deployment 'Method 2' and set 'SECRETS=yes':

```bash
$ NIXADDR=192.168.1.18 NIXHOST=avon NIXUSER=nixos SECRETS=yes make remote/bootstrap
```

#### FORCE: _WARNING: Disko format is pre-confirmed! Cannot be undone!!!_

```bash
$ NIXADDR=192.168.1.18 NIXHOST=avon NIXUSER=nixos SECRETS=yes FORCE=yes make remote/bootstrap
```

Note: Setting 'SECRETS=no' will still install the host normally, without secret fields

### Proxmox VM Deployment

Deploy NixOS VMs on a Proxmox host with automated VM creation, IP detection, and bootstrapping.

Set required variables (no defaults for host IP and storage):

- `PROXMOX_HOST`: Proxmox server IP
- `VMID`: VM ID
- `VM_MEMORY`: RAM in MB
- `VM_CORES`: CPU cores
- `VM_DISK_SIZE`: Disk size in GB
- `VM_BRIDGE`: Network bridge
- `VM_STORAGE`: Storage pool
- `VM_NAME`: VM name
- `VM_SUBNET`: Subnet for IP detection
- `NIXOS_ISO`: NixOS ISO path on Proxmox

#### Super One-liner Full Automated Deployment

```bash
$ BUILD_ON=local VMID=103 VM_MEMORY=16384 VM_CORES=8 VM_DISK_SIZE=128 \
  NIXHOST=avon NIXUSER=nixos SECRETS=yes FORCE=yes make proxmox/deploy
```

==> Remote bootstrap completed successfully in 3 minutes and 3 seconds.
==> NixOS VM deployed successfully at IP: 192.168.x.x

```bash
$ NIXHOST=gaming NIXUSER=vivi make proxmox/deploy
```

This creates the VM, starts it, detects the IP via nmap, and bootstraps NixOS.

#### Cloud-Init VM for Testing

For testing deployments in a safe environment, create cloud-init enabled VMs:

```bash
$ make proxmox/create-cloudinit-vm-seabios
```

This creates a VM with cloud-init support using SeaBIOS, ideal for testing NixOS configurations without affecting production systems.

### DigitalOcean Droplet Deployment

Deploy NixOS on a DigitalOcean droplet by converting an existing Ubuntu installation.

Set required variables:

- `NIXADDR`: Droplet IP address
- `NIXHOST`: Host configuration name (e.g., medo)

#### One-liner Conversion

```bash
$ NIXADDR=<droplet-ip> NIXHOST=medo make digitalocean/convert-switch
```

This process:

- Connects to the Ubuntu droplet via SSH
- Partitions the disk using disko (BIOS boot + /boot + /)
- Builds and installs NixOS with cloud-init for networking
- Reboots into NixOS; SSH access established post-reboot

#### Updating the Droplet

After initial deployment, update the configuration:

```bash
$ NIXADDR=<droplet-ip> NIXHOST=medo NIXUSER=nixos make remote/copy-switch
```

#### Step-by-Step Deployment

1. Create VM:

```bash
$ make proxmox/create-vm
```

2. Start VM:

```bash
$ make proxmox/start-vm
```

3. Detect VM IP:

```bash
$ make proxmox/get-vm-ip
```

4. Bootstrap NixOS (using the detected IP from /tmp/vm_ip.env):

```bash
$ source /tmp/vm_ip.env && NIXADDR=$NIXADDR make remote/bootstrap
```

## Post-Deployment Verification

After successful deployment, verify the system stability and configuration:

1. **SSH Connectivity**:

```bash
$ ssh root@<NIXADDR>  # e.g., ssh root@192.168.1.180
```

2. **System Services**:

```bash
$ systemctl status nix-daemon
$ journalctl -u nix-daemon --no-pager -n 20
```

3. **Configuration Validation**:

```bash
$ nixos-rebuild test --flake .#<NIXHOST>
$ lsblk  # Check disk partitioning
```

If issues arise, troubleshoot via `journalctl` or re-run `make remote/switch` from the deployment machine.

## Troubleshooting

### SSH Host Keys

After deployment, verify both RSA and Ed25519 host keys are available:

```bash
$ ssh-keyscan -t rsa,ed25519 <NIXADDR>
```

If Ed25519 is missing despite being present on the server, restart the SSH service:

```bash
$ sudo systemctl restart sshd
```

This ensures `sshd` loads all generated keys, as it may not auto-reload after key generation.

### Common Issues

- **GitHub Rate Limits**: Set `GITHUB_TOKEN` for authenticated builds.
- **SSH Connectivity**: Ensure port 22 is open; check firewall with `sudo iptables -L`.
- **Disk Partitioning**: Verify disko config matches hardware; use `lsblk` to confirm.
- **Secrets Decryption**: If SOPS fails, check keys in `secrets/sops/<host>.yaml`.
- **Service Failures**: Use `journalctl -u <service>` for logs.

## Platform-Specific Setup

### macOS / Darwin

- Installer: [Determinate Systems Nix Installer](https://determinate.systems/posts/determinate-nix-installer/)

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

After completion, verify with 'nix --version'. You are now ready to switch to the config:

```bash
$ NIXHOST=macair15-m2 make switch
```

For user-only configuration updates (no sudo/Touch ID required):

```bash
$ make switch/hm
```

- Note: Alternatively, you can use the official installer from
  [https://nixos.org/download/](https://nixos.org/download/). I use the Determinate Systems installer
  because it supports easy uninstallation.

```bash
$ sh <(curl -L https://nixos.org/nix/install)
```

### WSL

Enable WSL if not already done (check status with 'wsl --status')

```bash
$ wsl --install --no-distribution
```

For more info, refer to: [WSL basic commands](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)

#### Method 1: [NixOS-WSL](https://github.com/nix-community/NixOS-WSL)

- Download the pre-built at [latest NixOS-WSL release](https://github.com/nix-community/NixOS-WSL/releases/latest)

```bash
$ wsl --import NixOS %USERPROFILE%\NixOS\ nixos-wsl.tar.gz
$ wsl -d NixOS
$ git clone https://github.com/lamtt77/lamt-nixconfig && cd lamt-nixconfig
$ sudo nixos-rebuild switch --flake ".#wsl"
```

#### Method 2: build your own reuseable tarball: recommended

```bash
$ wsl --import NixOS %USERPROFILE%\NixOS\ nixos-wsl.tar.gz
$ wsl -d NixOS
$ git clone https://github.com/lamtt77/lamt-nixconfig && cd lamt-nixconfig
$ nix build .#nixosConfigurations.wsl.config.system.build.tarballBuilder
```

Copy/rename the generated tarball to %USERPROFILE%\Downloads\nixos-wsl-custom.tar.gz, then:

```bash
$ wsl --import NixOS $env:USERPROFILE\NixOS\ nixos-wsl-custom.tar.gz
$ wsl -d NixOS
```

- The first time wsl may start as root, switch to your username to initialize:

```bash
$ su lamt
```

- Note: Method 2 can be built with 'nix build' from any x86_64-linux host or WSL distro (such
  as Ubuntu) with Nix pre-installed

- Cross-platform tarball build issue:
  Currently, cross build the tarball from aarch64-linux is having the below issue:

```
$ make wsl
...
installing the boot loader...
chroot: failed to run command '/nix/var/nix/profiles/system/activate': No such file or directory
chroot: failed to run command '/nix/var/nix/profiles/system/sw/bin/bash': No such file or directory
```

## Operations

### Updating Existing Hosts

Once a host is deployed, you can update its configuration using several `make` targets from your deployment machine.

#### Remote Build (`remote/copy-switch`)

This method syncs your local source code to the target machine and then builds the new configuration on the target machine itself before activating it. This is useful when the target machine has sufficient resources.

```bash
# Sync source code, then build and switch on the remote host
$ NIXHOST=gaming NIXADDR=192.168.1.165 NIXUSER=vivi make remote/copy-switch
```

#### Local Build (`builder/switch`)

This target offloads the build process from the target host. It builds the configuration on your local (control) machine, copies the binary artifacts to the target, and then activates the new configuration. This is ideal for updating low-powered devices or for cross-architecture updates (e.g., updating a Linux host from a macOS machine).

**Usage:**

```bash
$ NIXHOST=gaming NIXADDR=192.168.1.165 NIXUSER=vivi SSHUSER=vivi make builder/switch
```

**How it Works:**

1.  The system configuration for `NIXHOST` is built on your local machine.
2.  The resulting `/nix/store` paths are copied to the target host specified by `NIXADDR`.
3.  The new configuration is activated on the target host.

### Testing the Installer

To validate the installer process on a test host:

1. **Local Test Build**:

```bash
$ make test NIXHOST=<test-host>
```

2. **Remote Dry Run** (without disk changes):

   - Set `FORCE=no` and run `make remote/bootstrap` on a VM.
   - Check logs for errors without actual partitioning.

3. **Full Deployment Test**:

   - Use a disposable VM (e.g., via Proxmox) for end-to-end testing.
   - Expected outcome: Successful bootstrap in ~5-10 minutes, SSH access post-reboot.

4. **Common Issues**:
   - GitHub rate limits: Ensure `GITHUB_TOKEN` is set.
   - SSH host keys: Handled automatically by the installer.
   - Disk partitioning: Verify disko config matches hardware.

## Credits

- [Virtual machine as macOS terminal workflow](https://github.com/mitchellh/nixos-config)
- [Utility libs, Doom Emacs, and modules structure](https://github.com/hlissner/dotfiles)
- Lots of others' nix configuration around the internet
