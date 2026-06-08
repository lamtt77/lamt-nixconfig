# Installer Rust Architecture And Implementation Plan

This document describes how `apps/installer-rs` implements the behavior specified in [Installer Requirements Specification.md](./Installer%20Requirements%20Specification.md). It stays focused on Rust code structure, module ownership, execution strategy, and implementation tradeoffs.

## Package And Entrypoint

The Rust crate remains named `installer-rs`, while the installed user command is `lamd`.

Packaging layout:

- `pkgs/installer-rs/default.nix` builds the Rust package from a cleaned `apps/installer-rs` source tree.
- `apps/installer-rs.nix` exposes the flake app and points it at `${installerPkg}/bin/lamd`.
- Managed systems expose `lamd` through shell aliases that run `nix run ${inputs.self.outPath}#installer-rs --` against the switched flake snapshot.

The package moves the built binary from `installer-rs` to `lamd`, then creates `installer-rs` as a compatibility symlink. The Makefile remains a thin forwarding wrapper around `nix run .#installer-rs --`.

## Crate Layout

Current high-level source layout:

```text
apps/installer-rs/src/
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

  operation/
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
    plan.rs
    plan_iso.rs
    plan_provider.rs
    plan_render.rs
    plan_risk.rs
    plan_spec.rs
    plan_workspace.rs

  executor/
    batch.rs
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
```

Use this ownership model:

- `main.rs` wires CLI parsing, global runtime options, subprocess-facing environment defaults, and command dispatch.
- `command/` owns CLI orchestration and should stay shallow.
- `fleet/` owns host metadata, selector expansion, local-host detection, provider detection, and endpoint/IP resolution.
- `operation/` owns deploy workflow, operation planning, risk classification, confirmation, deploy sub-steps, and Proxmox ISO staging after user confirmation.
- `executor/` owns host and batch execution mechanics, command execution, per-host logs, and result aggregation.
- `progress/` owns status rendering, color policy, and debug formatting.
- `nix/` owns Nix build strategy dispatch, strategy-specific build execution, pure command rendering helpers, evaluation helpers, copy command construction, and remote-builder coordination.
- `remote/` owns reusable SSH and known-host mechanics.
- `workspace/` owns source snapshots, persistent workspaces, remote sync, and host-secret injection.
- `identity/` owns SSH host keys, SOPS/age integration, Tailscale pre-auth validation, and GPG staging.
- `providers/` owns provider lifecycle and IP discovery only.

Avoid reintroducing source modules named `target/`; it is easy to confuse with Rust build output. Keep `progress/` rather than renaming it to `log/` because the module covers visual status, colored levels, host-prefixed batch output, summaries, and future progress indicators.

## Runtime Options

`config::RuntimeOptions` is the internal source of truth for runtime policy:

- debug
- force
- low-memory override
- build strategy override
- builder override
- repo source
- redeploy and overwrite policy
- deploy activity
- host-key and secrets-key update policy

Internal Rust workflow code should read `RuntimeOptions`, not process-wide environment variables such as `CLI_FORCE`, `LOW_MEM`, `BUILD_ON`, `BUILDER`, `DEPLOY_ACTIVE`, or `BATCH_HOSTS`.

Environment variables are still acceptable for compatibility and subprocess behavior, for example:

- `NIX_SSHOPTS` for Nix copy/SSH subprocesses.
- `NIX_REPO` for flake reference compatibility.
- `INSTALLER_RS_DEBUG` for debug compatibility.
- process facts such as `TMPDIR`, `USER`, and provider-specific defaults.

Do not add new process-global environment switches for internal installer policy unless there is a concrete subprocess interoperability requirement.

## Command Routing

`main.rs` parses CLI flags with `clap`, stores runtime options, then routes to command modules.

Routing rules:

- `switch` with neither `--target` nor `--hosts` defaults to the current short hostname.
- `-t/--target` and `--hosts` are mutually exclusive and fail before inventory/context loading.
- Single-target operations stream command output directly to the terminal.
- Batch operations use `executor::batch` and isolated per-host logs.
- Local self-switch targets are detected by hostname or loopback IP and skip remote SSH host-key validation.
- `exec` skips workspace prep, build, provider lifecycle, and secret staging.

The routing layer should select the command and target set, then delegate behavior to command, operation, executor, fleet, provider, workspace, identity, and Nix modules.

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

- `workspace/local.rs`: persistent temp workspace guards, cleanup, Git commit helpers, path sanitization.
- `workspace/source.rs`: local Git snapshots, non-Git rsync snapshots, and remote flake materialization.
- `workspace/secrets.rs`: per-host SOPS file discovery and injection.
- `workspace/remote.rs`: remote workspace representation, rsync sync, and remote Git snapshot commands.

Workspace shapes:

- pure local single-host operation: one host workspace
- remote operation: common source base plus one host workspace
- multi-host operation: one common source base plus isolated per-host workspaces

Local and remote workspaces are persistent cache directories refreshed between runs:

- local: `/private/tmp/installer-rs-workspace-<host>` or platform temp equivalent
- remote target/builder: `/tmp/installer-rs-workspace-<host>`

Secrets must remain scoped to host workspaces. Refresh operations remove stale host-specific secret material before the next run.

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
| Remote builder | Sync a common source base to the builder, derive a host workspace, build there, copy closure to target. |
| Target instantiated | Evaluate derivations off target, copy drv/input paths, realize on target. |
| Target native | Sync source to target and run Nix directly there. |

Attribute routing is OS-aware:

- NixOS toplevel: `nixosConfigurations.<host>.config.system.build.toplevel`
- NixOS Disko: `nixosConfigurations.<host>.config.system.build.diskoScript`
- Darwin system: `darwinConfigurations.<host>.system`

`substituteOnDestination` adds `--substitute-on-destination` to relevant `nix copy` operations. Debug mode logs the exact rendered `nix copy` command once per copy operation.

Remote builder rules:

- If the configured builder resolves to the current host, use a local build.
- Sync the common builder base once per builder per batch run.
- Derive one remote builder host workspace per target.
- Do not build directly inside the stable builder base during automated runs.

Build module rules:

- Keep `NixBuilder::build_attribute(...)` and `NixBuilder::build_system(...)` as the public API for operation and executor code.
- Route all strategy selection through `nix/build.rs`; strategy modules should implement one strategy each.
- Put repeatable command rendering in `build_commands.rs` or `copy.rs` rather than inlining shell strings across strategies.
- Keep command rendering helpers deterministic and covered by unit tests, especially copy target rendering, mounted-store flags, remote-builder commands, and low-memory target realization flags.

## Deploy Workflow

`operation/deploy.rs` implements the single-stage convergence deploy workflow. `executor/host.rs` prepares provider state, resolves the final target IP, and invokes the workflow.

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

Proxmox ISO staging is owned by `operation/plan_iso.rs`:

- `--plan` remains side-effect free.
- Batch and single-host deploys stage ISOs only after destructive-risk confirmation succeeds.
- Expected ISO paths are derived from Proxmox metadata, custom ISO config, `NIXOS_ISO`, and repository defaults.
- The provider implementation only consumes the expected staged ISO path; it does not prompt, build, download, or upload ISOs.

Provider IP resolution uses two different policies:

- Planning and early deploy fallback lookups use non-polling provider resolution to keep planning responsive and avoid hidden waits before confirmation.
- The final post-reboot deploy notice uses polling provider resolution because DHCP, guest-agent, and hypervisor network state can lag after reboot.

## Switch Workflow

Switch behavior is coordinated by `executor/host.rs` using `nix/`, `workspace/`, `remote/`, and `identity/`.

Supported switch paths:

- local Darwin: `darwin-rebuild <action> --flake <prepared-flake-ref>#<host>`
- local NixOS: NixOS rebuild equivalent
- remote NixOS: build according to strategy, copy closure when needed, then apply target profile/action over SSH
- Home Manager: local or remote `home-manager switch` using the prepared workspace

Remote switch should validate/sync target host keys before activation, preserve rollback safety where possible, and keep switch-specific execution in executor/operation code rather than `nix/`.

## Batch Execution And Parallelism

`executor/batch.rs` runs multi-host deploy, switch, and exec operations.

Rules:

- `--parallel <N>` limits host operation fan-out; `0` means unlimited.
- Per-host logs remain isolated.
- Host output is prefixed in batch mode.
- Batch summaries report succeeded and failed counts.
- Provider locks, builder sync locks, and workspace isolation remain authoritative for shared-resource safety.
- Concurrency permits must be released on success, error, and task panic.

Batch code should not duplicate deploy or switch behavior. It prepares workspaces, schedules host operations, collects results, prints useful failure context, and reports summaries.

## Remote Execution

`remote/ssh.rs` owns reusable SSH mechanics through `SshSession` and `SshOptions`. `executor/process.rs` remains the external process boundary for local commands, command recording/mocking in tests, child output capture, and progress-aware logging.

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

Build-time host SOPS injection is owned by `workspace/secrets.rs`, not by identity services. Identity services own target-side credentials and key material.

Host-key safety rules:

- A target hostname mismatch aborts before changing the host unless an explicit deploy-mode override permits the workflow.
- If the secrets repository is missing the local public/private host key but the target has an active host key, interactive runs must ask whether to import the target key, generate a fresh local key, or abort.
- Non-interactive forced runs import a missing target key only when `UPDATE_SECRETS_KEY=yes`; otherwise they fail rather than silently changing secrets.
- Host-key mismatch resolution keeps the existing choices: overwrite target from secrets, update secrets from target, proceed anyway, or abort.
- Public key files written into the secrets repository should be newline-terminated to stay friendly to Git and POSIX tools.

## Provider Implementations

Provider modules implement the lifecycle-focused trait from `providers/mod.rs`:

- `exists`
- `create`
- `destroy`
- `get_ip`

Provider-specific command semantics stay inside provider modules. Generic SSH execution, known-host cleanup, and logging mechanics should stay in shared modules.

Provider notes:

- Proxmox uses `qm` for lifecycle and resolves IPs through guest agent or hypervisor network tables before slower polling/fallbacks.
- Proxmox NixOS ISO path selection and staging are not provider responsibilities; `operation/plan_iso.rs` handles that after confirmation.
- VMware resolves leases from platform-specific DHCP lease locations and keeps VMX generation/parsing inside the VMware module.
- DigitalOcean uses `doctl` and declarative `deployment.digitalocean` metadata.

Providers should produce or locate a reachable target. They should not own installation, switch, workspace, or identity workflow logic.

Callers choose whether IP discovery may poll by using `ProviderIpMode`:

- `NonPolling` for planning and responsive fallback checks.
- `PollUntilReady` for boot/reboot boundaries where waiting for provider or DHCP convergence is expected.

## Nix Packaging Details

The package source should be narrow so unrelated Nix config changes do not force Rust recompilation.

`pkgs/installer-rs/default.nix` uses `lib.cleanSourceWith` over `apps/installer-rs` rather than the whole flake source. It filters local build products such as:

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

Shell installer2 remains useful as a reference for edge-case behavior, but new feature work should land in `apps/installer-rs`.

## Test And Validation Plan

Minimum validation before relying on installer changes:

- `cd apps/installer-rs && cargo fmt --check`
- `cd apps/installer-rs && cargo test`
- `cd apps/installer-rs && cargo clippy --all-targets -- -D warnings`
- `nix build .#installer-rs`
- `lamd switch --help`
- `lamd deploy --hosts <host> --plan`

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

- local Darwin `lamd switch`
- local/remote NixOS `lamd switch -t <host>`
- batch switch with multiple hosts
- batch deploy with missing provider hosts
- batch deploy with existing provider hosts skipped by default
- batch deploy with `--overwrite`
- batch deploy with `--redeploy`
- Proxmox cloud-init verification
- cloud-init `--convert-to`
- low-memory host deploy

Workspace regression checks:

- local single-host switch creates one host workspace and no common base
- remote single-host switch refreshes isolated persistent workspaces
- batch switch with multiple hosts sharing `deploy@utils` syncs the builder base once
- non-Git source checkouts use the rsync snapshot path
- `sync --repo` uses the configured target user and does not use deployment workspaces

## Tiered Integration Testing Strategy

The repository organizes and prepares integration tests across three distinct tiers to separate Nix configurations, orchestrator behaviors, and virtual lifecycle states:

### Tier 1: Static Nix Evaluations (tests/*.nix)
- **Purpose**: Verifies that template substitutions, target profiles (disk configurations, netmasks, gateways), and Nix-level assertions (such as Kea/dnsmasq interface conflicts) evaluate correctly without errors.
- **Location**: Structured under `tests/` named `<feature>-test.nix`.
- **Execution**: Run via `nix-instantiate --eval --strict tests/<name>-test.nix` for lightweight pre-deployment verification.

### Tier 2: Rust Planning & Command Tests (cargo test)
- **Purpose**: Verifies CLI argument parsing, metadata schema deserialization, dynamic IP updates, build strategy selection, and the correct rendering of raw SSH and virtualization command strings.
- **Location**: Native Rust tests (`#[cfg(test)]`) inside the `apps/installer-rs/src` packages.
- **Execution**: Run via `cargo test` in `apps/installer-rs`. Tests are completely stateless and use mocks to simulate command execution without side effects.

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
