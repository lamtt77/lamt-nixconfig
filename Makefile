# Connectivity info for Remote Machine
NIXADDR ?= unset
NIXPORT ?= 22
NIXUSER ?= lamt
# The hostname of the nixos/darwin Configuration in the flake
NIXHOST ?= avon
NIXCFG ?= lamt-nixconfig
TEA_URL ?= tea.lamhub.com

SSH_COPY_ID ?= yes
SECRETS ?= no

# OS switching
UNAME := $(shell uname)

# nh output monitoring
NH ?= yes

OFFLINE ?=
ifeq ($(OFFLINE), yes)
	OFFLINE = --option substitute false
endif

NIXOS_SWITCH ?= sudo nixos-rebuild switch $(OFFLINE) --flake ".\#$(NIXHOST)"
DARWIN_SWITCH ?= sudo nix run -- nix-darwin switch $(OFFLINE) --flake ".\#${NIXHOST}"
HM_SWITCH ?= nix run -- home-manager switch $(OFFLINE) --flake ".\#${NIXUSER}"

ifeq ($(NH), yes)
	NIXOS_SWITCH = nh os switch . --hostname $(NIXHOST)
	DARWIN_SWITCH = nh darwin switch . --hostname $(NIXHOST)
	HM_SWITCH = nh home switch .
endif

ifeq ($(UNAME), Darwin)
	OS_SWITCH = $(DARWIN_SWITCH)
else
	OS_SWITCH = $(NIXOS_SWITCH)
endif

FORCE ?=
ifeq ($(FORCE), yes)
	FORCE = -- --force
endif

GH_REPO ?= github:lamtt77/$(NIXCFG)
TEA_REPO ?= git+ssh://git@$(TEA_URL)/lamtt77/$(NIXCFG)
LOCAL_REPO ?= path:/root/$(NIXCFG)
ifeq ($(NIXREPO), tea)
	MYREPO = $(TEA_REPO)
else ifeq ($(NIXREPO), local)
	MYREPO = $(LOCAL_REPO)
else
	MYREPO = $(GH_REPO)
endif

# Get the path to this Makefile and Flake directory
FLAKE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

FLAKE_FEATURES ?= --extra-experimental-features \"nix-command flakes\"

FLAKE_EXCLUDE ?= --exclude='.git/' --exclude='secrets/' --exclude='result' --exclude='.DS_Store'

SSH_OPTIONS=-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no

copy/secrets:
	mkdir -p ./secrets/agenix
	rsync -av \
        --delete \
        ../lamt-secrets/agenix/{secrets.nix,$(NIXHOST)} secrets/agenix/
pre-secrets:
	test -d .git && test -d secrets && echo PRE-secrets && git add secrets/ || true
post-secrets:
	test -d .git && test -d secrets && echo POST-secrets && git rm --cached -r secrets/ || true

build0:
ifeq ($(UNAME), Darwin)
	nix build --extra-experimental-features "nix-command flakes" ".#darwinConfigurations.${NIXHOST}.system"
else
	nix build ".#nixosConfigurations.${NIXHOST}.config.system.build.toplevel"
endif

switch0:
	$(OS_SWITCH)

# switch home-manager modules only, sudo is not needed
switch/hm:
	$(HM_SWITCH)

test0:
ifeq ($(UNAME), Darwin)
	sudo nix run -- nix-darwin check --flake ".#${NIXHOST}"
else
	sudo nixos-rebuild test --flake ".#${NIXHOST}"
endif

# Main entry points, pre/post hack will remain until Nix supported git submodule properly
# Goal: isolate secrets by each host, nix/store only contains secrets of the running host
build: pre-secrets build0 post-secrets
switch: pre-secrets switch0 post-secrets
test: pre-secrets test0 post-secrets

# This will ERASE all data of the REMOTE machine's hard disk! Use at your OWN RISK!!!
#
# Format and setup a brand new Remote Host. One-time/liner installation :)
# Set a temp password for the root user before bootstrap for ssh connectivity,
# the password is only valid during installation session.
#
# Forwarding ssh-agent '-A' is only required for accessing my private repo, this
# deployment machine should already have the private-key installed.
#
# NixOS Minimal does not have git, which is required for nixos-install
# git+ssh also requires git pre-installed
#
# Low performance system may have out of memory (OOM) issue during Stage1, or sometime
# ssh may disconnect abnormally, if so simply do one more time 'remote/bootstrap1'
#
# After Stage1 completed, optionally reboot then 'remote/switch' with NIXUSER=<youruser>
remote/bootstrap:
ifeq ($(SSH_COPY_ID), yes)
	ssh-copy-id $(SSH_OPTIONS) -p$(NIXPORT) root@${NIXADDR}
endif
ifeq ($(NIXREPO), local)
	NIXUSER=root $(MAKE) remote/copyscp
endif
	$(MAKE) remote/bootstrap0 || true
	@echo "====>Stage1: Rebooting..."; sleep 30
	$(MAKE) remote/bootstrap1

# staging still works best for all configurations, especially for low performance system
remote/bootstrap0:
	@echo "====>Stage0: Staging..."
	ssh -A $(SSH_OPTIONS) -p$(NIXPORT) root@$(NIXADDR) " \
		test -f ./.ssh/known_hosts || (mkdir -p ./.ssh && \
		  ssh-keyscan -H ${TEA_URL} > ./.ssh/known_hosts); \
        nix-shell -p gitMinimal --run 'nix run ${FLAKE_FEATURES} \
          \"${MYREPO}#installer-staging\" ${FORCE} ${NIXHOST}' && reboot; \
    "

# If Stage1 completed, 'root' will be blocked from ssh login, use your user instead
# Can safely re-run 'remote/bootstrap1' if ssh disconnected
# TODO: default to 'yes' when nh moved to nixpkgs stable
remote/bootstrap1:
	@echo "====>Stage1: Host Swiching/Activating... Ctrl-C to terminate"
	until ssh $(SSH_OPTIONS) -p$(NIXPORT) root@$(NIXADDR) true; do sleep 3; done
ifeq ($(SECRETS), yes)
	NIXUSER=root $(MAKE) remote/copy/secrets
endif
	NIXUSER=root $(MAKE) remote/build
	NIXUSER=root NH=no $(MAKE) remote/switch
	$(MAKE) remote/cleanup/root

# experimental: only one stage required
# mkdir -p /mnt/tmp && export TMPDIR=/mnt/tmp; \
# READ: https://stackoverflow.com/questions/76591674/nix-gives-no-space-left-on-device-even-though-nix-has-lots
# TODO: figure out how to forward ssh agent to 'chroot' for secrets deployment
remote/bootstrap/chroot:
	ssh -A $(SSH_OPTIONS) -p$(NIXPORT) root@$(NIXADDR) " \
        nix-shell -p gitMinimal --run 'nix run ${FLAKE_FEATURES} \
          \"${MYREPO}#installer-nixos-enter\" ${NIXHOST}' && reboot; \
    "

remote/build:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
		cd ${NIXCFG}; \
		test -d .git && test -d secrets && echo PRE-secrets && git add secrets/; \
		nix build '.#nixosConfigurations.${NIXHOST}.config.system.build.toplevel'; \
		test -d .git && test -d secrets && echo POST-secrets && git rm --cached -r secrets/ || true; \
	"

# This does NOT copy files so you have to run remote/copy before.
remote/switch:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
		cd ${NIXCFG}; \
		test -d .git && test -d secrets && echo PRE-secrets && git add secrets/; \
		${NIXOS_SWITCH}; \
		test -d .git && test -d secrets && echo POST-secrets && git rm --cached -r secrets/ || true; \
	"

remote/copy-switch: remote/copy remote/switch

remote/cleanup/root:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) "sudo sh -c ' \
		test -d /root/${NIXCFG} && rm -rf /root/${NIXCFG}; \
		test -d /root/result && rm /root/result; \
		nix-collect-garbage -d; ' \
	"

remote/cleanup:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
		test -d ./${NIXCFG} && rm -rf ${NIXCFG}; \
		test -d result && rm result; \
        nix-collect-garbage -d; \
	"

# copy the Nix configurations into the Remote Machine. For local setup without github
remote/copy: remote/copy/secrets
	rsync -av $(FLAKE_EXCLUDE) -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' \
        --delete \
		$(FLAKE_DIR)/ $(NIXUSER)@$(NIXADDR):./$(NIXCFG)

remote/copy/secrets:
ifeq ($(SECRETS), yes)
	cd ../lamt-secrets/agenix; agenix -d $(NIXHOST)/id_agenix.age \
	    | ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
        sudo sh -c 'cat > /etc/ssh/id_agenix && chmod 600 /etc/ssh/id_agenix'; \
    "; cd ../../$(NIXCFG)
	rsync -av -e 'ssh ${SSH_OPTIONS} -p${NIXPORT}' \
		--rsync-path="mkdir -p ./${NIXCFG}/secrets/agenix && rsync" \
        --delete \
		../lamt-secrets/agenix/{secrets.nix,$(NIXHOST)} \
        $(NIXUSER)@$(NIXADDR):./$(NIXCFG)/secrets/agenix/
endif

# NixOS Minimal does not have 'rsync', and 'scp' does not support exclude files, thus this tmpdir trick
remote/copyscp:
	@tmpdir=`mktemp --tmpdir -d`; trap 'rm -rf "$$tmpdir"' EXIT; echo $$tmpdir; \
	rsync -a $(FLAKE_EXCLUDE) \
        --delete \
		$(FLAKE_DIR)/ $$tmpdir/$(NIXCFG); \
	scp -r $(SSH_OPTIONS) -p$(NIXPORT) $$tmpdir/$(NIXCFG) $(NIXUSER)@$(NIXADDR):./

# copy our GPG keyring and SSH keys secrets into the Remote Machine
remote/keys:
	rsync -av -e 'ssh $(SSH_OPTIONS) -p$(NIXPORT)' \
		--exclude='.#*' \
		--exclude='S.*' \
		--exclude='*.conf' \
		$(GNUPGHOME)/ $(NIXUSER)@$(NIXADDR):~/.config/gnupg
	rsync -av -e 'ssh $(SSH_OPTIONS)' \
		--exclude='environment' \
		$(HOME)/.ssh/ $(NIXUSER)@$(NIXADDR):~/.ssh

# Build a WSL installer
.PHONY: wsl
wsl:
	sudo nix run ".#nixosConfigurations.wsl.config.system.build.tarballBuilder"
