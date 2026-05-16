#!/usr/bin/env bash
# checkpoint-counter.sh — scan a tangle subtask's output streams for
# `### CHECKPOINT:` markers and write a counter + list to a state file.
#
# Called periodically by tangle_develop's wait loop. The state file's mtime
# is what the loop watches to decide whether a subtask is still making
# progress; a stalled subtask shows the same mtime across polls and trips
# the idle-timeout kill.
#
# Usage: checkpoint-counter.sh <results_dir> <task_id> <state_file>
#
# Scans every file matching the task_id in the results directory:
#   - <results_dir>/.tmp-<task_id>.err   (provider stderr, populated during run)
#   - <results_dir>/.tmp-<task_id>.out   (provider stdout, populated during run)
#   - <results_dir>/*-<task_id>.md       (final assembled output, after spawn finishes)
#
# Markers must appear AT THE START OF A LINE (column 0). The protocol
# header that gets prepended to subtask prompts contains indented example
# markers; anchoring to `^` prevents them from being miscounted as
# completed checkpoints.
#
# State file format:
#   First line: integer count of checkpoints
#   Subsequent lines: each checkpoint description, one per line
#
# Exit codes:
#   0  state file updated (count may or may not have changed)
#   2  state file location not writable or argument missing
#
# Idempotent — safe to call repeatedly. Only writes when the count changed,
# so mtime stays put while the subtask is stalled.

set -eo pipefail

results_dir="${1:-}"
task_id="${2:-}"
state_file="${3:-}"

if [[ -z "$results_dir" || -z "$task_id" || -z "$state_file" ]]; then
    echo "usage: $0 <results_dir> <task_id> <state_file>" >&2
    exit 2
fi

# Collect candidate files. Globs may not match anything yet (early in
# spawn) — that's fine, we just count 0.
shopt -s nullglob
candidates=(
    "$results_dir/.tmp-${task_id}.err"
    "$results_dir/.tmp-${task_id}.out"
    "$results_dir"/*-"${task_id}".md
    "$results_dir/.raw-${task_id}.out"
)
shopt -u nullglob

# Anchor to start of line. Indented example markers in the protocol header
# do not match. Codex's narrative output emits markers at column 0.
new_list=""
for f in "${candidates[@]}"; do
    [[ -r "$f" ]] || continue
    file_matches=$(grep -E '^### CHECKPOINT:' "$f" 2>/dev/null \
        | sed 's/^### CHECKPOINT:[[:space:]]*//' \
        || true)
    if [[ -n "$file_matches" ]]; then
        if [[ -n "$new_list" ]]; then
            new_list+=$'\n'
        fi
        new_list+="$file_matches"
    fi
done

new_count=0
if [[ -n "$new_list" ]]; then
    new_count=$(printf '%s\n' "$new_list" | grep -c '^' || echo 0)
fi

current_count=0
if [[ -f "$state_file" ]]; then
    current_count=$(head -1 "$state_file" 2>/dev/null || echo 0)
    [[ "$current_count" =~ ^[0-9]+$ ]] || current_count=0
fi

# Only rewrite when count changed — keeps mtime stable across no-progress polls.
if [[ "$new_count" != "$current_count" ]]; then
    mkdir -p "$(dirname "$state_file")" 2>/dev/null || true
    {
        echo "$new_count"
        printf '%s\n' "$new_list"
    } > "$state_file" 2>/dev/null || exit 2
fi

exit 0
