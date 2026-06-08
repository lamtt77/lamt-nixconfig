#!/usr/bin/env bash
# shellcheck disable=SC2154
# Core Installer Library (installer2)

# --- ANSI Color Codes ---
RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'

# --- Logging Helpers ---
info() {
    printf "${BLUE}[INFO]${RESET} %s\n" "$*" >&2
}

warn() {
    printf "${YELLOW}[WARN]${RESET} %s\n" "$*" >&2
}

error() {
    printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2
}

debug() {
    if [[ "${DEBUG:-no}" == "yes" ]]; then
        printf "${GREEN}[DEBUG]${RESET} %s\n" "$*" >&2
    fi
}

die() {
    error "$1"
    exit 1
}

require_var() {
    local var_name="$1"
    local friendly_name="${2:-$var_name}"
    if [[ -z "${!var_name:-}" ]]; then
        die "$friendly_name is required"
    fi
}

confirm_or_exit() {
    local message="$1"
    local reply

    [[ "${FORCE:-no}" == "yes" ]] && return 0

    warn "$message"
    read -r -p "Are you sure? (y/N): " reply
    [[ "$reply" =~ ^[Yy]$ ]] || exit 1
}

# --- Connection Helpers ---
ping_host() {
    local target="$1"
    local timeout=2
    if [[ "$(uname)" == "Darwin" ]]; then
        timeout=2000
    fi

    local ping_out
    if ping_out=$(ping -c 1 -W "$timeout" "$target" 2>/dev/null); then
        local first_line
        first_line=$(echo "$ping_out" | head -n 1)
        if [[ "$first_line" =~ \(([0-9a-fA-F\.:]+)\) ]]; then
            echo "${BASH_REMATCH[1]}"
        else
            echo "$target"
        fi
        return 0
    else
        return 1
    fi
}

ssh_cmd() {
    local target="$1"
    local cmd="$2"
    debug "Executing SSH to $target: $cmd"
    # shellcheck disable=SC2029
    ssh "${SSH_COMMON_ARGS[@]}" "$target" "$cmd"
}

rsync_cmd() {
    local src="$1"
    local dest="$2"
    local exclude_flags="${3:-}"
    local flags=()

    if [[ -n "$exclude_flags" ]]; then
        read -r -a flags <<< "$exclude_flags"
    fi

    debug "Executing RSYNC from $src to $dest"
    rsync -avh "${flags[@]}" -e "ssh $SSH_COMMON_OPTIONS" "$src" "$dest"
}

wait_for_ssh() {
    local target="$1"
    local timeout="${2:-300}"
    local interval=5
    local elapsed=0

    info "Waiting for SSH on $target..."
    while ! ssh "${SSH_COMMON_ARGS[@]}" "$target" "true" >/dev/null 2>&1; do
        if [[ $elapsed -ge $timeout ]]; then
            error "Timed out waiting for SSH on $target"
            return 1
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        debug "Waiting... (${elapsed}s)"
    done
    info "SSH is ready."
}

warmup_remote_builder() {
    local builder="$1"
    local target_ip="$2"
    local builder_host="${builder#*@}"

    if [[ "$builder_host" == "$target_ip" ]]; then
        return
    fi

    info "Warming up builder network ARP cache to target ($target_ip)..."
    # shellcheck disable=SC2029
    ssh "${SSH_COMMON_ARGS[@]}" "$builder" "ping -c 3 -W 1 $target_ip >/dev/null 2>&1 || true"
}

# --- Secrets Staging & Host Key Management ---
# (generate_host_key_if_missing has been moved to lib/keys.sh)

stage_secrets_pre() {
    local host="$1"
    local secrets_src="${DEFAULT_SECRETS_REPO}/sops/${host}.yaml"
    local secrets_dest="./secrets/sops/${host}.yaml"

    # Warn and skip when secrets repo is not present or invalid (e.g. running make on the target host itself)
    if [[ ! -d "$DEFAULT_SECRETS_REPO" || ! -f "$DEFAULT_SECRETS_REPO/.sops.yaml" ]]; then
        warn "Secrets repo '$DEFAULT_SECRETS_REPO' or '.sops.yaml' not found. Skipping secrets staging."
        return 0
    fi

    if [[ -f "$secrets_src" ]]; then
        info "Secrets found for $host. Copying to ./secrets/sops ..."
        mkdir -p "./secrets/sops"
        cp "$secrets_src" "$secrets_dest"
    else
        debug "No secrets found at $secrets_src. Continuing without secrets."
    fi
}

stage_secrets_post() {
    local host="${1:-}"
    if [[ -d "./secrets" ]]; then
        if [[ -n "$host" && -f "./secrets/sops/${host}.yaml" ]]; then
            info "Cleaning up copied secrets for $host..."
        else
            info "Cleaning up copied secrets..."
        fi
        rm -rf "./secrets"
    fi
}
