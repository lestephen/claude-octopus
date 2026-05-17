#!/usr/bin/env bash
# provider-config.sh — Mutate the providers.json `.disabled[]` array.
#
# Used by:
#   - `bash scripts/orchestrate.sh provider enable|disable|list <name>`
#   - `/octo:setup` / `/octo:doctor` interactive prompts (future)
#
# Backed by two config files:
#   - User: ~/.claude-octopus/config/providers.json (created on first write)
#   - Project: ./.octopus/providers.json (created on first write with --project)
#
# Each call rewrites the JSON file in place, preserving any unrelated
# keys. The `.disabled[]` array is the canonical mutable surface.

# Resolve which config file a `--project` or default call targets.
# Echoes the path. Does NOT create the file.
_provider_config_path() {
    local scope="${1:-user}"
    case "$scope" in
        project) echo "./.octopus/providers.json" ;;
        user|*)  echo "$HOME/.claude-octopus/config/providers.json" ;;
    esac
}

# lestephen.20 (F7): Validate provider name before writing to JSON.
# Rejects names with whitespace, newlines, control chars, or characters
# outside [a-z0-9-]. Returns 0 if valid, 2 with an error message if not.
_provider_validate_name() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "ERROR: provider name required" >&2
        return 2
    fi
    # Lowercase letters/digits + hyphen; must start with alphanumeric;
    # 1-32 chars (defensive upper bound).
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]]; then
        echo "ERROR: invalid provider name '$name'. Must match ^[a-z0-9][a-z0-9-]{0,31}\$ (lowercase alphanumerics + hyphens, max 32 chars)" >&2
        return 2
    fi
    return 0
}

# lestephen.20 (F6): Run a callback under an exclusive flock on the given
# config file. Prevents concurrent disable/enable from racing each other
# and losing one provider. Falls back to no-lock with a WARN if flock is
# unavailable.
_provider_config_with_lock() {
    local path="$1"
    shift
    if command -v flock >/dev/null 2>&1; then
        local lock_file="${path}.lock"
        mkdir -p "$(dirname "$lock_file")"
        # Use a dedicated fd. Sub-shell call so locking scope is the callback.
        (
            exec 200>"$lock_file"
            if ! flock -w 10 200; then
                echo "ERROR: could not acquire lock on $lock_file within 10s; another writer may be stuck" >&2
                return 2
            fi
            "$@"
        )
    else
        echo "WARN: flock not available; concurrent provider-config writes may race" >&2
        "$@"
    fi
}

# Read the current `.disabled[]` list from a scope. Echoes one name
# per line (lowercased). Returns 0 even if file missing/empty.
provider_config_disabled() {
    local scope="${1:-user}"
    local path
    path=$(_provider_config_path "$scope")
    [[ -f "$path" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r '(.disabled // []) | .[] | ascii_downcase' "$path" 2>/dev/null
}

# Add a provider to the .disabled[] array. Creates the file + parent
# dirs if needed. Idempotent.
provider_config_disable() {
    local provider="$1"
    local scope="${2:-user}"
    _provider_validate_name "$provider" || return 2
    command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; return 2; }

    local path
    path=$(_provider_config_path "$scope")
    mkdir -p "$(dirname "$path")"

    # Initialize file if missing
    [[ -f "$path" ]] || echo '{"version":"3.0"}' > "$path"

    # lestephen.20 (F6): All read+modify+write goes under a flock so concurrent
    # disable/enable on different providers can't read the same old JSON and
    # last-writer-wins one of them away.
    _provider_config_with_lock "$path" _provider_config_disable_locked "$provider" "$scope" "$path"
}

_provider_config_disable_locked() {
    local provider="$1"
    local scope="$2"
    local path="$3"

    # Check idempotency
    local already
    already=$(jq --arg p "$provider" 'any((.disabled // []) | .[]; ascii_downcase == ($p | ascii_downcase))' "$path" 2>/dev/null)
    if [[ "$already" == "true" ]]; then
        echo "Already disabled in $scope scope: $provider ($path)"
        return 0
    fi

    # Append + atomic rename
    local tmp
    tmp=$(mktemp "${path}.XXXXXX")
    jq --arg p "$provider" '.disabled = ((.disabled // []) + [$p | ascii_downcase])' "$path" > "$tmp" \
        && mv "$tmp" "$path" \
        && echo "Disabled in $scope scope: $provider ($path)"
}

# Remove a provider from the .disabled[] array. Idempotent.
provider_config_enable() {
    local provider="$1"
    local scope="${2:-user}"
    _provider_validate_name "$provider" || return 2
    command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; return 2; }

    local path
    path=$(_provider_config_path "$scope")
    if [[ ! -f "$path" ]]; then
        echo "Not currently disabled in $scope scope: $provider (no config file at $path)"
        return 0
    fi

    # lestephen.20 (F6): locked read+modify+write
    _provider_config_with_lock "$path" _provider_config_enable_locked "$provider" "$scope" "$path"
}

_provider_config_enable_locked() {
    local provider="$1"
    local scope="$2"
    local path="$3"

    local already
    already=$(jq --arg p "$provider" 'any((.disabled // []) | .[]; ascii_downcase == ($p | ascii_downcase))' "$path" 2>/dev/null)
    if [[ "$already" != "true" ]]; then
        echo "Not currently disabled in $scope scope: $provider ($path)"
        return 0
    fi

    local tmp
    tmp=$(mktemp "${path}.XXXXXX")
    jq --arg p "$provider" '.disabled = ((.disabled // []) | map(select(ascii_downcase != ($p | ascii_downcase))))' "$path" > "$tmp" \
        && mv "$tmp" "$path" \
        && echo "Re-enabled in $scope scope: $provider ($path)"
}

# Render a status table of every known provider showing:
#   provider  status (available|missing|disabled)  source-or-detection
# Status: "available" = installed + auth + not in any denylist
#         "missing"   = not installed or not authenticated
#         "disabled"  = explicitly disabled via env/project/user config
provider_config_list() {
    # Resolve repo root from script location to load helpers
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/provider-allowlist.sh" 2>/dev/null || true

    local provider_check="${script_dir}/../helpers/check-providers.sh"

    if [[ ! -x "$provider_check" ]]; then
        echo "ERROR: check-providers.sh not found at $provider_check" >&2
        return 2
    fi

    printf '%-15s  %-10s  %s\n' "PROVIDER" "STATUS" "SOURCE / NOTE"
    printf '%-15s  %-10s  %s\n' "---------------" "----------" "-------------------------"

    local output
    output=$(bash "$provider_check" 2>/dev/null)

    local line
    while IFS= read -r line; do
        case "$line" in
            PROVIDER_CHECK_START|PROVIDER_CHECK_END|"") continue ;;
        esac
        local name="${line%%:*}"
        local status="${line##*:}"
        # Strip extra :something if check-providers later emits richer format
        status="${status%%:*}"

        local source_note=""
        if octo_provider_disabled "$name"; then
            status="disabled"
            source_note="$(octo_provider_disabled_source "$name")"
        elif [[ "$status" == "missing" ]]; then
            source_note="not installed or not authenticated"
        elif [[ "$status" == "available" ]]; then
            source_note="detected"
        fi
        printf '%-15s  %-10s  %s\n' "$name" "$status" "$source_note"
    done <<< "$output"

    # Print legend / env hints
    echo ""
    echo "Hints:"
    echo "  Disable a provider:  bash scripts/orchestrate.sh provider disable <name> [--project]"
    echo "  Re-enable:           bash scripts/orchestrate.sh provider enable <name> [--project]"
    echo "  Session-only deny:   export OCTO_DISABLED_PROVIDERS=copilot,qwen"
    echo "  Session allowlist:   export OCTO_ALLOWED_PROVIDERS=codex,gemini,claude"
}
