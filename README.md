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

## Quickstart:
+ Boot with 'EFI' Bios, use NixOS Minimal ISO Boot CD
+ Must ensure hardware-configuration fileSystems correct, best is to use /by-label/

### Non-secrets Host Deployment
+ Method 1: Directly from github: TODO will be ready after migrated to 'disko'
```
$ sudo su
$ passwd <set-temporary-root-psw>
$ nix-shell -p git --command "nixos-install --no-root-passwd --flake github:lamtt77/lamt-nixconfig#gaming"
$ reboot
```
+ Method 2: Locally: from the target host:
```
$ sudo su
$ passwd <set-temporary-root-psw>
$ ip addr -> note the IP address of this host, example: 192.168.1.100
```
From the main deployment machine:
```
$ git clone https://github.com/lamtt77/lamt-nixconfig && cd lamt-nixconfig
$ NIXADDR=192.168.1.100 NIXHOST=gaming NIXUSER=vivi make remote/bootstrap
```

### Secrets Host Deployment: TODO improve to a more automatic way
+ Follow non-secrets host deployment above, and have some extra-steps:
From the main deployment machine: go to 'lamt-secrets' repo:
```
$ ssh-keyscan -H 192.168.1.101 -> note the ssh-ed25519 pubkey
Change 'lamt-secrets/agenix/secrets.nix' to add that ssh-ed25519 pubkey, then rekey:
$ agenix -r
Commit & push 'lamt-secrets'
```
Go back to 'lamt-nixconfig' repo:
```
$ NIXADDR=192.168.1.101 NIXHOST=avon NIXUSER=nixos make remote/copy
$ NIXADDR=192.168.1.101 NIXHOST=avon NIXUSER=nixos make remote/switch/secrets
Note: from 2nd switch onwards, if secrets not changed, use:
$ NIXADDR=192.168.1.101 NIXHOST=avon NIXUSER=nixos make remote/switch
```

### WSL
* If starting as root, run the following to init:
```
$ su lamt
```

## Credits
+ [Virtual Machine as MacOS terminal workflow] https://github.com/mitchellh/nixos-config
+ [handsome libs, doomemacs and modules/services structure] https://github.com/hlissner/dotfiles
+ Lots of others' nix configuration around the internet
