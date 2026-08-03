# Instruction ablation rubric

Give this file to a coding agent with: "Read this rubric, then ablate the always-on
instructions in <repo>. Work on a branch, open a PR, never touch the primary checkout."

## What counts as "always-on"

Anything injected into every session: the project CLAUDE.md (or equivalent), everything
your harness auto-loads (in Claude Code: all of `.claude/rules/*.md`, whether or not it
is @imported), the global user CLAUDE.md, global rules, and skill/command frontmatter
descriptions. Skill BODIES are lazy-loaded and cheap; their DESCRIPTIONS are not.

## Classify every block of every always-on file

**KEEP (compress if verbose)** - things the model cannot know or that encode real
external constraints:

- Environment facts: credential locations, project/account IDs, hostnames, test
  users/phone numbers/OTPs, API endpoints, port numbers, tenant mappings.
- Real tooling/harness bugs and their workarounds - but only if they still reproduce.
  Compress to symptom + fix; delete the discovery narrative.
- Pointers to structural enforcement: "X is enforced by test Y / hook Z" one-liners.
- Safety rails around irreversible operations (destructive migrations, secret rotation,
  customer-facing sends).

The test for every kept line: "could the model know this without being told?" If yes,
it goes.

**DELETE** - instructions correcting behaviors modern models already have:

- Generic engineering advice: "research before implementing", "don't over-engineer",
  "use the right tool", "prefer libraries", "be concise", "verify your work", "explore
  the codebase first", "commit often".
- Multi-paragraph "why" narratives and dated anecdotes. If the rule survives, one line
  states it; the story goes to an archive file or dies.
- Anything duplicated across global config, project config, and skills. One home per
  fact - prefer the lazy-loaded home.
- Stale references: any instruction naming a file/script/flag/URL gets verified (grep)
  before it is kept. Dead reference = delete or fix the instruction.
- Rules about workflows that no longer run or projects that shipped/died.

**ARCHIVE (move out of the auto-load path, keep in the repo)**:

- Gotchas older than ~2 months. Move them verbatim to `docs/gotchas-archive.md` (not
  auto-loaded) so any entry can be restored the day a model actually stumbles on it.
- Design/migration history, postmortems, launch narratives.

**CONSOLIDATE**:

- Multiple overlapping files on one topic (three testing docs, two style guides) become
  one file containing only the env facts and non-obvious commands.
- Reference DATA masquerading as rules (decision logs, inventories, profiles) moves to
  `docs/` behind a <=15-line pointer rule that says what lives where and when to read it.

## Dead code (optional second axis)

- **Tier 1 - delete in this PR**: files with ZERO references repo-wide (grep the filename
  AND basename across the repo, including CI config, package manifests, docs, and any
  global agent config that might reference them) that are also clearly one-off: dated
  repair/backfill scripts for closed issues, superseded-by-name files, .bak/tmp
  artifacts. If the repo has a type-checker or test suite and you delete anything
  imported/compiled, run it green or don't delete.
- **Tier 2 - list in the PR body, do NOT delete**: anything imported/compiled, tests, or
  anything requiring a full suite run to be confident about. A visible candidate list
  beats a risky deletion.
- Never delete: migrations, anything referenced by CI, hooks/settings (flag them
  instead - they encode enforcement, which is what should survive ablation).

## Process

1. Branch from origin/main in a fresh worktree; never edit the primary checkout (it may
   hold uncommitted work).
2. Compress files IN PLACE - keep paths stable, other things may reference them. Only
   fully delete files that nothing references.
3. Record `wc -w` before/after for every touched file; put the table in the PR body,
   plus the Tier-2 list and any cross-repo references that now need updating.
4. Verify before merge: every credential pointer, magic value, and live workaround
   survived; no secrets in the diff or PR body; nothing touched outside the intended
   paths.
5. After merge: live with it. Only re-add an instruction after the model repeatedly
   stumbles without it - restore the single archived entry, not the pile.
