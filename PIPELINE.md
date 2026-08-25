# Agent Pipeline

This repo defines a set of Claude Code subagents (`.claude/agents/*.md`) that together form one pipeline:

```
User prompt (+ optional attachment)
        │
        ▼
1. prompt-creator-agent   → writes .claude/briefs/<date>-<slug>.md, picks a lane
        │                    (design | mobile | exec-insights | process | data-pipeline | analysis |
        │                     architecture | docs | mixed)
        ▼
1.5. architect-agent      → ONLY if the brief needs one (new component/integration/tech-stack
        │                    decision) → writes an ADR at .claude/architecture/, required
        │                    reading for the builder below. Skipped for most briefs.
        ▼
2. The builder for the lane:
        │  - design        → frontend-design-agent  (web/desktop UI, brand, content, motion, a11y)
        │  - mobile        → mobile-app-agent        (native iOS/Android — ONLY on explicit confirmation)
        │  - exec-insights → exec-agent
        │  - process       → project-manager-agent
        │  - data-pipeline → data-engineer-agent
        │  - analysis      → data-scientist-agent    (stats/forecasting — checks data adequacy FIRST,
        │                     may refuse rather than fake rigor on data too small/synthetic to support it)
        │  - docs          → documentation-agent     (edits docs directly — see its own file for why that's still branch+PR)
        │    implements on a feature branch, commits, STOPS (no push)
        ▼
3. data-privacy-agent     → scans the diff/data for PII, secrets, exposure risk → SAFE / CAUTION / BLOCK
        │                    (BLOCK stops everything here, escalated directly — nothing below this runs)
        ▼
4. compliance-agent       → legal/contractual/licensing check, consumes step 3's findings → COMPLIANT / NEEDS REVIEW / BLOCK
        │
        ▼
5. quality-agent          → content/code quality gate, all lanes → PASS / REVISE / BLOCK
        │
        ▼
6. dashboard-scrutiny-agent (design lane only — mobile has no equivalent reviewer yet, see Known Gaps)
        │  → UI/UX/accessibility critique → PASS / REVISE / BLOCK
        ├─ REVISE from step 5 or 6 (max 2 rounds each) ──► back to step 2 with the "Required Fixes" list as input
        ├─ BLOCK (any gate) ──► stop, report to user directly, no PR
        └─ PASS ──► continue
        │
        ▼
7. ai-governance-agent    → audits disclosure, human-checkpoints, provenance for this round → ATTESTED / FLAGGED / ESCALATE
        │
        ▼
8. Open a PR (not a direct push to main)
        │
        ▼
9. User proofreads the PR on GitHub, then merges
```

`admin-control-agent` runs orthogonally to this — it audits whether the sequence above was actually followed (brief exists, every gate ran before any PR, nothing landed on `main` directly) and reports drift. It does not execute the sequence itself. `ai-governance-agent` is not a duplicate of this — `admin-control-agent` checks *stage order*, `ai-governance-agent` checks *whether the process was operated responsibly* (disclosure, human sign-off on irreversible actions, provenance).

`risk-assessment-agent` also runs orthogonally, but at a different altitude than either of those: it doesn't look at one branch or one pipeline run at all. It periodically (or after a major system change — a new data source, a new deployment target, a new external party referenced) rolls up findings from `data-privacy-agent`, `compliance-agent`, and `admin-control-agent` into a single quantified Risk Register (`RISK_REGISTER.md`) covering business operations, project delivery, contracts, and the AI pipeline itself as a source of risk. Think of the three orthogonal agents as three different questions asked at three different scopes: *did we follow the process* (admin-control), *was the process operated responsibly* (ai-governance), *what could actually hurt us, quantified* (risk-assessment).

For a lightweight ad hoc change, running all four per-branch gates (privacy, compliance, quality, governance) may be more process than the change warrants — use judgment, but `data-privacy-agent` is cheap to run and should be the one gate you don't skip, since it's the one that catches something genuinely hard to undo. `risk-assessment-agent` isn't part of that per-change judgment call at all — it's a standing system health check, run on its own cadence regardless of how many small changes happened in between.

## Why a brief instead of the raw prompt

Passing the user's raw message straight to the builder means every downstream agent re-interprets ambiguity differently. `prompt-creator-agent` resolves that once, up front, into one file every later stage reads as ground truth — including what's explicitly *out of scope* (e.g. "don't touch the data/measures"), which is what the Scrutiny Agent checks first.

## Why nothing pushes to `main` directly

The original versions of these agents each ran `git add . && git commit && git push origin main` autonomously, with no branch, no build check, and no review gate. With four independent agents doing that, there's no way to catch a bad change before it's live, no way to review before merge, and a real risk of two agents clobbering the same file. Every agent now stops at "committed to a feature branch" and a PR is only opened once Scrutiny returns PASS — that's what makes "user proofreads" a real gate instead of a post-mortem.

## How to run this in VS Code / Claude Code

There is no automatic chaining between subagents — you (or the top-level Claude session) invoke each stage explicitly, in order, e.g.:

1. "Use prompt-creator-agent on: *make the KPI row match this screenshot* [attachment]"
2. "Use frontend-design-agent with the brief at `.claude/briefs/2026-08-25-kpi-row.md`"
3. "Use data-privacy-agent to check branch `design/kpi-row`" — stop immediately on BLOCK
4. "Use compliance-agent to check the same branch" — stop on BLOCK, surface NEEDS REVIEW to the user
5. "Use quality-agent to check the same branch"
6. "Use dashboard-scrutiny-agent to review branch `design/kpi-row` against that brief"
7. If REVISE from 5 or 6: "Use frontend-design-agent to apply the fixes" → back to 5
8. If all PASS: "Use ai-governance-agent to audit this round" — ESCALATE stops everything, FLAGGED is noted but doesn't block
9. Open the PR (`gh pr create`) and stop for your review — do not auto-merge.

For a request that needs `architect-agent` first (step 1.5) or routes to `mobile-app-agent`, `data-engineer-agent`, or `documentation-agent` instead of `frontend-design-agent` in step 2, the rest of the sequence (privacy → compliance → quality → governance → PR) is the same — only `dashboard-scrutiny-agent` in step 6 is design-lane-specific; other lanes skip straight from quality-agent to ai-governance-agent.

`admin-control-agent` can be run any time you want a portfolio-level check on whether branches/PRs are following this order. `risk-assessment-agent` can be run any time you want the standing Risk Register refreshed — on a schedule (e.g. weekly), or immediately after something like a new data source, new deployment, or new external-party reference lands. `documentation-agent` should be run right after any structural change to this roster itself (a rename, a new agent, a reordering) — not doing so is exactly how `uiux-agent` references survived in five different files after it was renamed to `frontend-design-agent` earlier in this project's history.

## Known gaps this doesn't solve (see chat for full list)

- No CI is wired up to run automatically on the feature branch before the gates review it — each gate runs local build/lint/checks itself via Bash, but there's no GitHub Actions workflow yet.
- No automatic conflict prevention between simultaneously-open branches — `admin-control-agent` detects conflicts after the fact, it doesn't lock files.
- `data-privacy-agent`'s PII pattern matching is heuristic, not exhaustive — it catches the shapes of data described in its spec, not every possible sensitive-data format. Treat a SAFE verdict as "nothing obvious found," not a guarantee.
- `compliance-agent` explicitly does not give legal conclusions — every NEEDS REVIEW/BLOCK still needs an actual human (ideally legal/DPO) decision. There is no agent that can close that loop; a human always has to.
- None of the gates are wired into a CI trigger — like everything else in this pipeline, invoking them is still a manual step per round, not automatic on every commit.
- `mobile-app-agent` output has no dedicated screening agent yet — `dashboard-scrutiny-agent` is explicitly scoped to web/dashboard UX and isn't equipped to judge native HIG/Material compliance. If a native mobile feature is ever actually built, this gap needs closing before treating it as production-ready.
- `architect-agent`'s ADRs aren't currently checked by any gate for staleness — if the system changes enough that an old ADR's context no longer holds, nothing flags that automatically; `documentation-agent`'s periodic run is the closest thing today, but it checks for drift, not architectural obsolescence.
- Stacking a PR's base branch on another still-open feature branch is fragile: if the base branch gets merged to `master`/`main` independently before the stacked PR merges, the stacked commits are silently stranded (this happened twice in this project's own history). Prefer basing new branches on `master`/`main` directly and targeting PRs there, even when building on work from an unmerged branch locally.
