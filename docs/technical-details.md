# Technical Details: ACME and SSL Configuration

## Global ACME (Let's Encrypt) Support

The `modules/os/base/_server.nix` configuration enables global ACME support in NixOS for automatic SSL certificate management:

- `acceptTerms = true`: Automatically accepts Let's Encrypt's terms of service for certificate issuance.
- `defaults.email = "info@lamhub.com"`: Sets the default contact email for ACME account registration, used for notifications and account management.

This global configuration allows NixOS to handle certificate storage in `/var/lib/acme` and manage renewal automatically.

## Caddy Integration for blog.lamhub.com

The blog site at `blog.lamhub.com` leverages this global ACME setup through Caddy (configured in `hosts/medo/default.nix`):

- Caddy serves the site without explicit `tls internal`, which triggers ACME certificate requests automatically.
- NixOS's ACME integration handles certificate storage and renewal.
- Caddy accesses system-managed certificates for HTTPS, using the global email and terms acceptance.
- No domain-specific ACME config is needed in Caddy; it leverages the system's defaults.

## Migration Notes

If the domain was previously using internal TLS, switching to ACME required removing `tls internal` from Caddy's config. This ensures automatic certificate issuance/renewal for `blog.lamhub.com` over HTTPS, provided DNS points to the server and ports 80/443 are accessible.

## Ubuntu Kernel Upgrade for Kexec Compatibility

Ubuntu 18.04's 4.15 kernel supports kexec_load but not kexec_file_load (added in 4.17+). NixOS installer prefers the newer syscall, causing silent failure.

To upgrade:

1. Add HWE repositories:
   deb http://archive.ubuntu.com/ubuntu bionic main universe
   deb http://archive.ubuntu.com/ubuntu bionic-updates main universe
   deb http://archive.ubuntu.com/ubuntu bionic-backports main universe

2. Update and install HWE kernel:
   sudo apt update
   sudo apt install --install-recommends linux-generic-hwe-18.04
   sudo reboot

3. Verify: uname -r should show 5.4.0-###-generic.

Additional checks:

- `cat /proc/sys/kernel/kexec_load_disabled` should return 0
- `sudo kexec --version` should show kexec-tools version

## Router High Availability (HA) with Keepalived

The router setup uses Keepalived for VRRP-based failover between two NixOS routers (router-main and router-backup).

### Configuration

- **Virtual IPs**: 192.168.1.1 (LAN, added to eth1.10)
- **Priorities**: router-main (150, MASTER), router-backup (100, BACKUP)
- **VRRP Instance**: LAN on eth1.40 (sync VLAN), unicast peers on sync VLAN
- **Sync VLAN**: eth1.40 (192.168.4.0/24) for HA communication
- **Services**: DNS (Unbound), DHCP (Kea), NAT, Firewall
- **Gratuitous ARP**: garp_master_delay 5, garp_master_repeat 3, garp_master_refresh 10 for faster client convergence after failover

### Unicast VRRP Setup

VRRP runs on the sync VLAN (eth1.40) with unicast peers to avoid conflicts with eero on WAN. VIP is added to LAN interface (eth1.10).

- **router-main** (192.168.1.2 LAN, 192.168.4.2 sync):

  - Unicast peers: [192.168.4.3]

- **router-backup** (192.168.1.3 LAN, 192.168.4.3 sync):
  - Unicast peers: [192.168.4.2]

### Failover Testing

1. Stop Keepalived on MASTER: `sudo systemctl stop keepalived`
2. Verify BACKUP assumes VIPs and services continue
3. Restart Keepalived on MASTER: `sudo systemctl start keepalived`
4. Confirm MASTER reclaims VIPs

### Monitoring

Check Keepalived status: `sudo systemctl status keepalived`
View logs: `journalctl -u keepalived -f`
Check VRRP packets: `sudo tcpdump -i eth1.40 vrrp`
