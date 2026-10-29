# Claude Code instruction ablation

A repeatable way to cut the always-on instruction bloat (CLAUDE.md, rules files, skill
descriptions) that quietly degrades coding-agent performance as a setup ages.

Based on Boris Cherny (creator of Claude Code) on the Y Combinator Startup Podcast,
["Boris Cherny: Building Claude Code"](https://podcasts.apple.com/us/podcast/y-combinator-startup-podcast/id1236907421?i=1000778651350),
28 July 2026:

> "A lot of the stuff in the system prompt was correcting for these behaviors that the
> model should have known, but it didn't. Now, Opus 5 just does it."

> "The model is actually a little bit more intelligent without these prompts."

> "Every 6 months delete your CLAUDE.md. Delete your skills. Delete your hooks. See what
> the model does and it might surprise you."

The failure mode this fixes: every always-on instruction is read by the model on every
single request. Instructions accumulate (gotchas, war stories, style rules, advice written
for last year's models) and never leave, because nothing fails when one goes stale. Past a
point the model starts ignoring the pile, including the parts that still matter, and you
pay for the tokens on every turn regardless.

## Method

1. **Measure** - run `./measure-footprint.sh <repo>`. Anything over a few thousand words
   of always-on instructions is a candidate.
2. **Classify** - walk every block of every auto-loaded file against
   [`ablation-rubric.md`](ablation-rubric.md) (KEEP / CUT / ARCHIVE / MERGE). The default
   when unsure: advice gets cut, environment facts get kept.
3. **Cut on a branch** - one PR per repo, with before/after word counts in the PR body so
   the change is reviewable at a glance. Archive, don't destroy: dated war stories move to
   a file that is not auto-loaded, so any line can come back.
4. **Verify** - before merging, confirm the survivors include every credential pointer, ID,
   magic value and tooling workaround (the things a model cannot guess), and that no
   secrets landed in the diff or the PR body.
5. **Add back empirically** - the step people skip. Don't guess what the model needs. Use
   the trimmed setup, and only when the model *repeatedly* stumbles on the same thing do
   you restore that one entry. Every line you add back should name the failure it prevents.

Repeat every six months, or on every major model upgrade.

## Results from one real run

Six repos of a personal/startup portfolio, one pass, August 2026. Agents did the
classification and the edits; a human reviewed every PR.

| Repo type | Before (words) | After | Cut |
|---|---|---|---|
| Product web app | 17,069 | 3,573 | -79% |
| Ops/automation repo | 17,016 | 3,084 | -82% |
| Mobile app | 12,789 | 3,458 | -73% |
| Global config (loads everywhere) | 8,043 | 4,672 | -42% |
| Data pipeline | 5,261 | 2,429 | -54% |
| Docs-heavy private repo | 3,394 | 984 | -71% |
| **Total across repos** | **63,572** | **18,200** | **-71%** |

No single session loads all of that. A session loads one project's files plus the global
config, so the number that actually matters is the worst single session: **25,112 words
(~33k tokens) down to 8,245 (~11k), a 67% cut.** Nothing broke; the four repos that have
CI stayed green, and the two without CI have no build to break.

The most common finds, in rough order of tokens recovered:

- **Stale gotchas** - workarounds for bugs long since fixed, kept "just in case". The
  biggest single file was 10,096 words, and its own header said it should only ever hold
  the current month.
- **Advice the model no longer needs** - "research before implementing", "prefer
  libraries", "verify your work", "commit often". Modern models do these unprompted.
- **Reference data stored as rules** - decision logs, profiles, inventories sitting in an
  always-on rules directory instead of on-demand docs behind a short pointer.
- **Duplicates** - the same rule in global config, project config, and a skill, stated
  three slightly different ways, which is worse than once because they drift.
- **Dead references** - instructions naming files, scripts or flags that no longer exist.
- **Overlapping files** - five separate testing documents that should have been one.
- **Skill/command frontmatter** - in Claude Code a skill *description* loads into every
  session even though the skill *body* is lazy. Multi-paragraph descriptions are a hidden
  always-on cost; trim them to trigger phrases and push the detail into the body.

The find that mattered most was none of those. One repo still carried a rules file from a
migration that had finished months earlier, instructing agents to *never modify* a file
they now routinely needed to edit. Stale instructions do not decay into noise. They decay
into confident, specific, wrong instructions, and the model has no way to tell which is
which.

## Files

- **[`ablation-rubric.md`](ablation-rubric.md)** - the classification rubric and process.
  This is the part to hand to an agent: "read this rubric, then ablate this repo" works as
  a single prompt in any Claude Code session.
- **[`measure-footprint.sh`](measure-footprint.sh)** - measure a repo's always-on
  instruction footprint. Read-only; prints word counts and paths, never file contents.
  It follows `@path` imports out of CLAUDE.md, counts the project's auto-memory index,
  and leaves rules files with `paths:` frontmatter out of the total (they load only on a
  matching file). Without the first two, a CLAUDE.md that is one `@AGENTS.md` line
  measures as almost nothing.
- **[`multi-repo-workflow.js`](multi-repo-workflow.js)** - optional. A Claude Code dynamic
  workflow that runs analyze -> implement -> verify agent pipelines across many repos in
  parallel. If you don't use dynamic workflows, run the rubric prompt once per repo
  instead.

## Longer writeup

[I deleted 71% of my agent instructions](https://ctsheehan.com/writing/ablating-agent-instructions/)
covers what was in the pile, the failure modes, and how the verify stage catches the
implementer.

MIT licensed. Issues and PRs welcome, especially results from other people's setups.
