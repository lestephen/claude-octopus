#!/usr/bin/env bash
# dev-install.sh — Convert a marketplace-installed octo plugin into a dev
# install backed by a git working tree, in one command.
#
# Prerequisite: you have already run (inside Claude Code):
#     /plugin marketplace add lestephen/claude-octopus-marketplace
#     /plugin install octo@lestephen-octo
#
# Usage:
#     scripts/dev-install.sh [<source-dir>]
#
# Default source dir: $HOME/source/claude-octopus
#
# What this does:
#   1. Resolves Claude Code's active install path from installed_plugins.json
#   2. Clones the fork into <source-dir> if not already present there
#   3. Removes the cached install and replaces it with a symlink to <source-dir>
#   4. Symlinks the plugin's self-resolution path (~/.claude-octopus/plugin)
#      to the cached install path (which now resolves through to <source-dir>)
#
# Idempotent: re-running with the same source dir is a no-op for already-
# symlinked paths.
#
# Gotchas:
#   - `/plugin update` inside Claude Code will rm -rf the cache symlink and
#     re-pull the marketplace-pinned version. Re-run this script after any
#     /plugin update to restore the dev symlink.
#   - The version subdir in the cache path is the BASE version from
#     plugin.json (e.g. 9.38.0), not the fork suffix (-lestephen.36).

set -euo pipefail

SOURCE_DIR="${1:-$HOME/source/claude-octopus}"
REPO_URL="https://github.com/lestephen/claude-octopus"
INSTALL_RECORD="$HOME/.claude/plugins/installed_plugins.json"
SELF_RESOLUTION_PATH="$HOME/.claude-octopus/plugin"

# ─── 1. Verify prerequisite ───────────────────────────────────────────────
if [[ ! -f "$INSTALL_RECORD" ]]; then
    echo "ERROR: $INSTALL_RECORD not found." >&2
    echo "       Run /plugin install octo@lestephen-octo inside Claude Code first." >&2
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq required (apt install jq | brew install jq)" >&2
    exit 1
fi

# ─── 2. Resolve Claude Code's active install path ────────────────────────
# sort_by(.lastUpdated) | last picks the most recently updated install
# entry, deterministic across multi-version caches.
CACHED=$(jq -r '
    .plugins["octo@lestephen-octo"]
    | sort_by(.lastUpdated)
    | last
    | .installPath
  ' "$INSTALL_RECORD")
if [[ -z "$CACHED" || "$CACHED" == "null" ]]; then
    echo "ERROR: octo@lestephen-octo not in $INSTALL_RECORD." >&2
    echo "       Run /plugin install octo@lestephen-octo inside Claude Code first." >&2
    exit 1
fi
echo "→ Claude Code install path:  $CACHED"
echo "→ Source dir (working tree): $SOURCE_DIR"

# ─── 3. Clone if not present ──────────────────────────────────────────────
if [[ -d "$SOURCE_DIR/.git" ]]; then
    echo "→ Working tree already exists at $SOURCE_DIR (skipping clone)"
else
    if [[ -e "$SOURCE_DIR" ]]; then
        echo "ERROR: $SOURCE_DIR exists but is not a git repo. Remove or pick another path:" >&2
        echo "       scripts/dev-install.sh /alternate/path" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$SOURCE_DIR")"
    git clone "$REPO_URL" "$SOURCE_DIR"
fi

# Get the absolute, resolved source path (handles symlinks in the dirname chain)
SOURCE_DIR_ABS=$(cd "$SOURCE_DIR" && pwd -P)

# ─── 4. Replace cached install with symlink to working tree ──────────────
if [[ -L "$CACHED" ]]; then
    current_target=$(readlink "$CACHED")
    if [[ "$current_target" == "$SOURCE_DIR_ABS" ]]; then
        echo "→ Cache already symlinked to working tree (no-op)"
    else
        echo "→ Cache symlinked to $current_target; replacing with $SOURCE_DIR_ABS"
        rm -f "$CACHED"
        ln -s "$SOURCE_DIR_ABS" "$CACHED"
    fi
elif [[ -d "$CACHED" ]]; then
    echo "→ Replacing cached install (real dir) with symlink to working tree"
    rm -rf "$CACHED" || { echo "ERROR: failed to remove $CACHED (busy?)" >&2; exit 1; }
    ln -s "$SOURCE_DIR_ABS" "$CACHED"
else
    echo "ERROR: cached install path $CACHED doesn't exist as a dir or symlink." >&2
    echo "       Did /plugin install actually succeed? Check $INSTALL_RECORD." >&2
    exit 1
fi

# ─── 5. Symlink self-resolution path → cached install ────────────────────
# Many plugin scripts hardcode ~/.claude-octopus/plugin for self-resolution
# (bin/octo-consensus, setup.md install hints, skill prose, etc.). Point it
# at $CACHED so it resolves transitively through to the working tree.
mkdir -p "$(dirname "$SELF_RESOLUTION_PATH")"
if [[ -L "$SELF_RESOLUTION_PATH" ]]; then
    current_target=$(readlink "$SELF_RESOLUTION_PATH")
    if [[ "$current_target" == "$CACHED" ]]; then
        echo "→ Self-resolution path already symlinked correctly (no-op)"
    else
        echo "→ Self-resolution path symlinked to $current_target; updating"
        rm -f "$SELF_RESOLUTION_PATH"
        ln -s "$CACHED" "$SELF_RESOLUTION_PATH"
    fi
elif [[ -d "$SELF_RESOLUTION_PATH" ]]; then
    if [[ -z "$(ls -A "$SELF_RESOLUTION_PATH")" ]]; then
        rmdir "$SELF_RESOLUTION_PATH"
        ln -s "$CACHED" "$SELF_RESOLUTION_PATH"
    else
        echo "ERROR: $SELF_RESOLUTION_PATH is a non-empty directory." >&2
        echo "       Inspect and remove manually, then re-run this script:" >&2
        ls -la "$SELF_RESOLUTION_PATH" >&2
        exit 1
    fi
else
    ln -s "$CACHED" "$SELF_RESOLUTION_PATH"
fi

# ─── Done ────────────────────────────────────────────────────────────────
echo ""
echo "✓ Dev install complete."
echo "  Edits in $SOURCE_DIR_ABS are now live for /octo:* commands."
echo ""
echo "  Verify:"
echo "    ls -la \"$CACHED\""
echo "    ls -la \"$SELF_RESOLUTION_PATH\""
echo ""
echo "  Note: /plugin update inside Claude Code will clobber the cache"
echo "  symlink. Re-run this script after any /plugin update."
