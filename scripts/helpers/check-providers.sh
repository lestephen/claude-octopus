#!/usr/bin/env bash
# Claude Octopus — Provider Availability Check
# Single-source script for checking which AI providers are available.
# Used by skills (via Bash tool) to populate the activation banner.
#
# Output format (lestephen.45 — closes GH #5):
#   <name>:available:<capabilities>
#   <name>:missing
#
# capabilities is a comma-separated list. Currently emitted:
#   text          — text-only via headless CLI
#   text,vision   — text + image-attachment vision via headless CLI
#                   (verified empirically per lestephen.24 retest)
#
# Backward compat: legacy consumers that grep for ":available" still match
# (substring match on "provider:available:text"). New consumers can filter
# on the "vision" capability mechanically:
#   check-providers.sh | grep ',vision' | cut -d: -f1
# (the comma anchors against the comma-separated caps list so we don't
# match a hypothetical future provider named "visionary".)
#
# Override: set OCTO_PROVIDER_VISION=comma,separated,list to promote
# listed providers to text,vision without editing this map (ad-hoc tests).
#
# Exit code: always 0 (availability is informational, not an error).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Self-heal: ensure ~/.claude-octopus/plugin symlink exists before proceeding.
# Marketplace installs may not have the symlink yet if SessionStart hook hasn't
# fired. This is a no-op when the symlink is already healthy. (fixes #377)
bash "${SCRIPT_DIR}/ensure-plugin-root.sh" 2>/dev/null || true

source "${SCRIPT_DIR}/../lib/cursor-agent.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/provider-allowlist.sh" 2>/dev/null || true

# Capability map per provider. Conservative default: text. Vision listed
# only for providers verified empirically (lestephen.24 vision retest:
# both gemini and claude --print see images via path-reference in prompt
# body; codex via -i flag). Unverified providers get text only.
_octo_provider_caps() {
    local provider="$1"
    local caps
    case "$provider" in
        codex|claude|gemini) caps="text,vision" ;;
        copilot|qwen|opencode|cursor-agent|perplexity|ollama|openrouter)
            caps="text" ;;
        *) caps="text" ;;
    esac
    # OCTO_PROVIDER_VISION override: comma-separated provider names that
    # the operator has manually verified for vision. Adds "vision" to the
    # caps list without editing the case above.
    if [[ -n "${OCTO_PROVIDER_VISION:-}" ]]; then
        local _v
        IFS=',' read -r -a _v <<< "$OCTO_PROVIDER_VISION"
        for _p in "${_v[@]}"; do
            if [[ "$_p" == "$provider" && ",${caps}," != *",vision,"* ]]; then
                caps="${caps},vision"
            fi
        done
    fi
    echo "$caps"
}

provider_status() {
    local provider="$1"
    local status="$2"
    if declare -f octo_provider_allowed >/dev/null 2>&1 && ! octo_provider_allowed "$provider"; then
        status="missing"
    fi
    if [[ "$status" == "available" ]]; then
        printf "%s:%s:%s\n" "$provider" "$status" "$(_octo_provider_caps "$provider")"
    else
        printf "%s:%s\n" "$provider" "$status"
    fi
}

cursor_agent_status="missing"
if { ! declare -f octo_provider_allowed >/dev/null 2>&1 || octo_provider_allowed "cursor-agent"; } && \
   declare -f _is_cursor_agent_binary >/dev/null 2>&1 && _is_cursor_agent_binary && \
   { [ -n "${CURSOR_API_KEY:-}" ] || grep -Eq '"authInfo"[[:space:]]*:[[:space:]]*\{' "${HOME}/.cursor/cli-config.json" 2>/dev/null; }; then
    cursor_agent_status="available"
fi

echo "PROVIDER_CHECK_START"
provider_status "codex" "$(command -v codex >/dev/null 2>&1 && echo available || echo missing)"
provider_status "gemini" "$(command -v gemini >/dev/null 2>&1 && echo available || echo missing)"
provider_status "perplexity" "$([ -n "${PERPLEXITY_API_KEY:-}" ] && echo available || echo missing)"
provider_status "opencode" "$(command -v opencode >/dev/null 2>&1 && echo available || echo missing)"
provider_status "copilot" "$(command -v copilot >/dev/null 2>&1 && echo available || echo missing)"
provider_status "qwen" "$(command -v qwen >/dev/null 2>&1 && echo available || echo missing)"
provider_status "cursor-agent" "$cursor_agent_status"
provider_status "ollama" "$({ ! declare -f octo_provider_allowed >/dev/null 2>&1 || octo_provider_allowed "ollama"; } && command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && echo available || echo missing)"
provider_status "openrouter" "$([ -n "${OPENROUTER_API_KEY:-}" ] && echo available || echo missing)"
echo "PROVIDER_CHECK_END"
