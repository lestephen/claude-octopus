#!/usr/bin/env bash
# load-octo-profile.sh — Single canonical profile loader for octopus + eki-kw skills.
#
# Before lestephen.21, profile loading was duplicated three places:
#   - skills/skill-defensibility-pass/SKILL.md (prose loop)
#   - eki-kw/skills/_shared/profile-loading.md (prose loop)
#   - scripts/lib/provider-allowlist.sh::octo_disabled_set (bash for denylist subset)
# Drift was inevitable. This file is now the single source of truth.
#
# Usage (source it, then call the loader):
#   source "${HOME}/.claude-octopus/plugin/scripts/lib/load-octo-profile.sh"
#   octo_load_profile      # exports OCTO_PROFILE_PATH, OCTO_PROFILE_STATUS
#   echo "$OCTO_PROFILE_PATH"
#   echo "$OCTO_PROFILE_STATUS"  # loaded | template | missing | malformed
#
# Or in a one-shot script:
#   bash -c 'source .../load-octo-profile.sh; octo_load_profile; printenv | grep ^OCTO_PROFILE_'
#
# Search order (first match wins):
#   1. $OCTOPUS_KW_PROFILE     — explicit env var
#   2. ./.octopus/profile.yaml — project-local
#   3. $HOME/.config/octopus/profile.yaml — user-global (XDG-style)
#   4. $HOME/.claude-octopus/config/profile.yaml — alt user-global (legacy path)
#   5. $HOME/.claude/plugins/cache/*/eki-kw/profiles/default.yaml — installed plugin
#   6. $HOME/.claude/plugins/cache/*/profiles/default.yaml — any installed plugin profile

octo_load_profile() {
    local candidates=(
        "${OCTOPUS_KW_PROFILE:-}"
        "./.octopus/profile.yaml"
        "$HOME/.config/octopus/profile.yaml"
        "$HOME/.claude-octopus/config/profile.yaml"
    )

    # Plugin install paths via glob — expand and add to candidates
    local p
    for p in "$HOME/.claude/plugins/cache/"*"/eki-kw/profiles/default.yaml" \
             "$HOME/.claude/plugins/cache/"*"/profiles/default.yaml"; do
        [[ -f "$p" ]] && candidates+=("$p")
    done

    OCTO_PROFILE_PATH=""
    OCTO_PROFILE_STATUS="missing"

    for p in "${candidates[@]}"; do
        [[ -n "$p" && -f "$p" ]] || continue
        OCTO_PROFILE_PATH="$p"
        # Heuristic status check — look for placeholder markers
        if grep -q "<PLACEHOLDER" "$p" 2>/dev/null; then
            OCTO_PROFILE_STATUS="template"
        else
            # Validate it parses as YAML if python is around
            if command -v python3 >/dev/null 2>&1; then
                if ! python3 -c "import sys,yaml; yaml.safe_load(open('$p'))" 2>/dev/null; then
                    OCTO_PROFILE_STATUS="malformed"
                    OCTO_PROFILE_PATH=""
                    continue
                fi
            fi
            OCTO_PROFILE_STATUS="loaded"
        fi
        break
    done

    export OCTO_PROFILE_PATH OCTO_PROFILE_STATUS
    return 0
}

# Render a single-line status summary suitable for skill prose / doctor output:
#   "Profile: /path/to/profile.yaml (status: loaded)"
#   "Profile: (not found) — install via: ..."
octo_profile_status_line() {
    case "${OCTO_PROFILE_STATUS:-missing}" in
        loaded)    echo "Profile: $OCTO_PROFILE_PATH (status: loaded)" ;;
        template)  echo "Profile: $OCTO_PROFILE_PATH (status: template — placeholders present)" ;;
        malformed) echo "Profile: malformed (last attempted: $OCTO_PROFILE_PATH)" ;;
        missing|*) echo "Profile: not found — install: ln -s <yourrepo>/profile.yaml ~/.config/octopus/profile.yaml" ;;
    esac
}
