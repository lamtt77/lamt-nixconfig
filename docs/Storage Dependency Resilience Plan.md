# Storage Dependency Resilience Plan

## Status

Deferred infrastructure work. This plan is not part of the active NXD consumer
migration and does not authorize production mutation.

## Problem

A virtualization-node restart also restarted the VM providing shared storage.
Guests whose virtual disks depended on that storage remained active during the
path outage, received block I/O errors, and remounted ext4 read-only. Restarting
the affected builder restored service after storage paths recovered.

## Goal

Prevent a storage-provider VM restart from causing silent filesystem damage or
extended read-only operation in dependent guests.

## Work

- Map the storage-provider VM, hypervisor, Fibre Channel, multipath, and guest
  dependency graph, including startup and shutdown ordering.
- Decide whether the storage control plane must move outside the virtualization
  failure domain or be made independently highly available.
- Define explicit hypervisor ordering and readiness checks so dependent guests
  cannot start or remain active without healthy storage paths.
- Review multipath timeouts, queueing, path recovery, and filesystem error
  policies against the storage vendor and operating-system guidance.
- Add monitoring for path loss, device-mapper I/O errors, aborted journals,
  read-only remounts, and Nix builder health.
- Create a reviewed recovery runbook covering storage restoration, guest
  shutdown/restart, offline filesystem checks, validation, and rollback.
- Verify current backups before any repair trial.
- Test the failure and recovery sequence using disposable guests before changing
  production ordering or storage policy.

## Completion criteria

- The dependency graph and chosen architecture are reviewed.
- A storage outage cannot leave dependent guests serving from a read-only or
  journal-aborted root filesystem without an alert.
- Startup, shutdown, monitoring, backup, and recovery procedures are tested.
- The global distributed Nix builder passes both SSH and `ssh-ng` store health
  checks after a simulated storage-path interruption.
