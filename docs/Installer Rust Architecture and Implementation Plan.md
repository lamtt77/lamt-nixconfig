# Installer Rust Architecture And Implementation Plan

This document describes how `apps/nxd` implements the behavior specified in [Installer Requirements Specification.md](./Installer%20Requirements%20Specification.md). It stays focused on Rust code structure, module ownership, execution strategy, and implementation tradeoffs.

## Package And Entrypoint

The Rust crate, installed command, package, and flake app are named `nxd`.

Packaging layout:

- `pkgs/nxd/default.nix` builds the Rust package from a cleaned `apps/nxd` source tree.
- `apps/nxd.nix` exposes the flake app and points it at `${nxdPkg}/bin/nxd`.
- Managed systems install `pkgs.nxd`.

The package creates temporary `lamd` and `installer-rs` compatibility symlinks. The Makefile
remains a thin forwarding wrapper around `nix run .#nxd --`.

## Crate Layout

Current high-level source layout:

```text
apps/nxd/src/
  main.rs
  cli.rs
  config.rs
  context.rs

  command/
    deploy.rs
    switch.rs
    sync.rs
    destroy.rs
    info.rs
    exec.rs
    hosts.rs

  fleet/
    metadata.rs
    selectors.rs
    local.rs
    resolution.rs

  planning/
    mod.rs
    plan_iso.rs
    plan_local.rs
    plan_render.rs
    plan_risk.rs
    plan_spec.rs

  workflow/
    artifact.rs
    confirm.rs
    deploy.rs
    deploy_disko.rs
    deploy_install.rs
    deploy_kexec.rs
    deploy_mode.rs
    deploy_reboot.rs
    deploy_swap.rs
    deploy_system.rs
    deploy_wait.rs
    lockfile.rs

  execution/
    batch.rs
    coordinator.rs
    host.rs

  process.rs

  progress/
    color.rs
    log.rs
    stream.rs
    target.rs

  nix/
    build.rs
    build_commands.rs
    build_local.rs
    build_remote_builder.rs
    build_target_instantiated.rs
    build_target_native.rs
    copy.rs
    eval.rs
    remote_builder.rs
    strategy.rs

  remote/
    known_hosts.rs
    ssh.rs

  workspace/
    local.rs
    remote.rs
    secrets.rs
    source.rs

  identity/
    gpg.rs
    sops.rs
    tailscale.rs
    ssh/
      host_key_mismatch.rs
      host_key_staging.rs
      host_key_validation.rs
      host_keys.rs
      personal_keys.rs

  providers/
    digitalocean.rs
    proxmox.rs
    vmware.rs
    wsl/
      commands.rs
      mod.rs
```

Use this ownership model:

- `main.rs` wires CLI parsing, global runtime options, subprocess-facing environment defaults, and command dispatch.
- `command/` owns thin CLI adapters.
- `fleet/` owns host metadata, selector expansion, local-host detection, provider detection, and endpoint/IP resolution.
- `planning/` owns side-effect-free host plans, provider snapshots, risk classification, rendering, and Proxmox ISO planning.
- `workflow/` owns reusable deployment, artifact, confirmation, and post-success workflow steps.
- `execution/` owns the shared coordinator, prepared host jobs, host execution, concurrency, per-host logs, and result aggregation.
- `progress/` owns status rendering, color policy, and debug formatting.
- `nix/` owns Nix build strategy dispatch, strategy-specific build execution, pure command rendering helpers, evaluation helpers, copy command construction, and remote-builder coordination.
- `remote/` owns reusable SSH and known-host mechanics.
- `workspace/` owns immutable source snapshots, per-host secret store inputs, transfer destinations, and GC-root lifecycle.
- `identity/` owns SSH host keys, SOPS/age integration, Tailscale pre-auth validation, and GPG staging.
- `providers/` owns lifecycle state, capabilities, resource identity, endpoint discovery, and provider-specific control commands.

Avoid reintroducing source modules named `target/`; it is easy to confuse with Rust build output. Keep `progress/` rather than renaming it to `log/` because the module covers visual status, colored levels, host-prefixed batch output, summaries, and future progress indicators.

## Runtime Options

`config::RuntimeOptions` is the internal source of truth for runtime policy:

- debug
- force
- low-memory override
- build strategy override
- builder override
- flake reference
- redeploy and overwrite policy
- deploy activity
- host-key and secrets-key update policy

Internal Rust workflow code should read `RuntimeOptions`, not process-wide environment variables such as `CLI_FORCE`, `LOW_MEM`, `BUILD_ON`, `BUILDER`, `DEPLOY_ACTIVE`, or `BATCH_HOSTS`.

Environment variables are still acceptable for compatibility and subprocess behavior, for example:

- `NIX_SSHOPTS` for Nix copy/SSH subprocesses.
- `INSTALLER_RS_DEBUG` for debug compatibility.
- process facts such as `TMPDIR`, `USER`, and provider-specific defaults.

Do not add new process-global environment switches for internal installer policy unless there is a concrete subprocess interoperability requirement.

## Command Routing

`main.rs` parses CLI flags with `clap`, stores runtime options, then routes to command modules.

Routing rules:

- `switch` with neither `--target` nor `--hosts` defaults to the current short hostname.
- `-t/--target` and `--hosts` are mutually exclusive and fail before inventory/context loading.
- Single-target operations stream command output directly to the terminal.
- Planning inspects each provider once and fails on control-plane errors rather than treating them as missing resources.
- Single-host and batch operations use the same prepared host job representation.
- Batch operations use `execution::batch` and isolated per-host logs.
- Local self-switch targets are detected by hostname or loopback IP and skip remote SSH host-key validation.
- `exec` skips workspace prep, build, provider lifecycle, and secret staging.

The routing layer should select the command and target set, then delegate behavior to command,
planning, workflow, execution, fleet, provider, workspace, identity, and Nix modules.

## Fleet Metadata And Selectors

`fleet/metadata.rs` owns declarative metadata extraction from `deploymentHosts`. `context.rs` converts metadata into `RuntimeContext` and handles `[username@]hostname[=ip]` overrides.

Target specs support:

```text
[username@]hostname[=ip]
```

Selector rules live in `fleet/selectors.rs`:

- plain names are exact hosts
- `@tag` matches normalized tags
- glob selectors match host names
- multiple selectors union and dedupe
- exact host specs with username/IP overrides replace prior glob/tag results for the same host
- explicit selector order is preserved
- tag/glob expansion is sorted within each selector for deterministic output
- unknown exact hosts, unmatched tags/globs, and empty selector elements fail

Roles are Nix-owned metadata. Rust should keep `role: Option<String>` and `tags: Vec<String>` as data, not hard-code role enums or role-specific workflows.

## Context Loading And Caching

`RuntimeContext::load_batch` uses the lightweight `deploymentHosts` metadata fast path and evaluates multiple hosts in one Nix expression. A process-wide cache prevents duplicate `nix eval` calls across planning, resolution, and execution phases.

Performance rules:

- Prefer `deploymentHosts` over full `nixosConfigurations` / `darwinConfigurations` evaluation.
- Keep `meta.nix` cheap to evaluate; it must not import host modules, nixpkgs, overlays, or evaluated system configs.
- Carry host installability such as `hasDisko` in metadata where possible.
- Cache the current local hostname with `OnceLock`.
- Prefer the host system's `nix` binary through the wrapper PATH suffix so warm host-side Nix caches are used.

Callers should not build raw Nix attr paths. Use helpers in `fleet/metadata.rs` and `nix/`.

## Workspace And Source Preparation

`workspace/` prepares the source tree used for build, deploy, and switch operations without mutating the live checkout.

Module ownership:

- `workspace/local.rs`: component sanitization, unique run identifiers, and stale staging cleanup.
- `workspace/source.rs`: local and remote flake materialization, per-host secret staging, Nix store transfer, and GC roots.

Each operation uses one immutable source store path. Every real host secret is a separate
store directory containing exactly one encrypted file named `host.yaml`. Inputs are copied
only to the machine that evaluates them. Per-run local and remote GC roots protect inputs
during execution and are removed afterward; stale roots are cleaned by age.

## Nix Build Strategy

`nix/` owns all Nix build, copy, evaluation, and remote-builder coordination.

Module ownership:

- `nix/strategy.rs`: strategy selection and `NixBuilder`.
- `nix/build.rs`: public build dispatcher plus shared `BuildRequest` and `BuildOutput` types.
- `nix/build_commands.rs`: pure command/render helpers used by production strategy modules and unit tests.
- `nix/build_local.rs`: local Nix build plus copy to the target when needed.
- `nix/build_remote_builder.rs`: remote builder source sync, per-host workspace preparation, remote build, and copy to target.
- `nix/build_target_instantiated.rs`: local derivation evaluation, drv/input closure copy, and target-side realization.
- `nix/build_target_native.rs`: source sync to target and target-side `nix build`.
- `nix/copy.rs`: `nix copy` argument and command rendering.
- `nix/eval.rs`: local Nix capability checks and evaluation helpers.
- `nix/remote_builder.rs`: per-builder locks and common-base sync state.

Supported strategies:

| Strategy | Responsibility |
| :------- | :------------- |
| Local | Build on the orchestrator and copy to target when needed. |
| Remote builder | Copy immutable source and host-secret store paths to the builder, build there, copy closure to target. |
| Target instantiated | Evaluate derivations off target, copy drv/input paths, realize on target. |
| Target native | Copy and root source inputs on the target, then run Nix directly there. |

Attribute routing is OS-aware:

- NixOS toplevel: `nixosConfigurations.<host>.config.system.build.toplevel`
- NixOS Disko: `nixosConfigurations.<host>.config.system.build.diskoScript`
- Darwin system: `darwinConfigurations.<host>.system`

`substituteOnDestination` adds `--substitute-on-destination` to relevant `nix copy` operations. Debug mode logs the exact rendered `nix copy` command once per copy operation.

Remote builder rules:

- If the configured builder resolves to the current host, use a local build.
- If the remote builder resolves to the target host itself, the remote build is executed directly on the target host and the redundant `nix copy` loopback is skipped.
- Copy the common source store path once per builder per batch run.
- Keep each host secret in its own store path and GC root.
- Build directly from immutable store paths; no mutable builder workspace is created.

### Strategy Selection Priority

When no explicit `--build-on` flag is specified, the strategy resolves as follows:
1. **Remote builder**: Selected if a builder is configured (e.g. defaults to `deploy@utils`).
2. **Local**: Selected if the local workstation's architecture is natively compatible with the target.
3. **Target instantiated**: Selected if the target has low memory (`low_mem = true`).
4. **Target native**: Selected as the default remote target fallback for normal resource targets.

Build module rules:

- Keep `NixBuilder::build_attribute(...)` and `NixBuilder::build_system(...)` as the public API for workflow and execution code.
- Route all strategy selection through `nix/build.rs`; strategy modules should implement one strategy each.
- Put repeatable command rendering in `build_commands.rs` or `copy.rs` rather than inlining shell strings across strategies.
- Keep command rendering helpers deterministic and covered by unit tests, especially copy target rendering, mounted-store flags, remote-builder commands, and low-memory target realization flags.

## Deploy Workflow

`workflow/deploy.rs` implements the single-stage convergence deploy workflow.
`execution/host.rs` consumes provider state/capabilities/endpoints and invokes the workflow.

High-level deploy sequence:

1. Determine provider lifecycle policy: create missing, skip existing by default, overwrite in place, or redeploy by destroy/create.
2. Render the plan and obtain confirmation before side effects such as provider destroy/create or ISO staging.
3. Stage the expected Proxmox NixOS ISO only after confirmation.
4. Resolve deploy IP with explicit deploy-mode resolution, preferring provider IP for provider-backed deploys.
5. Wait for initial SSH.
6. Detect live installer, stock Linux, or installed system state.
7. Use kexec when needed to enter an ephemeral NixOS installer environment.
8. Configure low-memory ZRAM swap when required.
9. Run identity pre-install services.
10. Build/copy and run the Disko script.
11. Create physical swap under `/mnt` for low-memory targets.
12. Build or realize the final system toplevel.
13. Run identity post-install services.
14. Run `nixos-install --system <toplevel>`.
15. Re-stage SSH host keys after installation.
16. Reboot.
17. Poll provider IP discovery for the final post-reboot IP notice, clean known-host entries for that final address, and report elapsed time.

The Rust installer intentionally avoids the old installer2 two-stage deployment model. It installs the final host configuration directly and uses kexec only as an in-memory transition into an installer environment.

Proxmox ISO staging is owned by `planning/plan_iso.rs`:

- `--plan` remains side-effect free.
- Batch and single-host deploys stage ISOs only after destructive-risk confirmation succeeds.
- Expected ISO paths are derived from Proxmox metadata, custom ISO config, `NIXOS_ISO`, and repository defaults.
- The `--build-iso` option forces custom ISO recompilation. If a remote builder is configured, the build runs on the remote builder and SCPs directly to the Proxmox host via SSH agent forwarding, avoiding copy-back to the orchestrator.
- The provider implementation only consumes the expected staged ISO path; it does not prompt, build, download, or upload ISOs.

Provider IP resolution uses two different policies:

- Planning and early deploy fallback lookups use non-polling provider resolution to keep planning responsive and avoid hidden waits before confirmation.
- The final post-reboot deploy notice uses polling provider resolution because DHCP, guest-agent, and hypervisor network state can lag after reboot.

## Switch Workflow

Switch behavior is coordinated by `execution/host.rs` using `nix/`, `workspace/`, `remote/`, and `identity/`.

Supported switch paths:

- local Darwin: `darwin-rebuild <action> --flake <prepared-flake-ref>#<host>`
- local NixOS: NixOS rebuild equivalent
- remote NixOS: build according to strategy, copy closure when needed, then apply target profile/action over SSH
- Home Manager: local or remote `home-manager switch` using the prepared workspace

Remote switch should validate/sync target host keys before activation, preserve rollback safety
where possible, and keep switch-specific execution in execution/workflow code rather than `nix/`.

### Self-Updating Execution Behavior

When developing or modifying `nxd` itself (e.g. editing `main.rs`):
- **Using `nxd switch`**: If you run `nxd switch -t <host>`, the system evaluates the flake, builds the new `nxd` binary, and installs it to your path. However, the currently running process orchestrating the switch is still the old version. The new binary's logic will only be active starting from the next invocation.
- **Using `nix run`**: To run the new installer logic immediately for the current switch, run:
  ```bash
  nix run '.#nxd' -- switch -t <host>
  ```
  This forces Nix to compile the updated Rust code first and then execute the newly compiled binary to orchestrate the switch.


## Batch Execution And Parallelism

`execution/batch.rs` schedules prepared deploy and switch host jobs. Fleet `exec` remains a
separate direct-command path.

Rules:

- Single-target executions (jobs size 1) bypass `BatchRunner` and run directly. This streams remote execution in real-time, removes log prefixing, and skips the batch summary.
- Single-host `switch` operations run without interactive confirmation prompts.
- `--parallel <N>` limits host operation fan-out in batch mode; `0` means unlimited.
- Per-host logs remain isolated in batch mode.
- Host output is prefixed in batch mode.
- Batch summaries report succeeded and failed counts.
- Provider locks, builder sync locks, and workspace isolation remain authoritative for shared-resource safety.
- Concurrency permits must be released on success, error, and task panic.

Batch code must not duplicate deploy or switch behavior. It consumes prepared jobs, creates
workspaces, schedules host operations, collects results, prints useful failure context, and
reports summaries.

## Remote Execution

`remote/ssh.rs` owns reusable SSH mechanics through `SshSession` and `SshOptions`. Root
`process.rs` remains the external process boundary for local commands, command recording/mocking
in tests, child output capture, and progress-aware logging.

Rules:

- Use shared SSH option rendering for automation and Nix copy.
- Use public-key-only / batch-friendly options where operations must not hang on password prompts.
- Direct SSH probes should go through reusable remote helpers.
- Known-host cleanup belongs in `remote/known_hosts.rs`.
- `exec` uses the same fleet resolution path as switch, but skips workspace, provider lifecycle, build, and secrets.

Avoid adding raw `Command::new("ssh")` call sites outside `remote/` unless there is a narrow provider-specific reason.

## Progress And Logging

`progress/` owns visual status output rather than raw logging only.

Status levels:

- info
- success
- warning
- error
- failure
- debug

Rules:

- Debug output uses one `[DEBUG]` prefix and routes through `log_debug!`.
- Terminal status output may be colored according to `ColorMode`.
- Batch log files should remain plain text by default.
- Internal workflow status should use `log_status!`, not ad hoc `println!`.
- Direct stdout remains acceptable for intentional command output such as `info` and buffered `exec` output.
- Provider existence probes should be silent during plan rendering.

Never print private keys, secret contents, stdin tar payloads, or SOPS material.

## Identity Services

Identity handling is implemented as composable services under `identity/`.

Responsibilities:

- `identity/ssh/host_keys.rs`: shared host-key helpers, key generation/lookup, public-key normalization, and age-recipient conversion support.
- `identity/ssh/host_key_validation.rs`: pre-switch/deploy target host-key validation, missing local key handling, remote hostname safety checks, and interactive/non-interactive import or fresh-key decisions.
- `identity/ssh/host_key_mismatch.rs`: mismatch resolution between active target key material and secrets-repo key material.
- `identity/ssh/host_key_staging.rs`: staging pre-generated target host keys into the install root.
- `identity/ssh/personal_keys.rs`: manual personal SSH key sync.
- `identity/sops.rs`: identity-service integration point for SOPS.
- `identity/tailscale.rs`: Headscale reachability, pre-auth key validation, and key refresh.
- `identity/gpg.rs`: GPG credential staging/sync.

Build-time host SOPS staging is owned by `workspace/source.rs`; identity services own target-side credentials and key material.

Host-key safety rules:

- A target hostname mismatch aborts before changing the host unless an explicit deploy-mode override permits the workflow.
- If the secrets repository is missing the local public/private host key but the target has an active host key, interactive runs must ask whether to import the target key, generate a fresh local key, or abort.
- Non-interactive forced runs import a missing target key only when `UPDATE_SECRETS_KEY=yes`; otherwise they fail rather than silently changing secrets.
- Host-key mismatch resolution keeps the existing choices: overwrite target from secrets, update secrets from target, proceed anyway, or abort.
- Public key files written into the secrets repository should be newline-terminated to stay friendly to Git and POSIX tools.

## Provider Implementations

Provider modules implement the lifecycle-focused trait from `providers/mod.rs`:

- `inspect`
- `capabilities`
- `resource_identity`
- `create`
- `destroy`
- `get_ip`
- `endpoint`

Provider-specific command semantics stay inside provider modules. Generic SSH execution, known-host cleanup, and logging mechanics should stay in shared modules.

Provider notes:

- Proxmox uses `qm` for lifecycle and resolves IPs through guest agent or hypervisor network tables before slower polling/fallbacks.
- Proxmox NixOS ISO path selection and staging are not provider responsibilities;
  `planning/plan_iso.rs` handles that after confirmation.
- VMware resolves leases from platform-specific DHCP lease locations and keeps VMX generation/parsing inside the VMware module.
- DigitalOcean uses `doctl` and declarative `deployment.digitalocean` metadata.
- WSL uses strict-known-host Windows OpenSSH, encoded PowerShell commands, typed guest endpoints,
  and direct or Windows jump-host SSH readiness checks.

Providers should produce or locate a reachable target. They should not own installation, switch, workspace, or identity workflow logic.

Callers choose whether IP discovery may poll by using `ProviderIpMode`:

- `NonPolling` for planning and responsive fallback checks.
- `PollUntilReady` for boot/reboot boundaries where waiting for provider or DHCP convergence is expected.

## Nix Packaging Details

The package source should be narrow so unrelated Nix config changes do not force Rust recompilation.

`pkgs/nxd/default.nix` uses `lib.cleanSourceWith` over `apps/nxd` rather than the whole flake source. It filters local build products such as:

- `target/`
- `.direnv/`
- `result`

The wrapper should include runtime tools used by the installer, including Nix, OpenSSH, rsync, Git, SOPS, `ssh-to-age`, and configured provider CLIs.

## Migration Notes From installer2

Keep these improvements from the Rust rewrite:

- Replace regex JSON parsing with typed `serde_json`.
- Keep provider-specific parsing inside provider modules.
- Replace fragile shared shell state with scoped Rust data structures where possible.
- Preserve installer2 behavior only when it is still required by real workflows.
- Avoid reintroducing the deprecated two-stage deployment model.

Shell installer2 remains useful as a reference for edge-case behavior, but new feature work should land in `apps/nxd`.

## Test And Validation Plan

Minimum validation before relying on installer changes:

- `cd apps/nxd && cargo fmt --check`
- `cd apps/nxd && cargo test`
- `cd apps/nxd && cargo clippy --all-targets -- -D warnings`
- `nix build .#nxd`
- `nxd switch --help`
- `nxd deploy --hosts <host> --plan`

Focused Rust tests should cover:

- selector expansion and ordering
- target/host metadata deserialization
- fleet resolution policy
- runtime option behavior
- build strategy selection
- build command rendering
- SSH option rendering
- progress/debug rendering
- provider skip/overwrite/redeploy policy
- batch result aggregation

Real-world smoke tests:

- local Darwin `nxd switch`
- local/remote NixOS `nxd switch -t <host>`
- batch switch with multiple hosts
- batch deploy with missing provider hosts
- batch deploy with existing provider hosts skipped by default
- batch deploy with `--overwrite`
- batch deploy with `--redeploy`
- Proxmox cloud-init verification
- in-place software takeover via `nxd convert`
- low-memory host deploy

Source transport regression checks:

- local switches evaluate the prepared source store path and override the host secret input
- remote-builder operations copy source once and keep per-host secrets isolated
- target-native operations root source and secret inputs on the target
- non-Git source checkouts use the filtered rsync snapshot path
- `sync --repo` remains an explicit checkout sync and does not use deployment store inputs

## Tiered Integration Testing Strategy

The repository organizes and prepares integration tests across three distinct tiers to separate Nix configurations, orchestrator behaviors, and virtual lifecycle states:

### Tier 1: Static Nix Evaluations (tests/*.nix)
- **Purpose**: Verifies that template substitutions, target profiles (disk configurations, netmasks, gateways), and Nix-level assertions (such as Kea/dnsmasq interface conflicts) evaluate correctly without errors.
- **Location**: Structured under `tests/` named `<feature>-test.nix`.
- **Execution**: Run via `nix-instantiate --eval --strict tests/<name>-test.nix` for lightweight pre-deployment verification.

### Tier 2: Rust Planning & Command Tests (cargo test)
- **Purpose**: Verifies CLI argument parsing, metadata schema deserialization, dynamic IP updates, build strategy selection, and the correct rendering of raw SSH and virtualization command strings.
- **Location**: Native Rust tests (`#[cfg(test)]`) inside the `apps/nxd/src` packages.
- **Execution**: Run via `cargo test` in `apps/nxd`. Tests are completely stateless and use mocks to simulate command execution without side effects.

### Tier 3: Lifecycle Environment Orchestrations (tests/*.sh)
- **Purpose**: Exercises stateful integration pipelines by communicating with Proxmox APIs, managing virtual PXE bridges, rolling back VM states, starting machines, and testing final SSH accessibility.
- **Location**: Bash scripts under `tests/` (e.g., `tests/test_pve_pxe_integration.sh` and `tests/test_medo_deployment.sh`).
- **Guidelines**:
  - **Clean State**: Ensure previous test runs are wiped or rolled back to a base VM snapshot.
  - **Keep Option**: By default, automatically destroy and deprovision test VMs, but accept flags (like `--keep`) to let operators inspect the intermediate states.
  - **Shared Helpers**: Consolidate network checking, SSH configurations, and common log formatting into shared bash helpers in the `tests/` folder.

### Tier 4: Manual Hardware & Release Gate-Checks
- **Purpose**: Validates physical hardware behavior, BIOS boot sequences, and switch-level settings that are technically impossible to automate within a virtualized sandbox, or provides safety "gates" before deploying to production.
- **Key Validation Points**:
  - **Physical Switch & Bonding**: Verifying the transition of management traffic to the physical three-NIC LACP bond (`bond0`) and VLAN 10 tagging on the HP ProCurve switch.
  - **USB Bootloader & Refind**: Physically flashing the rEFInd bootloader USB (`dd`) and verifying BIOS NVMe boot priority on the Dell R720.
  - **Production Dry-run**: Running the installer with the `--dry-run` or `--plan` flag to inspect the planned actions (e.g., confirming partition layouts and target system configurations) before making changes.
  - **Secret Sanitization**: Manually scanning logs and build derivation files using standard strings search to guarantee no credential material (like the root installer password) is exposed or committed.

## WSL Deployment Guide

WSL is a provider with a Windows control plane and a NixOS guest target. `nxd` connects to Windows OpenSSH, runs explicit non-interactive PowerShell and `wsl.exe` commands, imports the minimal bootstrap image when needed, then builds and activates the final host configuration through the normal NixOS switch path.

### Windows Prerequisites

1. Install/enable WSL 2 and Windows OpenSSH Server.
2. Record and verify the Windows OpenSSH host key:
   ```bash
   ssh windows-user@windows-host.example
   ```
   `nxd` requires strict host-key checking for the Windows control plane. It does not silently accept or replace Windows host keys.
3. Authorize the invoking machine's public key for the configured Windows account. When password SSH already works, `nxd` can perform this one-time bootstrap:
   ```bash
   nxd wsl bootstrap-ssh -t wsl
   # Or explicitly override defines.nix mySshAuthKey:
   nxd wsl bootstrap-ssh -t wsl --public-key ~/.ssh/workstation.pub
   ```
   By default the command installs the same `mydefs.mySshAuthKey` used by `hosts/minimal-wsl/default.nix`. It prompts through OpenSSH for the Windows password, installs only the public key, applies the Windows administrator-key ACL when required, and verifies key-only access. The password is never passed to or stored by `nxd`.
4. Confirm that the account can run these commands without interaction:
   ```powershell
   wsl.exe --version
   wsl.exe --status
   wsl.exe --list --quiet
   ```
5. Permit inbound OpenSSH in Windows Firewall. For direct mirrored networking, also permit the WSL guest's SSH service through the Hyper-V firewall.

Windows OpenSSH is required for remote provider control. PowerShell alone is not a remote transport.

### Host Metadata

Add the real Windows endpoint to `hosts/wsl/meta.nix`:

```nix
deployment.wsl = {
  enable = true;
  windowsHost = "windows-host.example";
  windowsUser = "windows-user";
  distribution = "NixOS";
  installRoot = ''C:\WSL\NixOS'';
  bootstrapUser = "nixos";
  transport = "auto";
  # Optional stable mirrored-network DNS/IP:
  # guestHost = "nixos-wsl.example";
};
```

The checked-in WSL metadata intentionally leaves this block disabled. WSL lifecycle commands fail closed until the real Windows hostname, account, distribution, and install root are configured.

`transport = "auto"` prefers direct SSH to the guest. If the NAT-mode guest address is not directly reachable, `nxd` uses the Windows OpenSSH endpoint as an SSH jump host. Direct transport routes (such as Tailscale or stable mirrored networking) completely bypass Windows OpenSSH control calls, avoiding connection timeouts or wake-up delays on Windows. Use `transport = "direct"` to require direct guest reachability or `"windows"` to always use the Windows jump host.

### VM Keepalive

WSL 2 automatically shuts down the guest VM when it detects no interactive user shells or running console applications. To prevent background services (such as Tailscale or `sshd`) from losing connectivity, a declarative `wsl-keepalive` systemd service runs `sleep infinity` on the guest to satisfy WSL's activity detection.

If you need to stop the guest VM completely:
1. Temporarily stop the service inside the distribution:
   ```bash
   sudo systemctl stop wsl-keepalive
   ```
2. Or terminate the WSL distribution from the Windows host:
   ```powershell
   wsl.exe --terminate NixOS
   ```

### Deploy And Operate

```bash
# Side-effect-free provider/deployment preview
nxd deploy -t wsl --plan

# Import a missing distribution and converge the final configuration
nxd deploy -t wsl

# Existing distributions are skipped by deploy unless explicitly selected
nxd deploy -t wsl --overwrite

# Unregister, re-import, and converge
nxd deploy -t wsl --redeploy

# Normal steady-state operations
nxd switch -t wsl
nxd info -t wsl
nxd destroy -t wsl --plan
nxd destroy -t wsl
```

On an ARM Mac, the minimal x86_64 WSL artifact and final system can be built through the configured Linux builder, such as `deploy@utils`.

### Offline Artifact And Recovery

Artifact-only mode never connects to Windows:

```bash
nxd build --artifact minimal-wsl
# result-wsl/nixos-wsl-custom.tar.gz
```

Provider deployment reuses an existing nonempty artifact at the configured path. Remove it or run artifact-only build explicitly when a fresh bootstrap image is required.

For manual recovery, transfer the tarball to Windows and import it:

```powershell
wsl.exe --import NixOS C:\WSL\NixOS .\nixos-wsl-custom.tar.gz --version 2
wsl.exe -d NixOS
```

The minimal image is highly optimized (~700-800 MB compressed size) and contains only the approved public SSH key and reusable bootstrap settings. Redundant packages (like full `git` and `vim`) have been replaced with minimal alternatives (`gitMinimal` and `nano`) to reduce the bootstrap footprint. Host secrets and private keys are staged later through the normal host-scoped deployment workspace.

References: [NixOS-WSL](https://github.com/nix-community/NixOS-WSL), [Install OpenSSH on Windows](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse), [WSL commands](https://learn.microsoft.com/en-us/windows/wsl/basic-commands), and [WSL networking](https://learn.microsoft.com/en-us/windows/wsl/networking).
