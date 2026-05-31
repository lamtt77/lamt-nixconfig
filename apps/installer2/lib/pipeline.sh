#!/usr/bin/env bash
# shellcheck disable=SC2154
# State Convergence Pipeline Library (installer2)

# --- Sub-helpers for Phase 2: OS Installation ---

build_and_copy_to_target() {
    local host="$1"
    local attr="$2"
    local mount_point="${3:-}"

    info "Building target configuration attribute '$attr' for $host..."
    local drv_path
    drv_path=$(nix_build "$host" "$attr") || return 1

    local copy_target="ssh://$SSH_USER@$CONNECTION_IP"
    [[ -n "$mount_point" ]] && copy_target="${copy_target}?remote-store=local?root=$mount_point"

    resolve_build_strategy "$host"
    if [[ "$STRATEGY" == "builder" || "$STRATEGY" == "target" ]]; then
        local builder_host_or_ip="${BUILDER#*@}"
        if [[ "$STRATEGY" != "target" && "$builder_host_or_ip" != "$CONNECTION_IP" ]]; then
            info "Copying store paths from builder to target..."
            warmup_remote_builder "$BUILDER" "$CONNECTION_IP"
            set_nix_command_opts --substitute
            # shellcheck disable=SC2029
            ssh "${SSH_COMMON_ARGS[@]}" -A "$BUILDER" "export NIX_SSHOPTS='$SSH_COMMON_OPTIONS' && nix copy --to \"$copy_target\" $drv_path $NIX_OPTS_SSH"
        fi
    else
        nix_copy_closure "$SSH_USER@$CONNECTION_IP" "$drv_path"
    fi
    echo "$drv_path"
}

run_disko_partitioning() {
    local host="$1"
    local sudo_cmd="$2"

    local disko_script
    disko_script=$(build_and_copy_to_target "$host" "config.system.build.diskoScript") || exit 1

    confirm_or_exit "WARNING: This will partition the disk and erase all data on $CONNECTION_IP ($host)."
    info "Executing Disko partitioning..."
    ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd $disko_script --mode disko"
}

init_zram_swap() {
    info "Low Memory Optimization: Activating target ZRAM swap..."
    ssh_cmd "$SSH_USER@$CONNECTION_IP" "
        modprobe zram 2>/dev/null || true
        echo 1073741824 > /sys/block/zram0/disksize 2>/dev/null || true
        mkswap /dev/zram0 >/dev/null 2>&1 || true
        swapon /dev/zram0 >/dev/null 2>&1 || true
    "
}

init_physical_swap() {
    local sudo_cmd="$1"
    info "Low Memory Optimization: Provisioning 2GB physical swapfile on /mnt/swapfile..."
    ssh_cmd "$SSH_USER@$CONNECTION_IP" "
        $sudo_cmd fallocate -l 2G /mnt/swapfile || $sudo_cmd dd if=/dev/zero of=/mnt/swapfile bs=1M count=2048 status=none
        $sudo_cmd chmod 600 /mnt/swapfile
        $sudo_cmd mkswap /mnt/swapfile
        $sudo_cmd swapon /mnt/swapfile
    "
}


install_minimal_stage_1() {
    local host="$1"
    local sudo_cmd="$2"
    local installer_dir
    installer_dir="$(dirname "$LIB_DIR")"
    local template_dir="$installer_dir/templates"

    info "Starting Stage 1 Minimal Installation..."

    # 1. Hardware Detection
    ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd nixos-generate-config --force --root /mnt"

    # 2. Stage Base Configuration Files
    info "Staging minimal configuration files into target mountpoint..."
    copy_to_target() {
        local dest="$1"
        ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd tee '$dest' >/dev/null"
    }

    cat "$ROOT_DIR/defines.nix" | copy_to_target /mnt/etc/nixos/defines.nix
    cat "$ROOT_DIR/modules/os/linux/autorun/zramswap.nix" | copy_to_target /mnt/etc/nixos/zramswap.nix

    cat "$installer_dir/extra-config-base.nix" | copy_to_target /mnt/etc/nixos/extra-config.nix

    # 3. Network Configuration
    local net_import=""
    if [[ -n "${STATIC_IP:-}" ]]; then
        net_import="./persistent-net.nix"
        configure_persistent_networking "$host" "$sudo_cmd" "$template_dir"
    fi

    # 4. Bootloader Selection
    configure_minimal_bootloader "$sudo_cmd" "$installer_dir"

    # 5. Staging Main Stage-1 configuration.nix wrapper
    sed -e "s/{{HOSTNAME}}/$host/g" \
        -e "s|{{NETWORK_IMPORT}}|$net_import|g" \
        "$template_dir/minimal-configuration.nix" | copy_to_target /mnt/etc/nixos/configuration.nix

    # 5.5 Staging Target Host SSH Keys
    info "Zero-Trust: Staging pre-generated target host SSH key pair..."
    local local_key_file="${DEFAULT_SECRETS_REPO}/hosts/${host}/ssh_host_ed25519_key"
    local local_pub_file="${local_key_file}.pub"
    if [[ -d "$DEFAULT_SECRETS_REPO" && -f "$DEFAULT_SECRETS_REPO/.sops.yaml" && -f "$local_key_file" ]]; then
         ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd mkdir -p /mnt/etc/ssh"
         cat "$local_key_file" | ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd tee /mnt/etc/ssh/ssh_host_ed25519_key >/dev/null"
         ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key"
         if [[ -f "$local_pub_file" ]]; then
              cat "$local_pub_file" | ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd tee /mnt/etc/ssh/ssh_host_ed25519_key.pub >/dev/null"
              ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd chmod 644 /mnt/etc/ssh/ssh_host_ed25519_key.pub"
         fi
         info "Target host SSH key staged."
    else
         warn "No pre-generated local SSH host key found at $local_key_file. Skipping identity staging."
    fi

    # 6. Minimal Installation Execution
    info "Running nixos-install..."
    local gc_env=""
    [[ "${LOW_MEM:-no}" == "yes" ]] && gc_env="export GC_INITIAL_HEAP_SIZE=1M GC_DONT_GC=1 NIX_DISABLE_AUTO_GC=1;"
    ssh_cmd "$SSH_USER@$CONNECTION_IP" "$gc_env $sudo_cmd nixos-install --no-root-password"

}

configure_minimal_bootloader() {
    local sudo_cmd="$1"
    local installer_dir="$2"
    local firmware="uefi"

    if [[ "${BIOS_TYPE:-}" == "seabios" ]]; then
        firmware="bios"
        info "Forcing firmware bootloader: bios"
    elif ssh_cmd "$SSH_USER@$CONNECTION_IP" "test -d /sys/firmware/efi"; then
        firmware="uefi"
        info "Detected UEFI bootloader interface."
    else
        firmware="bios"
        info "Detected legacy BIOS bootloader interface."
    fi

    cat "$installer_dir/bootloader-$firmware.nix" | ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd tee /mnt/etc/nixos/bootloader.nix >/dev/null"

    if [[ "$firmware" == "bios" ]]; then
        local primary_disk
        primary_disk=$(ssh_cmd "$SSH_USER@$CONNECTION_IP" "lsblk -d -n -o NAME | grep -E '^(sda|vda|nvme0n1)$' | head -n 1 || true")
        primary_disk="${primary_disk:-sda}"
        if [[ "$primary_disk" != "sda" ]]; then
             ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd sed -i \"s|/dev/sda|/dev/$primary_disk|g\" /mnt/etc/nixos/bootloader.nix"
        fi
    fi
}

configure_persistent_networking() {
    local host="$1"
    local sudo_cmd="$2"
    local template_dir="$3"

    local subnet="${VM_SUBNET:-192.168.1.0/24}"
    local cidr
    cidr=$(echo "$subnet" | cut -d'/' -f2)
    [[ -z "$cidr" || "$cidr" == "$subnet" ]] && cidr="24"
    local gateway
    gateway="$(echo "$subnet" | cut -d. -f1-3).1"

    local iface="eth0"
    [[ "$host" == router-* ]] && iface="eth1"

    local vlan_config=""
    local ip_interface="$iface"
    if [[ -n "${BOOTSTRAP_VLAN:-}" ]]; then
        vlan_config="vlans.vlan${BOOTSTRAP_VLAN} = { id = ${BOOTSTRAP_VLAN}; interface = \"$iface\"; };"
        ip_interface="vlan${BOOTSTRAP_VLAN}"
    fi

    sed -e "s/{{GATEWAY}}/$gateway/g" \
        -e "s/{{INTERFACE}}/$ip_interface/g" \
        -e "s/{{IP}}/$STATIC_IP/g" \
        -e "s/{{CIDR}}/$cidr/g" \
        -e "s|{{VLAN_CONFIG}}|$vlan_config|g" \
        "$template_dir/persistent-net.nix" | ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd tee /mnt/etc/nixos/persistent-net.nix >/dev/null"
}

install_full_single_stage() {
    local host="$1"
    local sudo_cmd="$2"

    local system_drv
    system_drv=$(build_and_copy_to_target "$host" "config.system.build.toplevel" "/mnt") || exit 1

    info "Zero-Trust: Staging pre-generated target host SSH key pair..."
    local local_key_file="${DEFAULT_SECRETS_REPO}/hosts/${host}/ssh_host_ed25519_key"
    if [[ -d "$DEFAULT_SECRETS_REPO" && -f "$DEFAULT_SECRETS_REPO/.sops.yaml" && -f "$local_key_file" ]]; then
         ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd mkdir -p /mnt/etc/ssh"
         cat "$local_key_file" | ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd tee /mnt/etc/ssh/ssh_host_ed25519_key >/dev/null"
         ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key"
         info "Target host SSH key staged."
    else
         warn "No pre-generated local SSH host key found at $local_key_file. Skipping identity staging."
    fi

    info "Running nixos-install..."
    local gc_env=""
    [[ "${LOW_MEM:-no}" == "yes" ]] && gc_env="export GC_INITIAL_HEAP_SIZE=1M GC_DONT_GC=1 NIX_DISABLE_AUTO_GC=1;"
    ssh_cmd "$SSH_USER@$CONNECTION_IP" "$gc_env $sudo_cmd nixos-install --no-root-password --no-channel-copy --system $system_drv"
}

# --- Kexec Takeover logic ---
handle_kexec_takeover() {
    if [[ "$KEXEC_BOOT" == "no" ]]; then
        info "Kexec takeover bypassed by flag options."
        return 0
    fi

    if [[ "$KEXEC_BOOT" == "auto" ]]; then
        # Check if target is already running an installer (State 1)
        if ssh_cmd "$SSH_USER@$CONNECTION_IP" "command -v nixos-install >/dev/null 2>&1"; then
            local fs_type
            fs_type=$(ssh_cmd "$SSH_USER@$CONNECTION_IP" "findmnt / -o FSTYPE -n" 2>/dev/null || echo "unknown")
            if [[ "$fs_type" == "overlay" || "$fs_type" == "squashfs" || "$fs_type" == "tmpfs" || "$fs_type" == "iso9660" ]]; then
                info "Target is booted to a NixOS Installation CD / Ephemeral Live OS. Bypassing Kexec."
                return 0
            fi
        fi
    fi

    info "Target requires in-memory boot transition. Preparing Kexec..."
    if [[ -z "${LOW_MEM:-}" ]]; then
        export LOW_MEM="yes"
        info "Auto-enabled LOW_MEM=yes for Kexec takeover safety."
    fi

    local arch
    arch=$(ssh_cmd "$SSH_USER@$CONNECTION_IP" "uname -m")
    local kexec_url
    case "$arch" in
        x86_64 | aarch64)
            kexec_url="${KEXEC_BASE_URL}-${arch}-linux.tar.gz"
            ;;
        *)
            die "Architecture unsupported for Kexec: $arch"
            ;;
    esac

    # Download
    info "Downloading kexec package from $kexec_url..."
    ssh_cmd "$SSH_USER@$CONNECTION_IP" "
        mkdir -p /tmp/kexec && cd /tmp/kexec
        if command -v curl >/dev/null; then
            curl -L '$kexec_url' -o kexec.tar.gz
        elif command -v wget >/dev/null; then
            wget -O kexec.tar.gz '$kexec_url'
        else
            exit 1
        fi
        tar -xzf kexec.tar.gz
    " || die "Failed to download/extract kexec bundle."

    # Low-memory preparations
    if [[ "${LOW_MEM:-no}" == "yes" ]]; then
        info "Tuning target memory parameters for in-memory boot..."
        local sudo_prefix=""
        [[ "$SSH_USER" != "root" ]] && sudo_prefix="sudo"
        ssh_cmd "$SSH_USER@$CONNECTION_IP" "
            $sudo_prefix systemctl stop snapd packagekit unattended-upgrades udisks2 2>/dev/null || true
            sync
            echo 3 | $sudo_prefix tee /proc/sys/vm/drop_caches >/dev/null
            if ! grep -q swap /proc/swaps; then
                # Temporary swap on root
                $sudo_prefix fallocate -l 1G /swapfile || $sudo_prefix dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
                $sudo_prefix chmod 600 /swapfile
                $sudo_prefix mkswap /swapfile
                $sudo_prefix swapon /swapfile
            fi
        "
    fi

    # Execute kexec takeover
    info "Launching Kexec kernel takeover..."
    local tweaks=""
    if [[ "${LOW_MEM:-no}" == "yes" ]]; then
        tweaks+="sed -i 's/zswap.enabled=1/zswap.enabled=0/' run;"
        tweaks+="sed -i 's/--command-line \"/--command-line \"initrd.tmpfs.size=80% /' run;"
    fi

    local exec_cmd="sudo"
    [[ "$SSH_USER" == "root" ]] && exec_cmd=""

    ssh_cmd "$SSH_USER@$CONNECTION_IP" "
        cd /tmp/kexec
        if [ ! -f run ]; then
            DIR=\$(find . -maxdepth 2 -name run -type f -exec dirname {} \; | head -n 1)
            [[ -n \"\$DIR\" ]] && cd \"\$DIR\"
        fi
        $tweaks
        nohup $exec_cmd ./run > kexec.log 2>&1 &
    " || true # ignore dropped connection errors

    sleep 15
    export SSH_USER="root" # Kexec live ISO comes up as root
    wait_for_ssh "$SSH_USER@$CONNECTION_IP"
    info "Kexec takeover complete. Target is online."
}

# --- Deployment / Bootstrap Commands ---

cmd_deploy() {
    export DEPLOY_ACTIVE="yes"
    info "Initializing State Convergence Deployment Pipeline for $HOST at $CONNECTION_IP..."

    # Phase 2: System Installation & Transition
    handle_kexec_takeover

    if [[ "${LOW_MEM:-no}" == "yes" ]]; then
        init_zram_swap
    fi

    local sudo_cmd=""
    [[ "$SSH_USER" != "root" ]] && sudo_cmd="sudo"

    # Determine building options
    if [[ "${BUILD_ON:-local}" == "remote" ]]; then
        export BUILDER="$SSH_USER@$CONNECTION_IP"
    fi

    resolve_build_strategy "$HOST"
    local stage_strategy="single"
    if [[ "${BUILD_ON:-local}" == "remote" || "$STRATEGY" == "target" ]]; then
        stage_strategy="two-stage"
        if [[ "$STRATEGY" == "target" && -z "${STAGE:-}" ]]; then
            info "Auto-selecting two-stage installation because build is delegated directly to target host."
        fi
    fi
    if [[ -n "${STAGE:-}" ]]; then
        [[ "$STAGE" == "1" || "$STAGE" == "single" ]] && stage_strategy="single"
        [[ "$STAGE" == "2" || "$STAGE" == "two-stage" ]] && stage_strategy="two-stage"
    fi
    info "Deployment strategy: $stage_strategy"

    # Disk formatting
    run_disko_partitioning "$HOST" "$sudo_cmd"

    if [[ "${LOW_MEM:-no}" == "yes" ]]; then
        init_physical_swap "$sudo_cmd"
    fi

    # Stage-1 installation
    if [[ "$stage_strategy" == "single" ]]; then
        install_full_single_stage "$HOST" "$sudo_cmd"
    else
        install_minimal_stage_1 "$HOST" "$sudo_cmd"
    fi

    # Reboot target to boot into State 2
    info "Installation complete. Rebooting target system..."
    ssh_cmd "$SSH_USER@$CONNECTION_IP" "$sudo_cmd reboot" || true
    [[ -n "${STATIC_IP:-}" ]] && export CONNECTION_IP="$STATIC_IP"

    sleep 15

    if [[ -z "${STATIC_IP:-}" ]]; then
        info "Re-detecting target IP post-reboot..."
        local new_ip=""
        if [[ -n "${VMX_PATH:-}" && "$(type -t vmware_get_ip)" == "function" ]]; then
            new_ip=$(vmware_get_ip "$VMX_PATH")
        elif [[ -n "${VMID:-}" && "$(type -t qm_get_ip)" == "function" ]]; then
            new_ip=$(qm_get_ip)
        elif [[ -n "${DO_REGION:-}" && "$(type -t do_get_ip)" == "function" ]]; then
            new_ip=$(do_get_ip "$HOST")
        fi

        if [[ -n "$new_ip" ]]; then
            info "New IP detected: $new_ip"
            export CONNECTION_IP="$new_ip"
        fi
    fi

    # Phase 3: Profile Activation & Convergence
    if [[ "$stage_strategy" == "two-stage" ]]; then
        export SSH_USER="root"
        wait_for_ssh "$SSH_USER@$CONNECTION_IP"
        [[ "${BUILD_ON:-local}" == "remote" ]] && export BUILDER="$SSH_USER@$CONNECTION_IP"

        info "Entering Phase 3 (Stage 2 Switch)..."
        cmd_switch

        # Switch to default non-root user to verify production environment SSH
        local final_user="${NIXUSER:-root}"
        if [[ "$final_user" != "root" ]]; then
            export SSH_USER="$final_user"
        fi

        info "Verifying SSH connection connectivity (using user '$SSH_USER')..."
        wait_for_ssh "$SSH_USER@$CONNECTION_IP"

        # Cleanup temporary workspace files on target
        if [[ -n "$NIX_CFG" ]]; then
            local root_src="/root/$NIX_CFG"
            info "Cleaning up temporary build files on target..."
            if [[ "$SSH_USER" == "root" ]]; then
                ssh_cmd "$SSH_USER@$CONNECTION_IP" "rm -rf $root_src || true"
            else
                ssh_cmd "$SSH_USER@$CONNECTION_IP" "sudo rm -rf $root_src || true"
            fi
        fi

        # Final reboot to load the production kernel and final configuration
        info "Stage 2 activation complete. Rebooting target system into production kernel..."
        if [[ "$SSH_USER" == "root" ]]; then
            ssh_cmd "$SSH_USER@$CONNECTION_IP" "reboot" || true
        else
            ssh_cmd "$SSH_USER@$CONNECTION_IP" "sudo reboot" || true
        fi
        sleep 15

        info "Waiting for target system to boot up..."
        wait_for_ssh "$SSH_USER@$CONNECTION_IP"
    else
        export SSH_USER="${NIXUSER:-root}"
        wait_for_ssh "$SSH_USER@$CONNECTION_IP"

        # Cleanup temporary workspace files on target for single stage
        if [[ -n "$NIX_CFG" ]]; then
            local root_src="/root/$NIX_CFG"
            ssh_cmd "$SSH_USER@$CONNECTION_IP" "sudo rm -rf $root_src || true"
        fi
    fi

    # Archive/Pin the resulting lockfile for manual recovery reference
    archive_flake_lock "$HOST"

    info "State Convergence Deployment successfully finished!"
}

# --- System switch / Update Commands ---

cmd_switch() {
    local action="${1:-switch}"
    resolve_build_strategy "$HOST"

    if [[ "$HOST" == "$(hostname -s)" && ( -z "${IP:-}" || "$IP" == "127.0.0.1" ) ]]; then
        info "Detected local system switch configuration..."
        if [[ "$(uname)" == "Darwin" ]]; then
            local darwin_action="$action"
            if [[ "$darwin_action" == "bootentry" ]]; then
                warn "Darwin does not support bootentry action; falling back to switch."
                darwin_action="switch"
            fi
            sudo darwin-rebuild "$darwin_action" --flake "${FLAKE_URI}#$HOST"
        else
            sudo nixos-rebuild "$action" --flake "${FLAKE_URI}#$HOST"
        fi
        archive_flake_lock "$HOST"
    else
        info "Detected remote system switch deployment on $CONNECTION_IP..."

        # Verify SSH connection first
        ssh "${SSH_COMMON_ARGS[@]}" "$SSH_USER@$CONNECTION_IP" "true" 2>/dev/null || die "Cannot establish SSH connection to target $SSH_USER@$CONNECTION_IP"

        validate_and_sync_target_host_key "$HOST"

        local system_drv
        system_drv=$(nix_build "$HOST") || exit 1

        resolve_build_strategy "$HOST"
        if [[ "$STRATEGY" == "builder" || "$STRATEGY" == "target" ]]; then
            if [[ "$STRATEGY" != "target" ]]; then
                info "Build complete on builder. Copying derivation directly to target..."
                warmup_remote_builder "$BUILDER" "$CONNECTION_IP"
                set_nix_command_opts --substitute
                # shellcheck disable=SC2029
                ssh "${SSH_COMMON_ARGS[@]}" -A "$BUILDER" "export NIX_SSHOPTS='$SSH_COMMON_OPTIONS' && nix copy --to \"ssh://$SSH_USER@$CONNECTION_IP\" $system_drv $NIX_OPTS_SSH"
            fi
        else
            nix_copy_closure "$SSH_USER@$CONNECTION_IP" "$system_drv"
        fi

        # Magic Rollback Safety Switch
        if [[ "${DEPLOY_ACTIVE:-no}" != "yes" && "$action" != "bootentry" ]]; then
            info "Scheduling fallback rollback command (Magic Revert) on target..."
            local rollback_seconds=60
            local rollback_cmd="sleep $rollback_seconds && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration rollback"
            # Run rollback scheduler in the background on target
            ssh_cmd "$SSH_USER@$CONNECTION_IP" "nohup bash -c '$rollback_cmd' >/dev/null 2>&1 & echo \$! > /tmp/rollback.pid"
        fi

        info "Registering system profile generation & activating configuration..."
        local activate_cmd="set -euo pipefail
          sudo nix-env -p /nix/var/nix/profiles/system --set ${system_drv}
          sudo ${system_drv}/bin/switch-to-configuration ${action}"

        if ! ssh_cmd "$SSH_USER@$CONNECTION_IP" "$activate_cmd"; then
            if [[ "${DEPLOY_ACTIVE:-no}" == "yes" ]]; then
                warn "Activation command returned a warning/failure on bootstrap target."
                local check_user="${NIXUSER:-$SSH_USER}"
                info "Verifying SSH connection connectivity (using user '$check_user')..."
                if ssh_cmd "$check_user@$CONNECTION_IP" "true" 2>/dev/null; then
                    warn "SSH connection verified. Treating activation warning as non-fatal on bootstrap."
                else
                    die "Activation failed and target is unreachable via SSH."
                fi
            else
                warn "Activation command returned failure. Executing fallback check..."
                sleep 5
                # Retry connection and force rollback cancellation if verified
                if ssh_cmd "$SSH_USER@$CONNECTION_IP" "true" 2>/dev/null; then
                     ssh_cmd "$SSH_USER@$CONNECTION_IP" "[[ -f /tmp/rollback.pid ]] && sudo kill \$(cat /tmp/rollback.pid) || true"
                fi
                exit 1
            fi
        fi

        # Cancel scheduled rollback on success
        if [[ "${DEPLOY_ACTIVE:-no}" != "yes" ]]; then
            ssh_cmd "$SSH_USER@$CONNECTION_IP" "[[ -f /tmp/rollback.pid ]] && sudo kill \$(cat /tmp/rollback.pid) && rm /tmp/rollback.pid || true"
        fi

        # Archive/Pin the resulting lockfile
        archive_flake_lock "$HOST"
    fi
}

archive_flake_lock() {
    local host="$1"
    local flake_ref="${FLAKE_URI:-path:.}"
    # Only archive if the source is local
    is_local_flake_ref "$flake_ref" || return

    local dest_lock="$ROOT_DIR/hosts/$host/flake.lock"
    local source_lock="$ROOT_DIR/flake.lock"

    if [[ -f "$source_lock" ]]; then
        info "Archiving local flake.lock for host recovery reference..."
        mkdir -p "$(dirname "$dest_lock")"
        cp "$source_lock" "$dest_lock" || warn "Failed to copy local flake.lock."
    fi
}
