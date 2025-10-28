#!/usr/bin/env bash
# Remote installer script that runs on the target machine.
# This script is executed by the orchestrator.

# set -euxo pipefail to debug
set -euxo pipefail

# --- Globals and Setup ---

# Apply low memory optimizations if enabled
if [[ "${DO_LOW_MEM:-no}" == "yes" ]]; then
  export GC_INITIAL_HEAP_SIZE=1M
  export GC_DONT_GC=1
  export NIX_DISABLE_AUTO_GC=1
  export TMPDIR=/var/tmp
fi

# Source Nix profile if available
# shellcheck source=/dev/null
[[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]] && . "$HOME/.nix-profile/etc/profile.d/nix.sh"

# Low memory optimization options
LOW_MEM_BUILD_OPTIONS="--option cores 1 --option max-jobs 1 --option max-free 0 --option gc-keep-derivations false --option gc-keep-outputs false --option auto-optimise-store false"

# --- Helper Functions ---

log() {
	echo "[$(date '+%H:%M:%S')] \"$*\""
}

run_cmd() {
	if command -v sudo >/dev/null 2>&1 && [[ $EUID -ne 0 ]]; then
		sudo "$@"
	else
		"$@"
	fi
}

execute_disko_script() {
	local script_path="$1"
	if [[ $EUID -eq 0 ]]; then
		log "Executing disko script: $script_path"
		"$script_path"
	else
		log "Executing disko script with sudo: $script_path"
		sudo "$script_path"
	fi
}

build_flake_attr() {
    local flake_attr="$1"
    log "Building flake attribute: $flake_attr"

    local nix_cmd="nix build"
    if [[ "${DO_LOW_MEM:-no}" == "yes" ]]; then
        nix_cmd="$nix_cmd $LOW_MEM_BUILD_OPTIONS"
    fi
    nix_cmd="$nix_cmd --extra-experimental-features nix-command,flakes .#$flake_attr"

    log "Nix command: $nix_cmd"
    log "Disk status before build: $(df -h /nix)"

    if ! $nix_cmd; then
        log "ERROR: Failed to build $flake_attr."
        log "Disk status after failure: $(df -h /nix)"
        exit 1
    fi

    local build_path
    build_path=$(readlink result)
    rm result
    echo "$build_path"
}

build_disko_script() {
	log "Building disko script for $FLAKE_HOST..."
	log "Current directory: $(pwd)"
	log "Flake config attr: $FLAKE_CONFIG_ATTR"
	local disko_script_path
 	disko_script_path=$(build_flake_attr "$FLAKE_CONFIG_ATTR.config.system.build.diskoScript")
	log "Disko script built at $disko_script_path"
 	execute_disko_script "$disko_script_path"
}

# --- Installation Stage Functions ---

install_stage0_full() {
  log "--- Stage 0: Full Install ---"
  if [[ "$BUILD_ON" == "local" ]]; then
    log "Using pre-built closures from local build."
    # The disk is already partitioned and mounted by the DISKO_ONLY step
    [[ -z "${SYSTEM_CLOSURE:-}" ]] && log "ERROR: SYSTEM_CLOSURE not provided for local build." && exit 1
    log "Installing with pre-built system closure..."
    nixos-install --no-root-password --no-channel-copy --system "$SYSTEM_CLOSURE"
    mkdir -p "/mnt/root/$NIXCFG"
    cp /tmp/installer-staging/repo/flake.lock "/mnt/root/$NIXCFG/" || true
  else
    log "Performing remote build on target."
    cd /tmp/installer-staging/repo
    build_disko_script

    log "Building system closure..."
    local system_closure
    system_closure=$(build_flake_attr "$FLAKE_CONFIG_ATTR.config.system.build.toplevel")

    log "Installing NixOS with the new system closure..."
    nixos-install --no-root-password --no-channel-copy --system "$system_closure"
  fi
}

install_stage0_minimal() {
	log "--- Stage 0: Minimal Staged Install ---"
	if [[ "$BUILD_ON" == "local" ]]; then
		log "Using pre-built disko script from local build."
		[[ -z "${DISKO_SCRIPT:-}" ]] && log "ERROR: DISKO_SCRIPT not provided for local build." && exit 1
		execute_disko_script "$DISKO_SCRIPT"
	else
		log "Performing remote build of disko script on target."
		cd /tmp/installer-staging/repo
		build_disko_script
	fi

	log "Generating hardware configuration..."
	nixos-generate-config --force --root /mnt

	log "Copying extra configuration files..."
	cp /tmp/installer-staging/extra-config.nix /mnt/etc/nixos/
	cp /tmp/installer-staging/repo/defines.nix /mnt/etc/nixos/
	cp /tmp/installer-staging/repo/modules/os/linux/autorun/zramswap.nix /mnt/etc/nixos/
	sed -i '/hardware-configuration.nix/a ./extra-config.nix' /mnt/etc/nixos/configuration.nix

	log "Copying repository to /mnt/root for Stage 1..."
	mkdir -p /mnt/root
	cp -r /tmp/installer-staging/repo /mnt/root/lamt-nixconfig

	log "Setting up known hosts for root user..."
	if ! test -f /mnt/root/.ssh/known_hosts; then
		mkdir -p /mnt/root/.ssh
		ssh-keyscan -H tea.lamhub.com >/mnt/root/.ssh/known_hosts || true
	fi

	log "Installing minimal NixOS system..."
	local rev
	rev=$(nix run nixpkgs#jq -- -r '.nodes.nixpkgs.locked.rev' /mnt/root/lamt-nixconfig/flake.lock 2>/dev/null || echo "")

	local nixpkgs_url
	if [[ -n "$rev" && "$rev" != "null" ]]; then
		nixpkgs_url="https://github.com/NixOS/nixpkgs/archive/${rev}.tar.gz"
		log "Using nixpkgs revision from flake.lock: $rev"
	else
		nixpkgs_url="https://github.com/NixOS/nixpkgs/archive/nixos-24.05.tar.gz" # Stable fallback
		log "Warning: Could not get nixpkgs revision from flake.lock. Using fallback: $nixpkgs_url"
	fi

	log "Running nixos-install..."
	NIX_PATH="nixpkgs=${nixpkgs_url}" nixos-install --no-root-password --no-channel-copy
}

install_stage1_switch() {
	log "--- Stage 1: Switching to Full System ---"
	# The repository was copied to /root/lamt-nixconfig during stage 0.
	# After reboot, we are running on the newly installed minimal system.
	cd /root/lamt-nixconfig

	log "Building and switching to the full system configuration..."
	local rebuild_cmd="nixos-rebuild switch"
	if [[ "${DO_LOW_MEM:-no}" == "yes" ]]; then
		rebuild_cmd="$rebuild_cmd $LOW_MEM_REBUILD_OPTIONS"
	fi
	rebuild_cmd="$rebuild_cmd --flake .#$FLAKE_HOST"
	if ! $rebuild_cmd; then
		log "ERROR: Failed to switch to the full system."
		exit 1
	fi
}

# --- Main Execution ---

# Handle DISKO_ONLY mode for local builds to prepare for large nix copy
if [[ "${DISKO_ONLY:-no}" == "yes" ]]; then
    log "--- DISKO_ONLY mode: Partitioning disk and setting up overlay ---"

    if [[ -f /mnt/etc/nixos/hardware-configuration.nix ]]; then
        log "Disko appears to be done, skipping partitioning."
    else
        log "Using pre-built disko script from local build."
        [[ -z "${DISKO_SCRIPT:-}" ]] && log "ERROR: DISKO_SCRIPT not provided for local build." && exit 1
        execute_disko_script "$DISKO_SCRIPT"
    fi



    log "--- DISKO_ONLY mode finished successfully ---"
    exit 0
fi

# Set defaults for variables passed from orchestrator
: "${STAGE:=0}"
: "${DO_FULL:=no}"
: "${BUILD_ON:=remote}"
: "${FLAKE_HOST:=${FLAKE##*.#}}"

log "--- Remote Installer Starting ---"
log "Host:         $FLAKE_HOST"
log "Stage:        $STAGE"
log "Full Install: $DO_FULL"
log "Build on:     $BUILD_ON"
log "---------------------------------"

case "$STAGE" in
"0")
	if [[ "$DO_FULL" == "yes" ]]; then
		install_stage0_full
	else
		install_stage0_minimal
	fi
	;;
"1")
	if [[ "$DO_FULL" == "yes" ]]; then
		log "Stage 1 is not required for a full install. Skipping."
	else
		install_stage1_switch
	fi
	;;
*)
	log "ERROR: Invalid stage: '$STAGE'. Must be 0 or 1."
	exit 1
	;;
esac

log "--- Remote Installer Finished Successfully ---"
