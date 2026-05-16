#!/usr/bin/env bash
# checkpoint-counter.sh — scan a tangle subtask's result file for
# `### CHECKPOINT:` markers and write a counter + list to a state file.
#
# Called periodically by tangle_develop's wait loop. The state file's mtime
# is what the loop watches to decide whether a subtask is still making
# progress; a stalled subtask shows the same mtime across polls and trips
# the idle-timeout kill.
#
# Usage: checkpoint-counter.sh <result_file> <state_file>
#
# State file format:
#   First line: integer count of checkpoints
#   Subsequent lines: each checkpoint description, one per line
#
# Exit codes:
#   0  state file updated (count may or may not have changed)
#   1  result file missing or unreadable
#   2  state file location not writable
#
# Idempotent — safe to call repeatedly. Only writes when the count changed,
# so mtime stays put while the subtask is stalled.

set -eo pipefail

result_file="${1:-}"
state_file="${2:-}"

if [[ -z "$result_file" || -z "$state_file" ]]; then
    echo "usage: $0 <result_file> <state_file>" >&2
    exit 2
fi

if [[ ! -r "$result_file" ]]; then
    # Result file may not yet exist when the spawn is brand new. Treat as 0
    # checkpoints and seed the state file so the wait loop has a baseline.
    if [[ ! -f "$state_file" ]]; then
        mkdir -p "$(dirname "$state_file")" 2>/dev/null || true
        : > "$state_file" 2>/dev/null || exit 2
    fi
    exit 0
fi

# Pull every `### CHECKPOINT:` line, strip the marker prefix, leave the
# description. Use grep -F for a literal-string match on the marker prefix
# (the rest is free text), then sed to strip.
new_list=$(grep -F '### CHECKPOINT:' "$result_file" 2>/dev/null \
    | sed 's/^.*### CHECKPOINT:[[:space:]]*//' \
    || true)

new_count=0
if [[ -n "$new_list" ]]; then
    new_count=$(printf '%s\n' "$new_list" | grep -c '^' || echo 0)
fi

current_count=0
if [[ -f "$state_file" ]]; then
    current_count=$(head -1 "$state_file" 2>/dev/null || echo 0)
    [[ "$current_count" =~ ^[0-9]+$ ]] || current_count=0
fi

# Only rewrite when the count changed — keeps mtime stable across no-progress polls.
if [[ "$new_count" != "$current_count" ]]; then
    mkdir -p "$(dirname "$state_file")" 2>/dev/null || true
    {
        echo "$new_count"
        printf '%s\n' "$new_list"
    } > "$state_file" 2>/dev/null || exit 2
fi

exit 0
