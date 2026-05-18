#!/usr/bin/env bash
# render_diff.sh — Project-supplied render-script wrapper for /octo:visual-review.
#
# Runs the project's render-for-review script (from `visual.render_script`
# in the review profile) and returns the path to the resulting screenshot
# so the reviewer fleet can sample pixels from rendered output (not just
# the mockup). Per /octo:visual-review GH #11 design (lestephen.33):
# project-supplied script is more flexible than baking Playwright into the
# plugin, and works for any frontend stack the project already supports.
#
# Usage:
#     render_diff.sh <project-script-path> [args...]
#
# The project script MUST:
#   - Exit 0 on success, non-zero on failure
#   - Print the absolute path to the resulting screenshot as the LAST line
#     of stdout (anything else goes to stderr or earlier stdout lines)
#   - Be self-contained (start/stop its own dev server, handle cleanup)
#
# Example project script (`scripts/render-for-review.sh` in the project repo):
#     #!/usr/bin/env bash
#     set -euo pipefail
#     npm run dev > /tmp/dev.log 2>&1 &
#     DEV_PID=$!
#     trap "kill $DEV_PID 2>/dev/null || true" EXIT
#     for i in {1..30}; do curl -sf http://localhost:3000 >/dev/null && break; sleep 1; done
#     OUT="/tmp/render-$$.png"
#     npx playwright screenshot --viewport=1280,720 http://localhost:3000 "$OUT"
#     echo "$OUT"  # MUST be the last line of stdout
#
# Profile field that drives this:
#     visual:
#       render_script: ./scripts/render-for-review.sh
#       render_script_args: ["--page", "/dashboard"]  # optional
#       delta_e_threshold: 5.0
#
# Exit codes:
#     0  success; screenshot path on stdout
#     1  bad arguments
#     2  project script missing or not executable
#     3  project script exited non-zero
#     4  project script didn't output a valid screenshot path

set -uo pipefail

if [[ $# -lt 1 ]]; then
    echo "ERROR: usage: $(basename "$0") <project-script-path> [args...]" >&2
    exit 1
fi

PROJECT_SCRIPT="$1"
shift

if [[ ! -f "$PROJECT_SCRIPT" ]]; then
    echo "ERROR: project render script not found: $PROJECT_SCRIPT" >&2
    echo "       Configure in profile under visual.render_script" >&2
    exit 2
fi
if [[ ! -x "$PROJECT_SCRIPT" ]]; then
    echo "ERROR: project render script not executable: $PROJECT_SCRIPT" >&2
    echo "       Run: chmod +x $PROJECT_SCRIPT" >&2
    exit 2
fi

# Run the script. CRITICAL: keep stdout and stderr SEPARATE — the contract
# says "screenshot path is the last line of stdout"; if we merge stderr in,
# any stderr line emitted after the path (trap cleanup, dev-server teardown,
# Playwright shutdown noise) becomes the "screenshot path" and downstream
# tools ENOENT. lestephen.33 v2 fix to claude SEV-2.
_tmp_out=$(mktemp)
_tmp_err=$(mktemp)
trap "rm -f '$_tmp_out' '$_tmp_err'" EXIT

if ! "$PROJECT_SCRIPT" "$@" >"$_tmp_out" 2>"$_tmp_err"; then
    _rc=$?
    echo "ERROR: project render script exited non-zero (rc=$_rc):" >&2
    echo "--- stdout ---" >&2; cat "$_tmp_out" >&2
    echo "--- stderr ---" >&2; cat "$_tmp_err" >&2
    exit 3
fi

# Last line of STDOUT (not merged stream) is the screenshot path.
SCREENSHOT_PATH=$(tail -n 1 "$_tmp_out" | tr -d '\r\n')

if [[ -z "$SCREENSHOT_PATH" ]]; then
    echo "ERROR: project render script produced no output on last stdout line" >&2
    echo "       The script MUST echo the absolute screenshot path as its last line" >&2
    exit 4
fi

if [[ ! -f "$SCREENSHOT_PATH" ]]; then
    echo "ERROR: project render script claimed screenshot at $SCREENSHOT_PATH but file does not exist" >&2
    echo "       Full script output:" >&2
    cat "$_tmp_out" >&2
    exit 4
fi

echo "$SCREENSHOT_PATH"
