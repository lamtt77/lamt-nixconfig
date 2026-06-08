# New Features Coding Plan

This document tracks the approved implementation plan for the next `installer-rs` feature work.

---

## 1. Feature Requirements

Move installer workspaces from temp directories to an explicit installer-owned cache, then use persistent Git clones from committed base workspaces instead of rsync fan-out for per-host workspaces.

- Store persistent installer workspaces under `${XDG_CACHE_HOME:-~/.cache}/installer-rs`, not `/tmp`.
- Treat cache directories as installer-owned derived state. Users should run manual workflows from real checkouts, not from cache paths.
- Keep source/base workspaces as committed Git snapshots so `git+file://...` Nix flakes continue to work.
- Use stable `source-id` values to isolate caches for different source trees or flake refs.
- Respect `--repo-src local|github|tea` when deriving source bases and `source-id` values.
- Use stable `builder-id` values to isolate remote-builder caches for different SSH builder identities.
- Use per-host Git clones from the base workspace instead of rsync from base to each host workspace.
- Keep each host workspace as an independent Git repository, not a linked `git worktree`.
- Inject only the target host's SOPS file into that host workspace, then commit only when the resulting tree changes.
- Preserve Nix evaluation cache behavior by preserving Git commit identity when the final workspace tree is unchanged.
- Preserve batch parallelism by keeping one independent local and remote workspace per host.
- Apply the same cache/clone model to remote builder workspaces.
- Sync local source base to an installer-owned remote builder cache base once per builder/source per run with incremental `rsync --delete`.
- Clone per-host remote builder workspaces from the remote builder cache base.
- Never use a user's real remote checkout, such as `~/lamt-nixconfig`, as the shared clone source.
- Add `lamd cache list`, `lamd cache prune`, `lamd cache clean`, and `lamd cache repair`.
- Detect and repair corruption for cache entries needed by the current run.
- Create cache directories with private permissions on Unix because host workspaces may contain injected SOPS files.

---

## 2. Technical Design

### Cache Layout

Use an installer-owned cache root:

```text
${XDG_CACHE_HOME:-~/.cache}/installer-rs/
  sources/
    <source-id>/
      base/

  hosts/
    <source-id>/
      <host>/

  builders/
    <builder-id>/
      <source-id>/
        base/
        hosts/
          <host>/
```

Do not use `/tmp/installer-rs-workspace-*` for persistent source, host, or remote-builder workspaces after this migration. `/tmp` remains acceptable only for genuinely short-lived scratch files.

### ID Rules

`source-id` identifies the logical source tree, not each commit.

- Local checkout source:
  - used when `--repo-src local`
  - derive from canonical repo path for `path:.`
  - format: `local-<readable-name>-<short-hash>`
  - example: `local-lamt-nixconfig-a13f09c2`
- GitHub flake source:
  - used when `--repo-src github`
  - derive from the resolved `github:<owner>/<repo>` flake ref
  - format: `github-<readable-name>-<short-hash>`
  - example: `github-lamt-lamt-nixconfig-8b71c9aa`
- Tea/Gitea flake source:
  - used when `--repo-src tea`
  - derive from the resolved `git+ssh://...` flake ref
  - format: `tea-<readable-name>-<short-hash>`
  - example: `tea-tea-lamhub-com-lamtt77-lamt-nixconfig-31a9c4e0`
- Custom flake source:
  - used when `NIX_REPO` or future repo-source plumbing provides an explicit flake ref outside `local`, `github`, or `tea`
  - derive from the full flake ref string
  - format: `flake-<readable-name>-<short-hash>`

`builder-id` identifies the SSH builder identity.

- Derive from SSH connection string.
- Format: `ssh-<readable-name>-<short-hash>`.
- Example: `deploy@utils` -> `ssh-deploy-utils-22a91d0c`.

The readable name keeps paths understandable; the short hash avoids collisions after sanitization.

### Metadata

Each Git-backed cache workspace stores a small marker file inside its Git metadata directory:

```text
.git/installer-rs-cache.json
```

Do not store cache metadata in the workspace root. Metadata writes such as `last_used` updates must never alter the Git worktree, Git index, flake tree hash, or Nix evaluation cache key.

Required fields:

- `kind`: `source-base`, `host`, `remote-builder-base`, or `remote-builder-host`
- `source_id`
- `builder_id` when applicable
- `host` when applicable
- `repo_src`: `local`, `github`, `tea`, or `custom`
- `flake_ref`
- `source_description`
- `last_used`

The marker is used for cache ownership checks, active workspace validation, `lamd cache list`, prune candidate selection, and repair decisions.

### Normal Refresh

Normal refresh is the expected per-run update path and should preserve commit identity when content is unchanged.

Local source base:

```text
resolved source from --repo-src local|github|tea
  -> cache/sources/<source-id>/base
  -> delete stale files as part of source refresh
  -> git init if needed
  -> git add -A
  -> commit only if content changed
  -> write marker
```

Source refresh rules:

- `--repo-src local`: snapshot the current checkout as today, using tracked-file snapshotting for Git checkouts and rsync-style excludes for plain local directories.
- `--repo-src github`: resolve to the configured GitHub flake ref, materialize with `nix flake archive --json`, then refresh the source base from the archived source path.
- `--repo-src tea`: resolve to the configured Tea/Gitea `git+ssh://...` flake ref, materialize with `nix flake archive --json`, then refresh the source base from the archived source path.
- Custom flake refs: treat as remote flake sources and materialize with `nix flake archive --json`.
- Host SOPS injection remains per-host and local to the prepared host workspace; remote flake source selection must not stage shared secrets into the source base.

Local host workspace:

```text
cache/sources/<source-id>/base
  -> cache/hosts/<source-id>/<host> using persistent Git clone
  -> reset/clean to base HEAD
  -> inject host SOPS file
  -> git add -A
  -> commit only if content changed
  -> write marker
  -> use git+file://cache/hosts/<source-id>/<host>
```

Remote builder base:

```text
local cache/sources/<source-id>/base
  -> rsync --delete once to remote cache builders/<builder-id>/<source-id>/base
  -> git init if needed on remote base
  -> git add -A
  -> commit only if content changed
  -> write marker
```

Remote builder source acquisition rules:

- The orchestrator always prepares the local source base first, regardless of `--repo-src`.
- `--repo-src local`: the local source base is a snapshot of the current checkout.
- `--repo-src github`: the local source base is materialized from `nix flake archive --json github:<owner>/<repo>`.
- `--repo-src tea`: the local source base is materialized from `nix flake archive --json git+ssh://...`.
- Remote builders do not fetch GitHub or Tea/Gitea directly in this feature. They receive the already-prepared local source base by incremental `rsync --delete`.
- This preserves the current correctness property: the remote builder builds exactly the source tree that the orchestrator planned.

Remote builder host workspace:

```text
remote cache builders/<builder-id>/<source-id>/base
  -> remote cache builders/<builder-id>/<source-id>/hosts/<host> using persistent Git clone
  -> reset/clean to remote base HEAD
  -> sync host secrets into remote host workspace
  -> git add -A
  -> commit only if content changed
  -> write marker
  -> build on remote builder from remote host workspace
```

### Corruption Detection And Recovery

Automatic recovery applies only to cache corruption for workspaces needed by the current run. It is not a general scan of the whole cache tree.

Treat a cache entry as corrupt when any of these checks fail:

- expected path is a file instead of a directory
- marker file is missing or has the wrong `kind`, `source_id`, `builder_id`, or `host`
- required `.git` directory is missing or invalid
- Git commands needed for refresh fail
- host workspace clone points at the wrong source/base
- permissions are unsafe or the path is unwritable

Recovery actions:

- Prefer reset/resync/clean when the Git repository is valid.
- Recreate only the affected cache entry when structure or metadata is invalid.
- Never delete paths outside `${XDG_CACHE_HOME:-~/.cache}/installer-rs`.
- A recreated cache entry may cause a one-time Nix evaluation cache miss; healthy unchanged cache entries should preserve commit identity.

### Cache Commands

Add a `lamd cache` command group:

```bash
lamd cache list
lamd cache prune
lamd cache clean
lamd cache repair
```

Command behavior:

- `list`: show cache root, workspace kind, source ID, builder ID, host, size, last-used time, and health.
- `prune`: remove unused cache entries by age and size policy; support `--dry-run`.
- `clean`: remove all installer cache entries after confirmation unless `--force`.
- `repair`: validate and repair cache entries; support `--dry-run`.

Default pruning rules:

- never prune locked or active workspaces
- prune entries older than a conservative default age, such as 30 days
- support a size limit option so the cache can be bounded explicitly

### Module Modifications & New Files

- `apps/installer-rs/src/workspace/cache.rs`
  - cache root resolution
  - private directory creation
  - source ID and builder ID generation
  - repo-source-aware source ID generation for `local`, `github`, `tea`, and custom flake refs
  - cache path rendering
  - marker metadata read/write
  - cache entry discovery, size, last-used, health, prune, clean, and repair helpers
- `apps/installer-rs/src/workspace/git.rs`
  - committed snapshot helpers
  - clone/refresh helpers
  - reset/clean helpers
  - commit-if-changed helper
  - local command rendering helpers for tests
- `apps/installer-rs/src/workspace/source.rs`
  - use cache source base path instead of `TempDirGuard::new("base")`
  - derive source base from `config::flake_uri()` / active repo source
  - prepare source base as a committed Git snapshot
  - prepare host context via clone refresh instead of `rsync_tree`
- `apps/installer-rs/src/workspace/remote.rs`
  - add remote cache path rendering and remote clone/refresh command helpers
  - replace remote builder per-host rsync preparation with remote clone refresh
  - sync local source base to remote cache base once per builder/source
- `apps/installer-rs/src/nix/build_remote_builder.rs`
  - use remote builder cache paths for base and host workspace
  - preserve builder sync locks and per-run synced-builder tracking
- `apps/installer-rs/src/nix/strategy.rs`
  - populate remote workspace paths from cache helpers
- `apps/installer-rs/src/workspace/local.rs`
  - remove temp-workspace ownership for persistent source/host workspaces
  - retain only reusable sanitization or scratch helpers that remain needed
- `apps/installer-rs/src/cli.rs`
  - add `cache` subcommand group
- `apps/installer-rs/src/command/cache.rs`
  - implement `list`, `prune`, `clean`, and `repair`
- `apps/installer-rs/src/command/mod.rs`
  - wire cache command module
- `apps/installer-rs/src/main.rs`
  - route cache commands
- `docs/Installer Rust Architecture and Implementation Plan.md`
  - update workspace/cache architecture after implementation
- `docs/Installer Requirements Specification.md`
  - add cache command requirements after implementation

---

## 3. Implementation Tasks Checklist

- [ ] **Phase 1: Cache Foundation**
  - [ ] Add `workspace/cache.rs`.
  - [ ] Resolve `${XDG_CACHE_HOME:-~/.cache}/installer-rs`.
  - [ ] Create cache directories with `0700` on Unix.
  - [ ] Add source ID generation for local paths and flake refs.
  - [ ] Ensure `source-id` differs for `--repo-src local`, `--repo-src github`, and `--repo-src tea`.
  - [ ] Add builder ID generation for SSH connections.
  - [ ] Add cache path rendering for local and remote workspaces.
  - [ ] Add marker metadata read/write.
  - [ ] Add unit tests for ID stability, hash suffixes, path rendering, and metadata serialization.

- [ ] **Phase 2: Git Workspace Helpers**
  - [ ] Add `workspace/git.rs`.
  - [ ] Replace always-commit snapshot behavior with `commit_if_changed`.
  - [ ] Add clone detection and invalid-workspace recovery.
  - [ ] Add persistent local clone refresh from a base workspace.
  - [ ] Add reset/clean helpers that preserve `.git`.
  - [ ] Add unit tests for command rendering and commit-if-changed behavior.

- [ ] **Phase 3: Local Cache Workspaces**
  - [ ] Move source base from `/tmp/installer-rs-workspace-base` to `cache/sources/<source-id>/base`.
  - [ ] Preserve current source snapshot behavior for Git checkouts, plain checkouts, and remote flake refs.
  - [ ] Respect `--repo-src local|github|tea` when preparing the source base.
  - [ ] Materialize GitHub and Tea/Gitea sources through `nix flake archive --json`.
  - [ ] Commit base only when content changes.
  - [ ] Move host workspaces from `/tmp/installer-rs-workspace-<host>` to `cache/hosts/<source-id>/<host>`.
  - [ ] Replace local base-to-host `rsync_tree` with persistent clone refresh.
  - [ ] Inject host SOPS file after clone refresh.
  - [ ] Commit host workspace only when content changes.
  - [ ] Preserve `git+file://<host-workspace>` flake refs.
  - [ ] Preserve batch parallelism and per-host isolation.
  - [ ] Update logging to show cache paths and source ID.

- [ ] **Phase 4: Remote Builder Cache Workspaces**
  - [ ] Render remote cache base as `~/.cache/installer-rs/builders/<builder-id>/<source-id>/base`.
  - [ ] Sync local source base to the remote cache base once per builder/source per run with incremental `rsync --delete`.
  - [ ] Preserve the current source flow for all repo sources: remote builder receives the orchestrator-prepared source base and does not fetch GitHub/Tea directly.
  - [ ] Ensure remote cache base is a committed Git snapshot.
  - [ ] Render remote host workspace as `~/.cache/installer-rs/builders/<builder-id>/<source-id>/hosts/<host>`.
  - [ ] Replace remote builder per-host rsync prep with remote clone refresh from remote cache base.
  - [ ] Sync local host secrets into the remote host workspace after clone refresh.
  - [ ] Commit remote host workspace only when content changes.
  - [ ] Build from the remote host workspace as today.
  - [ ] Preserve existing builder sync locks and synced-builder tracking.
  - [ ] Stop using real user checkouts as installer-managed remote builder bases.

- [ ] **Phase 5: Corruption Recovery**
  - [ ] Validate marker metadata before using a cache entry.
  - [ ] Validate required Git repositories before refresh.
  - [ ] Recover invalid source bases by recreating only the affected source-base cache entry.
  - [ ] Recover invalid host workspaces by recreating only the affected host cache entry.
  - [ ] Recover invalid remote builder bases by resyncing/recreating only the affected remote base.
  - [ ] Recover invalid remote builder host workspaces by recreating only the affected remote host workspace.
  - [ ] Ensure recovery never deletes outside the installer cache root.
  - [ ] Log recovery actions clearly without printing secrets.

- [ ] **Phase 6: Cache CLI**
  - [ ] Add `lamd cache list`.
  - [ ] Add `lamd cache prune` with `--dry-run`.
  - [ ] Add `lamd cache clean`.
  - [ ] Add `lamd cache repair` with `--dry-run`.
  - [ ] Require confirmation for destructive cache clean/repair operations unless `--force`.
  - [ ] Avoid pruning locked or active workspaces.
  - [ ] Report cache entry health in `list` and `repair`.

- [ ] **Phase 7: Cleanup And Docs**
  - [ ] Remove persistent workspace path assumptions based on `/tmp`.
  - [ ] Keep `/tmp` only for true scratch files if any remain.
  - [ ] Update installer architecture docs.
  - [ ] Update requirements docs.
  - [ ] Run formatter, tests, clippy, and diff whitespace checks.

---

## 4. Verification & Testing Checklist

- [ ] `cargo fmt --check`
- [ ] `cargo test`
- [ ] `cargo clippy --all-targets -- -D warnings`
- [ ] `git diff --check`
- [ ] `lamd cache list`
- [ ] `lamd cache prune --dry-run`
- [ ] `lamd cache repair --dry-run`
- [ ] `lamd deploy --hosts <host> --plan`
- [ ] `lamd deploy --hosts <host> --plan --repo-src local`
- [ ] `lamd deploy --hosts <host> --plan --repo-src github`
- [ ] `lamd deploy --hosts <host> --plan --repo-src tea`
- [ ] Single-host deploy or switch uses cache host workspace.
- [ ] Batch deploy or switch creates isolated host cache workspaces.
- [ ] Remote builder deploy syncs remote cache base once and builds from remote host cache workspaces.
- [ ] Remote builder deploy with `--repo-src github` builds from the orchestrator-prepared source base synced to the builder.
- [ ] Remote builder deploy with `--repo-src tea` builds from the orchestrator-prepared source base synced to the builder.
- [ ] Re-running an unchanged deploy/switch preserves workspace commit identity.
- [ ] Corrupting an active cache marker triggers automatic recovery for that workspace only.

## 5. Test Coverage

Add focused tests for:

- cache root resolution with and without `XDG_CACHE_HOME`
- private cache directory creation
- `source-id` stability for the same local path or flake ref
- `source-id` difference for different paths or flake refs
- `source-id` difference across `local`, `github`, and `tea` repo sources
- source base path selection from active repo source
- remote builder source acquisition always uses local-source-base rsync for `local`, `github`, and `tea`
- `builder-id` stability and collision resistance after sanitization
- local cache path rendering
- remote builder cache path rendering
- marker metadata serialization and validation
- clone/refresh command rendering
- remote clone/refresh command rendering
- commit-if-changed behavior
- corruption detection for wrong kind/source/builder/host metadata
- corruption recovery candidate selection
- cache list entry rendering
- cache prune candidate selection
