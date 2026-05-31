#!/usr/bin/env bash
set -e

# Configuration
HOSTS=("pve1.lamhub.com" "pve2.lamhub.com")
NODES=("pve-dl360p"      "pve2")

OUTPUT_BASE="./_tmp/pve_configs"

# Function to generate the file list for a specific host
# Allows using the hostname variable to target node-specific paths
get_file_list() {
    local pve_node_name="$1"

    cat <<EOF
# --- System Configuration ---
/etc/network/interfaces
/etc/hosts
/etc/resolv.conf
/etc/chrony/chrony.conf
/etc/modprobe.d
/etc/kernel/cmdline
/etc/lvm/lvm.conf
/etc/lvm/lvmlocal.conf

# --- PVE Global Configuration ---
/etc/pve/storage.cfg
/etc/pve/corosync.conf
/etc/pve/user.cfg
/etc/pve/domains.cfg
/etc/pve/datacenter.cfg
/etc/pve/vzdump.cron

# --- Storage & Connectivity ---
# iSCSI
/etc/iscsi
# Multipath
/etc/multipath.conf
/etc/multipath

# --- Node-Specific Resources ---
# VM configurations
/etc/pve/nodes/${pve_node_name}/qemu-server
# LXC configurations
/etc/pve/nodes/${pve_node_name}/lxc
# OpenVZ (Legacy)
/etc/pve/nodes/${pve_node_name}/openvz
EOF
}

echo "Preparing to pull configurations..."
echo "Target directory: $OUTPUT_BASE"

# Iterate over indices
for i in "${!HOSTS[@]}"; do
    host="${HOSTS[$i]}"
    node_name="${NODES[$i]}"

    echo "--------------------------------------------------"
echo "Processing host: $host (Node: $node_name)"

    target_dir="$OUTPUT_BASE/$host"

    # --ignore-missing-args: Don't fail if a specific file (like openvz) is missing
    get_file_list "$node_name" | grep -v '^	*#' | grep -v '^	*$' | \
    rsync -ravhP --delete --ignore-missing-args --files-from=- "root@$host:/" "$target_dir/"

done

echo "--------------------------------------------------"
echo "Download complete."
echo "View files at: $OUTPUT_BASE"
