Here is the summary of your complete, optimized configuration. You can save this as `cluster_config.md`.

````markdown
# Proxmox Cluster Configuration Documentation

**Date:** 2025-11-23
**Architecture:** 2-Node Cluster with Virtualized TrueNAS (Shared Storage)

---

## 1. Architecture Overview

| Node        | Role                     | Connection to Storage    | Protocol           | Speed    |
| :---------- | :----------------------- | :----------------------- | :----------------- | :------- |
| **PVE1**    | Compute Node             | QLogic Fibre Channel HBA | **Native FC**      | 8 Gbps   |
| **PVE2**    | Host Node (Runs TrueNAS) | Internal Linux Bridge    | **iSCSI** (VirtIO) | ~20 Gbps |
| **TrueNAS** | Storage Appliance        | VM inside PVE2           | --                 | --       |

---

## 2. TrueNAS Configuration (The Backend)

### Block Storage (For Running VMs)

- **Type:** Zvol
- **Name:** (e.g., `disk-for-proxmox`)
- **Size:** 4TB
- **Compression:** LZ4 (Crucial for space savings)
- **Sync:** **Disabled** (Crucial for performance/IOPS)
- **Sharing:**
  - **Target:** `iqn.2005-10.org.freenas.ctl:fc-z2-iscsi`
  - **Access:** Shared via iSCSI (for PVE2) and Fibre Channel (for PVE1).

### File Storage (For ISOs/Backups)

- **Type:** Dataset
- **Sharing:** NFS Share
- **Network:** Exposed to both LAN (1G) and Internal Bridge (10G+).

---

## 3. PVE1 Configuration (Fibre Channel Node)

### Multipath

- **Status:** Enabled
- **Config:** Default multipath handles the QLogic paths.
- **Device:** `/dev/mapper/mpathd` (or similar) maps to the TrueNAS LUN.

### LVM (Shared Thick)

- **VG Name:** `fcvg-z2-shared`
- **Config (`/etc/lvm/lvm.conf`):**
  ```ini
  devices {
      issue_discards = 1   # Enables TRIM to pass through to TrueNAS
  }
  ```
  _Action:_ `update-initramfs -u` run after changes.

### Storage Definition (`/etc/pve/storage.cfg`)

- **ID:** `arthurz2-lvm`
- **Type:** LVM
- **Shared:** **YES**
- **Content:** Disk Image, Container

---

## 4. PVE2 Configuration (Host Node)

### LVM Config

- **Config (`/etc/lvm/lvm.conf`):**
  ```ini
  devices {
      issue_discards = 1
  }
  ```

### iSCSI "Re-connector" Logic

Since TrueNAS is a VM, PVE2 cannot connect at boot. It connects via script.

**1. iSCSI Setting (Prevent boot hang):**

```bash
iscsiadm -m node -T iqn.2005-10.org.freenas.ctl:fc-z2-iscsi -o update -n node.startup -v manual
```
````

**2. Connection Script (`/root/freenas_connect.sh`):**

```bash
#!/bin/bash
TARGET_IP="10.99.99.2"  # Internal Bridge IP for Speed
TARGET_IQN="iqn.2005-10.org.freenas.ctl:fc-z2-iscsi"
VG_NAME="fcvg-z2-shared"

# Wait for Network
until ping -c1 -W1 $TARGET_IP >/dev/null 2>&1; do sleep 5; done
sleep 15

# Login
if ! iscsiadm -m session | grep -q "$TARGET_IQN"; then
    iscsiadm -m node -T "$TARGET_IQN" --login
fi

# Refresh LVM
vgscan --mknodes
pvscan --cache
vgchange -ay "$VG_NAME"
pvesm status
```

**3. Crontab (`crontab -e`):**

```bash
@reboot /root/freenas_connect.sh >> /var/log/freenas_connect.log 2>&1
```

---

## 5\. VM Disk Strategy (The "Inception" Hack)

To enable **Snapshots** on LVM-Thick storage, we format the block devices as QCOW2.

### Creating New Disks

1.  Create disk normally (Proxmox defaults to RAW).
2.  **Convert to QCOW2:**
    ```bash
    # Create empty volume
    lvcreate -L 100G -n vm-100-disk-1.qcow2 fcvg-z2-shared
    # Convert/Copy
    qemu-img convert -p -f raw -O qcow2 /dev/fcvg-z2-shared/OLD-RAW /dev/fcvg-z2-shared/vm-100-disk-1.qcow2
    ```
3.  Update VM Config (`/etc/pve/qemu-server/100.conf`) to point to the new `.qcow2` volume.

### Operational Rules

- **Snapshots:** Safe to take/restore at any time on the running node.
- **Migration:** **MUST DELETE SNAPSHOTS** before Live Migrating between nodes.
  - _Reason:_ Migration will fail with "Device busy" if snapshots exist due to locking.

---

## 6\. Maintenance Commands

### Resizing Storage (After expanding TrueNAS Zvol)

Run on PVE1:

```bash
multipathd resize map mpathd   # Resize OS Layer
pvresize /dev/mapper/mpathd    # Resize LVM Layer
vgs                            # Verify free space
```

### Manual Fixes (If Migration Fails)

If migration fails with "No such file" (Inactive) or "Device Busy" (Stuck Active):

**On Destination Node:**

- **To Activate (Fix "No such file"):** `lvchange -ay fcvg-z2-shared/vm-ID-disk-1.qcow2`
- **To Deactivate (Fix "Device busy"):** `lvchange -an fcvg-z2-shared/vm-ID-disk-1.qcow2`
- **To Refresh:** `vgscan --mknodes`

<!-- end list -->

```

```
