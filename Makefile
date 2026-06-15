# Makefile - Wrapper for NixOS Installer/Orchestrator in Rust

.PHONY: switch boot build test deploy sync destroy info fmt update wsl iso/minimal iso/minimal/aarch64

NXD ?= $(shell command -v nxd 2>/dev/null || echo "nix run '.\#nxd' --")

# Default Target
.DEFAULT_GOAL := switch

switch boot build test deploy sync destroy info:
	$(NXD) $@ $(ARGS)

fmt:
	nix fmt

update:
	nix flake update

wsl:
	$(NXD) deploy --target wsl $(ARGS)

iso/minimal:
	nix build '.\#nixosConfigurations.minimal-iso-x86.config.system.build.isoImage' -o result-iso-x86

iso/minimal/aarch64:
	nix build '.\#nixosConfigurations.minimal-iso-aarch64.config.system.build.isoImage' -o result-iso-aarch64
