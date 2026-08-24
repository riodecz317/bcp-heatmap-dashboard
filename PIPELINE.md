# Agent Pipeline

This repo defines a set of Claude Code subagents (`.claude/agents/*.md`) that together form one pipeline:

```
User prompt (+ optional attachment)
        │
        ▼
1. prompt-creator-agent   → writes .claude/briefs/<date>-<slug>.md
        │
        ▼
2. uiux-agent / exec-agent / project-manager-agent   → implements on a feature branch, commits, STOPS (no push)
        │
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
6. dashboard-scrutiny-agent (uiux lane only) → UI/UX/accessibility critique → PASS / REVISE / BLOCK
        │
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
2. "Use uiux-agent with the brief at `.claude/briefs/2026-08-25-kpi-row.md`"
3. "Use data-privacy-agent to check branch `uiux/kpi-row`" — stop immediately on BLOCK
4. "Use compliance-agent to check the same branch" — stop on BLOCK, surface NEEDS REVIEW to the user
5. "Use quality-agent to check the same branch"
6. "Use dashboard-scrutiny-agent to review branch `uiux/kpi-row` against that brief"
7. If REVISE from 5 or 6: "Use uiux-agent to apply the fixes" → back to 5
8. If all PASS: "Use ai-governance-agent to audit this round" — ESCALATE stops everything, FLAGGED is noted but doesn't block
9. Open the PR (`gh pr create`) and stop for your review — do not auto-merge.

`admin-control-agent` can be run any time you want a portfolio-level check on whether branches/PRs are following this order. `risk-assessment-agent` can be run any time you want the standing Risk Register refreshed — on a schedule (e.g. weekly), or immediately after something like a new data source, new deployment, or new external-party reference lands.

## Known gaps this doesn't solve (see chat for full list)

- No CI is wired up to run automatically on the feature branch before the gates review it — each gate runs local build/lint/checks itself via Bash, but there's no GitHub Actions workflow yet.
- No automatic conflict prevention between simultaneously-open branches — `admin-control-agent` detects conflicts after the fact, it doesn't lock files.
- `data-privacy-agent`'s PII pattern matching is heuristic, not exhaustive — it catches the shapes of data described in its spec, not every possible sensitive-data format. Treat a SAFE verdict as "nothing obvious found," not a guarantee.
- `compliance-agent` explicitly does not give legal conclusions — every NEEDS REVIEW/BLOCK still needs an actual human (ideally legal/DPO) decision. There is no agent that can close that loop; a human always has to.
- None of the four new gates (privacy, compliance, quality, governance) are wired into a CI trigger — like everything else in this pipeline, invoking them is still a manual step per round, not automatic on every commit.
