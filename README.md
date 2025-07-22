# LamT NixOS System Configurations
This repository is my NixOS system configuration. I have slowly but fully migrated my existing dotfiles configuration to Nix.
Moving forward my dotfiles repo will only be using for Arch Linux (its wiki is just unbeatable) and FreeBSD/non-Linux.
All Linux, WSL and MacOS stuffs will be managed by Nix, no-going-back :).

## TODO
+ bootstrap: btrfs with [optional] luks encrypted
+ homelab and backup: migrate my custom scripts to nix
+ services: add tailscale/headscale, caddy...
+ github: build/workflows
+ security hardened
+ cloud: migrate my Digital Ocean hosting to nix
+ nixos-generators: iso/proxmox/esxi/docker images
+ impermanence support
+ [optional] secure boot: lanzaboote

## Features
+ One-liner system deployment
+ Unified Config for MacOS (apple silicon & intel), Linux and Windows WSL2
+ Modules/Services can easily enable/disable on demand
+ home-manager can act as a stanalone system or as a nixos module
+ Remote & Cross Platforms Deployment (WIP)
+ Secrets Management

## Quickstart:
+ Boot with 'EFI' Bios, use NixOS Minimal ISO Boot CD from https://nixos.org/download/

### Non-secrets Host Deployment
Format and build a brand new Host. One-liner headless installation!

*WARNING*: This will ERASE all data of the machine's hard disk! Use at your OWN RISK!!!

+ Method 1: Directly from GitHub:
```
$ sudo su
$ passwd <set-temp-root-psw>
$ nix run --extra-experimental-features "nix-command flakes" \
    github:lamtt77/lamt-nixconfig#installer-staging gaming && reboot
After logged in back:
$ cd lamt-nixconfig && nixos-rebuild switch --flake .#gaming
```
OR one-liner for powerful machine: may get out-of-memory (OOM) issue while building
```
$ nix run --extra-experimental-features "nix-command flakes" \
    github:lamtt77/lamt-nixconfig#installer gaming
```
Optional:
* Connect & setup the above in a remote ssh terminal (for copy & paste)
* Clear nix cache if getting old code:
```
$ rm -rf ~/.cache/nix/
```

+ Method 2: Locally:

From the target host:
```
$ sudo su
$ passwd <set-temp-root-psw>
$ ip addr -> note the IP address of this host, example: 192.168.1.100
```
From the main deployment machine:
```
$ git clone https://github.com/lamtt77/lamt-nixconfig && cd lamt-nixconfig
$ NIXADDR=192.168.1.100 NIXHOST=gaming make remote/bootstrap
```

### Secrets Host Deployment:
#### Follow non-secrets host deployment 'Method 2', and set 'SECRETS=yes':
```
$ NIXADDR=192.168.1.101 NIXHOST=avon NIXUSER=nixos SECRETS=yes make remote/bootstrap
```
#### FORCE: *WARNING: Disko Format Pre-confirmed! Can not be undone!!!*
```
$ NIXADDR=192.168.1.101 NIXHOST=avon NIXUSER=nixos SECRETS=yes FORCE=yes make remote/bootstrap
```
Note: set 'SECRETS=no' will still install the host normally, without secret fields

### MacOS / Darwin
* Installer: https://determinate.systems/posts/determinate-nix-installer/
```
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```
After completed, verify with 'nix --version', we are now ready to switch to our config:
+ Standalone home-manager:
```
$ NIXHOST=macair15-m2-hm make switch
$ NIXHOST=macair15-m2-hm make switch/hm
```
+ Combined home-manager as a nixos module: I used this option
```
$ NIXHOST=macair15-m2 make switch
```
+ Note: alternatively, you can use official installer https://nixos.org/download/, I use the installer from determinate systems because it supports unninstall easily.
```
$ sh <(curl -L https://nixos.org/nix/install)
```

### WSL
Enable WSL if not done yet (check status with 'wsl --status')
```
$ wsl --install --no-distribution
```
For more info, refer to: https://learn.microsoft.com/en-us/windows/wsl/basic-commands

#### Method 1: https://github.com/nix-community/NixOS-WSL
* Download the pre-built at https://github.com/nix-community/NixOS-WSL/releases/latest
```
$ wsl --import NixOS $env:USERPROFILE\NixOS\ nixos-wsl.tar.gz
$ wsl -d NixOS
$ git clone https://github.com/lamtt77/lamt-nixconfig && cd lamt-nixconfig
$ sudo nixos-rebuild switch --flake ".#wsl"
```
#### Method 2: build your own reuseable tarball: recommended
```
$ wsl --import NixOS $env:USERPROFILE\NixOS\ nixos-wsl.tar.gz
$ wsl -d NixOS
$ git clone https://github.com/lamtt77/lamt-nixconfig && cd lamt-nixconfig
$ nix build .#nixosConfigurations.wsl.config.system.build.tarballBuilder
```
Copy/rename the generated tarball to C:\Downloads\nixos-wsl-custom.tar.gz, and then
```
$ wsl --import NixOS $env:USERPROFILE\NixOS\ nixos-wsl-custom.tar.gz
$ wsl -d NixOS
```
* The first time wsl may start as root, switch to your username to initialize:
```
$ su lamt
```
* Note: method 2 can be built by 'nix build' from any x86_64-linux host or any wsl distro such as Ubuntu... with nix pre-installed

* Cross-platform tarball build issue:
Currently, cross build the tarball from aarch64-linux is having the below issue:
```
$ make wsl
...
installing the boot loader...
chroot: failed to run command ‘/nix/var/nix/profiles/system/activate’: No such file or directory
chroot: failed to run command ‘/nix/var/nix/profiles/system/sw/bin/bash’: No such file or directory
```

## Credits
+ [Virtual Machine as MacOS terminal workflow] https://github.com/mitchellh/nixos-config
+ [util libs, doomemacs and modules structure] https://github.com/hlissner/dotfiles
+ Lots of others' nix configuration around the internet
