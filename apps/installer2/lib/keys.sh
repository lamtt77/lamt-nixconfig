# --- SSH Host Key & Secrets Key Management ---

# Generates host keys locally if missing, imports from target if present,
# or registers/re-encrypts them in SOPS .sops.yaml configuration.
generate_host_key_if_missing() {
    local host="$1"
    local secrets_repo="${DEFAULT_SECRETS_REPO:-../lamt-secrets}"
    local key_dir="$secrets_repo/hosts/$host"
    local key_file="$key_dir/ssh_host_ed25519_key"
    local pub_key_file="${key_file}.pub"

    # Warn and skip when secrets repo is not present or invalid (e.g. running make on the target host itself)
    if [[ ! -d "$secrets_repo" || ! -f "$secrets_repo/.sops.yaml" ]]; then
        warn "Secrets repo '$secrets_repo' or '.sops.yaml' not found. Skipping host key management."
        return 0
    fi

    # Determine public key source: use the system key for the local host itself
    local active_pub_key=""
    local local_pub_key=""

    # Load local public key from secrets if it exists
    if [[ -f "$pub_key_file" ]]; then
        local_pub_key=$(cat "$pub_key_file" | awk '{print $1" "$2}')
    fi

    # Resolve active public key from the target machine
    if [[ "$host" == "$(hostname -s)" ]]; then
        if [[ -f "/etc/ssh/ssh_host_ed25519_key.pub" ]]; then
            active_pub_key=$(cat "/etc/ssh/ssh_host_ed25519_key.pub" | awk '{print $1" "$2}')
        fi
    else
        # If remote target, try fetching via SSH
        if [[ -n "${CONNECTION_IP:-}" ]]; then
            # We try to connect with a short timeout to check if SSH is up and retrieve key
            local fetched_key
            fetched_key=$(ssh -o ConnectTimeout=3 "${SSH_COMMON_ARGS[@]}" "$SSH_USER@$CONNECTION_IP" "sudo cat /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null" || echo "")
            if [[ -n "$fetched_key" ]]; then
                active_pub_key=$(echo "$fetched_key" | awk '{print $1" "$2}')
            fi
        fi
    fi

    # If the local key file is missing, we must generate one or import it
    if [[ ! -f "$pub_key_file" ]]; then
        if [[ -n "$active_pub_key" ]]; then
            info "Secrets repo is missing host key for '$host', but target host has an active key."
            info "Importing active host keys from target..."
            mkdir -p "$key_dir"
            if ssh "${SSH_COMMON_ARGS[@]}" "$SSH_USER@$CONNECTION_IP" "sudo cat /etc/ssh/ssh_host_ed25519_key" > "$key_file" 2>/dev/null && \
               ssh "${SSH_COMMON_ARGS[@]}" "$SSH_USER@$CONNECTION_IP" "sudo cat /etc/ssh/ssh_host_ed25519_key.pub" > "$pub_key_file" 2>/dev/null; then
                chmod 600 "$key_file"
                chmod 644 "$pub_key_file"
                local_pub_key="$active_pub_key"
            else
                warn "Failed to copy host keys from target host. Falling back to local generation."
                rm -f "$key_file" "$pub_key_file"
            fi
        fi

        # If still missing, generate a fresh key locally
        if [[ ! -f "$pub_key_file" ]]; then
            info "SSH host key for '$host' is missing. Generating fresh Ed25519 key locally..."
            mkdir -p "$key_dir"
            ssh-keygen -t ed25519 -f "$key_file" -N "" -q
            local_pub_key=$(cat "${pub_key_file}" | awk '{print $1" "$2}')
            warn "Generated new target host identity for $host."
        fi
    else
        debug "Existing local host key found for $host: $pub_key_file"
    fi

    # Check for mismatches between target host and local secrets definition
    if [[ -n "$active_pub_key" && "$active_pub_key" != "$local_pub_key" ]]; then
        warn "Target host '$host' SSH key mismatch detected!"
        info "  Local key (in secrets): $local_pub_key"
        info "  Target key (active on host): $active_pub_key"

        local reply=""
        if [[ "${CLI_FORCE:-no}" != "yes" ]]; then
            echo "How would you like to resolve this mismatch?"
            echo "  1) Overwrite target key to match secrets (Target -> Secrets)"
            echo "  2) Update secrets to match target key (Secrets -> Target)"
            echo "  3) Proceed anyway (decryption may fail)"
            echo "  4) Abort deployment"
            read -r -p "Select option (1-4): " reply
        else
            # Non-interactive mode (CLI_FORCE=yes)
            if [[ "${UPDATE_HOST_KEY:-no}" == "yes" ]]; then
                info "Auto-selecting Option 1: Overwrite target key (UPDATE_HOST_KEY=yes)..."
                reply="1"
            elif [[ "${UPDATE_SECRETS_KEY:-no}" == "yes" ]]; then
                info "Auto-selecting Option 2: Update secrets (UPDATE_SECRETS_KEY=yes)..."
                reply="2"
            else
                warn "No automatic option selected in non-interactive mode. Aborting."
                exit 1
            fi
        fi

        case "$reply" in
            1)
                info "Setting flag to update target host key during switch..."
                export UPDATE_HOST_KEY="yes"
                ;;
            2)
                info "Updating secrets repository with target host key..."
                mkdir -p "$key_dir"
                if ssh "${SSH_COMMON_ARGS[@]}" "$SSH_USER@$CONNECTION_IP" "sudo cat /etc/ssh/ssh_host_ed25519_key" > "$key_file" 2>/dev/null && \
                   ssh "${SSH_COMMON_ARGS[@]}" "$SSH_USER@$CONNECTION_IP" "sudo cat /etc/ssh/ssh_host_ed25519_key.pub" > "$pub_key_file" 2>/dev/null; then
                    chmod 600 "$key_file"
                    chmod 644 "$pub_key_file"
                    local_pub_key="$active_pub_key"

                    # Update SOPS age key in .sops.yaml and re-encrypt secrets
                    local local_age_key
                    local_age_key=$(echo "$local_pub_key" | ssh-to-age 2>/dev/null || echo "")
                    if [[ -n "$local_age_key" ]]; then
                        local sops_mgr="$secrets_repo/bin/sops-host-key-manager"
                        if [[ -x "$sops_mgr" ]]; then
                            "$sops_mgr" set-key "$host" "$local_age_key" || die "Failed to update host '$host' key in .sops.yaml"
                            info "Successfully updated .sops.yaml and re-encrypted secrets."
                        else
                            warn "SOPS host key manager not found at $sops_mgr. Skipping re-encryption."
                        fi
                    fi
                else
                    die "Failed to copy host keys from target host to match secrets."
                fi
                export UPDATE_HOST_KEY="no"
                ;;
            3)
                warn "Proceeding anyway. Secrets decryption may fail on target."
                export UPDATE_HOST_KEY="no"
                export FORCE_PROCEED_MISMATCH="yes"
                ;;
            *)
                die "Aborted by user."
                ;;
        esac
    fi

    # SOPS configuration updates (for registration in .sops.yaml if missing)
    if [[ -f "$pub_key_file" ]]; then
        local pub_key
        pub_key=$(cat "$pub_key_file")

        # Resolve age key representation using ssh-to-age
        if command -v ssh-to-age &>/dev/null; then
            local local_age_key
            local_age_key=$(echo "$pub_key" | ssh-to-age 2>/dev/null || echo "")

            if [[ -n "$local_age_key" ]]; then
                local sops_mgr="$secrets_repo/bin/sops-host-key-manager"
                if [[ -x "$sops_mgr" ]]; then
                    local registered_age_key
                    registered_age_key=$("$sops_mgr" get-key "$host" 2>/dev/null || echo "")

                    if [[ -z "$registered_age_key" ]]; then
                        warn "Host '$host' is not registered in .sops.yaml."
                        info "Public Key: $pub_key"
                        info "Age Key:    $local_age_key"

                        local reply="y"
                        if [[ "${CLI_FORCE:-no}" != "yes" ]]; then
                            read -r -p "Would you like to automatically register '$host' in .sops.yaml and initialize secrets? (y/N): " reply
                        else
                            info "Auto-confirming SOPS registration (FORCE=yes)..."
                        fi

                        if [[ "$reply" =~ ^[Yy]$ ]]; then
                            "$sops_mgr" set-key "$host" "$local_age_key" || die "Failed to register host '$host' key"
                        else
                            warn "Skipped SOPS registration. Secrets deployment will fail."
                        fi
                    elif [[ "$registered_age_key" != "$local_age_key" ]]; then
                        warn "SOPS key mismatch detected for '$host':"
                        info "  Local key (derived from SSH key): $local_age_key"
                        info "  Registered key (in .sops.yaml):   $registered_age_key"

                        local reply="y"
                        if [[ "${CLI_FORCE:-no}" != "yes" ]]; then
                            read -r -p "Would you like to automatically update .sops.yaml and re-encrypt secrets for '$host'? (y/N): " reply
                        else
                            info "Auto-confirming SOPS update (FORCE=yes)..."
                        fi

                        if [[ "$reply" =~ ^[Yy]$ ]]; then
                            "$sops_mgr" set-key "$host" "$local_age_key" || die "Failed to update host '$host' key"
                        else
                            warn "Skipped SOPS update. Deployment may fail due to key mismatch."
                        fi
                    fi
                else
                    warn "SOPS host key manager not found at $sops_mgr"
                fi
            else
                warn "Failed to resolve age key from SSH public key."
            fi
        else
            debug "ssh-to-age is not available on this host. Skipping SOPS registration checks."
        fi
    fi
}

validate_and_sync_target_host_key() {
    local host="$1"
    local local_key_file="${DEFAULT_SECRETS_REPO:-../lamt-secrets}/hosts/${host}/ssh_host_ed25519_key"
    local local_pub_file="${local_key_file}.pub"

    # Only validate/sync target host keys if the authentic secrets repo is present
    if [[ ! -d "${DEFAULT_SECRETS_REPO:-../lamt-secrets}" || ! -f "${DEFAULT_SECRETS_REPO:-../lamt-secrets}/.sops.yaml" ]]; then
        return 0
    fi

    [[ ! -f "$local_pub_file" ]] && return 0

    local local_pub_key
    local_pub_key=$(cat "$local_pub_file" | awk '{print $1" "$2}')

    info "Validating target host SSH key signature..."
    # Read the public key of the target
    local target_pub_key
    target_pub_key=$(ssh_cmd "$SSH_USER@$CONNECTION_IP" "sudo cat /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null" || echo "")
    target_pub_key=$(echo "$target_pub_key" | awk '{print $1" "$2}')

    if [[ "$target_pub_key" != "$local_pub_key" ]]; then
        warn "Target host '$host' SSH key mismatch detected!"
        info "  Local key (in lamt-secrets): $local_pub_key"
        info "  Target key (active on host): $target_pub_key"

        if [[ "${UPDATE_HOST_KEY:-no}" == "yes" ]]; then
            info "Updating SSH host key on target to match local key..."
            # Stage keys (handling persistence/impermanence systems cleanly)
            local private_b64 public_b64
            private_b64=$(base64 -w0 "$local_key_file" 2>/dev/null || base64 "$local_key_file" | tr -d '\r\n')
            public_b64=$(base64 -w0 "$local_pub_file" 2>/dev/null || base64 "$local_pub_file" | tr -d '\r\n')

            ssh_cmd "$SSH_USER@$CONNECTION_IP" "sudo env PRIV_B64=\"$private_b64\" PUB_B64=\"$public_b64\" bash -c '
                set -euo pipefail

                # Determine if we use persistence / impermanence path
                has_persist=0
                if [ -d /persist/etc/ssh ] && [ \"\$(stat -c %i /persist/etc/ssh 2>/dev/null)\" != \"\$(stat -c %i /etc/ssh 2>/dev/null)\" ]; then
                    has_persist=1
                fi

                write_key() {
                    local name=\$1
                    local mode=\$2
                    local content_b64=\$3

                    local dest=/etc/ssh/\$name
                    local persist_dest=/persist\$dest

                    if [ \$has_persist -eq 1 ]; then
                        mkdir -p /persist/etc/ssh
                        rm -f \$persist_dest
                        echo \"\$content_b64\" | base64 -d > \$persist_dest
                        chmod \$mode \$persist_dest
                        if [ -f \$dest ] && [ ! -L \$dest ]; then
                            rm -f \$dest
                        fi
                    else
                        rm -f \$dest
                        echo \"\$content_b64\" | base64 -d > \$dest
                        chmod \$mode \$dest
                    fi
                }

                write_key ssh_host_ed25519_key 600 \"\$PRIV_B64\"
                write_key ssh_host_ed25519_key.pub 644 \"\$PUB_B64\"
            '"

            # Reload sshd to apply changes
            ssh_cmd "$SSH_USER@$CONNECTION_IP" "sudo systemctl reload sshd || sudo systemctl restart ssh || true"
            info "Target host key updated successfully."

            # Clean local known_hosts to prevent warning messages when the user SSHes manually later
            ssh-keygen -R "$CONNECTION_IP" 2>/dev/null || true
            ssh-keygen -R "$host" 2>/dev/null || true
        else
            warn "Target key does not match local definition in lamt-secrets."
            if [[ "${FORCE_PROCEED_MISMATCH:-no}" != "yes" ]]; then
                warn "To sync and update target host key (local lamt-secrets -> target /etc/ssh/), run with UPDATE_HOST_KEY=yes"
                confirm_or_exit "Do you want to proceed with deployment switch anyway?"
            else
                info "Proceeding anyway as requested by user mismatch choice..."
            fi
        fi
    fi
}


# ==============================================================================
# Tailscale Pre-auth Key Management
# ==============================================================================

validate_and_sync_tailscale_preauth_key() {
    local host="$1"
    local secrets_repo="${DEFAULT_SECRETS_REPO:-../lamt-secrets}"
    local host_secret_file="$secrets_repo/sops/${host}.yaml"

    # 1. Skip if secrets repo is not present
    if [[ ! -d "$secrets_repo" || ! -f "$secrets_repo/.sops.yaml" ]]; then
        return 0
    fi

    # 2. Only proceed if the host secret file exists (i.e. we manage secrets for this host)
    if [[ ! -f "$host_secret_file" ]]; then
        return 0
    fi

    # 3. Check if tailscale_preauth_key is defined in host secrets
    local existing_key
    existing_key=$(sops -d --extract '["tailscale_preauth_key"]' "$host_secret_file" 2>/dev/null || echo "")

    # If no key is defined, this host does not use declarative pre-auth keys. Skip silently.
    if [[ -z "$existing_key" ]]; then
        return 0
    fi

    local key_invalid="no"
    local found_user_id=""
    local found_username=""

    if [[ -z "$existing_key" ]]; then
        key_invalid="yes"
    else
        info "Checking validity of Tailscale pre-auth key for '$host' on Headscale..."
        local avon_ip="${HEADSCALE_COORDINATOR_IP:-100.64.0.1}"
        local avon_user="${HEADSCALE_COORDINATOR_USER:-nixos}"

        # Try to ping Headscale server first to prevent SSH timeouts
        if ping -c 1 -W 2 "$avon_ip" >/dev/null 2>&1; then
            # Fetch user list to look up keys across namespaces
            local users_json
            users_json=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 \
              "${avon_user}@$avon_ip" "sudo headscale users list --output json" 2>/dev/null || echo "")

            if [[ -n "$users_json" ]]; then
                # Loop through each user to check their pre-auth keys
                while read -r u_id u_name; do
                    local key_status
                    key_status=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 \
                      "${avon_user}@$avon_ip" "sudo headscale preauthkeys list -u $u_id --output json" 2>/dev/null || echo "")

                    if [[ -n "$key_status" ]]; then
                        local key_match
                        key_match=$(echo "$key_status" | jq -r --arg key "$existing_key" '.[] | select(.key == $key) | .key' 2>/dev/null || echo "")
                        if [[ -n "$key_match" ]]; then
                            found_user_id="$u_id"
                            found_username="$u_name"

                            local is_expired
                            is_expired=$(echo "$key_status" | jq -r --arg key "$existing_key" '.[] | select(.key == $key) | if (.expiration | fromdateiso8601) < now then "yes" else "no" end' 2>/dev/null || echo "no")
                            if [[ "$is_expired" == "yes" ]]; then
                                warn "Tailscale pre-auth key is EXPIRED on Headscale for user '$u_name'."
                                key_invalid="yes"
                            fi
                            break
                        fi
                    fi
                done < <(echo "$users_json" | jq -r '.[] | "\(.id) \(.name)"')

                if [[ -z "$found_username" ]]; then
                    warn "Tailscale pre-auth key not found or revoked on Headscale (checked all users)."
                    key_invalid="yes"
                fi
            else
                warn "Failed to fetch users list from Headscale server. Skipping pre-auth validation."
            fi
        else
            warn "Headscale coordinator ($avon_ip) is offline/unreachable. Skipping pre-auth validation."
        fi
    fi

    # 5. If key is missing or invalid/expired, prompt to re-generate
    if [[ "$key_invalid" == "yes" ]]; then
        local reply="n"
        if [[ "${CLI_FORCE:-no}" != "yes" ]]; then
            echo "[WARN] Tailscale pre-auth key for '$host' is missing, expired, or invalid."
            read -r -p "Would you like to generate a new 1-year (365d) reusable pre-auth key on Headscale? (y/N): " reply
        else
            info "Auto-confirming pre-auth key generation (FORCE=yes)..."
            reply="y"
        fi

        if [[ "$reply" =~ ^[Yy]$ ]]; then
            local avon_ip="${HEADSCALE_COORDINATOR_IP:-100.64.0.1}"
            local avon_user="${HEADSCALE_COORDINATOR_USER:-nixos}"
            if ping -c 1 -W 2 "$avon_ip" >/dev/null 2>&1; then
                # Fetch user list to resolve ID
                local users_json
                users_json=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 \
                  "${avon_user}@$avon_ip" "sudo headscale users list --output json" 2>/dev/null || echo "")

                if [[ -z "$users_json" ]]; then
                    die "Failed to retrieve user list from Headscale to map namespace ID."
                fi

                # Select namespace
                local namespace="${DEFAULT_TAILSCALE_NAMESPACE:-lamt}"
                if [[ -n "$found_username" ]]; then
                    # Default to the namespace of the expired key if it was found
                    namespace="$found_username"
                fi

                if [[ "${CLI_FORCE:-no}" != "yes" ]]; then
                    echo "Select user namespace for the pre-auth key [current: $namespace]:"
                    local idx=1
                    for ns in "${TAILSCALE_NAMESPACES[@]}"; do
                        echo "  ${idx}) ${ns}"
                        idx=$((idx + 1))
                    done
                    read -r -p "Select option (1-${#TAILSCALE_NAMESPACES[@]}) [default: match current]: " ns_choice
                    if [[ -n "$ns_choice" && "$ns_choice" -ge 1 && "$ns_choice" -le "${#TAILSCALE_NAMESPACES[@]}" ]]; then
                        namespace="${TAILSCALE_NAMESPACES[$((ns_choice - 1))]}"
                    fi
                fi

                # Resolve numeric ID for the namespace (username)
                local user_id
                user_id=$(echo "$users_json" | jq -r --arg name "$namespace" '.[] | select(.name == $name) | .id' 2>/dev/null || echo "")
                if [[ -z "$user_id" ]]; then
                    die "User '$namespace' not found in Headscale."
                fi

                info "Creating new pre-auth key on Headscale for user '$namespace' (ID: $user_id)..."
                local new_key
                new_key=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${avon_user}@$avon_ip" \
                  "sudo headscale preauthkeys create -u $user_id --reusable --expiration 365d" 2>/dev/null || echo "")

                # Truncate any whitespace/newlines
                new_key=$(echo "$new_key" | xargs)

                if [[ -n "$new_key" && "$new_key" != "Error"* ]]; then
                    info "Generated new pre-auth key successfully."
                    # Update secret in the host sops file
                    sops --set "[\"tailscale_preauth_key\"] \"$new_key\"" "$host_secret_file"
                    info "Updated tailscale_preauth_key in '$host_secret_file' successfully."
                else
                    die "Failed to create pre-auth key on Headscale. Check server logs."
                fi
            else
                die "Cannot contact Headscale server at $avon_ip to generate key. Aborting."
            fi
        else
            warn "Proceeding without updating pre-auth key. Declarative Tailscale enrollment may fail."
        fi
    fi
}
