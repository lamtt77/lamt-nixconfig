#!/usr/bin/env bash
set -e

# Reusable script to test the deployment of a NixOS configuration onto a
# fresh Proxmox VM that has been restored from a cloud-init snapshot.

# --- Configuration ---
VMID="115"
SNAPSHOT_NAME="cloudinit_fresh"
PROXMOX_HOST="pve1.lamhub.com" # From Makefile
PROXMOX_USER="root"
DEPLOY_HOST="192.168.1.162"
DEPLOY_USER="deploy"
TARGET_IP="192.168.1.158"
TARGET_SSH_USER="ubuntu"      # Default user for the cloud-init image

# Variables for the make command
NIXHOST="medo"
NIXUSER="nixos"
NIXREPO="local"
SECRETS="yes"
FORCE="yes"
LOW_MEM="yes"

# SSH Options (mirrored from Makefile for consistency)
SSH_OPTIONS="-A -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3"

# --- Main Script ---

echo "--- Running on deploy host ---"

# --- Helper Functions ---
log() {
    echo
    echo "--- $1 ---"
}

# This function runs a command on the Proxmox host.
# It's called from the deploy host.
run_on_proxmox() {
    local cmd="$@"
    echo "Executing on Proxmox ($PROXMOX_HOST): $cmd" >&2
    ssh $SSH_OPTIONS "${PROXMOX_USER}@${PROXMOX_HOST}" "$cmd"
}


log "Starting test for host '$NIXHOST' on Proxmox VM $VMID"

log "Restoring snapshot '$SNAPSHOT_NAME' on VM $VMID"
run_on_proxmox "qm rollback $VMID $SNAPSHOT_NAME"

log "Ensuring VM $VMID is running"
# Check the status. The output is "status: <state>"
VM_STATUS=$(run_on_proxmox "qm status $VMID | awk '{print \$2}'" || echo "unknown")

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
# We use `remote/bootstrap` as it's the correct underlying target for this scenario.
# The `digitalocean/convert-switch` target is a specific wrapper for that platform.
make remote/bootstrap \
    NIXADDR="$TARGET_IP" \
    NIXHOST="$NIXHOST" \
    NIXUSER="$NIXUSER" \
    SSHUSER="$TARGET_SSH_USER" \
    NIXREPO="$NIXREPO" \
    SECRETS="$SECRETS" \
    FORCE="$FORCE" \
    LOW_MEM="$LOW_MEM"

log "Test script finished successfully."