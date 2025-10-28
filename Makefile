# Configuration Variables
.DEFAULT_GOAL := switch
SHELL := /usr/bin/env bash -e
NIXCFG ?= lamt-nixconfig
TEA_URL ?= tea.lamhub.com

GITHUB_TOKEN := $(shell command -v gh >/dev/null && gh auth token)
TOKEN_OPT := $(if $(GITHUB_TOKEN),--option access-tokens 'github.com=$(GITHUB_TOKEN)')
FORCE_FLAG := $(if $(filter yes,$(FORCE)),--force)

# Connectivity for Remote Machines
NIXADDR ?= unset
NIXPORT ?= 22
SSHUSER ?= root
NIXUSER ?= $(shell whoami)
NIXHOST ?= $(shell hostname -s)
REMOTE_OS ?= Linux

SSH_COPY_ID ?= yes
SECRETS ?= no
# nh Output Monitoring
NH ?= yes
# Enhanced installer options (inspired by nixos-anywhere)
BUILD_ON ?= auto
KEXEC_BOOT ?= auto
LOW_MEM ?= no
SUBS_ON_DEST ?= yes

# Repository Handling
GH_REPO ?= github:lamtt77/$(NIXCFG)
TEA_REPO ?= git+ssh://git@$(TEA_URL)/lamtt77/$(NIXCFG)
LOCAL_REPO ?= .
ifeq ($(NIXREPO), tea)
	MYREPO = $(TEA_REPO)
else ifeq ($(NIXREPO), local)
	MYREPO = $(LOCAL_REPO)
else
	MYREPO = $(GH_REPO)
endif

# Flake Directory and Options
FLAKE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
FLAKE_FEATURES ?= --extra-experimental-features nix-command --extra-experimental-features flakes
FLAKE_EXCLUDE ?= --exclude=.git --exclude=secrets --exclude=result --exclude=.DS_Store --exclude=flake.lock
SSH_OPTIONS = -A -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3

LOG_LEVEL ?= info
# OS Detection
UNAME := $(shell uname)

# Proxmox VM Configuration
PROXMOX_HOST ?= pve1.lamhub.com
VMID ?= 111
VM_MEMORY ?= 4096
VM_CORES ?= 4
VM_DISK_SIZE ?= 50
VM_BRIDGE ?= vmbr1,tag=10
VM_STORAGE ?= arthurz2-zfs
VM_NAME ?= $(NIXHOST)
VM_SUBNET ?= 192.168.1.0/24
NIXOS_ISO ?= arthurz2-dir:iso/nixos-minimal-25.05pre-git-x86_64-linux.iso

# Ubuntu cloud deployment
UBUNTU_CLOUD_IMG_PATH ?= /mnt/arthurz2-iscsi/images/ubuntu-22.04-server-cloudimg-amd64.img

# Generic cloud-init VM deployment
CLOUDINIT_IMG_PATH ?= $(UBUNTU_CLOUD_IMG_PATH)
CLOUDINIT_IMG_SYSTEM ?= ubuntu
CLOUDINIT_USER ?= ubuntu

# DigitalOcean Configuration
DO_REGION ?= sgp1
DO_SIZE ?= s-1vcpu-1gb
DO_IMAGE ?= ubuntu-22-04-x64
DO_SSH_KEY ?= $(shell doctl compute ssh-key list --format ID,FingerPrint --no-header | head -1 | awk '{print $$1}')

# Core Build/Switch/Test
# Command Templates
SUBSTITUTE_OPTS := $(if $(filter yes,$(SUBS_ON_DEST)),--substitute-on-destination)

# Remote Builder Configuration
BUILDER_HOST ?=
BUILDER_NIXCFG_PATH ?= ./$(NIXCFG)

FLAKE_ATTR_CMD = $(if $(filter Darwin,$(REMOTE_OS)), \
	.#darwinConfigurations.$(NIXHOST).system, \
	.#nixosConfigurations.$(NIXHOST).config.system.build.toplevel)
OS_BUILD_CMD = $(if $(filter Darwin,$(REMOTE_OS)), \
	nix build $(FLAKE_FEATURES) .#darwinConfigurations.$(NIXHOST).system, \
	nix build $(FLAKE_FEATURES) .#nixosConfigurations.$(NIXHOST).config.system.build.toplevel)

HM_SWITCH_CMD = $(if $(filter yes,$(NH)), \
	nh home switch . -c $(NIXUSER)_$(NIXHOST), \
	nix run -- home-manager switch --flake ".#$(NIXUSER)_$(NIXHOST)")

NIXOS_SWITCH = $(if $(filter yes,$(NH)), \
	nh os switch . --hostname $(NIXHOST), \
	sudo nixos-rebuild switch --flake ".#$(NIXHOST)")
DARWIN_SWITCH = $(if $(filter yes,$(NH)), \
	nh darwin switch . --hostname $(NIXHOST), \
	sudo -H nix run -- nix-darwin switch --flake ".#$(NIXHOST)")
OS_SWITCH_CMD = $(if $(filter Darwin,$(UNAME)), $(DARWIN_SWITCH), $(NIXOS_SWITCH))

OS_TEST_CMD = $(if $(filter Darwin,$(UNAME)), \
	sudo -H nix run -- nix-darwin check --flake .#$(NIXHOST), \
	sudo nixos-rebuild test --flake .#$(NIXHOST))

REMOTE_BUILD_CMD = $(if $(filter Darwin,$(REMOTE_OS)), \
	nix build .#darwinConfigurations.$(NIXHOST).system, \
	nix build .#nixosConfigurations.$(NIXHOST).config.system.build.toplevel)

REMOTE_SWITCH_CMD = $(if $(filter Darwin,$(REMOTE_OS)),$(DARWIN_SWITCH),$(NIXOS_SWITCH))

# Colored output functions
define INFO
printf '\033[1;34m[INFO]\033[0m %s\n' "$(1)"
endef

define WARN
printf '\033[1;33m[WARN]\033[0m %s\n' "$(1)"
endef

define ERROR
printf '\033[1;31m[ERROR]\033[0m %s\n' "$(1)"
endef

# Secrets Handling
copy/secrets:
	mkdir -p ./secrets/sops
	rsync -avh --delete ../lamt-secrets/sops/$(NIXHOST).yaml secrets/sops/

define SECRETS_PRE
test -d .git && test -d secrets && echo PRE-secrets && git add --intent-to-add secrets/ || true
endef

define SECRETS_POST
test -d .git && test -d secrets && echo POST-secrets && git rm --cached -r secrets/ || true
endef

# SSH and Cleanup Defines
define SSH_RUN
ssh $(SSH_OPTIONS) -p$(NIXPORT) $(1)@$(NIXADDR) "$(2)"
endef

define CLEANUP_CMD
test -d $(1) && rm -rf $(1); test -d result && rm result; nix-collect-garbage -d
endef

HOST_FLAKE_LOCK = hosts/$(NIXHOST)/flake.lock
define COPY_FLAKE_LOCK
if [ -f $(HOST_FLAKE_LOCK) ]; then scp $(SSH_OPTIONS) -P $(NIXPORT) $(HOST_FLAKE_LOCK) $(NIXUSER)@$(NIXADDR):./$(NIXCFG)/flake.lock; fi
endef

define BACKUP_FLAKE_LOCK_LOCAL
	$(call INFO,Backing up local flake.lock to $(HOST_FLAKE_LOCK)...); \
	rsync -c ./flake.lock $(HOST_FLAKE_LOCK)
endef

define BACKUP_FLAKE_LOCK
	$(call INFO,Backing up flake.lock from $(1) to $(HOST_FLAKE_LOCK)...); \
	if rsync -c -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' $(NIXUSER)@$(NIXADDR):./$(NIXCFG)/flake.lock $(HOST_FLAKE_LOCK); then \
		true; \
	else \
		$(call WARN,Failed to back up flake.lock from $(1)); \
	fi
endef

pre-secrets:
	$(SECRETS_PRE)

post-secrets:
	$(SECRETS_POST)

build0:
	$(OS_BUILD_CMD)

switch0:
	$(OS_SWITCH_CMD) && $(call BACKUP_FLAKE_LOCK_LOCAL)

switch/hm:
	$(HM_SWITCH_CMD)

test0:
	$(OS_TEST_CMD)

# Main Targets (with secrets isolation)
build: pre-secrets build0 post-secrets
switch: pre-secrets switch0 post-secrets
test: pre-secrets test0 post-secrets

# Remote Bootstrap (DANGER: Erases remote disk!)
remote/bootstrap:
	@START_TIME=$$(date +%s); \
	$(call INFO,Starting remote bootstrap process...); \
	export GITHUB_TOKEN="$(GITHUB_TOKEN)"; \
	nix run $(FLAKE_FEATURES) $(TOKEN_OPT) $(MYREPO)\#installer-staging -- \
		--flake ".#$(NIXHOST)" \
		--target-host "$(SSHUSER)@$(NIXADDR)" \
		--build-on "$(BUILD_ON)" \
		--kexec "$(KEXEC_BOOT)" \
		--low-mem "$(LOW_MEM)" \
		--substitute-on-destination "$(SUBS_ON_DEST)" \
		--log-level "$(LOG_LEVEL)" \
		--exclude "$(FLAKE_EXCLUDE)" \
		--mode "bootstrap" \
		--nix-user "$(NIXUSER)" \
		--nix-cfg "$(NIXCFG)" \
		$(FORCE_FLAG); \
	END_TIME=$$(date +%s); \
	DURATION=$$((END_TIME - START_TIME)); \
	MINUTES=$$((DURATION / 60)); \
	SECONDS=$$((DURATION % 60)); \
	$(call BACKUP_FLAKE_LOCK,newly bootstrapped host) && \
	$(call INFO,Remote bootstrap completed successfully in $$MINUTES minutes and $$SECONDS seconds at IP: $$NIXADDR)

# Remote Operations
remote/build:
	$(call SSH_RUN,$(NIXUSER),cd $(NIXCFG); $(SECRETS_PRE); $(REMOTE_BUILD_CMD); $(SECRETS_POST))

remote/switch:
	$(call SSH_RUN,$(NIXUSER),cd $(NIXCFG); $(SECRETS_PRE); $(REMOTE_SWITCH_CMD); $(SECRETS_POST)) && \
	$(call BACKUP_FLAKE_LOCK,remote host $(NIXHOST))

remote/copy-switch: remote/copy remote/switch

builder/switch:
	@# This is a single shell script to allow sharing the SYSTEM_PATH variable
	@if [ -z "$(strip $(BUILDER_HOST))" ]; then \
		echo "[INFO] Building locally..."; \
		$(MAKE) build; \
		SYSTEM_PATH=$$(readlink -f ./result); \
		echo "[INFO] Copying derivation to $(NIXHOST) at $(NIXADDR)..."; \
		nix copy $(FLAKE_FEATURES) $(SUBSTITUTE_OPTS) --to ssh://$(NIXUSER)@$(NIXADDR) $$SYSTEM_PATH; \
	else \
		echo "[INFO] Using remote builder: $(BUILDER_HOST)"; \
		echo "[INFO] Syncing source code to builder..."; \
		rsync -avh $(FLAKE_EXCLUDE) -e 'ssh $(SSH_OPTIONS)' --delete $(FLAKE_DIR)/ $(BUILDER_HOST):$(BUILDER_NIXCFG_PATH); \
		echo "[INFO] Building on builder..."; \
		SYSTEM_PATH=$$(ssh -n $(SSH_OPTIONS) $(BUILDER_HOST) "cd $(BUILDER_NIXCFG_PATH) && nix build $(FLAKE_FEATURES) --print-out-paths $(FLAKE_ATTR_CMD)"); \
		echo "[INFO] Instructing builder to push derivation to $(NIXHOST)..."; \
		ssh $(SSH_OPTIONS) $(BUILDER_HOST) "nix copy $(FLAKE_FEATURES) $(SUBSTITUTE_OPTS) --to ssh://$(NIXUSER)@$(NIXADDR) $$SYSTEM_PATH"; \
	fi; \
	\
	if [ -z "$$SYSTEM_PATH" ]; then $(call ERROR,Failed to get system path from build); exit 1; fi; \
	\
	$(call INFO,System path is $$SYSTEM_PATH); \
	$(call INFO,Switching configuration on $(NIXHOST)...); \
	$(call SSH_RUN,$(SSHUSER),sudo $$SYSTEM_PATH/bin/switch-to-configuration switch); \
	\
	$(call BACKUP_FLAKE_LOCK,remote host $(NIXHOST))

remote/cleanup:
	$(call SSH_RUN,$(NIXUSER),$(call CLEANUP_CMD,./$(NIXCFG)))

remote/copy: remote/copy/secrets
	rsync -avh $(FLAKE_EXCLUDE) -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' \
		--delete $(FLAKE_DIR)/ $(NIXUSER)@$(NIXADDR):./$(NIXCFG)
	$(COPY_FLAKE_LOCK)

remote/copy/secrets:
ifeq ($(SECRETS), yes)
	rsync -avh -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' \
		--rsync-path="mkdir -p ./$(NIXCFG)/secrets/sops && rsync" \
		--delete ../lamt-secrets/sops/$(NIXHOST).yaml \
		$(NIXUSER)@$(NIXADDR):./$(NIXCFG)/secrets/sops/
endif

remote/copyssh:
	tar $(FLAKE_EXCLUDE) -czf - . | ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) "mkdir -p ./$(NIXCFG) && cd ./$(NIXCFG) && tar -xzf -"
	$(COPY_FLAKE_LOCK)

remote/keys:
	rsync -avh -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='.#*' --exclude='S.*' --exclude='*.conf' \
		$(GNUPGHOME)/ $(NIXUSER)@$(NIXADDR):~/.config/gnupg
	rsync -avh -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='config' --exclude='environment' --exclude='known_hosts*' \
		$(HOME)/.ssh/ $(NIXUSER)@$(NIXADDR):~/.ssh

# WSL Installer
wsl:
	sudo nix run ".#nixosConfigurations.wsl.config.system.build.tarballBuilder"

# Utility Targets
flake/update:
	@nix flake update $(TOKEN_OPT)

# Build Minimal ISO with Serial Console
iso/minimal:
	nix-build '<nixpkgs/nixos>' -A config.system.build.isoImage --system x86_64-linux -I nixos-config=./hosts/minimal-iso/default.nix

# Proxmox VM Management
# Creates a headless VM in Proxmox with specified specs, virtio drivers for performance,
# no VGA for headless operation, serial socket for console access, and NixOS ISO for boot.
proxmox/create-vm:
	$(call INFO,====> Step 1/4: Creating Proxmox VM $(VMID) on $(PROXMOX_HOST)...)
	ssh $(SSH_OPTIONS) -p$(NIXPORT) root@$(PROXMOX_HOST) "qm create $(VMID) \
		--name $(VM_NAME) \
		--memory $(VM_MEMORY) \
		--cores $(VM_CORES) \
		--net0 virtio,bridge=$(VM_BRIDGE) \
		--scsihw virtio-scsi-pci \
		--scsi0 $(VM_STORAGE):$(VM_DISK_SIZE) \
		--efidisk0 $(VM_STORAGE):1 \
		--bios ovmf \
		--cdrom $(NIXOS_ISO),media=cdrom \
		--boot order=scsi0\\;ide2\\;net0 \
		--serial0 socket \
		--agent enabled=1 \
		--autostart 1" && $(call INFO,VM $(VMID) created successfully.)

# Starts the created VM.
proxmox/start-vm:
	$(call INFO,====> Step 2/4: Starting Proxmox VM $(VMID) on $(PROXMOX_HOST)...)
	ssh $(SSH_OPTIONS) -p$(NIXPORT) root@$(PROXMOX_HOST) "qm start $(VMID)" && $(call INFO,VM $(VMID) started successfully.)

# Stops and destroys the VM with confirmation.
proxmox/stop-destroy-vm:
	$(call WARN,CAUTION: This will stop and destroy the VM $(VMID). This is destructive!)
	read -p "Confirm stop and destroy (y/N)? " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		$(call ERROR,Stop and destroy cancelled.); \
		exit 1; \
	fi; \
	$(call INFO,====> Stopping Proxmox VM $(VMID) on $(PROXMOX_HOST)...); \
	ssh $(SSH_OPTIONS) -p$(NIXPORT) root@$(PROXMOX_HOST) "qm stop $(VMID)" && $(call INFO,VM $(VMID) stopped successfully.); \
	$(call INFO,====> Destroying Proxmox VM $(VMID) on $(PROXMOX_HOST)...); \
	ssh $(SSH_OPTIONS) -p$(NIXPORT) root@$(PROXMOX_HOST) "qm destroy $(VMID)" && $(call INFO,VM $(VMID) destroyed successfully.) \

# Retrieves the VM's IP address via nmap scan on the subnet
proxmox/get-vm-ip:
	$(call INFO,====> Step 3/4: Detecting VM IP via nmap...)
	@ssh -n $(SSH_OPTIONS) -p$(NIXPORT) root@$(PROXMOX_HOST) ' \
		echo "Retrieving MAC address for VM $(VMID)" >&2; \
		MAC=$$(qm config $(VMID) | grep ^net0 | sed "s/.*virtio=//;s/,.*//" | tr A-Z a-z); \
		echo "MAC address: $$MAC" >&2; \
		echo "Starting IP detection on subnet $(VM_SUBNET)" >&2; \
		for i in $$(seq 1 12); do \
			IP=$$(nmap -sn $(VM_SUBNET) 2>/dev/null | grep -i $$MAC -B 2 | grep "Nmap scan report" | rev | cut -d " " -f1 | rev); \
			[ ! -z "$$IP" ] && echo "Found IP: $$IP" >&2 && echo $$IP && break; \
			echo "Detecting... ($$i/12)" >&2; \
			sleep 5; \
		done; \
		[ -z "$$IP" ] && echo "IP detection failed after 12 attempts" >&2 && echo "" ; \
		exit 0 \
	' > /tmp/vm_ip_raw
	@VM_IP=$$(cat /tmp/vm_ip_raw); \
	if [ -z "$$VM_IP" ]; then \
		$(call ERROR,Failed to detect VM IP after scanning subnet $(VM_SUBNET). Check VM status, network config, or subnet.); \
		exit 1; \
	fi; \
	$(call INFO,VM IP found: $$VM_IP); \
	echo "NIXADDR=$$VM_IP" > /tmp/vm_ip.env

proxmox/deploy: proxmox/deploy0 proxmox/deploy1
proxmox/deploy0: proxmox/create-vm proxmox/start-vm
proxmox/deploy1: proxmox/get-vm-ip
	$(call INFO,====> Step 4/4: Bootstrapping remote system...)
	@source /tmp/vm_ip.env; \
	$(MAKE) remote/bootstrap NIXADDR=$$NIXADDR && \
	$(call INFO,NixOS VM deployed successfully at IP: $$NIXADDR)

proxmox/redeploy: proxmox/stop-destroy-vm proxmox/deploy

# DigitalOcean Droplet Management
digitalocean/create-droplet:
	$(call INFO,====> Creating DigitalOcean droplet $(NIXHOST) in $(DO_REGION)...)
	doctl compute droplet create $(NIXHOST) \
		--image $(DO_IMAGE) \
		--size $(DO_SIZE) \
		--region $(DO_REGION) \
		--ssh-keys $(DO_SSH_KEY) \
		--wait && $(call INFO,Droplet $(NIXHOST) created successfully.)

.PHONY: digitalocean/create-droplet

digitalocean/get-droplet-ip:
	$(call INFO,====> Getting droplet IP for $(NIXHOST)...)
	@DO_IP=$$(doctl compute droplet list --format ID,Name,PublicIPv4 --no-header | grep $(NIXHOST) | awk '{print $$3}'); \
	if [ -z "$$DO_IP" ]; then \
		$(call ERROR,Failed to get IP for droplet $(NIXHOST)); \
		exit 1; \
	fi; \
	$(call INFO,Droplet IP found: $$DO_IP); \
	echo "NIXADDR=$$DO_IP" > /tmp/do_ip.env

.PHONY: digitalocean/get-droplet-ip

digitalocean/convert-switch:
	$(call INFO,Converting Ubuntu droplet to NixOS at $(NIXADDR)...)
	@if [ -z "$(NIXADDR)" ] || [ "$(NIXADDR)" = "unset" ]; then \
		$(call ERROR,NIXADDR required: make digitalocean/convert-switch NIXADDR=123.456.789.0); \
		exit 1; \
	fi
	$(call WARN,⚠️  This will REPLACE Ubuntu with NixOS. All data will be lost!)
	@read -p "Proceed with conversion? (y/N): " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		$(call INFO,Conversion cancelled.); \
		exit 0; \
	fi
	$(call INFO,Starting conversion...)
	$(MAKE) remote/bootstrap NIXADDR=$(NIXADDR)
	$(call INFO,✅ NixOS ready at $(NIXADDR))

.PHONY: digitalocean/convert-switch

digitalocean/deploy: digitalocean/create-droplet digitalocean/get-droplet-ip
	$(call INFO,====> Bootstrapping NixOS on new droplet...)
	@source /tmp/do_ip.env; \
	$(MAKE) remote/bootstrap NIXADDR=$$NIXADDR && \
	$(call INFO,NixOS deployed successfully on DigitalOcean droplet at IP: $$NIXADDR)

.PHONY: digitalocean/deploy

digitalocean/destroy-droplet:
	$(call WARN,CAUTION: This will destroy the droplet $(NIXHOST). This is destructive!)
	@read -p "Confirm destroy (y/N)? " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		$(call ERROR,Droplet destroy cancelled.); \
		exit 1; \
	fi; \
	$(call INFO,====> Destroying DigitalOcean droplet $(NIXHOST)...); \
	doctl compute droplet delete $(NIXHOST) --force && $(call INFO,Droplet $(NIXHOST) destroyed successfully.)

.PHONY: digitalocean/destroy-droplet

# Ubuntu Cloud VM Management
proxmox/create-cloudinit-vm:
	$(call INFO,====> Creating $(CLOUDINIT_IMG_SYSTEM) cloud-init VM $(VMID) on $(PROXMOX_HOST)...)
	@SSH_KEY="$$(nix eval --raw --impure --expr 'let defs = import ./defines.nix; in defs.mySshAuthKey')"; \
	ssh $(SSH_OPTIONS) root@$(PROXMOX_HOST) "echo \"$$SSH_KEY\" > /tmp/ssh_key_$(VMID).pub && qm create $(VMID) \
		--name $(VM_NAME) \
		--memory $(VM_MEMORY) \
		--cores $(VM_CORES) \
		--net0 virtio,bridge=$(VM_BRIDGE) \
		--ipconfig0 ip=dhcp \
		--efidisk0 $(VM_STORAGE):1 \
		--ide2 $(VM_STORAGE):cloudinit \
		--bios ovmf \
		--boot order=virtio0\\;ide2\\;net0 \
		--serial0 socket \
		--agent enabled=1 \
		--autostart 1 \
		--ciuser $(CLOUDINIT_USER) \
		--sshkeys /tmp/ssh_key_$(VMID).pub && \
	qm importdisk $(VMID) $(CLOUDINIT_IMG_PATH) $(VM_STORAGE) && \
	qm set $(VMID) --virtio0 $(VM_STORAGE):vm-$(VMID)-disk-1 && \
	qm resize $(VMID) virtio0 $(VM_DISK_SIZE)G && \
	rm /tmp/ssh_key_$(VMID).pub" && $(call INFO,VM $(VMID) ($(CLOUDINIT_IMG_SYSTEM)) created successfully.)

proxmox/create-cloudinit-vm-seabios:
	$(call INFO,====> Creating $(CLOUDINIT_IMG_SYSTEM) cloud-init VM $(VMID) on $(PROXMOX_HOST) (BIOS mode)...)
	@SSH_KEY="$$(nix eval --raw --impure --expr 'let defs = import ./defines.nix; in defs.mySshAuthKey')"; \
	ssh $(SSH_OPTIONS) root@$(PROXMOX_HOST) "echo \"$$SSH_KEY\" > /tmp/ssh_key_$(VMID).pub && qm create $(VMID) \
		--name $(VM_NAME) \
		--memory $(VM_MEMORY) \
		--cores $(VM_CORES) \
		--net0 virtio,bridge=$(VM_BRIDGE) \
		--ipconfig0 ip=dhcp \
		--ide2 $(VM_STORAGE):cloudinit \
		--boot order=virtio0\\;ide2\\;net0 \
		--serial0 socket \
		--agent enabled=1 \
		--autostart 1 \
		--ciuser $(CLOUDINIT_USER) \
		--sshkeys /tmp/ssh_key_$(VMID).pub && \
	qm importdisk $(VMID) $(CLOUDINIT_IMG_PATH) $(VM_STORAGE) && \
	qm set $(VMID) --virtio0 $(VM_STORAGE):vm-$(VMID)-disk-0 && \
	qm resize $(VMID) virtio0 $(VM_DISK_SIZE)G && \
	rm /tmp/ssh_key_$(VMID).pub" && $(call INFO,VM $(VMID) ($(CLOUDINIT_IMG_SYSTEM)) created successfully (BIOS).)

.PHONY: proxmox/create-cloudinit-vm proxmox/create-cloudinit-vm-bios

proxmox/start-cloudinit-vm:
	$(call INFO,====> Starting $(CLOUDINIT_IMG_SYSTEM) cloud-init VM $(VMID) on $(PROXMOX_HOST)...)
	ssh $(SSH_OPTIONS) root@$(PROXMOX_HOST) "qm start $(VMID)" && $(call INFO,VM $(VMID) started successfully.)

.PHONY: proxmox/start-cloudinit-vm

proxmox/wait-cloudinit:
	$(call INFO,====> Waiting for $(CLOUDINIT_IMG_SYSTEM) cloud-init to complete...)
	@source /tmp/vm_ip.env; \
	for i in $$(seq 1 24); do \
		$(call INFO,Waiting for cloud-init... ($$i/24)); \
		if ssh $(SSH_OPTIONS) $(CLOUDINIT_USER)@$$NIXADDR "cloud-init status --wait --long 2>/dev/null | grep -q 'status: done'"; then \
			$(call INFO,Cloud-init completed successfully.); \
			break; \
		fi; \
		if [ $$i -eq 24 ]; then \
			$(call ERROR,Cloud-init did not complete within timeout.); \
			exit 1; \
		fi; \
		sleep 5; \
	done

.PHONY: proxmox/wait-cloudinit

proxmox/deploy-cloudinit-vm: proxmox/create-cloudinit-vm proxmox/start-cloudinit-vm proxmox/get-vm-ip proxmox/wait-cloudinit
	@source /tmp/vm_ip.env; \
	$(call INFO,Cloud-init VM ($(CLOUDINIT_IMG_SYSTEM)) deployed successfully at IP: $$NIXADDR)

.PHONY: proxmox/deploy-cloudinit-vm

proxmox/redeploy-cloudinit-vm: proxmox/stop-destroy-vm proxmox/deploy-cloudinit-vm

.PHONY: proxmox/redeploy-cloudinit-vm

# Phony Targets
.PHONY: build switch test wsl builder/switch flake/update proxmox/deploy proxmox/deploy-cloudinit-vm remote/bootstrap digitalocean/deploy digitalocean/convert-switch iso/minimal
