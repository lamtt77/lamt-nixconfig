# Nix Config Performance Optimization Plan

This document outlines the evaluation performance bottlenecks in the Nix configuration repository and defines the implementation plan for the final optimization phase.

## 1. Agreed Baseline Optimizations

### Phase 1: Disable Option Documentation & Manual Generation

- **Goal**: Solve the `builtins.derivation` warning during evaluation and reclaim ~2s of execution time by preventing Nix from building HTML manuals and JSON option databases.
- **Scope**:
  - **System (nix-darwin / NixOS)**:
    Set the following in [modules/os/base/core.nix](file:///Users/lamt/lamt-nixconfig/modules/os/base/core.nix):
    ```nix
    documentation.enable = false;
    documentation.info.enable = false;
    # Note: Keep documentation.man = true (or defaults) to retain command man pages.
    ```
  - **Home Manager**:
    Set the following in [modules/hm/base/core.nix](file:///Users/lamt/lamt-nixconfig/modules/hm/base/core.nix):
    ```nix
    manual.html.enable = false;
    manual.manpages.enable = false;
    manual.json.enable = false;
    ```

### Phase 2: Eliminate `${self}` / `${inputs.self}` store path dependencies

- **Goal**: Ensure that editing non-Nix files (like Rust source in `installer-rs` or Markdown docs) does **not** invalidate the Nix evaluation cache of your system config.
- **Scope**: Replace instances of `${self}` and `${inputs.self}` with **relative paths** in the following modules:
  - **[modules/hm/base/git.nix](file:///Users/lamt/lamt-nixconfig/modules/hm/base/git.nix)**:
    - _Before_: `cp ${self}/config/git/hooks/pre-commit ...`
    - _After_: `cp ${../../../config/git/hooks/pre-commit} ...`
  - **[modules/hm/base/zsh.nix](file:///Users/lamt/lamt-nixconfig/modules/hm/base/zsh.nix)**:
    - _Before_:
      - `".p10k.zsh".source = "${self}/config/zsh/.p10k.zsh";`
      - `initContent = builtins.readFile "${self}/config/zsh/.z4hrc";`
    - _After_:
      - `".p10k.zsh".source = ../../../config/zsh/.p10k.zsh;`
      - `initContent = builtins.readFile ../../../config/zsh/.z4hrc;`
  - **[modules/os/base/services/sops.nix](file:///Users/lamt/lamt-nixconfig/modules/os/base/services/sops.nix)**:
    - _Before_: `secretsFile = "${inputs.self}/secrets/sops/${myargs.hostname}.yaml";`
    - _After_: `secretsFile = ../../../secrets/sops + "/${myargs.hostname}.yaml";`
  - **[modules/os/base/\_workstation.nix](file:///Users/lamt/lamt-nixconfig/modules/os/base/_workstation.nix)**:
    - _Before_: `"nixpkgs-overlays=${self}/overlays"`
    - _After_: `"nixpkgs-overlays=${../../../overlays}"`
  - **[modules/os/linux/desktop/i3.nix](file:///Users/lamt/lamt-nixconfig/modules/os/linux/desktop/i3.nix)** & **[sway.nix](file:///Users/lamt/lamt-nixconfig/modules/os/linux/desktop/sway.nix)**:
    - _Before_: `"${self}/config/_linux/i3"`
    - _After_: `../../../../config/_linux/i3`
  - **[modules/os/linux/services/backup.nix](file:///Users/lamt/lamt-nixconfig/modules/os/linux/services/backup.nix)**:
    - _Before_: `inputs.self + "/pkgs/..."`
    - _After_: `../../../../pkgs/...`
- **Impact on `mkLink`**: None. `mkLink` uses string path concatenation of your home folder and the local repository name (`config.home.homeDirectory + "/" + mydefs.myRepoName + "/" + path`), resolving paths at runtime rather than evaluation time.

### Phase 3: Makefile instant-start wrapper

- **Goal**: Drop the ~3s `nix run` check overhead when running routine Makefile commands on already managed systems.
- **Scope**: Update [Makefile](file:///Users/lamt/lamt-nixconfig/Makefile) to detect and use the installed `lamd` binary from `$PATH` directly, falling back to `nix run` only when bootstrapping new hosts.
  ```makefile
  LAMD ?= $(shell command -v lamd 2>/dev/null || echo "nix run '.\#installer-rs' --")
  ```

---

## 2. Dynamic Feature Architecture (Design A)

To eliminate the eager loading of all 80+ modules via `mapModulesRec'` (which forces the evaluator to parse and compile unused services like Hyprland or Jellyfin for every host), we will migrate to **Design A** (Metadata-driven Feature Imports).

### Folder Structure Simplification & Platform-Specific Features (Design C)

To make base and optional modules clean and self-documenting, the sibling directories under `modules/os/` and `modules/hm/` are simplified to exactly two folders: `base/` (eagerly loaded baseline) and `feat/` (conditionally loaded features):

1. **`base/` (Eager Baseline)**:
   - Contains baseline configs loaded automatically based on host class (`nixos` vs `darwin` vs `wsl`).
   - Shared baseline files sit at the root (e.g. `core.nix`, `nixpath-registry.nix`, `default.nix`).
   - Platform-locked baseline files are grouped in subfolders (e.g. `base/linux/`, `base/darwin/`, `base/wsl/`).

2. **`feat/` (On-Demand Features)**:
   - Contains optional configs imported only when specified in `osFeatures` or `hmFeatures` via host metadata, profiles, or role defaults.
   - Shared features sit at the root folder level (e.g., `feat/services/tailscale.nix`, `feat/git.nix`).
   - Platform-locked features are nested inside platform folders (e.g., `feat/linux/services/openssh.nix`, `feat/linux/desktop/i3.nix`, `feat/darwin/services/nfsd.nix`).

#### Decoupling systems.nix from Host Roles

The hardcoded `(if server then [ _server.nix ] else [ _workstation.nix ])` import is removed from `lib/systems.nix`.
Instead, `_server.nix` and `_workstation.nix` are renamed to `modules/os/feat/server.nix` and `modules/os/feat/workstation.nix`. They are declaratively imported by adding their path features to [flake/host-roles.nix](file:///Users/lamt/lamt-nixconfig/flake/host-roles.nix):

- `server` and `router` roles include `../../modules/os/feat/server.nix`.
- `workstation`, `laptop`, and `wsl` roles include `../../modules/os/feat/workstation.nix`.

This allows us to completely remove the `server` boolean parameter from the functions in `lib/systems.nix` (`mkSystem`, `mkHost`, `nixos-modules`).

### Metadata Configuration (`hosts/<name>/meta.nix`)

Feature scope is explicit:

- `osFeatures` contains NixOS or nix-darwin modules.
- `hmFeatures` contains Home Manager modules and package-group modules.
- A plain path is a standard module.
- A parameterized feature uses `{ module = <path>; args = { ... }; }`.

Buildable hosts must declare a known `role`. Role features are merged with host features, while the flattened `features` field remains exported only for installer compatibility.

Example in `hosts/macair15-m2/meta.nix`:

```nix
{
  class = "darwin";
  system = "aarch64-darwin";
  username = "lamt";

  role = "workstation";

  osFeatures = [
    ../../modules/os/feat/services/builders.nix
  ];

  hmFeatures = [
    {
      module = ../../modules/hm/feat/editors/doomemacs.nix;
      args = { };
    }
  ];
}
```

### Profile & Role Configurations

Shared role features are defined as metadata. Reusable profiles may vary by platform and role, while host-specific choices such as Doom Emacs on `macair15-m2` are declared in host `hmFeatures`.

Feature ownership uses three distinct names:

- `profileFeatures`: reusable Home Manager features selected inside `profiles/<user>/default.nix`.
- `hmFeatures`: host-specific Home Manager additions declared in `hosts/<name>/meta.nix`.
- `imports`: the standard Nix module field that receives the resolved combination; it is wiring, not feature metadata.

```nix
# flake/host-roles.nix
{
  server = {
    server = true;
    tags = [ "server" ];
    osFeatures = [
      ../modules/os/feat/server.nix
    ];
  };

  workstation = {
    tags = [ "client" ];
    osFeatures = [
      ../modules/os/feat/workstation.nix
    ];
  };

  wsl = {
    wsl = true;
    tags = [ "wsl" ];
    osFeatures = [
      ../modules/os/feat/workstation.nix
    ];
  };
}
```

### Modular Packages Split (Feature Groups)

To prevent remote servers or lightweight VMs from carrying heavy dev/cli packages, we will split the giant packages array in `profiles/lamt/default.nix` into granular, opt-in feature groups:

- `"hm/base/profiles/lamt/sysadmin"`: Basic system tools (htop, iperf, ncdu, lsof, jq, nvd, etc.).
- `"hm/base/profiles/lamt/dev"`: Language runtimes and compiler tools (cargo, rustc, go, nodejs, python, devenv, zig).
- `"hm/base/profiles/lamt/cloud"`: Cloud provider integrations (doctl, borgbackup, rclone, restic).

These groups are imported by the self-contained user profile or explicitly by host `hmFeatures`:

```nix
let
  profileFeatures =
    [
      ../../modules/hm/feat/zsh.nix
      ./sysadmin.nix
    ]
    ++ lib.optional (role == "workstation") ./dev.nix
    ++ lib.optional (role == "workstation" || role == "server") ./cloud.nix;
in
{
  imports = my.resolveFeatures profileFeatures;
}
```

### Module Definition (Parameterized Function)

Modules no longer declare global option schemas or wrap themselves in `.enable` checks. They return a function accepting configuration parameters. Defaults are set directly in the arguments list:

```nix
# modules/os/base/services/tailscale.nix
{
  loginServer ? "https://ts.lamhub.com",
  exitNode ? false,
  authKey ? null,
}:
{ config, pkgs, lib, myargs, ... }:
# ... implementation using parameters directly
```

### Flake Integration & Core Modules (`flake/hosts.nix` & `lib/systems.nix`)

1. **Delete Eager Recursive Scanning**:
   Remove `mapModulesRec'` and `getPlatformModules` from [lib/systems.nix](file:///Users/lamt/lamt-nixconfig/lib/systems.nix).

2. **Define Core Modules via Entrypoint Directory Imports**:
   Instead of a verbose listing of individual files, rely on directory-level `default.nix` files to group eagerly loaded base modules (e.g., `modules/os/base/default.nix`, `modules/os/linux/default.nix`, `modules/os/darwin/default.nix`).

   In [lib/systems.nix](file:///Users/lamt/lamt-nixconfig/lib/systems.nix):

   ```nix
    coreOSModules =
      darwin: wsl:
      [
        ../modules/os/base
      ]
      ++ lib.optionals darwin [
        ../modules/os/base/darwin
      ]
      ++ lib.optionals (!darwin) (
        [
          ../modules/os/base/linux
        ]
        ++ lib.optionals wsl [
          ../modules/os/base/wsl
        ]
      );
   ```

3. **Map Dynamic Features (Support Relative Paths for Vim `gf`)**:
   Features use relative path literals with full `.nix` extensions. Plain paths are standard modules; parameterized modules must use an explicit wrapper.

   Example in `hosts/macair15-m2/meta.nix`:

   ```nix
   osFeatures = [
     ../../modules/os/feat/services/builders.nix
     {
       module = ../../modules/os/feat/services/tailscale.nix;
       args.authKey = "tailscale_preauth_key";
     }
   ];
   ```

   In [lib/systems.nix](file:///Users/lamt/lamt-nixconfig/lib/systems.nix):

   ```nix
   resolveFeatures =
     features:
     map (
       feature:
       if builtins.typeOf feature == "path" then
         feature
       else if builtins.isAttrs feature && feature ? module then
         import feature.module (feature.args or { })
       else
         throw "Invalid feature entry"
     ) features;
   ```

4. **Cleanup Library & Helper Functions**:
   - **Static Library Bootstrapping**: Remove the extensible fold (`makeExtensible`) and filesystem directory mapping (`readDir`) from [lib/default.nix](file:///Users/lamt/lamt-nixconfig/lib/default.nix), replacing it with static imports of library components (`loader`, `my`, `systems`). This eliminates disk I/O, prevents eager folding evaluation, and restores standard LSP autocomplete and Go-to-Definition references.
   - **Rename modules.nix**: Rename [lib/modules.nix](file:///Users/lamt/lamt-nixconfig/lib/modules.nix) to [lib/loader.nix](file:///Users/lamt/lamt-nixconfig/lib/loader.nix) as it acts as a generic directory/package importer rather than a NixOS module manager. Delete the unused `mapModules'` helper.
   - **Delete attrs.nix**: Inline `mapFilterAttrs` directly inside the new `loader.nix` and delete [lib/attrs.nix](file:///Users/lamt/lamt-nixconfig/lib/attrs.nix) completely, as all other functions (`attrsToList`, `genAttrs'`, `anyAttrs`, `countAttrs`) are dead code.
   - **Systems Builder Refactoring**: Keep deterministic `resolveFeatures`, `mkHost`, and `mkExtraUser` APIs without function-signature introspection.
   - **Optimize myargs**: Maintain the `myargs` special arguments pattern as it passes flat primitive values statically, bypassing options evaluation, and is highly performant.

### Tailscale Pre-Auth Key Automation

To prevent hosts from executing unnecessary secrets generation and setup for Tailscale if they don't require auto-connection:

1. **Module Defaulting**: The `tailscale.nix` module parameters are refactored so that `authKey` defaults to `null`.
2. **Explicit Declaration**: Only hosts that require automated connection need to explicitly define the feature arguments in their `meta.nix`:
   ```nix
   osFeatures = [
     {
       module = ../../modules/os/feat/services/tailscale.nix;
       args = {
         authKey = "tailscale_preauth_key";
       };
     }
   ];
   ```
3. **Rust Installer Verification & Provisioning**:
   - `installer-rs` queries the evaluated `features` list in `flake.deploymentHosts` metadata.
   - If a host explicitly specifies `authKey`, the tool checks if the specified secret key (e.g., `tailscale_preauth_key`) exists in the host's SOPS `.yaml` file.
   - If missing or expired, the installer automatically contacts the Headscale coordinator, requests a new 1-year reusable key, writes and encrypts it using `sops --set`, and restarts/stages the secrets before running the rebuild.

---

## 3. Implementation Checklist

- [x] **Step 1: Disable HTML/JSON Manuals**
  - [x] Set `documentation.enable = false;` in `modules/os/base/autorun/core.nix`.
  - [x] Set `manual.html.enable = false;` in `modules/hm/base/autorun/core.nix`.
- [x] **Step 2: Replace `${self}` references**
  - [x] Rewrite `${self}` references to relative paths in:
    - `modules/hm/base/git.nix`
    - `modules/hm/base/zsh.nix`
    - `modules/os/base/services/sops.nix`
    - `modules/os/base/_workstation.nix`
    - `modules/os/linux/desktop/i3.nix` / `sway.nix`
    - `modules/os/linux/services/backup.nix`
- [x] **Step 3: Makefile instant-start wrapper**
  - [x] Update `Makefile` with the `command -v lamd` check.
- [x] **Step 4: Benchmark Baseline Improvements**
  - [x] Run `time nix eval '.#darwinConfigurations.macair15-m2.system.drvPath'` and verify:
    - Baseline time is reduced.
    - `builtins.derivation` warning is gone.
- [x] **Step 5: Design A Core Migration**
  - [x] Create `flake/user-profiles.nix` with dynamic platform/role functions.
  - [x] Rewrite `lib/systems.nix` to load `coreModules` explicitly and drop `mapModulesRec'`.
  - [x] Rewrite `flake/hosts.nix` to process host features and resolve role inheritance.
- [x] **Step 6: Migrate Specific Modules to Parameterized Functions**
  - [x] Convert `modules/hm/base/editors/neovim.nix`
  - [x] Convert `modules/os/base/services/tailscale.nix`
  - [x] Convert other service/desktop modules as required.
- [x] **Step 7: Create Modular Package Feature Groups**
  - [x] Move and split package definitions in `profiles/lamt/default.nix` into granular `hm/base/profiles/lamt/sysadmin.nix`, `dev.nix`, and `cloud.nix` files.
- [x] **Step 8: Update Host `meta.nix` files**
  - [x] Populate feature arrays in active host metadata.
- [x] **Step 9: Final Verification**
  - [x] Run full build/switch tests on local system configuration.
- [x] **Step 10: Optimize Base Imports & Path Features**
  - [x] Convert `persist.nix` to use implicit activation and remove `persist.enable`.
  - [x] Create directory-level `default.nix` files for eager base modules.
  - [x] Migrate features to relative path literals with `.nix` extensions for Vim `gf` navigation.
  - [x] Implement initial path-based feature filtering; superseded by explicit `osFeatures` and `hmFeatures` in Step 17.
- [x] **Step 11: Tailscale Pre-Auth Key Provisioning Automation**
  - [x] Refactor `modules/os/base/services/tailscale.nix` to default `authKey` to `null`.
  - [x] Declare `authKey = "tailscale_preauth_key";` in host features for hosts requiring auto-connection (`medo`, `utils`, `air15vm`).
  - [x] Update `installer-rs` metadata parsing to read evaluated `features` and identify defined Tailscale configuration arguments.
  - [x] Implement dynamic Tailscale key check and automatic provisioning using `sops --set` and Headscale ssh generation.
- [x] **Step 12: Library Cleanup & Static Bootstrapping**
  - [x] Delete `lib/attrs.nix` and inline `mapFilterAttrs` inside the loader.
  - [x] Rename `lib/modules.nix` to `lib/loader.nix` and delete `mapModules'`.
  - [x] Rewrite `lib/default.nix` to statically import library components (`loader`, `my`, `systems`).
- [x] **Step 13: Systems Refactoring & myargs Validation**
  - [x] Centralize feature resolution; simplified to deterministic path/wrapper handling in Step 17.
  - [x] Retain `mkHost` and `mkExtraUser` in `lib/systems.nix`.
  - [x] Keep the optimized `myargs` special argument injection in `mkSpecialArgs`.
- [x] **Step 14: Restructure Modules Tree (Flat Shared + Platform Folders)**
  - [x] Rename `mapModules` -> `mapPackages` in `loader.nix` and its caller in `per-system.nix`.
  - [x] Move system feature modules under `modules/os/feat/` (grouped into `services/`, `desktop/` and platform subfolders `linux/`, `darwin/`).
  - [x] Move Home Manager feature modules under `modules/hm/feat/` (grouped into subfolders, and platform subfolder `linux/`).
  - [x] Nest base/eager modules under `base/linux/`, `base/darwin/`, and `base/wsl/` folders under both `modules/os/` and `modules/hm/`.
  - [x] Decouple `lib/systems.nix` from server/workstation defaults, moving `server.nix` and `workstation.nix` imports into `flake/host-roles.nix`.
  - [x] Remove `server` boolean argument from host builders inside `lib/systems.nix`.
  - [x] Update all path feature references in `hosts/*/meta.nix` and `flake/user-profiles.nix`.
- [x] **Step 15: Self-Contained User Profiles Refactoring**
  - [x] Relocate HM packages and package groups (`sysadmin.nix`, `dev.nix`, `cloud.nix`) under root-level `profiles/` directory.
  - [x] Merge HM profiles feature logic from `flake/user-profiles.nix` directly into respective self-contained profiles (e.g., `profiles/lamt/default.nix`, `profiles/vivi/default.nix`, `profiles/deploy/default.nix`, `profiles/nixos/default.nix`).
  - [x] Eliminate `flake/user-profiles.nix` registry entirely.
  - [x] Propagate system `role` and other context parameters (`hostname`, `darwin`, `wsl`) into Home Manager profiles via `myargs` special args.
  - [x] Update `lib/systems.nix` to load `../profiles/${username}` directly for the primary user.
- [x] **Step 16: Unified Profile Features Refactoring (Approach B)**
  - [x] Expose `resolveFeatures` in the `lib.my` namespace from `lib/systems.nix`.
  - [x] Merge profile feature declarations directly into `profiles/<username>/default.nix` using the `my.resolveFeatures` pattern.
  - [x] Remove temporary profile `meta.nix` files, returning to a clean, single-file design per user profile.
  - [x] Restore `home-modules` builder in `lib/systems.nix` to load `../profiles/${username}` directly without redundant external metadata loading.
- [x] **Step 17: Explicit Feature Contracts & Validation**
  - [x] Split host and role metadata into explicit `osFeatures` and `hmFeatures` lists.
  - [x] Replace feature scope/path heuristics and function-argument introspection with deterministic feature entries.
  - [x] Keep flattened `deploymentHosts.<host>.features` metadata for installer compatibility.
  - [x] Require valid roles for buildable hosts and reject legacy `features` metadata.
  - [x] Move host-specific Home Manager choices out of reusable profiles.
  - [x] Fix parameterized feature defaults that reference unavailable module arguments.
  - [x] Add focused evaluation assertions for critical host features.
- [x] **Step 18: Profile Feature Naming**
  - [x] Name reusable profile-owned feature lists `profileFeatures`.
  - [x] Reserve `hmFeatures` for host metadata additions.
  - [x] Keep `imports` as the standard Nix module wiring field.

---

## 4. Benchmark Results

### Evaluation Performance

- **Reference Host**: `macair15-m2` (Apple M2 MacBook Air)
- **Benchmark Command**:
  ```bash
  time nix eval '.#darwinConfigurations.macair15-m2.config.system.build.toplevel.drvPath'
  ```

| Metric                     | Historical Baseline                          | Historical Optimized          | Current Verification          |
| :------------------------- | :------------------------------------------- | :---------------------------- | :---------------------------- |
| **Evaluation Time (Mean)** | **4.57s**, n=3 (4.68s, 4.60s, 4.42s)         | **3.98s**, n=2 (4.03s, 3.92s) | **4.62s**, n=2 (4.67s, 4.56s) |
| **Maximum RSS**            | **~2.30 GiB** (raw measurement not retained) | **~1.10 GiB**                 | **~1.18 GiB**, n=2            |
| **Warnings**               | `builtins.derivation` (options.json)         | None for the reference host   | None for the reference host   |

The historical samples suggested a 13% timing improvement, but the current two-run verification does not reproduce that result. The current memory result remains close to the historical optimized measurement. Timing should be compared with more runs under explicitly documented cache and system-load conditions.

### Build Validation

- Local system configuration rebuild for `macair15-m2` completed successfully via `installer-rs` in **17 seconds**:
  ```bash
  nix run '.#installer-rs' -- switch -t macair15-m2 --action build
  ```
- **Nix Evaluation**: Verified every emitted NixOS, cross-NixOS, Darwin, and standalone Home Manager configuration.
- **Feature Contract Checks**: Verified `gaming` Minecraft assertions, `utils` development packages, `macair15-m2` Doom Emacs, and flattened installer feature metadata.
- **Rust Installer Tests**: Ran `cargo test` in `apps/installer-rs` successfully with all 68/68 unit tests passing.

---

## 5. Superseded Follow-Up Work

The former PR roadmap has been removed. Its persistent workspace proposal is replaced
by [New Features Coding Plan-Cache Workspace.md](./New%20Features%20Coding%20Plan-Cache%20Workspace.md),
which uses Git tree IDs directly and covers local, remote-builder, and cache lifecycle
behavior in one reviewed design.

---

## 6. Proxmox Provider Refactoring Plan

To address the growth of [proxmox.rs](file:///Users/lamt/lamt-nixconfig/apps/installer-rs/src/providers/proxmox.rs) (which has grown to 916 lines by mixing preflight checks, multiple VM creation flows, IP guest resolution, and guest script injection), we are implementing a flat refactoring plan similar to the `operation/deploy_*` module patterns.

### Refactored Sibling Files Structure

We are splitting the codebase under [src/providers/](file:///Users/lamt/lamt-nixconfig/apps/installer-rs/src/providers/) into:

- [proxmox.rs](file:///Users/lamt/lamt-nixconfig/apps/installer-rs/src/providers/proxmox.rs): Main entry point containing `ProxmoxProvider` definition and `VirtualizationProvider` trait implementation.
- [proxmox_preflight.rs](file:///Users/lamt/lamt-nixconfig/apps/installer-rs/src/providers/proxmox_preflight.rs): Bridge presence/bridge isolated state checking and proxy-jump VM status checks.
- [proxmox_create.rs](file:///Users/lamt/lamt-nixconfig/apps/installer-rs/src/providers/proxmox_create.rs): Modular VM creation strategies (PXE boot, NixOS ISO boot, and Cloud-Init templates).
- [proxmox_ip.rs](file:///Users/lamt/lamt-nixconfig/apps/installer-rs/src/providers/proxmox_ip.rs): Guest agent IP query, static IP script injection, ARP neighbor checking, and nmap subnet scanning.

### Reusable Patterns & Deduplication Goals

1. **Boilerplate SSH Execution**: Add `execute`, `execute_silent`, and `execute_with_log` helper methods on `ProxmoxProvider` to centralize formatting of `root@<pve_host>` SSH targets.
2. **Duplicate Network Options**: Deduplicate `--net1` and extra bridge interface generation by introducing an `extra_net_args()` helper method on `ProxmoxProvider`.
3. **Normalize Settings Defaults**: Consolidate VM size defaults (`cores`, `memory`, `disk_size`) during `ProxmoxProvider::new()` struct instantiation instead of evaluating them ad-hoc during provisioning.

### Progress Checklist

- [x] **Step 1: Create boilerplate execution helper on `ProxmoxProvider`**
- [x] **Step 2: Implement `src/providers/proxmox_preflight.rs`**
- [x] **Step 3: Implement `src/providers/proxmox_create.rs` (PXE, ISO, Cloud-Init)**
- [x] **Step 4: Implement `src/providers/proxmox_ip.rs` (IP resolution, scanning, and guest agent injection)**
- [x] **Step 5: Rewrite `src/providers/proxmox.rs` to delegate tasks and register sibling modules in `src/providers/mod.rs`**
- [x] **Step 6: Run verification and tests (`cargo test` under `apps/installer-rs`)**

---

## 7. Reusable Nix Cache Feature (Harmonia)

To share built Nix store paths from the `utils` remote builder to client hosts on the LAN or Tailnet, we implemented a lightweight, zero-copy binary cache feature.

### Implementation Details

- Module Path: [nix-cache.nix](file:///Users/lamt/lamt-nixconfig/modules/os/feat/linux/services/nix-cache.nix)
- Engine: [Harmonia](https://github.com/nix-community/harmonia), which serves `/nix/store` directly over HTTP.
- Key Parameters:
  - `domain`: Domain name to serve the cache on.
  - `port`: The port Harmonia listens on (default: `5000`).
  - `bindAddress`: Local/public address to bind (default: `127.0.0.1`).
  - `nginxProxy` / `caddyProxy`: Configures reverse proxying.
  - `signKeySecretName`: SOPS secret key for store path signatures.

### Target Setup

Active on the **[utils](file:///Users/lamt/lamt-nixconfig/hosts/utils/meta.nix)** host, binding publicly to `0.0.0.0:5000` to allow local LAN and Tailnet machines to fetch build outputs without duplicate storage caching.
