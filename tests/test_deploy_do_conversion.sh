#!/usr/bin/env bash
set -e

# Script to test DigitalOcean/VPS Conversion (Remote Build, Low Mem)
# Usage: ./tests/test_deploy_do_conversion.sh <TARGET_IP>

# Configuration
TARGET_IP="${1:-192.168.1.158}"
NIXHOST="medo"
NIXUSER="nixos"
# DigitalOcean droplets usually start as 'root'.
# If testing against 'medo' cloud-init VM, we might need 'ubuntu'.
# We'll default to 'ubuntu' here for the test lab, but real DO is 'root'.
SSHUSER="ubuntu"

echo "--- Testing DigitalOcean Conversion (Low Mem, Single Stage/Local Build) ---"
echo "Target IP: $TARGET_IP"
echo "Target Host: $NIXHOST"
echo "Connecting as: $SSHUSER"

# We use `make deploy` which invokes the orchestrator in bootstrap mode.
# BUILD_ON="local" (default) is preferred for 1GB VPS to avoid compilation OOM.
# LOW_MEM="yes" applies GC tuning and kexec optimizations.
# We separate NIXTARGET (Final User@Host) from BOOTSTRAP_USER (Initial SSH User).
make deploy \
    NIXTARGET="$NIXUSER@$NIXHOST" \
    BOOTSTRAP_USER="$SSHUSER" \
    NIXIP="$TARGET_IP" \
    FORCE="yes" \
    BUILD_ON="local" \
    LOW_MEM="yes"

echo "Test script finished successfully."

