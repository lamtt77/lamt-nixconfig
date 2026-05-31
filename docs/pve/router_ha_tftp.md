Perfect — you’ve built the exact setup most people *wish* they had for proper bare-metal automation 👏

Let’s go through how to make **iPXE + Proxmox auto-install** work cleanly and *highly available* across your 2-node HA pair (VIP `192.168.1.1`, primaries `1.2` and `1.3`).

You want iPXE boot and installer provisioning to **always work**, even if the active router/host flips from 1.2 to 1.3.

---

## 🧭 Your Environment Recap

| Component                     | Role                                                   | Notes                             |
| ----------------------------- | ------------------------------------------------------ | --------------------------------- |
| Node A (pfSense1 / or NixOS1) | `192.168.1.2`                                          | Keepalived primary                |
| Node B (pfSense2 / or NixOS2) | `192.168.1.3`                                          | Keepalived backup                 |
| HA VIP                        | `192.168.1.1`                                          | Floating IP managed by Keepalived |
| Kea DHCP                      | Running on both                                        | Sends boot info to clients        |
| Unbound                       | Local DNS                                              |                                   |
| Nginx                         | Serves iPXE scripts, kernel/initrd, preseed/cloud-init |                                   |
| TFTP (optional)               | May serve initial iPXE EFI chainloader                 |                                   |

Goal:
Clients always contact **192.168.1.1** (the VIP), not a specific node.
When the master flips, everything continues to work transparently.

---

## 🧩 Core Idea

You want all the **boot references (DHCP next-server, iPXE scripts, preseed URLs)** to **point to the VIP (192.168.1.1)**, not the underlying hosts.

That way, **Keepalived handles failover**, and iPXE clients always talk to the currently active node.

---

## ⚙️ Step-by-step Setup

### 1️⃣ Configure Kea DHCP (on both nodes)

Kea on each node must advertise the VIP as the `next-server` and in any boot URLs.

```json
"subnet4": [
  {
    "subnet": "192.168.1.0/24",
    "pools": [ { "pool": "192.168.1.50 - 192.168.1.200" } ],
    "next-server": "192.168.1.1",
    "boot-file-name": "ipxe/ipxe.efi",
    "option-data": [
      { "name": "domain-name-servers", "data": "192.168.1.1" },
      { "name": "routers", "data": "192.168.1.1" }
    ]
  }
]
```

✅ Notes:

* Kea can run in HA mode or active-passive (mirror configs).
* VIP 192.168.1.1 will always float to whichever node is active.
* Clients will always pull iPXE bootstrap from the active node.

---

### 2️⃣ Sync iPXE content via NixOS or rsync

You’ll need both nodes to serve the same content (`/srv/ipxe` or `/srv/boot`).

Option 1 (recommended): Use NixOS configuration for both nodes, identical except Keepalived role:

```nix
services.nginx.virtualHosts."boot.local" = {
  root = "/srv/ipxe";
};
environment.etc."ipxe/default.ipxe".text = ''
#!ipxe
set base-url http://192.168.1.1/boot/debian
kernel ${base-url}/linux auto=true priority=critical \
  url=${base-url}/preseed.cfg interface=auto console=ttyS0,115200n8
initrd ${base-url}/initrd.gz
boot
'';
```

Option 2: Use rsync or Nix store sync to keep `/srv/ipxe` mirrored:

```bash
rsync -avz /srv/ipxe/ root@192.168.1.3:/srv/ipxe/
```

---

### 3️⃣ Nginx config on both nodes

Serve iPXE and installer files:

```nix
services.nginx = {
  enable = true;
  virtualHosts."boot.local" = {
    root = "/srv/ipxe";
    listenAddresses = [ "192.168.1.1" "192.168.1.2" "192.168.1.3" ];
  };
};
```

This allows Nginx to bind to the VIP when Keepalived assigns it.

💡 **Tip:** Add `bind-to-device` if your VIP is on a specific interface:

```bash
ip addr show dev eth0
```

Then in NixOS:

```nix
services.nginx.extraConfig = ''
  listen 80 default_server;
  bind 192.168.1.1;
'';
```

---

### 4️⃣ Keepalived setup (VIP on same interface as DHCP/Nginx)

Typical snippet for NixOS:

```nix
services.keepalived = {
  enable = true;
  vrrpInstances = {
    "PXE_VIP" = {
      interface = "eth0";
      virtualRouterId = 51;
      priority = 200; # 150 on backup
      virtualIps = [ "192.168.1.1/24" ];
      trackScripts = [ "nginx" ];
    };
  };
  vrrpScripts = {
    "nginx" = {
      script = "pidof nginx";
      interval = 5;
    };
  };
};
```

So only the node with active Nginx + Keepalived holds the VIP.

---

### 5️⃣ iPXE chainloader and script

Store your iPXE script at `/srv/ipxe/debian.ipxe`:

```ipxe
#!ipxe
set base-url http://192.168.1.1/boot/debian
kernel ${base-url}/linux auto=true priority=critical interface=auto \
  url=${base-url}/preseed.cfg console=ttyS0,115200n8 console=tty0
initrd ${base-url}/initrd.gz
boot
```

And your DHCP will deliver the boot file `ipxe.efi` (for UEFI) or `undionly.kpxe` (for BIOS).
These files can be placed in `/srv/ipxe` or `/var/lib/tftpboot/ipxe`.

---

### 6️⃣ Optional: Serve preseed or cloud-init via same VIP

Put your files under `/srv/ipxe/boot/debian/`:

```
/srv/ipxe/boot/debian/
├── linux
├── initrd.gz
└── preseed.cfg
```

Then everything is served via:

```
http://192.168.1.1/boot/debian/preseed.cfg
```

If node 1 fails → Keepalived moves VIP to 192.168.1.3 →
DHCP, HTTP, and iPXE boot continue seamlessly 🎯

---

## ✅ End Result

| Component   | Address                            | HA Behavior                     |
| ----------- | ---------------------------------- | ------------------------------- |
| VIP         | `192.168.1.1`                      | Always active on one node       |
| DHCP (Kea)  | `next-server = 192.168.1.1`        | Clients always contact VIP      |
| Nginx       | Serves `/srv/ipxe` on VIP          | Moves with Keepalived           |
| iPXE script | Points to `http://192.168.1.1/...` | Never needs updating            |
| Failover    | Keepalived                         | Transparent to PXE/iPXE clients |

---

## 🧠 TL;DR

✅ Use **VIP (192.168.1.1)** for all URLs and DHCP options.
✅ Run **identical iPXE + nginx setup** on both nodes.
✅ Sync `/srv/ipxe` content between them (via Nix config or rsync).
✅ Keepalived ensures the active node always owns the VIP.
✅ When failover occurs — PXE/iPXE boots continue uninterrupted.

---

Would you like me to write a **ready-to-drop NixOS module** for this (including: Kea config, Nginx serving `/srv/ipxe`, Keepalived VIP binding, and an iPXE auto-install script for Proxmox)?
That would give you a complete HA iPXE provisioning stack in one config file.
