# nxd (NixOS Deployment Operator)

`nxd` is a fast, zero-trust deployment orchestrator written in Rust. It manages system rebuilds and lifecycle operations for physical machines, Proxmox/VMware VMs, DigitalOcean droplets, and WSL instances.

## WSL Provider Configuration & Operations

The WSL provider manages NixOS distributions under Windows Subsystem for Linux (WSL 2) using a Windows host as a control plane. It automates VM creation, provisioning, SSH credential bootstrapping, and system configuration switching.

### Prerequisites

To use `nxd` with WSL, the Windows host must meet the following requirements:
1. **WSL 2**: WSL must be installed and enabled.
2. **Windows OpenSSH Server**: The OpenSSH Server option must be installed and running.
3. **PowerShell**: PowerShell must be available on the Windows host.
4. **Authorized SSH Key**: The orchestrator's SSH public key must be enrolled on the Windows host. You can use the automated bootstrap command to configure this (see below).

### Declarative Metadata Configuration

WSL target hosts are declared in their respective metadata files (e.g., `hosts/<name>/meta.nix`). The configuration schema includes:

```nix
deployment.wsl = {
  enable = true;                 # Enable the WSL provider
  windowsHost = "192.168.1.171"; # IP or hostname of the Windows control plane
  windowsUser = "lamt";          # Windows user account name
  distribution = "NixOS";        # Managed WSL distribution name (default: "NixOS")
  installRoot = "C:\\WSL\\NixOS"; # Path where the distribution disk image is imported
  bootstrapUser = "nixos";       # Bootstrap Linux user in the minimal image (default: "nixos")
  transport = "auto";            # "auto" | "direct" | "windows" (default: "auto")
};
```

### SSH Bootstrapping

Before deploying, you must authorize your SSH public key on the Windows control plane. `nxd` provides a command that automates target user directory structure creation and permissions setup:

```bash
# Enroll using the default key (mydefs.mySshAuthKey)
nix run '.#nxd' -- wsl bootstrap-ssh -t wsl

# Enroll using a specific public key file
nix run '.#nxd' -- wsl bootstrap-ssh -t wsl --public-key ~/.ssh/id_ed25519.pub
```

### Lifecyle Commands

#### 1. Deploy (`deploy`)
Installs and provisions a fresh WSL distribution.
* **New Installs**:
  ```bash
  nxd deploy -t wsl
  ```
* **In-place Reinstalls (`--overwrite`)**: Re-imports the base distribution image and re-applies configuration, preserving the virtual machine shell settings but clearing target state:
  ```bash
  nxd deploy -t wsl --overwrite
  ```
* **Redeploy (`--redeploy`)**: Completely destroys and recreates the WSL distribution before running the deployment:
  ```bash
  nxd deploy -t wsl --redeploy
  ```

#### 2. Switch (`switch`)
Builds and applies configuration updates to an already active WSL target:
```bash
nxd switch -t wsl
```

#### 3. Destroy (`destroy`)
Unregisters and cleans up the WSL distribution from the Windows host:
```bash
nxd destroy -t wsl
```

---

## Important WSL Caveats

### 1. Interactive Shell Limitation (`wsl -d NixOS`)
Due to Windows `vsock` relay limitations, launching an interactive NixOS shell from an active SSH session on the Windows host (e.g., `ssh windows-host "wsl -d NixOS"`) may fail with socket errors (`0x8007274c` / `WSAETIMEDOUT`) if there is no active Windows graphical user session present. 
* **Workaround**: Launch the distribution shell directly using **Windows Terminal** on the host, or connect to the guest VM directly via SSH (`ssh nixos@<guest-ip>`).

### 2. Offline Artifact Building
To build a minimal WSL bootstrap archive (`nxd-NixOS-*.tar.gz`) without performing a full deploy, run:
```bash
nxd build -t wsl --artifact minimal-wsl --output ./minimal-wsl.tar.gz
```
This artifact can be copied and imported manually on offline Windows machines.
