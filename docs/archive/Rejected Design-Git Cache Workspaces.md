# Rejected Design: Git Cache Workspaces

## Status

**Archived on June 12, 2026. Do not implement.**

This design was considered as a replacement for the current persistent
`/tmp/installer-rs-workspace-*` behavior. It is retained only as historical context. It
is not a fallback and must not be added alongside the selected store-backed source
design.

The selected implementation is
[Store-Backed Source Coding Plan](../New%20Features%20Coding%20Plan-Cache%20Workspace.md).

---

## Former Design

The rejected design would have created installer-owned persistent Git repositories:

```text
${XDG_CACHE_HOME:-~/.cache}/installer-rs/
  sources/
    <source-id>/
      base/
      hosts/<host>/
      locks/

  builders/
    <builder-id>/
      sources/<source-id>/
        base/
        hosts/<host>/
        locks/
```

It included:

- stable source and builder IDs;
- marker metadata under `.git/installer-rs-cache.json`;
- cross-process locks for every mutable cache entry;
- committed source-base snapshots;
- persistent per-host Git clones;
- candidate-tree comparison to preserve unchanged host commits;
- remote tree-ID checks before incremental rsync;
- remote builder base and host repositories;
- corruption detection, quarantine, repair, and recreation;
- private permissions and symlink-safe deletion;
- age and size pruning;
- `lamd cache list`, `prune`, `clean`, and `repair`.

Local host refresh would reset a persistent clone to the source-base commit, inject the
selected encrypted SOPS file, calculate the staged tree, and reuse the previous host
commit when the final tree matched.

Remote builders would maintain another committed source base and persistent host
clones. The installer would compare Git tree IDs, rsync changed worktrees while
excluding `.git`, commit the remote base, inject each host secret, and build from a
remote `git+file://` workspace.

---

## Why It Was Rejected

The design improved the current workspace implementation but retained the same
fundamental architecture: mutable installer-managed source trees on the orchestrator,
builders, and targets.

Compared with split store-backed inputs, it required:

- more mutable states and failure modes;
- local and remote Git orchestration;
- rsync and tree-ID protocols;
- cross-process local and remote locks;
- cache metadata schemas and migrations;
- corruption repair and custom pruning;
- separate local, remote-builder, and target-native workspace behavior.

The selected design delegates content identity, transfer deduplication, locking,
integrity, and garbage collection to Nix. Benchmarking also showed better complete
pre-build time for the representative tiny-edit workflow.

No code should be added for this archived design. If the selected architecture fails a
future acceptance gate, stop for a new design review rather than implementing this
archive automatically.
