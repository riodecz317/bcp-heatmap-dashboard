# Executive Insights Brief — BCP Heatmap
**Date:** August 23, 2026 | **Data source:** `bcp_data.json` (15 records) vs. prior snapshot (16 records, commit `c9bff00`)

## Executive Summary
Business continuity exposure improved this period: active cases fell from **10 to 7 (-30%)** and resolved cases rose from **3 to 5 (+67%)**, with monitoring holding steady at 3. However, the concentration of risk is worsening, not improving — **4 of 7 active cases (57%) are now clustered in Metro Manila**, and **71% of active cases still require material assistance** (generators, ISP failover, structural inspection). Separately, the live publish pipeline is currently stalled: Power BI Desktop is not running, so BCP Dashboard Auto-Publish has been disabled since 08:54 and has not refreshed for **20+ consecutive cycles**.

## Top Risks (Red Flags)
1. **Metro Manila / NCR concentration risk** — 4 of 7 active cases (Maria Santos, Patricia Go, Eduardo Santos, John Dela Cruz) are in NCR, spanning three distinct hazard types (Typhoon, Internet Outage, Power Outage). A single regional event is now capable of impacting the majority of open cases.
2. **Auto-publish pipeline is down** — `bcp_watcher.log` shows Power BI Desktop has been offline since 08:54, disabling the dashboard refresh bridge for over 2 hours as of last log entry. Executive-facing views (Heatmap_Dashboard.html / GitHub Pages) may be showing stale data if this isn't restored.
3. **Unmet assistance requests among active cases** — 5 of 7 active cases (71%) have outstanding help requests (generators, backup ISP, UPS/flashlights), including two typhoon-driven Metro Manila cases still awaiting response.

## Trends & Observations
- **Status mix is shifting favorably**: Active caseload down 30% period-over-period (10 → 7); this is largely genuine resolution, not data loss — Pedro Gil (Earthquake, Batangas) and Ana Reyes (Typhoon, Metro Manila) both moved Active → Resolved.
- **One case dropped off the register**: EMP016 (Ricky Dela Torre, Flooded/Typhoon, Mandaluyong, help requested) present in the prior snapshot is absent from the current one. Confirm whether this reflects resolution-and-removal or a data sync gap before treating the improvement as fully validated.
- **Typhoon remains the dominant hazard** among active cases (3 of 7), followed by Internet Outage (2) and one each of Power Outage and Earthquake.
- **Help-needed ratio is improving**: 81% of all cases required help last period vs. 67% this period — a positive signal even though the currently-open cases skew toward higher unmet need (71%).

## Benchmarking (Current vs. Prior Period)
| Metric | Prior (16 rows) | Current (15 rows) | Change |
|---|---|---|---|
| Active | 10 | 7 | -30% |
| Monitoring | 3 | 3 | flat |
| Resolved | 3 | 5 | +67% |
| Help requested (all statuses) | 13 (81%) | 10 (67%) | -14 pts |
| NCR share of active cases | 5 of 10 (50%) | 4 of 7 (57%) | +7 pts |

## Strategic Recommendations
1. **Restart Power BI Desktop / the auto-publish bridge immediately** and add a monitoring alert so a future Power BI shutdown doesn't silently freeze the executive dashboard for hours.
2. **Stand up an NCR-specific contingency plan** (shared generator/ISP failover pool) given that over half of remaining active cases sit in one region — the current one-off-per-case response doesn't address the concentration.
3. **Audit the EMP016 record removal** to confirm it reflects genuine resolution rather than a data pipeline gap, and add a change log to `bcp_data.json` updates so record removals are traceable going forward.

## Data Quality Note
Dataset is small (n=15) and appears to be a fixed simulation/demo set (e.g., "Jose Rizal" as an employee ID) rather than a live production feed — treat percentages as directional, not statistically robust.

## Dashboard Update Needed
`Heatmap_Dashboard.html` — update the **Active Cases** and **Help Needed** executive cards/KPI tiles to reflect 7 active / 10 help-needed-total, and flag the NCR cluster in the regional heatmap card.
