#!/usr/bin/env bash
# install-skill.sh — copy the create-app skill from this repo to where Claude Code
# reads skills. This repo is the source; ~/.claude/skills holds a working copy (a
# symlink there is not picked up by skill discovery, hence a copy and this step).
#
#   install-skill.sh            copy repo → ~/.claude/skills/create-app
#   install-skill.sh --check    diff only; non-zero if the two have drifted
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/create-app"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/create-app"

case "${1:-}" in
  "")
    mkdir -p "$(dirname "$DEST")"
    rm -rf "$DEST"; cp -a "$SRC" "$DEST"
    echo "✓ installed the create-app skill to $DEST" ;;
  --check)
    if diff -r "$SRC" "$DEST" >/dev/null 2>&1; then
      echo "✓ create-app skill in sync with the repo"
    else
      echo "✗ create-app skill has drifted from the repo:" >&2
      diff -r "$SRC" "$DEST" >&2 || true
      exit 1
    fi ;;
  *) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
