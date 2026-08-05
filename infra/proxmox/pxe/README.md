# Proxmox PXE inputs

This directory owns directly authored installer inputs and transport templates
for Proxmox installation. Per-node answer files live under
`targets/<node>/answer.toml`; host-local files installed after setup live under
`../state/pve/<node>/`.

`pkgs/pve-pxe-assets` is intentionally only a packaging implementation: it
consumes these files, constructs the reviewed immutable PXE artifact, and does
not own site inventory or construct node configuration from Nix data.
