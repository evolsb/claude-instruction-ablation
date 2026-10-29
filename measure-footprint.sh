#!/usr/bin/env bash
# Measure a repo's always-on Claude Code instruction footprint.
# Usage: ./measure-footprint.sh [repo-dir]   (defaults to cwd)
# Rough token estimate = words * 1.3.
# Read-only: prints word counts and paths only, never file contents.
# Note: always also counts YOUR ~/.claude global config and skill descriptions,
# because those load in every session regardless of which repo you point it at.
#
# What counts as always-on, matching how Claude Code loads it:
# - CLAUDE.md files, plus every file they pull in with an `@path` import line
#   (followed recursively, each file counted once). A CLAUDE.md that is mostly
#   one `@AGENTS.md` line is otherwise measured as almost nothing.
# - .claude/rules/*.md WITHOUT `paths:` frontmatter. A rules file that has
#   `paths:` loads only when a matching file is read or edited, so it is
#   listed separately and left out of the total.
# - The auto-memory index for this project (~/.claude/projects/<slug>/memory/MEMORY.md).
# - Skill frontmatter descriptions (bodies load lazily).

set -euo pipefail
REPO="$(cd "${1:-.}" && pwd)"
total=0
scoped_total=0
SEEN=$(mktemp)
trap 'rm -f "$SEEN"' EXIT

words() { wc -w < "$1" | tr -d ' '; }

add() { # add <label> <words>
  [ "${2:-0}" -gt 0 ] || return 0
  printf '%-46s %8d words\n' "$1" "$2"
  total=$((total + $2))
}

has_paths_frontmatter() { # true when the file's leading --- block has a paths: key
  awk 'NR==1 && $0!="---"{rc=1; exit} NR>1 && $0=="---"{rc=(found?0:1); closed=1; exit} NR>1 && /^paths:/{found=1} END{exit (closed ? rc : 1)}' "$1"
}

# Print each file a markdown file imports with `@path`, resolved against the
# importing file's directory (`@~/x` against $HOME). Code spans and fenced
# blocks are skipped, as Claude Code skips them.
imports_of() {
  local file="$1" dir
  dir="$(cd "$(dirname "$file")" && pwd)"
  awk '/^```/{fence=!fence; next} !fence' "$file" \
    | sed 's/`[^`]*`//g' \
    | grep -oE '(^|[[:space:]])@[~./A-Za-z0-9_-][^[:space:]]*' \
    | sed -E 's/^[[:space:]]*@//' \
    | while read -r ref; do
        case "$ref" in
          "~/"*) printf '%s\n' "$HOME/${ref#\~/}" ;;
          /*) printf '%s\n' "$ref" ;;
          *) printf '%s\n' "$dir/$ref" ;;
        esac
      done
}

# Count a file and, recursively, its imports, each file once.
count_tree() { # count_tree <label> <file>
  local label="$1" file="$2" real imp
  [ -f "$file" ] || return 0
  real="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
  grep -qxF "$real" "$SEEN" && return 0
  printf '%s\n' "$real" >> "$SEEN"
  add "$label" "$(words "$real")"
  while read -r imp; do
    [ -n "$imp" ] && [ -f "$imp" ] && count_tree "  imported by $(basename "$real"): ${imp/#$HOME/~}" "$imp"
  done < <(imports_of "$real")
  return 0
}

count_rules() { # count_rules <label-prefix> <dir>
  local prefix="$1" dir="$2" f always=0 scoped=0
  compgen -G "$dir/*.md" >/dev/null || return 0
  for f in "$dir"/*.md; do
    if has_paths_frontmatter "$f"; then
      scoped=$((scoped + $(words "$f")))
    else
      always=$((always + $(words "$f")))
      printf '%s\n' "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")" >> "$SEEN"
    fi
  done
  add "$prefix (no paths:, always-on)" "$always"
  if [ "$scoped" -gt 0 ]; then
    printf '%-46s %8d words (not in total)\n' "$prefix (paths:, on match only)" "$scoped"
    scoped_total=$((scoped_total + scoped))
  fi
}

echo "== Project: $REPO =="
count_tree "project CLAUDE.md" "$REPO/CLAUDE.md"
count_tree "project CLAUDE.local.md" "$REPO/CLAUDE.local.md"
count_rules "project .claude/rules/*.md" "$REPO/.claude/rules"

# Auto-memory index: the project slug is its absolute path with / and . turned into -.
slug="$(printf '%s' "$REPO" | sed 's#[/.]#-#g')"
mem="$HOME/.claude/projects/$slug/memory/MEMORY.md"
[ -f "$mem" ] && add "auto-memory index (MEMORY.md)" "$(words "$mem")"

echo "== Global (loads in EVERY session) =="
count_tree "global ~/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
count_rules "global ~/.claude/rules/*.md" "$HOME/.claude/rules"

# Skill frontmatter descriptions load always-on; skill bodies are lazy.
desc_total=0
for f in "$HOME"/.claude/skills/*/SKILL.md "$REPO"/.claude/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  w=$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm==1 && /^description:/{d=1} fm==1 && d && /^[a-zA-Z_-]+:/ && !/^description:/{d=0} fm==1 && d{print} fm>1{exit}' "$f" | wc -w | tr -d ' ')
  desc_total=$((desc_total + w))
done
add "skill frontmatter descriptions (always-on)" "$desc_total"

echo "-----------------------------------------------------------"
printf '%-46s %8d words (~%d tokens)\n' "TOTAL always-on" "$total" $((total * 13 / 10))
[ "$scoped_total" -gt 0 ] && printf '%-46s %8d words\n' "plus path-scoped rules (on match)" "$scoped_total"
echo
echo "Biggest single always-on files:"
xargs wc -w < "$SEEN" 2>/dev/null | sort -rn | grep -v ' total$' | head -8 | sed "s#$HOME#~#" || true
