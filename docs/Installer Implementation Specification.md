# Implementation Specification: NixOS Deployment Orchestrator & Installer

## 1. Introduction & Executive Summary

### 1.1 Purpose

This document specifies the functional and architectural requirements for a language-agnostic NixOS/nix-darwin Deployment Orchestrator and Installer (the "Orchestrator"). The design synthesizes the best paradigms of **nixos-anywhere** (remote in-memory bootstrap) and **deploy-rs** (flake-native remote profile switching and rollback safety) into a unified, lightweight utility.

### 1.2 Ultimate Goal: One-Liner Convergence

The system is designed to achieve zero-intervention, one-liner automation for all deployment phases:

- **One-Liner Provisioning & Bootstrap**: Initialize hypervisors or cloud infrastructure, execute kernel takeovers, partition, stage keys/secrets, and install the OS in a single execution.
- **One-Liner Switch/Build**: Verify and apply configurations natively, remotely, or via delegation.
- **Cross-Platform Compatibility**: Unifies macOS (nix-darwin), Linux (NixOS), and WSL deployment targets.
- **Lean Runtime Execution**: Zero local dependencies other than standard system tools (`ssh`, `rsync`, `nix`).

---

## 2. Developer Interface (The Makefile Entrypoint Wrapper)

The root `Makefile` is a thin, zero-logic wrapper that forwards subcommands and arbitrary arguments (`ARGS`) directly to the `installer-rs` binary.

### 2.1 Forwarding Structure

The `Makefile` maps top-level commands directly to the `installer-rs` subcommands:

| Makefile Command | Orchestrator Subcommand | Usage Example |
| :--------------- | :---------------------- | :------------ |
| `make switch`     | `switch`                | `make switch ARGS="-t avon"` |
| `make deploy`     | `deploy`                | `make deploy ARGS="-t avon"` |
| `make sync`       | `sync`                  | `make sync ARGS="-t avon --repo"` |
| `make destroy`    | `destroy`               | `make destroy ARGS="-t avon"` |
| `make info`       | `info`                  | `make info ARGS="-t avon"` |
| `make wsl`        | `deploy`                | `make wsl ARGS="--plan"` |

All target host details, overrides, and user configurations are passed dynamically through `ARGS` using the inline target spec format:
```
[username@]hostname[=ip]
```
For example:
* `make switch ARGS="-t nixos@avon=192.168.1.18"` overrides the target user to `nixos`, selects target host `avon`, and overrides the target IP address to `192.168.1.18`.
* `make deploy ARGS="--hosts avon=192.168.1.18,utils=192.168.1.19"` runs a batch deployment with manual target IP overrides for both nodes.

---

## 3. Host Identity & Zero-Trust Secret Staging

To eliminate manual "failed-activation -> keyscan -> re-key" loops during initial deployment, target host identities (SSH keys) are managed **locally and upstream** prior to target installation.

```
       +---------------------------------------------+
       |   Orchestrator (Local Dev / Host Machine)    |
       +---------------------------------------------+
          |                                       |
          | (1) Generate key pair                 | (3) Compile deployment
          v                                       v     with encrypted secrets
  +-----------------------+              +-----------------------+
  |  Target Host Key      |              | Nix System Derivation |
  |  ssh_host_ed25519_key |              |  (/nix/store/...)     |
  +-----------------------+              +-----------------------+
          |                                       |
          | (4) Stage SSH private key             | (5) Install OS closure
          v                                       v
       +---------------------------------------------+
       |             Target /mnt Storage             |
       +---------------------------------------------+
```

#### 3.1 Host Key Generation Workflow

1.  **Local Host Key Sourcing & Generation**:
    - **Local Self-Switch (Bypass)**: If the target host matches the current executing host (`$(hostname -s)`), the Orchestrator bypasses key generation and resolves the active public key source directly to `/etc/ssh/ssh_host_ed25519_key.pub` on the system. This prevents creating dummy keys or mutating files inside the `lamt-secrets` folder on simple switches.
    - **Remote Targets**: If a host key does not exist for a remote target host, the Orchestrator automatically generates a new Ed25519 SSH host key pair locally inside the secrets repository:
      ```bash
      ssh-keygen -t ed25519 -f ../lamt-secrets/hosts/<host>/ssh_host_ed25519_key -N "" -q
      ```
2.  **Automated Sops Integration & Re-Keying**:
    - The Orchestrator extracts the resolved public key (from `/etc/ssh/` for the local host, or the secrets repo for remote hosts) and converts it to an `age` recipient key on the fly using `ssh-to-age`.
    - If the target host is not registered or if there is an age key mismatch, the Orchestrator delegates to the helper script `../lamt-secrets/bin/sops-host-key-manager` (`get-key`/`set-key` subcommands) to automatically update `../lamt-secrets/.sops.yaml` with the new age key.
    - It then triggers `sops updatekeys` in the context of the secrets repository to re-encrypt the target's secrets file (`../lamt-secrets/sops/<host>.yaml`) non-interactively using the new key.
    - Sops and key registration updates are automatically skipped if the secrets repository is not present or if `ssh-to-age` is missing (e.g. during a remote target self-switch).
3.  **Target Staging**:
    - During `bootstrap`/`deploy`, the Orchestrator stages the private host key directly onto the target's mounted disk storage:
      - Source: `../lamt-secrets/hosts/<host>/ssh_host_ed25519_key`
      - Destination: `/mnt/etc/ssh/ssh_host_ed25519_key` (Permissions: `0600`)
4.  **First Boot Success**:
    - When the target boots, it uses this pre-staged SSH host key. Sops-nix immediately decrypts all secrets successfully, completing deployment in a single, automated pass.

#### 3.2 Offline & Secrets-Free Builds

To support deploying, redeploying, or testing configurations from target hosts or environments that do not have access to the private secrets repository `lamt-secrets`:
- **Conditional Validation Bypass**: In the base SOPS module, the Orchestrator dynamically detects the presence of the host-specific secrets file (`secrets/sops/<host>.yaml`). If the file is missing during evaluation, the configuration automatically sets:
  ```nix
  sops.validateSopsFiles = false;
  sops.defaultSopsFile = ./dummy-secrets.yaml; # static fallback tracked in the flake
  ```
- **Evaluation Success**: Disabling `validateSopsFiles` prevents `sops-nix` from running its compile-time validation check (`sops-install-secrets`), which would otherwise fail the build due to missing keys or files (e.g. `the key 'wg0do_private_key' cannot be found`). This allows the system configuration to build successfully on any host.

#### 3.3 Tailscale Pre-auth Key Lifecycle Management

For hosts that run Tailscale with auto-registration enabled, the Orchestrator dynamically validates the status of their pre-auth keys:
1. **Host-Specific Secrets Location**: Tailscale pre-auth keys are stored securely inside the host-specific secrets files (`../lamt-secrets/sops/<host>.yaml`).
2. **Headscale Querying & Verification**:
   - The Orchestrator contacts the Headscale server (`avon` at `100.64.0.1`) via SSH.
   - It lists Headscale users and queries namespaces dynamically, checking if the current pre-auth key exists on the server and is still valid.
   - If a host does not have `tailscale_preauth_key` defined in its secrets file, the check is skipped silently (allowing coordinate systems like `avon` to build without warnings).
3. **Interactive 1-Year Key Re-generation**:
   - If the pre-auth key is missing, expired, or invalid, the Orchestrator alerts the user and prompts for confirmation to generate a new key.
   - The user selects a namespace (defaulting to the existing namespace or offering `lamt`, `cloud`, `fcm`).
   - The Orchestrator calls `headscale` on `avon` to create a new 1-year (365d) reusable pre-auth key.
   - It automatically updates the key inside `../lamt-secrets/sops/<host>.yaml` using SOPS non-interactively, so the new key is staged for deployment.


---

## 4. State Convergence Model (Unified Pipeline)

Rather than maintaining separate, redundant workflows for kexec, bootstrap, and switch, the Orchestrator treats all target hosts under a **State Convergence Model**. The utility detects the host's current state and runs only the phases required to converge it to the target state.

```
                      +---------------------------------------+
                      | Target State: Fully Converged System  |
                      +---------------------------------------+
                                          ^
                                          | (Phase 3: Activate / Switch)
                      +---------------------------------------+
                      |       State 3: Active NixOS           |
                      +---------------------------------------+
                                          ^
                                          | (Reboot)
                      +---------------------------------------+
                      |       State 2: Installed System       |
                      +---------------------------------------+
                                          ^
                                          | (Phase 2: Install / Format)
                      +---------------------------------------+
                      |       State 1: Ephemeral Live OS      |
                      |    (NixOS Live CD or memory image)    |
                      +---------------------------------------+
                                          ^
                                          | (Phase 2: Kexec Takeover)
                      +---------------------------------------+
                      |    State 0: Running Non-NixOS Linux   |
                      |   (e.g., stock Ubuntu/Debian server)  |
                      +---------------------------------------+
```

### 4.1 Convergence Pipeline Phases

#### Phase 1: Alignment (Environment State Setup)

- **Target Identification**: Connect, check operating system, resolve IP address, and parse Flake configuration.
- **Secrets Prep**: Copy host SOPS secrets to `./secrets/sops/<host>.yaml`.
- **Identity Retrieval**: Locate the pre-generated local SSH host key pair.
- **Active Lock Archival**: Sync/download the updated `flake.lock` from the target workspace (`~/lamt-nixconfig/flake.lock`) to `hosts/<host>/flake.lock` upon successful runs.

#### Phase 2: System Installation & Transition (State 0/1 to State 2)

1. **Takeover Detection & Execution**:
   - The Orchestrator queries the target to determine if it is in **State 0** or **State 1**:
     - _Check_: Does `nixos-install` exist? If yes, verify the active filesystem type via `findmnt / -o FSTYPE -n`.
     - _State 1 (Bypass Kexec)_: If the filesystem is `overlay`, `squashfs`, `tmpfs`, or `iso9660`, the host is identified as already running a **NixOS Installation CD / Ephemeral Live OS**. The Orchestrator skips the kexec takeover phase entirely, beginning work from State 1.
     - _State 0 (Trigger Kexec)_: If it runs a persistent filesystem on non-NixOS Linux, the Orchestrator executes `kexec` boot takeover (downloads the architecture-appropriate image, stops heavy services, prepares a swapfile, sets line arguments, and runs the in-memory kernel loader) to transition it from **State 0** to **State 1**.
2. **Resource Optimization**: Enable 1GB ZRAM swap immediately on the live installer (State 1).
3. **Partitioning**: Execute `disko` scripts.
4. **Swap Provisioning**: If `LOW_MEM` is active, write a 2GB swapfile to `/mnt/swapfile`.
5. **Closure Staging**:
   - _Single-Stage_: Compile system closure (via Compilation Broker) and copy it directly to `/mnt`. Stage local private SSH/SOPS keys directly to `/mnt/etc/ssh/` and `/mnt/var/lib/sops-nix/`. Run `nixos-install --system <drv>`.
   - _Two-Stage_: Stage minimal configurations (`configuration.nix`, `defines.nix`, `zramswap.nix`, `extra-config.nix`, and `persistent-net.nix`) and run `nixos-install` (compilation will run natively on target in Phase 3).
6. **Reboot**: Trigger hardware reboot to transition the system to a clean boot state (State 2).

#### Phase 3: Profile Activation & Convergence (State 2 $\rightarrow$ Target State)

1. **Re-connection**: Wait for SSH and re-resolve dynamic IP configurations.
2. **Minimal-to-Full Transition** (Two-Stage Only): Copy codebase repository, trigger Compilation Broker to build the full configuration natively using target resources, and transition.
3. **Profile Registration**: Register target generation explicitly into system profiles:
   ```bash
   sudo nix-env -p /nix/var/nix/profiles/system --set <drv>
   ```
4. **Safety Switch**:
   - Schedule safety rollback revert.
   - Apply configuration via `switch-to-configuration switch`.
   - Verify connection health to cancel scheduled rollback, converging the target to the desired final state.
5. **Cleanup**: Remove target scratch sources and purge temporary secrets.

### 4.2 Parallel Batch Deployments

To manage complex infrastructures, the Orchestrator provides a high-concurrency batch execution engine.

1.  **Metadata Discovery**:
    The engine performs a single-pass Nix evaluation across all `nixosConfigurations` in the Flake to identify hosts containing valid `deployment` attributes.
2.  **Planning Phase**:
    Before execution, a planning table is presented to the user, detailing the target hosts, identified providers (Proxmox, VMware, DigitalOcean), and specific hardware/network details.
3.  **Concurrency Model**:
    Deployments are executed in parallel using background subshells. The engine monitors these processes using a `wait -n` loop, reporting status in real-time as each host completes.
4.  **Execution Timing**:
    Each parallel job tracks its own execution duration, reporting the final time (e.g., `SUCCESS for host: gaming in 8m 29s`) upon completion.
5.  **Log Persistence**:
    To facilitate debugging of parallel runs, temporary log files are created via `mktemp` and preserved in the system's `tmp` directory. Users are notified of the log locations at the end of the batch run.

---

## 5. Architectural Components & Interfaces

The Orchestrator's internal codebase is structured around three modular components:

```
+---------------------------------------------------------------------------------+
|                                 Command Router                                  |
+---------------------------------------------------------------------------------+
                                         |
                                         v
+---------------------------------------------------------------------------------+
|                    Flake Metadata Parser (deployment.* schema)                   |
+---------------------------------------------------------------------------------+
                                         |
                                         v
+---------------------------------------------------------------------------------+
|                          State Convergence Pipeline                             |
|  +---------------------------+           +-----------------------------------+  |
|  |     Compilation Broker    | <-------> |  Infrastructure Provider          |  |
|  |  (Nix local/remote build) |           |  (Proxmox, DigitalOcean)          |  |
|  +---------------------------+           +-----------------------------------+  |
+---------------------------------------------------------------------------------+
```

### 5.1 Component Definitions

##### A. Flake Metadata Parser

- **Single-Pass Evaluation**: To prevent high start latency caused by executing multiple sequential `nix eval` commands, the Orchestrator queries all metadata attributes (under `deployment` or `darwinConfigurations/nixosConfigurations.<host>.config`) in a **single, unified Nix expression call returning a JSON object**. The resulting fields are parsed locally using a pure-bash JSON field extractor (`json_get` based on regex matching via `BASH_REMATCH`), eliminating the dependency on external utilities like `jq` to enable zero-dependency execution on target hosts.
- **Git-Free Path Flake Evaluation**: Evaluates path flakes without requiring the directory to be a Git repository (essential on rsync'd target hosts) by dynamically detecting local support for the `--force` flag (via `supports_nix_force_flag`) and applying it to Nix evaluation and build operations.
- **Option Schema paths**:
  - `nixosConfigurations.<host>.config.deployment.*` (Standard NixOS Linux hosts)
  - `darwinConfigurations.<host>.config.deployment.*` (macOS/nix-darwin hosts)
- **Host settings extracted dynamically**:
  - System architecture: Evaluates `config.nixpkgs.system` (e.g. `x86_64-linux`, `aarch64-darwin`) to detect target requirements and compilation targets.
- CLI flags (like `--ip` or `--vmid`) serve purely as temporary overrides to the Flake configuration.

#### B. Compilation Broker

- **Inputs**: Flake Attribute, Target Host, Build Strategy (`auto`, `local`, `builder`, `target`, `cross`), Low-Memory flag.
- **Outputs**: Path to the built derivation (`/nix/store/...`).
- **Nix Target Attribute Routing**:
  The Orchestrator must evaluate the resolved target attribute based on the target OS and build strategy:
  - If strategy is `cross` (cross-compiling): Map target to `crossNixosConfigurations.<host>.<attr_suffix>`.
  - If the target system is macOS/Darwin: Map target to `darwinConfigurations.<host>.<attr_suffix>`.
  - Default NixOS Linux: Map target to `nixosConfigurations.<host>.<attr_suffix>`.
- **Low-Memory Strategy**: Limits build concurrency to a single core/job (`--cores 1 --max-jobs 1`) and tunes the garbage collector (`GC_INITIAL_HEAP_SIZE=1M GC_DONT_GC=1 NIX_DISABLE_AUTO_GC=1`) on memory-constrained targets (<= 1GB RAM).

#### C. Infrastructure Provider Interface

Standardized interface for provisioning backends.

```python
interface InfrastructureProvider:
    def provision(host_config: Map) -> TargetIP
    def destroy(host_id: String) -> Void
    def get_ip(host_id: String) -> TargetIP
    def status(host_id: String) -> StatusEnum
```

#### D. Rollback Safety Guard

Schedules temporary rollback commands during remote switch execution to prevent lockouts.

#### E. Key & Secrets Manager

Isolates all host SSH identity validation, age key translation, SOPS registration, and Tailscale pre-auth key validation/generation (`lib/keys.sh`). It contacts the Headscale server (`100.64.0.1`) to check pre-auth key status, maps namespaces to numeric IDs, and uses `sops` to update the host's secrets file on demand.

---

## 6. Provider Specifications & Declarative Metadata Schemas

### 6.1 Proxmox Provider Schema

Configurations are mapped under `deployment.proxmox.*`:

- **VM Identification**: `deployment.proxmox.vmid` (Target VM ID).
- **Firmware Type**: `deployment.proxmox.bios` (`ovmf` for UEFI or `seabios` for BIOS).
- **Disk Interface**: `deployment.proxmox.diskBus` (`scsi` or `virtio`).
- **Memory & CPU allocation**: `deployment.proxmox.memory` (MB) and `deployment.proxmox.cores` (cores count).
- **Cloud-Init Metadata Settings**:
  - `deployment.proxmox.cloudInit.image`: Path to target baseline OS image (e.g., `/mnt/pve/images/ubuntu.img`).
  - `deployment.proxmox.cloudInit.user`: Default OS username (defaults to `ubuntu`).
  - `deployment.proxmox.cloudInit.ipconfig0`: Networking options for primary interface (e.g. `ip=dhcp` or static address).
  - `deployment.proxmox.cloudInit.ipconfig1`: Networking options for secondary interface (Optional).
- **VM Creation Behavior (`qm_create`)**:
  - Automatically attaches a Cloud-Init drive by default:
    ```bash
    qm set <VMID> --ide0 <storage>:cloudinit --ipconfig0 ip=dhcp
    ```
  - Network bridges: Assigns dual interfaces WAN (`vmbr0`) and LAN (`vmbr1`) for `router-*` configurations, and single bridge configurations for other nodes.
- **IP Injection & Scanning**:
  - If a VM boots into a VLAN environment without a DHCP server, run the QEMU Guest Agent commands via Proxmox:
    ```bash
    qm guest exec <VMID> -- /run/current-system/sw/bin/ip link add link eth0 name eth0.<vlan> type vlan id <vlan>
    qm guest exec <VMID> -- /run/current-system/sw/bin/ip link set up dev eth0.<vlan>
    qm guest exec <VMID> -- /run/current-system/sw/bin/ip addr add <ip>/<cidr> dev eth0.<vlan>
    qm guest exec <VMID> -- /run/current-system/sw/bin/ip route add default via <gateway>
    ```
  - Subnet IP Scanning Fallback: Scan hypervisor subnet matching VM MAC address via nmap.
- **Cloud-Init Wait Behavior**:
  - The Orchestrator polls for SSH reachability on the Cloud-Init target.
  - Once SSH is available, it returns control to the user immediately, providing a manual command to track the remaining background initialization tasks (e.g., `cloud-init status --wait`).

### 6.2 DigitalOcean Provider Schema

Configurations are mapped under `deployment.digitalocean.*`:

- **Region**: `deployment.digitalocean.region` (e.g. `sgp1`, `nyc1`).
- **Droplet Instance Size**: `deployment.digitalocean.size` (e.g. `s-1vcpu-1gb`).
- **Droplet Source Image**: `deployment.digitalocean.image` (e.g. `ubuntu-24-04-x64`).
- **Resource Constraints**: Default 1GB RAM instances (`s-1vcpu-1gb`) must automatically configure `LOW_MEM=yes` and `BUILD_ON=local` options.

### 6.3 VMware Fusion Provider Schema

Configurations are mapped under `deployment.vmware.*`:

- **VM Identification**: `deployment.vmware.vmxPath` (Absolute path to the `.vmx` file).
- **VM Creation Behavior (`vmware_create`)**:
  - Automatically generates the `.vmx` configuration file from scratch.
  - Provisions a new virtual disk (`.vmdk`) using `vmware-vdiskmanager`.
  - Locates or downloads the target architecture's NixOS minimal ISO for the installer.
- **IP Resolution (`vmware_get_ip`)**:
  - Extracts the generated MAC address from the `.vmx` file.
  - Scans local VMware DHCP lease files (`/var/db/vmware/vmnet-dhcpd-*.leases`) to map the MAC address to the assigned dynamic IP.

---

## 7. Technical Data Dictionary & Option Bindings

The `installer-rs` orchestrator exposes a streamlined set of CLI options. Most target VM/hardware properties (such as VMID, cloud-init paths, disk sizes, bios type, etc.) are declared statically in the Nix flake configuration under `deployment.*` and loaded automatically by the orchestrator at runtime.

### 7.1 Global CLI Options
| Argument | Environment Variable | Default | Description |
| :--- | :--- | :--- | :--- |
| `-d`, `--debug` | `DEBUG` | `false` | Enable verbose debugging output |
| `-F`, `--force` | `CLI_FORCE` | `false` | Skip safety verification prompts (e.g. hostname or username mismatches) |
| `--low-mem` | `LOW_MEM` | None | Override low-memory mode (`yes` or `no`) |
| `--build-on` | `BUILD_ON` | None | Override build strategy (`local`, `builder`, `target`, `instantiated`) |
| `--builder` | `BUILDER` | None | Override remote SSH builder target (e.g. `deploy@utils`) |
| `--repo-src` | `NIX_REPO` | `"local"` | Repository source path or URL |

### 7.2 Subcommand Bindings
* **`deploy`** (Provision, partition, and bootstrap targets):
  * `-t`, `--target`: Target host specifier (`[username@]hostname[=ip]`)
  * `--hosts`: Comma-separated list of host specifiers for batch deployment runs
  * `--plan`: Output dry-run planning/spec details without executing the deployment
  * `--redeploy`: Force recreation of VMs/droplets (destructive)
* **`switch`** (Rebuild and apply configuration profiles to active nodes):
  * `-t`, `--target`: Target host specifier (`[username@]hostname[=ip]`)
  * `--hosts`: Comma-separated list of host specifiers for batch switches
  * `--action`: Rebuild actions: `switch`, `bootentry`, `test`, `build` (Default: `switch`)
  * `--hm`: Include Home-Manager user activation switch
* **`sync`** (Copy directory files or cryptographic keys to targets):
  * `-t`, `--target`: Target host specifier (`[username@]hostname[=ip]`) (Required)
  * `--keys`: Sync personal SSH and GPG credentials to the target system
  * `--repo`: Sync codebase repository files to the target workspace
* **`destroy`** (Stop and wipe provider VM instances):
  * `-t`, `--target`: Target host specifier (`[username@]hostname[=ip]`) (Required)
* **`info`** (Resolve and display target details):
  * `-t`, `--target`: Target host specifier (`[username@]hostname[=ip]`) (Required)
  * `--ip`: Print only the resolved IP address (completely silent output for script integrations)
* **`completions`** (Generate shell completions):
  * Positional `<shell>`: Targets: `bash`, `elvish`, `fish`, `powershell`, `zsh`
