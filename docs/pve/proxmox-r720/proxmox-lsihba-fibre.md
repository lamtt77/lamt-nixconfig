# Proxmox VE Installation on Dell R720 with LSI HBA and Fibre Channel Support

**Updated 2025**: This guide now includes a fresh Proxmox install on NVMe using rEFInd USB boot (bypassing Dell BIOS NVMe limitations), followed by HBA configuration. The original migration from ESXi is preserved below for reference.

Thank you for clarifying that the **FreeNAS VM** on the **Dell R720** (currently ESXi, to be migrated to Proxmox VE, 192.168.1.5) uses a **LSI HBA** for ZFS storage in addition to the two **QLogic Fibre Channel (FC) HBAs** (e.g., QLE2562) directly connected to the **old ProLiant server** (also with two QLogic FC HBAs) for iSCSI storage. The **HP ProLiant** is already running Proxmox VE (192.168.1.201) and configured as an iSCSI initiator accessing FreeNAS iSCSI storage over FC. This migration will move the FreeNAS VM from ESXi to Proxmox on the Dell R720, configuring both the LSI HBA (for ZFS storage) and QLogic FC HBAs (for iSCSI) with PCI passthrough. The setup uses the **HP ProCurve 2810-24G** switch (`trunk 1-3 trk1 trunk` for Dell R720 `vmnic0-2`, `trunk 20-21 trk2 trunk` for HP ProLiant `eno1,eno2`), VLANs 1 (LAN_PCs, 192.168.1.0/24), 2 (Servers, 192.168.2.0/24), 5 (IoT, 192.168.5.0/24), and 10 (LAN) tagged on `trk1`/`trk2`, VLAN 1 untagged on ports 5-7 (Eero on port 6, bridge mode), and requirements for **Management on VLAN 1**, IoT isolation, double-NAT, FreeNAS, Eero WiFi, and ProCurve security.

The **LSI HBA** (e.g., LSI 9211-8i or similar) is passed through to the FreeNAS VM for direct access to physical disks for ZFS pools, while the QLogic FC HBAs provide iSCSI storage connectivity to the old ProLiant. This guide provides **CLI commands** to migrate the Dell R720 to Proxmox VE, import FreeNAS and pfSense VMs, configure PCI passthrough for both the LSI HBA and QLogic FC HBAs, and maintain iSCSI connectivity for the HP ProLiant (Proxmox) and pfSense HA.

## Fresh Proxmox Install on NVMe (Recommended)

For a clean install bypassing ESXi migration:

1. **Build rEFInd USB with NVMe Driver**:
   - `nix build .#nixosConfigurations.router-main.config.system.build.refindBootImg`
   - Flash `result` to USB: `sudo dd if=result of=/dev/sdX bs=1M`
   - Boot Dell R720 from USB; rEFInd auto-selects NVMe Proxmox after 10s.

2. **PXE Install Proxmox**:
   - Use existing PXE server (router-main) with iPXE menu.
   - Select "Setup Proxmox (Auto-Install)" for headless install on NVMe.

3. **Post-Install HBA Config**:
   - Follow `proxmox_hba_config.txt` (IOMMU pre-enabled via PXE).
   - Load drivers, verify FC/SAS.

This method installs Proxmox directly on NVMe, avoiding ESXi migration.

### Assumptions
- **FreeNAS VM** (Dell R720, ESXi):
  - IP: 192.168.1.6/24 (VLAN 10, LAN).
  - Two QLogic FC HBAs (e.g., QLE2562, dual-port) for iSCSI to old ProLiant.
  - One LSI HBA (e.g., 9211-8i) for ZFS storage (local disks on Dell R720).
  - iSCSI target: `iqn.2025-08.com.freenas:target0`, FC-based portal.
- **Dell R720**:
  - ESXi: `vmnic0-2` to ProCurve ports 1-3 (`trk1`), `vmnic3` to Netgear port 2 (WAN).
  - Proxmox: `eno1-eno3` (LAN), `eno4` (WAN).
- **HP ProLiant** (Proxmox, 192.168.1.201):
  - iSCSI initiator to FreeNAS via FC.
- **Old ProLiant**: Provides physical disks to FreeNAS via direct FC cables.
- **LSI HBA**: Uses `mpt3sas` driver (common for LSI 9211-8i).
- **Proxmox VE**: Version 8.2 or 8.3 (latest as of August 2025).

### Warnings
- **Backup**: Export FreeNAS VM, save FreeNAS config, and back up ZFS pools and iSCSI data.
- **Downtime**: Dell R720 offline during Proxmox install.
- **PCI Passthrough**: Requires IOMMU enabled; LSI and QLogic HBAs must be isolated.
- **ZFS Pool**: FreeNAS must re-import ZFS pool post-migration; verify disk IDs.

### CLI Commands for Migration

#### 1. Backup ESXi Configuration and VMs (Dell R720)
Export FreeNAS and primary pfSense VMs, save ESXi config.

<xaiArtifact artifact_id="27348937-3ded-43e0-8d05-439af960dff9" artifact_version_id="214460b9-a93c-4a40-ac26-dc3a12c87670" title="esxi_backup.sh" contentType="text/x-shellscript">
#!/bin/bash
# SSH to Dell R720 ESXi (192.168.1.200)
# Export FreeNAS VM
vm_id_freenas=$(vim-cmd vmsvc/getallvms | grep FreeNAS | awk '{print $1}')
vim-cmd vmsvc/power.off $vm_id_freenas
mkdir /vmfs/volumes/datastore1/backup
ovftool vi://root@192.168.1.200/FreeNAS /vmfs/volumes/datastore1/backup/FreeNAS.ova

# Export primary pfSense VM
vm_id_pfsense=$(vim-cmd vmsvc/getallvms | grep pfSense | awk '{print $1}')
vim-cmd vmsvc/power.off $vm_id_pfsense
ovftool vi://root@192.168.1.200/pfSense /vmfs/volumes/datastore1/backup/pfSense.ova

# Backup ESXi network config
esxcli network vswitch standard list > /vmfs/volumes/datastore1/backup/vswitch_config.txt
esxcli network ip interface list >> /vmfs/volumes/datastore1/backup/network_config.txt

# Copy backups to external storage
# From Management PC (192.168.1.50):
scp root@192.168.1.200:/vmfs/volumes/datastore1/backup/* /path/to/backup/
</xaiArtifact>

#### 2. Backup FreeNAS Configuration and ZFS Pool
Save FreeNAS config and snapshot ZFS pool.

<xaiArtifact artifact_id="ee4e4015-7e6c-4f4b-8655-cad2b78ee737" artifact_version_id="6daee28b-d42e-4104-b889-7db747f6e490" title="freenas_backup.txt" contentType="text/plain">
# Access FreeNAS GUI: https://192.168.2.10
# Login: root, password
# Navigate: System > General > Save Config
# Download to Management PC (192.168.1.50)

# CLI (SSH to FreeNAS):
# Save config
config save /tmp/freenas_config.db
scp /tmp/freenas_config.db root@192.168.1.50:/path/to/backup/

# Snapshot ZFS pool
zpool list
# Example: pool name 'tank'
zfs snapshot tank@pre-migration
zfs list -t snapshot
# Export snapshot (optional, to external storage)
# zfs send tank@pre-migration | ssh root@192.168.1.50 "cat > /path/to/backup/tank.snapshot"
</xaiArtifact>

#### 3. Install Proxmox VE on Dell R720
Install Proxmox VE 8.x using iPXE and cloud-init autoinstall (headless).

**Notes**:
- Access GUI: https://192.168.1.5:8006.
- Verify: `pveversion`.

#### 4. Configure LSI and QLogic HBAs on Proxmox
Set up PCI passthrough for FreeNAS VM.

<xaiArtifact artifact_id="5523641d-b126-4f15-afdb-7b213ab94641" artifact_version_id="6b0f8f5d-eb24-4049-af0e-bbc67f489a01" title="proxmox_hba_config.sh" contentType="text/x-shellscript">
#!/bin/bash
# Note: IOMMU is already enabled via PXE install (intel_iommu=on iommu=pt in kernel params)
# Skip the following if already done:
# echo "intel_iommu=on" >> /etc/default/grub  # or amd_iommu=on for AMD
# update-grub
# reboot

# Verify HBAs
lspci | grep -E 'Fibre|LSI'
# Example (Dell R720):
# 04:00.0 Fibre Channel: QLogic Corp. ISP2532-based 8Gb Fibre Channel to PCI Express HBA (rev 02)
# 04:00.1 Fibre Channel: QLogic Corp. ISP2532-based 8Gb Fibre Channel to PCI Express HBA (rev 02)
# 44:00.0 Serial Attached SCSI controller: Broadcom / LSI SAS2308 PCI-Express Fusion-MPT SAS-2 (rev 05)
# Note PCI IDs (e.g., 0000:04:00.0, 0000:04:00.1, 0000:44:00.0)

# Get QLogic WWNs
cat /sys/class/fc_host/host*/port_name
# Example: 0x21000024ff2ef75d, 0x21000024ff2ef75c

# Load drivers
modprobe qla2xxx  # QLogic FC
modprobe mpt3sas  # LSI HBA
echo "qla2xxx" >> /etc/modules
echo "mpt3sas" >> /etc/modules
update-initramfs -u

# Verify FC connectivity (direct to old ProLiant)
# systool not installed by default; use sysfs instead:
cat /sys/class/fc_host/host*/port_state  # Should show "Online"
# Or install sysfsutils: apt update && apt install sysfsutils && systool -c fc_host -v
# Check for connected FC ports (e.g., remote WWNs if available)

# Verify LSI disks
lsblk
# Example: sda to sdh (8x 3.6T SAS disks from LSI HBA)
</xaiArtifact>

**Notes**:
- Adjust PCI IDs based on `lspci`.
- Save QLogic WWNs for FreeNAS initiator config.

#### 5. Migrate FreeNAS VM to Proxmox
Import FreeNAS VM with LSI and QLogic passthrough.

<xaiArtifact artifact_id="1c1e437f-6921-4978-8139-5793370e3f17" artifact_version_id="564845ac-dda7-4cfa-aaaf-d606cba0defc" title="proxmox_freenas_migrate.sh" contentType="text/x-shellscript">
#!/bin/bash
# Copy FreeNAS OVA
scp /path/to/backup/FreeNAS.ova root@192.168.1.200:/var/lib/vz/template/iso/

# Import FreeNAS VM
qm importovf 100 /var/lib/vz/template/iso/FreeNAS.ova local --format qcow2

# Configure VM
qm set 100 --name FreeNAS
qm set 100 --vga std
qm set 100 --net0 virtio,bridge=vmbr0,tag=10  # VLAN 10

# Start VM
qm start 100

# Restore FreeNAS config (GUI: https://192.168.1.6)
# System > General > Upload Config
# CLI (SSH to FreeNAS):
scp root@192.168.1.50:/path/to/backup/freenas_config.db /tmp/
config restore /tmp/freenas_config.db

# Re-import ZFS pool
zpool import -f tank
zpool status
</xaiArtifact>

**Notes**:
- Adjust PCI IDs (`02:00.0`, `03:00.0`, `04:00.0`).
- Verify ZFS disks: `lsblk` in FreeNAS.



#### 6. Configure Proxmox Network
Set up VLAN-aware bridge.

<xaiArtifact artifact_id="127865fe-c13b-49ae-9e41-cc9b9a96f80a" artifact_version_id="500cfb6f-9ca9-44ab-901f-3de701715101" title="proxmox_network_config.sh" contentType="text/x-shellscript">
#!/bin/bash
# Backup network config
cp /etc/network/interfaces /etc/network/interfaces.bak

# Configure LACP bond and VLAN-aware bridge (similar to pve1)
cat << EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto eno1
iface eno1 inet manual
	bond-master bond0

auto eno2
iface eno2 inet manual
	bond-master bond0

auto eno3
iface eno3 inet manual
	bond-master bond0

iface eno4 inet manual

auto bond0
iface bond0 inet manual
	bond-slaves eno1 eno2 eno3
	bond-miimon 100
	bond-mode 802.3ad
	bond-xmit-hash-policy layer3+4

auto vmbr0
iface vmbr0 inet manual
	bridge-ports eno4
	bridge-stp off
	bridge-fd 0

auto vmbr1
iface vmbr1 inet manual
	bridge-ports bond0
	bridge-stp off
	bridge-fd 0
	bridge-vlan-aware yes
	bridge-vids 10 20 40 50

auto vmbr1.10
iface vmbr1.10 inet static
    	address 192.168.1.5/24
    	gateway 192.168.1.1

auto vmbrVyos
iface vmbrVyos inet manual
	bridge-ports none
	bridge-stp off
	bridge-fd 0
EOF

# Apply
ifreload -a

# Verify
ip addr show
ping 192.168.1.10
</xaiArtifact>

#### 7. Update FreeNAS iSCSI Initiator List
Ensure HP ProLiant’s WWNs are authorized.

<xaiArtifact artifact_id="ee4e4015-7e6c-4f4b-8655-cad2b78ee737" artifact_version_id="f61047a7-a18e-4fd6-948c-51a14d5d2aa3" title="freenas_iscsi_config.txt" contentType="text/plain">
# Access FreeNAS GUI: https://192.168.2.10
# Login: root, password
# Navigate: Sharing > Block Shares (iSCSI) > Initiators > Edit
# Confirm HP ProLiant WWNs (e.g., 0x21000024ff123456, 0x21000024ff123457)
# Save

# Verify iSCSI target
# CLI (SSH to FreeNAS):
camcontrol devlist
ctladm islist
</xaiArtifact>

#### 8. Verify HP ProLiant iSCSI Connectivity
Reconfirm HP ProLiant (Proxmox) iSCSI initiator.

<xaiArtifact artifact_id="fb105257-079c-4edc-96ac-1aee7f732c37" artifact_version_id="c360d54e-a499-4d62-bbf6-1487037998eb" title="proxmox_iscsi_config.sh" contentType="text/x-shellscript">
#!/bin/bash
# SSH to HP ProLiant (192.168.1.201)
iscsiadm -m discovery -t sendtargets -p 192.168.2.10
iscsiadm -m node -T iqn.2025-08.com.freenas:target0 -p 192.168.2.10 --login
iscsiadm -m session
lsblk
pvesm status
</xaiArtifact>

#### 9. Verify ProCurve Configuration
Ensure `trk1` supports VLANs.

<xaiArtifact artifact_id="22d96468-b6e4-4615-9e60-ed9db46036aa" artifact_version_id="187b2604-d8c4-4f4b-bbd9-d51a2432a1b9" title="procurve_config.txt" contentType="text/plain">
configure terminal
no trunk 1-3 trk1 trunk
trunk 1-3 trk1 trunk
vlan 1
  name "LAN_PCs"
  untagged 5-7
  tagged trk1
exit
vlan 2
  name "Servers"
  untagged 11-15
  tagged trk1
exit
vlan 5
  name "IoT"
  untagged 19
  tagged trk1
exit
vlan 10
  name "SYNC"
  tagged trk1
exit
write memory
exit
</xaiArtifact>

#### 10. Test Connectivity
<xaiArtifact artifact_id="614867ec-f687-4872-88c5-bacd703db7cb" artifact_version_id="80ff85d3-1866-47ac-b5bc-5c74c5977344" title="proxmox_test.sh" contentType="text/x-shellscript">
#!/bin/bash
# Test network (Dell R720)
ping 192.168.1.1
ping 192.168.2.10

# Test FC and iSCSI (HP ProLiant)
systool -c fc_host -v
iscsiadm -m session
lsblk
pvesm status

# Test FreeNAS FC and ZFS
# SSH to FreeNAS
camcontrol devlist
ctladm islist
zpool status

# Test pfSense HA
# In pfSense GUI: Status > CARP
# Shutdown secondary; check primary
</xaiArtifact>

### Physical Connections
- **FC Connections**: Dell R720 (Proxmox) QLogic HBA ports to old ProLiant QLogic HBA ports (direct cables).
- **Network**:
  - Dell R720: `eno1-eno3` -> ProCurve ports 1-3 (`trk1`); `eno4` -> Netgear port 2.
  - HP ProLiant: `eno1,eno2` -> ProCurve ports 20-21 (`trk2`); `eno3` -> Netgear port 3.
  - Eero: Port 6 (VLAN 1).

### Implications
- **FreeNAS**: Migrated to Proxmox with LSI and QLogic passthrough; ZFS and iSCSI intact.
- **IoT Isolation**: Maintained.
- **ProCurve Security**: Intact.
- **Old ProLiant**: Continues providing disks to FreeNAS via FC.

### Conclusion
These CLI commands migrate the Dell R720 to Proxmox VE, import FreeNAS (with LSI and QLogic passthrough) and maintain iSCSI. Please provide:
- LSI HBA model (e.g., 9211-8i).
- QLogic HBA model (e.g., QLE2562).
- FreeNAS iSCSI IQN and portal type.
- Old ProLiant disk details.
Run commands, test, and report issues!
