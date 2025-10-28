#!/usr/bin/env bash
# Centralized configuration for installer-staging

# Default values
readonly DEFAULT_BUILD_ON="remote"
readonly DEFAULT_KEXEC_BOOT="auto"
readonly DEFAULT_FULL="auto"
readonly DEFAULT_STAGE="0"
readonly DEFAULT_LOW_MEM="no"
readonly DEFAULT_FORCE="no"
readonly DEFAULT_LOG_LEVEL="info"
readonly DEFAULT_SUBS_ON_DEST="yes"

# Paths and URLs
readonly KEXEC_BASE_URL="https://github.com/nix-community/nixos-images/releases/download/nixos-25.05/nixos-kexec-installer-noninteractive"
readonly NIX_INSTALL_URL="https://releases.nixos.org/nix/nix-2.31.2/install"

# SSH settings
readonly SSH_KEY_FILE="$HOME/.ssh/id_installer"
readonly SSH_OPTIONS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3"

# File paths
readonly REMOTE_INSTALLER_SCRIPT="./apps/installer-staging/remote-installer.sh"
readonly EXTRA_CONFIG_FILE="./apps/installer-staging/extra-config.nix"
readonly REMOTE_TMP_DIR="/tmp/installer-staging"

# Default excludes
readonly DEFAULT_FLAKE_EXCLUDE="--exclude=.git --exclude=secrets --exclude=result --exclude=.DS_Store --exclude=flake.lock"

# Validation patterns
readonly VALID_BUILD_MODES="local|remote|auto|cross"
readonly VALID_KEXEC_MODES="yes|no|auto"
readonly VALID_FULL_MODES="yes|no|auto"
readonly VALID_LOW_MEM_MODES="yes|no"
readonly VALID_STAGES="0|1"
readonly VALID_SUBS_ON_DEST_MODES="yes|no"
