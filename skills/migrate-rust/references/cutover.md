# cutover · write paths, backfill, reconciliation, rollback, ramp

**Read this file in full** before you plan any switch of live traffic or data: dual-write, shadow, backfill, reconciliation, rollback, canary or ramp. Later steps (one-way doors, consumer notification, decommission, client releases, security-driven migrations) are in closeout.md; the transitions.md ledger is templates.md §4. Rules: SKILL R1–R6; numbers: Default strictness table. Numeric gates go into `acceptance.md` before the run.

**Most often missed here**
- §1 Every step in your plan has its own rollback cell. A step without one is a one-way door and moves after the observation window.
- §2 Every write path gets its own test that goes red when that path's dual-write is commented out.
- §3 Before adding a constraint, count the existing rows that violate it, using the constraint's exact semantics.
- §4 Reconciliation first asserts its denominator: rows compared == source `COUNT(*)`, tables compared == expected list.
- §6 Ramp gates: dual-read mismatch per write path (a path with 0 comparisons fails); error and p99 deltas per seam unit; the shadow stage has 0 real outbound side effects.

**Sections** · §1 In what order, and where is each step's gate? · §2 Are all write paths and side effects covered? · §3 How do I backfill safely? · §4 How do I reconcile, and is the new side complete? · §5 Can I roll back by flipping a switch? · §6 What gate does each ramp stage pass?

## 1. Order of steps (also the table of contents)
Go in order. Every step can stop and roll back; irreversible steps come last. Pass conditions are written only in the section each row points to.

| Step | What | Detail |
|---|---|---|
| 1 | List every consumer, one decision per row | closeout §2 |
| 2 | Ship the compatibility layer first (new reads old format, old reads new format) and run it in production for one full release cycle | closeout §1 |
| 3 | Wire up every write path (dual-write or shadow write), each with a test that can go red | §2 |
| 4 | Backfill: dry-run → batched real run → reconciliation after each batch | §3, §4 |
| 5 | Rollback drill | §5 |
| 6 | Ramp by stage; the gate is dual-read mismatch counted per write path | §6 |
| 7 | Observation window | Default strictness table, observation-window row; date assertions in closeout §1 |
| 8 | Make old-path use fail loudly; zero-call evidence at every layer | closeout §3 |
| 9 | Measure coverage ranges, set a disposition, reconcile table by table, keep a snapshot | §4, closeout §3 |
| 10 | Delete, archive, residue reaches zero in CI | closeout §3 |
| — | Transitional-artifact ledger and expiry check | templates §4 |
| — | Client-distributed artifacts (no server-side switch) | closeout §4 |
| — | Someone changes the old system during dual-run | closeout §5 |
| — | Security-driven migrations: fail closed | closeout §6 |

*Why: once a one-way door (drop a table, add NOT NULL, stop old writes) is passed early, a problem found in any later step can no longer be undone.*

Machine check for your own plan: list every step as a row `step | gate | rollback (command or switch) | rollback tested?`. A row with an empty rollback cell is a one-way door: move it after the observation window (closeout §1), or give it a rollback.

## 2. Write paths and side effects: wire them all before ramping
**List the write paths in a table. Wire them one by one, each with a test that can go red.**
- Sources: repo-wide `rg` for write calls (ORM save/update/delete; raw SQL INSERT/UPDATE/DELETE/UPSERT; message publish; file writes), scheduled jobs, admin consoles, ops scripts, database triggers, callbacks from external systems.
- One row each: entry point, table written, dual-written yet?, test name.
- Test: write once through this path only and assert the row appears on both sides. Comment out this path's dual-write and the test must go red (R2).

*Why: a reconciliation residue of 0 only says the two sides matched at reconciliation time. A missed write path may simply have had no traffic then and start losing data after the ramp.*

**For every write after an await, retry or backfill step, state the cancellation and transaction semantics.** For each point answer: what is left behind if the task is cancelled or the process killed just before this line; can a retry write twice; is the external call (publish, payment, email) inside the database transaction?
By default keep external calls outside the transaction and get exactly-once through an outbox table or an idempotency key.
*Why: a rollback cannot recall a message already sent. "Give up halfway and redo the whole thing on the old implementation" also calls side-effecting callbacks twice.*

```bash
# Machine check: external calls inside a transaction body should be 0 (rough screen: the transaction
# syntax and client names are examples, adapt to the project; inspect any hit by hand)
rg -n -U 'transaction\.atomic|BEGIN' -A 30 src/ | rg -c 'requests\.|httpx\.|publish\(|send_mail' || true
```
Chaos test: inject kill -9 and network loss before and after every write point, then reconcile. Mismatches = 0, and each side effect happens exactly 1 time.

### 2.1 Temporary bridges (triggers, CDC): assess each item before choosing one

**A bridge is a transport, not write-path coverage.** Every row in the write-path table still needs its own test that can go red. The bridge gets its own row of type "bridge" and goes into transitions.md.
*Why: a bridge cannot see writes that bypass the watched table (direct writes to the new table, another database, files, messages), and it hides a missed write path behind "the data arrived".*

Before choosing a bridge, treat each item below as a possible difference to diff-test, with the old side's behavior taking precedence. Treat deviations caused by the bridge as new differences, not as "normal bridge behavior".
Write the conclusion into the alternatives table in `decisions.md` (same numeric columns for every option: duplicate writes, added write latency ms, sync lag p99 s, false mismatches).

| Item | Possible difference to diff-test | How to diff-test |
|---|---|---|
| Stacking with app-level dual-write | The app writes once and the bridge copies again: duplicate rows, doubled counts, a late write overwriting an earlier one (only under post-ramp concurrency) | Write once per write path; assert the new-table row appears once and its final value = old-side value; rerun with bridge and dual-write both on |
| Synchronous trigger inside the transaction | Higher old-side write latency, longer locks, a trigger failure rolling back the old write (old-side semantics are consumer-visible, R5) | On one machine, alternate old/new and measure old write-path p99; increase ≤ the gate in acceptance.md; inject a trigger failure and assert the old side behaves as with no bridge |
| Async bridge (CDC) lag | Not-yet-caught-up rows counted as mismatches, or real differences dismissed as lag | Compare only writes before the confirmed position; count rows over the lag gate separately, neither merged into mismatches nor dropped |
| Coverage | Watched tables and operations (TRUNCATE, DDL, bulk import) miss some write paths | Mark each write-path row "visible to bridge or not"; wire the invisible ones at app level |
| Switching back | On rollback the bridge reverses and creates a new→old→new loop | Run the §5 drill once with the bridge on; assert no loop and `missing_rows_after_rollback = 0` |

## 3. Backfill: dry-run, batches, idempotence

**Dry-run for counts first, then run for real. The two must be equal.** The dry-run only reads and counts: how many rows change, under which condition, in how many batches. The real run logs affected rows per batch; compare the total with the dry-run.
*Why: unequal counts mean the condition is wrong or the data changed after the dry-run. Find out which before continuing.*

**Reconcile each batch as soon as it is written; don't wait for the full run.** Size batches by the write-freeze window or lock duration. Measure migrate, verify and roll back separately and write the total into acceptance.md. If a batch fails reconciliation, stop at that batch.

**Backfills must be idempotent and rerunnable.** Use upsert or a "only rows not yet processed" condition, with a batch number or watermark. Kill midway and rerun: the final per-row hash equals a single clean run. Drill "kill halfway, rerun" once.
*Why: backfills almost always get interrupted (timeouts, lock conflicts, deploys). Without idempotence the only fix is hand-repairing data.*

**Fix data that is already inconsistent before migrating it, and keep reconciliation as a safety net.** Count rows that violate constraints (orphan foreign keys, duplicate keys, illegal enum values) first. Count them under the exact semantics of the constraint you are about to add: a case-insensitive or collation-aware UNIQUE needs the duplicate count after case folding or collation, and trimming and NULL handling must match. Decide the fix per R6, fix, then backfill. Keep the reconciliation script until the observation window ends.

**After splitting a table or changing its shape, aggregate the new tables back into the old shape and compare.** JOIN or GROUP BY the new structure back into the old one and compare row by row with the old table. Comparing only new-table row counts misses "part of it was lost in the split".

## 4. Reconciliation and per-table checks: fixed denominator, measure coverage first

**Assert the denominator before judging differences.** The reconciliation script first asserts "tables compared = length of the expected table list" and "rows compared per table = source `COUNT(*)`", and exits non-zero if either is 0. Skipped tables may not exceed the baseline. Only then look at the difference count.
*Why: selecting 0 cases still reports "0 differences". A reconciliation script can likewise compare an empty set because of a misspelled table name or a wrong filter.*

**Derive comparison-unit IDs from content, not position.** Shards, cases and batches use the primary key or a content hash, not a sequence number.

**Metric queries must assert exactly 1 series.** Many tools treat 0 series as "no errors", and with several series it is unclear which one you read. The script asserts series count = 1, then reads the value.

**Comparisons use no normalizer by default (R2).** Only columns where the old implementation is itself nondeterministic (order, generation time, addresses) switch to invariant or set comparison, written as an equivalence rule with a counterexample. Any other loosening (tolerance, dropped columns, allowed extra rows) is escalated to the owner per R6(b).

### 4.1 Measure coverage ranges, then decide the disposition

Premises about data scope from the task or docs ("the new DB only has the last few months", "nobody writes the old table any more") are not facts (R1).
Before deciding any table's disposition, run a query on both old and new databases for each table's time column: min, max and row count. Paste the results into the reconciliation output.
- Tables without a time column: name the substitute column (auto-increment key, batch number), or record "no time column" and say how coverage is judged.
- New range narrower than old: the gap is what must be backfilled or archived. Don't treat the new DB as complete.
- Old max later than the write-stop date: something still writes. Go back to §2 and find the missed write path.

Dispositions (exactly one per table, written as `disposition` and `reason` in the reconciliation output):
| Disposition | When | Evidence |
|---|---|---|
| Migrate and reconcile per table | Consumers read it and the new side keeps using it | All zeros in this section's output |
| Archive only, don't migrate | Retention or retrieval obligation, but the new system doesn't read it | closeout §3 retrieval drill |
| Cache/session data → discard | Data rebuildable from source or useless once expired (caches, sessions, temporary tokens, materialized results) | Reason: where it rebuilds from or why it expires; checked that no consumer depends on its history |
| Escalate to the owner | Discarding or reshaping changes what existing consumers see, and the task didn't authorize it | Item in `pending-decisions.md` per R6(b), with recommendation and default |

**The per-table reconciliation output has fixed fields:**
```yaml
reconcile:
  run_at: <ISO-8601 time>
  snapshot: <snapshot path>          # snapshot used for this run; keep until the table is dropped
  tables_expected: <expected count>
  tables_compared: <same>            # must == tables_expected
  tables_mismatch: 0                 # counts any table whose row count, PK hash or coverage range differs
  missing_rows: 0                    # in old, not in new
  extra_rows: 0                      # in new, not in old; must be 0 by default, loosening per R6(b)
  per_table:                         # disposition: migrate / archive / discard / owner; reason required for discard and owner
    - {name: <table>, disposition: migrate, reason: "", time_column: <col>, old_count: <n>, new_count: <n>, pk_hash_old: "<h>", pk_hash_new: "<h>",
       coverage_old: {min: "<time>", max: "<time>"}, coverage_new: {min: "<time>", max: "<time>"}}   # coverage: measured on each DB
```
Human-readable summary columns: table | disposition / reason | coverage (min, max) old / new | rows old / new | PK hash old / new. For `migrate`, all three old/new pairs must be equal.
PK hash: sort by primary key, concatenate rows, hash (aggregate hash syntax differs per database). Bucket large tables by PK range and drill into buckets whose hashes differ.

## 5. Rollback: drill before you switch

**Roll back by flipping a switch only, not by deploying or changing code.** The switch takes effect through an independent channel (config service, environment variable, feature flag), not tied to deploying the new version. Run the full test suite with the switch on the old path too.
*Why: if rollback needs a deploy, rollback itself can fail on the build, the approval or a bug in the new version.*

**Writes produced by the new path must sync back to the old side.** Either keep dual-writing or run a reverse-sync job. After the drill assert "rows missing on the old side after switching back = 0" and "unsent messages = 0".

**Time the drill and log it.** Flip the switch for real once, in staging or on a small production slice:

```yaml
rollback_drill: {date: <date>, env: staging, trigger: "<switch>=legacy", rollback_ok: true, elapsed_s: <seconds>, unsent_after_rollback: 0, missing_rows_after_rollback: 0}
```
`elapsed_s` runs from the flip until the error rate is back at baseline. It goes into the ramp gates' rollback condition as the bound on how fast a step-down must complete.

## 6. Ramp: one numeric gate per stage

**Each stage has a numeric gate (with units), a hold duration and a rollback condition. A script reads them and stops if any gate fails.** The control group is the old path over the same period, not last week's history. Preconditions: every write path from §2 is wired, the §5 drill passed, and the capacity gate (py2rust §7) passed.

**The data gate is dual-read mismatch counted per write path, not reconciliation residue.**
- Dual-read: the same request reads both sides and compares byte for byte by default (R2). Each mismatch carries the id of the write path that last wrote the row.
- The gate is judged once per write path; any path > 0 fails. A path with 0 comparisons during this stage's hold also fails (fixed denominator).
- Low-frequency paths (such as month-end close) with no natural traffic during the hold get a marked probe write to fill the denominator, and the 100% stage's observation window waits until they really run once.
- Reconciliation residue (`reconcile_mismatch`) is an auxiliary alert only, not a gate.

*Why: residue looks only at a total at one moment. Missed write paths, errors that cancel out and errors overwritten by later writes all disappear in it. Counting per write path tells you which path broke and which stage to step back to.*

**Judge `error_rate_delta` and `p99_latency_delta` once per seam unit, not only overall.** Any seam unit over its gate fails the stage.
*Why: one slow or failing endpoint at 1% of traffic disappears in the overall average.*

**The shadow stage must have no real outbound side effects.**
- Replace outbound adapters (HTTP clients, mail, payment, publish) with a recording sink. The gate includes `shadow_real_egress == 0`. Prove it can fail first: in a drill, point one adapter at a real (staging) endpoint and confirm the gate goes red.
- Isolate consumer groups and write targets from production: the shadow gets its own consumer group, schema or database, and bucket, so it neither steals messages nor writes production rows.
- Compare the recorded outbound requests byte for byte with the old version's real outbound, matched by business key. Outbound requests are a channel like any other.
- Account for the shadow's load and quota on shared downstreams (databases, caches, rate-limited third-party APIs it still reads). Measure the added load, keep it under the downstream's quota and headroom, and write the number into acceptance.md.

*Why: a shadow that really sends sends every email, charge and message twice. A shadow on the production consumer group takes messages away from the old path. And a shadow that silently doubles read load can take down a shared dependency for both.*

```yaml
# Ramp gates in acceptance.md (values are examples; set them per project). Any gate fails → stay at this stage and run rollback.
# dual_mm = dual_read_mismatch_per_write_path, dual_n = dual_read_compared_per_write_path; deltas are against the old path over the same period
# error_rate_delta and p99_latency_delta are judged per seam unit
# 100% stage hold = Default strictness table, observation-window row; if the contract is stricter, use the stricter value
rollout:
  precondition: {write_paths_covered: "<n>/<n>", rollback_drill_ok: true, capacity_gate_ok: true}   # every write path has a test that can go red
  stages:
    - {name: shadow, traffic_pct: 100, hold: 7d, gate: {shadow_diff_rate: "<= 0.0%", compared_requests: ">= 1e6 req", shadow_real_egress: "== 0 req", shadow_egress_mismatch: "== 0 req"}}   # compare only, no effect
    - {name: canary, traffic_pct: 1, hold: 48h, gate: {error_rate_delta: "<= 0.05 pp", p99_latency_delta: "<= 10 ms", dual_mm: "== 0 rows", dual_n: ">= 1 rows"}}
    - {name: ramp-50, traffic_pct: 50, hold: 7d, gate: {error_rate_delta: "<= 0.02 pp", dual_mm: "== 0 rows", dual_n: ">= 1 rows"}}   # covers a full week
    - {name: ramp-100, traffic_pct: 100, hold: <observation window>, gate: {dual_mm: "== 0 rows", dual_n: ">= 1 rows", oncall_pages_new_path: "== 0 pages"}}
  auxiliary: {reconcile_mismatch: "== 0 rows"}   # alert only, not a gate
  rollback_when: "any gate fails, or data is incomplete when elapsed > hold"
  rollback_max_s: <measured in §5>
```
**Thresholds are frozen and tighten-only (R2).** Commit threshold changes separately. The ramp script reads thresholds only from this file and accepts no command-line override. On failure, stay at the current stage, run `rollback_when`, then investigate.
*Why: the most common after-the-fact loosening at a ramp gate is "it was close, change the number".*

Machine check: the script parses `stages[].gate` and asserts each value has the form "comparator + number + unit" (unit from a pre-listed set: %, pp, ms, s, rows, req, pages). Any malformed value exits non-zero.
