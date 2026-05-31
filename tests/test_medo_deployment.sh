#!/usr/bin/env bash
set -e

# Reusable script to test the deployment of a NixOS configuration onto a
# fresh Proxmox VM that has been restored from a cloud-init snapshot.

# --- Configuration ---
VMID="203"
SNAPSHOT_NAME="cloudinit_fresh"
PROXMOX_HOST="pve1.lamhub.com"
PROXMOX_USER="root"
TARGET_IP="${1:-192.168.1.154}"

# Deployment Variables
NIXHOST="medo"
NIXUSER="nixos"
BOOTSTRAP_USER="ubuntu" # Initial user on the cloud-init image
FORCE="yes"
LOW_MEM="yes"
BUILD_ON="local"

# SSH Options
SSH_OPTIONS="-A -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3"

# --- Helper Functions ---
log() {
    echo
    echo "--- $1 ---"
}

run_on_proxmox() {
    local cmd="$@"
    echo "Executing on Proxmox ($PROXMOX_HOST): $cmd" >&2
    ssh $SSH_OPTIONS "${PROXMOX_USER}@${PROXMOX_HOST}" "$cmd"
}

# --- Main Script ---

log "Starting test for host '$NIXHOST' on Proxmox VM $VMID"

log "Restoring snapshot '$SNAPSHOT_NAME' on VM $VMID"
run_on_proxmox "qm rollback $VMID $SNAPSHOT_NAME"

log "Ensuring VM $VMID is running"
VM_STATUS=$(run_on_proxmox "qm status $VMID | awk '{print $2}'" || echo "unknown")

if [ "$VM_STATUS" == "running" ]; then
    echo "VM $VMID is already running."
elif [ "$VM_STATUS" == "stopped" ]; then
    echo "VM $VMID is stopped. Starting it now..."
    run_on_proxmox "qm start $VMID"
else
    echo "Warning: Could not determine VM status (got \'$VM_STATUS\'). Proceeding..."
fi

log "Waiting for VM to become reachable on port 22 (timeout: 60s)"
for i in {1..20}; do
    if nc -z -w 2 $TARGET_IP 22; then
        echo "VM is online."
        break
    fi
    if [ $i -eq 20 ]; then
        echo "ERROR: VM did not become reachable on port 22."
        exit 1
    fi
    sleep 3
done

log "Running NixOS bootstrap command"
# Using new Makefile interface
make deploy \
    NIXTARGET="$NIXUSER@$NIXHOST" \
    NIXIP="$TARGET_IP" \
    BOOTSTRAP_USER="$BOOTSTRAP_USER" \
    FORCE="$FORCE" \
    LOW_MEM="$LOW_MEM" \
    BUILD_ON="$BUILD_ON"

log "Test script finished successfully."
