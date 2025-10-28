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