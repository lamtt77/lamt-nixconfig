#!/usr/bin/env bash
# shellcheck disable=SC2154
# Nix Compilation & Flake Parser Library (installer2)

declare -g -A TARGET_SYSTEMS=()
declare -g -A RESOLVED_STRATEGIES=()
declare -g -A SYNCED_HOSTS=()

declare -g _NIX_SUPPORTS_FORCE=""

supports_nix_force_flag() {
    if [[ -z "$_NIX_SUPPORTS_FORCE" ]]; then
        if nix --help 2>&1 | grep -q -E -- '--force[[:space:]]'; then
            _NIX_SUPPORTS_FORCE="yes"
        else
            _NIX_SUPPORTS_FORCE="no"
        fi
    fi
    [[ "$_NIX_SUPPORTS_FORCE" == "yes" ]]
}

# --- Flake Metadata Parser ---
eval_flake_meta() {
    local host="$1"
    local path="$2"
    local flake_ref="${FLAKE_URI:-path:.}"
    local nix_eval_opts=("--extra-experimental-features" "nix-command flakes" "--raw")
    supports_nix_force_flag && nix_eval_opts+=("--force")

    # Evaluate against NixOS configuration first, fallback to darwin
    local val
    val=$(nix eval "${nix_eval_opts[@]}" "${flake_ref}#nixosConfigurations.${host}.config.${path}" 2>/dev/null || \
          nix eval "${nix_eval_opts[@]}" "${flake_ref}#darwinConfigurations.${host}.config.${path}" 2>/dev/null || echo "")
    echo "$val"
}

is_local_flake_ref() {
    local flake_ref="$1"
    [[ "$flake_ref" == "." || "$flake_ref" == "path:." || "$flake_ref" == "path:$ROOT_DIR" ]]
}

resolve_target_system() {
    local host="$1"
    local safe_key="${host//-/_}"

    # Ensure metadata is loaded if we don't have it cached
    if [[ -z "${TARGET_SYSTEMS["$safe_key"]:-}" ]]; then
        if declare -f ensure_metadata_loaded >/dev/null; then
            ensure_metadata_loaded
        fi
    fi

    local system="${TARGET_SYSTEMS["$safe_key"]:-}"

    if [[ -z "$system" ]]; then
        system=$(eval_flake_meta "$host" "nixpkgs.system")
        TARGET_SYSTEMS["$safe_key"]="$system"
    fi
    echo "$system"
}

current_host_system() {
    local os arch
    os=$(uname -s)
    arch=$(uname -m)

    case "$os" in
        Darwin)
            case "$arch" in
                x86_64) echo "x86_64-darwin" ;;
                arm64 | aarch64) echo "aarch64-darwin" ;;
                *) echo "unknown" ;;
            esac
            ;;
        Linux)
            case "$arch" in
                x86_64) echo "x86_64-linux" ;;
                aarch64 | arm64) echo "aarch64-linux" ;;
                *) echo "unknown" ;;
            esac
            ;;
        *)
            # Fallback to nix eval if operating system is unexpected
            nix eval --impure --raw --expr 'builtins.currentSystem' 2>/dev/null || echo ""
            ;;
    esac
}

# Translate arch to Nix system identifier
system_from_arch() {
    local arch="$1"
    case "$arch" in
        x86_64) echo "x86_64-linux" ;;
        aarch64 | arm64) echo "aarch64-linux" ;;
        *) echo "unknown" ;;
    esac
}

# --- Compilation Broker ---
resolve_nix_attr() {
    local host="$1"
    local attr_suffix="$2"
    local strategy="$3"
    local system
    system=$(resolve_target_system "$host")

    if [[ "$strategy" == "cross" ]]; then
        echo "crossNixosConfigurations.$host.$attr_suffix"
    elif [[ "$system" == *darwin* ]]; then
        if [[ "$attr_suffix" == "config.system.build.toplevel" ]]; then
            echo "darwinConfigurations.$host.system"
        else
            echo "darwinConfigurations.$host.$attr_suffix"
        fi
    else
        echo "nixosConfigurations.$host.$attr_suffix"
    fi
}

check_builder_connectivity() {
    local builder="$1"
    local builder_host="${builder#*@}"
    local builder_ip
    builder_ip=$(ping_host "$builder_host" || echo "")

    info "Verifying remote builder availability ($builder)..."
    if ! ssh "${SSH_COMMON_ARGS[@]}" "$builder" "true" 2>/dev/null; then
        die "Remote builder '$builder' is not reachable via SSH."
    fi

    if [[ -n "$builder_ip" ]]; then
        info "Builder reachable at $builder_ip."
    fi
}

detect_builder_system() {
    local builder="$1"
    local builder_arch="unknown"

    if ssh "${SSH_COMMON_ARGS[@]}" "$builder" "true" 2>/dev/null; then
        builder_arch=$(ssh "${SSH_COMMON_ARGS[@]}" "$builder" "uname -m" 2>/dev/null || echo "unknown")
    fi
    system_from_arch "$builder_arch"
}

resolve_build_strategy() {
    local host="$1"
    local safe_key="${host//-/_}"

    if [[ -n "${RESOLVED_STRATEGIES["$safe_key"]:-}" ]]; then
        STRATEGY="${RESOLVED_STRATEGIES["$safe_key"]}"
        return
    fi

    local strategy="local"
    local target_system
    target_system=$(resolve_target_system "$host")

    if [[ -n "${BUILD_ON:-}" && "$BUILD_ON" != "auto" ]]; then
        strategy="$BUILD_ON"
        if [[ "$strategy" == "builder" ]]; then
            require_var BUILDER "--builder"
            check_builder_connectivity "$BUILDER"
        elif [[ "$strategy" == "remote" ]]; then
            strategy="target"
        fi
    else
        local host_system
        host_system=$(current_host_system)

        if [[ -z "$target_system" ]]; then
            strategy="local"
            debug "Strategy resolution: Could not determine architecture. Defaulting to local."
        elif [[ "$target_system" == "$host_system" ]]; then
            strategy="local"
            debug "Strategy resolution: Architectures match. Building natively locally."
        elif [[ -n "${BUILDER:-}" ]]; then
            local builder_host="${BUILDER#*@}"
            if [[ "$(hostname -s)" != "$builder_host" ]]; then
                local builder_system
                builder_system=$(detect_builder_system "$BUILDER")

                if [[ "$target_system" == "$builder_system" ]]; then
                    strategy="builder"
                    info "Strategy resolution: Architecture mismatch. Delegating to remote builder ($BUILDER)."
                else
                    strategy="target"
                    info "Strategy resolution: Builder mismatch. Building directly on target ($host)."
                fi
            else
                strategy="target"
            fi
        else
            strategy="target"
            info "Strategy resolution: Local mismatch & no builder defined. Building directly on target."
        fi
    fi

    RESOLVED_STRATEGIES["$safe_key"]="$strategy"
    STRATEGY="$strategy"
}

load_github_token() {
    if [[ -z "${TOKEN_OPT:-}" ]]; then
        if [[ -z "${GITHUB_TOKEN:-}" ]] && command -v gh >/dev/null 2>&1; then
            GITHUB_TOKEN=$(gh auth token 2>/dev/null || true)
        fi
        TOKEN_OPT=$([[ -n "${GITHUB_TOKEN:-}" ]] && echo "--option access-tokens github.com=$GITHUB_TOKEN" || echo "")
    fi
}

# --- Nix Commands wrapper ---
set_nix_command_opts() {
    load_github_token
    NIX_OPTS=("--extra-experimental-features" "nix-command flakes")
    supports_nix_force_flag && NIX_OPTS+=("--force")

    if [[ -n "${TOKEN_OPT:-}" ]]; then
        read -ra token_opts <<< "${TOKEN_OPT}"
        NIX_OPTS+=("${token_opts[@]}")
    fi

    if [[ "${1:-}" == "--substitute" && "${SUBS_ON_DEST:-yes}" == "yes" ]]; then
        NIX_OPTS+=("--substitute-on-destination")
    fi

    NIX_OPTS_SSH="${NIX_OPTS[*]@Q}"
}

nix_build() {
    local host="$1"
    local attr_suffix="${2:-config.system.build.toplevel}"
    local drv_path=""

    resolve_build_strategy "$host"
    local strategy="$STRATEGY"

    # Sync code to builder/target first if local references are used
    local flake_ref="${FLAKE_URI:-path:.}"
    if is_local_flake_ref "$flake_ref"; then
        if [[ "$strategy" == "builder" || "$strategy" == "target" ]]; then
            local build_target="$BUILDER"
            [[ "$strategy" == "target" ]] && build_target="$SSH_USER@$CONNECTION_IP"

            local safe_sync_key="${build_target//-/_}"
            safe_sync_key="${safe_sync_key//@/_}"
            safe_sync_key="${safe_sync_key//./_}"

            if [[ -z "${SYNCED_HOSTS["$safe_sync_key"]:-}" ]]; then
                info "Syncing local repository codebase to remote build host ($build_target)..."
                ssh_cmd "$build_target" "mkdir -p $NIX_CFG"
                rsync_cmd "$ROOT_DIR/" "$build_target:$NIX_CFG/" "$RSYNC_COMMON_FLAGS" >&2
                SYNCED_HOSTS["$safe_sync_key"]="yes"
            else
                debug "Repository codebase already synced to $build_target in this run. Skipping sync."
            fi
        fi
    fi

    local attr
    attr=$(resolve_nix_attr "$host" "$attr_suffix" "$strategy")
    set_nix_command_opts

    if [[ "$strategy" == "builder" || "$strategy" == "target" ]]; then
        local remote_host="$BUILDER"
        [[ "$strategy" == "target" ]] && remote_host="$SSH_USER@$CONNECTION_IP"

        info "Delegating Nix build to remote host: $remote_host..."
        local build_flags=""
        local gc_env=""

        if [[ "${LOW_MEM:-no}" == "yes" ]]; then
             info "Low Memory Tuning: Restricting build resources to 1 core/job and GC limit..."
             build_flags="--cores 1 --max-jobs 1"
             gc_env="export GC_INITIAL_HEAP_SIZE=1M GC_DONT_GC=1 NIX_DISABLE_AUTO_GC=1;"
        fi

        local cd_cmd=""
        is_local_flake_ref "$flake_ref" && cd_cmd="cd $NIX_CFG &&" && flake_ref="path:."

        local compile_cmd="set -euo pipefail; $cd_cmd export NIX_SSHOPTS='$SSH_COMMON_OPTIONS' && $gc_env nix build $build_flags $NIX_OPTS_SSH --print-out-paths --no-link ${flake_ref}#$attr"
        drv_path=$(ssh "${SSH_COMMON_ARGS[@]}" -A "$remote_host" "$compile_cmd") || return 1
        drv_path=$(echo "$drv_path" | tr -d '\r' | tail -n 1)
    else
        info "Executing native Nix build derivation for $host ($attr) locally..."
        drv_path=$(nix build "${NIX_OPTS[@]}" --print-out-paths --no-link "${flake_ref}#$attr") || return 1
    fi

    [[ -z "$drv_path" ]] && error "Nix build returned empty path." && return 1
    echo "$drv_path"
}

nix_copy_closure() {
    local dest_target="$1"
    local drv_path="$2"

    info "Transferring compiled Nix store closure to $dest_target..."
    set_nix_command_opts --substitute
    export NIX_SSHOPTS="$SSH_COMMON_OPTIONS"
    nix copy --to "ssh://$dest_target" "$drv_path" "${NIX_OPTS[@]}"
}
