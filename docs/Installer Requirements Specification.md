# Installer Requirements Specification

This document defines the high-level behavior of the `nxd` deployment orchestrator. It describes what the tool must do from a user and system-flow perspective. Programming language choices, module structure, command execution details, and Nix internals belong in [Installer Rust Architecture and Implementation Plan.md](./Installer%20Rust%20Architecture%20and%20Implementation%20Plan.md).

## Goals

`nxd` provides one command surface for managing local and remote Nix systems:

- Provision provider-backed machines.
- Convert stock Linux cloud-init systems into NixOS.
- Install NixOS from ephemeral live environments.
- Switch existing NixOS and nix-darwin hosts.
- Run single-host operations interactively and batch operations concurrently.
- Run fleet command execution without build/deploy side effects.
- Keep host identity, SOPS recipients, and first-boot secrets aligned before activation.

The expected operator experience is one-step convergence:

```bash
nxd switch
nxd switch -t avon
nxd deploy --hosts avon,utils
nxd deploy --hosts avon,utils --overwrite
nxd deploy -t medo-test --redeploy
nxd deploy -t medo-test --redeploy --build-iso
nxd deploy --hosts avon,utils --plan
nxd exec --hosts @router -- uptime
```

`nxd switch` defaults to the current short hostname when neither `--target` nor `--hosts` is provided.

## Entrypoints

The primary command and flake app/package are `nxd`. The root `Makefile` is a convenience wrapper only. `lamd` and `.#installer-rs` remain temporary compatibility aliases:

| Make target    | Forwarded command | Example                         |
| :------------- | :---------------- | :------------------------------ |
| `make switch`  | `nxd switch`     | `make switch ARGS="-t avon"`    |
| `make deploy`  | `nxd deploy`     | `make deploy ARGS="-t avon"`    |
| `make sync`    | `nxd sync`       | `make sync ARGS="-t avon --repo"` |
| `make destroy` | `nxd destroy`    | `make destroy ARGS="-t avon"`   |
| `make info`    | `nxd info`       | `make info ARGS="-t avon --ip"` |
| `make wsl`     | `nxd deploy`     | `make wsl ARGS="--plan"`        |

The Makefile uses `nix run '.#nxd' --` by default from a repo checkout.

Targets use this format:

```text
[username@]hostname[=ip]
```

Examples:

- `nxd switch -t nixos@avon=192.168.1.18`
- `nxd deploy --hosts avon=192.168.1.18,utils=192.168.1.19`

## Host Metadata, Roles, And Selectors

Hosts expose lightweight deployment metadata through `deploymentHosts`. This metadata must be cheap to evaluate and suitable for planning, selection, provider detection, and IP resolution.

Requirements:

- Host metadata may define `role = "<name>"`.
- Hosts without a role normalize to `null`.
- Roles are metadata, not hard-coded behavior. The orchestrator must not require a fixed programming-language enum for role names.
- Host metadata may define `tags = [ ... ]`.
- A role implicitly contributes its role name as a tag.
- Role defaults may contribute tags and deployment defaults, but they must remain cheap to evaluate.
- Host metadata must not require full host module, nixpkgs, overlay, or system configuration evaluation.

`--hosts` accepts comma-separated selectors:

- exact host: `router-main`
- exact host with override: `deploy@router-main=192.168.1.10`
- glob selector: `router-*`
- tag selector: `@router`

Selector requirements:

- `-t/--target` and `--hosts` are mutually exclusive.
- plain selectors without glob characters are exact host names.
- glob selectors match host names.
- `@tag` selectors match normalized tags.
- multiple selectors union and dedupe.
- exact host specs with username/IP overrides take precedence over earlier glob/tag results for the same host.
- explicit selector order is preserved; tag/glob expansion is deterministic within each selector.
- unknown exact hosts fail.
- unmatched tags/globs fail.
- empty selector elements fail.

## Source And Workspace Model

Deployment and switch operations build from an explicit workspace instead of mutating the live repository checkout.

Requirements:

- Local repo checkouts are snapshotted before build/switch/deploy work starts.
- Remote flake sources such as `github:` and `tea:` may be used for bootstrap operations; if no local secrets are available, the operation must still complete with the existing no-secrets warning behavior.
- Host secrets are never staged into Git and are never committed by the installer.
- Each operation creates one immutable source store path and, when available, one separate secret store path per host.
- A host secret store directory contains only `host.yaml`; it must never contain another host's SOPS file.
- Source and secret paths are copied only to the builder or target that evaluates them and are protected by per-run GC roots.
- `sync --repo` is a direct repository sync utility. It does not use deployment store inputs and must not be treated as a build/deploy operation.

## Performance And Resource Optimization

To ensure responsiveness, `nxd` enforces key optimization constraints:

- **Config Batch Queries**: When targeting multiple hosts (via `--hosts`), `nxd` must perform a single-shot batch query to evaluate flake configurations instead of sequential single-host queries.
- **Metadata Fast Path**: `nxd` must prefer the lightweight `deploymentHosts` flake output for planning and provider detection, falling back to full system evaluation only for compatibility.
- **Evaluation Caching**: Target host configurations must be cached in memory to completely prevent redundant `nix eval` executions across the planning, resolution, and execution phases.
- **Inline Feature Probing**: Target features (such as `diskoScript` presence) must be probed inline during the main metadata evaluation, avoiding standalone process executions.
- **Local Target Bypass**: Network IP resolution and SSH checks must be completely bypassed when switching the orchestrator host itself (`localhost` / short hostname).
- **Cached Local Hostname**: The local system hostname query must be cached to prevent spawning redundant processes.
- **Host Nix Preference**: The wrapper script must suffix the store Nix package rather than prefixing it, preferring the host's native/optimized Nix installation (and its warm evaluation cache) over the colder store-packaged Nix fallback version.
- **Fast IP Resolution Fallbacks**: Virtualization providers must query active hypervisor caches (such as `ip neigh` or guest agents) before executing slow subnet-wide scans.

## Commands

### `switch`

Applies a NixOS or nix-darwin configuration to an existing host.

Requirements:

- Supports local NixOS and local nix-darwin switches.
- Supports remote NixOS switches over SSH.
- Supports switch, boot, test, and build as subcommands.
- Optimizes NixOS switch/boot/test runs by skipping activation if the target system is already running the built generation (bypassable with `-F`/`--force`).
- Supports `--hm` for Home Manager activation.
- Supports selector-based `--hosts` and batch switching.
- Supports `--parallel <N>` for batch fan-out.
- Skips remote SSH host-key validation for local self-switch targets.
- Reports consistent elapsed time for single-host and batch runs.

### `deploy`

Converges a machine from provider state, stock Linux, or live installer state into the final NixOS system.

Requirements:

- Default deploy behavior is conservative for provider-backed hosts: missing instances are created and deployed, while existing instances are skipped and reported to the user.
- `--overwrite` reuses existing provider-backed instances and permits in-place install/partitioning. It must not destroy/recreate the provider instance.
- `--redeploy` destroys and recreates provider-backed instances before verification or installation.
- `--redeploy` is stronger than `--overwrite`: it discards the provider instance first, then proceeds with verification or installation.
- Existing destructive targets require `--overwrite` or `--redeploy` before destructive install work may run.
- Cloud-init template verification stops after confirming SSH access.
- In-place software takeover is handled via the separate `convert` command: `nxd convert --target <source> --to <destination-host>`.
- Batch deploy plans must show each host's provider action clearly, such as create/deploy, skip existing, overwrite existing, or redeploy.
- `--plan` must be side-effect free: it may query metadata and provider state, but it must not stage Proxmox ISOs, create instances, destroy instances, mutate secrets, or prepare install workspaces.
- For Proxmox NixOS ISO deploys, missing ISO staging prompts, builds, downloads, and uploads must happen only after the operator confirms the deploy plan.
- The `--build-iso` flag forces rebuilding and uploading of the custom NixOS ISO. If a remote builder is configured for the target host, the ISO is compiled directly on the remote builder and SCPed directly to the Proxmox host using SSH agent forwarding, bypassing the local developer workstation entirely.
- Supports selector-based `--hosts` and `--parallel <N>` for batch deployment.
- Host SSH keys and SOPS secrets must be staged before `nixos-install` and remain valid after reboot.
- After reboot, provider-backed deploys should resolve and report the final provider IP using a polling lookup so DHCP and hypervisor state can settle.

### `exec`

Runs a remote command against one or more hosts.

Requirements:

- Supports `-t/--target` for a single host.
- Supports selector-based `--hosts` for batch execution.
- Supports `--parallel <N>`.
- Supports buffered output by default for batch execution.
- Supports `--stream` for real-time interleaved output with host prefixes.
- Uses the same fleet host/IP resolution behavior as `switch`.
- Does not prepare workspaces.
- Does not build systems.
- Does not stage secrets.
- Does not run provider lifecycle actions.
- Does not run deploy or switch workflows.
- Returns non-zero if any host fails.
- Remote command arguments are shell-escaped unless the user explicitly invokes a shell such as `sh -lc`.

### `sync`

Copies repository data or user credentials to an existing target.

Requirements:

- `--repo` syncs the codebase.
- `--keys` syncs SSH/GPG credentials through the identity service workflow.
- Target overrides from `[username@]hostname[=ip]` apply consistently.

### `destroy`

Destroys provider-managed instances using the host's declarative provider metadata.

Requirements:

- Requires explicit target selection.
- Requires confirmation for destructive operations unless forced.

### `info`

Displays resolved target metadata.

Requirements:

- `--ip` prints only the resolved IP address for scripting.
- Provider-backed hosts may resolve IPs through provider APIs, guest agents, or subnet scans.

## State Convergence Flow

`deploy` treats hosts as states and executes only the required transition.

| State | Description | Next action |
| :---- | :---------- | :---------- |
| Provider missing | VM/droplet does not exist | Create provider instance |
| Provider exists | VM/droplet already exists | Skip by default; install only with `--overwrite`; recreate only with `--redeploy` |
| Cloud-init Linux | Stock Ubuntu/Debian-style target | Verify SSH or kexec into installer |
| Ephemeral installer | NixOS live/kexec environment | Partition and install |
| Installed NixOS | System is installed but not necessarily current | Reboot and/or switch |
| Converged | Active target generation is applied | Finish |

Main deployment flow:

1. Resolve target metadata and provider information.
2. Ensure target instance exists: create missing provider instances, skip existing instances by default, reinstall existing instances for `--overwrite`, or recreate them for `--redeploy`.
3. Wait for SSH and identify the current OS state.
4. If needed, boot into an ephemeral NixOS installer with kexec.
5. Stage identity services: SSH host key, SOPS file, Tailscale pre-auth key, and GPG material where applicable.
6. Run Disko partitioning.
7. Build or realize the target system using the selected build strategy.
8. Copy the target system closure to the installation root.
9. Run `nixos-install --system <system-path>`.
10. Re-stage host SSH keys after installation if the installer activation changed `/mnt/etc`.
11. Reboot into the final system.
12. Resolve the post-reboot provider IP when available, clean stale known-host entries for that address, and report elapsed time.

The installer uses a single final installation stage. It does not intentionally reboot into a temporary minimal NixOS generation before applying the final host configuration.

### WSL Target Flow

For WSL provider targets (`deployment.wsl.enable = true`):

- The Windows control plane requires OpenSSH public-key access and explicit non-interactive
  PowerShell invocation.
- A missing distribution is created from the reusable
  `result-wsl/nixos-wsl-custom.tar.gz` bootstrap artifact.
- Artifact construction uses the pinned NixOS-WSL module and
  `nixosConfigurations.minimal-wsl-x86.config.system.build.tarballBuilder`.
- `nxd build --artifact minimal-wsl` is an offline artifact-only path and does not contact
  Windows.
- Provider deployment imports/starts the distribution, resolves the guest endpoint, then reuses
  normal source, secret, build, copy, profile registration, activation, and lockfile paths.
- WSL skips Disko, kexec, `nixos-install`, swap preparation, and reboot.
- Mirrored networking uses direct guest SSH. NAT-mode guests use the Windows OpenSSH control host
  as a jump host.
- Existing distributions are skipped by default, converged with `--overwrite`, and
  unregistered/re-imported with `--redeploy`.


## Low-Memory Behavior

Low-memory hosts are first-class deployment targets. A host may opt in through `deployment.lowMem = "yes"` or by CLI override.

Expected behavior:

- Avoid target-side Nix evaluation when a local or remote builder can evaluate/build the system.
- Prefer copying a realized system closure to the target for the lowest target memory usage.
- When target realization is unavoidable, constrain target Nix jobs and provide swap before realization.
- During kexec/live-installer deployment, allocate additional ZRAM swap before heavy work.
- After partitioning, create a physical swapfile under `/mnt` for low-memory installations.

The exact Nix commands, environment variables, and build-strategy routing are implementation details covered in the Rust architecture document.

## Host Identity And Secret Staging

The deployment must avoid first-boot SOPS/key mismatch loops.

Requirements:

- Remote target SSH host keys are generated or sourced before deployment.
- The target SSH public key is converted to an age recipient.
- The secrets repository is updated when the target recipient is missing or stale.
- If the secrets repository is missing local host-key material but the target has an active host key, interactive runs must ask whether to import the target key into secrets, generate a fresh local key, or abort.
- Non-interactive forced runs may import a missing target key only when the secrets-key update policy is explicitly enabled.
- If local secrets key material and the active target key mismatch, the operator must be able to choose between overwriting the target from secrets, updating secrets from the target, proceeding anyway, or aborting.
- Host-specific SOPS files are resolved in priority order from the external secrets repository (specified via the `--secrets-repo` CLI option, `DEFAULT_SECRETS_REPO` environment variable, home directory auto-detection, or sibling `../lamt-secrets`), then repo-local `./secrets` (resolved relative to the active flake directory).
- Only `secrets/sops/<host>.yaml` for the current target host is injected into that host's temporary workspace.
- Host-specific SOPS files are staged only for the duration needed by evaluation/deployment and cleaned up on success or failure.
- The target private SSH host key is installed into `/mnt/etc/ssh`.
- After `nixos-install`, the target host key is staged again to account for activation steps that may rewrite `/mnt/etc`.
- Local self-switches use the active host key and do not create dummy target keys.

Tailscale-enabled hosts also validate or refresh declarative pre-auth keys through the Headscale coordinator before installation.

## Build Strategy Expectations

The orchestrator chooses a build path from declarative host metadata and CLI overrides.

| Strategy | Expected use |
| :------- | :----------- |
| Local | Build on the machine running `nxd` when platform-compatible. |
| Remote builder | Delegate build to a configured builder such as `deploy@utils`. |
| Target realization | Evaluate elsewhere, then realize on the target. |
| Target native | Build directly on the target only when necessary. |

Remote builder runs copy one immutable source store path per operation and one immutable
secret store path per host. Nix deduplicates repeated source copies, while host secrets
remain independently addressable and GC-rooted.

For cloud or WAN hosts, substituting on the destination may be enabled declaratively to let the target fetch from configured substituters instead of copying every path from the builder over SSH. The default remains off unless a host opts in. Debug mode should print the exact `nix copy` command so operators can confirm whether `--substitute-on-destination` is active.

Build strategy implementation must keep command rendering deterministic and testable. Shared copy targets, remote-builder commands, target-native commands, and target-realization commands should be rendered through common helpers instead of duplicated per workflow.

## Provider Scope

Provider metadata is declarative under `deployment.*`.

Supported provider classes:

- Proxmox VMs, including cloud-init template provisioning.
- DigitalOcean droplets.
- VMware Fusion/Workstation VMs.
- Existing hosts with static or dynamically resolved target IPs.

Provider implementations must support the same lifecycle concepts where applicable:

- Create or verify instance.
- Destroy instance.
- Resolve IP address.
- Provide enough metadata for deploy planning and safety prompts.

Provider IP resolution may be immediate or polling depending on caller intent. Planning and early fallback checks should avoid hidden waits; boot and post-reboot checks may poll to obtain the usable final address.

## Batch Behavior

Batch runs are selected with `--hosts`.

Requirements:

- Each host has isolated logs.
- Single-host operations stream directly to the terminal and may prompt interactively.
- Batch operations run concurrently and summarize per-host status.
- `--parallel <N>` limits host operation fan-out.
- `--parallel 0` means unlimited.
- Batch operations must isolate host-specific SOPS files in distinct immutable store paths.
- Multiple hosts using the same remote builder share the immutable source store path while retaining separate host secret paths.
- Elapsed time formatting is consistent between single-target and batch paths.
- Failure output includes enough recent log context to diagnose the failing host.

## Progress And Logging

Operator output must make fleet operations readable without leaking secrets.

Requirements:

- Status levels should distinguish info, success, warning, error, failure, and debug output.
- Terminal output should visually distinguish warning, error, success, failure, and debug status where color is available.
- Batch log files must remain readable plain text by default.
- Debug output must use a consistent `[DEBUG]` prefix.
- Debug output must not expose private keys, SOPS contents, stdin payloads containing key material, tar payloads, or secret file contents.
- Provider existence probes used for planning must not leak raw provider command output into the plan.
- Batch streamed command output must include host prefixes.

## Safety Requirements

- Destructive deploy and destroy operations must prompt unless explicitly forced.
- Hostname/user mismatches must be surfaced before proceeding.
- Local known-host entries may be cleaned for rebuilt targets when host keys are intentionally replaced.
- Remote switch operations must preserve rollback safety where possible.
- Staged secrets must be scoped to one host, GC-rooted only for the operation lifetime, and never printed or committed.
