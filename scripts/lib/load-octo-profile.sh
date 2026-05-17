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

# octo_validate_profile <path> — check that the profile has the keys
# skill-defensibility-pass actually consumes. Without these, "defensibility"
# is theater (lestephen.31, closes GH #4).
#
# Required keys (minimal schema):
#   - audiences: object (at least one audience key)
#   - banned_terms: array (may be empty, but must be present)
#   - internal_codenames: array (may be empty, but must be present)
#
# Optional keys (consumed if present, not required):
#   - banned_wording: array of {pattern, reason}
#   - audiences.<name>.tone, audiences.<name>.banned_phrases
#
# Returns: 0 if all required keys present, 1 if any missing.
# Sets: OCTO_PROFILE_MISSING_KEYS to comma-separated list of missing keys.
octo_validate_profile() {
    local _path="$1"
    OCTO_PROFILE_MISSING_KEYS=""

    if [[ ! -f "$_path" ]]; then
        OCTO_PROFILE_MISSING_KEYS="<file-not-found>"
        return 1
    fi

    # Prefer python+yaml (already-checked-importable in octo_load_profile);
    # accept also yq if installed.
    if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
        local _result
        _result=$(python3 - "$_path" <<'PYEOF' 2>/dev/null
import sys, yaml
try:
    data = yaml.safe_load(open(sys.argv[1]))
except Exception as e:
    print(f"unparseable: {e}")
    sys.exit(2)
if not isinstance(data, dict):
    print("top-level-not-object")
    sys.exit(2)
required_object_keys = ["audiences"]
required_array_keys = ["banned_terms", "internal_codenames"]
missing = []
for k in required_object_keys:
    if k not in data or not isinstance(data[k], dict) or not data[k]:
        missing.append(k)
for k in required_array_keys:
    if k not in data or not isinstance(data[k], list):
        missing.append(k)
if missing:
    print(",".join(missing))
    sys.exit(1)
print("ok")
PYEOF
        )
        local _rc=$?
        if [[ $_rc -eq 0 && "$_result" == "ok" ]]; then
            return 0
        else
            OCTO_PROFILE_MISSING_KEYS="$_result"
            return 1
        fi
    elif command -v yq >/dev/null 2>&1; then
        # yq fallback — but with EXPLICIT checks that match the python branch
        # (lestephen.31 v2 consensus SEV-2: bare `yq -e ".audiences"` accepted
        # empty `audiences: {}` while python rejected it; host-dependent
        # validity is a footgun). Use the same emptiness/type predicates.
        local _missing=""
        # audiences: must be an object with at least one key
        if ! yq -e '.audiences | type == "!!map" and length > 0' "$_path" >/dev/null 2>&1; then
            _missing+="audiences"
        fi
        # banned_terms: must be an array (may be empty)
        if ! yq -e '.banned_terms | type == "!!seq"' "$_path" >/dev/null 2>&1; then
            _missing+="${_missing:+,}banned_terms"
        fi
        # internal_codenames: must be an array (may be empty)
        if ! yq -e '.internal_codenames | type == "!!seq"' "$_path" >/dev/null 2>&1; then
            _missing+="${_missing:+,}internal_codenames"
        fi
        if [[ -n "$_missing" ]]; then
            OCTO_PROFILE_MISSING_KEYS="$_missing"
            return 1
        fi
        return 0
    else
        # No validator available — signal explicitly so the caller can decide
        # whether to gate. Returns rc=2 (distinct from "missing keys" rc=1)
        # so callers can tell "validator missing" apart from "validation failed".
        OCTO_PROFILE_MISSING_KEYS="<validator-unavailable: install python3-yaml or yq>"
        return 2
    fi
}

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
    OCTO_PROFILE_MISSING_KEYS=""

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
            # lestephen.31 (closes GH #4): YAML parses, but does it have the
            # required keys? Surface schema gaps explicitly so callers don't
            # produce degraded output thinking they have a complete profile.
            octo_validate_profile "$p"
            local _val_rc=$?
            case $_val_rc in
                0) OCTO_PROFILE_STATUS="loaded" ;;
                2) OCTO_PROFILE_STATUS="unvalidated" ;;  # validator unavailable; treat as cautiously-present
                *) OCTO_PROFILE_STATUS="incomplete" ;;
            esac
            if [[ "$OCTO_PROFILE_STATUS" == "incomplete" ]]; then
                # Don't fall through to lower-priority — same rationale as
                # the malformed branch above (user expects this profile to
                # be active; a stale default would silently override).
                break
            fi
        fi
        break
    done

    export OCTO_PROFILE_PATH OCTO_PROFILE_STATUS OCTO_PROFILE_MISSING_KEYS

    # Return code policy (lestephen.31 v2 consensus SEV-2 fix to rc-contract
    # backward-compat concern):
    #   rc=0: loaded (fully validated) OR unvalidated (couldn't validate, but
    #         present — callers may opt to halt by inspecting STATUS)
    #   rc=0: missing / template — these were rc=0 in pre-patch behavior;
    #         scripts under `set -e` that handled "no profile yet" via STATUS
    #         continue to work.
    #   rc=1: malformed / incomplete — actively broken profile, callers SHOULD
    #         halt. These are the new "fail-loud" cases the GH #4 patch adds.
    case "$OCTO_PROFILE_STATUS" in
        malformed|incomplete) return 1 ;;
        *)                    return 0 ;;
    esac
}

# Render a single-line status summary suitable for skill prose / doctor output:
#   "Profile: /path/to/profile.yaml (status: loaded)"
#   "Profile: (not found) — install via: ..."
octo_profile_status_line() {
    case "${OCTO_PROFILE_STATUS:-missing}" in
        loaded)      echo "Profile: $OCTO_PROFILE_PATH (status: loaded)" ;;
        unvalidated) echo "Profile: $OCTO_PROFILE_PATH (status: unvalidated — install python3+yaml or yq to enable schema check)" ;;
        template)    echo "Profile: $OCTO_PROFILE_PATH (status: template — placeholders present)" ;;
        malformed)   echo "Profile: malformed (last attempted: $OCTO_PROFILE_PATH)" ;;
        incomplete)  echo "Profile: $OCTO_PROFILE_PATH (status: incomplete — missing keys: ${OCTO_PROFILE_MISSING_KEYS:-unknown})" ;;
        missing|*)   echo "Profile: not found — install: ln -s <yourrepo>/profile.yaml ~/.claude-octopus/config/profile.yaml" ;;
    esac
}
