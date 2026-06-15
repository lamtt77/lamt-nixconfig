# Store-Backed Source Coding Plan

This document defines the implementation plan for replacing persistent `installer-rs`
workspaces with immutable Nix store inputs. The design prioritizes a small runtime path,
stable Nix inputs, batch parallelism, and avoiding repeated remote filesystem work.

## Decision Status

**Selected design:** split store-backed source and encrypted-secret inputs.

**Implementation readiness:** approved for coding.

**Rejected alternative:** persistent Git cache workspaces. The historical design is
archived in
[Rejected Design-Git Cache Workspaces.md](./archive/Rejected%20Design-Git%20Cache%20Workspaces.md).
It is not a fallback and must not be implemented.

Implementation proceeds only with the store-backed phases in this document.

The remaining cold/warm, batch, and strategy checks are implementation acceptance
tests. They are not unresolved architecture decisions.

---

## 1. Current Versus Proposed Workspaces

### Current implementation

The current implementation already keeps nominally temporary workspaces between runs,
but their lifecycle and identity are implicit:

- the source base and host workspaces live under
  `${TMPDIR:-/tmp}/installer-rs-workspace-*`;
- every run cleans and repopulates the source base;
- every local host preparation cleans its workspace and rsyncs the complete base tree;
- every remote builder host preparation rsyncs the complete remote base worktree;
- remote builder base reuse is tracked only in process memory, so a new `lamd`
  invocation synchronizes it again;
- Git commits are reused when a retained worktree is unchanged, but this is an
  incidental property of the existing directories;
- no cross-process lock prevents two `lamd` processes from mutating the same base or
  host workspace;
- workspace names do not isolate different local checkouts or repo sources;
- permissions, ownership validation, pruning, and corruption recovery are undefined;
- target-native builds retain a separate remote `/tmp` workspace flow.

Current strengths:

- the implementation is small;
- per-host directories preserve batch parallelism;
- Git-backed `git+file://` flakes are known to work;
- source and host-secret preparation behavior is already established.

Current costs and risks:

- repeated whole-tree cleanup, scanning, and copying;
- repeated network rsync after restarting `lamd`;
- possible corruption from concurrent processes;
- collisions across source checkouts;
- persistent sensitive derived state under a temporary-directory namespace;
- multiple workspace algorithms for local, remote-builder, and target-native builds.

### Rejected mutable-cache alternative

A persistent Git-cache design was reviewed and rejected because it would preserve
mutable local and remote workspaces while adding cache IDs, metadata, locks, repair,
pruning, and administration commands. The archived document records that analysis; it
is outside this implementation scope.

---

## 2. Selected Design: Split Store-Backed Inputs

Use the Nix store as the content-addressed snapshot and transport layer.

### Design

1. Prepare one common source tree locally using the existing tracked-file snapshot
   rules, without injecting host SOPS files.
2. Add the common source tree to the Nix store with a fixed name using
   `nix store add`.
3. Add each selected host's encrypted SOPS file as a separate small store path.
4. Group the SOPS module and its existing dummy file under
   `modules/os/base/services/sops/`, then declare one relative non-flake
   `installer-secret` input whose locked default points at that SOPS-specific
   directory:

   ```nix
   installer-secret = {
     url = "path:./modules/os/base/services/sops";
     flake = false;
   };
   ```

   The directory contains `default.nix` and the existing `dummy-secrets.yaml`
   fallback, but intentionally contains no `<hostname>.yaml` or unrelated service modules.
5. Build each host from the common `path:<source-store-path>` flake while overriding
   that input:

   ```text
   nix build \
     path:<source-store-path>#<target> \
     --override-input installer-secret path:<host-secret-store-path>
   ```

6. Update the SOPS base module to use
   `inputs.installer-secret + "/${myargs.hostname}.yaml"` instead of requiring the encrypted file to
   exist inside the common flake source.
7. For a remote builder or target-native build, batch-transfer the common source and
   all selected encrypted secret store paths in one command:

   ```text
   nix copy --to <store-uri> <source-store-path> <secret-store-path>...
   ```

8. Build hosts in parallel from the same immutable common source path, each with its
   own secret input override.

### Input contract

The `installer-secret` input is:

- declared with `flake = false`;
- when real, a generated store directory containing exactly one encrypted file named
  `<hostname>.yaml` and no files for any other host;
- locked by default to `modules/os/base/services/sops` for manual evaluation without
  installer staging;
- overridden by installer commands for hosts with a resolved SOPS source;
- never used to carry decrypted data or unrelated secrets.

The input must be declared because flake outputs need an explicit
`inputs.installer-secret` value and the installer needs a stable input name for
`--override-input`. Omitting the declaration would require an impure value, generated
wrapper flake, or mutation of the common source, all of which are more complex.

Keep the default relative to the flake root. The lock file records it as a relative
child input rather than an absolute path to one developer's checkout. Use the
SOPS-specific module directory rather than the general-purpose `services` directory:
this prevents `maintenance.nix` and future unrelated services from becoming incidental
members of the secret-input contract.

Do not add a top-level empty-secret placeholder. That would be a technically pure input
boundary, but it would duplicate the fallback concept and introduce a directory whose
only purpose is satisfying the lock file. Grouping the existing SOPS module and dummy
file provides the narrow boundary without another artifact. The module's fallback
still refers directly to `./dummy-secrets.yaml`; the locked input is only the
no-`<hostname>.yaml` input value.

This relative input also works for GitHub and Tea/Gitea repository sources. Nix resolves
the locked child path relative to the fetched parent flake source, not relative to the
machine invoking `lamd`. An isolated Git archive test evaluated the resulting
`path:<archived-source-store-path>` successfully with both the checked-in default and a
runtime `--override-input installer-secret` value. The SOPS directory and the updated
`flake.lock` must therefore be committed and present in every remote revision selected
by `--flake`.

The SOPS module reads only `inputs.installer-secret + "/${myargs.hostname}.yaml"`. The host name is
not part of the input directory schema because the installer has already selected the
correct encrypted file for that host.

When no real host secret is available, the installer leaves the input at its locked
default. `builtins.pathExists (inputs.installer-secret + "/${myargs.hostname}.yaml")` remains false,
so `modules/os/base/services/sops/default.nix` continues to use the existing
`./dummy-secrets.yaml` and activation warning. Do not add or duplicate another dummy
SOPS file, and do not override the input with an empty generated directory.

Secret isolation is per input path and per build:

- each `secret_store_path` contains one host's encrypted `<hostname>.yaml` only;
- the host-to-secret-path mapping is immutable after preparation;
- each build command receives only the override belonging to its target host;
- a build must never receive another host's secret path, even when several hosts build
  concurrently;
- tests must inspect the rendered command and secret directory contents for this
  invariant.

During a batch, the builder's global Nix store may contain separate encrypted secret
paths for several selected hosts because all paths are batch-copied once. This does not
merge or expose them to each build: each flake evaluation references only its selected
single-host input path. Requiring the entire builder store to contain only one host's
encrypted file would conflict with parallel batch builds and Nix store semantics.

An isolated store-backed flake test confirmed that the non-flake override resolves
`<hostname>.yaml` from the supplied secret store path. Nix emits its standard
`not writing modified lock file` warning because the runtime override differs from the
locked default input; `--no-write-lock-file`, `--no-update-lock-file`, and `--quiet` do
not suppress it in the current Nix version. Treat this exact warning as expected
installer behavior and keep it out of normal user-facing output while preserving it in
debug logs.

The warning is a multi-line block, not one standalone line. Apply a command-specific
stderr filter only to Nix evaluation/build commands rendered with
`--override-input installer-secret`:

- buffer a candidate block beginning with
  `warning: not writing modified lock file of flake `;
- continue buffering subsequent bullet and indented continuation lines until EOF or
  the first unrelated, non-indented diagnostic line;
- suppress it only when the buffered block contains an input-change line naming
  exactly `installer-secret`;
- do not depend on a fixed line count or on `-`, `+`, or arrow markers because these
  details vary across Nix versions;
- impose a defensive limit of 32 lines or 16 KiB and flush the block unchanged if the
  limit is exceeded;
- write every suppressed line to debug logging;
- if the expected block shape does not match, flush all buffered lines to normal
  output;
- retain the original stderr in command failure diagnostics.

Do not put an unconditional substring discard in the generic logging layer, and do not
suppress any other Nix warning.

### Secret staging contract

For each distinct resolved host SOPS file, create a unique private temporary directory:

```text
${TMPDIR:-/tmp}/installer-rs-secret-<run-id>/
```

The directory:

- is created with an RAII temporary-directory API and mode `0700` on Unix;
- contains exactly one regular file named `<hostname>.yaml`;
- copies only the already-encrypted selected host SOPS file and never decrypted data;
- uses mode `0600` for the staged file on Unix;
- is added with `nix store add --name installer-secret`;
- is removed immediately after insertion, including error and unwind paths;
- does not include the hostname in the temporary or store-path name;
- is never reused as a cache or shared by concurrent operations.

Validate that the source is the resolved regular encrypted SOPS file before copying.
Keep the host-to-resulting-store-path association in `PreparedSourceSet`; directory
contents and names must not be used to rediscover the target host.

The resulting encrypted store object is immutable but normally readable to local Nix
store users. This is consistent with the existing encrypted-SOPS model, but it is why
plaintext, private keys, and decrypted secret material must never enter this flow.

### Source preparation contract

Replace the custom `--repo-src` selector with one global flake-reference option:

```text
lamd --flake <flake-ref> <command> ...
```

`--flake` is not a universal global option implemented by every `nix` subcommand, but
it is the established interface used by tools such as `nixos-rebuild` and Home Manager.
Its value follows the standard Nix flake-reference syntax instead of installer-specific
source names.

Examples:

```text
lamd --flake . switch -t air15vm --action build
lamd --flake github switch -t air15vm --action build
lamd --flake tea deploy --hosts air15vm
lamd --flake 'git+https://example/repo?ref=review-branch' deploy --hosts air15vm --plan
```

When omitted, discover the nearest parent `flake.nix` from the current directory, as
the installer does for `local` today. Log the resulting canonical flake reference in
debug mode. Do not retain the old source-type model: `local` is represented by omitted
`--flake` or a local flake reference, while `github` and `tea` are only narrow
convenience expansions into real flake references.

The option identifies the source flake only. Continue selecting hosts with `-t` or
`--hosts`; reject a `#<output>` fragment in `--flake` rather than creating two competing
ways to select the target.

Provide the old `github` and `tea` convenience names in two consistent layers:

1. `lamd --flake github|tea` expands through a small built-in resolver backed by
   predefined `config.rs` constants, so it works during first bootstrap and on
   unmanaged machines.
2. Managed systems also expose matching declarative system flake-registry entries, so
   the same short references work with normal Nix commands.

The built-in mappings are:

```text
github -> github:<configured-owner>/<configured-repository>
tea    -> git+ssh://git@<configured-gitea-host>/<configured-owner>/<configured-repository>
```

Keep the owner, repository, Gitea host, and SSH user as centralized constants/defaults
in `config.rs`; do not reconstruct these URLs in command handlers. The resolver accepts
only these two convenience names and otherwise preserves the supplied standard flake
reference unchanged.

Declare matching system registry entries:

```nix
nix.registry = {
  github.to = {
    type = "github";
    owner = mydefs.githubUser;
    repo = mydefs.myRepoName;
  };

  tea.to = {
    type = "git";
    url = "ssh://git@${mydefs.teaURL}/${mydefs.githubUser}/${mydefs.myRepoName}";
  };
};
```

Use `ssh://` in this structured registry `url`. With `type = "git"`, the registry entry
already identifies the Git fetcher, so `ssh://` is the canonical transport URL.
Continue using `git+ssh://` for the built-in resolver's serialized flake reference.
These forms identify the same source in their structured and string contexts.

Place these entries with the existing base registry configuration so they are
available on both managed NixOS and nix-darwin hosts. Do not add Makefile aliases,
which would only work from a checkout and would create a third source-selection layer.

Explicit references remain supported and are preferred when a script must make the
source independent of local constants or registry configuration:

```text
lamd --flake github:<owner>/<repo> ...
lamd --flake 'git+ssh://git@<gitea-host>/<owner>/<repo>' ...
```

Prefer explicit references in portable scripts because registry entries can differ
between machines.

Resolve the active flake source once per operation:

- local Git flake reference such as `.`, `path:<checkout>`, or
  `git+file://<checkout>`:
  - fail when `git ls-files --deleted` reports missing tracked files;
  - archive `git+file://<canonical-checkout>` with `nix flake archive --json`;
  - use the returned top-level source store path directly.
- local non-Git path flake: construct an exact snapshot using the current explicit
  excludes, then add it with `nix store add`.
- any non-local flake reference, including `github:`, `git+ssh:`, `git+https:`, and
  `tarball+https:`: materialize it with `nix flake archive --json`.

Classify local handling from the resolved flake reference and canonical filesystem
path, not from a second source-type enum or string. Local-only behavior such as dirty
tracked-file capture and repository lock-file checks must use this classification.

The resulting common source must not contain `secrets/`, installer-generated metadata,
or a nested workspace Git repository. Add it to the store under one stable name so
unchanged content produces the same store path.

For Git checkouts and remote sources, reuse the immutable top-level source path returned
by `nix flake archive --json`. Do not copy that store path into a staging directory and
add it to the store again.

An isolated test confirmed that `git+file://` archive behavior matches the required
local source semantics:

- tracked working-tree edits were included;
- untracked files were excluded;
- `.git` was excluded.

This is preferable to `path:<checkout>`, which included `.git` and untracked files in
the same test.

Only plain non-Git local directories require a short-lived staging directory because
the installer must construct an exact filtered snapshot before `nix store add`.

Use a unique private path such as:

```text
${TMPDIR:-/tmp}/installer-rs-source-<run-id>/
```

This directory:

- contains only the common source snapshot, never host SOPS files;
- is mode `0700` on Unix;
- is unique per operation, so concurrent commands do not share mutable state;
- is removed after `nix store add` succeeds or when the operation exits;
- is not reused as a cache and is never transferred to a builder or target.

Git checkouts and remote archived sources do not need this staging directory.

### Comparison With Current Source Preparation

The current common source workspace is persistent, but refresh is not delta-only:

1. Retain its `.git` directory.
2. Delete every other top-level entry with `clean_workspace_except_git`.
3. Copy every tracked file back with `git ls-files` plus rsync.
4. Stage the complete result and conditionally commit it.

Therefore, a tiny edit currently still reconstructs the full common worktree locally.
The later builder rsync can transfer only the changed file, but local common-source
preparation is a full delete-and-copy cycle.

For the selected design's normal day-to-day Git-checkout workflow:

```text
git+file:// checkout
  -> nix flake archive
  -> immutable source store path
```

There is no new common-source directory and no local full-tree rsync managed by
`installer-rs`. Nix performs the tracked Git source snapshot directly. The temporary
directory described above is only the fallback for plain non-Git source directories.

### Per-run source set

Create one immutable `PreparedSourceSet` shared by all host contexts in the operation:

- `source_store_path`;
- one `secret_store_path` per distinct resolved encrypted host SOPS file;
- the selected flake-source description;
- rendered local and remote flake targets.

Prepare it once before parallel host builds. Copy the common source and all secret paths
needed by hosts assigned to the same builder in one `nix copy`. After that copy
completes, host builds may run in parallel and must not mutate shared source state.

For commands started directly on a builder, add source and secret paths to that
builder's local store and skip network source transfer.

### Lifetime and garbage collection

Store paths need no persistent installer cache or custom pruning policy, but they must
be protected from concurrent garbage collection while an operation is using them:

- create unique per-run indirect GC-root links for the common source and selected
  secret paths on the orchestrator;
- after copying to a remote builder or target, create equivalent unique per-run
  indirect roots there before starting parallel builds;
- remove local and remote roots in normal cleanup after all dependent builds finish;
- use run-specific root names so concurrent `lamd` processes never replace each
  other's roots;
- clean stale installer run roots by age at startup without deleting store paths
  directly;
- if a path is garbage-collected between invocations, recreate it from source content;
- do not create permanent GC roots for prepared source or secret paths;
- treat a missing path before roots are established as a recoverable preparation
  failure and retry preparation once.

Installer-owned root links live in user-writable state, not directly under
`/nix/var/nix/gcroots`:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/installer-rs/gcroots/<run-id>/
  source
  secret-<sanitized-hostname>
```

Use `secret-<sanitized-hostname>` rather than a sequential index. Hostnames are already
non-secret deployment identifiers, and readable names make manual inspection and
troubleshooting easier. Apply the existing safe-component sanitizer and reject
duplicate sanitized names within one run rather than replacing a root link.

Create each link with:

```text
nix-store --realise <store-path> --add-root <link> --indirect
```

Nix then registers the indirect root through its daemon-managed GC-root machinery. Do
not manually create entries under `/nix/var/nix/gcroots`, which would require
unnecessary privilege and would make ownership and stale cleanup harder. This exact
command shape was validated against the current Nix installation.

For a remote builder or target, run the same command over SSH as the account that owns
the installer operation, using that account's `XDG_STATE_HOME` or home-directory
fallback on the remote machine. Create the remote run directory after `nix copy`
returns and before any dependent build starts. If GC wins the short interval between
copy and root creation, repeat the copy once and retry root creation.

Store a non-secret run marker beside the root links for age-based stale cleanup. Use a
seven-day stale threshold. Normal completion still removes roots immediately; seven
days applies only to crash recovery and avoids disrupting unusually long or
temporarily disconnected operations. Retention cost is low because these roots protect
only source and small encrypted-secret inputs.

Cleanup removes only installer-owned run directories older than seven days and their
links; it never invokes store-path deletion. Do not use `TMPDIR` for roots because
crash remnants there are unreliable across reboots and system cleanup.

Nix store paths already provide:

- deterministic identity for common source and host-secret content;
- deduplicated transfer and destination-side existence checks;
- concurrency control through the Nix daemon;
- immutable source snapshots;
- garbage collection and integrity verification;
- identical source identity for local, remote-builder, and target-native builds.

The repository currently has no dependency on `self.rev`, `self.shortRev`,
`self.dirtyRev`, or equivalent Git-only flake metadata. That makes a `path:` store
flake feasible, subject to integration testing.

### Simplification potential

The selected design removes:

- remote builder base and host workspace directories;
- remote Git initialization, clone refresh, snapshot commits, and metadata;
- remote workspace locks;
- tree-ID comparison over SSH;
- rsync-based source transfer to builders and targets;
- remote cache list, prune, clean, and repair behavior;
- source and builder fingerprint metadata beyond the local staging cache.

Only plain non-Git local sources need short-lived common-source staging. Give each such
operation a unique staging directory so concurrent processes never share mutable source
state; no cross-process workspace lock is required. Git checkouts and remote sources
archive directly to an immutable store path. The remote side becomes normal Nix store
transport rather than a second workspace cache implementation.

For the uncommon plain-directory case, staging will normally reside under the process
`TMPDIR` on macOS; on systems without that variable it falls back to `/tmp`.
Temporary-directory use is retained only as a filtering implementation detail, not as a
persistent workspace or evaluation cache.

### Performance tradeoffs

Likely improvements:

- unchanged common-source transfer becomes a cheap Nix store existence check;
- common source bytes are transferred once per distinct source content and builder,
  not once per host;
- host-specific transfer is limited to each encrypted SOPS input;
- all selected paths can be checked and copied through one Nix store connection;
- no remote checkout or Git command sequence is required;
- local and remote builds use exactly the same immutable source path;
- batch hosts remain parallel because input overrides are per build command.

Possible regressions:

- `nix store add` must hash and serialize the common source tree;
- NAR transfer operates at store-path granularity, so a small common-source change may
  transfer the complete source path rather than rsync deltas;
- source paths are subject to Nix garbage collection and may need to be recreated;
- command rendering and flake behavior must change from `git+file://` to `path:`;
- direct SSH stores disable SSH compression by default;
- the flake and SOPS module gain one explicit installer-secret input contract.

For this repository, the source tree is expected to be small compared with built system
closures. Removing remote workspace orchestration may be worth more than rsync's
fine-grained delta transfer, but this must be measured rather than assumed.

### Security constraint

Only encrypted SOPS files may enter the secret input. Never add decrypted secrets,
private keys, generated credentials, or installer runtime key material to the Nix
store. The current Nix modules already copy the encrypted host SOPS file into a source
tree that Nix imports into the store, so the split input does not introduce a new
plaintext-secret model.

### Quick benchmark

Measured on June 12, 2026 from `macair15-m2` to the configured `deploy@utils` builder.
The snapshot used the current tracked working tree, including current documentation
edits but excluding build artifacts and untracked files.

Snapshot characteristics:

- 388 files;
- 1,419,297 bytes of file content;
- 1,519,160-byte raw NAR;
- 276,968-byte XZ NAR when written to a file binary cache.

Local command timings, 12 runs:

| Operation | Mean |
| :--- | ---: |
| rsync cold copy | 103.8 ms |
| rsync unchanged scan | 44.2 ms |
| rsync after tiny documentation edit | 44.0 ms |
| `nix copy` cold to file cache | 303.9 ms |
| `nix copy` unchanged to file cache | 75.7 ms |
| `nix copy` changed path to file cache | 306.6 ms |

Observed local `nix store add` timings were 0.25 seconds for the first insertion,
0.08 seconds for unchanged content already present, and 0.19 seconds after the tiny
edit. These timings remain relevant to plain-directory staging.

After selecting direct Git archive preparation, the 388-file dirty tracked checkout was
also measured over 12 runs:

| Operation | Mean |
| :--- | ---: |
| `nix flake archive --json git+file://<checkout>` | 128.4 ms |

This direct archive includes tracked edits without creating or repopulating an
installer-managed common-source directory.

Actual Mac-to-builder timings:

| Operation | Time | Sent or copied |
| :--- | ---: | ---: |
| rsync cold | 0.77 s | 1,476,442 bytes |
| rsync unchanged | 0.45 s | 29,061 bytes |
| rsync after tiny edit | 0.45 s | 29,931 bytes |
| `nix copy` cold | 0.76 s | one 1,519,160-byte raw NAR |
| `nix copy` unchanged | 0.53 s | zero paths |
| `nix copy` after tiny edit | 0.75 s | one 1,519,192-byte raw NAR |

A single follow-up changed-path sample with
`ssh://deploy@utils?compress=true` completed in 0.67 seconds. The corresponding
uncompressed samples ranged from 0.75 to 1.02 seconds, so SSH compression appears
useful but needs repeated measurement before becoming a default.

The transfer-only table does not include the workspace work performed before and after
the current rsync. A second benchmark reproduced those installer phases for one host
after a tiny source edit:

| Workspace phase | Mean or observed time |
| :--- | ---: |
| Rebuild and commit local common base | 0.276 s |
| Rebuild and commit local host workspace | 0.227 s |
| Current builder-base rsync including `.git` | 0.64 s |
| Optimized builder-base rsync excluding `.git` | 0.45 s |
| Remote host rsync, secret sync, and Git snapshot | 1.311 s |
| **Current implementation total** | **about 2.45 s** |
| **Optimized rsync total excluding `.git`** | **about 2.26 s** |

The current implementation's generic remote sync copies the local base `.git`
directory. That is not the intended optimized baseline. The fair rsync comparison
excludes `.git` from the builder-base transfer and keeps Git only in the final remote
host workspace.

The corresponding split-store samples were:

| Split-store phase | Observed time |
| :--- | ---: |
| Archive changed Git source directly to the store | 0.128 s |
| Add synthetic 8 KiB encrypted-secret-sized input | 0.07 s |
| Batch-copy both paths with SSH compression | 0.73 s |
| **Split-store pre-build total** | **about 0.93 s** |

Fresh uncompressed two-path batch copies varied between 0.88 and 1.20 seconds, with one
2.42-second outlier. The unchanged two-path batch check took 0.48 seconds and copied
zero paths. More end-to-end samples must be collected at the review gate, but the
representative compressed result is already materially below the current workspace
orchestration cost.

Interpretation:

- cold transfer performance was effectively equal;
- viewed only as transport, a tiny source edit cost about 0.30 seconds more with
  full-NAR `nix copy`;
- unchanged `nix copy` cost about 0.08 seconds more;
- viewed as complete single-host pre-build workspace preparation, the split-store
  sample was about 1.33 seconds faster than the optimized rsync baseline because it
  removed both local and remote host workspace reconstruction;
- these differences are small relative to the observed 20-second-plus remote build;
- the original per-host full-source store design would multiply NAR transfer by host
  count and is therefore rejected;
- the split-input design transfers the full source at most once per source change and
  builder, then transfers only small encrypted secret inputs per host;
- batching all selected store paths into one `nix copy` avoids one SSH connection per
  host;
- operations started directly on the builder require no source network transfer and
  pay only local source hashing/store insertion before evaluation.

The current batch implementation prepares different hosts concurrently, so the
per-host current costs must not be multiplied directly to predict batch wall time.
Batch wall-clock behavior remains a required review-gate measurement.

The benchmark paths added to the builder store are unrooted and may be reclaimed by
normal Nix garbage collection. The disposable remote rsync directory was removed.

### Acceptance criteria

- `path:<store-path>` evaluates all required NixOS, Darwin, and Home Manager outputs.
- Two unchanged preparations return the same common source path, secret path, and
  system `.drvPath`.
- A changed host SOPS file changes only that host's secret input and system output.
- A remote builder receives the common source and selected secrets through one
  `nix copy` and builds without a remote mutable workspace.
- An unchanged second remote build copies zero source or secret paths.
- Target-native builds use the same source-store path flow.
- Batch host preparation and builds remain parallel.
- No required Git revision metadata is missing.
- Debug output does not expose secret contents or sensitive command arguments.
- End-to-end single-host and batch warm-run time improves on the optimized current
  workspace baseline or any regression is explicitly reviewed.

---

## 3. Implementation Phases

### Phase 1: Store-backed source foundation (Complete)

- Replace global `--repo-src` with `--flake <flake-ref>` and remove the `NIX_REPO`
  source-name translation.
- Add a narrow `github`/`tea` convenience resolver backed by centralized `config.rs`
  constants; pass every other `--flake` value through unchanged.
- Add declarative system registry entries named `github` and `tea` in the existing base
  registry module, matching the built-in resolver values.
- Preserve nearest-parent local flake discovery only as the omitted-option default.
- Derive local-versus-remote behavior from the resolved flake reference.
- Remove the obsolete source-selection implementation completely:
  - remove `Cli.repo_src` and add `Cli.flake: Option<String>`;
  - remove `RuntimeOptions.repo_src` and replace consumers with the resolved typed
    flake-source value;
  - stop setting and reading `NIX_REPO`;
  - stop reading `FLAKE_SOURCE`; explicit `--flake` supersedes it;
  - replace `flake_uri()` with one flake-reference resolver that handles omitted local
    discovery, the two explicit convenience names, and standard references;
  - remove runtime evaluation of `defines.nix` used only for old source selection;
    bootstrap alias values come from centralized `config.rs` constants;
  - update lock-file checks to use resolved local-source classification instead of
    `repo_src == "local"`;
  - remove old source-selector tests rather than keeping compatibility branches.
- Do not retain a deprecated `--repo-src` flag or environment-variable fallback.
- Add direct `git+file://` archive preparation for local Git checkouts.
- Retain deterministic temporary staging plus `nix store add` only for plain local
  directories.
- Move `services/sops.nix` and `services/dummy-secrets.yaml` into the focused
  `services/sops/` module directory and update its import.
- Add a non-flake `installer-secret` input defaulting to
  `path:./modules/os/base/services/sops`.
- Add each selected encrypted host SOPS file to the store separately.
- Stage each encrypted host file through a unique private RAII temporary directory
  containing only `<hostname>.yaml`, and remove it immediately after store insertion.
- Add per-run local and remote indirect GC-root management under the operation user's
  state directory.
- Introduce the immutable per-run `PreparedSourceSet`.
- Add focused tests for deterministic source and secret store paths, flake-source
  classification, missing tracked files, and dummy-secret fallback.

### Phase 2: Build strategy migration (Complete)

- Render local and remote builds from `path:<source-store-path>` with a per-host
  `--override-input installer-secret`.
- Batch-transfer the common source and selected secret paths once per builder.
- Use the same source-set contract for local, remote-builder, target-native, and
  instantiated build strategies.
- Preserve host build parallelism after source transfer.

### Phase 3: Workspace removal (Complete)

- Remove persistent source, local-host, remote-builder-host, and target-native
  workspaces.
- Remove obsolete `TempDirGuard`, workspace Git snapshot, rsync, remote workspace path,
  and legacy `/tmp` cleanup logic.
- Retain only short-lived staging for plain-directory common sources and single-host
  encrypted secret inputs before `nix store add`.
- Update logging around source store paths, secret input selection, and batch copy.

### Phase 4: Review gate

- Run all acceptance and verification cases.
- Record single-host and batch cold/warm timings.
- Confirm source and secret input behavior for local, GitHub, and Tea/Gitea flake
  references.
- Continue to documentation cleanup when the gate passes.
- Stop for a new design review if the store-backed architecture fails a required
  correctness or performance gate. Do not automatically implement the archived Git
  cache.

### Phase 5: Documentation

- Audit and update every related document under `docs/`, not only the primary
  architecture and requirements documents.
- Update `README.md`, command examples, option references, bootstrap instructions, and
  generated/help-facing documentation.
- Document the source-input contract, encrypted-secret override, batching, and GC
  behavior.
- Replace all `--repo-src`, `NIX_REPO`, and `FLAKE_SOURCE` references with the new
  `--flake` contract and document the built-in `github`/`tea` convenience names.
- Remove obsolete cache-workspace and `/tmp` lifecycle documentation.
- Run a final repository-wide documentation search so no completed-design text still
  describes persistent workspaces or the removed source selector.

---

## 4. Expected File Changes

Store-backed implementation:

- `flake.nix`
- `flake.lock`
- `modules/os/base/default.nix`
- `modules/os/base/nixpath-registry.nix`
- `modules/os/base/services/sops/default.nix` (moved from `services/sops.nix`)
- `modules/os/base/services/sops/dummy-secrets.yaml` (moved from
  `services/dummy-secrets.yaml`)
- `apps/installer-rs/Cargo.toml`
- `apps/installer-rs/Cargo.lock`
- `apps/installer-rs/src/workspace/source.rs`
- `apps/installer-rs/src/workspace/mod.rs`
- `apps/installer-rs/src/cli.rs`
- `apps/installer-rs/src/config.rs`
- `apps/installer-rs/src/main.rs`
- `apps/installer-rs/src/context.rs`
- `apps/installer-rs/src/operation/plan_workspace.rs`
- `apps/installer-rs/src/operation/lockfile.rs`
- `apps/installer-rs/src/nix/build_commands.rs`
- `apps/installer-rs/src/nix/build_local.rs`
- `apps/installer-rs/src/nix/build_remote_builder.rs`
- `apps/installer-rs/src/nix/build_target_native.rs`
- `apps/installer-rs/src/nix/build_target_instantiated.rs`
- `apps/installer-rs/src/nix/strategy.rs`
- `apps/installer-rs/src/nix/mod.rs`
- `apps/installer-rs/src/workspace/remote.rs`
- `apps/installer-rs/src/workspace/local.rs`
- `docs/Installer Rust Architecture and Implementation Plan.md`
- `docs/Installer Requirements Specification.md`
- `docs/New Features Coding Plan-Installer2 Features.md`
- `README.md`

Avoid adding cache-management abstractions. The selected design relies on Nix store
identity, transfer, locking, integrity, and garbage collection.

---

## 5. Verification

### Automated

- [x] `cargo fmt --check`
- [x] `cargo test`
- [x] `cargo clippy --all-targets -- -D warnings`
- [x] `git diff --check`
- [x] Store-backed review-gate results are recorded.

Store-backed path:

- [x] Unchanged common source and host SOPS content produce the same store paths.
- [x] Local Git source preparation includes tracked dirty edits and excludes `.git`
  and untracked files without creating an installer staging directory.
- [x] `--flake` accepts local paths and standard remote flake references without a
  separate repo-source selector.
- [x] `lamd --flake github` and `lamd --flake tea` resolve from built-in constants
  before bootstrap or registry provisioning.
- [x] Managed NixOS and nix-darwin hosts resolve the `github` and `tea` registry aliases
  to the same repository URLs as the built-in resolver.
- [x] Explicit GitHub and Tea/Gitea references pass through unchanged.
- [x] Omitting `--flake` discovers the nearest parent flake, while an explicit value is
  preserved as the user's selected reference.
- [x] Local-only behavior is derived from canonical source classification rather than
  from the old `repo_src` source-type field; classification occurs after convenience
  expansion.
- [x] The Rust source and user documentation contain no `repo_src`, `--repo-src`,
  `NIX_REPO`, or `FLAKE_SOURCE` compatibility path.
- [x] All related files under `docs/` and `README.md` describe the implemented
  `--flake` behavior and no longer describe the removed workspace/source-selector
  architecture.
- [x] One immutable source set is prepared per operation and shared safely.
- [x] Concurrent host builds remain parallel with different secret overrides.
- [x] An unchanged remote batch copy transfers no source or secret paths.
- [x] Local, remote-builder, and target-native builds use the same immutable source and
  secret inputs.
- [x] A source edit transfers one common source NAR per builder, not one per host.
- [x] A secret edit transfers only that host's encrypted secret input.
- [x] Every generated secret input directory contains exactly one target host's
  encrypted regular file named `<hostname>.yaml`, has private staging permissions, and
  contains no other host files.
- [x] Secret staging directories are unique, omit hostnames, and are removed after
  successful insertion and on failure.
- [x] Every rendered build command maps the target host to only its own secret input
  path.
- [x] Missing host secrets use the locked default input and existing
  `dummy-secrets.yaml`, retaining the activation warning.
- [x] The complete expected runtime input-override lock-warning block is filtered only
  for commands overriding `installer-secret`, remains available in debug logs, and is
  retained in failure diagnostics.
- [x] Per-run local and remote GC roots protect all source inputs until dependent builds
  finish.
- [x] Root links live under each operation user's installer state directory; installer
  code never writes directly under `/nix/var/nix/gcroots`.
- [x] Secret root links use sanitized hostnames, reject collisions, and remain
  independent across concurrent run directories.
- [x] Concurrent operations use independent roots and cannot unroot each other's paths.
- [x] Stale run-root cleanup removes only installer-owned run directories older than
  seven days and never deletes store paths directly.
- [x] Garbage-collected prepared paths are recreated cleanly on the next invocation.

### Integration

- [x] `lamd --flake <local-or-remote-ref> deploy --hosts <host> --plan` for local,
  GitHub, and Tea/Gitea flake references.
- [x] Batch host preparation and builds remain parallel.
- [x] Two unchanged `--action build` runs produce the same source identity and system `.drvPath`.
- [x] Local, remote-builder, target-native, and instantiated strategies build from the
  same source-input contract.
- [x] No persistent `/tmp/installer-rs-workspace-*` directory is required.
- [x] Plain-directory source staging uses a unique private temporary directory,
  contains no host secrets, and is removed after source insertion or failure cleanup.
