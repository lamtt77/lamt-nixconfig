# New Features Coding Plan - Nxd Convert

This document describes the plan to introduce a new top-level `nxd convert` command for in-place NixOS takeovers of arbitrary Linux systems, and the cleanup of deprecated `--convert-to` parameters from `nxd deploy`.

---

## 1. Feature Requirements

We want to simplify the conversion workflow by removing the `--convert-to` option from `nxd deploy` and introducing a dedicated, clean top-level `nxd convert` command.

### CLI Syntax
```bash
nxd convert --target <source> --to <destination-host>
# Or short-hand:
nxd convert -t abc@192.168.1.187 --to medo-test
```

### Expected Behaviors & Constraints
1. **Source Resolution**:
   - The `--target` (or `-t`) argument is exclusively treated as an ad-hoc connection spec (e.g. `abc@192.168.1.187`).
   - `nxd` does not require or query the inventory metadata for the source target. It parses the username (`abc`) and IP/host (`192.168.1.187`) dynamically to build an ephemeral source context.
2. **Takeover Isolation**:
   - Because it is a software takeover (using `kexec`), `nxd convert` will not attempt to manage VM provider lifecycles (no stopping, destroying, or recreating VMs). It will directly verify SSH reachability and launch the kexec NixOS installer.
3. **Deprecation/Cleanup**:
   - Remove `--convert-to` option from the `nxd deploy` command.
   - Clean up the hybrid context logic and deployment mode checks that were previously scattered across the deploy pipeline.
   - Prevent `flake.lock` archival for hosts with `buildSystem = false` (metadata-only/test VMs).

---

## 2. Technical Design

### Module Modifications & New Files

#### CLI Layer
- `apps/nxd/src/cli.rs`:
  - Add the `Convert` variant to `Commands`:
    ```rust
    Convert {
        #[arg(long, short)]
        target: String,

        #[arg(long)]
        to: String,
    }
    ```
  - Remove `convert_to` from `Commands::Deploy`.

#### Core Execution Layer
- `apps/nxd/src/main.rs`:
  - Wire `Commands::Convert` to call `command::convert::execute_convert(target, to, args.parallel).await`.
  - Include `Commands::Convert` in the list of commands that report total execution time (`show_duration`).
- `apps/nxd/src/command/convert.rs` (New File):
  - Implement `execute_convert(target: String, to: String, parallel: usize) -> Result<(), Box<dyn std::error::Error>>`.
  - Parse the source target specification as an ad-hoc/ephemeral target spec.
  - Resolve the target install context by loading the configuration of the destination host (`to`).
  - Merge connection details (IP, user) into the install context.
  - Trigger `run_deployment` with the resolved target context.

#### Context & Planning Layer
- `apps/nxd/src/context.rs`:
  - Add support for parsing raw `user@ip` host specs into ephemeral `RuntimeContext` instances.
  - Delete `resolve_install_context` completely since the conversion pipeline handles merging locally.
- `apps/nxd/src/workflow/deploy_mode.rs`:
  - Update `DeploymentMode` variants and `from_context` to cleanly support `CloudInitConvert` based on the command context.

---

## 3. Implementation Tasks Checklist

- [x] **Phase 1: Design & Scope**
  - [x] Detail the API and data structure modifications.
  - [x] Review against architecture guidelines (modular, reusable, no secrets in logs).
- [x] **Phase 2: CLI & Parser Implementation**
  - [x] Implement ad-hoc target parser for `user@host` specifications in `apps/nxd/src/planning/mod.rs` and `context.rs`.
  - [x] Add the `convert` subcommand to `cli.rs` and remove `--convert-to` from `deploy` arguments.
  - [x] Wire the matching arm in `main.rs`.
- [x] **Phase 3: Core Conversion Execution**
  - [x] Create `apps/nxd/src/command/convert.rs` to run the in-place conversion pipeline.
  - [x] Update `DeploymentMode::from_context` and the helper logic in `deploy_mode.rs`.
  - [x] Refactor `apps/nxd/src/workflow/deploy.rs` to clean up deprecated `CloudInitConvert` and `buildSystem` order bypasses.
- [x] **Phase 4: Testing & Verification**
  - [x] Add unit tests in `deploy_mode.rs` and `context.rs` to verify ad-hoc host parsing and install context resolution.
  - [x] Run formatter (`cargo fmt`) and check linter warnings (`cargo clippy`).

---

## 4. Verification & Testing Checklist

- [x] **Unit Tests**
  - [x] Run `cargo test` and ensure all tests pass.
- [ ] **Manual Verification**
  - [ ] Run `nix run '.#nxd' -- convert -t abc@my-existing-vm --to medo-test` to dry-run or verify command execution parameters.


## 5. Test Coverage

- Add unit test coverage for `HostSpec` and `RuntimeContext` parsing of raw connection strings.
- Add test coverage for `resolve_install_context` on ad-hoc target conversion.
