# Agent Guidelines for lamt-nixconfig

## Build/Lint/Test Commands

- **Build system**: `nxd build -t <host>`, `nix run '.#nxd' -- build -t <host>`, or `make build ARGS="-t <host>"`
- **Test system**: `nxd test -t <host>`, `nix run '.#nxd' -- test -t <host>`, or `make test ARGS="-t <host>"`
- **Switch/apply**: `nxd switch -t <host>`, `nix run '.#nxd' -- switch -t <host>`, or `make switch ARGS="-t <host>"`; `make switch` defaults to the current host
- **Bypass skip-activation**: `nxd` skips activation if target is already running the built configuration. To force reactivation (e.g. to test service restarts), pass `-F` or `--force` (e.g., `nxd switch -t <host> -F`).
- **Deploy plan**: `nxd deploy --hosts <host> --plan`, `nix run '.#nxd' -- deploy --hosts <host> --plan`, or `make deploy ARGS="--hosts <host> --plan"`
- **Direct NixOS rebuilds**: Do not use `nixos-rebuild` or bare `nix build '.#nixosConfigurations...'` for deployment validation when secrets are involved; they bypass installer workspace preparation and host secret staging
- **Format**: `make fmt` or `nix fmt`
- **Lint shell**: `nix develop '.#lint'` provides actionlint, luacheck, stylua, statix, alejandra, yamllint, cargo, clippy, rustc, and rustfmt; run the relevant tool for the touched area
- **Rust installer tests**: `cd apps/nxd && cargo fmt && cargo test`; use `cargo test <name>` for a focused Rust test

## Code Style Guidelines

- **Formatting**: Follow .editorconfig (2 spaces for Nix, tabs for Makefile, LF endings, UTF-8, trim whitespace), config/formatting.lua rules
- **Nix**: Functional programming, descriptive names, modular structure, no imperative code
- **Lua**: Neovim best practices, clear variable names, proper error handling
- **Imports**: Group by type (stdlib, external, local); sort alphabetically within groups
- **Naming**: camelCase for variables/functions, PascalCase for modules/types, kebab-case for files
- **Error handling**: Use proper assertions, avoid silent failures, log meaningful messages
- **Documentation**: Comprehensive comments for complex logic, docstrings for public functions
- **Security**: Never commit secrets, use proper permission management, validate inputs
- **Size and complexity**: Avoid oversized files and long functions; split code when responsibilities, workflows, or test surfaces become hard to understand at a glance
- **Constants and defaults**: Avoid hard-coded values when they represent project policy, reusable defaults, paths, hosts, roles, timeouts, or command options; centralize them in typed config, shared helpers, or `defines.nix` as appropriate
- **Duplication**: Regularly look for repeated command construction, option lists, shell snippets, validation logic, and workflow branches; abstract repeated mechanics behind small reusable helpers while keeping domain-specific behavior readable

## Your Role

You are an expert NixOS, Rust and Neovim/Emacs configuration specialist with deep knowledge of:

- Nix package manager and NixOS system configuration
- Rust DevOps nxd
- Neovim plugin ecosystem and Lua configuration
- Emacs elisp and its plugins ecosystem
- Home Manager for user environment management
- Git workflows and version control best practices

## Your Mission

Help maintain and improve this NixOS configuration system by:

- Writing clean, maintainable Nix expressions
- Optimizing Neovim plugin configurations
- Ensuring system stability and reproducibility
- Following NixOS and Neovim best practices
- Providing clear documentation and comments

## Architecture Guidelines

- Keep configurations modular, reusable, and pluggable so features can be extended or reused without rewriting unrelated workflows
- Separate host-specific from generic configurations
- Use overlays for package customizations
- Maintain clear separation between system and user configurations
- Ensure configurations are idempotent and declarative
- Prefer small modules with clear ownership over large files that mix parsing, planning, execution, logging, and provider-specific behavior
- Design shared Rust and Nix APIs around explicit data structures instead of ad hoc strings, environment-variable plumbing, or copy-pasted defaults
- Prefer declarative over imperative configurations; test changes on minimal hosts first
- Host inventory and deployment metadata live in `hosts/<name>/meta.nix`; keep metadata cheap to evaluate and use `buildSystem = false` for metadata-only targets
- `meta.nix` may import constants such as `../../defines.nix`, but must not import host modules, nixpkgs, overlays, or evaluated system configs
- `deploymentHosts` is the fast path for installer planning; keep its schema aligned with `apps/nxd/src/context.rs` and `modules/shared/options.nix`
- The targeted unstable overlay intentionally overrides selected stable package names from `nixpkgs-unstable`; do not reintroduce a broad dynamic `pkgs.unstable` overlay

## Working Practice

- Read the relevant module, host, or app code before changing it; prefer existing patterns over new abstractions
- Keep changes scoped to the requested behavior and avoid unrelated refactors
- Preserve user or generated work in the tree; do not revert unrelated changes without explicit instruction
- When changing code or adding features, look for refactoring opportunities first: remove duplicated mechanics or logic, simplify the existing shape, and fit the change into shared abstractions before adding new branches or one-off helpers
- Run focused verification for the touched area when practical, and report any command that could not be run
- When adding documentation or plans, keep claims tied to verified behavior or clearly mark them as assumptions
- For flake host changes, verify both `deploymentHosts.<host>` metadata and the relevant full system output when `buildSystem` is true
- For installer changes, run `cargo fmt` and `cargo test` in `apps/nxd`; use `-d/--debug` to inspect exact `nix copy` commands when checking copy/substitution behavior
- Local and remote installer workspaces are persistent cache directories refreshed between runs; do not assume they are deleted on drop

## Security Considerations

- Avoid storing secrets in configuration files
- Never commit, print, quote, or write private keys to logs, command output, documentation, or generated files; redact key material if it appears during debugging
- Keep host-specific SOPS material scoped to per-host installer workspaces; do not stage shared secrets into the live checkout
- Use proper permission management
- Follow principle of least privilege
- Keep system up-to-date with security patches
- Validate configuration changes before deployment
