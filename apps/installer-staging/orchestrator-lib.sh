#!/usr/bin/env bash
# Local orchestration library for installer-staging
# Provides SSH management, file transfer, build coordination, and kexec handling

set -euxo pipefail

#
# Global variables (set by orchestrator)
#
# FLAKE, TARGET_HOST, etc. are exported from the main script
SYSTEM_CLOSURE=""
DISKO_SCRIPT=""
TMPDIR_OVERRIDE="/tmp"

#
# Logging and Utility Functions
#
log() {
	local level="$1"
	local message="$2"
	local timestamp
	timestamp=$(date "+%Y-%m-%d %H:%M:%S")

	case "$level" in
	error) echo "[$timestamp] ERROR: $message" >&2 ;;
	warn) echo "[$timestamp] WARN: $message" >&2 ;;
	info) echo "[$timestamp] INFO: $message" ;;
	debug)
		if [[ "$LOG_LEVEL" == "debug" ]]; then
			echo "[$timestamp] DEBUG: $message"
		fi
		;;
	*) echo "[$timestamp] $message" ;;
	esac
}

log_and_exit() {
	log "$1" "$2"
	exit 1
}

cleanup_temp_files() {
	local files=($@)
	for file in "${files[@]}"; do
		[[ -f "$file" ]] && rm -f "$file" && log debug "Cleaned up: $file"
	done
}

# Helper to get current system
get_current_system() {
    local current_arch
    current_arch=$(uname -m | sed 's/arm64/aarch64/')
    local current_os
    current_os=$(uname -s | tr '[:upper:]' '[:lower:]')
    echo "$current_arch-$current_os"
}

# Helper to parse target system from flake.nix
get_target_system() {
    local flake_file="./flake.nix"
    if [[ -f "$flake_file" ]]; then
        grep -A 10 "$FLAKE_HOST = mkSystem" "$flake_file" | grep -o 'system = "[^"]*"' | sed 's/system = "\(.*\)"/\1/' | head -1 || echo ""
    fi
}

# Helper to detect config type (darwin, nixos, or cross)
detect_config_type() {
    local flake_file="./flake.nix"
    if [[ -f "$flake_file" ]]; then
        # Search for the host in order, preferring cross for nixos if available
        if grep -A 10 "crossNixosConfigurations = {" "$flake_file" | grep -q "$FLAKE_HOST = mkSystem"; then
            echo "crossNixosConfigurations"
        elif grep -A 10 "darwinConfigurations = {" "$flake_file" | grep -q "$FLAKE_HOST = mkSystem"; then
            echo "darwinConfigurations"
        elif grep -A 10 "nixosConfigurations = {" "$flake_file" | grep -q "$FLAKE_HOST = mkSystem"; then
            echo "nixosConfigurations"
        else
            echo "nixosConfigurations"  # Default fallback
        fi
    else
        echo "nixosConfigurations"
    fi
}

# Resolve BUILD_ON=auto based on cross-compilation needs
resolve_build_on_auto() {
	if [[ "$BUILD_ON" == "auto" ]]; then
		local target_system=""
		target_system=$(get_target_system)
		if [[ -z "$target_system" ]]; then
			log info "Could not parse system from flake.nix, falling back to remote build"
		fi
		local current_system
		current_system=$(get_current_system)

		log info "Auto-detecting build mode..."
		log info "Current system: $current_system"

		if [[ -n "$target_system" ]]; then
			log info "Target system: $target_system"
			local config_type
			config_type=$(detect_config_type)
			if [[ "$target_system" == "$current_system" ]]; then
				log info "Systems match - using local build"
				BUILD_ON="local"
				FLAKE_CONFIG_ATTR="nixosConfigurations.$FLAKE_HOST"
			else
				log info "Cross-compilation required: $current_system → $target_system"
				log info "Systems differ - using local build for cross-compilation"
				BUILD_ON="local"
				FLAKE_CONFIG_ATTR="${config_type}.$FLAKE_HOST"
			fi
		else
			log info "Could not evaluate target system - using remote build for safety"
			BUILD_ON="remote"
			FLAKE_CONFIG_ATTR="nixosConfigurations.$FLAKE_HOST"  # Default to NixOS for remote
		fi
	fi
}

#
# Remote Command Helpers
#
ssh_target() {
	ssh -n -i "$HOME/.ssh/id_installer" $SSH_OPTIONS "$TARGET_HOST" "$@"
}

#
# Main Orchestration Steps
#

# 1. SSH Connection Management
establish_ssh() {
	log info "Setting up SSH connection to $TARGET_HOST"
	mkdir -p ~/.ssh
	[[ ! -f "$SSH_KEY_FILE" ]] && ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -C "installer-staging" >/dev/null

	SSH_HOST="${TARGET_HOST#*@}"
	KEXEC_USER="root"
	[[ -n "${GITHUB_TOKEN:-}" ]] && export GITHUB_TOKEN

	log info "Testing SSH connection and copying key..."
	local retries=0
	while ! ssh_target true 2>/dev/null; do
		((retries++))
		[[ $retries -gt 3 ]] && log_and_exit error "Cannot establish SSH connection to $TARGET_HOST."

		log warn "SSH connection attempt $retries failed, trying ssh-copy-id..."
		command -v ssh-copy-id >/dev/null && ssh-copy-id -i "$SSH_KEY_FILE" $SSH_OPTIONS "$TARGET_HOST" 2>/dev/null || true
		sleep 2
	done
	log info "SSH connection established."
}

# 2. File Transfer Coordination
transfer_files() {
	if [[ "$STAGE" != "0" ]]; then
		log info "Skipping repository transfer for Stage $STAGE."
		return 0
	fi
	log info "Transferring files to target..."
	if [[ "$BUILD_ON" == "remote" ]]; then
		install_nix_on_target
	fi

	log info "Transferring repository..."
	ssh_target "mkdir -p $REMOTE_TMP_DIR" || log_and_exit error "Failed to create remote directory $REMOTE_TMP_DIR"
	tar -czf /tmp/repo.tar.gz $FLAKE_EXCLUDE . || log_and_exit error "Failed to create repository archive"
	scp -i "$SSH_KEY_FILE" $SSH_OPTIONS "/tmp/repo.tar.gz" "$TARGET_HOST:$REMOTE_TMP_DIR/repo.tar.gz" || log_and_exit error "Failed to transfer repository archive"
	ssh_target "cd $REMOTE_TMP_DIR && mkdir -p repo && cd repo && tar -xzf ../repo.tar.gz && rm ../repo.tar.gz" || log_and_exit error "Failed to extract repository archive"
	cleanup_temp_files "/tmp/repo.tar.gz"

	local flake_lock_src=""
	if [[ -f "hosts/$FLAKE_HOST/flake.lock" ]]; then
		flake_lock_src="hosts/$FLAKE_HOST/flake.lock"
	elif [[ -f "flake.lock" ]]; then
		flake_lock_src="flake.lock"
	fi

	if [[ -n "$flake_lock_src" ]]; then
		log info "Copying host-specific lock file to target: $flake_lock_src"
		scp -i "$SSH_KEY_FILE" $SSH_OPTIONS "$flake_lock_src" "$TARGET_HOST:$REMOTE_TMP_DIR/repo/flake.lock" || log_and_exit error "Failed to copy flake.lock"
	else
		log info "No host-specific lock file found. A new one will be generated on the target."
	fi

	log info "File transfer completed."
}

install_nix_on_target() {
    log info "Checking Nix installation on target"
    local remote_script
    remote_script=$(cat <<EOF
if ! command -v nix >/dev/null 2>&1; then
    echo "Nix not found on target, installing Nix..."
    curl -L "${NIX_INSTALL_URL}" | sh
    # shellcheck source=/dev/null
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
else
    echo "Nix already installed on target."
fi
EOF
)
    ssh_target "$remote_script"
}

# 3. Build Coordination
build_and_copy_disko_locally() {
	log info "Building disko script locally..."
	export NIX_SSHOPTS="$SSH_OPTIONS -i $HOME/.ssh/id_installer"
	local local_cores_arg=$([[ "$LOW_MEM" == "yes" ]] && echo "--cores 1" || echo "")

	local disko_build_output
	local exit_code=0
	# Capture stderr to a temp file to show on failure
  disko_build_output=$(nix build --extra-experimental-features nix-command --extra-experimental-features flakes $local_cores_arg --print-out-paths --no-link --show-trace ".#$FLAKE_CONFIG_ATTR.config.system.build.diskoScript") || exit_code=$?
	if [[ $exit_code -ne 0 ]]; then
		log "error" "Nix build for disko script failed."
		exit 1
	fi
	DISKO_SCRIPT=$disko_build_output
	[[ -z "$DISKO_SCRIPT" ]] && log_and_exit error "Local disko script build failed (output was empty)."
	log info "Copying disko script to target..."
		local substitute_flag=$([[ "$SUBS_ON_DEST" == "yes" ]] && echo "--substitute-on-destination" || echo "")
	nix copy --extra-experimental-features nix-command --extra-experimental-features flakes $substitute_flag --to "ssh://$TARGET_HOST?compress=true" "$DISKO_SCRIPT" || log_and_exit error "Failed to copy disko script."
}

build_and_copy_system_locally() {
	log info "Building system closure locally..."
	export NIX_SSHOPTS="$SSH_OPTIONS -i $HOME/.ssh/id_installer"
	local local_cores_arg=$([[ "$LOW_MEM" == "yes" ]] && echo "--cores 1" || echo "")

	if [[ "$DO_FULL" == "yes" ]]; then
		local system_build_output
		exit_code=0
    system_build_output=$(nix build --extra-experimental-features nix-command --extra-experimental-features flakes $local_cores_arg --print-out-paths --no-link --show-trace ".#$FLAKE_CONFIG_ATTR.config.system.build.toplevel") || exit_code=$?
		if [[ $exit_code -ne 0 ]]; then
			log "error" "Nix build for system closure failed."
			exit 1
		fi
		SYSTEM_CLOSURE=$system_build_output
		[[ -z "$SYSTEM_CLOSURE" ]] && log_and_exit error "Local system closure build failed (output was empty)."
		log info "Copying system closure to target..."
	local substitute_flag=$([[ "$SUBS_ON_DEST" == "yes" ]] && echo "--substitute-on-destination" || echo "")
		nix copy --extra-experimental-features nix-command --extra-experimental-features flakes $substitute_flag --to "ssh://$TARGET_HOST?remote-store=local?root=/mnt&compress=true" "$SYSTEM_CLOSURE" || log_and_exit error "Failed to copy system closure."
	fi
}

# 4. Kexec Bootstrap Handling
handle_kexec() {
	if ! ssh_target "grep -q 'ID=nixos' /etc/os-release 2>/dev/null" &&
		([[ "$KEXEC_BOOT" == "yes" ]] || ([[ "$KEXEC_BOOT" == "auto" ]] && ! ssh_target "command -v nixos-install >/dev/null 2>&1" 2>/dev/null)); then
		log info "Kexec boot required, preparing..."
		local arch
		arch=$(ssh_target "uname -m")
		case "$arch" in
		x86_64 | aarch64)
			KEXEC_URL="$KEXEC_BASE_URL-${arch}-linux.tar.gz"
			;;
		*)
			log_and_exit error "Unsupported architecture for kexec: $arch"
			;;
		esac

		download_kexec_bundle
		execute_kexec

		log info "Waiting for kexec reboot..."
		sleep 15
		TARGET_HOST="${KEXEC_USER}@${SSH_HOST}" # Switch to root user for NixOS installer

		local retries=0
		set +e
		while true; do
			if ssh_target true 2>/dev/null; then
				break
			fi
			((retries++))
			[[ $retries -gt 60 ]] && log_and_exit error "Target did not come back online after kexec."
			log info "Waiting for target to reboot... ($retries/60)"
			sleep 5
		done
		set -e

		log info "Kexec completed, target is back online."
		# Enable ZRAM swap immediately post-kexec for LOW_MEM
		if [[ "$LOW_MEM" == "yes" ]]; then
			ssh_target "
				if modprobe zram 2>/dev/null; then
					echo 1 > /sys/block/zram0/reset 2>/dev/null || true
					echo 1073741824 > /sys/block/zram0/disksize 2>/dev/null || true
					mkswap /dev/zram0 >/dev/null 2>&1 || true
					swapon /dev/zram0 >/dev/null 2>&1 || true
					echo 'ZRAM swap enabled post-kexec: \$(free -h | grep Swap)'
				else
					echo 'WARN: ZRAM module not available post-kexec'
				fi
			"
		fi
	else
		log info "Skipping kexec (not needed or disabled)."
	fi
}

download_kexec_bundle() {
    log info "Downloading kexec bundle"
    local remote_script
    remote_script=$(cat <<EOF
echo "Downloading kexec bundle from ${KEXEC_URL}..."
export TMPDIR="${TMPDIR_OVERRIDE}"
cd "\$TMPDIR" || exit 1
curl -L "${KEXEC_URL}" -o kexec.tar.gz
tar -xzf kexec.tar.gz

if [[ "${LOW_MEM}" == "yes" ]]; then
    echo "Optimizing initrd for low memory..."
    if gzip -t kexec/initrd 2>/dev/null; then
        chmod +w kexec/initrd
        mkdir -p initrd_tmp && cd initrd_tmp
        gzip -dc ../kexec/initrd | cpio -id 2>/dev/null || true
        rm -rf var/log/* usr/share/doc/* 2>/dev/null || true
        find . -name '*.deb' -delete 2>/dev/null || true
        find . -type f -size +1M -delete 2>/dev/null || true
        find . 2>/dev/null | cpio -o -H newc 2>/dev/null | gzip -9 >../kexec/initrd || true
        cd .. && rm -rf initrd_tmp
    fi
fi
EOF
)
    ssh_target "$remote_script"
}

execute_kexec() {
    log info "Executing kexec"
    local remote_script
    remote_script=$(cat <<EOF
if [[ "${LOW_MEM}" == 'yes' ]]; then
    if df / | awk 'NR==2 {if (\$4 > 5242880) exit 0; else exit 1}'; then
        sudo fallocate -l 2G /swapfile || true
        sudo chmod 600 /swapfile || true
        sudo mkswap /swapfile || true
        sudo swapon /swapfile || true
    fi
    sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'
    free -h
    sed -i 's/zswap.enabled=1/zswap.enabled=0/' "${TMPDIR_OVERRIDE}/kexec/run"
    # Increase tmpfs size to prevent "No space left on device" during builds
    sed -i 's/--command-line "/--command-line "initrd.tmpfs.size=75% /' "${TMPDIR_OVERRIDE}/kexec/run"
fi

echo "Executing kexec..."
cd "${TMPDIR_OVERRIDE}/kexec" || exit 1
sudo ./run
EOF
)
    ssh_target "$remote_script"
}

# 5. Remote Execution Orchestration
execute_installation() {
	log info "Copying installer scripts to target..."
	scp -i "$HOME/.ssh/id_installer" $SSH_OPTIONS \
		"./apps/installer-staging/remote-installer.sh" "./apps/installer-staging/extra-config.nix" \
		"$TARGET_HOST:$REMOTE_TMP_DIR/" || log_and_exit error "Failed to copy installer scripts."

	log info "Running remote installer..."

	local remote_env_exports="
	export BUILD_ON='$BUILD_ON'
export FLAKE='$FLAKE'
export FLAKE_CONFIG_ATTR='$FLAKE_CONFIG_ATTR'
export STAGE='$STAGE'
export FULL='$FULL'
export DO_LOW_MEM='$LOW_MEM'
export DO_FULL='$DO_FULL'
export DISKO_ONLY='${DISKO_ONLY:-no}'
export DISKO_SCRIPT='$DISKO_SCRIPT'
export SYSTEM_CLOSURE='$SYSTEM_CLOSURE'
export NIXCFG='$NIXCFG'"

	local main_remote_script
	main_remote_script=$(cat <<-'EOF'
cd /tmp/installer-staging
chmod +x remote-installer.sh
./remote-installer.sh 2>&1
EOF
)

    # Construct the full script to be executed remotely, ensuring proper separation
    local full_script="
${remote_env_exports}

${main_remote_script}
"

	ssh_target "$full_script" || log_and_exit error "Remote installation failed."
	log info "Remote installation completed."
}

#
# Reboot and Wait Function
#
reboot_and_wait() {
	local reboot_user="${1:-}"
	local wait_user="${2:-$reboot_user}"
	log info "Rebooting target..."

	# If reboot_user specified, temporarily switch TARGET_HOST
	local original_target="$TARGET_HOST"
	if [[ -n "$reboot_user" ]]; then
		TARGET_HOST="${reboot_user}@${SSH_HOST}"
	fi

	# Optional: Capture boot ID for verification
	local pre_boot_id=""
	pre_boot_id=$(ssh_target "cat /proc/sys/kernel/random/boot_id 2>/dev/null" || echo "")

	ssh_target "reboot" || log warn "Reboot command failed, continuing..."
	sleep 15

	# Switch TARGET_HOST for waiting if wait_user different
	if [[ -n "$wait_user" ]]; then
		TARGET_HOST="${wait_user}@${SSH_HOST}"
	fi

	log info "Waiting for target to come back online..."
	local start_time=$(date +%s)
	local timeout=120  # 2 minutes

	until ssh_target true; do
		local elapsed=$(( $(date +%s) - start_time ))
		if [[ $elapsed -gt $timeout ]]; then
			log_and_exit error "Target did not come back online within ${timeout}s after reboot."
		fi
		log debug "SSH connection failed, retrying in 3s... (${elapsed}s elapsed)"
		sleep 3
	done

	# Optional: Verify boot ID change
	if [[ -n "$pre_boot_id" ]]; then
		local current_boot_id
		current_boot_id=$(ssh_target "cat /proc/sys/kernel/random/boot_id 2>/dev/null" || echo "")
		if [[ "$current_boot_id" != "$pre_boot_id" ]]; then
			log info "Confirmed system reboot (boot ID changed)"
		else
			log warn "Boot ID unchanged - system may not have rebooted properly"
		fi
	fi

	log info "Target is back online."

	# User verification if wait_user provided
	if [[ -n "$wait_user" ]]; then
		local current_user
		current_user=$(ssh_target "whoami" 2>/dev/null || echo "unknown")
		if [[ "$current_user" != "$wait_user" ]]; then
			log warn "User mismatch after reboot: expected '$wait_user', got '$current_user'"
		else
			log debug "User verified: $current_user"
		fi
	fi

	# Restore original TARGET_HOST if changed
	TARGET_HOST="$original_target"
}

#
# Main Orchestration Flow
#
prepare_run() {
	validate_environment() {
		local required_vars=("FLAKE" "TARGET_HOST")
		for var in "${required_vars[@]}"; do
			if [[ -z "${!var}" ]]; then
				log_and_exit error "Required variable '$var' is not set"
			fi
		done

		if ! [[ "$BUILD_ON" =~ ^($VALID_BUILD_MODES)$ ]]; then
			log_and_exit error "Invalid --build-on mode: '$BUILD_ON'"
		fi
		if ! [[ "$KEXEC_BOOT" =~ ^($VALID_KEXEC_MODES)$ ]]; then
			log_and_exit error "Invalid --kexec mode: '$KEXEC_BOOT'"
		fi
		if ! [[ "$LOW_MEM" =~ ^($VALID_LOW_MEM_MODES)$ ]]; then
			log_and_exit error "Invalid --low-mem mode: '$LOW_MEM'"
		fi
		if ! [[ "$STAGE" =~ ^($VALID_STAGES)$ ]]; then
			log_and_exit error "Invalid --stage: '$STAGE'"
		fi
		if ! [[ "$FULL" =~ ^($VALID_FULL_MODES)$ ]]; then
			log_and_exit error "Invalid FULL mode: '$FULL'"
		fi
	}
	validate_environment

	FLAKE_HOST="${FLAKE##*.#}"

	resolve_build_on_auto

	if [[ "$BUILD_ON" == "cross" ]]; then
		FLAKE_CONFIG_ATTR="crossNixosConfigurations.$FLAKE_HOST"
		BUILD_ON="local"
		log info "Explicit cross-compilation enabled for $FLAKE_HOST"
	elif [[ "$BUILD_ON" == "local" ]]; then
		# For explicit local, check if cross needed
		local target_system
		target_system=$(get_target_system)
		local current_system
		current_system=$(get_current_system)
		local config_type
		config_type=$(detect_config_type)
  if [[ -n "$target_system" && "$target_system" != "$current_system" ]]; then
    FLAKE_CONFIG_ATTR="${config_type}.$FLAKE_HOST"
  else
    local config_type
    config_type=$(detect_config_type)
    if [[ "$config_type" == "crossNixosConfigurations" ]]; then
      FLAKE_CONFIG_ATTR="nixosConfigurations.$FLAKE_HOST"
    elif [[ "$config_type" == "darwinConfigurations" ]]; then
      FLAKE_CONFIG_ATTR="darwinConfigurations.$FLAKE_HOST"
    else
      FLAKE_CONFIG_ATTR="nixosConfigurations.$FLAKE_HOST"
    fi
  fi
	elif [[ "$BUILD_ON" == "remote" ]]; then
		FLAKE_CONFIG_ATTR="nixosConfigurations.$FLAKE_HOST"
	fi

	log info "--- Installer Staging ---"
	log info "Target:      $TARGET_HOST"
	log info "Flake:       $FLAKE"
	log info "Flake config attr: $FLAKE_CONFIG_ATTR"
	log info "Build on:    $BUILD_ON"
	log info "Kexec:       $KEXEC_BOOT"
	log info "Stage:       $STAGE"
	log info "Low memory:  $LOW_MEM"
	log info "Substitute on dest: $SUBS_ON_DEST"
	log info "Force:       $FORCE"

	KEXEC_BOOT=${KEXEC_BOOT:-$([[ "$STAGE" == "0" ]] && echo "auto" || echo "no")}
	DO_FULL=$([[ "$FULL" == "yes" || ("$FULL" == "auto" && "$BUILD_ON" == "local") ]] && echo "yes" || echo "no")

	if [[ "$LOW_MEM" == "yes" ]]; then
		log info "Low memory mode enabled, applying optimizations."
		if ssh_target "df /var 2>/dev/null | awk 'NR==2 {if (\$4 > 1000000) exit 0; else exit 1}'" 2>/dev/null; then
			TMPDIR_OVERRIDE="/var/tmp"
		fi
	fi
}

copy_flake_lock_to_user_home() {
	local user_home="/home/$NIXUSER"
	ssh_target "sudo sh -c 'if [ -f \"/root/$NIXCFG/flake.lock\" ]; then \
		mkdir -p \"$user_home/$NIXCFG\" && \
		mv \"/root/$NIXCFG/flake.lock\" \"$user_home/$NIXCFG/\" && \
		chown -R $NIXUSER \"$user_home/$NIXCFG\" && \
		echo Moved flake.lock; \
	fi'"
}

bootstrap_orchestrator() {
	trap 'log error "Bootstrap failed"; cleanup_temp_files "/tmp/repo.tar.gz"; exit 1' ERR

	# --- Common Setup for Stage 0 ---
	export STAGE=0
	prepare_run
	establish_ssh

	if [[ "$FORCE" != "yes" ]]; then
		log warn "WARNING: This will destroy all data on the target system."
		read -p "Continue? (y/N): " -n 1 -r
		echo
		[[ "$REPLY" =~ ^[Yy]$ ]] || log_and_exit error "Operation cancelled."
	fi

	handle_kexec
	log info "Waiting for target to be ready..."
	sleep 5
	transfer_files

	# --- Main Workflow ---
	if [[ "$BUILD_ON" == "local" ]]; then
		# LOCAL BUILD: A single-stage process before reboot
		log info "Starting local build full installation..."
		log info "Freeing memory on target..."
		ssh_target "sync && echo 3 > /proc/sys/vm/drop_caches && free -h"
		build_and_copy_disko_locally
		log info "Executing remote disko setup..."
		DISKO_ONLY=yes execute_installation
		build_and_copy_system_locally
		log info "Executing final remote installation..."
		DISKO_ONLY=no execute_installation
	else # BUILD_ON=remote
		# REMOTE BUILD: A two-stage process with a reboot
		log info "Executing remote minimal install (Stage 0)..."
		execute_installation # This will run install_stage0_minimal

		log info "Rebooting target after Stage 0..."
		reboot_and_wait "root"

		# --- Stage 1 ---
		log info "Starting bootstrap Stage 1..."
		export STAGE=1
		prepare_run # Re-run prepare to set STAGE=1 correctly
		log info "Executing remote full system switch (Stage 1)..."
		execute_installation # This will run install_stage1_switch
	fi

	# --- Final Reboot for Local Builds ---
	if [[ "$BUILD_ON" == "local" ]]; then
		log info "Rebooting target to boot into the newly installed system..."
		reboot_and_wait "root" "$NIXUSER"
		TARGET_HOST="${NIXUSER}@${SSH_HOST}"  # Switch to NIXUSER for subsequent operations
		copy_flake_lock_to_user_home
		log info "Local build completed. Target has rebooted into the new system."
	fi

	# --- Cleanup ---
	if [[ "$BUILD_ON" != "local" ]]; then
		log info "Performing cleanup on target..."
		TARGET_HOST="${NIXUSER}@${SSH_HOST}"  # Switch to user SSH
		copy_flake_lock_to_user_home
		ssh_target "sudo bash -c 'test -d /root/$NIXCFG && rm -rf /root/$NIXCFG; test -d result && rm result; nix-collect-garbage -d'"
	else
		log info "Skipping cleanup for local build (not required)."
	fi

	log info "Bootstrap orchestration completed successfully."
}

main_orchestration() {
	trap 'log error "Installation failed"; cleanup_temp_files "/tmp/repo.tar.gz"; exit 1' ERR

	prepare_run
	establish_ssh

	if [[ "$FORCE" != "yes" ]]; then
		log warn "WARNING: This will destroy all data on the target system."
		read -p "Continue? (y/N): " -n 1 -r
		echo
		[[ "$REPLY" =~ ^[Yy]$ ]] || log_and_exit error "Operation cancelled."
	fi

	handle_kexec
	log info "Waiting for target to be ready..."
	sleep 5

	# This function is for single-stage "install" mode.
	# It does not handle the full bootstrap sequence.
	transfer_files
	execute_installation

	log info "Installation orchestration completed successfully."
}
