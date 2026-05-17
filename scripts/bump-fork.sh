#!/usr/bin/env bash
# bump-fork.sh — Bump the fork suffix across every manifest in one shot.
#
# Usage:
#   ./scripts/bump-fork.sh patch
#   ./scripts/bump-fork.sh merge-upstream <X.Y.Z>
#   ./scripts/bump-fork.sh set <X.Y.Z-lestephen.N>
#   ./scripts/bump-fork.sh status
#   ./scripts/bump-fork.sh --help
#
# Modes:
#   patch
#     Increment the `-lestephen.N` suffix to N+1 across all seven
#     manifest version fields. Use after each new fork-only patch
#     commit lands.
#
#   merge-upstream <X.Y.Z>
#     Reset to `<X.Y.Z>-lestephen.1` across all manifests. Use right
#     after merging a fresh upstream release tag (e.g. after
#     `git merge upstream/v9.39.0`).
#
#   set <version>
#     Force-set the version across all manifests. Use for migrations
#     or to sync manifests back to an existing tag after a checkout
#     reverted them. Validates format but does not enforce monotonic
#     ordering.
#
#   status
#     Print the current fork version (and warn if manifests disagree).
#
# What it does NOT do:
#   - Does not commit, tag, or push. After it runs, review the diff
#     and commit/tag yourself. The intentional separation lets the
#     bump commit be paired with whatever code change drove it (see
#     FORK_PATCHES.md Patch 18 for the convention).
#   - Does not regenerate `patches/`. After committing the bump,
#     refresh patches with:
#       rm -f patches/*.patch
#       git format-patch --no-stat upstream/main..HEAD -o patches/
#
# Files updated:
#   package.json
#   .claude-plugin/plugin.json
#   .claude-plugin/marketplace.json          (metadata.version + plugins[octo].version)
#   .codex-plugin/plugin.json
#   .cursor-plugin/plugin.json
#   .factory-plugin/plugin.json
#   .factory-plugin/marketplace.json         (metadata.version + plugins[claude-octopus].version)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PLUGIN_ROOT"

readonly FORK_TAG="lestephen"

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

current_version() {
    python3 -c "import json; print(json.load(open('package.json'))['version'])"
}

# Parse a version string into (upstream, fork_n). Accepts:
#   "9.38.0"                 -> upstream=9.38.0, fork_n=0
#   "9.38.0-lestephen.10"    -> upstream=9.38.0, fork_n=10
parse_version() {
    local ver="$1"
    python3 - "$ver" "$FORK_TAG" <<'EOF'
import re, sys
ver, fork = sys.argv[1], sys.argv[2]
m = re.match(r'^(\d+\.\d+\.\d+)(?:-' + re.escape(fork) + r'\.(\d+))?$', ver)
if not m:
    print(f"ERROR: cannot parse version {ver!r}; expected X.Y.Z or X.Y.Z-{fork}.N", file=sys.stderr)
    sys.exit(2)
upstream, n = m.group(1), m.group(2) or "0"
print(f"{upstream} {n}")
EOF
}

# Set the version field on every manifest atomically.
# lestephen.20 (F10): Two-stage write — build all replacement files in temp
# locations first; only if every read+mutate succeeds, atomically rename each
# temp file into place. A crash, jq error, SIGINT, or disk error mid-loop
# leaves the original files untouched. Previously this rewrote files in
# sequence; a partial-completion left mixed versions across manifests.
set_version_everywhere() {
    local new_version="$1"
    python3 - "$new_version" <<'EOF'
import json, os, sys, tempfile

new = sys.argv[1]

# (path, json-path-or-action). action is one of:
#   "top"                       -> data["version"] = new
#   "meta"                      -> data["metadata"]["version"] = new
#   ("plugins", "<name>")       -> data["plugins"][i]["version"] = new  where name matches
targets = [
    ("package.json", "top"),
    (".claude-plugin/plugin.json", "top"),
    (".claude-plugin/marketplace.json", "meta"),
    (".claude-plugin/marketplace.json", ("plugins", "octo")),
    (".codex-plugin/plugin.json", "top"),
    (".cursor-plugin/plugin.json", "top"),
    (".factory-plugin/plugin.json", "top"),
    (".factory-plugin/marketplace.json", "meta"),
    (".factory-plugin/marketplace.json", ("plugins", "claude-octopus")),
]

# Group by file so we read/write each once.
from collections import defaultdict
by_file = defaultdict(list)
for path, action in targets:
    by_file[path].append(action)

# ── STAGE 1: read + mutate + write to temp files (no destructive writes yet) ──
plans = []  # list of (target_path, temp_path)
try:
    for path, actions in by_file.items():
        if not os.path.exists(path):
            print(f"ERROR: target file missing: {path}", file=sys.stderr)
            sys.exit(2)
        with open(path) as f:
            data = json.load(f)  # raises if malformed → no destructive writes
        for action in actions:
            if action == "top":
                data["version"] = new
            elif action == "meta":
                data.setdefault("metadata", {})["version"] = new
            elif isinstance(action, tuple) and action[0] == "plugins":
                name = action[1]
                for plugin in data.get("plugins", []):
                    if plugin.get("name") == name:
                        plugin["version"] = new
                        break
                else:
                    print(f"WARN: {path}: no plugins[] entry named {name!r}", file=sys.stderr)

        # Detect trailing-newline preference from original file
        with open(path, "rb") as f:
            had_trailing_newline = f.read().endswith(b"\n")

        # Write to a temp file in the same directory (atomic rename requires same fs)
        dirpath = os.path.dirname(path) or "."
        fd, tmp_path = tempfile.mkstemp(prefix=".bump-fork.", suffix=".tmp", dir=dirpath)
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(data, f, indent=2)
                if had_trailing_newline:
                    f.write("\n")
            plans.append((path, tmp_path))
        except Exception:
            os.unlink(tmp_path)
            raise

    # ── STAGE 2: atomic rename — only fires if stage 1 succeeded for ALL files
    for target_path, tmp_path in plans:
        os.replace(tmp_path, target_path)

    # Report
    for target_path, _ in plans:
        print(f"   {target_path}")
except Exception as e:
    # Clean up any temps we created before the error
    for _, tmp_path in plans:
        try: os.unlink(tmp_path)
        except OSError: pass
    print(f"ERROR: rolled back; no files modified. Cause: {e}", file=sys.stderr)
    sys.exit(2)
EOF
}

cmd_status() {
    local ver
    ver=$(current_version)
    read -r upstream n <<<"$(parse_version "$ver")"
    if [[ "$n" == "0" ]]; then
        echo "Current: $ver  (no fork suffix — manifests reflect bare upstream)"
    else
        echo "Current: $ver  (upstream: $upstream, fork patch: $n)"
    fi

    # Cross-check that all manifests agree
    local mismatch=0
    while IFS=$'\t' read -r path other_ver; do
        if [[ "$other_ver" != "$ver" ]]; then
            echo "WARN: $path reports $other_ver (expected $ver)"
            mismatch=1
        fi
    done < <(python3 - <<'EOF'
import json

# Only octopus-fork-owned entries. Sibling plugins in shared marketplaces
# (e.g. 'img' in .claude-plugin/marketplace.json) have their own versions.
OWNED_PLUGIN_NAMES = {"octo", "claude-octopus"}

files = [
    "package.json",
    ".claude-plugin/plugin.json",
    ".claude-plugin/marketplace.json",
    ".codex-plugin/plugin.json",
    ".cursor-plugin/plugin.json",
    ".factory-plugin/plugin.json",
    ".factory-plugin/marketplace.json",
]
for path in files:
    with open(path) as f:
        d = json.load(f)
    if "version" in d:
        print(f"{path}\t{d['version']}")
    if "metadata" in d and "version" in d["metadata"]:
        print(f"{path} (metadata)\t{d['metadata']['version']}")
    for plugin in d.get("plugins", []) or []:
        name = plugin.get("name", "?")
        if name in OWNED_PLUGIN_NAMES and "version" in plugin:
            print(f"{path} (plugins/{name})\t{plugin['version']}")
EOF
    )
    # lestephen.21 (C3): distinct exit codes so CI/pre-push hooks can
    # tell "drift detected" (1) apart from "script crashed" (other non-zero).
    #   0 — all consistent
    #   1 — drift detected (a manifest reports a different version than current)
    #   2 — internal script error (set -u trap, command failure, etc. — set via shell defaults)
    return $mismatch
}

cmd_patch() {
    local ver upstream n new
    ver=$(current_version)
    read -r upstream n <<<"$(parse_version "$ver")"
    new="${upstream}-${FORK_TAG}.$((n + 1))"
    echo "Bumping fork patch level: $ver  ->  $new"
    set_version_everywhere "$new"
    echo ""
    echo "Done. Next steps:"
    echo "  1. Review:    git diff"
    echo "  2. Stage:     git add -p"
    echo "  3. Commit:    git commit -m 'chore(fork): bump to $new'"
    echo "  4. Tag:       git tag v$new"
    echo "  5. Regen:     rm -f patches/*.patch && git format-patch --no-stat upstream/main..HEAD -o patches/"
}

cmd_set() {
    local new="$1"
    # Validate format: X.Y.Z or X.Y.Z-lestephen.N
    if ! [[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-${FORK_TAG}\.[0-9]+)?$ ]]; then
        echo "ERROR: '$new' is not a valid version (expected X.Y.Z or X.Y.Z-${FORK_TAG}.N)" >&2
        exit 2
    fi
    local ver
    ver=$(current_version)
    echo "Setting fork version: $ver  ->  $new"
    set_version_everywhere "$new"
    echo ""
    echo "Done. Review with: git diff"
}

cmd_merge_upstream() {
    local new_upstream="$1"
    if [[ ! "$new_upstream" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: '$new_upstream' is not a valid upstream version (expected X.Y.Z)" >&2
        exit 2
    fi
    local ver upstream n new
    ver=$(current_version)
    read -r upstream n <<<"$(parse_version "$ver")"
    if [[ "$upstream" == "$new_upstream" ]]; then
        echo "WARN: upstream is already $new_upstream; use 'patch' mode instead." >&2
        exit 2
    fi
    new="${new_upstream}-${FORK_TAG}.1"
    echo "Resetting fork onto new upstream: $ver  ->  $new"
    set_version_everywhere "$new"
    echo ""
    echo "Done. Next steps:"
    echo "  1. Review:    git diff"
    echo "  2. Update FORK_PATCHES.md header: 'currently at upstream v$new_upstream'"
    echo "  3. Commit:    git commit -m 'chore(fork): rebase onto upstream v$new_upstream, reset to $new'"
    echo "  4. Tag:       git tag v$new"
    echo "  5. Regen:     rm -f patches/*.patch && git format-patch --no-stat upstream/main..HEAD -o patches/"
}

# lestephen.20 (F11): Serialize mutating commands with flock so concurrent
# `bump-fork.sh patch` runs can't both read version=N and both write N+1
# (lost-increment race). status mode is read-only and does not lock.
_bump_dispatch() {
    case "${1:-}" in
        patch)            cmd_patch ;;
        merge-upstream)   shift; [[ $# -lt 1 ]] && { echo "ERROR: merge-upstream requires an upstream version" >&2; exit 2; }; cmd_merge_upstream "$1" ;;
        set)              shift; [[ $# -lt 1 ]] && { echo "ERROR: set requires a version" >&2; exit 2; }; cmd_set "$1" ;;
        status|"")        cmd_status ;;
        -h|--help|help)   usage 0 ;;
        *)                echo "ERROR: unknown mode '$1'" >&2; usage 2 ;;
    esac
}

case "${1:-}" in
    patch|merge-upstream|set)
        # Mutating commands take an exclusive lock at the repo root
        LOCK_FILE="$PLUGIN_ROOT/.bump-fork.lock"
        if command -v flock >/dev/null 2>&1; then
            exec 9>"$LOCK_FILE"
            if ! flock -n 9; then
                echo "ERROR: another bump-fork.sh run is in progress (lock: $LOCK_FILE). Wait for it to finish." >&2
                exit 2
            fi
            _bump_dispatch "$@"
            rc=$?
            flock -u 9
            exit $rc
        else
            echo "WARN: flock not available; concurrent bump-fork.sh runs may race" >&2
            _bump_dispatch "$@"
        fi
        ;;
    *)
        # status / help — read-only, no lock needed
        _bump_dispatch "$@"
        ;;
esac
