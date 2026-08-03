// Claude Code dynamic-workflow script: instruction ablation across many repos at once.
// Each repo flows through analyze -> implement -> verify independently (no barriers).
//
// Usage: in a Claude Code session, ask for a workflow and pass args like:
//   { "brief": "/abs/path/to/ablation-rubric.md",
//     "tmp":   "/abs/path/for/plan/files",
//     "repos": [ { "name": "my-app",
//                  "path": "/abs/path/to/my-app",
//                  "wtPath": "/abs/path/to/my-app-worktrees/ablation",
//                  "notes": "repo-specific targets, dirty-checkout warnings, no-go zones" } ] }
//
// If you don't use dynamic workflows: skip this file and run the rubric as a single
// prompt per repo ("read ablation-rubric.md, then ablate this repo").

export const meta = {
  name: 'instruction-ablation-sweep',
  description: 'Ablate always-on instruction bloat + dead code across repos; one PR each',
  phases: [
    { title: 'Analyze', detail: 'per-repo keep/delete/archive plan' },
    { title: 'Implement', detail: 'worktree, cuts, PR' },
    { title: 'Verify', detail: 'diff sanity + KEEP-survival check' },
  ],
}

const A = typeof args === 'string' ? JSON.parse(args) : args
const BRIEF = A.brief
const TMP = A.tmp
const repos = A.repos

log(`Ablation sweep over ${repos.length} repos`)

const results = await pipeline(
  repos,

  // 1. ANALYZE (read-only): classify every always-on block, write a concrete plan.
  (r) => agent(
    `You are the ANALYSIS agent for an instruction-ablation sweep. READ-ONLY: do not edit
any repo file; your only write is your plan file.

FIRST read the rubric at ${BRIEF} and follow it exactly. Repo: ${r.path}
Repo-specific notes: ${r.notes}

1. Inventory every always-on instruction file (CLAUDE.md, .claude/rules/*.md - the
   harness auto-loads ALL of rules/, @imported or not - and skill frontmatter).
2. Classify every block KEEP/DELETE/ARCHIVE/CONSOLIDATE with one-line justifications.
   For every kept line: "the model couldn't know this."
3. Grep-verify every file/script/flag an instruction references still exists.
4. List Tier-1 dead-file candidates WITH zero-reference grep evidence; Tier-2 separately.
5. Note any target file that is dirty in the primary checkout (implement agent must base
   those on the live file, not origin/main, or it will revert uncommitted work on merge).

Write the full plan to ${TMP}/plan-${r.name}.md with exact per-file edit instructions and
before/projected-after word counts. Return AT MOST 10 lines: plan path, totals, top cuts.`,
    { label: `analyze:${r.name}`, phase: 'Analyze' }
  ),

  // 2. IMPLEMENT: worktree -> cuts -> PR. Never touches the primary checkout.
  (analysis, r) => {
    if (!analysis) { log(`SKIP implement:${r.name} - analysis died`); return null }
    return agent(
      `You are the IMPLEMENT agent for an instruction-ablation sweep on ${r.path}.
Read the rubric at ${BRIEF}, then your plan at ${TMP}/plan-${r.name}.md.
Analysis summary:\n${analysis}\n
1. git -C ${r.path} fetch origin main -q && git -C ${r.path} worktree add ${r.wtPath} origin/main -b ablate/instructions
   (suffix the branch and worktree path if either already exists, so a second run does not collide)
   NEVER edit the primary checkout; absolute paths everywhere.
2. If the plan flagged dirty-base files, cp the live file in as your editing base and say
   so in the PR body.
3. Apply the plan: compress KEEP in place, delete DELETE, move ARCHIVE content to archive
   files, consolidate as planned, delete only Tier-1 dead files. Keep paths stable.
4. Record wc -w before/after for every touched file.
5. If you deleted compiled/imported code, run the repo's type-check/tests green - or
   demote the deletion to Tier-2.
6. Commit, push -u, then open the PR in a SEPARATE command (title
   "chore(ablation): cut always-on instruction bloat"; body = before/after table +
   Tier-2 list). Follow your team's merge policy from there.
Return AT MOST 12 lines, first line "PR: <url>" (or "PR: NONE - <why>").`,
      { label: `implement:${r.name}`, phase: 'Implement' }
    )
  },

  // 3. VERIFY: adversarial check before anyone merges.
  (impl, r) => {
    if (!impl) { log(`SKIP verify:${r.name} - implement died`); return null }
    return agent(
      `You are the VERIFY agent for an instruction-ablation PR on ${r.path}.
Implement agent reported:\n${impl}\nPlan: ${TMP}/plan-${r.name}.md (its KEEP list is the contract).
Using gh pr view / gh pr diff:
1. Scan the full diff AND the PR body for secrets, tokens, or sensitive business content.
2. Pick 5 KEEP items from the plan (prioritize credential pointers, magic test values,
   tooling workarounds) and confirm each survives in the head-branch files.
3. Confirm the diff touches nothing outside the intended paths (no hooks/, settings,
   CI config, migrations).
4. Confirm the PR body has the before/after table and Tier-2 list.
If anything CRITICAL: comment on the PR and say so. Return AT MOST 6 lines:
verdict (OK/BLOCKED/WARN), PR URL, notes.`,
      { label: `verify:${r.name}`, phase: 'Verify' }
    )
  }
)

const out = results.filter(Boolean)
log(`Sweep finished: ${out.length}/${repos.length} repos produced a verdict`)
return out
