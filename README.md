# LamT NixOS System Configurations
This repository is my NixOS system configuration. I have slowly but fully migrated my existing dotfiles configuration to Nix.
Moving forward my dotfiles repo will only be using for Arch Linux (its wiki is just unbeatable) and FreeBSD/non-Linux.
All Linux, WSL and MacOS stuffs will be managed by Nix, no-going-back :).

## TODO
+ Migrate to my own vim/nvim configuration stored in dotfiles, not-in-hurry as the existing nvim config is working fine
+ bootstrap: migrate Makefile/scripts to 'disko' and 'btrfs' with [optional] luks encrypted
+ homelab and backup: migrate my custom scripts to nix
+ services: add tailscale/headscale, caddy...
+ github: build/workflows
+ security hardened
+ cloud: migrate my Digital Ocean hosting to nix
+ nixos-generators: iso/proxmox/esxi/docker images
+ impermanence support
+ [optional] secure boot: lanzaboote

## Features
+ One (or two) command(s) Full System Deployment
+ Unified Config for MacOS (apple silicon & intel), Linux and Windows WSL2
+ Modules/Services can easily enable/disable on demand
+ home-manager can act as a stanalone system or as a nixos module
+ Remote & Cross Platforms Deployment (TODO)
+ Secrets Management

## Quickstart: TODO
+ Comment out 'mysecrets' input in 'flake.nix' for non-secrets deployment
+ Boot with 'EFI' bios
+ Must ensure hardware-configuration fileSystems correct, best is to use /by-label/

### WSL
* If starting as root, run the following to init:
```
$ su lamt
```

## Credits
+ [Virtual Machine as MacOS terminal workflow] https://github.com/mitchellh/nixos-config
+ [handsome libs, doomemacs and modules/services structure] https://github.com/hlissner/dotfiles
+ Lots of others' nix configuration around the internet
