#!/usr/bin/env bash
# Centralized configurations for installer2

readonly DEFAULT_NIX_CFG="lamt-nixconfig"
readonly DEFAULT_TEA_URL="tea.lamhub.com"

# Kexec takeover image base url
readonly KEXEC_BASE_URL="https://github.com/nix-community/nixos-images/releases/download/nixos-25.05/nixos-kexec-installer-noninteractive"

# Proxmox Defaults
readonly DEFAULT_PROXMOX_HOST="pve1.lamhub.com"
readonly DEFAULT_VM_STORAGE="arthurz2-lvm"
readonly DEFAULT_VM_BRIDGE="vmbr1,tag=10"
readonly DEFAULT_VM_SUBNET="192.168.1.0/24"
readonly DEFAULT_NIXOS_ISO_QEMU="arthurz2-dir:iso/nixos-minimal-25.05pre-git-x86_64-linux-qemu.iso"
readonly DEFAULT_NIXOS_ISO_VLAN="arthurz2-dir:iso/nixos-minimal-25.05pre-git-x86_64-linux.iso"
readonly DEFAULT_CLOUDINIT_IMG_PATH="/mnt/pve/arthurz2-dir/images/ubuntu-22.04-server-cloudimg-amd64.img"

# DigitalOcean Defaults
readonly DEFAULT_DO_REGION="sgp1"
readonly DEFAULT_DO_SIZE="s-1vcpu-1gb"
readonly DEFAULT_DO_IMAGE="ubuntu-24-04-x64"

# Nix / Rsync flags
readonly DEFAULT_SUBS_ON_DEST="no"
readonly RSYNC_COMMON_FLAGS="--exclude=.git --exclude=result --exclude=.DS_Store --exclude=blog/themes --exclude=*.bak --exclude=.antigravitycli --delete"

# Standard SSH parameters
readonly SSH_COMMON_ARGS=(
    -o UserKnownHostsFile=/dev/null
    -o StrictHostKeyChecking=no
    -o LogLevel=ERROR
    -o ConnectTimeout=10
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=3
    -o PasswordAuthentication=no
    -o ChallengeResponseAuthentication=no
    -o KbdInteractiveAuthentication=no
)
readonly SSH_COMMON_OPTIONS="${SSH_COMMON_ARGS[*]}"

# Repository / Path configurations
readonly DEFAULT_SECRETS_REPO="../lamt-secrets"
readonly DEFAULT_GITHUB_USER="lamtt77"
readonly DEFAULT_TEA_SSH_USER="git"
readonly DEFAULT_TEA_SSH_URI="git+ssh://${DEFAULT_TEA_SSH_USER}@${DEFAULT_TEA_URL}/${DEFAULT_GITHUB_USER}"
readonly DEFAULT_GITHUB_URI="github:${DEFAULT_GITHUB_USER}"

# Deployment orchestration Defaults
readonly DEFAULT_BUILDER="deploy@utils"

# Headscale / Tailscale Coordinator Defaults
readonly HEADSCALE_COORDINATOR_IP="100.64.0.1"
readonly HEADSCALE_COORDINATOR_USER="nixos"
readonly TAILSCALE_NAMESPACES=("lamt" "cloud" "fcm")
readonly DEFAULT_TAILSCALE_NAMESPACE="lamt"

# VMware Defaults
readonly DEFAULT_VMW_ISO_DIR="/Users/lamt/Virtual Machines.localized/VMWIsoImages"

