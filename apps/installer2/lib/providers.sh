#!/usr/bin/env bash
# shellcheck disable=SC2154
# Infrastructure Cloud Providers Library (installer2)

# --- Proxmox Defaults & Helper context ---
init_proxmox_context() {
    PROXMOX_HOST="${PROXMOX_HOST:-$DEFAULT_PROXMOX_HOST}"
    VM_STORAGE="${VM_STORAGE:-$DEFAULT_VM_STORAGE}"
    VM_BRIDGE="${VM_BRIDGE:-$DEFAULT_VM_BRIDGE}"

    # Determine default installer ISO
    local default_iso="$DEFAULT_NIXOS_ISO_VLAN"
    if [[ -n "${BOOTSTRAP_VLAN:-}" ]]; then
        default_iso="$DEFAULT_NIXOS_ISO_QEMU"
    fi
    NIXOS_ISO="${NIXOS_ISO:-$default_iso}"

    # Router bridge mappings (Dual bridge WAN/LAN)
    if [[ "$HOST" == router-* ]]; then
        VM_NET0="virtio,bridge=vmbr0"
        VM_NET1="virtio,bridge=vmbr1"
        info "Router configuration: mapping net0 (WAN, vmbr0) & net1 (LAN, vmbr1)"
    else
        VM_NET0="virtio,bridge=$VM_BRIDGE"
        VM_NET1=""
    fi
}

qm_stop() {
    info "Requesting stop for Proxmox VM $VMID on $PROXMOX_HOST..."
    ssh_cmd "root@$PROXMOX_HOST" "qm stop $VMID" || warn "VM $VMID stop command skipped (might not be running)"
}

qm_destroy() {
    confirm_or_exit "WARNING: This will DESTROY VM $VMID on $PROXMOX_HOST."
    local ssh_target="root@$PROXMOX_HOST"
    if ! ssh_cmd "$ssh_target" "qm status $VMID" >/dev/null 2>&1; then
        info "Proxmox VM $VMID does not exist on $PROXMOX_HOST. Skipping destroy."
        return 0
    fi
    info "Requesting destroy for Proxmox VM $VMID..."
    ssh_cmd "$ssh_target" "qm destroy $VMID" || die "Failed to destroy VM $VMID"
}

qm_create() {
    local ssh_target="root@$PROXMOX_HOST"
    if ssh_cmd "$ssh_target" "qm status $VMID" >/dev/null 2>&1; then
        info "Proxmox VM $VMID already exists on $PROXMOX_HOST. Reusing existing instance."
        return 0
    fi

    info "Provisioning Proxmox VM $VMID ($HOST)..."

    # Disk bus config
    local disk_args="--scsihw virtio-scsi-pci --scsi0 $VM_STORAGE:${VM_DISK_SIZE:-50}"
    local boot_disk="scsi0"
    if [[ "${VM_DISK_BUS:-scsi}" == "virtio" ]]; then
        disk_args="--virtio0 $VM_STORAGE:${VM_DISK_SIZE:-50}"
        boot_disk="virtio0"
    fi

    # Network configurations
    local net1_arg=""
    [[ -n "$VM_NET1" ]] && net1_arg="--net1 $VM_NET1"

    # Bios/Firmware settings
    local bios_args="--bios ovmf --efidisk0 $VM_STORAGE:1"
    if [[ "${BIOS_TYPE:-ovmf}" == "seabios" ]]; then
        bios_args="--bios seabios"
    fi

    # qm create execution (with cloud-init drive attached by default on ide0)
    ssh_cmd "$ssh_target" "qm create $VMID \
        --name $HOST \
        --memory ${VM_MEMORY:-4096} \
        --cores ${VM_CORES:-4} \
        --net0 $VM_NET0 \
        $net1_arg \
        $disk_args \
        $bios_args \
        --ide0 $VM_STORAGE:cloudinit \
        --ipconfig0 ip=dhcp \
        --cdrom $NIXOS_ISO,media=cdrom \
        --boot order=$boot_disk\\;ide2\\;net0 \
        --serial0 socket \
        --agent enabled=1 \
        --autostart 1"

    info "Proxmox VM $VMID created successfully."
}

qm_create_cloudinit() {
    local ssh_target="root@$PROXMOX_HOST"
    if ssh_cmd "$ssh_target" "qm status $VMID" >/dev/null 2>&1; then
        info "Proxmox VM $VMID already exists on $PROXMOX_HOST. Reusing existing instance."
        return 0
    fi

    info "Provisioning Proxmox Cloud-Init VM $VMID ($HOST)..."
    local bios_type="${BIOS_TYPE:-ovmf}"
    local ci_user="${CLOUDINIT_USER:-ubuntu}"
    local img_path="${CLOUDINIT_IMG_PATH:-$DEFAULT_CLOUDINIT_IMG_PATH}"
    local disk_size="${VM_DISK_SIZE:-50}"

    # Extract user pubkey from local defines.nix
    local ssh_key
    ssh_key=$(nix eval --raw --impure --expr 'let defs = import ./defines.nix; in defs.mySshAuthKey') || die "Failed to read public keys from defines.nix"

    local bios_args=""
    [[ "$bios_type" == "ovmf" ]] && bios_args="--bios ovmf --efidisk0 $VM_STORAGE:1"

    local net1_arg=""
    local ipconfig1_arg=""
    if [[ -n "$VM_NET1" ]]; then
        net1_arg="--net1 $VM_NET1"
        [[ -n "${IPCONFIG1:-}" ]] && ipconfig1_arg="--ipconfig1 ${IPCONFIG1}"
    fi

    ssh_cmd "$ssh_target" "
        echo \"$ssh_key\" > /tmp/ssh_key_${VMID}.pub && \
        qm create $VMID \
            --name $HOST \
            --memory ${VM_MEMORY:-4096} \
            --cores ${VM_CORES:-4} \
            --net0 $VM_NET0 \
            --ipconfig0 ${IPCONFIG0:-ip=dhcp} \
            $net1_arg $ipconfig1_arg \
            $bios_args \
            --ide2 $VM_STORAGE:cloudinit \
            --serial0 socket \
            --agent enabled=1 \
            --autostart 1 \
            --ciuser $ci_user \
            --sshkeys /tmp/ssh_key_${VMID}.pub && \
        qm importdisk $VMID $img_path $VM_STORAGE && \
        IMPORTED_DISK=\$(qm config $VMID | grep -oP '^unused[0-9]+: \K[^,]+') && \
        qm set $VMID --virtio0 \$IMPORTED_DISK && \
        qm set $VMID --boot 'order=virtio0;ide2;net0' && \
        qm resize $VMID virtio0 ${disk_size}G && \
        rm /tmp/ssh_key_${VMID}.pub
    "
    info "Cloud-Init VM $VMID initialized successfully."
}

qm_start() {
    info "Starting Proxmox VM $VMID on $PROXMOX_HOST..."
    ssh_cmd "root@$PROXMOX_HOST" "qm start $VMID"
    info "VM $VMID started."
}

wait_cloudinit() {
    local ip="$1"
    local ci_user="${CLOUDINIT_USER:-ubuntu}"
    local target="$ci_user@$ip"
    local timeout="${2:-300}"
    local interval=5
    local elapsed=0

    # Phase 1: poll until SSH is reachable (VM may still be booting)
    info "Waiting for SSH on $target before returning..."
    while ! ssh "${SSH_COMMON_ARGS[@]}" "$target" "true" >/dev/null 2>&1; do
        if [[ $elapsed -ge $timeout ]]; then
            error "Timed out waiting for SSH on $target"
            return 1
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    # Phase 2: Inform user how to check cloud-init status instead of blocking
    info "SSH is reachable. Cloud-init is likely still finishing background tasks."
    info "You can check its progress manually by running:"
    info "    ssh ${SSH_COMMON_OPTIONS} $target 'cloud-init status --wait'"
    
    return 0
}

qm_inject_ip() {
    local vmid="$1"
    local static_ip="$2"
    local subnet="$3"
    local net_if="$4"
    local vlan="$5"

    info "Executing QEMU Guest Agent static IP/VLAN network injection..."
    ssh_cmd "root@$PROXMOX_HOST" "bash -s $vmid $static_ip $subnet $net_if $vlan" <<'EOF'
        VMID="$1"
        STATIC_IP="$2"
        SUBNET="$3"
        NET_IF="$4"
        BOOTSTRAP_VLAN="$5"

        CIDR=$(echo "$SUBNET" | cut -d'/' -f2)
        [[ -z "$CIDR" || "$CIDR" == "$SUBNET" ]] && CIDR="24"
        GATEWAY="$(echo "$SUBNET" | cut -d. -f1-3).1"

        IFACE_ETH="eth0"
        [[ "$NET_IF" == "net1" ]] && IFACE_ETH="eth1"

        configure_network_interface() {
            local iface="$1"
            local target="$1"

            if [ -n "$BOOTSTRAP_VLAN" ]; then
                target="$iface.$BOOTSTRAP_VLAN"
                qm guest exec $VMID -- /run/current-system/sw/bin/ip addr flush dev $iface >/dev/null 2>&1
                qm guest exec $VMID -- /run/current-system/sw/bin/ip link add link $iface name $target type vlan id $BOOTSTRAP_VLAN >/dev/null 2>&1
                qm guest exec $VMID -- /run/current-system/sw/bin/ip link set up dev $target >/dev/null 2>&1
            fi

            qm guest exec $VMID -- /run/current-system/sw/bin/ip link set up dev $iface >/dev/null 2>&1
            qm guest exec $VMID -- /run/current-system/sw/bin/ip addr add $STATIC_IP/$CIDR dev $target >/dev/null 2>&1
            qm guest exec $VMID -- /run/current-system/sw/bin/ip route add default via $GATEWAY >/dev/null 2>&1
        }

        for j in {1..6}; do
            configure_network_interface "$IFACE_ETH"
            sleep 5
            if ping -c 1 -W 2 "$STATIC_IP" >/dev/null 2>&1; then
                echo "Static IP injected and reachable." >&2
                exit 0
            fi
        done
        exit 1
EOF
}

qm_scan_ip() {
    local vmid="$1"
    local subnet="$2"
    local net_if="$3"

    info "Scanning subnet $subnet for target VM MAC address on interface $net_if..."
    local ip
    # shellcheck disable=SC2029
    ip=$(ssh "${SSH_COMMON_ARGS[@]}" "root@$PROXMOX_HOST" "bash -s $vmid $subnet $net_if" <<'EOF'
        VMID="$1"
        SUBNET="$2"
        NET_IF="$3"

        if ! qm config "$VMID" > /dev/null 2>&1; then
            exit 1
        fi

        MACS=$(qm config "$VMID" | grep -E "^$NET_IF:" | sed -E 's/.*=([0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}).*/\1/' | tr A-Z a-z)
        if [ -z "$MACS" ]; then
             exit 1
        fi

        for i in $(seq 1 24); do
            IP=$(nmap -sn "$SUBNET" 2>/dev/null | grep -i "$MACS" -B 2 | grep "Nmap scan report" | rev | cut -d " " -f1 | rev | head -n 1)
            if [ -n "$IP" ]; then
                echo "$IP"
                exit 0
            fi
            sleep 5
        done
        exit 1
EOF
    ) || return 1

    if [[ -n "$ip" ]]; then echo "$ip"; else return 1; fi
}

qm_get_ip() {
    info "Locating target Proxmox VM IP..."
    local target_net="net0"
    [[ "${HOST:-}" == router-* ]] && target_net="net1"

    # Try static IP ping
    if [[ -n "${STATIC_IP:-}" ]]; then
        if ping -c 1 -W 5 "$STATIC_IP" >/dev/null 2>&1; then
            echo "$STATIC_IP"
            return 0
        fi

        # Try Guest Agent Injection if VLAN tag is defined
        if [[ -n "${BOOTSTRAP_VLAN:-}" ]]; then
            if qm_inject_ip "$VMID" "$STATIC_IP" "${VM_SUBNET:-192.168.1.0/24}" "$target_net" "$BOOTSTRAP_VLAN"; then
                echo "$STATIC_IP"
                return 0
            else
                warn "Agent IP injection failed. Falling back to subnet scan."
            fi
        fi
    fi

    # Fallback to scanning
    qm_scan_ip "$VMID" "${VM_SUBNET:-192.168.1.0/24}" "$target_net"
}

# --- DigitalOcean Provider Logic ---
check_doctl() {
    if ! command -v doctl >/dev/null 2>&1; then
        die "doctl is required but not found in PATH."
    fi
}

do_create_droplet() {
    local name="$1"
    local region="${DO_REGION:-sgp1}"
    local size="${DO_SIZE:-s-1vcpu-1gb}"
    local image="${DO_IMAGE:-ubuntu-24-04-x64}"
    local ssh_keys="${DO_SSH_KEYS:-$(doctl compute ssh-key list --format ID --no-header | tr '\n' ',' | sed 's/,$//')}"

    info "Verifying droplet configuration for '$name'..."
    if doctl compute droplet get "$name" >/dev/null 2>&1; then
        info "Droplet '$name' already exists. Reusing existing instance."
    else
        info "Provisioning new DigitalOcean droplet '$name' ($region, $size)..."
        doctl compute droplet create "$name" \
            --region "$region" \
            --size "$size" \
            --image "$image" \
            --ssh-keys "$ssh_keys" \
            --tag-names "nixos,installer" \
            --wait
        info "Droplet creation complete."
    fi
}

do_get_ip() {
    local name="$1"
    local ip
    if ! ip=$(doctl compute droplet get "$name" --format PublicIPv4 --no-header) || [[ -z "$ip" ]]; then
        error "Unable to resolve Public IP for Droplet '$name'."
        return 1
    fi
    echo "$ip"
}

do_destroy_droplet() {
    local name="$1"
    info "Requesting destroy for DigitalOcean droplet '$name'..."
    doctl compute droplet delete "$name" --force
}

# --- VMware Fusion Provider Logic ---
check_vmrun() {
    VMRUN_PATH="/Applications/VMware Fusion.app/Contents/Public/vmrun"
    if [[ ! -x "$VMRUN_PATH" ]]; then
        VMRUN_PATH="/Applications/VMware Fusion.app/Contents/Library/vmrun"
    fi
    if [[ ! -x "$VMRUN_PATH" ]]; then
        if command -v vmrun >/dev/null 2>&1; then
            VMRUN_PATH="$(command -v vmrun)"
        else
            die "vmrun (VMware Fusion) is required but not found."
        fi
    fi
}

vmware_is_running() {
    local vmx_path="$1"
    check_vmrun
    "$VMRUN_PATH" -T fusion list | grep -Fq "$vmx_path"
}

vmware_start() {
    local vmx_path="$1"
    check_vmrun
    if vmware_is_running "$vmx_path"; then
        info "VMware VM is already running."
    else
        info "Starting VMware Fusion VM..."
        "$VMRUN_PATH" -T fusion start "$vmx_path" gui
    fi
}

vmware_stop() {
    local vmx_path="$1"
    check_vmrun
    if vmware_is_running "$vmx_path"; then
        info "Stopping VMware Fusion VM..."
        local tools_state
        tools_state=$("$VMRUN_PATH" -T fusion checkToolsState "$vmx_path" 2>/dev/null || echo "unknown")
        if [[ "$tools_state" == "running" ]]; then
            "$VMRUN_PATH" -T fusion stop "$vmx_path" soft || "$VMRUN_PATH" -T fusion stop "$vmx_path" hard
        else
            "$VMRUN_PATH" -T fusion stop "$vmx_path" hard
        fi
    fi
}

vmware_destroy() {
    local vmx_path="$1"
    check_vmrun
    vmware_stop "$vmx_path"

    local vmx_dir
    vmx_dir=$(dirname "$vmx_path")
    if [[ -d "$vmx_dir" ]]; then
        # If this is a destroy mode, delete everything
        if [[ "${MODE:-}" == *"-destroy" || "${MODE:-}" == "destroy" ]]; then
            if [[ -f "$vmx_path" ]]; then
                info "Deleting VMware Fusion VM at $vmx_path..."
                "$VMRUN_PATH" -T fusion deleteVM "$vmx_path" || true
            fi
            info "Cleaning up VM directory $vmx_dir..."
            rm -rf "$vmx_dir"
        else
            # For redeploy or other modes, preserve VMX config
            info "Cleaning up guest state files in $vmx_dir (preserving VMX configuration)..."
            rm -f "$vmx_dir"/*.vmdk
            rm -f "$vmx_dir"/*.log
            rm -f "$vmx_dir"/*.nvram "$vmx_dir"/*.scoreboard
            rm -rf "$vmx_dir"/*.lck
            rm -f "$vmx_dir"/*.vmsd
        fi
    fi
}

vmware_get_ip() {
    local vmx_path="$1"
    if [[ ! -f "$vmx_path" ]]; then
        return 1
    fi
    local mac
    mac=$(grep -E -i "^ethernet0.generatedAddress[[:space:]]*=" "$vmx_path" | cut -d '"' -f2 | tr -d '\r[:space:]')
    if [[ -z "$mac" ]]; then
        return 1
    fi
    mac=$(echo "$mac" | tr '[:upper:]' '[:lower:]')

    # Try up to 12 times (60 seconds) for lease acquisition
    for i in $(seq 1 12); do
        local ip
        ip=$(awk -v mac="$mac" '
          /^lease/ { ip = $2 }
          /hardware ethernet/ {
            sub(/;/, "", $3)
            if ($3 == mac) {
              found_ip = ip
            }
          }
          END { if (found_ip) print found_ip }
        ' /var/db/vmware/vmnet-dhcpd-*.leases)

        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
        sleep 5
    done
    return 1
}

generate_vmx_content() {
    local name="$1"
    local disk_name="$2"
    local iso_path="$3"
    local arch="$4"
    local memsize="${VM_MEMORY:-4096}"
    local numvcpus="${VM_CORES:-4}"

    local guest_os="arm-other6xlinux-64"
    local net_dev="vmxnet3"
    if [[ "$arch" == "x86_64" ]]; then
        guest_os="other6xlinux-64"
        net_dev="e1000e"
    fi

    cat <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "22"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
vmci0.present = "TRUE"
hpet0.present = "TRUE"
nvram = "${name}.nvram"
virtualHW.productCompatibility = "hosted"
powerType.powerOff = "soft"
powerType.powerOn = "soft"
powerType.suspend = "soft"
powerType.reset = "soft"
displayName = "${name}"
firmware = "efi"
guestOS = "${guest_os}"
tools.syncTime = "TRUE"
tools.upgrade.policy = "upgradeAtPowerCycle"
sound.autoDetect = "TRUE"
sound.virtualDev = "hdaudio"
sound.fileName = "-1"
sound.present = "TRUE"
numvcpus = "${numvcpus}"
cpuid.coresPerSocket = "1"
memsize = "${memsize}"
sata0.present = "TRUE"
nvme0.present = "TRUE"
sata0:0.fileName = "${disk_name}"
sata0:0.present = "TRUE"
sata0:1.deviceType = "cdrom-image"
sata0:1.fileName = "${iso_path}"
sata0:1.present = "TRUE"
sata0:1.startConnected = "TRUE"
sata0:1.autodetect = "FALSE"
usb.present = "TRUE"
ehci.present = "TRUE"
usb_xhci.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.addressType = "generated"
ethernet0.virtualDev = "${net_dev}"
ethernet0.linkStatePropagation.enable = "TRUE"
ethernet0.present = "TRUE"
extendedConfigFile = "${name}.vmxf"
isolation.tools.hgfs.disable = "FALSE"
hgfs.mapRootShare = "TRUE"
hgfs.linkRootShare = "TRUE"
floppy0.present = "FALSE"
bios.bootOrder = "hdd"
bios.hddOrder = "sata0:0"
mks.enable3d = "TRUE"
gui.fitGuestUsingNativeDisplayResolution = "TRUE"
vmxstats.filename = "${name}.scoreboard"
svga.vramSize = "268435456"
EOF
}

vmware_create() {
    local vmx_path="$1"
    check_vmrun

    local vmx_dir
    vmx_dir=$(dirname "$vmx_path")
    local vm_name
    vm_name=$(basename "$vmx_path" .vmx)

    # Determine CPU architecture
    local target_arch="aarch64"
    local safe_key="${HOST//-/_}"
    local target_sys="${TARGET_SYSTEMS["$safe_key"]:-}"
    if [[ "$target_sys" == x86_64-linux || "$(uname -m)" == "x86_64" ]]; then
        target_arch="x86_64"
    fi

    # Find or download NixOS Minimal ISO
    local iso_dir="${DEFAULT_VMW_ISO_DIR:-/Users/lamt/Virtual Machines.localized/VMWIsoImages}"
    mkdir -p "$iso_dir"
    local custom_iso="${iso_dir}/nixos-minimal-25.11.20260522.b77b3de-aarch64-linux.iso"
    local official_iso="${iso_dir}/latest-nixos-minimal-${target_arch}-linux.iso"
    local local_iso=""

    if [[ -f "$custom_iso" ]]; then
        info "Own-built custom NixOS ISO found: $custom_iso"
        local_iso="$custom_iso"
    elif [[ -f "$official_iso" ]]; then
        info "Official NixOS ISO found: $official_iso"
        local_iso="$official_iso"
    else
        # Wildcard fallback search (e.g. for any older or manual files matching target arch)
        for f in "$iso_dir"/nixos-minimal-*-"${target_arch}"-linux.iso "$iso_dir"/*"${target_arch}"*.iso; do
            if [[ -f "$f" ]]; then
                local_iso="$f"
                break
            fi
        done
    fi

    if [[ -z "$local_iso" ]]; then
        local_iso="$official_iso"
        local channel="nixos-24.11"
        local download_url="https://channels.nixos.org/${channel}/latest-nixos-minimal-${target_arch}-linux.iso"
        info "NixOS ISO not found in $iso_dir. Downloading official ISO from $download_url..."
        if ! curl -L "$download_url" -o "$local_iso"; then
            rm -f "$local_iso"
            die "Failed to download NixOS ISO from $download_url"
        fi
    fi

    info "NixOS ISO selected: $local_iso"

    # Always use "Virtual Disk.vmdk" for the recreated disk name
    local disk_name="Virtual Disk.vmdk"

    # Create Virtual Disk (.vmdk) using vmware-vdiskmanager
    local vdiskmanager="/Applications/VMware Fusion.app/Contents/Library/vmware-vdiskmanager"
    local disk_size="${VM_DISK_SIZE:-50}"
    info "Creating ${disk_size}GB VMware virtual disk ($disk_name)..."
    mkdir -p "$vmx_dir"
    if ! "$vdiskmanager" -c -s "${disk_size}GB" -a lsilogic -t 0 "${vmx_dir}/${disk_name}"; then
        die "Failed to create VMware virtual disk."
    fi

    # Generate VMX file content from scratch
    info "Generating VMX configuration file at $vmx_path..."
    generate_vmx_content "$vm_name" "$disk_name" "$local_iso" "$target_arch" > "$vmx_path"
    info "VMware VMX configuration generated successfully."
}
