set shell := ["bash", "-euo", "pipefail", "-c"]

NXD := env_var_or_default("NXD_BIN", `if [ -x "$HOME/lab/nxd/target/debug/nxd" ]; then echo "$HOME/lab/nxd/target/debug/nxd"; else echo "nix run .#nxd --"; fi`)
NXD_SOURCE := env_var_or_default("NXD_SOURCE", ".#nxdConfigurations.lamt")
NXD_SECRETS_REPO := env_var_or_default("NXD_SECRETS_REPO", env_var("HOME") + "/lamt-secrets")
NXDS := "env DEFAULT_SECRETS_SITE=bar DEFAULT_SECRETS_REPO=\"" + NXD_SECRETS_REPO + "\""

default: switch

# Thin pinned-NXD aliases. NXD owns evaluation, selection, plans, approval,
# retries, provider DAGs, parallel scheduling, output, and verification.
switch *args:
    {{ NXDS }} {{ NXD }} switch {{ args }} --source "{{ NXD_SOURCE }}"

switch-hosts hosts *args:
    {{ NXDS }} {{ NXD }} switch --hosts "{{ hosts }}" --source "{{ NXD_SOURCE }}" {{ args }}

build *args:
    {{ NXDS }} {{ NXD }} build {{ args }} --source "{{ NXD_SOURCE }}"

build-hosts hosts *args:
    {{ NXDS }} {{ NXD }} build --hosts "{{ hosts }}" --source "{{ NXD_SOURCE }}" {{ args }}

boot *args:
    {{ NXDS }} {{ NXD }} boot {{ args }} --source "{{ NXD_SOURCE }}"

test *args:
    {{ NXDS }} {{ NXD }} test {{ args }} --source "{{ NXD_SOURCE }}"

deploy host *args:
    {{ NXDS }} {{ NXD }} deploy "{{ host }}" --source "{{ NXD_SOURCE }}" {{ args }}

plan intent host *args:
    {{ NXDS }} {{ NXD }} plan "{{ host }}" --intent "{{ intent }}" --source "{{ NXD_SOURCE }}" {{ args }}

destroy host *args:
    {{ NXDS }} {{ NXD }} plan "deployment-target/{{ host }}" --intent destroy --source "{{ NXD_SOURCE }}" {{ args }}

convert host from *args:
    {{ NXDS }} {{ NXD }} plan "deployment-target/{{ host }}" --intent convert --convert-from "{{ from }}" --source "{{ NXD_SOURCE }}" {{ args }}

verify host *args:
    {{ NXDS }} {{ NXD }} verify "deployment-target/{{ host }}" --source "{{ NXD_SOURCE }}" {{ args }}

make-approval plan *args:
    {{ NXD }} approval create --plan "{{ plan }}" {{ args }}

apply-plan plan approval *args:
    {{ NXDS }} {{ NXD }} apply "{{ plan }}" --approval "{{ approval }}" {{ args }}

info *args:
    {{ NXDS }} {{ NXD }} info {{ args }} --source "{{ NXD_SOURCE }}"

# One mixed-provider plan replaces consumer JSON export, jq discovery, and
# per-provider plan/apply loops.
plan-pve *args:
    {{ NXDS }} {{ NXD }} plan operation:pve --source "{{ NXD_SOURCE }}" --out .nxd/pve.plan.json {{ args }}

provision-pve *args:
    {{ NXDS }} {{ NXD }} apply .nxd/pve.plan.json {{ args }}

verify-pve *args:
    {{ NXDS }} {{ NXD }} verify operation:pve --source "{{ NXD_SOURCE }}" {{ args }}

plan-pbs *args:
    {{ NXDS }} {{ NXD }} plan operation:pbs --source "{{ NXD_SOURCE }}" --out .nxd/pbs.plan.json {{ args }}

provision-pbs *args:
    {{ NXDS }} {{ NXD }} apply .nxd/pbs.plan.json {{ args }}

verify-pbs *args:
    {{ NXDS }} {{ NXD }} verify operation:pbs --source "{{ NXD_SOURCE }}" {{ args }}

test-pbs-recover:
    {{ NXDS }} NXD_BIN="{{ NXD }}" ./tests/nxd-pbs-recover.sh

plan-vmware *args:
    {{ NXDS }} {{ NXD }} plan operation:vmware --source "{{ NXD_SOURCE }}" --out .nxd/vmware.plan.json {{ args }}

provision-vmware *args:
    {{ NXDS }} {{ NXD }} apply .nxd/vmware.plan.json {{ args }}

verify-vmware *args:
    {{ NXDS }} {{ NXD }} verify operation:vmware --source "{{ NXD_SOURCE }}" {{ args }}

# Import the SSH host identity for a managed host.
import-host-key host *args:
    {{ NXDS }} {{ NXD }} plan "ssh-host-identity/{{ host }}" --host-identity import --source "{{ NXD_SOURCE }}" --auto-apply {{ args }}

# Rotate the SSH host identity for a managed host.
rotate-host-key host *args:
    {{ NXDS }} {{ NXD }} plan "ssh-host-identity/{{ host }}" --host-identity rotate --source "{{ NXD_SOURCE }}" --auto-apply {{ args }}

fmt:
    nix fmt

check: assert-nxd-pin-not-path
    nix flake check

update:
    nix flake update

iso-minimal:
    nix build '.#nixosConfigurations.minimal-iso-x86.config.system.build.isoImage' -o result-iso-x86

iso-minimal-aarch64:
    nix build '.#nixosConfigurations.minimal-iso-aarch64.config.system.build.isoImage' -o result-iso-aarch64

dev-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    nxd_source="$(nix flake archive --json "git+file://${HOME}/lab/nxd" | jq -r .path)"
    nix flake lock --override-input nxd "path:${nxd_source}"

dev-reset:
    #!/usr/bin/env bash
    set -euo pipefail
    git restore flake.lock
    rev="$(git -C "${HOME}/lab/nxd" rev-parse HEAD)"
    nix flake lock --override-input nxd "git+file://${HOME}/lab/nxd?ref=refs/heads/main&rev=${rev}"

assert-nxd-pin-not-path:
    @test "$(jq -r '.nodes.nxd.locked.type' flake.lock)" != path || { echo "run: just dev-reset" >&2; exit 1; }

build-nxd-linux:
    nix build "{{ env_var("HOME") }}/lab/nxd#packages.x86_64-linux.nxd" -L

# Keep only E2E/lifecycle/PXE entrypoints here. Focused checks run directly
# from tests/ so the justfile does not mirror every test executable.
test-e2e:
    {{ NXDS }} NXD_BIN="{{ NXD }}" NXD_FLAKE_INPUT="${NXD_FLAKE_INPUT:-git+file://${HOME}/lab/nxd}" ./tests/nxd-config-export.sh
    nix-instantiate --eval --strict tests/nxd-infra-defaults.nix
    ./tests/nxd-pve-pxe-security.sh
    {{ NXDS }} NXD_BIN="{{ NXD }}" ./tests/nxd-guest-plan-medo.sh
    {{ NXDS }} NXD_BIN="{{ NXD }}" ./tests/nxd-pve-inventory.sh
    {{ NXDS }} NXD_BIN="{{ NXD }}" ./tests/nxd-pbs-inventory.sh
    ./tests/nxd-headscale-rest.sh
    ./tests/lib/timing-summary.sh .nxd/test-timings/timings.jsonl 6

test-lifecycle:
    NXD_BIN="{{ NXD }}" ./tests/nxd-guest-lifecycle.sh

test-install:
    NXD_BIN="{{ NXD }}" ./tests/nxd-disposable-install.sh

# Exact target is deliberately required: this live proof never chooses a
# disposable machine by fallback. The glob lane refuses fewer than two targets.
test-switch target:
    {{ NXDS }} NXD_BIN="{{ NXD }}" NXD_SWITCH_TARGET="{{ target }}" ./tests/nxd-disposable-switch.sh

test-pxe:
    nix-instantiate --eval --strict tests/nxd-pve-pxe-assets.nix
    ./tests/nxd-pve-pxe-security.sh
    NXD_BIN="{{ NXD }}" ./tests/nxd-pve-pxe.sh
