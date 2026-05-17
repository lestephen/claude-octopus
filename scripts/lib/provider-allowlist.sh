#!/usr/bin/env bash
# provider-allowlist.sh — Shared provider allow/deny helpers.
#
# Two mechanisms are supported:
#
# 1. Allowlist (legacy):
#    OCTO_ALLOWED_PROVIDERS — space/comma separated list of provider names.
#    When unset, every detected provider is allowed. When set, only the
#    listed providers are allowed; anything else is treated as unavailable.
#
# 2. Denylist (lestephen.15+):
#    Multiple sources, all merged into a single effective deny set.
#    Precedence (highest first) — any source that lists a provider as
#    disabled wins:
#      a. OCTO_DISABLED_PROVIDERS env var (session-scoped denylist)
#      b. ./.octopus/providers.json `.disabled[]` (project-scoped)
#      c. ~/.claude-octopus/config/providers.json `.disabled[]` (user-scoped)
#
# Effective availability rule:
#    A provider is OK to use iff:
#        (allowlist unset OR provider is in allowlist)
#        AND provider is not in any denylist source

octo_normalize_provider_name() {
    printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr -d ','
}

# ─────────────────────────────────────────────────────────────────────
# Denylist (new)
# ─────────────────────────────────────────────────────────────────────

# Read disabled providers from a JSON config file. Echoes one provider
# name per line. Silent (no output) when file missing or malformed.
_octo_disabled_from_file() {
    local path="$1"
    [[ -f "$path" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r '.disabled // [] | .[]' "$path" 2>/dev/null
}

# Build the effective disabled set as a newline-separated list of
# normalized provider names. Exported for cheap repeated lookup via
# octo_provider_disabled. Re-runs on every call (no caching) — callers
# that loop many times can capture the output once.
octo_disabled_set() {
    {
        # Env var: OCTO_DISABLED_PROVIDERS (space/comma separated)
        if [[ -n "${OCTO_DISABLED_PROVIDERS:-}" ]]; then
            local token
            # shellcheck disable=SC2086 # intentional word splitting
            for token in ${OCTO_DISABLED_PROVIDERS//,/ }; do
                [[ -n "$token" ]] && octo_normalize_provider_name "$token" && echo
            done
        fi
        # Project config
        _octo_disabled_from_file "./.octopus/providers.json" | while read -r p; do
            [[ -n "$p" ]] && { octo_normalize_provider_name "$p"; echo; }
        done
        # User config
        _octo_disabled_from_file "$HOME/.claude-octopus/config/providers.json" | while read -r p; do
            [[ -n "$p" ]] && { octo_normalize_provider_name "$p"; echo; }
        done
    } | awk 'NF' | sort -u
}

# Return 0 if provider is in any denylist source.
octo_provider_disabled() {
    local provider
    provider="$(octo_normalize_provider_name "${1:-}")"
    [[ -n "$provider" ]] || return 1

    local disabled_list
    disabled_list="$(octo_disabled_set)"
    [[ -z "$disabled_list" ]] && return 1

    local entry
    while IFS= read -r entry; do
        [[ "$entry" == "$provider" ]] && return 0
    done <<< "$disabled_list"
    return 1
}

# Return human-readable source(s) where provider is denied. Used by
# /octo:doctor and `provider list` for transparency.
octo_provider_disabled_source() {
    local provider
    provider="$(octo_normalize_provider_name "${1:-}")"
    [[ -n "$provider" ]] || { echo ""; return 1; }

    local sources=()

    if [[ -n "${OCTO_DISABLED_PROVIDERS:-}" ]]; then
        local token
        for token in ${OCTO_DISABLED_PROVIDERS//,/ }; do
            [[ "$(octo_normalize_provider_name "$token")" == "$provider" ]] && sources+=("env (OCTO_DISABLED_PROVIDERS)")
        done
    fi

    local proj="./.octopus/providers.json"
    if [[ -f "$proj" ]] && command -v jq >/dev/null 2>&1; then
        local in_proj
        in_proj=$(jq --arg p "$provider" -r '(.disabled // []) | map(ascii_downcase) | index($p)' "$proj" 2>/dev/null)
        [[ "$in_proj" != "null" && -n "$in_proj" ]] && sources+=("project ($proj)")
    fi

    local user="$HOME/.claude-octopus/config/providers.json"
    if [[ -f "$user" ]] && command -v jq >/dev/null 2>&1; then
        local in_user
        in_user=$(jq --arg p "$provider" -r '(.disabled // []) | map(ascii_downcase) | index($p)' "$user" 2>/dev/null)
        [[ "$in_user" != "null" && -n "$in_user" ]] && sources+=("user ($user)")
    fi

    if [[ ${#sources[@]} -eq 0 ]]; then
        echo ""
        return 1
    fi
    printf '%s' "${sources[0]}"
    local i
    for ((i=1; i<${#sources[@]}; i++)); do
        printf ', %s' "${sources[$i]}"
    done
    echo ""
}

# ─────────────────────────────────────────────────────────────────────
# Allowlist (existing, extended to also enforce denylist)
# ─────────────────────────────────────────────────────────────────────

# Return 0 if provider is allowed to run.
#   - If denylist contains provider: NOT allowed.
#   - Else if allowlist unset: allowed.
#   - Else: allowed iff provider in allowlist.
octo_provider_allowed() {
    local provider
    provider="$(octo_normalize_provider_name "${1:-}")"
    [[ -n "$provider" ]] || return 1

    # Denylist trumps everything
    octo_provider_disabled "$provider" && return 1

    # No allowlist set = allowed
    if [[ -z "${OCTO_ALLOWED_PROVIDERS:-}" ]]; then
        return 0
    fi

    local token normalized
    # shellcheck disable=SC2086 # Intentional word splitting: space separated allowlist.
    for token in ${OCTO_ALLOWED_PROVIDERS//,/ }; do
        normalized="$(octo_normalize_provider_name "$token")"
        [[ -n "$normalized" ]] || continue

        [[ "$provider" == "$normalized" ]] && return 0

        case "$normalized" in
            claude|anthropic|sonnet)
                case "$provider" in
                    claude|claude-sonnet|claude-opus|sonnet) return 0 ;;
                esac
                ;;
            codex|openai)
                case "$provider" in
                    codex|codex-*) return 0 ;;
                esac
                ;;
            gemini|google)
                case "$provider" in
                    gemini|gemini-*) return 0 ;;
                esac
                ;;
            cursor|cursor-agent|xai)
                [[ "$provider" == "cursor-agent" ]] && return 0
                ;;
            local)
                [[ "$provider" == "ollama" ]] && return 0
                ;;
        esac
    done

    return 1
}
