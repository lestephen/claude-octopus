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
    # lestephen.22 (critique #2 Codex F5): canonical octopus-native path
    # (~/.claude-octopus/config/profile.yaml) takes precedence over the
    # XDG path. This matches the documented "canonical" recommendation
    # in skill-defensibility-pass and keeps a stale XDG profile from
    # overriding the recommended location.
    local candidates=(
        "${OCTOPUS_KW_PROFILE:-}"
        "./.octopus/profile.yaml"
        "$HOME/.claude-octopus/config/profile.yaml"
        "$HOME/.config/octopus/profile.yaml"
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
            # lestephen.22 (codex F3 — critique #2 finding): if the highest-
            # priority profile is malformed, STOP and report malformed —
            # don't silently fall through to a lower-priority profile.
            # A user with a malformed high-priority profile expects that
            # to be the active one; loading a stale default would use the
            # wrong audience matrix / banned terms.
            # lestephen.22 (codex F4): only validate YAML when PyYAML is
            # actually importable; many default python3 installs lack it.
            if command -v python3 >/dev/null 2>&1 \
               && python3 -c "import yaml" 2>/dev/null; then
                if ! python3 - "$p" <<'PYEOF' 2>/dev/null
import sys, yaml
yaml.safe_load(open(sys.argv[1]))
PYEOF
                then
                    OCTO_PROFILE_STATUS="malformed"
                    # Per critique F3: preserve PATH for user diagnosis;
                    # STOP iteration so lower-priority profiles don't mask the failure
                    break
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
        missing|*) echo "Profile: not found — install: ln -s <yourrepo>/profile.yaml ~/.claude-octopus/config/profile.yaml" ;;
    esac
}
