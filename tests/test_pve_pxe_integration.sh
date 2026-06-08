#!/usr/bin/env bash
# Integration test runner for the Bare Metal Proxmox PXE bootstrap lifecycle.
# This script deploys the metadata-only pve-test VM, waits for the unattended
# installation to complete, verifies connectivity, and cleans up.
set -eo pipefail

# --- Configuration & Defaults ---
PROXMOX_HOST=$(nix eval --raw .#deploymentHosts.pve-test.deployment.proxmox.host 2>/dev/null || echo "192.168.1.15")
TARGET_IP=$(nix eval --raw .#deploymentHosts.pve-test.deployment.targetIp 2>/dev/null || echo "192.168.250.10")
VMID=$(nix eval --raw .#deploymentHosts.pve-test.deployment.vmid 2>/dev/null || echo "911")
KEEP_VM=false
HEADLESS=false

# --- Usage/Help ---
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --keep     Keep the pve-test VM running at the end of the test (to log in and inspect)"
    echo "  --headless Route the Proxmox web console to serial0 for automated debugging"
    echo "  --help     Show this help message"
    exit 0
}

# Parse options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --keep) KEEP_VM=true; shift ;;
        --headless) HEADLESS=true; shift ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

log() {
    echo
    echo "========================================================================="
    echo ">>> $1"
    echo "========================================================================="
}

# --- Step 1: Run Nix Evaluation-Level Tests ---
log "Running Nix evaluation-level unit tests..."
nix-instantiate --eval --strict tests/pve-pxe-assets-test.nix

# --- Step 2: Validate Hypervisor Prerequisites ---
log "Checking hypervisor prerequisites on Proxmox host ($PROXMOX_HOST)..."
SSH_OPTS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=5"

if ! ssh $SSH_OPTS "root@$PROXMOX_HOST" "ip link show vmbrPxe" >/dev/null 2>&1; then
    echo "ERROR: Isolated test bridge 'vmbrPxe' not found or inactive on Proxmox host $PROXMOX_HOST."
    echo "Please perform the Manual Operator Prerequisite to add 'vmbrPxe' before running this test."
    exit 1
fi
if ! ssh $SSH_OPTS "root@$PROXMOX_HOST" "ip link show vmbrTestWan" >/dev/null 2>&1; then
    echo "ERROR: Isolated test bridge 'vmbrTestWan' not found or inactive on Proxmox host $PROXMOX_HOST."
    echo "Please perform the Manual Operator Prerequisite to add 'vmbrTestWan' before running this test."
    exit 1
fi
echo "Bridges 'vmbrPxe' and 'vmbrTestWan' found and active."

# Check if router-recovery VM exists on its configured Proxmox host
ROUTER_VMID=$(nix eval --raw .#deploymentHosts.router-recovery.deployment.vmid 2>/dev/null || echo "910")
ROUTER_HOST=$(nix eval --raw .#deploymentHosts.router-recovery.deployment.proxmox.host 2>/dev/null || echo "192.168.1.15")
ROUTER_STATUS=$(ssh $SSH_OPTS "root@$ROUTER_HOST" "qm status $ROUTER_VMID" 2>/dev/null || echo "not_found")

if [[ "$ROUTER_STATUS" == *"not_found"* ]]; then
    log "router-recovery VM (VMID $ROUTER_VMID) does not exist. Deploying it now..."
    nix run .#installer-rs -- deploy -t router-recovery --force
else
    echo "router-recovery VM (VMID $ROUTER_VMID) already exists. Status: $(echo "$ROUTER_STATUS" | tr -d '\n')"
    
    if [ -t 0 ]; then
        # Interactive terminal: prompt the user
        while true; do
            read -p "Choose action for router-recovery [s=switch configuration, r=redeploy VM, c=continue as-is, a=abort test]: " choice
            case "$choice" in
                s|switch)
                    log "Switching configuration on router-recovery..."
                    nix run .#installer-rs -- switch -t router-recovery
                    break
                    ;;
                r|redeploy)
                    log "Redeploying router-recovery VM from scratch..."
                    nix run .#installer-rs -- deploy -t router-recovery --redeploy --force
                    break
                    ;;
                c|continue)
                    echo "Continuing test using current router-recovery VM."
                    if [[ "$ROUTER_STATUS" == *"status: stopped"* ]]; then
                        echo "Starting stopped router-recovery VM..."
                        ssh $SSH_OPTS "root@$PROXMOX_HOST" "qm start $ROUTER_VMID"
                    fi
                    break
                    ;;
                a|abort)
                    echo "Aborting test."
                    exit 1
                    ;;
                *)
                    echo "Invalid option. Please choose s, r, c, or a."
                    ;;
            esac
        done
    else
        # Non-interactive terminal: default to continue
        echo "Non-interactive terminal detected. Defaulting to 'continue' with existing router-recovery VM."
        if [[ "$ROUTER_STATUS" == *"status: stopped"* ]]; then
            echo "Starting stopped router-recovery VM..."
            ssh $SSH_OPTS "root@$PROXMOX_HOST" "qm start $ROUTER_VMID"
        fi
    fi
fi

# Clean up any leftover test VM from a previous run
if ssh $SSH_OPTS "root@$PROXMOX_HOST" "qm status $VMID" >/dev/null 2>&1; then
    log "Leftover VM $VMID found from a previous run. Destroying it..."
    ssh $SSH_OPTS "root@$PROXMOX_HOST" "qm stop $VMID" >/dev/null 2>&1 || true
    ssh $SSH_OPTS "root@$PROXMOX_HOST" "qm destroy $VMID"
fi

# --- Step 3: Run Deployment (PXE VM Boot & Install) ---
log "Starting automated PXE deployment pipeline for pve-test (VMID $VMID)..."
if [ "$HEADLESS" = true ]; then
    VGA_MODE="serial0"
    echo "Headless mode: Proxmox Console and 'qm terminal $VMID' use serial0."
else
    VGA_MODE="std"
    echo "Manual mode: Proxmox Console uses the standard VGA display."
fi

# Apply the requested display mode when reusing an existing VM. VM_VGA applies
# the same mode when installer-rs creates a fresh VM.
if ssh $SSH_OPTS "root@$PROXMOX_HOST" "qm status $VMID" >/dev/null 2>&1; then
    ssh $SSH_OPTS "root@$PROXMOX_HOST" "qm set $VMID --vga $VGA_MODE"
fi

# Using the installer-rs orchestrator directly
VM_VGA="$VGA_MODE" nix run .#installer-rs -- deploy -t pve-test --force

# --- Step 4: Verification ---
log "Verifying final target environment SSH access (via recovery router jump host)..."
ROUTER_IP=$(nix eval --raw .#deploymentHosts.router-recovery.deployment.targetIp 2>/dev/null || echo "192.168.1.20")
if ssh $SSH_OPTS -o "ProxyCommand=ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR -W %h:%p nixos@$ROUTER_IP" -o BatchMode=yes -o ConnectTimeout=3 "root@$TARGET_IP" "pveversion" >/dev/null 2>&1; then
    echo "SUCCESS: Successfully connected to root@$TARGET_IP via jump host. Proxmox is installed!"
else
    echo "ERROR: Unable to connect to root@$TARGET_IP via jump host or command failed."
    exit 1
fi

# --- Step 5: Cleanup or Keep VM ---
if [ "$KEEP_VM" = true ]; then
    log "Test complete. Keeping VM $VMID alive as requested."
    echo "Target is reachable at root@$TARGET_IP."
    echo "Run the following command later to clean up and delete the VM:"
    echo "  nix run .#installer-rs -- destroy -t pve-test"
else
    log "Cleaning up and destroying VM $VMID..."
    nix run .#installer-rs -- destroy -t pve-test
    echo "VM $VMID has been successfully destroyed."
fi

log "Integration test completed successfully!"
