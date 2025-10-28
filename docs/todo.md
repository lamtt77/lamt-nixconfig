### 1. Review Secrets Implementation:

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

legacy stuffs to have a look:

```nix
# LamT secrets stuff: legacy, changed to manage by make file
# OR sudo nixos-rebuild switch --override-input mysecrets "" --flake '.#gaming'
mysecrets.url = "git+ssh://git@tea.lamhub.com/lamtt77/lamt-secrets.git";
mysecrets.url = "path:./secrets";
mysecrets.flake = false;
```
