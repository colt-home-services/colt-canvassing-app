# Live export reconciliation — September 28, 2026

Result: no discrepancies in the checks described below. All 28 local reconciliation tests passed. All database statements were SELECTs executed inside explicitly read-only transactions. No application data or schema was modified.

The linked Supabase project was confirmed to match the project configured in `lib/main.dart`.

The main database snapshot was taken at **2026-09-28 19:03:23 UTC** in a repeatable-read, read-only transaction. It contained 405 daily summary rows, 475 allowed shifts, and four saved daily overrides. Eight disallowed shifts were excluded. One allowed shift remained open.

## Checks performed

- Independently aggregated database summary rows with saved manager overrides, allowed shift rows, and shift/knock overlap dates using SQL.
- Ran the dashboard's current aggregation methods, extracted unchanged into a temporary local test harness, against that snapshot. Applied adjustments with the application's actual `DailyMetricOverrideService`.
- Compared every aggregation field with SQL for all history, September 14–28, the latest activity date, an empty future date, and each of 22 team members: 26 scenarios.
- Used the actual `summaryExportRows` and `encodeSpreadsheet` functions to generate exports. Checked 16 formatted metrics per scenario, then parsed the generated CSVs independently with Python's CSV reader: **416 matching values**.
- Compared live shift-view duration, New York work date, and signup values against the underlying `shifts` table: zero discrepancies.
- Used a second read-only snapshot at **19:05:31 UTC** to check the most active ZIP. Its 36 matching daily rows reconciled to 2,750 knocks, 513 answers, 74 signups, and 123.00 knock hours. Shift metrics were excluded. The application's New York midnight query boundaries matched the database's New York date calculation for every summary day tested.

## Recent-period example

September 14–28, inclusive, at the snapshot time:

| Metric | Database and export |
| --- | ---: |
| Knocks | 1,764 |
| Answers | 363 |
| Signups | 86 |
| Shift signups | 56 |
| Knock hours | 124.00 |
| Shift hours | 111.74 |
| Total hours | 235.74 |
| Overlap days | 10 |

## Scope and limits

This verifies the local implementation's calculations and CSV formatting against live database snapshots. It does not verify a deployed browser download, clipboard permissions, or an authenticated manager's PostgREST/RLS access. The database reads used the configured CLI connection.

The conversion rate is stored locally rather than in the database. A 50% test rate was used to validate the derived audit and cost formulas; it is not a verified live business rate. These remain estimates, not recorded payroll payments.

One open shift means hours can change after the snapshot. Total hours retain the application's existing shift-plus-knock calculation and overlap warning; reconciliation does not mean overlapping hours have been deduplicated.

The app refreshes before export and checks paginated row counts, but its multiple requests are not one transactional snapshot. This check therefore establishes correctness for the sampled snapshots, not a guarantee against concurrent edits during every future export.

Raw snapshots and generated CSVs were kept in a temporary local directory, not added to the repository. The verification required no application-code changes.

## Follow-up: per-canvasser payroll layout

The row-per-canvasser export was implemented after the database snapshot above. The earlier 26-scenario reconciliation verifies the underlying range totals and the per-person source fields, but does **not** verify the newly introduced `canvasserPayrollRows` grouping/layout against that snapshot. The payroll-row layout has only been checked with static analysis so far; it has not been covered by tests or re-run against live data.
