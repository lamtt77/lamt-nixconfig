# Neovim Picker and Workspace Migration Plan

This document tracks the approved migration from Telescope and the coupled
project/session stack to fzf-lua, auto-session, and independent repository
discovery.

---

## 1. Goals

- Replace Telescope completely with fzf-lua while retaining a polished floating
  picker with previews, borders, split/tab actions, and resume support.
- Replace `coffebar/neovim-project`, `Shatur/neovim-session-manager`, and the
  custom directory-session workaround with `rmagatti/auto-session`.
- Keep repository discovery independent from session persistence.
- Preserve or improve existing picker, DAP, Git, AI, and workspace workflows.
- Improve startup time and avoid loading picker code until a picker is used.
- Make `nvim .` restore the current directory session while direct file
  arguments remain session-independent.

## 2. Baseline

Measured before migration with `hyperfine --warmup 2 --runs 8`:

- `nvim --headless flake.nix +qa`: `96.6 ms +/- 3.1 ms`
- `nvim --headless . +qa`: `58.4 ms +/- 1.1 ms`

These are process-level headless measurements. Full interactive workspace
restoration is also verified separately because scheduled `VimEnter` work can
continue after Neovim reports core startup complete.

## 3. Design

### Picker Ownership

- `config/fzf.lua` owns fzf-lua appearance, picker defaults, actions, and keymaps.
- Use the fzf-lua Telescope profile as a visual baseline, with a responsive
  preview layout and filename-first path display.
- Keep project-root resolution and repository discovery in a small shared helper,
  not in the picker plugin specification.

### Repository Discovery

- Search explicit roots only:
  - `~/lamt-nixconfig`
  - `~/lab`
  - `~/work`
- Recognize normal Git repositories and worktrees.
- Avoid scanning the full home directory.
- Selecting a repository changes Neovim's global cwd. auto-session handles the
  save/clear/restore lifecycle through directory-change tracking.

### Session Ownership

- auto-session owns session naming, restore, save, deletion, and cwd transitions.
- Enable directory-argument restoration for `nvim .`.
- Do not restore a workspace for direct file arguments by default.
- Suppress session creation for home, root, and temporary directories.
- Close transient DAP, Neogit, quickfix, help, and health buffers before saving.
- Start without branch-specific sessions; add them only if a real workflow
  requires separate layouts per branch.

### Workspace Keymaps

- `<leader>ww`: discover and switch repositories.
- `<leader>wr`: search saved sessions.
- `<leader>ws`: save the current session.
- `<leader>wR`: restore the current directory session.
- `<leader>wd`: delete a session through the picker.
- `<leader>wa`: toggle automatic session handling.
- `<leader>wp`: purge orphaned sessions.

## 4. Implementation Checklist

- [x] Inventory Telescope and project/session integrations.
- [x] Record pre-migration startup baseline.
- [x] Add fzf-lua with floating Telescope-style UI.
- [x] Migrate file, grep, buffer, history, diagnostics, LSP, Git, and list pickers.
- [x] Add independent repository discovery and switching.
- [x] Add auto-session with cwd tracking and directory-argument handling.
- [x] Migrate workspace keymaps.
- [x] Replace Telescope DAP configuration picker.
- [x] Change Neogit integration from Telescope to fzf-lua.
- [x] Change Avante selector provider and remove Telescope dependency.
- [x] Remove Telescope, telescope-dap, neovim-project, and session-manager.
- [x] Update README, theme integration, clues, and lockfile.
- [x] Run Lua lint and formatting checks for touched files.
- [x] Verify all picker keymaps and plugin integrations headlessly where possible.
- [x] Verify two-launch `nvim .` session restoration.
- [x] Verify repository switching saves and restores independent sessions.
- [x] Record post-migration startup benchmarks and compare with baseline.

## 5. Verification Criteria

- No Telescope or old project/session plugin remains in plugin specs or lockfile.
- fzf-lua loads only when a picker or dependent integration is invoked.
- `nvim .`, open `flake.nix`, exit, and reopen restores `flake.nix`.
- `nvim flake.nix` does not unexpectedly restore another workspace.
- Repository selection changes cwd and restores that repository's session.
- DAP configuration selection runs the selected `nvim-dap` configuration.
- Neogit and Avante operate without Telescope installed.
- Touched Lua files pass Luacheck and `git diff --check`.
- Startup is no slower than baseline outside expected session restoration work.

## 6. Progress Log

- 2026-06-07: Approved architecture and keymap direction.
- 2026-06-07: Completed dependency inventory and recorded startup baseline.
- 2026-06-07: Implemented fzf-lua picker migration, independent repository
  discovery, auto-session workspace handling, and dependent plugin integrations.
- 2026-06-07: Reconciled the lockfile without upgrading unrelated plugins.
- 2026-06-07: Added pre/post restore MiniFiles cleanup after isolated testing
  found that its `winfixbuf` directory window could block or cover the restored
  workspace.
- 2026-06-07: Verified isolated `nvim .` restoration to `flake.nix`, direct-file
  startup without session restoration, and cwd switching to an independent lab
  repository session.
- 2026-06-07: Luacheck, focused StyLua checks, and `git diff --check` pass.
  fzf-lua remains unloaded at startup while auto-session is loaded for
  `VimEnter`/`DirChanged` handling.
- 2026-06-07: Post-migration benchmarks:
  - `nvim --headless flake.nix +qa`: `93.2 ms +/- 2.7 ms` (3.4 ms faster).
  - `nvim --headless . +qa`: `58.9 ms +/- 1.2 ms` (0.5 ms slower, within noise).
- 2026-06-07: Investigated slow interactive session switching. The synchronous
  auto-session save/restore path measured about 34 ms, but saved sessions
  included hidden buffers from other repositories and terminals, causing
  avoidable post-restore buffer, LSP, and plugin initialization.
- 2026-06-07: Restricted `sessionoptions` to visible workspace state and fixed
  repository discovery to strip `fd` directory separators before deriving the
  repository root, preventing sessions from being created under `.git`.
- 2026-06-07: Removed LSP shutdown from the session-switch critical path.
  Exact-session profiling showed both forced and graceful `nil_ls` shutdown
  blocked Neovim for roughly three seconds. Buffer replacement detaches the old
  client without making session restoration wait for its shutdown handshake.
- 2026-06-07: Exact save/restore phase timing found the remaining freeze in
  auto-session's `allowed_dirs` check: expanding `~/lab/**` and `~/work/**`
  recursively on every autosave took about 3.1 seconds. Replaced glob-based
  allow-listing with constant-time workspace-root prefix checks in `auto_create`
  and `pre_save_cmds`.
- 2026-06-07: Re-measured the formerly blocking autosave condition from the
  Mitchell `.git` cwd at `0.38 ms`, down from `3,124 ms`; restoring the lamt
  session itself measured about `20 ms`.
- 2026-06-07: Verified clean sessions contain only their visible repository
  buffer. The isolated synchronous switch measured `17.6 ms`, reduced from the
  observed `34-73 ms`, with the correct repository cwd and target buffer.
