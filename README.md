# lamt-nixconfig

Declarative NixOS, nix-darwin, Home Manager, and WSL configuration for a real
multi-site environment — plus the infrastructure underneath it: Proxmox VE
hypervisors, a Proxmox Backup Server appliance, VMware guests, and a
self-hosted tailnet control plane.

This is a **consumer repository** for [NXD](https://github.com/lamtt77/nxd), a
reconciliation engine that evaluates Nix-authored desired state into a
canonical specification, plans changes as one dependency-ordered graph across
every provider, and applies them only against a plan digest you approved.

If you arrived from [Introducing NXD](https://blog.lamhub.com/posts/introducing-nxd/)
and wanted to read configuration rather than prose, this is that configuration.

> **Pre-release.** NXD interfaces still change between revisions. This
> repository pins an exact NXD revision and moves it deliberately.

## Contents

- [Contents](#contents)
- [What you get](#what-you-get)
- [What is where](#what-is-where)
- [Prerequisites](#prerequisites)
- [Getting set up per platform](#getting-set-up-per-platform)
  - [macOS (nix-darwin)](#macos-nix-darwin)
  - [NixOS](#nixos)
  - [WSL (Windows Subsystem for Linux)](#wsl-windows-subsystem-for-linux)
- [Everyday use](#everyday-use)
  - [Naming a target](#naming-a-target)
  - [Choosing the source flake](#choosing-the-source-flake)
  - [Reviewing before applying](#reviewing-before-applying)
  - [Installing and converting](#installing-and-converting)
  - [Infrastructure operations](#infrastructure-operations)
- [Infrastructure and cloud](#infrastructure-and-cloud)
  - [Proxmox](#proxmox)
  - [DigitalOcean](#digitalocean)
  - [Bare metal](#bare-metal)
- [Developing against a local NXD](#developing-against-a-local-nxd)
- [Secrets and host keys](#secrets-and-host-keys)
- [Rules this repository follows](#rules-this-repository-follows)
- [Maintenance](#maintenance)
- [Checks](#checks)

## What you get

- **One command surface.** `nxd` drives local switches, remote switches,
  destructive installs, fleet plans, and provider lifecycle actions. There is no
  second tool for "the infrastructure part."
- **Review before it runs.** Every change can be planned to a file, read, and
  applied only against that exact plan digest. Destructive and identity-critical
  actions are listed first.
- **Smart build placement.** Builds run locally, on a remote builder, natively on
  the target, cross-compiled, or — for low-memory hosts — evaluated on the
  orchestrator and realized on the target.
- **Parallel fleet operations.** Multi-host work runs concurrently with isolated
  logs and per-host secret inputs, bounded by `--parallel`.
- **Fast planning.** Lightweight `hosts/<name>/meta.nix` data is exported as
  canonical resources, so planning one host does not evaluate every NixOS system
  in the site.
- **Secret-aware.** Host SOPS files are staged as separate store inputs, with SSH
  host keys aligned to age recipients. Nothing sensitive reaches a Nix store path.
- **Headless infrastructure.** Proxmox provisioning, DigitalOcean droplets, kexec
  takeovers, Disko installs, and tailnet enrollment come from the same CLI.

## What is where

| Path | Contains |
| --- | --- |
| `hosts/` | Per-host declarations — hardware, disk layout, role, deployment settings |
| `infra/` | Site topology: clusters, nodes, guests, storage, network |
| `nxd/` | Projection into NXD's resource model — providers, operations, identities, secret bindings |
| `modules/` | Reusable feature modules shared across hosts |
| `pkgs/` | Local packages, including the Nix-built blog and site |
| `tests/` | Consumer boundary and security checks |

The `nxd/` directory is a *projection*, not a second source of truth. Endpoints,
VM IDs, storage, and policy are authored once in `hosts/` and `infra/`.

## Prerequisites

- **Orchestrator** — any machine with Nix installed and SSH access to the target.
- **Target for `switch`** — an already-managed NixOS, nix-darwin, Home Manager, or
  WSL host.
- **Target for `install`** — a machine booted from the
  [NixOS minimal ISO](https://nixos.org/download/), or a running Linux system that
  can be taken over with kexec (an Ubuntu cloud image, for example).
- **Secrets** — hosts using SOPS resolve the private secrets repository from
  `DEFAULT_SECRETS_REPO`, falling back to `$HOME/lamt-secrets` or a sibling
  `../lamt-secrets`. `DEFAULT_SECRETS_SITE` selects the site. The `justfile` sets
  both.

## Getting set up per platform

### macOS (nix-darwin)

Install Nix — the [Determinate installer](https://determinate.systems/posts/determinate-nix-installer/)
is the smoothest path on macOS:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Then apply the configuration to the machine you are sitting at:

```bash
just switch self          # the operator machine
just switch macair15-m2   # or by name, from anywhere
```

`self` and `current` both mean "this machine", which is what you usually want on
a laptop.

### NixOS

A managed host is switched by name from any orchestrator:

```bash
just switch <host>
```

A *new* machine is installed rather than switched. Boot it from the minimal ISO,
make it reachable over SSH, then:

```bash
just deploy <host>
```

An existing Linux machine that cannot be booted from media is taken over in
place with kexec:

```bash
nxd plan --intent convert --source '.#nxdConfigurations.lamt' ...
```

`medo` — the 1 GB DigitalOcean droplet serving the blog and project site — was
created from an Ubuntu image and converted this way.

### WSL (Windows Subsystem for Linux)

1. Enable **WSL 2** and the **Windows OpenSSH Server** on the Windows host.
2. Authorize your workstation key so the orchestrator can reach it over SSH.
3. Then:

```bash
just deploy wsl    # first time
just switch wsl    # updates thereafter
```

An offline installer artifact can be built for a machine with no network path
to the orchestrator:

```bash
nxd artifact build minimal-wsl --source '.#nxdConfigurations.lamt'
```

## Everyday use

The `justfile` holds thin aliases over stable NXD routes. NXD owns evaluation,
selection, planning, approval, scheduling, and verification — the recipes add
no logic of their own.

```bash
# Inspect without composing mutation providers
nxd validate --source '.#nxdConfigurations.lamt'
nxd show config --source '.#nxdConfigurations.lamt'

# Day-2 lifecycle for one host
just build <host>
just test <host>
just switch <host>
just verify <host>

# Several hosts, via canonical selectors rather than a shell loop
just switch-hosts "avon utils"
```

### Naming a target

Commands that take a target accept a flexible spec:

```
[user@]hostname[=ip]
```

| Form | Meaning |
| --- | --- |
| `avon` | By name; the endpoint is discovered |
| `self` / `current` | The machine you are typing on |
| `nixos@avon` | Override the SSH user |
| `avon=192.168.1.18` | Force the endpoint, skipping discovery |
| `nixos@avon=192.168.1.18` | Both |

Omitting the target entirely means the current host. The `=ip` form is what you
want when a machine has moved, or when discovery cannot reach it yet.

### Choosing the source flake

`--source <flake-ref>#<output>` selects what is evaluated. The `justfile`
defaults to `.#nxdConfigurations.lamt`; `NXD_SOURCE` overrides it.

```bash
# This checkout
just switch avon

# Explicitly, or from another checkout
nxd switch avon --source '.#nxdConfigurations.lamt'

# Straight from GitHub, before a local clone exists
nix run github:lamtt77/nxd#nxd -- switch avon \
  --source 'github:lamtt77/lamt-nixconfig#nxdConfigurations.lamt'
```

Running from a remote flake is mainly for first bootstrap or remote execution.
A managed machine already has `nxd` from its own switched configuration.

### Reviewing before applying

For anything you want to read before it runs, persist the plan and approve it
explicitly:

```bash
just plan switch <host> --out .nxd/host.plan.json
# read the plan, then:
just make-approval .nxd/host.plan.json --out .nxd/approval.json
just apply-plan .nxd/host.plan.json .nxd/approval.json
```

Approval binds to that exact plan digest. If the configuration changes in
between, the digest stops matching and the apply refuses. Interactive
confirmation defaults to **no**, and non-interactive mutation always requires
independently created approval evidence.

### Installing and converting

`just deploy <target>` is the interactive create/reinstall/replace route.
Automation uses the explicit form:

```bash
nxd plan --intent install --install-mode create|reinstall|replace ...
```

`--intent convert` takes over an existing Linux machine in place via kexec.
`medo`, the 1 GB DigitalOcean droplet serving the blog and project site, was
created from an Ubuntu image and converted this way.

> **An install can wipe the target's disk.** Plan it and read the plan first.
> Destructive and identity-critical actions are listed before anything else.

#### What an install actually does

1. **Partitions the disk** with Disko, under `/mnt` on the target.
2. **Builds the system**, wherever [build placement](https://nxd.lamhub.com/manual/how-to/build-placement.html) resolves to.
3. **Installs the closure** onto `/mnt`.
4. **Stages credentials** — SSH host key, SOPS material, and the tailnet
   authentication key — so the machine can decrypt its own secrets on first boot.
5. **Restages host identity** after `nixos-install`, in case activation rewrote
   `/mnt/etc`.
6. **Reboots and reports the final endpoint** once the provider can observe it.

A running non-NixOS machine is taken over with kexec instead of a reboot into
installer media, which is what makes converting a cloud image possible without
console access.

### Infrastructure operations

Provider-owned infrastructure is selected through named operation sets rather
than by touching providers directly:

```bash
just plan-pve      # review .nxd/pve.plan.json
just provision-pve
just verify-pve

just plan-pbs      # review .nxd/pbs.plan.json
just provision-pbs
just verify-pbs

just plan-vmware
```

## Infrastructure and cloud

### Proxmox

Guest lifecycle is declarative: multi-NIC layouts, static addressing and VLAN
tags for environments without DHCP, and cloud-init seeding all come from host
metadata rather than the web UI.

```bash
just deploy avon              # provision and bootstrap from metadata
nxd info avon --ip            # endpoint of a running guest
```

Removing a disposable guest uses `--intent destroy`, which is guarded by exact
target identity so it cannot act on the wrong machine.

A NixOS ISO must be present on Proxmox storage for install routes. NXD also
produces PXE installer assets, so a machine can install over the network with
no media at all.

### DigitalOcean

Droplets are created and then converted to NixOS with kexec — no custom image
required. `medo` runs this way on a 1 GB droplet.

### Bare metal

`modules.os.feat.linux.services.refind-booter` builds a rEFInd boot image for
machines that cannot boot NVMe natively, such as an R720:

```bash
nix build '.#nixosConfigurations.<host>.config.system.build.refindBootImg'
sudo dd if=result of=/dev/sdX bs=1M status=progress
```

For network installs, see the [cold recovery and PXE](https://nxd.lamhub.com/manual/explanation/installation.html)
section of the NXD manual.

## Developing against a local NXD

Point `NXD_BIN` at a debug build to iterate without touching the lock:

```bash
export NXD_BIN="$HOME/lab/nxd/target/debug/nxd"
just plan switch <host> --out .nxd/host.plan.json
```

The lock is never refreshed implicitly:

- `just dev-setup` — only when evaluation must see unreleased NXD Nix, schema,
  or package inputs, and a full rebuild is acceptable.
- `just dev-reset` — re-pin to NXD's current revision. **Run this before
  deploying if you have changed NXD**, or the deploy will build the old pin.

`.nxd/` holds regenerated, gitignored plans and local state.

## Secrets and host keys

Secret *values* live in a separate encrypted repository. This one carries binding
references only, so it stays publishable.

During installation NXD stages the host's SOPS file as its own store input and
keeps SSH host keys aligned with age recipients, so a freshly installed machine
can decrypt its own secrets on first boot — no manual key scanning, no re-keying
loop. In outline it:

1. Generates the target's SSH host key locally if it is missing.
2. Derives the matching age key from it.
3. Checks the host and key are registered as recipients in the secrets repository.
4. Stops and asks if a recipient is missing or a host key does not match, rather
   than guessing which side is correct.

Step 4 is deliberate: silently overwriting either side is how a machine ends up
unable to decrypt its own secrets.

## Rules this repository follows

- **Secrets never appear here.** Values live in a separate encrypted store;
  configuration carries binding references only, and nothing sensitive reaches
  a Nix store path.
- **No side channels.** Not `nixos-rebuild`, not provider binaries, not
  SSH or vendor UIs, not hand-edited plan JSON — changes go through NXD
  planning and verification so that what ran is what was reviewed.
- **No destroying a durable target** without exact owner approval for that
  target and that action.
- `pbs-r720` is a PBS appliance, not a NixOS deployment target. Its topology is
  authored in `infra/site.nix` and its lifecycle uses the PVE/PBS routes above.

## Maintenance

Garbage collection and store optimization run weekly on their own, for system
*and* user/Home Manager profiles, configured in
`modules/os/base/services/maintenance.nix` — via `nix.gc.automatic` and
`auto-optimise-store` on NixOS, and a root `launchd` daemon on macOS.

To reclaim space immediately rather than waiting for the schedule:

```bash
nix-collect-garbage --delete-older-than 14d        # your user profile
sudo nix-collect-garbage --delete-older-than 14d   # system generations
nix-store --optimise                               # deduplicate the store
```

## Checks

```bash
just test-e2e     # consumer boundary
just test-pxe     # PXE retirement invariants
./tests/nxd-pve-pxe-security.sh

nix build .#nxd && nix run '.#nxd' -- --version
```

Engine and provider changes belong in the
[NXD repository](https://github.com/lamtt77/nxd), not here.
