Here is the summary document focusing on the creation of your safe storage and the warnings regarding the unsafe/inefficient methods we discussed.

You can save this as `storage_risks_and_setup.md`.

---

# Storage Architecture: Setup & Risk Analysis

**Date:** 2025-11-23
**Context:** Proxmox Cluster (PVE1/PVE2) backed by TrueNAS Core/Scale.

---

## 1. The "Golden Standard" Setup: Shared LVM-Thick

This is the configuration currently running on your cluster. It provides the best balance of **Safety** (Cluster-aware) and **Speed** (Native Fibre Channel).

### How it was created

1.  **TrueNAS:** Created a Zvol (Block Device) -> Shared via iSCSI Target.
2.  **PVE1 (Fibre Channel):**
    - Detected Native FC device via Multipath (`/dev/mapper/mpathX`).
    - **Created Physical Volume:** `pvcreate /dev/mapper/mpathX`
    - **Created Volume Group:** `vgcreate fcvg-z2-shared /dev/mapper/mpathX`
3.  **PVE2 (iSCSI):**
    - Logged in via iSCSI (Internal Bridge).
    - Scanned VG: `vgscan` -> `vgchange -ay fcvg-z2-shared`.
4.  **Proxmox GUI:**
    - Added **LVM** Storage.
    - Selected Volume Group: `fcvg-z2-shared`.
    - **Crucial Step:** Checked **[x] Shared**.

### The "QCOW2 Hack" (For Snapshots)

To enable snapshots on this Thick storage, we do **not** use RAW format.

- **Method:** We format the LVM block device with QCOW2 headers.
- **Command:** `qemu-img convert -O qcow2 source.raw target.qcow2`
- **Result:** Proxmox sees a block device, but QEMU sees a QCOW2 file, enabling internal snapshots.

---

## 2. WARNING: The LVM-Thin Trap (Data Loss Risk)

**Verdict:** **DO NOT USE** on Shared Storage without strict filters.

### The Risk: "Split Brain" Corruption

Standard LVM-Thin is **not cluster-aware**. It assumes it is the only OS managing the metadata (allocation map) of the pool.

- **Scenario:** You have LVM-Thin on a shared iSCSI/FC disk.
- **The Crash:**
  1.  **PVE1** allocates a new block for VM 100. It updates the metadata in its RAM.
  2.  **PVE2** boots up. It scans the disk, sees the _old_ metadata, and decides to "fix" or "activate" the pool.
  3.  **PVE2** writes to the metadata track.
  4.  **Result:** PVE1's changes are overwritten. The filesystem index becomes garbage. **Total Data Loss.**

### When is it safe?

Only if you strictly prevent the second node from **ever** seeing the disk using **LVM Filters** in `/etc/lvm/lvm.conf` (The "Blindfold" method).

- _If you forget the filter and reboot the second node..._ **BOOM.**

---

## 3. WARNING: ZFS-over-ZFS (Inefficiency)

**Verdict:** **Performance Killer.** Avoid unless strictly necessary for replication.

### The Architecture

This happens if you take a TrueNAS Zvol (Layer 1), export it via iSCSI, mount it on Proxmox, and format it as ZFS (Layer 2).

### The "Write Amplification" Penalty

Both layers use **Copy-on-Write (CoW)**.

1.  **VM Writes 4k:**
2.  **Proxmox ZFS:** Reads 128k block -> Modifies 4k -> Writes new 128k block to iSCSI.
3.  **TrueNAS ZFS:** Receives 128k write -> Reads its own record -> Writes new physical block to disk.
4.  **Result:** A tiny 4k write generated massive I/O overhead. Throughput often drops to **50-60%** of potential speed.

### The "ARC Fight" (RAM Waste)

- **TrueNAS:** Wants 50% of RAM to cache the data.
- **Proxmox:** Wants 50% of RAM to cache the _exact same data_.
- **Result:** You are double-caching, wasting RAM that could be used for VMs.

---

## 4. Summary Decision Matrix

| Feature           | **LVM-Thick (Current)**             | **LVM-Thin**                        | **ZFS-over-ZFS**                        |
| :---------------- | :---------------------------------- | :---------------------------------- | :-------------------------------------- |
| **Shared Safety** | ✅ **Safe** (Locks handled by LVM)  | ❌ **Dangerous** (Split Brain risk) | ❌ **Dangerous** (ZFS is not clustered) |
| **Performance**   | 🚀 **High** (Direct Block Access)   | 🚀 **High**                         | ⚠️ **Low** (CoW Overhead)               |
| **Snapshots**     | ⚠️ **Via Hack Only** (QCOW2 on LVM) | ✅ **Native**                       | ✅ **Native** (Local only)              |
| **Space Usage**   | ⚠️ **Full Allocation** (Thick)      | ✅ **Thin**                         | ✅ **Thin**                             |
| **Recommended?**  | **YES**                             | **NO** (Unless single node)         | **NO**                                  |
