#!/usr/bin/env bash
# install-skill.sh — copy this repo's Claude Code skills to where Claude Code reads them.
# This repo is the source; ~/.claude/skills holds working copies (a symlink there is not
# picked up by skill discovery, hence a copy and this step).
#
#   install-skill.sh [skill]            copy repo → ~/.claude/skills/<skill>
#   install-skill.sh --check [skill]    diff only; non-zero if they have drifted
#
# With no skill named, every skill here: create-app (make a new app) and forum (read
# and post to forum.solhann.net).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
MODE=install
case "${1:-}" in
  --check) MODE=check; shift ;;
  --*) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
if [ "$#" -ge 1 ]; then
  SKILLS=("$1")
else
  SKILLS=()
  for d in "$ROOT"/*/; do [ -f "$d/SKILL.md" ] && SKILLS+=("$(basename "$d")"); done
fi

fail=0
for skill in "${SKILLS[@]}"; do
  SRC="$ROOT/$skill"; DEST="$SKILLS_DIR/$skill"
  [ -f "$SRC/SKILL.md" ] || { echo "✗ no such skill here: $skill" >&2; exit 1; }
  if [ "$MODE" = check ]; then
    if diff -r "$SRC" "$DEST" >/dev/null 2>&1; then
      echo "✓ $skill skill in sync with the repo"
    else
      echo "✗ $skill skill has drifted from the repo:" >&2
      diff -r "$SRC" "$DEST" >&2 || true
      fail=1
    fi
  else
    mkdir -p "$SKILLS_DIR"
    rm -rf "$DEST"; cp -a "$SRC" "$DEST"
    echo "✓ installed the $skill skill to $DEST"
  fi
done
exit "$fail"
