# Refactoring Plan: `installer-rs`

> **Goal:** Clean, non-duplicated, human-readable, pluggable Rust that avoids
> hard-coded values and leverages `config.rs` / `defines.nix` correctly.

## Status Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Done |
| 🔲 | Pending |

---

## Progress Tracker

| Priority | Item | Status |
|----------|------|--------|
| HIGH | SSH opts unified (`SSH_BASE_OPTS`, `SSH_LONG_OPTS`, `SSH_PIPE_OPTS`) | 🔲 |
| HIGH | `execute_ssh_forwarded()` — `-A` only on builder path | 🔲 |
| HIGH | `check_ssh_alive()` — replaces 3 inline probe blocks | 🔲 |
| HIGH | `Display` impl for `BuildStrategy` | 🔲 |
| HIGH | `sync_repo_to_ssh()` helper — replaces 4 tar pipe duplicates | 🔲 |
| HIGH | `clear_known_hosts()` helper | 🔲 |
| HIGH | Deduplicate stdout/stderr threads in `process.rs` | 🔲 |
| MEDIUM | `REPO_TAR_EXCLUDES` constant + all call sites | 🔲 |
| MEDIUM | SSH timeout constants (`SSH_TIMEOUT_WORK`, `SSH_TIMEOUT_PROBE`) | 🔲 |
| MEDIUM | Numeric constants (ZRAM, swap, timers, dirs, Proxmox defaults) | 🔲 |
| MEDIUM | Fix `/Users/lamt/lamt-secrets` hardcode in `config.rs` | 🔲 |
| MEDIUM | `is_low_mem()` accessor on `DeploymentConfig` | 🔲 |
| MEDIUM | `print_host_plan()` helper in `main.rs` | 🔲 |
| MEDIUM | Provider name dedup (`describe_provider()`) | 🔲 |
| MEDIUM | Extract generic `run_batch<F>` in `batch.rs` | 🔲 |
| LOW | Wire remaining constants into callers (`pipeline.rs`, `switch.rs`, `batch.rs`, `proxmox.rs`) | 🔲 |
| LOW | Split `main.rs` into `commands/` subdirectory | 🔲 |
| LOW | `CliOverrides` struct instead of env var coupling (`main.rs` → `context.rs`) | 🔲 |
| LOW | Batch `defines.nix` reads in `config.rs` (single JSON eval) | 🔲 |
| LOW | Custom `InstallerError` enum (`thiserror` crate) | 🔲 |

---

## 1. Critical Duplications

### 1.1 SSH Options ✅

The same SSH option block (`-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
-o LogLevel=ERROR …`) was repeated verbatim in 5+ files.

**Fix:** Extract from `process.rs` and export:
- `SSH_BASE_OPTS: &[&str]` — the 4 universal options
- `SSH_LONG_OPTS: &[&str]` — ConnectTimeout + ServerAlive keepalives
- `SSH_PIPE_OPTS: &str` — inline string form for bash pipe commands
- `execute_ssh()` — without `-A`
- `execute_ssh_forwarded()` — with `-A`, used **only** on builder path
  (`nix.rs` `RemoteBuilder` build + copy commands)
- `check_ssh_alive(target)` — replaces inline probe blocks in `switch.rs` and `pipeline.rs`

---

### 1.2 `repo_tar_pipe` ✅

The `tar … | ssh … "rm -rf … && tar -xzf …"` pattern was in 4 places.

**Fix:** Add `CommandExecutor::sync_repo_to_ssh(dest, remote_dir, log_target)` to `process.rs`.
All 4 call sites in `nix.rs` (×2), `switch.rs`, `main.rs` reduce to a single function call each.

---

### 1.3 `BuildStrategy` Display Name ✅

The strategy → string match arm was copy-pasted 4 times across `main.rs` and `pipeline.rs`.

**Fix:** Implement `Display` for `BuildStrategy` in `nix.rs`.
All call sites then use `format!("{}", strategy)` — no match arms at call sites.

---

### 1.4 Provider Name Resolution — Duplicated in `main.rs` 🔲

The `if !ctx.deployment.proxmox.host.is_empty() { "Proxmox VM" } …` block
appears twice in `main.rs` (deploy plan, switch plan).

**Fix:** `fn describe_provider(ctx: &RuntimeContext) -> &'static str` free
function in `main.rs` or `providers/mod.rs`.

---

### 1.5 Plan/Summary Display 🔲

Deploy plan block and switch plan block in `main.rs` produce near-identical
tabular output.

**Fix:** `fn print_host_plan(ctx, strategy, extra_fields: &[(&str, &str)])` helper.

---

### 1.6 `batch::deploy_batch` vs `batch::switch_batch` 🔲

Both share an identical skeleton (log dir, spawn loop, collect handles, elapsed time).

**Fix:** Generic `run_batch<F>(hosts, task_fn: F)` where
`F: Fn(RuntimeContext, Arc<Mutex<LogTarget>>) -> Result<(), String> + Send + 'static`.

---

### 1.7 `ssh-keygen -R` — `clear_known_hosts` 🔲

`ssh-keygen -R <ip>` + `ssh-keygen -R <hostname>` is triplicated across
`pipeline.rs` (×2) and `switch.rs`.

**Fix:** `CommandExecutor::clear_known_hosts(ip, hostname)` already added to
`process.rs` — remaining callers in `pipeline.rs` and `switch.rs` still use
the old inline form and need updating.

---

### 1.8 `wait_for_ssh` vs Inline SSH Checks ✅

`switch.rs` had two inline one-shot SSH probe blocks duplicating `ssh` command
construction.

**Fix:** Add `fn check_ssh_alive(target_ssh: &str) -> bool` to `process.rs` using
the unified `SSH_BASE_OPTS` + `SSH_TIMEOUT_PROBE`. Replace the two inline probe
blocks in `switch.rs` (L77-92, L135-147) with calls to this helper.

---

## 2. Hard-coded Values

### 2.1 `config.rs` ✅ (mostly)

| Item | Status |
|------|--------|
| `get_secrets_repo()` `/Users/lamt/lamt-secrets` hardcode | 🔲 Fix — use `HOME`-relative fallback |
| `DEFAULT_VMW_ISO_DIR` macOS-only literal `/Users/lamt/…` | 🔲 Fix — remove user-specific prefix |
| `eval_defines()` — 4 separate `nix eval` subprocess calls | 🔲 Batch into one JSON read |
| `ssh_auth_key()` fallback public key literal in code | Acceptable as last-resort fallback |

---

### 2.2 Values Hard-coded Outside `config.rs`

| Location | Hard-coded Value | Constant to Add | Wired? |
|----------|-----------------|-----------------|--------|
| `pipeline.rs` | `nameserver 1.1.1.1` | `config::FALLBACK_DNS` | 🔲 |
| `pipeline.rs` | `3221225472` (3 GB ZRAM) | `config::ZRAM_SWAP_SIZE_BYTES` | 🔲 |
| `pipeline.rs` | `3G` swapfile | `config::SWAP_FILE_SIZE` | 🔲 |
| `pipeline.rs` | `15` sec kexec wait | `config::KEXEC_BOOT_WAIT_SECS` | 🔲 |
| `switch.rs` | `60` sec rollback | `config::ROLLBACK_TIMEOUT_SECS` | 🔲 |
| `batch.rs` | `"_tmp"` log dir | `config::BATCH_LOG_DIR` | 🔲 |
| `proxmox.rs` | `"50"` GB, `"4"` cores, `"4096"` MB | `config::DEFAULT_PVE_*` | 🔲 |
| `nix.rs`, `switch.rs`, `main.rs` | tar excludes string (×4) | `config::REPO_TAR_EXCLUDES` | 🔲 |

> **Note:** All constants should be defined in `config.rs` and then wired into
> their respective call sites across `pipeline.rs`, `switch.rs`, `batch.rs`, `proxmox.rs`.

---

## 3. Structural & Architectural Improvements

### 3.1 `main.rs` Too Large (624 lines) 🔲

`main.rs` mixes module declarations, `resolve_provider()`, all command dispatch,
planning output, dialoguer prompts, and IP resolution.

**Proposed split:**

```
src/
  main.rs          # tokio::main + module decls + CLI parse + dispatch (~50 lines)
  resolve.rs       # resolve_provider() + describe_provider()
  display.rs       # print_host_plan(), format_duration()
  commands/
    deploy.rs      # handle_deploy()
    switch.rs      # handle_switch()  (rename current switch.rs → exec/switch.rs)
    sync.rs        # handle_sync()
```

---

### 3.2 `context.rs` Env Var Coupling 🔲

`context.rs` reads `BUILDER` and `LOW_MEM` from env. CLI flags are set as env
vars in `main.rs` before calling `RuntimeContext::load()` — a hidden contract.

**Fix:**

```rust
pub struct CliOverrides {
    pub builder:  Option<String>,
    pub low_mem:  Option<String>,
    pub build_on: Option<String>,
}
// RuntimeContext::load(hostname, overrides: CliOverrides)
```

---

### 3.3 `process.rs` — Stdout/Stderr Thread Duplication 🔲

`execute()` and `execute_with_stdin()` differ only in stdin setup but the
43-line I/O-streaming thread block is copy-pasted verbatim twice.

**Fix:** Extract private
`fn stream_output(stdout, stderr, log_target) -> (String, String)`.

---

### 3.4 `nix.rs` — `NixBuilder::resolve()` ~115-line Conditional 🔲

Hard to read; impossible to unit-test without `nix` installed.

**Fix:** Split into two pure functions:
- `resolve_active_builder(deployment_builder, cli_override) -> String`
- `resolve_strategy(params: StrategyParams) -> BuildStrategy`

---

### 3.5 `context.rs` — Stringly-Typed Booleans 🔲

`ctx.deployment.low_mem == "yes"` is spread across 5+ files.

**Fix:**

```rust
impl DeploymentConfig {
    pub fn is_low_mem(&self) -> bool { self.low_mem == "yes" }
}
```

No Nix schema change required.

---

### 3.6 Custom `InstallerError` Enum 🔲 (Low priority)

Every function returns `Box<dyn std::error::Error>`, preventing structured
error matching.

**Fix:** `thiserror`-derived `InstallerError` enum with variants
`SshFailed`, `NixEvalFailed`, `ProviderError`, etc.

---

## 4. `defines.nix` Redundancy Audit

| `defines.nix` key | Read by `config.rs`? | Notes |
|-------------------|---------------------|-------|
| `myRepoName` | ✅ via `nix_cfg()` | Correct |
| `githubUser` | ✅ via `github_user()` | Correct |
| `teaURL` | ✅ via `tea_url()` | Correct |
| `mySshAuthKey` | ✅ via `ssh_auth_key()` | Correct |
| `defaultUsername` | ❌ | Correct — comes from flake eval via `context.rs` |
| `hosts.pve1 / pve2` | ❌ | Correct — comes from `deployment.proxmox.host` |
| `nixBuilderPubkey` | ❌ | Gap: pre-wire via `config.rs` if builder SSH validation is added |
| `networking.*` | ❌ | Correct — IPs from `deployment.targetIp` |
| `timeZone`, `stateVersion` | ❌ | Correct — NixOS module-only values |
| `gpgDefaultKey`, `gpgSshKey` | ❌ | Correct — `gpg.rs` reads from `HOME/.gnupg` |

**Assessment:** No redundancy. The `defines.nix` / `config.rs` split is architecturally sound.

---

## 5. What is Already Well-Designed — Do NOT Change

- `IdentityService` trait — clean, pluggable, correct pre/post hook order
- `VirtualizationProvider` trait — minimal, focused, correct 3-method interface
- `OnceLock` caching in `config.rs` for `defines.nix` values
- Single-batch `nix eval --json` in `context.rs` (avoids N separate evals)
- `LogTarget` enum + `Arc<Mutex<>>` for transparent batch/foreground switching
- `BUILDER_LOCKS` / `LOCAL_NIX_LOCK` per-builder mutex — prevents concurrent `nix build` races
- `synced_to_builder: Mutex<bool>` dedup flag — prevents double-sync to builder
- `check_builder_compatible()` SSH probe before committing to a builder strategy
- Kexec idempotency check via live-OS filesystem type detection
- `--plan` dry-run output before any destructive action
- `dialoguer::Confirm` prompts guarding destructive paths (deploy, redeploy)
