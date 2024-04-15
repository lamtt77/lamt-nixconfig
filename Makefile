# Connectivity info for Linux Remote Machine
NIXADDR ?= unset
NIXPORT ?= 22
NIXUSER ?= lamt

# Get the path to this Makefile and directory
MAKEFILE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# The name of the nixosConfiguration in the flake
NIXNAME ?= macair15-m2

SSH_OPTIONS=-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no

# We need to do some OS switching below.
UNAME := $(shell uname)

switch:
ifeq ($(UNAME), Darwin)
	nix build --extra-experimental-features "nix-command flakes" ".#darwinConfigurations.${NIXNAME}.system"
	./result/sw/bin/darwin-rebuild switch --flake "$$(pwd)#${NIXNAME}"
else
	sudo nixos-rebuild switch --flake ".#${NIXNAME}"
endif

# should only run with home-manager standalone config
switch/hm:
	home-manager switch --flake ".#${NIXUSER}_${NIXNAME}"

test:
ifeq ($(UNAME), Darwin)
	nix build ".#darwinConfigurations.${NIXNAME}.system"
	./result/sw/bin/darwin-rebuild check --flake "$$(pwd)#${NIXNAME}"
else
	sudo nixos-rebuild test --flake ".#$(NIXNAME)"
endif

# bootstrap a brand new Remote Machine. The one should have NixOS ISO on the CD drive
# and just set the password of the root user to "root". This will install
# NixOS. After installing NixOS, you must reboot and set the root password for the next step.
remote/bootstrap0:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) root@$(NIXADDR) " \
		parted /dev/sda -- mklabel gpt; \
		parted /dev/sda -- mkpart primary 512MB -8GB; \
		parted /dev/sda -- mkpart primary linux-swap -8GB 100\%; \
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
		sed --in-place '/system\.stateVersion = .*/a \
nix.package = pkgs.nixUnstable;\n \
nix.extraOptions = \"experimental-features = nix-command flakes\";\n \
environment.systemPackages = with pkgs; [git gnumake vim];\n \
services.openssh.enable = true;\n \
services.openssh.settings.PasswordAuthentication = true;\n \
services.openssh.settings.PermitRootLogin = \"yes\";\n \
users.users.root.initialPassword = \"root\";\n \
		' /mnt/etc/nixos/configuration.nix; \
		nixos-install --no-root-passwd && reboot; \
	"

# after bootstrap0, run this to finalize. After this, do everything else
# in the Remote Machine unless secrets change.
remote/bootstrap:
	NIXUSER=root $(MAKE) remote/copy
	NIXUSER=root $(MAKE) remote/switch
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
	sudo reboot; \
	"
# copy our secrets into the Remote Machine
remote/secrets:
	# GPG keyring
	rsync -av -e 'ssh $(SSH_OPTIONS)' \
		--exclude='.#*' \
		--exclude='S.*' \
		--exclude='*.conf' \
		$(HOME)/.gnupg/ $(NIXUSER)@$(NIXADDR):~/.gnupg
	# SSH keys
	rsync -av -e 'ssh $(SSH_OPTIONS)' \
		--exclude='environment' \
		$(HOME)/.ssh/ $(NIXUSER)@$(NIXADDR):~/.ssh

# copy the Nix configurations into the Remote Machine.
remote/copy:
	rsync -av -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='.git/' \
		--exclude='result' \
		--exclude='flake.lock' \
		--rsync-path="sudo rsync" \
		$(MAKEFILE_DIR)/ $(NIXUSER)@$(NIXADDR):/nix-config

# run the nixos-rebuild switch command. This does NOT copy files so you have to run remote/copy before.
remote/switch:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
	sudo NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --flake \"/nix-config#${NIXNAME}\" \
	"

# Build a WSL installer
.PHONY: wsl
wsl:
	 sudo nix run ".#nixosConfigurations.wsl.config.system.build.tarballBuilder"
