#!/usr/bin/env bash
# Measure a repo's always-on Claude Code instruction footprint.
# Usage: ./measure-footprint.sh [repo-dir]   (defaults to cwd)
# Rough token estimate = words * 1.3.
# Read-only: prints word counts and paths only, never file contents.
# Note: always also counts YOUR ~/.claude global config and skill descriptions,
# because those load in every session regardless of which repo you point it at.

set -euo pipefail
REPO="${1:-.}"
total=0

count() { # count <label> <file...>
  local label="$1"; shift
  local w
  w=$(cat "$@" 2>/dev/null | wc -w | tr -d ' ')
  [ "${w:-0}" -gt 0 ] || return 0
  printf '%-46s %8d words\n' "$label" "$w"
  total=$((total + w))
}

echo "== Project: $REPO =="
[ -f "$REPO/CLAUDE.md" ] && count "project CLAUDE.md" "$REPO/CLAUDE.md"
if compgen -G "$REPO/.claude/rules/*.md" >/dev/null; then
  count "project .claude/rules/*.md (all auto-load)" "$REPO"/.claude/rules/*.md
fi

echo "== Global (loads in EVERY session) =="
[ -f "$HOME/.claude/CLAUDE.md" ] && count "global ~/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
if compgen -G "$HOME/.claude/rules/*.md" >/dev/null; then
  count "global ~/.claude/rules/*.md" "$HOME"/.claude/rules/*.md
fi

# Skill frontmatter descriptions load always-on; skill bodies are lazy.
desc_total=0
for f in "$HOME"/.claude/skills/*/SKILL.md "$REPO"/.claude/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  w=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm==1 && /^description:/{d=1} fm==1 && d && /^[a-zA-Z_-]+:/ && !/^description:/{d=0} fm==1 && d{print} fm>1{exit}' "$f" | wc -w | tr -d ' ')
  desc_total=$((desc_total + w))
done
if [ "$desc_total" -gt 0 ]; then
  printf '%-46s %8d words\n' "skill frontmatter descriptions (always-on)" "$desc_total"
  total=$((total + desc_total))
fi

echo "-----------------------------------------------------------"
printf '%-46s %8d words (~%d tokens)\n' "TOTAL always-on" "$total" $((total * 13 / 10))
echo
echo "Biggest single files:"
{ ls "$REPO"/CLAUDE.md "$REPO"/.claude/rules/*.md "$HOME"/.claude/CLAUDE.md "$HOME"/.claude/rules/*.md 2>/dev/null || true; } \
  | xargs wc -w 2>/dev/null | sort -rn | head -8 | grep -v ' total$' || true
