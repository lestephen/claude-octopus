#!/usr/bin/env bash
# image-attach.sh — Shared --image plumbing for probe_single_agent,
# spawn_agent, and run_agent_sync (closes GH #14).
#
# When OCTO_AGENT_IMAGES env var is set (newline-separated list of absolute
# image paths), this helper:
#
#   1. Appends an "Attached images" block listing the paths to the prompt
#      body — universal mechanism that works for codex, claude --print, and
#      gemini headless (all read referenced paths from the prompt body, per
#      lestephen.24 retest).
#
#   2. For codex agents, ALSO splices `-i <path>` flags into the cmd_array
#      before the trailing `-` stdin marker. Belt-and-suspenders: codex sees
#      the image via both channels, and the -i splice survives any future
#      prompt-body rewriting.
#
# This helper was extracted from probe_single_agent during the GH #14 work
# so all three call sites (probe-single, spawn_agent, run_agent_sync) handle
# images the same way. Previously only probe_single_agent had the logic,
# which meant /octo:review's Round 1 fleet (spawn_agent) and Rounds 2-3
# (run_agent_sync) couldn't attach pixels even when the review profile had
# a `reference` field set.
#
# Usage (call AFTER cmd_array is built, BEFORE result-file header write):
#
#   _img_note=""
#   octo_attach_images "$agent_type" enhanced_prompt cmd_array _img_note
#
# enhanced_prompt and cmd_array are passed by NAME (bash nameref). The
# function mutates both in place. _img_note returns a one-line note suitable
# for the result-file header (e.g. "# Images attached (codex -i + prompt-body
# paths): /tmp/foo.png").
#
# When OCTO_AGENT_IMAGES is unset/empty, the function is a no-op.

octo_attach_images() {
    local agent_type="$1"
    local -n _prompt_ref="$2"     # nameref to caller's enhanced_prompt
    local -n _cmd_array_ref="$3"  # nameref to caller's cmd_array
    local -n _note_ref="$4"       # nameref to caller's image-note variable

    _note_ref=""
    [[ -z "${OCTO_AGENT_IMAGES:-}" ]] && return 0

    local -a _image_files=()
    mapfile -t _image_files <<< "$OCTO_AGENT_IMAGES"
    # Drop empty trailing element from trailing newline
    local _last_idx=$(( ${#_image_files[@]} - 1 ))
    [[ $_last_idx -ge 0 && -z "${_image_files[$_last_idx]}" ]] && unset '_image_files[$_last_idx]'
    [[ ${#_image_files[@]} -eq 0 ]] && return 0

    local _img _missing=0 _missing_files=""
    for _img in "${_image_files[@]}"; do
        if [[ ! -f "$_img" ]]; then
            type log >/dev/null 2>&1 && log "WARN" "octo_attach_images: --image path missing: $_img"
            _missing=1
            _missing_files+="${_img} "
        fi
    done

    # Universal: append "Attached images" block to prompt body
    local _files_listed
    _files_listed=$(printf '%s\n' "${_image_files[@]}" | sed 's/^/  - /')
    _prompt_ref="${_prompt_ref}

---

Attached images (paths — your provider's CLI will read these for vision):
${_files_listed}"

    # Codex belt-and-suspenders: splice -i flags before trailing '-'
    case "$agent_type" in
        codex|codex-standard|codex-max|codex-mini|codex-general|codex-spark|codex-reasoning|codex-large-context|codex-review)
            if [[ $_missing -eq 0 ]]; then
                local _last="${_cmd_array_ref[-1]}"
                if [[ "$_last" == "-" ]]; then
                    unset '_cmd_array_ref[-1]'
                    for _img in "${_image_files[@]}"; do
                        _cmd_array_ref+=(-i "$_img")
                    done
                    _cmd_array_ref+=("-")
                else
                    # Defensive — if codex command shape changes upstream and
                    # no longer ends with '-', append -i flags at the end.
                    for _img in "${_image_files[@]}"; do
                        _cmd_array_ref+=(-i "$_img")
                    done
                fi
                _note_ref="# Images attached (codex -i + prompt-body paths): $(printf '%s ' "${_image_files[@]}")"
            else
                _note_ref="# Images requested but missing on disk: ${_missing_files}— dispatched without -i (paths still in prompt body)"
            fi
            ;;
        *)
            if [[ $_missing -eq 0 ]]; then
                _note_ref="# Images attached (prompt-body paths): $(printf '%s ' "${_image_files[@]}")"
            else
                _note_ref="# Images requested but missing on disk: ${_missing_files}— provider may flag the missing files"
            fi
            ;;
    esac

    return 0
}
