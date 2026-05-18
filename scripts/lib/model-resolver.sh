#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION v3.0: Unified Model Resolver (v8.50.0)
# Consolidated logic for provider, phase, and role-based model selection.
# Precedence: Env Var > Session Override > Phase/Role Routing > Capability > Tier > Defaults
# Extracted from orchestrate.sh — v9.7.5
# ═══════════════════════════════════════════════════════════════════════════════

_model_resolver_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f _is_cursor_agent_binary >/dev/null 2>&1; then
    source "${_model_resolver_lib_dir}/cursor-agent.sh" 2>/dev/null || true
fi
if ! declare -f is_claude_agent_type >/dev/null 2>&1; then
    source "${_model_resolver_lib_dir}/routing.sh" 2>/dev/null || true
fi
if ! declare -f is_claude_agent_type >/dev/null 2>&1; then
    is_claude_agent_type() {
        case "${1:-}" in
            claude|claude-*) return 0 ;;
            *) return 1 ;;
        esac
    }
fi

# v9.23.0: Opus default picker — prefers 4.7 when host supports it, falls back to 4.6.
# Respects OCTOPUS_OPUS_MODEL override (user-pinned version).
opus_default_model() {
    if [[ -n "${OCTOPUS_OPUS_MODEL:-}" ]]; then
        echo "$OCTOPUS_OPUS_MODEL"
        return 0
    fi
    # SUPPORTS_OPUS_4_7 is detected from Claude Code v2.1.111+ — see lib/providers.sh
    if [[ "${SUPPORTS_OPUS_4_7:-false}" == "true" ]]; then
        echo "claude-opus-4.7"
    else
        echo "claude-opus-4.6"
    fi
}

# resolve_octopus_model <provider> <agent_type> <phase> <role>
resolve_octopus_model() {
    local provider="$1"
    local agent_type="$2"
    local phase="${3:-}"
    local role="${4:-}"
    local config_file="${HOME}/.claude-octopus/config/providers.json"
    local resolved_model=""

    # 0. Session Cache (v8.53.0)
    # Uses a process-local memory cache + optional file-based cache for cross-process speed
    local cache_key
    # v8.49.0: Field-delimited cache key prevents collisions
    # (e.g., provider="codex" + type="spark" must differ from type="codex-spark")
    local safe_p="${provider//[^a-zA-Z0-9]/_}"
    local safe_a="${agent_type//[^a-zA-Z0-9]/_}"
    local safe_ph="${phase//[^a-zA-Z0-9]/_}"
    local safe_r="${role//[^a-zA-Z0-9]/_}"
    cache_key="MC_${safe_p}_A_${safe_a}_P_${safe_ph}_R_${safe_r}"
    local cached_val
    eval "cached_val=\"\${_OCTO_MODEL_CACHE_${cache_key}:-}\""
    if [[ -n "$cached_val" ]]; then
        echo "$cached_val"
        return 0
    fi

    # Persistent File Cache (optional, for parallel execution speed)
    local persistent_cache="/tmp/octo-model-cache-${USER:-${USERNAME:-unknown}}-${CLAUDE_CODE_SESSION:-global}.json"
    # v8.49.0: Invalidate cache if config file changed since cache was written
    if [[ -f "$persistent_cache" && -f "$config_file" && "$config_file" -nt "$persistent_cache" ]]; then
        rm -f "$persistent_cache"
    fi
    if [[ -f "$persistent_cache" ]] && command -v jq &>/dev/null; then
        cached_val=$(jq -r ".\"$cache_key\" // empty" "$persistent_cache" 2>/dev/null)
        if [[ -n "$cached_val" && "$cached_val" != "null" ]]; then
            # Sanitize before eval: strip shell metacharacters (model names are alphanumeric + .:/-_)
            cached_val="${cached_val//[^a-zA-Z0-9._:\/\-]/}"
            eval "_OCTO_MODEL_CACHE_${cache_key}=\"\$cached_val\""
            echo "$cached_val"
            return 0
        fi
    fi

    # v8.49.0: Resolution trace for debugging model selection
    local _trace="${OCTOPUS_TRACE_MODELS:-}"
    [[ -n "$_trace" ]] && echo "[model-trace] Resolving: provider=$provider type=$agent_type phase=${phase:-<none>} role=${role:-<none>}" >&2

    # 1. Force/Session Overrides (Env vars)
    local env_var="OCTOPUS_$(echo "$provider" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_MODEL"
    if [[ -n "${!env_var:-}" ]]; then
        resolved_model="${!env_var}"
        [[ -n "$_trace" ]] && echo "[model-trace] Tier 1 (env $env_var): ${!env_var} ← SELECTED" >&2
    elif [[ -n "$_trace" ]]; then
        echo "[model-trace] Tier 1 (env $env_var): —" >&2
    fi

    # v8.41.0 Priority 0.5: Check native CC model settings
    if [[ -z "$resolved_model" && "$provider" == "claude" && -n "${CLAUDE_MODEL:-}" ]]; then
        resolved_model="${CLAUDE_MODEL}"
        [[ -n "$_trace" ]] && echo "[model-trace] Tier 0.5 (CC native CLAUDE_MODEL): $CLAUDE_MODEL ← SELECTED" >&2
    fi

    # Config file lookups
    if [[ -z "$resolved_model" && -f "$config_file" ]] && command -v jq &> /dev/null; then
        # Load config once for this resolution tree
        local config_data
        config_data=$(<"$config_file")

        # Priority 1b: Session-only config overrides
        resolved_model=$(echo "$config_data" | jq -r ".overrides.${provider} // empty" 2>/dev/null)
        if [[ -n "$resolved_model" && "$resolved_model" != "null" ]]; then
            [[ -n "$_trace" ]] && echo "[model-trace] Tier 2 (session override): $resolved_model ← SELECTED" >&2
        else
            [[ -n "$_trace" ]] && echo "[model-trace] Tier 2 (session override): —" >&2
        fi

        # 2. Phase/Role Routing
        if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
            local routed=""
            if [[ -n "$phase" ]]; then
                routed=$(echo "$config_data" | jq -r ".routing.phases.\"${phase}\" // empty" 2>/dev/null)
            fi
            if [[ -z "$routed" || "$routed" == "null" ]] && [[ -n "$role" ]]; then
                routed=$(echo "$config_data" | jq -r ".routing.roles.\"${role}\" // empty" 2>/dev/null)
            fi

            # Handle recursive reference (e.g. "codex:spark")
            # v9.17.1: Skip cross-provider routing — if route targets a different provider,
            # don't apply its model to the current provider (fixes #235 item 3)
            # lestephen.14: Same cross-provider skip for bare-provider form
            # (e.g. role=researcher routed to bare "perplexity"). Previously the
            # bare-provider branch had no safety check and would assign the wrong
            # provider name as the model for the current provider's dispatch.
            if [[ -n "$routed" && "$routed" != "null" ]]; then
                if [[ "$routed" == *:* ]]; then
                    local ref_provider="${routed%%:*}"
                    local ref_type="${routed#*:}"
                    if [[ "$ref_provider" != "$provider" ]]; then
                        # Route targets a different provider — skip for this resolution
                        [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): SKIP (route $routed targets $ref_provider, resolving for $provider)" >&2
                        routed=""
                    else
                        resolved_model=$(resolve_octopus_model "$ref_provider" "$ref_type" "" "")
                    fi
                else
                    # Bare value — could be:
                    #   (a) a known bare provider name (e.g. "perplexity") — treat as provider ref
                    #   (b) an agent_type with capability suffix (e.g. "gemini-fast", "claude-opus")
                    #       — treat as provider:capability reference and recurse
                    #   (c) a literal model name (e.g. "gpt-5.5", "sonar-pro")
                    # lestephen.22 (F4): Previously only (a) was handled; (b) fell through to
                    # (c) and got assigned as a literal model name, handing the wrong provider
                    # the wrong string.
                    bare_provider=""
                    # Source the helper if available. lestephen.22 (critique
                    # #2 Codex F1): prefer the BASH_SOURCE-relative path so
                    # the resolver works correctly when run from a repo
                    # checkout or test harness, not just from the installed
                    # plugin path. Falls back to the installed path.
                    if ! declare -f octo_provider_for_agent_type >/dev/null 2>&1; then
                        _mr_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P 2>/dev/null)"
                        if [[ -n "$_mr_self_dir" && -f "$_mr_self_dir/provider-allowlist.sh" ]]; then
                            # shellcheck disable=SC1091
                            source "$_mr_self_dir/provider-allowlist.sh" 2>/dev/null
                        elif [[ -f "${HOME}/.claude-octopus/plugin/scripts/lib/provider-allowlist.sh" ]]; then
                            # shellcheck disable=SC1091
                            source "${HOME}/.claude-octopus/plugin/scripts/lib/provider-allowlist.sh" 2>/dev/null
                        fi
                        unset _mr_self_dir
                    fi
                    if declare -f octo_provider_for_agent_type >/dev/null 2>&1; then
                        bare_provider="$(octo_provider_for_agent_type "$routed")"
                    fi

                    if [[ -n "$bare_provider" ]]; then
                        # (a) or (b) — `routed` is a recognized agent_type
                        if [[ "$bare_provider" != "$provider" ]]; then
                            [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): SKIP (bare '$routed' resolves to provider '$bare_provider', different from '$provider')" >&2
                            routed=""
                        elif [[ "$routed" == "$provider" ]]; then
                            # (a) — exact provider match — fall through to capability/default
                            [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): bare provider '$routed' matches current provider; falling through to capability/default" >&2
                            routed=""
                        else
                            # (b) — agent_type with capability, same provider — recurse
                            [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): bare agent_type '$routed' resolves to same provider — recursing" >&2
                            resolved_model=$(resolve_octopus_model "$provider" "$routed" "" "")
                        fi
                    else
                        # (c) — not a known provider/agent_type; treat as literal model name
                        resolved_model="$routed"
                    fi
                fi
                if [[ -n "$routed" ]]; then
                    [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): $resolved_model ← SELECTED (route: $routed)" >&2
                fi
            else
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 3 (phase/role routing): —" >&2
            fi
        fi

        # 3. Capability Mapping (providers.codex.spark, etc)
        if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
            local capability=""
            if [[ "$agent_type" == *-* ]]; then
                capability="${agent_type#*-}"
            else
                capability="$agent_type"
            fi

            if [[ -n "$capability" && "$capability" != "$provider" ]]; then
                # Support both short capability (spark) and full model aliases (spark_model)
                # lestephen.21 (F5): use --arg for hyphenated provider names (e.g. cursor-agent).
                # jq treats `.providers.cursor-agent` as a subtraction operator, not a key access.
                resolved_model=$(echo "$config_data" | jq -r --arg p "$provider" --arg c "$capability" '.providers[$p][$c] // .providers[$p][$c+"_model"] // empty' 2>/dev/null)
            fi
            if [[ -n "$resolved_model" && "$resolved_model" != "null" ]]; then
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 4 (capability map): $resolved_model ← SELECTED (cap: ${capability:-none})" >&2
            else
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 4 (capability map): —" >&2
            fi
        fi

        # 4. Tier Mapping
        if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
            if [[ -n "${OCTOPUS_COST_MODE:-}" && "${OCTOPUS_COST_MODE:-}" != "standard" ]]; then
                resolved_model=$(echo "$config_data" | jq -r ".tiers.\"${OCTOPUS_COST_MODE}\".\"${provider}\" // empty" 2>/dev/null)
                if [[ -n "$resolved_model" && "$resolved_model" =~ ^[a-z_]+$ ]]; then
                    # Capability ref in tier map
                    local tier_mapped_model
                    tier_mapped_model=$(echo "$config_data" | jq -r ".providers.\"${provider}\".\"${resolved_model}\" // .providers.\"${provider}\".\"${resolved_model}_model\" // empty" 2>/dev/null)
                    [[ -n "$tier_mapped_model" && "$tier_mapped_model" != "null" ]] && resolved_model="$tier_mapped_model"
                fi
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 5 (cost mode ${OCTOPUS_COST_MODE}): ${resolved_model:-—}" >&2
            fi
        fi

        # 5. Global Defaults
        if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
            # lestephen.21 (F5): use --arg for hyphenated provider names
            resolved_model=$(echo "$config_data" | jq -r --arg p "$provider" '.providers[$p].default // .providers[$p].model // empty' 2>/dev/null)
            if [[ -n "$resolved_model" && "$resolved_model" != "null" ]]; then
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 6 (config default): $resolved_model ← SELECTED" >&2
            else
                [[ -n "$_trace" ]] && echo "[model-trace] Tier 6 (config default): —" >&2
            fi
        fi
    fi

    # Fallback to hard-coded defaults (Priority 7)
    if [[ -z "$resolved_model" || "$resolved_model" == "null" ]]; then
        case "$agent_type" in
            codex*)          resolved_model="gpt-5.4" ;;
            gemini-fast|gemini-flash) resolved_model="gemini-3-flash-preview" ;;
            gemini*)         resolved_model="gemini-3.1-pro-preview" ;;
            claude-opus-legacy*) resolved_model="claude-opus-4.6" ;;
            claude-opus*)    resolved_model="$(opus_default_model)" ;;
            claude*)         resolved_model="claude-sonnet-4.6" ;;
            perplexity-fast)  resolved_model="sonar" ;;
            perplexity*)       resolved_model="sonar-pro" ;;
            openrouter-glm*)  resolved_model="z-ai/glm-5" ;;
            openrouter-kimi*) resolved_model="moonshotai/kimi-k2.5" ;;
            openrouter-deepseek*) resolved_model="deepseek/deepseek-r1-0528" ;;
            ollama*)         resolved_model="llama3.3" ;;
            copilot*)        resolved_model="claude-sonnet-4.5" ;; # Copilot default; actual model selected by copilot CLI
            qwen*)           resolved_model="qwen3-coder" ;;
            cursor-agent*)   resolved_model="grok-4-20" ;;
            opencode-research*) resolved_model="z-ai/glm-5.1" ;;
            opencode-fast*)  resolved_model="google/gemini-2.5-flash" ;;
            opencode*)       resolved_model="google/gemini-2.5-flash" ;;
            *)              resolved_model="gpt-5.4" ;; # Safest universal fallback
        esac
        [[ -n "$_trace" ]] && echo "[model-trace] Tier 7 (hardcoded fallback): $resolved_model ← SELECTED" >&2
    fi

    [[ -n "$_trace" ]] && echo "[model-trace] ► Result: $resolved_model" >&2

    # Update memory and persistent cache
    # Use \$var to prevent double-expansion; resolved_model is internally computed but defensive quoting is cheap
    eval "_OCTO_MODEL_CACHE_${cache_key}=\"\$resolved_model\""
    if command -v jq &>/dev/null; then
        local cache_json="{}"
        # Self-heal: reject unreadable, concatenated-JSON, or non-object payloads.
        # Plain `jq -e .` accepts `{}\n{}` as a valid stream — the exact
        # concurrent-writer artifact this gate exists to heal. Slurp to count.
        if cache_json=$(<"$persistent_cache") 2>/dev/null && [[ -n "$cache_json" ]]; then
            cache_json=$(jq -cse 'if length == 1 and (.[0] | type) == "object" then .[0] else error("invalid") end' \
                         <<<"$cache_json" 2>/dev/null) || cache_json="{}"
        else
            cache_json="{}"
        fi
        echo "$cache_json" | jq --arg key "$cache_key" --arg val "$resolved_model" '.[$key] = $val' > "${persistent_cache}.tmp.$$" 2>/dev/null && mv "${persistent_cache}.tmp.$$" "$persistent_cache"
    fi

    echo "$resolved_model"
}

# ── Extracted from orchestrate.sh ──
# Validate model name to prevent shell injection and other malformed inputs
validate_model_name() {
    local model="$1"
    
    # Reject empty names
    [[ -z "$model" ]] && return 1
    
    # Reject names with shell meta-characters (v8.50.0 Security hardening)
    if [[ "$model" =~ [[:space:]\;\|\&\$\`\'\"()\<\>\!*?\[\]\{\}$'\n'$'\r'] ]]; then
        return 1
    fi
    
    # Reject names that look like absolute paths
    if [[ "$model" == /* ]]; then
        return 1
    fi
    
    return 0
}


# ── v2 agent helpers (moved from orchestrate.sh v9.22.1) ──
is_agent_available_v2() {
    local agent="$1"

    # Load config if needed
    [[ -z "$PROVIDER_CODEX_INSTALLED" ]] && load_providers_config

    if is_claude_agent_type "$agent"; then
        [[ "$PROVIDER_CLAUDE_INSTALLED" == "true" ]]
        return
    fi

    case "$agent" in
        codex|codex-standard|codex-mini|codex-max|codex-general|codex-review|codex-spark|codex-reasoning|codex-large-context)
            [[ "$PROVIDER_CODEX_INSTALLED" == "true" && "$PROVIDER_CODEX_AUTH_METHOD" != "none" ]]
            ;;
        gemini|gemini-fast|gemini-image)
            # lestephen.50 (closes GH #28): use centralized dispatch
            # allowlist. PROVIDER_GEMINI_AUTH_METHOD is populated by
            # detect_providers/save_user_config which now all use the
            # centralized resolver, so values are one of: api-key, oauth,
            # keychain, stale-blob, none.
            if [[ "$PROVIDER_GEMINI_INSTALLED" != "true" ]]; then
                false
            elif declare -f octo_gemini_dispatch_allowed >/dev/null 2>&1; then
                octo_gemini_dispatch_allowed "$PROVIDER_GEMINI_AUTH_METHOD"
            else
                # Inline fallback — explicit allowlist same as the helper.
                case "$PROVIDER_GEMINI_AUTH_METHOD" in
                    api-key|oauth|keychain) true ;;
                    *) false ;;
                esac
            fi
            ;;
        openrouter|openrouter-*)
            [[ "$PROVIDER_OPENROUTER_ENABLED" == "true" && "$PROVIDER_OPENROUTER_API_KEY_SET" == "true" ]]
            ;;
        perplexity|perplexity-fast)
            [[ -n "${PERPLEXITY_API_KEY:-}" ]]
            ;;
        ollama*)
            command -v ollama &>/dev/null && curl -sf http://localhost:11434/api/tags &>/dev/null
            ;;
        copilot|copilot-research)
            command -v copilot &>/dev/null && {
                [[ -n "${COPILOT_GITHUB_TOKEN:-}" ]] || [[ -n "${GH_TOKEN:-}" ]] || \
                [[ -n "${GITHUB_TOKEN:-}" ]] || [[ -f "${HOME}/.copilot/config.json" ]] || \
                { command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; }
            }
            ;;
        qwen|qwen-research)
            command -v qwen &>/dev/null && {
                [[ -f "${HOME}/.qwen/oauth_creds.json" ]] || \
                [[ -f "${HOME}/.qwen/config.json" ]] || \
                [[ -n "${QWEN_API_KEY:-}" ]]
            }
            ;;
        opencode|opencode-fast|opencode-research)
            [[ "$PROVIDER_OPENCODE_INSTALLED" == "true" && "$PROVIDER_OPENCODE_AUTH_METHOD" != "none" ]]
            ;;
        cursor-agent|cursor-agent-*)
            declare -f _is_cursor_agent_binary >/dev/null 2>&1 && _is_cursor_agent_binary && {
                [[ -n "${CURSOR_API_KEY:-}" ]] || \
                grep -Eq '"authInfo"[[:space:]]*:[[:space:]]*\{' "${HOME}/.cursor/cli-config.json" 2>/dev/null
            }
            ;;
        *)
            return 0  # Unknown agents assumed available
            ;;
    esac
}

get_fallback_agent() {
    local preferred="$1"
    local task_type="$2"

    if is_agent_available "$preferred"; then
        echo "$preferred"
        return 0
    fi

    # Fallback logic (v8.9.0: extended with spark, reasoning, large-context fallbacks)
    case "$preferred" in
        gemini|gemini-fast)
            # Gemini unavailable, try codex
            if is_agent_available "codex"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: $preferred -> codex (no Gemini)" || true
                echo "codex"
            else
                echo "$preferred"  # Return anyway, will error
            fi
            ;;
        codex|codex-standard|codex-mini)
            # Codex unavailable, try gemini
            if is_agent_available "gemini"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: $preferred -> gemini (no OpenAI)" || true
                echo "gemini"
            else
                echo "$preferred"
            fi
            ;;
        codex-spark)
            # Spark unavailable or unsupported → fall back to standard codex → gemini
            if is_agent_available "codex"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: codex-spark -> codex (spark unavailable)" || true
                echo "codex"
            elif is_agent_available "gemini"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: codex-spark -> gemini (no OpenAI)" || true
                echo "gemini"
            else
                echo "$preferred"
            fi
            ;;
        codex-reasoning)
            # Reasoning model unavailable → fall back to codex (deep reasoning) → gemini
            if is_agent_available "codex"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: codex-reasoning -> codex (reasoning unavailable)" || true
                echo "codex"
            elif is_agent_available "gemini"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: codex-reasoning -> gemini (no OpenAI)" || true
                echo "gemini"
            else
                echo "$preferred"
            fi
            ;;
        codex-large-context)
            # Large context unavailable → fall back to codex (400K ctx) → gemini
            if is_agent_available "codex"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: codex-large-context -> codex (large-ctx unavailable)" || true
                echo "codex"
            elif is_agent_available "gemini"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: codex-large-context -> gemini (no OpenAI)" || true
                echo "gemini"
            else
                echo "$preferred"
            fi
            ;;
        openrouter-glm5|openrouter-kimi|openrouter-deepseek)
            # v8.11.0: Model-specific OpenRouter → generic openrouter → codex → gemini
            if is_agent_available "openrouter"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: $preferred -> openrouter (model-specific unavailable)" || true
                echo "openrouter"
            elif is_agent_available "codex"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: $preferred -> codex (no OpenRouter)" || true
                echo "codex"
            elif is_agent_available "gemini"; then
                [[ "$VERBOSE" == "true" ]] && log DEBUG "Fallback: $preferred -> gemini (no OpenRouter/OpenAI)" || true
                echo "gemini"
            else
                echo "$preferred"
            fi
            ;;
        *)
            echo "$preferred"
            ;;
    esac
}
