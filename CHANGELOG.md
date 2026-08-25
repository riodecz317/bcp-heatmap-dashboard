# Changelog

This project had no changelog, no GitHub Releases, and no tags before this file — reconstructed from the full commit history (91 commits, 2026-08-23 onward) rather than starting from a blank slate. Individual "Agent UI/UX Update" commits during the 2026-08-24 visual design overhaul are grouped by theme below rather than listed one-by-one; see `git log` for the full blow-by-blow if needed. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

Going forward: add an entry here for anything that changes what a user of the dashboard sees or how the pipeline behaves. Day-to-day "Auto-refresh published snapshot" data commits are not logged here — those are tracked in `DATA_CHANGELOG.md` instead, which records *what data changed* (additions/removals/ID reuse), not routine refreshes.

## [Unreleased]
Pending merge in `bcp-heatmap-dashboard` PR #4.
### Fixed
- **Critical:** `bcp_publish.ps1` now blocks the automated publish if the source data contains an account name that isn't on an approved (confirmed-fictional) list, instead of pushing anything Power BI returns straight to public `main` unchecked.
- Real enterprise account names (Deloitte, JP Morgan, Microsoft, Azure) replaced with fictional ones (Contoso, Fabrikam, Northwind Traders, Tailwind Traders) in `bcp_data.json` and the dashboard's offline fallback data.
### Added
- `DATA_CHANGELOG.md` — automated per-publish record of added/removed/reused record IDs, so a change like the historical `EMP016` disappearance (see below) is never silent again.
- This file.

## [2026-08-25] — Governance pipeline agents synced in
### Added
- `.claude/agents/`: `data-privacy-agent`, `compliance-agent`, `quality-agent`, `ai-governance-agent`, `risk-assessment-agent`, `architect-agent`, `data-engineer-agent`, `mobile-app-agent`, `documentation-agent` — vendored in from the `shadowrealm-agents` pipeline repo.
- `PIPELINE.md` documenting the full review pipeline.
### Changed
- `uiux-agent` renamed and scope-expanded to `frontend-design-agent` (agent-pipeline change, not dashboard-facing).
### Fixed
- Province table (`Impact by Provinces`) and the heat map now expose proper ARIA roles/labels for screen readers.
- Dashboard now shows an explicit staleness warning (instead of looking identical to a fresh load) when the published snapshot or the offline fallback data is stale.

## [2026-08-24] — Visual design overhaul
### Changed
- Rebuilt the dashboard shell multiple times over the course of the day, converging on a zero-scroll, single-screen, 3-column "command center" layout (header/exec-summary banner, 6-card KPI row, main grid, office-sites footer strip).
- Explored and discarded several full visual "skins" (Apple Vision Pro pastel, Lightcore Prism, MoonRow, Walenteer orange-gradient) before settling on the current design-token-based palette.
- Status chart went through several iterations (stacked bar → donut → back to stacked bar) before landing on the current horizontal stacked bar with inline counts.
- `Impact by Provinces` rebuilt from a plain table into a pastel floating-row list with status pills, then had multiple readability passes (column alignment, row height, truncation fixes).
- Added the **Needed Help** filter to the banner filter cluster.
- Enriched Case Feed cards with Account/LOB detail.
### Fixed
- Critical: a heatmap empty-state bug that could destroy `#heatmapTable` and break every card rendered after it in the DOM.
- Multiple color-contrast issues (white text on dark fills, illegible status pills) — the strict status-color-token system now in place (`--status-good/warning/critical` + `-text`/`-soft` variants) exists specifically because of this recurring bug class.
- Card padding/spacing standardized to 16px across all cards after several inconsistent overrides were found.
### Data
- Published snapshot grew from 15 to 30 rows during this period.

## [2026-08-23] — Initial release
### Added
- Initial Executive BCP heatmap dashboard: Power BI model (`Heatmap.pbix`) + HTML/JS dashboard (`Heatmap_Dashboard.html`), Leaflet-based geographic heat map, KPI row, Case Feed, Impact by Account/Line of Business breakdowns.
- Local live-data bridge (`bcp_bridge.ps1`) for viewing live Power BI data from a `file://` page on the same machine.
- Scheduled GitHub Pages publish pipeline (`bcp_publish.ps1`, `bcp_watcher.ps1`) so a hosted copy stays current without manual publishing.
- First Executive Insights Brief (`Executive_Insights_Brief_2026-08-23.md`) — narrative BI analysis of the dataset.
- Dynamic, auto-generated Executive Summary module on the dashboard itself.
### Fixed
- **Security:** tightened the local bridge's CORS policy to close a data-exposure hole where any website (not just this dashboard) could have read live data from a machine running the bridge.
- A critical data-truncation bug in `ConvertTo-JsonArray` (single-row results were being written malformed).
- `bcp_publish.ps1` now checks `bcp_data.json` and `index.html` for changes independently, so a code-only fix isn't silently held back until the data also happens to change.
- Visible PowerShell window flash from the scheduled publish task.
### Removed
- Several files unrelated to the BCP dashboard project that had been committed alongside the initial import (stray geography reference files).

## Known unresolved data-quality issue, predates this changelog
`EMP016` (originally "Ricky Dela Torre," per `Executive_Insights_Brief_2026-08-23.md`) disappeared from the published snapshot between the 2026-08-22 and 2026-08-23 runs with no recorded reason, and the same ID was later reused for an unrelated record ("Mark Reyes") in a subsequent snapshot. Neither event was caught at the time — `DATA_CHANGELOG.md` exists specifically so this doesn't happen silently again.
