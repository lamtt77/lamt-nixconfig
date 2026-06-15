# Bare Metal Proxmox Bootstrap

## Status

- **Automated Integration Test**: Successfully verified via the `./tests/test_pve_pxe_integration.sh --keep` pipeline. The disposable `pve-test` VM boots via PXE, retrieves the autoinstall configuration, executes the first-boot setup script (with shebang `/bin/sh` preserved in the Nix store by omitting executable permissions), configures the bonded target network layout, and becomes reachable at `192.168.250.10` via the jump host.
- **Failover / HA Configuration**: Identical PXE config is enabled on both `router-main` and `router-backup`. The PXE services (TFTP and HTTP) automatically start/stop following the LAN VIP VRRP state changes.

## Goal

Provide a reproducible path from fresh physical hardware to a reachable Proxmox node using repository-managed PXE assets and configuration.

The design must cover:

1. Normal recovery when a router/PXE server is available.
2. Cold recovery when both production routers are unavailable.
3. Automated disposable integration testing on `pve1` without automated mutation of production bridges, addresses, routes, or physical interfaces.
4. Dell R720 NVMe boot through the existing rEFInd helper.
5. HP server installation without rEFInd.

The scope ends when Proxmox is installed, its final networking is active, reviewed baseline configuration is restored, and the node is reachable for normal `lamd` VM deployment.

## Design Principles

### Keep The CLI Small

Reuse the existing installer lifecycle:

```text
lamd deploy -t router-recovery
lamd deploy -t pve-test --plan
lamd deploy -t pve-test
lamd deploy -t pve-test --redeploy
lamd deploy -t pve-test --redeploy --build-iso
lamd destroy -t pve-test
```

Do not add a separate `lamd pve-test` command family.

### Template First

All human-readable Proxmox/PXE configuration that needs Nix parameters should be a checked-in template.

This includes:

- Proxmox answer TOML
- `/etc/network/interfaces`
- first-boot shell script
- `corosync.conf`
- `storage.cfg`
- iPXE menu

Use explicit placeholders such as:

```text
@HOSTNAME@
@FINAL_IP@
@GATEWAY@
@BOOTSTRAP_IP@
@FIRST_BOOT_URL@
```

Nix should only:

- select the target and template variant
- validate required parameters
- substitute placeholders
- compose PXE assets and restore tarballs

Do not build these files line by line in target-specific Nix renderer functions when a template is easier to review.

Use one small generic substitution helper. A specialized renderer is acceptable only when the output is genuinely variable-length and a template would be less readable.

### One HTTP Implementation

Keep the existing Python/aiohttp answer-server approach because the Proxmox installer POSTs the answer-file request.

- Extract it from the current monolithic module.
- Make it serve all PXE HTTP files for both GET (kernels, initrds, public boot scripts, configs.tar.gz) and POST/GET (the dynamic answer file).
- The Python server accepts `--static-dir` to serve static assets from the Nix store and `--answer-file` to serve the dynamically materialized answer file.
- Reuse it for router-hosted, `router-recovery`, and portable cold-recovery paths.
- Do not implement another HTTP server in Rust.
- Do not add nginx solely to proxy answer-file POST requests; completely replace Nginx on these paths.

### Package Assets, Module Runtime

Keep a strict boundary between reusable build artifacts and NixOS runtime integration.

The package layer owns pure, reusable outputs:

- selected target profile and instantiated templates
- Proxmox kernel/initrd and iPXE binaries
- non-secret answer inputs and first-boot script
- restore tarball
- target metadata used by the portable bootstrap app
- packaged Python HTTP/answer-server executable

The NixOS service module owns machine state and runtime policy:

- systemd units
- interface and listen-address binding
- firewall ports
- HTTP/TFTP service startup
- integration with the router's DHCP configuration
- assertions preventing unsafe or conflicting service combinations

The package must not enable services, configure interfaces, open firewall ports, or choose a DHCP daemon. The service module must not contain complex asset-generation logic.

The final answer TOML is runtime state, not a store artifact, because it contains the temporary installer credential. The service or portable app must materialize it under `/run` from the packaged non-secret inputs plus a runtime credential.

Use a package-producing function rather than one package containing every target:

```nix
mkPvePxeAssets {
  target = "pve1";
  bootstrapIp = "192.168.1.1";
}
```

This keeps evaluation and builds target-specific and avoids forcing a router or recovery image to build assets for `pve1`, `pve2`, and `pve-test` together.

### One DHCP Owner

Only one DHCP implementation may own an install segment:

- `router-main` and `router-backup` remain the production Kea HA pair.
- `router-main` contains the `pve1` PXE package and `router-backup` contains
  the `pve2` PXE package.
- Production Kea always advertises `next-server = 192.168.1.1`.
- `192.168.1.1` is the existing LAN VRRP VIP. Only the production router that currently owns the VIP serves TFTP and HTTP on it.
- Portable cold recovery and isolated `router-recovery` test mode use dnsmasq for DHCP/TFTP.
- The PXE service module must support `dhcpBackend = "none" | "dnsmasq"`; `none` means another declarative service such as Kea owns DHCP.
- Never start dnsmasq DHCP beside production Kea on the same L2 segment.

Kea HA and PXE availability therefore fail over together:

1. `router-main` normally owns `192.168.1.1`, serves `pve1`, and runs as the
   Kea primary.
2. If `router-main` fails, `router-backup` takes `192.168.1.1`, serves `pve2`,
   and continues DHCP as the Kea standby.
3. Clients continue using the same DHCP `next-server` and boot filenames; no DHCP reconfiguration or recovery-host promotion is required.

PXE services must follow VRRP ownership. Keepalived state notifications should start the VIP-bound TFTP/HTTP services on transition to `MASTER` and stop them on transition away from `MASTER`. A standby router must not fail its boot merely because the VIP is absent, and it must not serve production PXE through its fixed LAN address.

Keeping identical assets on `router-backup` increases its Nix-store and deployment footprint, but does not materially increase steady-state CPU or memory use while it remains standby. This is the accepted tradeoff for automatic PXE failover without operator steps.

The reusable asset package is independent of this choice.

### Runtime Secrets Stay Out Of The Store

Never put the Proxmox installer password, its hash, SSH private keys, or cluster credentials in templates, target metadata, derivation arguments, generated packages, or restore tarballs.

- Router and `router-recovery` services load the temporary installer credential through a systemd credential backed by the existing secret-management path.
- Portable cold recovery generates a one-time credential by default, stores it in a root-only runtime credential file, and reports only that file's path.
- An explicit credential input may be supported for recovery, but it must use a file descriptor or root-only file, not a CLI value or environment variable.
- The Python server reads the materialized answer file; it does not receive or log the credential separately.
- First boot installs the intended access configuration and then disables or rotates the temporary installer credential.

This preserves pure, cacheable PXE assets without leaking recovery credentials through the Nix store, process list, logs, or shell history.

### Versioned Asset Contract

Each selected asset package must include a small non-secret manifest containing:

- schema version
- target name and expected hostname
- hashes of served boot, template, and restore artifacts
- required HTTP/TFTP paths
- first-boot protocol version

The NixOS service and portable bootstrap app must reject an unsupported schema. The first-boot script must verify the restore artifact hash before extraction. This makes mixed or stale USB, server, and template versions fail clearly instead of partially restoring a node.

### Isolated Four-NIC Integration Test

`pve-test` models the physical Proxmox network layout with four NICs while remaining isolated from production:

- `net0` through `net2` become guest interfaces `ens18` through `ens20` and connect to `vmbrPxe`.
- `net3` becomes guest interface `ens21` and connects to `vmbrTestWan`.
- `ens18` through `ens20` form the test `bond0` used by guest `vmbr1`.
- `ens21` remains separate and backs guest `vmbr0`.

The bridges are persistent Proxmox host infrastructure, not test-run state. Initially, the operator adds them to `pve1`. Long term, the reviewed network-interface templates for both `pve1` and `pve2` include both bridges:

```text
auto vmbrPxe
iface vmbrPxe inet manual
        bridge-ports none
        bridge-stp off
        bridge-fd 0

auto vmbrTestWan
iface vmbrTestWan inet manual
        bridge-ports none
        bridge-stp off
        bridge-fd 0
```

Both bridges have no host IP, physical port, VLAN trunk, or route to production networks:

- `vmbrPxe` connects the isolated PXE server interface on `router-recovery` to the three bonded `pve-test` interfaces.
- `vmbrTestWan` represents the separate WAN-side network used by `pve-test` guest `vmbr0`.
- `vmbrTestWan` is test-specific and must not reuse the unrelated `vmbrVyos` bridge.

`installer-rs` must treat both bridges as prerequisites:

- verify that `vmbrPxe` and `vmbrTestWan` exist on the selected Proxmox node before creating `pve-test`
- fail with a clear remediation message if either is absent
- never create, configure, modify, or remove either bridge
- never include bridge cleanup in failed-create or destroy paths

This keeps the provider limited to VM lifecycle operations and removes host-network mutation and rollback logic from integration testing.

#### Manual Operator Prerequisite

Before the first automated integration run, the operator must perform this one-time change on `pve1`:

1. Back up `/etc/network/interfaces`.
2. Add the `vmbrPxe` and `vmbrTestWan` bridge definitions shown above without changing `vmbr0`, `vmbr1`, bonds, VLANs, addresses, gateways, or physical-port assignments.
3. Validate the interfaces file layout using `ifquery -a` (this parses `/etc/network/interfaces` and reports syntax errors).
4. Apply the change live on the node using `ifreload -a` (this reloads the configuration via `ifupdown2` without restarting the node or dropping active network links).
5. Confirm that production management connectivity and existing VMs remain healthy.
6. Confirm that both test bridges exist, are `UP`, have no IP addresses, and have no physical bridge ports.
7. Tell the implementation operator that the prerequisite is complete before any `router-recovery` or `pve-test` deployment is attempted.

This is intentionally not automated by `lamd`. The initial change modifies production host networking and requires human review. After the integration design is proven on `pve1`, make both bridges part of the reviewed, persistent interface templates for `pve1` and `pve2`.

The automated test validates:

- DHCP and PXE boot
- iPXE asset retrieval
- Proxmox unattended installation
- first-boot script execution
- template substitution
- restore-tarball isolation
- final SSH reachability
- normal `deploy`, `redeploy`, and `destroy` behavior

It validates the guest-side three-NIC active-backup bond topology, but not the physical 802.3ad bond, VLAN trunk, switch configuration, throughput, or link-failure behavior. Those remain targeted hardware tests.

## Existing Physical Flow

The current physical server layout is:

- `eno1`, `eno2`, and `eno3` form `bond0`.
- `bond0` feeds VLAN-aware `vmbr1`.
- Proxmox management runs on `vmbr1.10`.
- `eno4` feeds untagged `vmbr0` for the router WAN side.

Preferred reinstall path:

1. Leave `eno1` through `eno3` connected to their final production trunk ports.
2. Use `eno4` as the temporary untagged PXE/install path.
3. Serve DHCP, TFTP, and HTTP only on the isolated recovery segment.
4. Install Proxmox using the temporary DHCP lease.
5. First boot writes the final production network template.
6. Management moves to `vmbr1.10`.
7. Disconnect the temporary recovery path.

This avoids manually toggling VLAN mode on the HP ProCurve switch.

## Recovery Paths

### Router-Hosted Recovery

`router-main` and `router-backup` are the production PXE pair:

- `router-main` builds and serves the `pve1` PXE profile.
- `router-backup` builds and serves the `pve2` PXE profile.
- Both are configured to serve TFTP and HTTP on the LAN VIP `192.168.1.1`.
- Only the current VRRP `MASTER` runs the VIP-bound PXE services.
- Both Kea peers advertise `next-server = 192.168.1.1`.
- Router and PXE service ownership fail over through VRRP. The available PXE
  profile changes with the router that owns the VIP.

`router-recovery` is not part of the production PXE or Kea HA pair.

The router service selects a target profile:

```nix
modules.os.linux.services.router = {
  enablePxe = true;
  pxeTarget = "pve1"; # pve1, pve2, or pve-test
};
```

Target selection is explicit host policy:

- `router-main`: `pxeTarget = "pve1"`
- `router-backup`: `pxeTarget = "pve2"`

Do not rely on the router module default for either production router.

### Cold Recovery

When no router is available, boot a laptop or temporary machine into a Linux/NixOS live environment and run the portable bootstrap service.

The runtime is Linux because it needs root networking, DHCP broadcasts, TFTP, and predictable Ethernet behavior. macOS is used to build and flash media, not to run the service directly.

The portable server handles one explicit target per process:

```text
sudo pve-bootstrap-server \
  --target pve1 \
  --interface eth0 \
  --listen-ip 192.168.0.5 \
  --dhcp-range 192.168.0.200,192.168.0.220
```

Keep the options limited to:

- `--target <pve1|pve2|pve-test>`
- `--interface <name>`
- `--listen-ip <ip>`
- `--dhcp-range <start,end>`
- `--assets-dir <path>` for development or recovery overrides
- `--workdir <path>`
- `--dry-run`
- `--force`
- `--debug`

Target-specific disks, final networking, restore files, and rEFInd requirements belong in target metadata, not CLI flags.

The Cold Recovery USB is a bootable NixOS live image. It contains:

- `pve-bootstrap-server`
- dnsmasq and the packaged HTTP answer server
- prebuilt `pve1` assets under `/etc/cold-recovery/assets/pve1`
- prebuilt `pve2` assets under `/etc/cold-recovery/assets/pve2`
- the fixed cold-recovery bootstrap IP `192.168.0.5`

It does not replace `router-recovery`, which remains the isolated automated
integration-test VM.

### Build And Flash The Cold Recovery USB

The image contains both production asset packages and is larger than a minimal
live ISO. Use an 8 GiB or larger USB drive.

Build the image from the repository root:

```bash
nix build \
  .#nixosConfigurations.cold-recovery-usb.config.system.build.coldRecoveryImg \
  -o result-cold-recovery
```

`result-cold-recovery` points directly to the hybrid bootable ISO and can be
written to the whole USB device, not to a partition.

Before flashing, disconnect unrelated removable disks and identify the USB
device carefully. The following operation destroys all data on the selected
device.

Linux:

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
sudo umount /dev/sdX?* 2>/dev/null || true
sudo dd if=result-cold-recovery of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

macOS:

```bash
diskutil list external physical
diskutil unmountDisk /dev/diskN
sudo dd if=result-cold-recovery of=/dev/rdiskN bs=4m
sync
diskutil eject /dev/diskN
```

Replace `/dev/sdX` or `/dev/diskN` with the whole USB device. Do not use a
partition such as `/dev/sdX1` or `/dev/diskNs1`.

### Use The Cold Recovery USB

1. Boot the laptop from the Cold Recovery USB.
2. Connect its wired Ethernet interface to the temporary recovery network.
3. Identify the interface and assign the fixed bootstrap address:

   ```bash
   ip link
   sudo ip link set eth0 up
   sudo ip address replace 192.168.0.5/24 dev eth0
   ```

4. Start exactly one target profile.

Recover `pve1`:

```bash
sudo pve-bootstrap-server \
  --target pve1 \
  --interface eth0 \
  --listen-ip 192.168.0.5 \
  --dhcp-range 192.168.0.200,192.168.0.220 \
  --assets-dir /etc/cold-recovery/assets/pve1
```

Recover `pve2`:

```bash
sudo pve-bootstrap-server \
  --target pve2 \
  --interface eth0 \
  --listen-ip 192.168.0.5 \
  --dhcp-range 192.168.0.200,192.168.0.220 \
  --assets-dir /etc/cold-recovery/assets/pve2
```

5. One-time PXE boot the matching physical server from the laptop network.
6. Confirm the target before proceeding:
   - `pve1`: `sda` and `sdb`, final IP `192.168.1.15`
   - `pve2`: `nvme0n1`, final IP `192.168.1.5`
7. Stop `pve-bootstrap-server` with `Ctrl+C` after installation.

The rEFInd USB required by `pve2` is separate from this Cold Recovery USB.

## Router-Recovery

`router-recovery` is a normal NixOS flake host deployed through the existing installer.

Host identity:

- hostname: `router-recovery`
- WAN IP: `192.168.0.20`
- LAN IP: `192.168.1.20`
- sync IP: `192.168.4.20`
- no production Kea peer or VRRP membership during ordinary operation

Its normal role is the isolated `pve-test` PXE server. In this role it:

- serves dnsmasq DHCP/TFTP and HTTP only on the isolated `vmbrPxe` segment
- uses `192.168.250.1/24` on its isolated interface
- does not start production DHCP, VRRP, WAN VIP, gateway, or DNS services
- may run on `pve1` or `pve2` without participating in the production router pair

Catastrophic recovery when both production routers are unavailable belongs to the portable cold-recovery/USB path. It must not turn the routinely running `router-recovery` VM into an automatic third Kea or VRRP peer.

## Pve-Test

`pve-test` is a metadata-only host used by the existing Proxmox provider lifecycle.

Planned metadata:

```nix
let
  mydefs = import ../../defines.nix;
in
{
  class = "nixos";
  system = "x86_64-linux";
  username = "root";
  server = true;
  hasDisko = false;
  buildSystem = false;

  deployment = {
    vmid = "911";
    diskSize = "20";
    targetIp = "192.168.250.10";
    proxmox = {
      host = mydefs.hosts.pve1.ip;
      bios = "seabios";
      diskBus = "virtio";
      cores = "2";
      memory = "8192";
      network = "virtio,bridge=vmbrPxe";
      extraNetworks = [
        "virtio,bridge=vmbrPxe"
        "virtio,bridge=vmbrPxe"
        "virtio,bridge=vmbrTestWan"
      ];
    };
  };
}
```

Test network:

- Proxmox host: `pve1` at `192.168.1.15`
- Proxmox node name: `pve-dl360p`
- VMID: `911`
- disk size: `20 GiB`
- persistent isolated bridges: `vmbrPxe` and `vmbrTestWan`, prepared on `pve1` before running the test
- bootstrap server: `192.168.250.1`
- DHCP range: `192.168.250.100-150`
- final pve-test IP: `192.168.250.10`

Provider behavior:

- Reuse normal fixed-VMID `exists()` and `destroy()` behavior.
- Add only the minimum PXE-specific create/start behavior.
- Perform a preflight check verifying both:
  - The preconfigured `vmbrPxe` and `vmbrTestWan` bridges exist and are active.
  - The `router-recovery` VM is active (using `qm status <router-recovery-vmid>`).
- On failed create, call the normal provider `destroy()` cleanup.
- Never create, stop, modify, or destroy production VMs or Proxmox host bridges.
- Leave `router-recovery` intact when destroying `pve-test`.
- Since `pve-test` has `buildSystem = false` and `hasDisko = false`, `installer-rs` skips the NixOS build, partition, and disko formatting steps. It creates and starts the VM to let PXE boot run, and polls SSH reachability on the final static IP (`192.168.250.10`) until the unattended Proxmox installation and first-boot configuration are fully complete.

## Target Profiles

Create cheap target metadata under the PXE module. It may import `defines.nix`, but it must not evaluate full host systems.

Each target declares:

- hostname and Proxmox node name
- final management IP
- install network mode
- installation disks and optional disk filters
- network template
- answer and first-boot template parameters
- static restore fragments
- whether cluster/storage templates are included
- whether rEFInd is required

Profiles:

- `pve1`: production HP/DL360 configuration; does not require rEFInd.
- `pve2`: production Dell R720/NVMe configuration; requires rEFInd.
- `pve-test`: one disk, four NICs on two isolated networks, no production cluster or storage restore.

The HP server does not use rEFInd. The Dell R720 NVMe installation does.

Keep target profiles in one cheap shared data file (`pkgs/pve-pxe-assets/targets.nix`) consumed by both package construction and installer metadata. Do not maintain separate Rust and Nix copies of target defaults. Export only the small runtime subset as JSON inside the selected asset package when the portable app needs it.

Separate profile data by ownership:

- PXE/install profile: disks, answer parameters, final network template, restore fragments, rEFInd requirement. Defined in `pkgs/pve-pxe-assets/targets.nix` and consumed by `mkPvePxeAssets`.
- VM lifecycle metadata: Proxmox host, VMID, cores, memory, and test bridges. Defined in `hosts/<name>/meta.nix` and exposed via flake `deploymentHosts`.
- Runtime service configuration: interface, listen address, DHCP backend, and firewall policy. Defined in the service module configuration.

Do not mix these three concerns into one large profile.

## Refactoring Requirements

Refactoring the existing implementation is part of this feature, not optional cleanup after it.

- Keep the existing production behavior working while extracting packages, templates, target metadata, and the thin service module.
- Remove unrelated Ubuntu/cloud-init PXE behavior instead of carrying it into the Proxmox-specific design.
- Replace hard-coded target names, host addresses, paths, ports, and command options with typed metadata or shared constants where they represent policy.
- Reuse the existing installer provider lifecycle and shared command/process helpers. Do not duplicate `exists`, `destroy`, SSH, logging, dry-run, or child-process mechanics.
- Keep Rust responsibilities small: validate configuration, construct reviewed commands, supervise child processes, and report failures.
- Keep Nix responsibilities declarative: select profiles, validate values, instantiate templates, and compose packages and services.
- Keep the Python server limited to the HTTP behavior required by the Proxmox installer.
- Prefer small modules with one owner. Split files when asset construction, runtime service configuration, lifecycle planning, and provider execution become mixed.
- Search for repeated command construction, validation, option lists, and shell snippets before adding new branches; extract shared mechanics only where it reduces real duplication.
- Do not add compatibility aliases or transitional abstractions unless they are required for the staged migration. Remove temporary compatibility code after router-hosted recovery is verified.

Before each implementation phase is considered complete, review the changed files for duplicated mechanics, oversized functions, hard-coded policy, and responsibilities that belong in another layer.

## Proposed File Layout

```text
pkgs/pve-pxe-assets/
  default.nix
  targets.nix
  manifest.nix
  templates/
    answer.toml
    first-boot.sh
    interface-production
    interface-test
    corosync.conf
    storage.cfg
    autoexec.ipxe
  lib/
    substitute-template.nix
    config-tarball.nix
  configs/
    pve1/
    pve2/

pkgs/pve-answer-server/
  default.nix
  answer-server.py

modules/os/linux/services/pve-pxe.nix

apps/installer-rs/src/bin/
  pve-bootstrap-server.rs

apps/installer-rs/src/pve_bootstrap/
  config.rs
  dnsmasq.rs
  interface.rs

hosts/
  router-recovery/
  pve-test/
```

`pkgs/pve-pxe-assets/default.nix` exposes `mkPvePxeAssets`, a pure package-producing function. `modules/os/linux/services/pve-pxe.nix` is a thin runtime wrapper with an `assets` package option. Asset construction and portable bootstrap must not depend on enabling the router module.

Suggested service interface:

```nix
modules.os.linux.services.pve-pxe = {
  enable = true;
  assets = mkPvePxeAssets {
    target = "pve1";
    bootstrapIp = "192.168.1.1";
  };
  interface = "eth1.10";
  listenAddress = "192.168.1.1";
  dhcpBackend = "none"; # router Kea owns DHCP
};
```

The production router integration must wrap this service with VRRP ownership handling. The service is enabled in both router configurations, but its VIP-bound HTTP/TFTP units run only while the local router owns `192.168.1.1`.

For isolated recovery:

```nix
modules.os.linux.services.pve-pxe = {
  enable = true;
  assets = mkPvePxeAssets {
    target = "pve-test";
    bootstrapIp = "192.168.250.1";
  };
  interface = "eth1";
  listenAddress = "192.168.250.1";
  dhcpBackend = "dnsmasq";
};
```

Keep a compatibility import or option alias during migration from `pxe-ipxe`, then remove the old name after router hosts are verified. The new module name should be Proxmox-specific because unrelated PXE workflows do not belong in it.

### Build Boundaries

Split expensive, stable inputs from cheap target-specific outputs where practical:

- Proxmox ISO download/extraction should be shared and cached.
- Template substitution, target metadata, non-secret answer inputs, first-boot scripts, manifests, and restore tarballs should be cheap per-target derivations.
- Changing a hostname, IP, or template should not repeat unrelated package work when Nix can reuse the extracted ISO layer.
- Do not expose a combined all-target package as the normal runtime dependency.

## First-Boot Requirements

The first-boot template must:

1. Use `set -eu`.
2. Refresh the Proxmox boot configuration.
3. Download the target restore tarball with `curl -fsSL` before changing networking.
4. Verify the tarball hash from the asset manifest, then validate it with `tar -tzf`.
5. Write the selected final network template.
6. Apply networking.
7. Extract the validated restore tarball.
8. Fail hard if download, validation, network application, or restore fails.
9. Rotate or disable the temporary installer root password.

Do not continue after a failed restore download.

## Restore Safety

Production restore files must be reviewed and target-specific.

- `pve1` and `pve2` may use parameterized `corosync.conf` and `storage.cfg` templates.
- Hardware-specific `lvm.conf`, `multipath.conf`, and modprobe fragments remain static unless they need parameters.
- `pve-test` must not copy any file from `pve1` or `pve2`.
- `pve-test` must not receive production cluster names, node keys, storage definitions, NFS paths, or LVM configuration.
- Never place secrets or private keys in templates or restore tarballs.

Before physical recovery, explicitly confirm the historical `pve1` hostname difference between `pve1` and `pve-dl360p` in the cluster configuration.

## rEFInd Requirements

The Dell R720 cannot boot directly from its NVMe disk.

- Keep the existing `refind-booter.nix` behavior until the new design is implemented and verified.
- The rEFInd USB is separate from the Cold Recovery USB.
- During reinstall, use one-time PXE boot or temporarily remove/disable the rEFInd USB so the old NVMe installation is not started.
- Reattach or re-enable rEFInd after Proxmox installation.
- The HP server skips this process.

Target metadata must drive the operator reminder; do not enable or build rEFInd unconditionally for every target.

## Safety Requirements

`pve-bootstrap-server` must:

- run only on Linux
- require root except for `--dry-run`
- require explicit interface and listen IP
- reject Wi-Fi unless `--force`
- reject the default-route interface unless `--force`
- require the listen IP to exist on the selected interface
- refuse occupied UDP 67, UDP 69, or TCP 80
- bind DHCP/TFTP/HTTP only to the selected interface/IP
- terminate child processes on shutdown
- remove only temporary state it created

The Proxmox-backed test must:

- use fixed VMID `911`
- attach only to `vmbrPxe` and `vmbrTestWan`
- require both isolated bridges to be preconfigured on the selected Proxmox node
- refuse an unexpected Proxmox node name
- verify exact VM ownership before destructive actions
- never contact or mutate `pve2`
- never attach to `vmbr0`, `vmbr1`, or another production bridge
- never create, reconfigure, or delete a Proxmox host bridge
- leave `router-recovery` intact when destroying `pve-test`

## Implementation Plan

### Phase 1: Tests And Templates

- [x] Add unit tests for generic placeholder substitution and missing placeholders.
- [x] Add checked-in templates for answer TOML, first boot, production/test interfaces, corosync, storage, and iPXE.
- [x] Add target-profile evaluation tests for `pve1`, `pve2`, and `pve-test`.
- [x] Add restore-isolation tests before changing production asset generation.
- [x] Define and test the versioned asset-manifest schema.
- [x] Capture focused regression tests for current production asset paths and target selection before refactoring them.

### Phase 2: Refactor Existing PXE Module

- [x] Extract target metadata from `default.nix`.
- [x] Create pure `mkPvePxeAssets` package construction.
- [x] Split cached Proxmox base extraction from cheap target-specific assets where practical.
- [x] Package and reuse the Python HTTP/answer server.
- [x] Add a thin `pve-pxe` NixOS service module with an explicit `assets` option.
- [x] Add `dhcpBackend = "none" | "dnsmasq"` and assertions enforcing one DHCP owner.
- [x] Materialize the final answer TOML under `/run` from a systemd credential; keep credentials out of Nix derivations and packages.
- [x] Remove unrelated Ubuntu/cloud-init PXE logic.
- [x] Parameterize router target selection instead of hard-coding `pve2`.
- [x] Keep a temporary compatibility path for the old `pxe-ipxe` module name.
- [x] Preserve current production behavior while refactoring.
- [x] Review the resulting Nix modules for duplicated rendering, oversized expressions, and hard-coded policy before proceeding.

### Phase 3: Portable Bootstrap Server

- [x] Add `pve-bootstrap-server` inside `apps/installer-rs`.
- [x] Keep Rust limited to CLI validation and child-process management.
- [x] Use `dnsmasq` for DHCP/TFTP.
- [x] Launch the packaged Python HTTP server.
- [x] Pass one selected `pve-pxe-assets` package to the flake app.
- [x] Generate or securely load a one-time installer credential and materialize the answer TOML in a root-only runtime directory.
- [x] Validate the asset-manifest schema before starting network services.
- [x] Add dry-run and interface-safety tests.
- [x] Reuse installer process, logging, command-planning, and shutdown helpers instead of adding parallel implementations.

### Phase 4: Production PXE Failover And Router-Recovery

- [x] Add `hosts/router-recovery` as a normal deployable NixOS host.
- [x] Add an explicit isolated PXE test mode.
- [x] Ensure test mode cannot enable production DHCP/VRRP behavior.
- [x] Remove the obsolete production standby-router role from the finalized recovery design.
- [x] Assign `pve1` explicitly to `router-main` and `pve2` explicitly to
  `router-backup`.
- [x] Make production PXE units follow ownership of the `192.168.1.1` VRRP VIP.
- [x] Make both Kea peers advertise `next-server = 192.168.1.1`.
- [ ] Test router-main to router-backup PXE failover.

### Phase 5: Pve-Test Lifecycle

- [x] Operator: back up and manually add persistent `vmbrPxe` and `vmbrTestWan` bridges to `pve1`, verify production health, and confirm completion before integration testing.
- [x] Add the no-port, no-IP `vmbrTestWan` definition to the long-term reviewed network templates for `pve1` and `pve2`.
- [x] Keep the no-port, no-IP `vmbrPxe` definition in the long-term reviewed network templates.
- [x] Replace the temporary `vmbrVyos` fourth-NIC attachment with `vmbrTestWan`.
- [x] Add metadata-only `hosts/pve-test` with fixed VMID `911`, a 20 GiB disk, 8 GiB RAM, and four NICs.
- [x] Extend the existing provider with the minimum PXE create path.
- [x] Extend the read-only preflight check to validate both isolated bridges and reject physical ports or host IP addresses.
- [x] Reuse normal provider `exists`, `redeploy`, and `destroy` behavior.
- [x] Add plan tests proving only VMID `911`, `vmbrPxe`, and `vmbrTestWan` are referenced.
- [x] Review `proxmox.rs` after the PXE path lands and extract shared lifecycle mechanics if create, cleanup, or command construction is duplicated.

### Phase 6: Automated Integration

Integration testing is automated via the [test_pve_pxe_integration.sh](file:///Users/lamt/lamt-nixconfig/tests/test_pve_pxe_integration.sh) script. The script verifies:

1. Nix evaluation-level target configuration correctness.
2. Hypervisor presence and isolation of `vmbrPxe` and `vmbrTestWan`.
3. PXE VM creation and autostart on the hypervisor.
4. Target dynamic OS installation and final reachability via SSH.
5. Post-installation VM destruction (unless kept).

To run the integration pipeline:

- Run all tests and auto-destroy VM:
  ```bash
  ./tests/test_pve_pxe_integration.sh
  ```
- Run tests and keep the target VM running (for inspection or manual login):
  ```bash
  ./tests/test_pve_pxe_integration.sh --keep
  ```

### Phase 7: Hardware Validation

- [x] Add a reproducible `system.build.coldRecoveryImg` live-image output.
- [ ] Build, flash, and boot the physical Cold Recovery USB.
- [ ] Validate HP installation without rEFInd.
- [ ] Validate Dell R720 installation with the separate rEFInd USB.
- [ ] Validate the real three-NIC bond and VLAN 10 transition.
- [ ] Confirm restored cluster/storage configuration on each production node.

### Phase 8: Cleanup And Documentation

- [x] Remove temporary compatibility code after router-hosted recovery is verified.
- [x] Run formatters and relevant linters for all touched Nix, Rust, Python, shell, and documentation files.
- [ ] Update `docs/Installer Rust Architecture and Implementation Plan.md` for permanent installer architecture changes.
- [ ] Update the operator runbook with the final cold-recovery, router-recovery, `pve-test`, and rEFInd procedures.
- [ ] Perform a final duplication, hard-coded policy, module-size, and ownership-boundary review.

## Verification And Test Coverage

Increase coverage where appropriate and sensible, prioritizing planning helpers, command construction, safety validation, asset generation, and lifecycle regressions.

### Unit And Evaluation Tests

- Template substitution succeeds for every target and fails on missing or unused required placeholders.
- Target profiles reject invalid disks, network modes, restore combinations, and rEFInd settings.
- Asset manifests are deterministic, schema-versioned, and contain correct hashes and paths.
- `pve-test` restore construction cannot reference `pve1` or `pve2` files.
- DHCP ownership assertions reject conflicting Kea/dnsmasq configurations.
- Runtime-secret tests prove credentials are absent from derivation inputs, package outputs, plans, and logs.
- Portable-server validation covers Linux/root requirements, interface selection, occupied ports, default-route protection, Wi-Fi rejection, and `--force` behavior.
- Proxmox planning tests cover fixed VMID ownership, expected node, bridge allow-listing, command construction, dry-run output, and cleanup reuse.
- Destroy and failed-create tests prove only the owned VM is removed and `vmbrPxe`, `vmbrTestWan`, `router-recovery`, production VMs, and production bridges are untouched.

### Integration Tests

- Exercise Python GET and POST answer-file behavior using generated assets.
- Evaluate `deploymentHosts.pve-test` without building a full NixOS system.
- Build each selected target asset package independently.
- Run the disposable `pve-test` workflow through normal `lamd deploy`, `--redeploy`, and `destroy` commands.
- Cover successful install, repeated redeploy, interrupted create, missing bridge, unavailable `router-recovery`, failed asset download, invalid manifest, and cleanup after failure.
- Snapshot relevant `pve1` VM, bridge, storage, and cluster state before and after the automated test and compare it for unintended changes.

### Required Commands

Run the commands relevant to the files changed in each phase:

```text
make fmt
cd apps/installer-rs && cargo fmt && cargo test
./tests/test_pve_pxe_integration.sh
```

Use focused Rust tests during development, then run the full installer suite before completion. Also run the relevant Nix evaluations/builds for `deploymentHosts.pve-test`, target asset packages, `router-recovery`, and any changed production router output. Do not use direct `nixos-rebuild` or bare deployment builds that bypass installer workspace and secret preparation.

Hardware-only behavior that automation cannot cover must remain explicitly tracked in Phase 7 rather than being implied by the virtual integration test.

## Definition Of Done

The implementation is complete only when:

- templates are the source of all parameterized Proxmox/PXE text configuration
- reusable assets are pure packages and runtime integration remains in a thin NixOS service module
- installer and recovery credentials never enter the Nix store, process arguments, logs, or restore artifacts
- each install segment has exactly one DHCP owner
- services, portable media, and first boot share a versioned, validated asset contract
- normal hosts depend only on the selected target asset package, not a combined all-target bundle
- router-hosted and portable paths use the same generated assets and Python HTTP server
- `lamd deploy/redeploy/destroy -t pve-test` works without a separate command family
- `installer-rs` validates but never manages the persistent `vmbrPxe` bridge
- production Kea always advertises `next-server = 192.168.1.1`
- `router-main` contains the `pve1` profile, `router-backup` contains the
  `pve2` profile, and only the current VRRP owner serves its configured profile
- `installer-rs` validates but never manages the persistent `vmbrTestWan` bridge
- the automated isolated four-NIC test is repeatable and cannot affect production
- planning helpers, command construction, safety validation, asset generation, failure cleanup, and lifecycle regressions have focused automated coverage
- formatting, relevant linting, Rust tests, Nix evaluations/builds, disposable integration tests, and documented hardware checks pass
- final code passes a refactoring review for duplication, hard-coded policy, module size, and ownership boundaries
- both physical server types have a verified recovery runbook
- temporary credentials are removed or disabled automatically
- no direct production test is required for routine code validation
