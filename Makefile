# Makefile - Wrapper for NixOS Installer/Orchestrator in Rust

.PHONY: switch deploy sync destroy info fmt update wsl iso/minimal iso/minimal/vlan iso/minimal/aarch64

# Default Target
.DEFAULT_GOAL := switch

switch deploy sync destroy info:
	nix run .#installer-rs -- $@ $(ARGS)

fmt:
	nix fmt

update:
	nix flake update

wsl:
	nix run .#installer-rs -- deploy --target wsl $(ARGS)

iso/minimal:
	nix build .#nixosConfigurations.minimal-iso-x86.config.system.build.isoImage -o result-iso-x86-flake

iso/minimal/vlan:
	nix build .#nixosConfigurations.minimal-iso-vlan.config.system.build.isoImage -o result-iso-vlan-flake

iso/minimal/aarch64:
	nix build .#nixosConfigurations.minimal-iso-aarch64.config.system.build.isoImage -o result-iso-aarch64-flake
