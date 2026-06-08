#!/bin/sh
set -eu

echo "=== Starting Proxmox First Boot Setup ==="

# 1. Refresh boot configuration
echo "Refreshing boot tool..."
proxmox-boot-tool refresh

# 2. Download target restore tarball before changing networking
echo "Downloading restoration config: @RESTORE_TARBALL_NAME@..."
curl -fsSL "@BOOTSTRAP_URL@/@RESTORE_TARBALL_NAME@" -o /tmp/configs.tar.gz

# 3. Verify the tarball hash
echo "Verifying hash of @RESTORE_TARBALL_NAME@..."
echo "@RESTORE_TARBALL_HASH@  /tmp/configs.tar.gz" | sha256sum -c

# 4. Validate tarball content
echo "Validating tarball integrity..."
tar -tzf /tmp/configs.tar.gz > /dev/null

# 5. Write final network interfaces
echo "Writing final network configuration..."
cat << 'EOF' > /etc/network/interfaces
@NETWORK_INTERFACES@
EOF

# 6. Apply networking
echo "Applying new network interfaces..."
ifreload -a || systemctl restart networking

# 7. Extract the validated restore tarball
echo "Extracting restored configuration files..."
tar -xzvf /tmp/configs.tar.gz -C /

# 8. Rotate / lock temporary installer password
echo "Disabling temporary installer root password..."
passwd -l root

echo "=== Proxmox First Boot Setup Complete ==="
