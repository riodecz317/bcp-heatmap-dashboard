# Data Changelog

Automatically appended by `bcp_publish.ps1` whenever the row set changes — every addition, removal, or ID reuse gets a dated entry here so a change is never silent (see `RISK_REGISTER.md` R-05 in the `shadowrealm-agents` repo for why this exists).

This file starts empty except for this header. The first automated entry below records the exact ID-reuse case that motivated adding this tracking: **`EMP016`** disappeared from the published snapshot between 2026-08-22 and 2026-08-23 (originally "Ricky Dela Torre", per `Executive_Insights_Brief_2026-08-23.md`) with no recorded reason, and was later reused for an unrelated record ("Mark Reyes") in a subsequent snapshot — silently, since no mechanism existed to flag it until now.

## 2026-08-25 (manual backfill, not machine-generated)
- **ID reused (same ID, different person):** EMP016: was "Ricky Dela Torre" (removed 2026-08-23, cause unrecorded), now "Mark Reyes" — flagged retroactively while adding this changelog; not caught at the time it happened.
