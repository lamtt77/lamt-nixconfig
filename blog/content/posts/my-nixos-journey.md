---
title: "My NixOS Journey: From Arch Linux and FreeBSD to Declarative Configuration"
date: 2025-10-16T00:00:00Z
draft: false
---

# My NixOS Journey: From Arch Linux and FreeBSD to Declarative Configuration

## Introduction

Picture this: years spent wrestling with Arch Linux's bleeding-edge updates and FreeBSD's meticulous stability, only to realize there's a better way. Enter NixOS, the declarative operating system that promised to revolutionize how I manage my infrastructure. The transition wasn't just a switch—it was an awakening. And along the way, I've harnessed the power of agentic coding to supercharge my NixOS configurations, turning potential chaos into a symphony of automated reliability.

## The Magic of Automated Deployment

Imagine starting from absolute scratch: a bare-metal server or a fresh VM with nothing but a NixOS ISO. With our system, it's as simple as running a single command—a "super one-liner" that orchestrates the entire deployment. This powerhouse script handles disk partitioning via Disko, installs a minimal NixOS base, sets up SSH for remote access, and bootstraps your full configuration. From zero to a fully functional, customized system in minutes, all while you sip your coffee. No more manual partitioning, no tedious package installations—just pure, declarative magic that builds your entire environment from the ground up, ensuring every host is identical and reproducible.

For beginners, getting started is straightforward: boot into the NixOS minimal ISO, set a temporary root password, and run the installer command. It automatically detects your hardware, partitions the disk, installs NixOS, and configures everything according to your flake. Within 5-10 minutes, you'll have a production-ready system ready for your specific use case.

## Centralized Build System: The Makefile Maestro

At the heart of our deployment workflow is a centralized Makefile that acts as the conductor for all operations. This single file provides intuitive targets for everything from building to switching configurations. Key targets include:

- `make build`: Compiles your NixOS configuration locally
- `make switch`: Applies the configuration to your current system
- `make test`: Dry-runs the configuration without applying changes
- `make remote/bootstrap`: Deploys to a remote machine from scratch (use with caution—it erases disks!)
- `make builder/switch`: Builds on one machine, deploys to another

This centralized approach eliminates guesswork, ensuring consistent deployments across all your hosts.

## The Installer: apps/installer-staging/

Our custom installer, located in `apps/installer-staging/`, is the secret sauce behind seamless deployments. This Nix flake app handles the heavy lifting: it partitions disks with Disko, sets up SSH keys, syncs your configuration repository, and performs the initial system build. It's designed for reliability, with features like kexec boot acceleration for faster deployments and low-memory optimizations for resource-constrained systems.

## Build Flexibility: Remote, Local, and Cross-Compilation

One of the standout advantages of our system is its build flexibility. You can build configurations remotely on the target machine, locally on your development box and copy the artifacts, or even cross-compile for different architectures. Remote builds are great for powerful servers, local builds shine when deploying to low-resource devices, and cross-compilation enables deploying ARM systems from x86 machines. This versatility means you can always choose the most efficient path for your specific scenario.

## Builder/Switch: Effortless Remote Updates

The `builder/switch` target is a game-changer for managing remote systems. It builds your configuration on a powerful local or remote builder machine, then seamlessly copies and activates it on the target host. Perfect for updating Raspberry Pis or other low-powered devices without straining their resources. No more waiting hours for builds on underpowered hardware—just fast, efficient deployments that respect your time.

## Secrets Management: Secure and Git-Safe

Handling sensitive data like API keys and passwords is crucial, and our system does it right with SOPS-encrypted secrets. Secrets are stored in `secrets/sops/` as encrypted YAML files, decrypted only during builds, and never committed to Git. The Makefile includes pre/post hooks that stage secrets for builds but remove them from Git tracking, preventing accidental commits. This ensures your sensitive data stays secure while maintaining the declarative nature of your configurations.

## System Architecture: A Modular Masterpiece

Under the hood, our NixOS setup is a marvel of modularity. Host-specific configs live in dedicated directories, shared modules provide reusable components, and overlays customize packages without breaking the ecosystem. Flake-based builds guarantee that every deployment is locked to exact versions, eliminating the dreaded "works on my machine" syndrome. This architecture scales effortlessly, whether you're deploying to a Raspberry Pi or a high-end gaming rig.

## Future Vision: A Fully Declarative Homelab

My ultimate goal? To obliterate every manual configuration in my homelab and personal setups, replacing them with this NixOS powerhouse. A world where my entire digital life—servers, workstations, even my development environments—is defined in code, deployable with a single command, and immune to the entropy of manual changes.