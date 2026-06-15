# New Features Coding Plan: `nxd`, WSL Provider, And Orchestration Refactor

This document defines the design and implementation plan for:

1. renaming the Rust orchestrator, package, flake app, and installed command to `nxd`;
2. replacing the current WSL tarball-export special case with a first-class WSL provider;
3. creating a reusable minimal NixOS-WSL bootstrap image;
4. deploying the final WSL host configuration into a Windows machine with WSL enabled; and
5. reducing duplicated command, planning, workspace, and single/batch execution mechanics.

This is a planning document only. It does not authorize implementation until the unresolved
design decisions are reviewed.

---

## 1. Feature Requirements

### 1.1 Rename The Orchestrator To `nxd`

The final public and internal name is `nxd`.

Required rename scope:

- Rust crate and produced binary: `installer-rs` -> `nxd`.
- Source directory: `apps/installer-rs` -> `apps/nxd`.
- Nix package: `pkgs.installer-rs` / `pkgs/installer-rs` -> `pkgs.nxd` / `pkgs/nxd`.
- Flake app: `.#installer-rs` -> `.#nxd`.
- App definition: `apps/installer-rs.nix` -> `apps/nxd.nix`.
- Home Manager feature module: `modules/hm/feat/installer-rs.nix` -> `modules/hm/feat/nxd.nix`.
- Installed command: `lamd` -> `nxd`.
- Internal application/state name: `installer-rs` -> `nxd`.
- Debug environment variable: `INSTALLER_RS_DEBUG` -> `NXD_DEBUG`.
- Log, temporary directory, GC-root, and test prefixes: `installer-rs-*` -> `nxd-*`.
- Documentation, Makefile variables, tests, comments, and examples.

Expected command surface:

```text
nxd switch
nxd switch -t <host>
nxd build -t <host>
nxd test -t <host>
nxd deploy -t <host>
nxd deploy --hosts <selector>
nxd deploy -t <wsl-host> --plan
nix run '.#nxd' -- deploy -t <host>
```

Recommended migration policy:

- Make `nxd` the only documented name immediately.
- Keep `lamd` and the `installer-rs` flake app/package as temporary compatibility aliases for
  one migration window only if existing switched generations, recovery media, or remote
  automation still depend on them.
- Compatibility aliases must call the same `nxd` binary and emit a deprecation warning.
- Remove compatibility aliases in a separately reviewed cleanup after all managed hosts have
  switched to a generation containing `nxd`.

This staged compatibility is safer than an immediate hard cut because an old managed host may
still expose only `lamd` while the repository and documentation already expect `nxd`.

### 1.2 WSL Must Be A Provider

WSL must be selected through declarative deployment metadata and resolved through the same
provider registry used by Proxmox, VMware, and DigitalOcean.

The current top-level `wsl = true` special case must not directly alter generic target-IP
resolution, deployment risk, plan rendering, or host execution. Those behaviors should derive
from the resolved provider and deployment mode.

The WSL provider represents two related systems:

- **Control plane:** a Windows host with WSL installed and enabled.
- **Guest target:** a named NixOS WSL distribution managed by that Windows host.

The provider is responsible for the WSL distribution lifecycle:

- detect whether the requested distribution exists;
- import a bootstrap rootfs when it is missing;
- unregister it for explicit redeploy/destroy;
- start it and wait for the guest management endpoint;
- return a target endpoint suitable for the shared NixOS switch/convergence workflow.

The provider must not own:

- Nix source snapshot preparation;
- SOPS store input preparation;
- final NixOS system builds;
- generic switch activation;
- generic SSH command execution;
- host identity policy.

### 1.3 Minimal WSL Bootstrap Image

Add a non-host bootstrap configuration comparable to `hosts/minimal-iso/default.nix`.

The implementation must use the official
[NixOS-WSL](https://github.com/nix-community/NixOS-WSL) module and tarball builder already
provided by the pinned `nixos-wsl` flake input. It must not create a parallel rootfs builder.

The repository currently pins NixOS-WSL revision
`3e6d8af994e2a2d31af7a91863d7c0d6e278d951`. Its module exposes:

```text
config.system.build.tarballBuilder
```

The upstream builder:

- creates an isolated temporary root;
- installs `config.system.build.toplevel` into that root with `nixos-install`;
- adds WSL distribution metadata and the NixOS-WSL icon;
- writes or copies the initial `/etc/nixos/configuration.nix`;
- creates a deterministic compressed tar archive suitable for WSL import;
- performs rootfs cleanup through an exit trap.

Therefore, `minimal-wsl` is close to the official NixOS-WSL image by design. Our work is a
configuration layer on top of the upstream image mechanism, not a fork of its image-building
logic.

Proposed location:

```text
hosts/minimal-wsl/default.nix
```

Proposed flake output:

```text
nixosConfigurations.minimal-wsl-x86.config.system.build.tarballBuilder
```

Required artifact:

```text
result-wsl/nixos-wsl-custom.tar.gz
```

`nxd` should pass the requested output filename to the upstream
`nixos-wsl-tarball-builder`. Upstream may use a `.wsl` default filename in newer revisions, but
the payload remains an importable compressed rootfs archive. Our explicit `.tar.gz` filename is
kept for the requested operator workflow unless testing identifies a Windows integration reason
to adopt `.wsl`.

The bootstrap image should contain only the facilities required to make the imported
distribution manageable and ready for final convergence:

- Nix with flakes enabled;
- systemd support required by NixOS-WSL;
- OpenSSH server or another explicitly selected management transport;
- the configured bootstrap public SSH key for the bootstrap account;
- trusted host keys for required source remotes;
- Git, rsync, jq, and basic diagnostics;
- configured binary caches and trusted public keys;
- a predictable bootstrap user and privilege model;
- WSL interoperability needed to discover/control the Windows host when applicable.

The bootstrap image must not contain:

- private SSH keys;
- decrypted secrets;
- host-specific SOPS material;
- final host identity keys;
- a final production host configuration;
- credentials embedded through command-line arguments or build logs.

The public key may be sourced from repository policy such as `defines.nix`, following the
existing minimal ISO pattern. Secret material remains runtime-staged.

Our customizations should be expressed through normal NixOS options in
`hosts/minimal-wsl/default.nix`, including:

- `wsl.enable = true`;
- the bootstrap default user;
- OpenSSH and the approved public authorized key;
- Nix flakes and cache settings;
- bootstrap packages and diagnostics;
- `/etc/wsl.conf` or NixOS-WSL options required for systemd, user selection, and networking;
- optional initial configuration copied through the upstream `wsl.tarball.configPath` facility
  when required by the pinned NixOS-WSL revision.

Do not copy the upstream `build-tarball.nix` into this repository. Upstream changes should be
consumed by updating the pinned flake input and adjusting our configuration only where its public
module interface changes.

### 1.4 WSL Deployment Flow

The intended operator flow is:

```text
nxd deploy -t <wsl-host> --plan
nxd deploy -t <wsl-host>
nxd switch -t <wsl-host>
nxd destroy -t <wsl-host>
nxd build --artifact minimal-wsl
```

`nxd build --artifact minimal-wsl` is the required offline/manual recovery path. It builds the
bootstrap tarball without resolving, connecting to, or mutating a Windows target.

Expected behavior:

- `--artifact minimal-wsl` is mutually exclusive with `--target`, `--hosts`, and `--hm`.
- The default output is `result-wsl/nixos-wsl-custom.tar.gz`.
- `--output <path>` may override the result path.
- The command uses the normal local/remote builder strategy and immutable source workspace.
- The tarball builder script must execute on a compatible Linux machine. Building from Darwin
  should select a configured Linux builder rather than execute a cross-built Linux script
  locally.
- The completed artifact remains usable for a manual Windows import:

  ```powershell
  wsl.exe --import NixOS C:\WSL\NixOS .\nixos-wsl-custom.tar.gz --version 2
  ```

- The command prints the artifact path and digest, but performs no SCP, PowerShell, provider,
  endpoint, or guest activation work.

This explicit artifact mode is preferable to overloading `nxd build -t <wsl-host>`:

- target builds continue to mean "build the final selected host configuration";
- bootstrap images remain non-host reusable artifacts;
- the same artifact interface can later support `minimal-iso-x86`,
  `minimal-iso-aarch64`, and recovery images without provider-specific commands.

Proposed state transition:

1. Load the final WSL host metadata.
2. Resolve the WSL provider and Windows control endpoint.
3. Query whether the requested WSL distribution exists.
4. Build or locate the reusable minimal WSL bootstrap tarball.
5. Transfer the bootstrap tarball to the Windows host when required.
6. Import the distribution with `wsl.exe --import`.
7. Start the distribution and wait for its management endpoint.
8. Prepare the immutable source and host-secret store inputs.
9. Build the final WSL host `config.system.build.toplevel` through the normal build strategy.
10. Copy the closure to the WSL guest.
11. Register and activate the final system profile using a WSL-specific convergence operation.
12. Validate reachability and report the final distribution and endpoint.
13. Archive the successful source lockfile through the common post-success lifecycle.

WSL deployment must skip bare-metal-only stages:

- provider VM disk creation;
- kexec takeover;
- Disko partitioning;
- `nixos-install`;
- physical swap creation;
- hardware reboot polling.

It must not skip shared stages merely because it is WSL:

- source/workspace preparation;
- build strategy resolution;
- final system build;
- final system profile activation;
- host-secret input isolation;
- success cleanup;
- lockfile archival;
- plan and result reporting.

### 1.5 Windows Control Transport

The provider needs a supported way to invoke PowerShell and `wsl.exe` on the Windows host.

Accepted phase 1 design:

- Windows OpenSSH Server is a required prerequisite for remote `nxd deploy`, `switch`, `info`,
  and `destroy` operations.
- PowerShell alone is sufficient only when commands are run locally on Windows; it is not a
  remote transport.
- Metadata supplies the Windows SSH endpoint and user.
- `nxd` invokes non-interactive PowerShell commands through the existing SSH process boundary.
- WSL guest SSH uses a separately resolved Linux endpoint.

The Windows account must:

- accept public-key SSH authentication from the orchestrator;
- be able to run non-interactive PowerShell;
- be the Windows user that owns or can manage the configured WSL distribution;
- have permission to create the configured install directory;
- have any elevation required for firewall or port-forward fallback configured without an
  interactive password prompt.

Provider preflight must fail with an actionable error if:

- the Windows SSH endpoint is unreachable;
- public-key authentication fails;
- PowerShell cannot be invoked non-interactively;
- `wsl.exe` is unavailable;
- the installed WSL version does not support the required lifecycle commands;
- the Windows user cannot query or manage the configured distribution.

Example conceptual metadata:

```nix
deployment.wsl = {
  windowsHost = "windows-host.example";
  windowsUser = "deploy";
  distribution = "NixOS";
  installRoot = ''C:\WSL\NixOS'';
  bootstrapUser = "nixos";
  transport = "ssh-powershell";
};
```

Do not use a Linux-style `targetIp` placeholder for WSL. Model the Windows control endpoint and
the WSL guest endpoint as distinct typed data.

Performance and reliability assessment:

1. **Direct SSH to the WSL guest with mirrored networking is the preferred steady-state path.**
   It gives `nix copy`, SSH activation, probes, and logs a direct connection to Linux without
   relaying every operation through a Windows PowerShell process. Microsoft documents that
   mirrored networking supports direct LAN access to WSL and improves VPN/network compatibility
   on supported Windows 11 systems.
2. **Windows-mediated `wsl.exe -d <distribution> -- <command>` is the preferred bootstrap and
   recovery path.** It does not require a known guest IP and is suitable for starting the
   distribution, checking readiness, discovering addresses, and repairing guest SSH. It is not
   the preferred bulk data path because each operation is relayed through Windows SSH,
   PowerShell, and `wsl.exe`, and it does not directly provide the normal Nix SSH store
   transport.
3. **Windows OpenSSH jump-host routing is the implemented fallback for WSL systems using default
   NAT networking.** `nxd` resolves the guest address through `wsl.exe` and routes SSH and Nix
   store-copy traffic through the Windows control host. This avoids mutable `portproxy` state and
   a separate port-aware target model. Explicit Windows port forwarding remains a possible
   future operator-managed option, not phase 1 behavior.

Phase 1 recommendation:

- require Windows OpenSSH for the provider control plane;
- use Windows-mediated `wsl.exe` commands to import and start the distribution;
- prefer direct guest SSH when mirrored networking and the Hyper-V firewall permit it;
- fall back to the Windows OpenSSH control host as a jump host when direct guest SSH is
  unavailable;
- retain Windows-mediated guest execution as a last-resort bootstrap/repair channel, not the
  normal convergence transport.

This hybrid model gives the best steady-state performance while preserving deterministic
bootstrap access before the guest endpoint is known.

Platform references:

- [Microsoft WSL networking documentation](https://learn.microsoft.com/en-us/windows/wsl/networking)
- [Microsoft WSL command documentation](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
- [Microsoft OpenSSH for Windows documentation](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)

### 1.6 Planning And Safety

`--plan` must remain side-effect free.

A WSL plan should report:

- provider: WSL;
- Windows control host;
- distribution name;
- distribution install root;
- current provider state: missing, present, running, or unavailable;
- bootstrap artifact source: existing, local build, or remote builder;
- intended action: create, skip, overwrite/converge, redeploy, or destroy;
- build strategy for the final host;
- whether guest SSH or Windows-mediated execution is expected;
- risk level.

Recommended policy:

- missing distribution: create and converge;
- existing distribution: skip by default for `deploy`, matching other providers;
- `--overwrite`: keep the distribution and converge the final configuration;
- `--redeploy`: unregister, re-import bootstrap image, and converge;
- `destroy`: unregister the named distribution after confirmation.

The provider must validate that its distribution and install-root values are safe before
rendering PowerShell commands. Distribution names, Windows paths, SSH endpoints, and usernames
must be escaped through structured command helpers.

---

## 2. Technical Design

### 2.1 Current Architecture Assessment

The current top-level directory categories are generally valid:

- `command/` should own CLI-level orchestration.
- `operation/` should own reusable domain workflows.
- `executor/` should own execution scheduling and process boundaries.
- `fleet/` should own inventory, selectors, metadata, and endpoint resolution.
- `providers/` should own external provider lifecycle.

The main issue is not the existence of these folders. It is that their current boundaries are
not consistently enforced.

Confirmed overlap and duplication:

1. `command/deploy.rs` separately implements batch and single-target planning, confirmation,
   source preparation, remote-builder transfer, workspace construction, execution, and cleanup.
2. `command/switch.rs` repeats the same mechanics for switch/build/test/boot.
3. `executor/batch.rs` repeats workspace preparation and host execution for deploy and switch.
4. Both deploy command planning helpers query providers and build `PlanHostOptions` more than
   once for the same hosts.
5. `executor/host.rs` contains both lifecycle coordination and large operation-specific switch
   and WSL implementations.
6. Provider detection is split between `fleet/resolution.rs` and the separate positional
   `provider_kind(...)` logic in `operation/plan_provider.rs`.
7. The current WSL implementation bypasses common post-success behavior through an early return
   and duplicates Nix build mechanics instead of using the public build dispatcher.
8. `main.rs` exposes aliases (`pipeline`, `plan`, `runner`, and `batch`) that obscure actual
   ownership and make cross-layer calls harder to follow.

Areas that should remain separate:

- `fleet/` is not redundant with `executor/`. Fleet describes targets; executor runs work.
- `command/` is not redundant with `operation/`. Command parses operator intent; operation
  implements domain behavior.
- root `process.rs` is the shared command-execution boundary and must not move into provider
  modules.
- `nix/`, `workspace/`, `identity/`, `remote/`, and `progress/` have coherent responsibilities.

### 2.2 Recommended Source Layout

Proposed high-level layout after the rename and refactor:

```text
apps/nxd/src/
  main.rs
  cli.rs
  config.rs

  command/
    deploy.rs
    switch.rs
    destroy.rs
    exec.rs
    info.rs
    sync.rs

  fleet/
    context.rs
    metadata.rs
    selectors.rs
    local.rs
    resolution.rs

  planning/
    mod.rs
    render.rs
    risk.rs
    spec.rs

  workflow/
    deploy/
      mod.rs
      bare_metal.rs
      cloud_init.rs
      wsl.rs
    switch.rs
    convergence.rs
    lockfile.rs

  execution/
    coordinator.rs
    host.rs
    batch.rs
  process.rs

  providers/
    mod.rs
    registry.rs
    capabilities.rs
    proxmox/
    vmware/
    digitalocean.rs
    wsl/
      mod.rs
      commands.rs
      artifact.rs
      endpoint.rs

  nix/
  workspace/
  identity/
  remote/
  progress/
```

This is a target ownership model, not a requirement to move every file at once. The refactor
should be incremental and compile after each phase.

Naming recommendation:

- Keep the `fleet/` name. It already describes host inventory, selector expansion, local-host
  detection, provider resolution, and endpoint resolution clearly enough.
- Rename `operation/` to `workflow/` because it currently contains long-running workflows,
  planning, and operation substeps. If planning becomes its own module, `workflow/` is clearer.
- Rename `executor/` to `execution/` only as part of the same atomic source move; otherwise keep
  `executor/` and add the coordinator there.

The important change is ownership and shared APIs, not directory churn.

### 2.3 Shared Operation Coordinator

Introduce a typed request that represents one CLI invocation:

```rust
struct OperationRequest {
    kind: OperationKind,
    targets: TargetSelection,
    policy: OperationPolicy,
    execution: ExecutionPolicy,
}
```

Conceptual supporting types:

```rust
enum OperationKind {
    Deploy,
    Switch(SwitchAction),
    Destroy,
}

enum TargetSelection {
    DefaultLocal,
    Single(String),
    Selectors(String),
}

struct OperationPolicy {
    force: bool,
    overwrite: bool,
    redeploy: bool,
    convert_to: Option<String>,
    home_manager: bool,
}

struct ExecutionPolicy {
    plan_only: bool,
    parallelism: usize,
}
```

The coordinator should own the mechanics currently duplicated across command and batch code:

1. validate and expand target selection;
2. load contexts once;
3. resolve provider snapshots once;
4. build typed host plans once;
5. render plans;
6. stop for `--plan`;
7. confirm;
8. prepare one source set;
9. calculate and pre-transfer shared store destinations;
10. create per-host workspaces;
11. execute sequentially or concurrently through one host operation API;
12. collect results and print summaries;
13. clean local and remote GC roots;
14. archive lockfiles after successful eligible operations.

`command/deploy.rs` and `command/switch.rs` should become thin adapters that construct an
`OperationRequest`. `executor/batch.rs` should schedule generic prepared host jobs rather than
contain separate deploy and switch workflows.

### 2.4 Provider Model

The current `VirtualizationProvider` trait is too narrow and too VM-specific for WSL.

Replace it with a provider interface that separates:

- identity and display metadata;
- state inspection;
- lifecycle changes;
- endpoint discovery;
- provider capabilities.

Conceptual API:

```rust
trait Provider {
    fn kind(&self) -> ProviderKind;
    fn capabilities(&self) -> ProviderCapabilities;
    fn inspect(&self) -> Result<ProviderState, ProviderError>;
    fn create(&self, input: &ProviderCreateInput) -> Result<ProviderState, ProviderError>;
    fn destroy(&self) -> Result<(), ProviderError>;
    fn endpoint(&self, mode: EndpointMode) -> Result<TargetEndpoint, ProviderError>;
}
```

Conceptual capability and state types:

```rust
struct ProviderCapabilities {
    supports_create: bool,
    supports_destroy: bool,
    has_control_host: bool,
    requires_bootstrap_artifact: bool,
    supports_ip_discovery: bool,
}

enum ProviderState {
    Missing,
    Present,
    Running,
    Unreachable { reason: String },
}

enum TargetEndpoint {
    Ssh { user: String, host: String },
    WindowsMediatedWsl {
        windows_ssh: String,
        distribution: String,
        linux_user: String,
    },
}
```

Do not add optional no-op methods for every provider-specific behavior. Put WSL bootstrap
artifact preparation in the WSL workflow/provider input and keep the generic provider contract
focused on lifecycle and endpoint production.

Provider resolution should return a single typed object/snapshot used by planning and execution.
Remove the parallel positional `provider_kind(...)` inference path.

### 2.5 WSL Metadata

Move WSL provider settings under `deployment.wsl`.

Proposed Nix option schema:

```nix
deployment.wsl = {
  enable = lib.mkEnableOption "WSL provider deployment";

  windowsHost = lib.mkOption {
    type = lib.types.str;
    default = "";
  };

  windowsUser = lib.mkOption {
    type = lib.types.str;
    default = "";
  };

  distribution = lib.mkOption {
    type = lib.types.str;
    default = "";
  };

  installRoot = lib.mkOption {
    type = lib.types.str;
    default = "";
  };

  bootstrapUser = lib.mkOption {
    type = lib.types.str;
    default = "nixos";
  };

  transport = lib.mkOption {
    type = lib.types.enum [ "ssh-powershell" ];
    default = "ssh-powershell";
  };
};
```

The top-level host `wsl` boolean may remain a Nix system-construction fact because
`lib/systems.nix` needs it to include the NixOS-WSL module. Rust provider selection, however,
should use `deployment.wsl.enable` rather than a generic boolean special case.

Validation rules:

- WSL provider requires `system = "x86_64-linux"` until another image is explicitly supported.
- `windowsHost`, `windowsUser`, `distribution`, and `installRoot` are required when enabled.
- WSL provider metadata must not coexist with Proxmox, VMware, or DigitalOcean provider
  metadata for the same host.
- `hasDisko` must be false for WSL targets.
- Windows install roots must be absolute Windows paths and reject shell metacharacters not
  handled by the PowerShell argument renderer.

### 2.6 Bootstrap Artifact Ownership

The minimal WSL rootfs is analogous to the minimal ISO but should not be built inside the
provider's `create()` method through ad hoc shell commands.

The artifact layer orchestrates the official NixOS-WSL builder; it does not implement tarball
contents or rootfs assembly. Its build target is:

```text
nixosConfigurations.minimal-wsl-x86.config.system.build.tarballBuilder
```

The resulting store path contains `bin/nixos-wsl-tarball-builder`. `nxd` runs that builder on a
compatible Linux machine and supplies the requested output path. Rootfs installation,
WSL-specific metadata, deterministic tar creation, and builder-internal cleanup remain owned by
NixOS-WSL.

Introduce a reusable artifact preparation layer:

```text
workflow/artifact.rs
workflow/artifact.rs
```

Responsibilities:

- select the correct flake attribute;
- resolve local or remote builder strategy;
- build the upstream NixOS-WSL tarball builder derivation;
- execute the upstream builder on a compatible Linux machine;
- copy the resulting tarball to the orchestrator or directly to the Windows control host;
- use unique run-scoped temporary paths;
- return a typed `PreparedArtifact`;
- clean temporary output on success and failure.

Conceptual type:

```rust
struct PreparedArtifact {
    local_path: Option<PathBuf>,
    remote_path: Option<RemotePath>,
    digest: String,
}
```

The artifact builder must not treat a cross-built Linux script as locally executable on Darwin.
The tarball builder must execute on a compatible Linux machine. A remote Linux builder is the
preferred path from macOS.

### 2.7 WSL Convergence Workflow

Create a WSL-specific deployment workflow rather than branching inside the bare-metal pipeline.

The workflow should reuse a shared NixOS convergence helper also used by remote switch:

```rust
fn converge_nixos_profile(
    ctx: &RuntimeContext,
    endpoint: &TargetEndpoint,
    action: SwitchAction,
    logger: Logger,
) -> Result<ConvergenceResult, Error>
```

Shared convergence responsibilities:

- build final toplevel through `NixBuilder`;
- ensure the closure is available to the target;
- compare current profile when supported;
- set `/nix/var/nix/profiles/system`;
- run `switch-to-configuration`;
- respect `--force`;
- report the resulting store path.

WSL-specific preparation before convergence:

- import/start the distribution;
- ensure systemd and SSH are ready;
- resolve the guest endpoint;
- validate bootstrap hostname rules without treating the generic bootstrap name as a mismatch;
- stage final WSL host identity where required.

Do not call `nixos-install` for WSL.

### 2.8 Command Rendering And Security

Add pure, unit-tested renderers for:

- PowerShell `wsl.exe --list --quiet`;
- `wsl.exe --import`;
- `wsl.exe --unregister`;
- `wsl.exe -d <name> -- <command>`;
- Windows directory creation/removal;
- tarball checksum verification;
- remote temporary path generation;
- endpoint probe commands.

Never construct these commands by interpolating unvalidated metadata directly into a shell
string. Use argument vectors where possible and one PowerShell escaping helper where remote SSH
requires a command string.

Do not print:

- private keys;
- SOPS contents;
- PowerShell stdin containing secrets;
- tar payloads;
- remote command lines containing access tokens.

### Module Modifications & New Files

Rename-related paths:

- `apps/installer-rs/` -> `apps/nxd/`: Rust crate and source.
- `pkgs/installer-rs/` -> `pkgs/nxd/`: Nix package.
- `apps/installer-rs.nix` -> `apps/nxd.nix`: flake app.
- `modules/hm/feat/installer-rs.nix` -> `modules/hm/feat/nxd.nix`: installed package.

Nix and metadata:

- `hosts/minimal-wsl/default.nix`: reusable bootstrap WSL image.
- `flake/hosts.nix`: expose minimal WSL configuration and WSL provider metadata.
- `modules/shared/options.nix`: add typed `deployment.wsl` options.
- `hosts/<wsl-host>/meta.nix`: configure Windows control host and distribution.
- `lib/systems.nix`: continue including NixOS-WSL modules for final WSL system configs.

Rust architecture:

- `src/providers/capabilities.rs`: typed capabilities and provider state.
- `src/providers/registry.rs`: single provider selection path.
- `src/providers/wsl/mod.rs`: WSL provider lifecycle.
- `src/providers/wsl/commands.rs`: pure PowerShell/WSL command rendering.
- `src/workflow/artifact.rs`: reusable bootstrap artifact build and remote-builder support.
- `src/providers/wsl/mod.rs`: artifact transfer/import, guest startup, and endpoint discovery.
- `src/execution/coordinator.rs`: shared plan/confirm/prepare/run/cleanup orchestration.
- `src/execution/batch.rs`: generic job scheduling and aggregation only.
- `src/execution/host.rs`: dispatch prepared jobs to workflows.
- `src/execution/host.rs`: provider-capability-driven WSL deployment and shared convergence.
- `src/workflow/convergence.rs`: shared final NixOS profile activation.
- `src/planning/`: provider-aware plan, risk, and rendering.

Existing modules to simplify:

- `src/command/deploy.rs`: construct request and delegate.
- `src/command/switch.rs`: construct request and delegate.
- `src/fleet/resolution.rs`: remove WSL target placeholder behavior.
- Remove the old duplicate plan-provider inference module; consume provider snapshots from the
  provider registry.
- `src/execution/host.rs`: remove inline WSL tarball implementation and consume typed endpoints.
- `src/nix/build.rs`: remain the only public build strategy dispatcher.
- `src/workspace/source.rs`: expose shared destination planning without command-specific loops.
- `src/main.rs`: remove ownership-obscuring re-export aliases.

---

## 3. Implementation Tasks Checklist

- [x] **Phase 1: Design Decisions And Safety Contract**
  - [x] Use temporary `lamd` and `.#installer-rs` compatibility aliases for one migration
        window.
  - [x] Require Windows OpenSSH Server with public-key authentication as the phase 1 control
        transport; use non-interactive PowerShell behind SSH.
  - [x] Use the hybrid WSL endpoint strategy: direct mirrored-network SSH, Windows OpenSSH
        jump-host fallback, and Windows-mediated bootstrap/repair.
  - [x] Skip existing distributions by default, use `--overwrite` for convergence, and use
        `--redeploy` for unregister/import/converge.
  - [x] Define typed provider state, endpoint, and capability structures; retain source command
        context in provider errors.
  - [x] Define `deployment.wsl` schema and validation.
  - [x] Define bootstrap image contents and secret exclusions.
  - [x] Review against architecture and security guidelines.

- [x] **Phase 2: Atomic `nxd` Rename**
  - [x] Rename crate, source directory, package directory, app file, and Home Manager module.
  - [x] Rename flake app/package/overlay attributes to `nxd`.
  - [x] Rename installed command and completions command to `nxd`.
  - [x] Rename application state, log, temporary directory, and GC-root prefixes.
  - [x] Rename debug environment variable to `NXD_DEBUG`.
  - [x] Update Makefile fallback to `nix run '.#nxd' --`.
  - [x] Update recovery image references and integration tests.
  - [x] Add temporary compatibility aliases only if approved in Phase 1.
  - [x] Update active documentation; do not rewrite archived historical documents unless needed
        to prevent executable stale instructions.

- [x] **Phase 3: Shared Orchestration Refactor**
  - [x] Introduce typed operation request and execution policy.
  - [x] Load and resolve target contexts once per command.
  - [x] Resolve provider snapshots once per planning cycle.
  - [x] Build and render host plans once.
  - [x] Centralize plan-only exit and confirmation.
  - [x] Centralize source-set preparation and transfer destination calculation.
  - [x] Centralize per-host workspace creation.
  - [x] Replace deploy/switch-specific batch methods with generic prepared job scheduling.
  - [x] Centralize GC-root cleanup and lockfile archival.
  - [x] Keep command modules as thin CLI adapters.
  - [x] Remove root-level `pipeline`, `plan`, `batch`, and `runner` re-export aliases.
  - [x] Move the generic process runner out of `executor/`; executor now owns scheduling and
        per-host execution only.

- [x] **Phase 4: Provider Contract Refactor**
  - [x] Replace `VirtualizationProvider` with provider lifecycle/state/endpoint abstractions.
  - [x] Add a provider registry with one selection path.
  - [x] Adapt Proxmox, VMware, and DigitalOcean without behavior changes.
  - [x] Remove duplicate provider-kind inference.
  - [x] Add capability-aware planning and risk rendering.
  - [x] Keep provider state inspection non-polling during plan operations.

- [x] **Phase 5: Minimal WSL Bootstrap Image**
  - [x] Add `hosts/minimal-wsl/default.nix`.
  - [x] Import `inputs.nixos-wsl.nixosModules.wsl`; do not add a custom rootfs/tar builder.
  - [x] Configure NixOS-WSL, systemd, bootstrap user, SSH, Nix, caches, and required tools.
  - [x] Disable bootstrap-only documentation, channels, registry, and NIX_PATH closure inputs.
  - [x] Add only the approved public SSH key.
  - [x] Expose the minimal WSL flake configuration.
  - [x] Build through `config.system.build.tarballBuilder`.
  - [x] Verify the pinned NixOS-WSL builder interface, including `wsl.tarball.configPath`.
  - [x] Add `nxd build --artifact minimal-wsl [--output <path>]`.
  - [x] Ensure artifact-only builds perform no Windows/provider connection or mutation.
  - [x] Print the completed artifact path and digest for manual transfer/import.
  - [x] Verify no host secrets or private keys enter the closure.
  - [x] Document manual import and bootstrap troubleshooting.

- [x] **Phase 6: WSL Provider**
  - [x] Add typed WSL metadata to Nix and Rust.
  - [x] Implement WSL provider detection in the registry.
  - [x] Add Windows preflight checks for SSH public-key authentication, non-interactive
        PowerShell, `wsl.exe`, supported WSL version, distribution access, and install-root
        permissions.
  - [x] Implement side-effect-free provider inspection.
  - [x] Implement bootstrap artifact selection/build.
  - [x] Implement transfer to Windows and checksum verification.
  - [x] Implement import, start, endpoint discovery, and destroy/unregister.
  - [x] Use unique run-scoped remote paths and cleanup on checksum/import completion or failure.
  - [x] Add PowerShell and WSL command renderers with escaping tests.
  - [x] Add one-time `nxd wsl bootstrap-ssh` automation for operators who already have Windows
        password SSH access. Default to `defines.nix` `mySshAuthKey`, matching the minimal WSL
        image, while allowing an explicit public-key file override; keep normal provider
        operations strictly public-key-only.

- [x] **Phase 7: WSL Final Convergence**
  - [x] Extract shared NixOS profile convergence from the current switch implementation.
  - [x] Implement WSL deploy workflow without Disko, kexec, `nixos-install`, or reboot.
  - [x] Reuse normal source, secret, build, copy, activation, and lockfile paths.
  - [x] Support `nxd switch -t <wsl-host>` after initial import.
  - [x] Define host-key behavior for first import and subsequent switches.
  - [x] Ensure `--force` activation semantics match normal NixOS switches.

- [x] **Phase 8: Cleanup And Documentation**
  - [x] Remove the current inline `run_wsl_deployment`.
  - [x] Remove WSL target-IP placeholders and WSL-specific generic risk branches.
  - [x] Remove obsolete tarball-only README instructions.
  - [x] Replace the README WSL section with a complete operator guide covering:
        Windows WSL 2 and OpenSSH Server prerequisites; public-key authorization; Windows
        account permissions; `deployment.wsl` metadata; mirrored networking and firewall
        setup; NAT jump-host fallback; offline `nxd build --artifact minimal-wsl`; manual
        tarball transfer/import; normal `nxd deploy`, `switch`, `info`, and `destroy` examples;
        `--overwrite`/`--redeploy` behavior; and bootstrap/recovery troubleshooting.
  - [x] Link the README guide to the official Microsoft WSL/OpenSSH documentation and the
        upstream NixOS-WSL project.
  - [x] Update `docs/Installer Requirements Specification.md`.
  - [x] Update `docs/Installer Rust Architecture and Implementation Plan.md`, including its
        filename if the final documentation naming is changed to `nxd`.
  - [x] Update repository agent instructions and build/test commands.
  - [x] Run formatter, lints, tests, and Nix validation.
  - [x] Replace duplicate deploy/switch batch runners with one prepared-host job scheduler.
  - [x] Remove duplicate planning provider inference and consume inspected provider snapshots.
  - [x] Remove duplicate source transfers between coordinator and batch execution.

---

## 4. Verification & Testing Checklist

- [x] **Rename Verification**
  - [x] `cargo metadata` reports package `nxd`.
  - [x] `nix build .#nxd` succeeds.
  - [x] `nix run '.#nxd' -- --help` reports command `nxd`.
  - [x] Shell completions generate for `nxd`.
  - [x] No active code or documentation depends on `lamd`, `installer-rs`,
        `INSTALLER_RS_DEBUG`, or old state prefixes except approved compatibility aliases.

- [x] **Unit Tests**
  - [x] Provider registry selects exactly one provider.
  - [x] Conflicting provider metadata fails validation.
  - [x] WSL metadata deserializes and validates.
  - [x] Windows control preflight reports distinct SSH, authentication, PowerShell, WSL,
        permission, and unsupported-version failures.
  - [x] WSL provider state maps missing/present/running and propagates inspection errors.
  - [x] PowerShell and `wsl.exe` command rendering safely escapes all fields.
  - [x] WSL plans perform inspection only and do not build, transfer, import, or unregister.
  - [x] Default deploy, overwrite, redeploy, and destroy policies render correctly.
  - [x] Artifact strategy rejects locally executed incompatible Linux builder scripts.
  - [x] Unique temporary paths do not collide across concurrent jobs.
  - [x] Cleanup executes after transfer, import, workspace, or convergence failures.
  - [x] Common post-success lockfile archival includes WSL deployments.
  - [x] Shared coordinator produces the same prepared-host job shape for single and batch behavior.

- [x] **Rust Verification**
  - [x] `cd apps/nxd && cargo fmt --check`
  - [x] `cd apps/nxd && cargo test`
  - [x] `cd apps/nxd && cargo clippy --all-targets -- -D warnings`

- [ ] **Nix Verification**
  - [x] `nix fmt -- --ci` repository formatting verification.

  - [x] Evaluate `deploymentHosts.<wsl-host>`.
  - [x] Evaluate the full final `nixosConfigurations.<wsl-host>`.
  - [x] Evaluate the minimal WSL bootstrap configuration.
  - [x] Confirm the minimal image uses the pinned NixOS-WSL module and upstream
        `system.build.tarballBuilder`.
  - [x] Build the minimal WSL tarball on an x86_64 Linux builder.
  - [ ] Import the produced `.tar.gz` with `wsl.exe --import`.
  - [x] Inspect the artifact for project host secrets and private-key paths.
  - [x] Build `.#nxd` on the current supported macOS orchestrator.

- [x] **Plan Verification**
  - [x] `nxd build --artifact minimal-wsl` works while the Windows host is offline.
  - [x] Artifact-only build rejects `--target`, `--hosts`, and `--hm`.
  - [x] Missing WSL distribution plan shows create/import/converge.
  - [x] Existing WSL distribution plan shows skip by default.
  - [x] `--overwrite` plan shows in-place convergence.
  - [x] `--redeploy` plan shows unregister/import/converge.
  - [x] Destroy plan shows the exact provider resource identity without performing destruction.
  - [x] Planning does not build or transfer the bootstrap image.

- [ ] **Integration Verification**
  - [ ] Import the bootstrap image into a disposable Windows/WSL test environment.
  - [ ] Confirm the configured public key permits non-interactive bootstrap access.
  - [ ] Deploy the final WSL host configuration.
  - [ ] Run a second `nxd switch` and confirm idempotent convergence.
  - [ ] Confirm `--force` performs activation even when the generation is unchanged.
  - [ ] Confirm `--redeploy` removes and recreates only the named distribution.
  - [ ] Confirm `destroy` unregisters only the named distribution and preserves unrelated WSL
        distributions.
  - [ ] Confirm interrupted transfer/import does not leave reusable partial artifacts.
  - [ ] Confirm concurrent deployments use isolated local and remote paths.

---

## 5. Test Coverage

Prioritize pure tests around planning, provider selection, command construction, and orchestration.

Required coverage groups:

- rename and packaging smoke tests;
- provider registry and conflict validation;
- WSL metadata parsing;
- WSL state inspection parsing;
- PowerShell escaping;
- import/unregister/start command rendering;
- bootstrap artifact build-location selection;
- source/workspace destination planning;
- common operation coordinator single/batch parity;
- provider policy for missing/existing/overwrite/redeploy states;
- WSL convergence command generation;
- cleanup and lockfile finalization on success and failure.

Use command recording/mocks for Rust tests. Do not invoke a real Windows host from unit tests.
Keep real WSL lifecycle testing in an explicitly configured integration environment.

---

## 6. Approved Implementation Decisions

Implementation proceeds with these approved defaults:

1. Keep temporary `lamd` and `.#installer-rs` compatibility aliases for one migration window.
2. Require Windows OpenSSH Server with public-key authentication. Run explicit non-interactive
   PowerShell commands through that SSH connection.
3. Use Windows-mediated commands for bootstrap and repair, then prefer direct guest SSH through
   mirrored networking, with the Windows OpenSSH control host as the NAT-mode jump host.
4. Keep deployment bootstrap artifacts on the selected producer and transfer them directly to
   Windows. For the normal macOS workflow this is `deploy@utils -> Windows`; the orchestrator
   must not relay or retain the deployment tarball. Direct-transfer failures are fatal and must
   report actionable builder-to-Windows SSH diagnostics. Local artifact output remains exclusive
   to the offline/manual `nxd build --artifact minimal-wsl` workflow.
5. Use one WSL distribution per final Nix host.
6. Skip existing distributions by default. Use `--overwrite` for in-place convergence and
   `--redeploy` for unregister/import/converge.
7. Stage a final host SSH identity during convergence; the bootstrap image contains only its
   reusable bootstrap identity and approved public access key.
8. Require an explicit absolute Windows install root.
9. Produce local build output initially; publishing/versioning bootstrap artifacts is deferred.
10. Rename `installer-rs`/`lamd` to `nxd` first, then perform ownership refactors in compile-safe
    phases. Keep the `fleet/` name.
11. Keep OpenSSH plus encoded non-interactive PowerShell as the Windows control plane. Do not
    enable WinRM/WSMan for `nxd`.
12. Keep destination-side substitution enabled through the existing
    `deployment.substituteOnDestination` policy; bootstrap artifact transport is independent of
    final Nix closure transport.
13. Use content-addressed Windows staging names with checksum verification and reuse. Do not add
    a Windows `rsync` dependency; direct SCP is the initial transfer mechanism.

### 6.1 Direct Bootstrap Artifact Transfer Addendum

Approved implementation flow for provider creation and redeploy:

```text
orchestrator prepares immutable source set
  -> selected x86_64-linux producer builds minimal-wsl tarball
  -> producer computes SHA-256
  -> producer checks/stages content-addressed tarball on Windows over OpenSSH
  -> Windows verifies SHA-256 and imports the named distribution
  -> producer temporary output and operation GC roots are cleaned
```

Required behavior:

- no `remote builder -> orchestrator -> Windows` relay or fallback;
- the configured full Windows connection (`windowsUser@windowsHost`) is used by lifecycle,
  keepalive, transfer, and diagnostics;
- an existing checksum-matched Windows artifact is reused;
- a mismatched or partial Windows artifact is removed before transfer;
- transfer, checksum, and import failures preserve enough context to identify the producer,
  Windows endpoint, and staging filename;
- run-scoped producer output is removed on success and failure;
- deployment metadata does not expose a local artifact path;
- offline/manual artifact builds continue to honor `--output` and produce a local file.

Implementation progress:

- [x] Approved direct-transfer architecture recorded; relay fallback removed.
- [x] Separate offline local artifact output from deployment artifact production.
- [x] Build deployment artifact on the selected compatible producer.
- [x] Transfer directly from producer to the configured Windows OpenSSH endpoint.
- [x] Add content-addressed Windows reuse and checksum validation.
- [x] Centralize the complete Windows connection identity.
- [x] Add focused command-rendering, selection, cleanup, and failure tests.
- [x] Run Rust formatting, tests, clippy, and focused Nix validation.

### 6.2 Bootstrap Performance, Progress, And Redeploy Endpoint Addendum

Observed behavior during live `--redeploy`:

- the coordinator transferred and rooted the immutable source set on `deploy@utils`, then the
  bootstrap artifact builder repeated the same source transfer under a second run ID;
- the minimal WSL tarball was regenerated, compressed, hashed, and transferred even when its
  builder output was unchanged;
- nested builder-to-Windows SCP emitted no visible progress because the SCP progress meter is
  TTY-oriented while `nxd` consumes newline-delimited output;
- after import, endpoint readiness was checked from the orchestrator, but the final Nix copy
  wakeup used a blind three-second delay and retried the same captured NAT address. WSL can stop
  or restart between endpoint discovery and copy, making that address temporarily unavailable or
  stale from the builder route.

Approved correction:

- reuse the coordinator-staged source set and GC root for deployment artifact production;
- cache generated bootstrap archives on the producer by tarball-builder store identity;
- retain a bounded content-addressed archive cache on Windows;
- stage uploads through a run-unique partial filename and promote only after checksum validation;
- report explicit build/archive/hash phases and poll Windows destination size during SCP;
- keep the WSL distribution alive from endpoint discovery through final convergence;
- verify guest SSH readiness through the exact selected producer/jump route before Nix copy;
- refresh the WSL guest address before retrying a failed copy instead of retrying a captured
  address blindly.

Implementation progress:

- [x] Diagnose the live redeploy failure and verify the exact builder/jump/guest route.
- [x] Remove duplicate deployment source transfer/root creation.
- [x] Add producer-side content-addressed bootstrap archive caching.
- [x] Add bounded Windows archive caching and partial-upload promotion.
- [x] Add newline-based transfer progress reporting.
- [x] Hold a WSL keepalive across endpoint discovery and convergence.
- [x] Add exact-route readiness and endpoint refresh for final Nix copy.
- [x] Add focused tests and run full verification.

### 6.3 OpenSSH Post-Quantum Warning Policy

Recent OpenSSH clients warn when a server does not negotiate a post-quantum key exchange. Until
the Windows OpenSSH server supports a compatible post-quantum algorithm, `nxd` suppresses only
that diagnostic with `WarnWeakCrypto=no-pq-kex` on coordinator and nested producer SSH/SCP
commands. This is a logging policy, not a cryptographic upgrade; other weak-crypto warnings remain
enabled.

Implementation progress:

- [x] Apply the option through shared SSH, SCP, rsync, and `NIX_SSHOPTS` rendering.
- [x] Apply the option to nested builder-originated WSL and Proxmox SSH/SCP commands.
- [x] Run focused and full Rust verification.

### 6.4 WSL Keepalive And Retry Diagnostics

Live redeploy testing confirmed that a PowerShell `Start-Process wsl.exe ... sleep` launched over
Windows OpenSSH is terminated when the launching SSH session exits. The returned PID therefore did
not represent a durable keepalive, and WSL shut down uncleanly during long destination-side Nix
substitution. The failed command also replayed all captured `nix copy` stderr progress inside one
warning event, causing normal `copying path` lines to be mislabeled as warnings.

Approved correction:

- retain a live SSH child running foreground `wsl.exe ... sleep` for the required lifetime;
- terminate and reap that SSH child when the provider operation or copy attempt completes;
- preserve the command and terminal failure diagnostics in retry errors;
- omit already-captured routine `copying path` progress from repeated warning and summary text.

Implementation progress:

- [x] Reproduce and confirm that the detached Windows keepalive process exits with its SSH session.
- [x] Replace PID-based keepalive with an owned foreground SSH session.
- [x] Compact WSL copy retry diagnostics without hiding the terminal failure.
- [x] Run focused and full Rust verification.

---

## 7. Completion Criteria

This work is complete when:

- `nxd` is the canonical crate, package, flake app, installed command, state prefix, and
  documentation name;
- WSL is resolved through the provider registry rather than generic `ctx.wsl` branches;
- a minimal secret-free WSL bootstrap tarball is reproducibly buildable;
- `nxd deploy -t <wsl-host>` can create and converge a named WSL distribution on a remote
  Windows host;
- `nxd switch -t <wsl-host>` reuses the normal NixOS convergence path;
- `nxd destroy -t <wsl-host>` safely unregisters only the configured distribution;
- single and batch orchestration use shared planning, workspace, execution, cleanup, and
  reporting mechanics;
- all focused Rust, Nix, plan, and disposable Windows/WSL integration checks pass.

---

## 8. Change History

### 2026-06-13

- **[Design / Prep]** Initialized Change History. Resolved layout renames to be done first, followed by orchestration and WSL provider logic. Agreed on using Windows OpenSSH plus explicit PowerShell/`wsl.exe` control commands. Kept temporary compatibility aliases for one migration window.
- **[Refactor]** Completed layout directories renames (`operation` -> `workflow`, `executor` -> `execution`) and moved planning submodules under `planning/`. Introduced `OperationCoordinator` in `src/execution/coordinator.rs` to centralize orchestration, and simplified deploy/switch command entry points to thin adapters. Verified compiling and tests passing.
- **[Refactor]** Completed the provider contract refactor. Provider inspection now returns typed state or an error, planning consumes one provider snapshot, capabilities drive bootstrap/recreate policy, and execution consumes typed SSH endpoints. Removed duplicate plan-provider inference.
- **[Implementation]** Hardened WSL control: PowerShell uses UTF-16LE `-EncodedCommand`, output is forced to UTF-8 and normalized, Windows OpenSSH uses strict known-host checking, preflight failures are labeled by authentication/PowerShell/WSL/version/access/install-root stage, transfer cleanup covers partial failures, and guest readiness polls the effective direct/jump-host SSH path.
- **[Refactor]** Replaced separate deploy/switch batch runners with one prepared-host job scheduler. Centralized source transfer and GC-root cleanup in the coordinator, filtered skipped hosts before workspace work, reused existing bootstrap artifacts, and retained common lockfile finalization.
- **[Verification]** `cargo fmt --check`, 85 Rust tests, strict clippy, WSL metadata/full-system/minimal-image evaluation, `nix build .#nxd --no-link`, CLI help, and offline artifact generation all pass. Built the optimized artifact through `deploy@utils` at 1.1 GiB and confirmed no project host-secret/private-key paths. Disposable Windows import/deploy/switch/destroy integration remains open.
- **[Implementation]** Added `nxd wsl bootstrap-ssh -t <host> [--public-key <path>]` for one-time Windows OpenSSH enrollment. Its default key is `defines.nix` `mySshAuthKey`, the same key authorized by the minimal WSL image; the file option is an explicit override. It uses an interactive password SSH session without accepting or storing a password, selects the Windows user/admin authorized-key path, applies the required admin ACL, and verifies the normal strict key-only control connection.
- **[Verification]** WSL SSH bootstrap changes pass `cargo fmt --check`, all 88 Rust tests, strict clippy, and CLI help rendering. Live Windows password-to-key enrollment remains the next integration check.
- **[Fix]** Corrected WSL SSH bootstrap failure reporting so network failures retain the SSH diagnostic and display the configured `user@host`, rather than being mislabeled as password or account-permission failures.

### 2026-06-14

- **[Fix]** Allowed generic installer/bootstrap hostnames ('nixos', 'installer', 'nixos-installer') or --force override in validate_remote_hostname during active deployments, enabling the initial deployment check to succeed when connecting to the minimal WSL bootstrap image.
- **[Design]** Approved direct bootstrap artifact delivery from the selected Linux producer to Windows with no orchestrator relay fallback. Retained OpenSSH plus encoded PowerShell, destination-side Nix substitution, content-addressed checksum reuse, and offline local artifact output as a separate workflow.
- **[Implementation]** Split offline local artifact output from deployment production. WSL provider creation now builds on the compatible producer, computes SHA-256 there, transfers directly to `windowsUser@windowsHost`, reuses checksum-matched Windows staging files, verifies before import, and cleans producer output, temporary known-host data, Windows staging, and artifact-specific GC roots. Removed the obsolete deployment-local artifact option and centralized the complete Windows connection for keepalive commands.
- **[Verification]** `cargo fmt`, all 95 Rust tests, strict clippy, and repository `nix fmt -- --ci` pass. `deploymentHosts.wsl`, the final WSL system derivation, and the minimal WSL tarball-builder derivation evaluate successfully. Live builder-to-Windows transfer and import remain integration checks.
- **[Diagnosis]** Live `--redeploy` exposed duplicate source staging, silent nested SCP, repeated tarball generation, and a WSL endpoint lifetime race. The builder-to-Windows-to-guest SSH route succeeds when probed directly; the failed copy retried a captured guest NAT endpoint after a blind wake delay instead of validating the exact route or refreshing the endpoint.
- **[Implementation]** Reused coordinator source staging, added producer archive caching keyed by tarball-builder store identity, retained a bounded Windows content-addressed cache, uploaded through unique partial names with polled byte/percentage progress, and promoted only after checksum validation. WSL providers now hold an operation keepalive through convergence; every final copy attempt refreshes the guest IP and remote-builder copies probe the exact builder/Windows/guest SSH route first.
- **[Verification]** All 97 Rust tests and strict clippy pass. WSL deployment metadata and the minimal tarball-builder derivation evaluate successfully, and direct read-only probes confirm the configured Windows guest IP and exact `deploy@utils -> Windows jump -> WSL guest` route. A destructive live redeploy remains an operator-run integration check.
- **[Fix / Verification]** Suppressed only the OpenSSH `no-pq-kex` warning across shared and nested `nxd` SSH/SCP paths with `WarnWeakCrypto=no-pq-kex`. This removes deployment log noise without hiding other weak-crypto diagnostics or changing negotiated algorithms. All 97 Rust tests and strict clippy pass.
- **[Diagnosis / Fix / Verification]** Live redeploy proved the detached Windows `Start-Process wsl.exe ... sleep` keepalive died as soon as its launching SSH session closed, allowing an unclean WSL shutdown during long Nix substitution. Replaced it with an owned foreground SSH session and removed replayed `copying path` progress from retry warnings while retaining terminal diagnostics. A live foreground keepalive remained active for its full SSH-owned lifetime; all 98 Rust tests and strict clippy pass.
- **[Verification]** Live `nxd deploy -t wsl --overwrite` succeeded end-to-end: source staging, builder transfer, Windows archive reuse (checksum match), WSL import, keepalive, Nix closure copy, `switch-to-configuration switch`, and lockfile archival all completed (6m 26s). Confirmed `systemctl --failed` shows 0 units after convergence — the NixOS configuration and systemd are fully healthy on the guest.
- **[Diagnosis]** After a successful deploy, `wsl -d NixOS` (interactive) failed with `Wsl/Service/0x8007274c` when invoked from a Windows OpenSSH terminal session. Journal analysis confirmed `WSL (Relay) ERROR: UtilAcceptVsock — Waiting for abnormally long accept` and `accept4 failed 110 (ETIMEDOUT)`. Root cause: WSL's interactive vsock relay requires an interactive Windows desktop session; it cannot establish a persistent PTY through an SSH session that has no desktop context. Non-interactive `wsl.exe ... --exec command` (used by `nxd`) is unaffected — this is a known Windows limitation. Running `wsl -d NixOS` from Windows Terminal (GUI) works correctly.
- **[Fix]** `nxd switch -t wsl` failed with "Target host unreachable over SSH" because `execute_switch_workflow` called `provider.endpoint(false)`, which starts the WSL keepalive but skips `wait_for_guest_ssh`. By the time `validate_and_sync_target_host_key` ran, sshd was not yet ready. Fixed by using `endpoint(poll)` where `poll = provider.capabilities().requires_bootstrap_artifact` — WSL now polls until SSH is reachable before host key validation; other providers (Proxmox, VMware) keep the existing no-poll behavior. Also removed the now-redundant 3-second blind sleep from `ensure_wsl_distribution_awake` in `identity/ssh/host_key_validation.rs`, which was a fragile workaround for the same missing readiness wait.
- **[Diagnosis / Fix / Verification]** After the switch readiness fix, the target configuration converged successfully but disabled `sshd` because `hosts/wsl/meta.nix` was missing `../../modules/os/feat/linux/services/openssh.nix` in `osFeatures`. Added the feature module to prevent SSH from being deactivated.
- **[Fix / Verification]** Added a robust 5-attempt retry loop to `validate_and_sync_target_host_key` in `apps/nxd/src/identity/ssh/host_key_validation.rs` to prevent race conditions during target `sshd` restarts. Verified end-to-end by redeploying the WSL guest (`6m 4s`) and performing subsequent switches (`0m 41s`) successfully. All 98 Rust tests pass.
- **[Implementation / Fix / Verification]** Optimized `nxd switch -t wsl` for direct transport mode (e.g., via Tailscale). When the guest VM is directly SSH-reachable, the provider bypasses Windows OpenSSH keepalives and SSH port-forwarding checks. Defer keepalive sessions, Windows-side wake-up commands (`ensure_wsl_distribution_awake`), and SSH polling to occur only under the `WindowsJump` fallback mode. This resolves connection timeouts when the Windows host SSH server is unreachable or firewalled, and speeds up direct switches. Verified that all 98 Rust tests and `nix fmt` pass.
- **[Implementation / Nix / Verification]** Added a declarative `wsl-keepalive` systemd service running `sleep infinity` to the core WSL NixOS configuration ([modules/os/base/wsl/core.nix](file:///Users/lamt/lamt-nixconfig/modules/os/base/wsl/core.nix)). This ensures the WSL VM stays alive in the background when no interactive windows are open, maintaining steady connectivity for Tailscale and sshd. Verified that the WSL configuration evaluates and plans successfully under `nxd`.
- **[Optimization / Nix / Verification]** Optimized bootstrap image package footprints in both `minimal-wsl` ([hosts/minimal-wsl/default.nix](file:///Users/lamt/lamt-nixconfig/hosts/minimal-wsl/default.nix)) and `minimal-iso` ([hosts/minimal-iso/default.nix](file:///Users/lamt/lamt-nixconfig/hosts/minimal-iso/default.nix)). Replaced the heavy standard `git` package (which pulls in a full Perl runtime) with the lightweight `gitMinimal` package, and removed `vim` as a duplicate editor since `nano` is natively available. This significantly reduces the size of the compressed WSL and ISO bootstrap images by ~200MB+ while preserving all necessary functionality for remote-builder flake resolution. Verified that all Nix formatting and Rust tests pass.
