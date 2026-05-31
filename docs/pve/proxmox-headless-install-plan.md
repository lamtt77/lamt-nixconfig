# Headless Proxmox VE Installation Guide

## Overview

This guide implements headless installation of Proxmox VE 9 using iPXE and the Proxmox installer's answer file feature, served by HA NixOS routers with Keepalived failover. Authentication is **SSH key-based only** (no passwords), and content synchronization is handled via **Nix Store** (deterministic builds on both nodes).

## Architecture

- **VIP**: 192.168.1.1 (Keepalived managed)
- **Router Main**: 192.168.1.2 (priority 150)
- **Router Backup**: 192.168.1.3 (priority 100)
- **Target pve1**: 192.168.1.15
- **Target pve2**: 192.168.1.5

## Phase 1: Configure HA Routers

### 1.1 Router-Main Configuration (`hosts/router-main/default.nix`)

```nix
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/os/linux/services/pxe-ipxe.nix
    ../../modules/os/linux/services/router.nix
  ];

  networking = {
    hostName = "router-main";
    hostId = "a1b2c3d4";  # Generate with: head -c 8 /dev/urandom | od -A n -t x1 | tr -d ' \n'

    interfaces.eth0 = {
      ipv4.addresses = [{
        address = "192.168.0.2";
        prefixLength = 24;
      }];
    };
  };

  # ============================================================================
  # ROUTER MODULE CONFIGURATION
  # ============================================================================

  modules.os.linux.services.router = {
    enable = true;
    isMaster = true;

    hostname = "router-main";

    wanIp = "192.168.0.2";
    lanIp = "192.168.1.2";
    syncIp = "192.168.4.2";
    vipLan = "192.168.1.1";

    dnsServers = [ "1.1.1.1" "1.0.0.1" ];

    enableHA = true;
    priority = 150;  # Master priority
  };

  # ============================================================================
  # PXE/iPXE MODULE CONFIGURATION
  # ============================================================================

  modules.os.linux.services.pxe-ipxe = {
    enable = true;
    isMaster = true;

    pxeVip = config.modules.os.linux.services.router.vipLan;  # 192.168.1.1
    nodeIp = config.modules.os.linux.services.router.lanIp;   # 192.168.1.2

    pxeInterface = "eth1.10";

    # Target Proxmox installation (pve2)
    targetHostname = "pve2";
    targetIp = "192.168.1.5"; # This will be overridden by the answer file
    targetNetmask = "24";
    targetGateway = "192.168.1.1";

    # SSH keys for root access (REQUIRED - no password auth)
    # This is now handled by the pve-answer.toml file
    # sshAuthorizedKeys = [
    #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJqXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX user@laptop"
    # ];

    # DHCP is handled by router.nix, so disable here
    enableDhcp = false;
  };

  # ============================================================================
  # EXTEND ROUTER.NIX KEA DHCP WITH PXE OPTIONS
  # ============================================================================

  services.kea.dhcp4.settings.subnet4 = lib.mkForce [
    {
      id = 1;
      subnet = "192.168.1.0/24";
      option-data = [
        {
          name = "routers";
          data = config.modules.os.linux.services.router.vipLan;
        }
        {
          name = "domain-name-servers";
          data = config.modules.os.linux.services.router.vipLan;
        }
      ];
      pools = [{ pool = "192.168.1.100 - 192.168.1.199"; }];

      # Static reservations
      reservations = [
        {
          hw-address = "c8:b8:2f:5d:4b:8d";
          ip-address = "192.168.1.4";
          hostname = "eero";
        }
      ];

      # PXE BOOT OPTIONS
      next-server = config.modules.os.linux.services.router.vipLan;  # 192.168.1.1
      boot-file-name = "ipxe/ipxe.efi";
    }
  ];

  # ============================================================================
  # ADDITIONAL SYSTEM CONFIGURATION
  # ============================================================================

  # Enable SSH for management
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # System packages
  environment.systemPackages = with pkgs;
    [
      vim
      tmux
      htop
      iotop
      ncdu
    ];

  system.stateVersion = "24.05";
}
```

### 1.2 Router-Backup Configuration (`hosts/router-backup/default.nix`)

```nix
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/os/linux/services/pxe-ipxe.nix
    ../../modules/os/linux/services/router.nix
  ];

  networking = {
    hostName = "router-backup";
    hostId = "e5f6g7h8";  # Generate unique ID

    interfaces.eth0 = {
      ipv4.addresses = [{
        address = "192.168.0.3";
        prefixLength = 24;
      }];
    };
  };

  # ============================================================================
  # ROUTER MODULE CONFIGURATION
  # ============================================================================

  modules.os.linux.services.router = {
    enable = true;
    isMaster = false;  # This is the backup node

    hostname = "router-backup";

    wanIp = "192.168.0.3";
    lanIp = "192.168.1.3";
    syncIp = "192.168.4.3";
    vipLan = "192.168.1.1";

    dnsServers = [ "1.1.1.1" "1.0.0.1" ];

    enableHA = true;
    priority = 100;  # Backup priority (lower than master)
  };

  # ============================================================================
  # PXE/iPXE MODULE CONFIGURATION
  # ============================================================================

  modules.os.linux.services.pxe-ipxe = {
    enable = true;
    isMaster = false;  # This is the backup node

    pxeVip = config.modules.os.linux.services.router.vipLan;  # 192.168.1.1
    nodeIp = config.modules.os.linux.services.router.lanIp;   # 192.168.1.3

    pxeInterface = "eth1.10";

    # Target Proxmox installation (same as master)
    targetHostname = "pve2";
    targetIp = "192.168.1.5"; # This will be overridden by the answer file
    targetNetmask = "24";
    targetGateway = "192.168.1.1";

    # SSH keys (same as master - REQUIRED)
    # This is now handled by the pve-answer.toml file
    # sshAuthorizedKeys = [
    #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJqXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX user@laptop"
    # ];

    # DHCP is handled by router.nix, so disable here
    enableDhcp = false;
  };

  # ============================================================================
  # EXTEND ROUTER.NIX KEA DHCP WITH PXE OPTIONS
  # ============================================================================

  services.kea.dhcp4.settings.subnet4 = lib.mkForce [
    {
      id = 1;
      subnet = "192.168.1.0/24";
      option-data = [
        {
          name = "routers";
          data = config.modules.os.linux.services.router.vipLan;
        }
        {
          name = "domain-name-servers";
          data = config.modules.os.linux.services.router.vipLan;
        }
      ];
      pools = [{ pool = "192.168.1.100 - 192.168.1.199"; }];

      # Static reservations
      reservations = [
        {
          hw-address = "c8:b8:2f:5d:4b:8d";
          ip-address = "192.168.1.4";
          hostname = "eero";
        }
      ];

      # PXE BOOT OPTIONS
      next-server = config.modules.os.linux.services.router.vipLan;  # 192.168.1.1
      boot-file-name = "ipxe/ipxe.efi";
    }
  ];

  # ============================================================================
  # ADDITIONAL SYSTEM CONFIGURATION
  # ============================================================================

  # Enable SSH for management
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # System packages
  environment.systemPackages = with pkgs;
    [
      vim
      tmux
      htop
      iotop
      ncdu
    ];

  system.stateVersion = "24.05";
}
```

### 1.3 Deploy Configuration

```bash
# On router-main
sudo nixos-rebuild switch

# On router-backup
sudo nixos-rebuild switch

# Verify VIP
ip addr show eth1.10 | grep 192.168.1.1

# Check Keepalived status
sudo systemctl status keepalived
sudo journalctl -u keepalived -f

# Verify services
sudo systemctl status nginx
sudo systemctl status kea-dhcp4-server
sudo systemctl status tftpd-hpa
```

## Phase 2: Customize Proxmox Installation

### 2.1 Generate SSH Key

```bash
# Generate SSH key if needed
ssh-keygen -t ed25519 -C "proxmox-admin"

# Copy public key content
cat ~/.ssh/id_ed25519.pub
```

### 2.2 Update SSH Keys in Configuration

Edit `modules/os/linux/services/pxe-ipxe.nix` to update the `root-ssh-keys` in the `answerTomlFile` definition.

```nix
# Example snippet from pxe-ipxe.nix
answerTomlFile = pkgs.writeText "pve-answer.toml" ''
  [global]
  # ...
  root-ssh-keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIYourActualKeyHere... user@laptop"
  ]
  # ...
'';
```

### 2.3 Customize for Target Node

The `pve-answer.toml` file is generated dynamically based on the `pxe-ipxe` module options.

**For pve1 installation (192.168.1.15):**

```nix
modules.os.linux.services.pxe-ipxe = {
  targetHostname = "pve1";
  targetIp = "192.168.1.15";
  # ... rest stays the same
};
```

**For pve2 installation (192.168.1.5):**

```nix
modules.os.linux.services.pxe-ipxe = {
  targetHostname = "pve2";
  targetIp = "192.168.1.5";
  # ... rest stays the same
};
```

### 2.4 Rebuild Both Routers

```bash
# On router-main
sudo nixos-rebuild switch

# On router-backup
sudo nixos-rebuild switch

# Both nodes now have identical configuration via Nix Store
```

## Phase 3: Install Proxmox on Target Server

### 3.1 Pre-Installation Checks

```bash
# On either router (both have identical files), verify files are ready
ls -lh /srv/ipxe/proxmox/
# Should show: linux, initrd, proxmox.iso

ls -lh /srv/ipxe/pve-answer.toml
# Should show: pve-answer.toml

ls -lh /srv/ipxe/first-boot.sh
# Should show: first-boot.sh

ls -lh /var/lib/tftpboot/ipxe/
# Should show: ipxe.efi

# Test HTTP access
curl http://192.168.1.1/pve-answer.toml
curl http://192.168.1.1/first-boot.sh
curl http://192.168.1.1/proxmox/linux
```

### 3.2 Boot Target Server

**For Dell R720 (pve2):**

1. Access iLO/iDRAC
2. Navigate to Virtual Console
3. Power on server
4. Press F11 for Boot Menu
5. Select "Network Boot" or "PXE Boot"
6. Select UEFI Network Boot

**For HP ProLiant (pve1):**

1. Access iLO
2. Launch Remote Console
3. Power on server
4. Press F12 for Network Boot
5. Select appropriate NIC

### 3.3 Monitor Installation

**Watch DHCP leases:**

```bash
sudo journalctl -u kea-dhcp4-server -f
```

**Watch nginx access:**

```bash
sudo tail -f /var/log/nginx/access.log
```

**Watch TFTP requests:**

```bash
sudo journalctl -u tftpd-hpa -f
```

### 3.4 Installation Process

The automated installation will:

1. PXE boot from TFTP (load ipxe.efi)
2. Execute iPXE script (fetch kernel/initrd)
3. Boot Proxmox installer
4. Fetch `auto-installer-mode.toml` from embedded ISO
5. Fetch `pve-answer.toml` from HTTP
6. Detect disks and create ZFS pool
7. Install Proxmox VE packages
8. Configure networking
9. Reboot into Proxmox
10. On first boot, execute `first-boot.sh` to refresh bootloader configuration

**Expected duration:** 15-30 minutes depending on hardware

## Phase 4: Post-Installation Configuration

### 4.1 Access Proxmox Web Interface

After reboot, access:

- pve1: https://192.168.1.15:8006
- pve2: https://192.168.1.5:8006

Login:

- Username: `root`
- Password: (what you set in `pve-answer.toml`)

### 4.2 Verify Installation

```bash
# SSH to new Proxmox node
ssh root@192.168.1.5

# Check Proxmox version
pveversion -v

# Check ZFS pool
zpool status
zpool list

# Check network
ip addr show
ip route show

# Check services
systemctl status pve-cluster
systemctl status pvedaemon
systemctl status pveproxy
```

### 4.3 Configure Advanced Networking (LACP/VLANs)

The complex network configuration is now handled automatically by the `pve-answer.toml` file during installation. No manual configuration is needed here.

### 4.4 Set Up Cluster (Optional)

If installing multiple nodes:

```bash
# On pve1 (first node)
pvecm create proxmox-cluster

# On pve2 (joining node)
pvecm add 192.168.1.15
```

## Troubleshooting

### DHCP Not Working

```bash
# Check Kea is running
sudo systemctl status kea-dhcp4-server

# Check DHCP leases
sudo journalctl -u kea-dhcp4-server -f
```

### TFTP Timeout

```bash
# Check TFTP service
sudo systemctl status tftpd-hpa

# Test TFTP manually
tftp 192.168.1.1
> get ipxe/ipxe.efi
> quit

# Check firewall
sudo iptables -L -n | grep 69
```

### HTTP Files Not Found / Parse Errors

```bash
# Check nginx
sudo systemctl status nginx
sudo nginx -t

# Check file permissions
ls -la /srv/ipxe/
sudo chmod -R 755 /srv/ipxe

# Test HTTP access
curl -X POST http://192.168.1.1/pve-answer.toml -d '{}' -H 'Content-Type: application/json'
# Expected: 200 OK and content of pve-answer.toml
```

### Bootloader Setup Errors

This should now be handled by the `first-boot.sh` script. If issues persist, check the script's execution.

```bash
# SSH to new Proxmox node
ssh root@192.168.1.5

# Check first-boot script logs
journalctl -u first-boot.service # (assuming systemd service is created by installer)
```

### Storage Configuration Issues

If ZFS mirror fails:

```bash
# Boot to installer shell
# Check available disks
lsblk

# Check disk sizes
fdisk -l

# Manual ZFS pool creation if needed
zpool create -f -o ashift=12 rpool mirror /dev/sda /dev/sdb
```

## Security Considerations

1. **Change Default Passwords**: Immediately after installation
2. **SSH Keys Only**: Disable password authentication
3. **Firewall**: Configure iptables/ufw
4. **Updates**: Keep Proxmox and NixOS updated
5. **Backup**: Regular backups of VMs and configurations

## Next Steps

1. ✅ Configure storage (ZFS, LVM, Directory)
2. ✅ Set up backups (PBS, NFS, etc.)
3. ✅ Create VMs and containers
4. ✅ Configure cluster (if multi-node)
5. ✅ Set up HA (Keepalived, Corosync)
6. ✅ Monitor with Prometheus/Grafana

## References

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [iPXE Documentation](https://ipxe.org/docs)
- [Keepalived Documentation](https://keepalived.readthedocs.io/)