#!/usr/bin/env bash
# Unit tests for the machine-enforced consensus gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Consensus Gate"

GATE="$PROJECT_ROOT/bin/octo-consensus"

write_reviewer_output() {
    local file="$1"
    local body="$2"

    mkdir -p "$(dirname "$file")"
    cat > "$file" <<EOF
# Reviewer output

## Status: SUCCESS

## Output
$body

## Metadata
EOF
}

write_dispatch_json() {
    local file="$1"
    shift
    local total="$#"

    {
        echo "{"
        echo '  "output_dir": "'"$(dirname "$file")"'",'
        echo '  "doc_path": "'"$TEST_TMP_DIR/doc.md"'",'
        echo '  "min_reviewers": 2,'
        echo '  "total": '"$total"','
        echo '  "success": '"$total"','
        echo '  "failed": 0,'
        echo '  "reviewers": ['
        local index=0
        local spec agent output_file sep
        for spec in "$@"; do
            agent="${spec%%:*}"
            output_file="${spec#*:}"
            sep=","
            [[ $index -eq $((total - 1)) ]] && sep=""
            printf '    {"label":"reviewer-%s","agent_type":"%s","task_id":"task-%s","outcome":"success","output_file":"%s"}%s\n' \
                "$index" "$agent" "$index" "$output_file" "$sep"
            index=$((index + 1))
        done
        echo "  ]"
        echo "}"
    } > "$file"
}

run_gate() {
    local dispatch="$1"
    set +e
    RUN_OUTPUT="$("$GATE" check "$dispatch" "unit test action" 2>&1)"
    RUN_STATUS=$?
    set -e
}

test_case "two clean reviewers from distinct families allow"
case_dir="$TEST_TMP_DIR/consensus-clean"
mkdir -p "$case_dir"
write_reviewer_output "$case_dir/codex.md" "NO BLOCKING FINDINGS"
write_reviewer_output "$case_dir/gemini.md" "NO BLOCKING FINDINGS"
write_dispatch_json "$case_dir/dispatch.json" \
    "codex:$case_dir/codex.md" \
    "gemini:$case_dir/gemini.md"
run_gate "$case_dir/dispatch.json"
if assert_success "$RUN_STATUS" "clean distinct reviewers should pass" &&
   assert_contains "$RUN_OUTPUT" "CONSENSUS GATE: ALLOW" "expected ALLOW verdict"; then
    test_pass
fi

test_case "valid SEV-3 line counts as parseable non-blocking input"
case_dir="$TEST_TMP_DIR/consensus-sev3"
mkdir -p "$case_dir"
write_reviewer_output "$case_dir/codex.md" "SEV-3: Minor polish - Non-blocking implementation cleanup."
write_reviewer_output "$case_dir/gemini.md" "NO BLOCKING FINDINGS"
write_dispatch_json "$case_dir/dispatch.json" \
    "codex:$case_dir/codex.md" \
    "gemini:$case_dir/gemini.md"
run_gate "$case_dir/dispatch.json"
if assert_success "$RUN_STATUS" "SEV-3 should not make the provider unparseable" &&
   assert_contains "$RUN_OUTPUT" "CONSENSUS GATE: ALLOW" "expected ALLOW verdict"; then
    test_pass
fi

test_case "parseable reviewers must still have provider diversity"
case_dir="$TEST_TMP_DIR/consensus-parseable-diversity"
mkdir -p "$case_dir"
write_reviewer_output "$case_dir/codex.md" "NO BLOCKING FINDINGS"
write_reviewer_output "$case_dir/codex-mini.md" "NO BLOCKING FINDINGS"
write_reviewer_output "$case_dir/gemini.md" "This reviewer produced a long prose paragraph without the required severity-line grammar, so the gate must not count it as a valid diversity vote."
write_dispatch_json "$case_dir/dispatch.json" \
    "codex:$case_dir/codex.md" \
    "codex-mini:$case_dir/codex-mini.md" \
    "gemini:$case_dir/gemini.md"
run_gate "$case_dir/dispatch.json"
if assert_exit_code 4 "$RUN_STATUS" "same-family parseable quorum must be blocked" &&
   assert_contains "$RUN_OUTPUT" "NO PROVIDER DIVERSITY" "expected diversity block"; then
    test_pass
fi

test_case "two SEV-1 reviewers hard block"
case_dir="$TEST_TMP_DIR/consensus-hard-block"
mkdir -p "$case_dir"
write_reviewer_output "$case_dir/codex.md" "SEV-1: Unsafe action - It can corrupt the release artifact."
write_reviewer_output "$case_dir/gemini.md" "SEV-1: Unsafe action - It can corrupt the release artifact."
write_dispatch_json "$case_dir/dispatch.json" \
    "codex:$case_dir/codex.md" \
    "gemini:$case_dir/gemini.md"
run_gate "$case_dir/dispatch.json"
if assert_exit_code 1 "$RUN_STATUS" "two SEV-1 reviewers should hard block" &&
   assert_contains "$RUN_OUTPUT" "CONSENSUS GATE: HARD BLOCK" "expected hard block verdict"; then
    test_pass
fi

test_case "single successful reviewer has no quorum"
case_dir="$TEST_TMP_DIR/consensus-no-quorum"
mkdir -p "$case_dir"
write_reviewer_output "$case_dir/codex.md" "NO BLOCKING FINDINGS"
write_dispatch_json "$case_dir/dispatch.json" "codex:$case_dir/codex.md"
run_gate "$case_dir/dispatch.json"
if assert_exit_code 4 "$RUN_STATUS" "single reviewer should not meet quorum" &&
   assert_contains "$RUN_OUTPUT" "CONSENSUS GATE: NO QUORUM" "expected no quorum verdict"; then
    test_pass
fi

test_summary
