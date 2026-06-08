# Makefile - Wrapper for NixOS Installer/Orchestrator in Rust

.PHONY: switch deploy sync destroy info fmt update wsl iso/minimal iso/minimal/vlan iso/minimal/aarch64

LAMD ?= nix run .#installer-rs --

# Default Target
.DEFAULT_GOAL := switch

switch deploy sync destroy info:
	$(LAMD) $@ $(ARGS)

fmt:
	nix fmt

update:
	nix flake update

wsl:
	$(LAMD) deploy --target wsl $(ARGS)

iso/minimal:
	nix build .#nixosConfigurations.minimal-iso-x86.config.system.build.isoImage -o result-iso-x86

iso/minimal/vlan:
	nix build .#nixosConfigurations.minimal-iso-vlan.config.system.build.isoImage -o result-iso-vlan

iso/minimal/aarch64:
	nix build .#nixosConfigurations.minimal-iso-aarch64.config.system.build.isoImage -o result-iso-aarch64
