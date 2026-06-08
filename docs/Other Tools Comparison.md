# Other Tools Comparison

## High-Level Difference

Colmena is a general-purpose, stateless NixOS deployment tool: it builds/evaluates a "hive" and applies existing NixOS configs over SSH. Its README describes it as a thin wrapper over Nix commands with parallel deployment support.

Source: <https://github.com/zhaofengli/colmena>

Our `installer-rs` is more of a lifecycle orchestrator: it can provision, bootstrap, convert, stage secrets, handle provider lifecycle, run Disko installs, route builds, and then switch/update hosts.

## Comparison

| Area | Colmena | `installer-rs` |
| :--- | :--- | :--- |
| Primary job | Deploy existing NixOS nodes | Provision, bootstrap, install, switch, sync, destroy |
| Target model | NixOS nodes in a hive | Declared hosts with provider/deployment metadata |
| Bootstrap new machines | Not the main purpose | Core feature: Proxmox, DigitalOcean, kexec, Disko |
| Existing host updates | Strong | Strong, with rollback safety |
| Parallelism | Mature: `--parallel`, node selection, tags | Present: concurrent batch deploy/switch with isolated workspaces/logs |
| Host selection | `--on host,@tag,glob` | `--hosts host1,host2` / `-t host` |
| Secrets | `deployment.keys`, uploaded out-of-band and not in Nix store | SOPS host secrets, SSH host key/age alignment, Tailscale preauth staging |
| Build modes | Local or target build via `deployment.buildOnTarget` / CLI override | Local, remote builder, target native, target realization, substitute-on-destination |
| Safety around unknown/existing profiles | `deployment.replaceUnknownProfiles` / force flag | rollback switch, existing provider skip by default, `--overwrite`, `--redeploy`, `--convert-to` |
| Cloud/provider lifecycle | Not its focus | First-class provider lifecycle |
| Local deployment | `apply-local` with explicit option | local switch path plus Darwin/NixOS support |
