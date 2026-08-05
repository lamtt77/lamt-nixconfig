#!/bin/sh
set -eu

echo "=== Starting Proxmox First Boot Setup ==="

# 1. Download target restore tarball before changing networking
echo "Downloading restoration config: @RESTORE_TARBALL_NAME@..."
curl -fsSL "@BOOTSTRAP_URL@/@RESTORE_TARBALL_NAME@" -o /tmp/configs.tar.gz

# 2. Verify the tarball hash
echo "Verifying hash of @RESTORE_TARBALL_NAME@..."
echo "@RESTORE_TARBALL_HASH@  /tmp/configs.tar.gz" | sha256sum -c

# 3. Validate tarball content
echo "Validating tarball integrity..."
tar -tzf /tmp/configs.tar.gz > /dev/null

# 4. Restore the reviewed host-local state. The artifact builder rejects
# /etc/pve, so normal installation cannot overwrite live pmxcfs authority.
echo "Extracting reviewed host-local state..."
tar -xzvf /tmp/configs.tar.gz -C /

# 5. Activate restored module and bootloader policy. Legacy BIOS uses GRUB;
# UEFI installations use the loader tracked by proxmox-boot-tool.
echo "Rebuilding initramfs and refreshing boot configuration..."
update-initramfs -u -k all
if [ ! -d /sys/firmware/efi ]; then
    update-grub
fi
proxmox-boot-tool refresh

# 6. Apply networking
echo "Applying new network interfaces..."
ifreload -a || systemctl restart networking

# 7. Rotate / lock temporary installer password.
echo "Disabling temporary installer root password..."
passwd -l root

echo "=== Proxmox First Boot Setup Complete ==="
sync

# A clean stopped transition is the provider-observed completion handshake.
# NXD then persists disk-only boot and starts the installed host once; no QEMU
# guest agent or SSH trust bootstrap is required for this Proxmox guest.
systemctl poweroff --no-block
