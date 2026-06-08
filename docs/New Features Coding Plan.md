# New Features Coding Plan

This document tracks the remaining `installer-rs` feature work for review. The guiding goal is to keep the CLI small and predictable, put host-specific behavior in metadata, and fit new behavior into the existing build/deploy/provider pipeline instead of adding extra command shapes.

---

## 1. Final Scope

Features to implement:

- Local host lockfile archival after successful local-source switch/deploy.
- GitHub access-token support for Nix commands.
- Explicit cross-build attr selection through `--build-on cross`.
- Proxmox static IP/VLAN bootstrap through provider metadata and QEMU guest-agent injection, specifically for no-DHCP cold starts where the router VM is one of the first systems being brought online.

Design constraints:

- Only support the current `installer-rs` command and build-strategy names.
- Do not add `--kexec` flags; keep `KEXEC_BOOT` as the expert override and keep `--convert-to` for cloud-init/bootstrap source conversion.
- Do not add provider-specific subcommands for Proxmox bootstrap networking.
- Prefer metadata over CLI flags for durable host topology and bootstrap networking.
- Keep CLI overrides for operator intent, not host inventory.

---

## 2. Technical Design

### Lockfile Archive

After a successful local-source switch or deploy, copy the root lockfile to the host pin:

```text
./flake.lock -> ./hosts/<host>/flake.lock
```

Behavior:

- Run only when the active repo source is local.
- Skip without error if root `flake.lock` is missing.
- Do not run for `--repo-src github`, `--repo-src tea`, or custom non-local flake refs.
- In batch operations, archive independently for each host that completed successfully.
- Keep filesystem writes in an operation helper, not command handlers.

Implementation targets:

- `apps/installer-rs/src/operation/lockfile.rs`
- `apps/installer-rs/src/operation/mod.rs`
- `apps/installer-rs/src/command/switch.rs`
- `apps/installer-rs/src/command/deploy.rs`

### GitHub Token Support

Add token support for Nix operations that may need private GitHub inputs or higher rate limits:

```text
lamd --github-token <token> switch -t <host>
lamd --github-token <token> deploy --hosts <host>
GITHUB_TOKEN=<token> lamd switch -t <host>
```

Rules:

- Add global `--github-token <TOKEN>`.
- Accept `GITHUB_TOKEN` from the environment.
- Optionally detect `gh auth token` only when no CLI/env token exists and `gh` is available.
- Append `--option access-tokens github.com=<token>` to relevant Nix invocations:
  - metadata evaluation
  - flake archive/materialization
  - local builds
  - remote-builder builds
  - target-native builds
  - target-instantiated derivation evaluation
- Never print or log the raw token. Debug command rendering must redact it.

Implementation targets:

- `apps/installer-rs/src/cli.rs`
- `apps/installer-rs/src/config.rs`
- `apps/installer-rs/src/nix/build_commands.rs`
- `apps/installer-rs/src/nix/eval.rs`
- `apps/installer-rs/src/workspace/source.rs`
- local, remote-builder, target-native, and target-instantiated build paths

### Cross Build Strategy

Use the existing build-strategy surface:

```text
lamd --build-on cross switch -t <host> --action build
lamd --build-on cross deploy --hosts <host>
```

This keeps cross builds cohesive with `local`, `builder`, `target`, `native`, `instantiated`, and `auto`. Cross is an explicit operator choice because cross-compilation can fail for package-specific reasons and should not be selected by automatic strategy resolution.

#### Metadata

The flake already exposes cross intent in host metadata:

```nix
{
  class = "nixos";
  system = "x86_64-linux";

  cross = {
    localSystem = "aarch64-linux";
    crossSystem = {
      config = "x86_64-unknown-linux-gnu";
    };
  };
}
```

Expose enough of this through `deploymentHosts.<host>` and Rust metadata loading to answer only one question: is cross configured for this host? `installer-rs` does not need to interpret every cross field for command construction because the flake already owns the cross package set and exposes the final output.

Suggested Rust shape:

```rust
#[derive(Deserialize, Debug, Clone, Default)]
pub struct CrossConfig {
    #[serde(default)]
    pub local_system: Option<serde_json::Value>,
    #[serde(default)]
    pub cross_system: Option<serde_json::Value>,
}

#[derive(Deserialize, Debug, Clone)]
pub struct FlakeMetadata {
    #[serde(default)]
    pub cross: Option<CrossConfig>,
    // existing fields...
}
```

Use `serde_json::Value` or a similarly loose shape unless a later feature needs typed cross internals. That keeps evaluation cheap and avoids duplicating Nix's cross schema in Rust.

#### Build Strategy

Add:

```rust
pub enum BuildStrategy {
    Local,
    RemoteBuilder { ssh_connection: String },
    TargetInstantiated,
    TargetNative,
    Cross,
}
```

Selection rules:

- `--build-on cross` selects `BuildStrategy::Cross`.
- Reject cross for Darwin hosts. The current flake exposes `crossNixosConfigurations`, not a Darwin cross output, and the installer build attrs that matter for deploy (`config.system.build.diskoScript`, NixOS toplevel install paths) are NixOS-specific. Add a separate Darwin design only if a real Darwin cross-build workflow appears later.
- Reject cross when host metadata has no `cross`.
- Do not select cross from `auto`.
- Do not combine cross with remote builder or target-native build modes in this phase. Cross builds run on the orchestrator against the flake's `crossNixosConfigurations` output.
- Reuse the existing build request flow so deploy still builds `config.system.build.diskoScript` and `config.system.build.toplevel` through the same call sites.

#### Attr Rendering

Keep build call sites unchanged. They should still request attrs like:

```text
config.system.build.toplevel
config.system.build.diskoScript
```

Centralize attr rendering in `NixBuilder::target_attr`:

```text
BuildStrategy::Cross => crossNixosConfigurations.<host>.<attr>
Darwin toplevel      => darwinConfigurations.<host>.system
Normal NixOS         => nixosConfigurations.<host>.<attr>
Normal Darwin        => darwinConfigurations.<host>.<attr>
```

This is the smallest change because all build implementations already call through builder attr rendering.

#### Verification

- `lamd --build-on cross switch -t gaming --action build -d` should render `crossNixosConfigurations.gaming.config.system.build.toplevel`.
- Deploy with `--build-on cross` should render Disko and toplevel through `crossNixosConfigurations`.
- A host without `meta.cross` should fail before invoking Nix.
- Darwin hosts should fail with a clear unsupported message.

Implementation targets:

- `apps/installer-rs/src/cli.rs`
- `apps/installer-rs/src/fleet/metadata.rs`
- `apps/installer-rs/src/nix/eval_batch_hosts.template`
- `apps/installer-rs/src/nix/mod.rs`
- `apps/installer-rs/src/nix/strategy.rs`
- `apps/installer-rs/src/nix/build.rs`

### Proxmox Static IP/VLAN Bootstrap

Use provider metadata, not new subcommands. The normal user flow stays:

```text
lamd deploy -t router-main
lamd deploy --hosts router-main,router-backup
lamd deploy -t router-main --plan
```

Static bootstrap is activated by host metadata. A CLI flag is not the primary interface because static IP, VLAN, subnet, and bootstrap interface are properties of the VM topology, not ad hoc operator choices.

#### Cold-Start Requirement

The target scenario is a rebuild from very little working infrastructure:

- A Proxmox host has already been installed or recovered enough to be reachable from the operator machine.
- The router VMs are not running yet, so there is no DHCP service and possibly no default gateway on the bootstrap LAN.
- `installer-rs` must still be able to create the router VM, give the live installer a reachable static address, SSH in, run Disko/install, and let the final NixOS router configuration bring up DHCP/routing afterward.

This feature covers the Proxmox VM stage of that cold start. It assumes the Proxmox host itself is already reachable and can run `qm`. Bare-metal Proxmox installation/recovery is documented separately in `docs/Bare Metal Proxmox Bootstrap.md`.

#### Problem

Some Proxmox installs cannot rely on DHCP, cloud-init IP config, QEMU guest-agent IP reporting, or subnet/MAC scanning. Router-style VMs can also have separate WAN/LAN NICs where the management/bootstrap path is on `net1`, not `net0`.

The provider needs a controlled fallback:

1. Create/start the VM with the declared NIC topology.
2. Try normal provider IP discovery.
3. If static bootstrap metadata exists and the static IP is not reachable, use `qm guest exec` to configure temporary live-ISO networking.
4. Continue the existing deploy flow over SSH.

#### Metadata

Add explicit metadata under `deployment.proxmox`:

```nix
deployment.proxmox = {
  host = "192.168.1.15";

  net0 = "virtio,bridge=vmbr0";
  net1 = "virtio,bridge=vmbr1"; # optional

  bootstrap = {
    interface = "net1";       # net0 or net1, default net0
    staticIp = "192.168.1.2"; # optional; enables static injection path
    subnet = "192.168.1.0/24";
    gateway = "";             # optional; usually empty when bootstrapping the router itself
    vlan = 10;                # optional
  };

  iso = {
    type = "vlan";
  };
};
```

Prefer nested `bootstrap` over several flat fields because it groups temporary install-environment networking separately from permanent VM hardware.

Current option migration:

- Keep existing `deployment.proxmox.network` as an alias for `net0` while hosts are updated.
- Default `bootstrap.interface = "net0"`.
- If `bootstrap.staticIp` is empty, do not attempt guest-agent injection.
- If `net1` is empty but `bootstrap.interface = "net1"`, fail during planning/context loading.
- Do not create a second source of truth for permanent host IPs. If `bootstrap.staticIp` is the same address as a permanent host/router IP, define that address once in host config or `defines.nix` and reference it from metadata. If it is only a temporary installer address, keep it only under `deployment.proxmox.bootstrap`.

Suggested Rust shape:

```rust
pub struct ProxmoxConfig {
    pub network: String, // existing option, mapped to net0
    #[serde(default)]
    pub net0: String,
    #[serde(default)]
    pub net1: String,
    #[serde(default)]
    pub bootstrap: ProxmoxBootstrapConfig,
    // existing fields...
}

#[derive(Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ProxmoxBootstrapConfig {
    #[serde(default = "default_bootstrap_interface")]
    pub interface: String,
    #[serde(default)]
    pub static_ip: String,
    #[serde(default)]
    pub subnet: String,
    #[serde(default)]
    pub gateway: String,
    #[serde(default)]
    pub vlan: Option<u16>,
}
```

VLAN modeling:

- If Proxmox tags the VM NIC, put the tag in `net0` / `net1` (for example `virtio,bridge=vmbr1,tag=10`) and leave `bootstrap.vlan` empty. The live ISO sees an untagged interface.
- If the VM receives a trunk and must create a VLAN interface inside the guest, leave the NIC untagged/trunked in Proxmox metadata and set `bootstrap.vlan = 10`.
- Prefer Proxmox-side tagging unless the router VM needs trunk access during the installer phase.

#### Provider Flow

VM creation:

- Resolve `net0` as:
  - `proxmox.net0` when set
  - otherwise existing `proxmox.network`
  - otherwise default network config
- Emit `--net0 <net0>`.
- Emit `--net1 <net1>` only when non-empty.
- Do not infer router topology from hostname.

IP discovery:

- Use `bootstrap.interface` to choose the Proxmox NIC line for MAC extraction.
- Try fast discovery first:
  - neighbor table lookup
  - `qm guest cmd <vmid> network-get-interfaces`
  - configured subnet scan
- If `bootstrap.staticIp` is configured, ping it before scanning and before injection.
- If normal discovery fails and static bootstrap metadata is present, run injection.
- After injection, return `bootstrap.staticIp` only after reachability succeeds.

Guest-agent injection:

- Run from `providers/proxmox.rs`, not generic deploy code.
- Map `net0 -> eth0`, `net1 -> eth1` for the live ISO.
- If `vlan` is set:
  - create `ethX.<vlan>`
  - flush conflicting addresses/routes on the raw interface
  - assign IP to the VLAN interface
- If `vlan` is not set:
  - assign IP directly to `ethX`
- Derive CIDR from `bootstrap.subnet`; default to `/24` only if the subnet omits CIDR.
- Add a default route only when `bootstrap.gateway` is set. Do not infer `.1` automatically: in the cold-start router case, the gateway may not exist yet, and same-subnet SSH should work without a default route.
- Retry a small bounded number of times because QEMU guest-agent can become available after boot services settle.

ISO safety:

- Static injection requires a custom ISO with SSH access and QEMU guest-agent enabled.
- If `bootstrap.staticIp` is set:
  - block official ISO fallback
  - require `iso.type = "vlan"` or a custom ISO path known to be compatible
  - surface this during plan rendering before VM creation

#### Why This Is The Optimum Shape

- The CLI stays unchanged for normal deploys.
- Durable VM topology lives with host metadata.
- No-DHCP bootstrap requirements are represented as explicit host metadata rather than one-off flags.
- The provider owns Proxmox-specific behavior.
- Existing deploy, plan, wait, Disko, install, reboot, and post-reboot logic remain unchanged.
- Router hosts become normal Proxmox hosts with explicit two-NIC metadata.

Implementation targets:

- `modules/shared/options.nix`
- `apps/installer-rs/src/fleet/metadata.rs`
- `apps/installer-rs/src/context.rs`
- `apps/installer-rs/src/providers/proxmox.rs`
- `apps/installer-rs/src/operation/plan_iso.rs`
- `apps/installer-rs/src/operation/plan_render.rs`

---

## 3. Implementation Checklist

- [ ] **Lockfile Archive**
  - [ ] Add local-source archive eligibility helper.
  - [ ] Implement `hosts/<host>/flake.lock` copy helper.
  - [ ] Wire successful local-source switch.
  - [ ] Wire successful local-source deploy, including batch hosts.
  - [ ] Add tests for local source, non-local source, missing root lockfile, and destination path rendering.

- [ ] **GitHub Token Support**
  - [ ] Add global CLI/runtime option.
  - [ ] Add env fallback.
  - [ ] Add optional `gh auth token` fallback if appropriate.
  - [ ] Add Nix option rendering with redaction support.
  - [ ] Thread options through eval, archive/materialization, local build, remote builder, target-native, and target-instantiated flows.
  - [ ] Add tests proving debug/rendered logs redact the token.

- [ ] **Cross Strategy**
  - [ ] Expose optional `cross` metadata in `deploymentHosts` evaluation.
  - [ ] Deserialize optional `cross` metadata in Rust.
  - [ ] Add `BuildStrategy::Cross`.
  - [ ] Parse `--build-on cross`.
  - [ ] Validate NixOS host and configured cross metadata before building.
  - [ ] Render `crossNixosConfigurations.<host>.<attr>` from `NixBuilder::target_attr`.
  - [ ] Wire the strategy through `build_attribute`.
  - [ ] Add command-rendering tests for cross toplevel and Disko attrs.

- [ ] **Proxmox Static IP Bootstrap**
  - [ ] Add Proxmox `net0`, `net1`, and nested `bootstrap` options.
  - [ ] Preserve `deployment.proxmox.network` as `net0` during host migration.
  - [ ] Validate `bootstrap.interface` against configured NICs.
  - [ ] Update VM creation to emit optional `net1`.
  - [ ] Make IP discovery use the configured bootstrap interface.
  - [ ] Implement provider-local `qm guest exec` static IP/VLAN helper.
  - [ ] Add optional `bootstrap.gateway` handling without inferred default gateway.
  - [ ] Add plan-time custom ISO validation for static bootstrap hosts.
  - [ ] Block official ISO fallback for static bootstrap hosts.
  - [ ] Add tests for command rendering, interface mapping, fallback order, and ISO blocking.

---

## 4. Verification Checklist

- [ ] `cd apps/installer-rs && cargo fmt --check`
- [ ] `cd apps/installer-rs && cargo test`
- [ ] `cd apps/installer-rs && cargo clippy --all-targets -- -D warnings`
- [ ] `nix eval .#deploymentHosts.gaming.cross`
- [ ] `nix eval .#crossNixosConfigurations.gaming.config.system.build.toplevel.drvPath`
- [ ] `nix run .#installer-rs -- switch -t gaming --action build --build-on cross -d`
- [ ] Successful local-source switch archives `flake.lock` to `hosts/<host>/flake.lock`.
- [ ] Non-local repo source does not write `hosts/<host>/flake.lock`.
- [ ] GitHub token is accepted and redacted in debug output.
- [ ] Default kexec `auto` still bypasses live NixOS installer environments and takes over persistent OS targets.
- [ ] `--convert-to` still installs the requested final host configuration from a cloud-init/bootstrap source host.
- [ ] Proxmox two-NIC hosts can provision `net1` and discover/reach the bootstrap IP through the configured interface.

---

## 5. Test Coverage Priorities

- Cross attr rendering.
- Host metadata validation for cross strategy.
- Cross rejection for Darwin or hosts without `cross`.
- Token option rendering and redaction.
- Lockfile archive eligibility.
- Batch per-host success handling for lockfile archival.
- Proxmox static IP/VLAN command rendering.
- Proxmox bootstrap-interface MAC extraction and subnet scanning.
- Proxmox `net0`/`net1` creation command rendering.
- Custom ISO requirement and official ISO fallback blocking for static IP/VLAN bootstrap.
- Kexec `auto` behavior, `KEXEC_BOOT` override handling, and live-installer bypass behavior.
