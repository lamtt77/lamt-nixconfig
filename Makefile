# Connectivity info for Linux Remote Machine
NIXADDR ?= unset
NIXPORT ?= 22
NIXUSER ?= lamt
# The hostname of the nixosConfiguration in the flake
NIXHOST ?= avon
SWAPSIZE ?= 4GB

# Get the path to this Makefile and Flake directory
FLAKE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

SSH_OPTIONS=-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no

# We need to do some OS switching below.
UNAME := $(shell uname)

switch:
ifeq ($(UNAME), Darwin)
	nix build --extra-experimental-features "nix-command flakes" ".#darwinConfigurations.${NIXHOST}.system"
	./result/sw/bin/darwin-rebuild switch --flake "$$(pwd)#${NIXHOST}"
else
	sudo nixos-rebuild switch --flake ".#${NIXHOST}"
endif

# should only run with home-manager standalone config
switch/hm:
	home-manager switch --flake ".#${NIXUSER}_${NIXHOST}"

test:
ifeq ($(UNAME), Darwin)
	nix build ".#darwinConfigurations.${NIXHOST}.system"
	./result/sw/bin/darwin-rebuild check --flake "$$(pwd)#${NIXHOST}"
else
	sudo nixos-rebuild test --flake ".#$(NIXHOST)"
endif

# This will ERASE all data of the REMOTE machine's hard disk! Use at your OWN RISK!!!
#
# Format and setup a brand new Remote Host. One-time/liner installation from github :)
# NixOS Minimum ISO required to be on the CD drive.
#
# Set your own password for the root user before running this for ssh connectivity.
#
# Remove 'ssh-keyscan' if you do not want/have secrets deployment, it's OK to keep as-is
# Forwarding ssh-agent '-A' is only required for my secrets private repo deployment,
# this deployment machine should already have the private-key installed.
remote/bootstrap:
	ssh -A $(SSH_OPTIONS) -p$(NIXPORT) root@$(NIXADDR) " \
		parted /dev/sda -- mklabel gpt; \
		parted /dev/sda -- mkpart primary 512MB -${SWAPSIZE}; \
		parted /dev/sda -- mkpart primary linux-swap -${SWAPSIZE} 100\%; \
		parted /dev/sda -- mkpart ESP fat32 1MB 512MB; \
		parted /dev/sda -- set 3 esp on; \
		sleep 1; \
		mkfs.ext4 -L nixos /dev/sda1; \
		mkswap -L swap /dev/sda2; \
		mkfs.fat -F 32 -n boot /dev/sda3; \
		sleep 1; \
		mount /dev/disk/by-label/nixos /mnt; \
		mkdir -p /mnt/boot; \
		mount /dev/disk/by-label/boot /mnt/boot; \
		nixos-generate-config --root /mnt; \
		mkdir -p /root/.ssh && ssh-keyscan -H tea.lamhub.com > /root/.ssh/known_hosts; \
        nix-shell -p git --command \"nixos-install --no-root-passwd \
		  --flake github:lamtt77/lamt-nixconfig#${NIXHOST}\" && reboot; \
	"

# copy our GPG keyring and SSH keys secrets into the Remote Machine
remote/secrets:
	rsync -av -e 'ssh $(SSH_OPTIONS)' \
		--exclude='.#*' \
		--exclude='S.*' \
		--exclude='*.conf' \
		$(HOME)/.gnupg/ $(NIXUSER)@$(NIXADDR):~/.gnupg
	rsync -av -e 'ssh $(SSH_OPTIONS)' \
		--exclude='environment' \
		$(HOME)/.ssh/ $(NIXUSER)@$(NIXADDR):~/.ssh

# copy the Nix configurations into the Remote Machine. For local setup without github
remote/copy:
	rsync -av -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='.git/' \
		--exclude='result' \
        --delete \
		$(FLAKE_DIR)/ $(NIXUSER)@$(NIXADDR):~/lamt-nixconfig

# This does NOT copy files so you have to run remote/copy before.
remote/switch:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
	sudo nixos-rebuild switch --flake \"./lamt-nixconfig#${NIXHOST}\" \
	"

# This only requires for 1st time secrets deployment or when secrets changed
remote/switch/secrets:
	ssh -A $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
	test -f ./.ssh/known_hosts || (mkdir -p ./.ssh && ssh-keyscan -H tea.lamhub.com > ./.ssh/known_hosts); \
	cd lamt-nixconfig && nix flake update mysecrets; \
	sudo nixos-rebuild switch --flake \".#${NIXHOST}\" \
	"

# Build a WSL installer
.PHONY: wsl
wsl:
	 sudo nix run ".#nixosConfigurations.wsl.config.system.build.tarballBuilder"
