# closeout · one-way doors, consumers, decommission, client releases, security

**Read this file in full** before any one-way door (drop a table or column, add NOT NULL, stop old writes, retire an API), before you notify consumers or delete old code or data, when the artifact ships to users' machines, when someone must change the old system during dual-run, or when the migration exists to remove a vulnerability. Rules: SKILL R1–R6; numbers: Default strictness table. Ledger: templates.md §4.

**Most often missed here**
- §2 Alerts and dashboards are consumers. Diff metric names and labels (old ⊆ new). In staging, inject a fault and assert the alert arrives within the agreed time.
- §2 Anyone who already consumed wrong output (canary data, reports) gets a correction, and you verify it.
- §3 Zero-call evidence at every layer over the full observation window, then delete. CI keeps the residue at 0.
- §3 Before dropping a database, run a fixed-seed retrieval drill against the archive, byte for byte.
- §6 Security-driven migrations fail closed and never fall back to the vulnerable path.

**Sections** · §1 Is it safe to pass a one-way door? · §2 Who must be told, and are alerts still wired? · §3 How do I delete old paths, tables and data? · §4 How do I ramp and roll back a client-installed artifact? · §5 What if the old code changes during dual-run? · §6 What changes when the migration is for security?

## 1. One-way doors: last

One-way doors include: dropping old tables or columns, adding NOT NULL or narrowing a type, stopping old-side writes, removing compatibility reads, announcing the old API's retirement, deleting old message-queue topics.

**Before each one-way door, check three things and write them into `decisions.md`:**
1. The compatible version shipped first, and every reader and writer runs a version that handles both formats (dated before the door).
2. The observation window meets the Default strictness observation-window row. For businesses with quarterly close or annual reports, use that cycle and name the longest-cycle job.
3. The migration scripts contain no destructive DDL and no constraint tightening that old code still depends on. In Django, `python manage.py sqlmigrate <app> <migration>` prints the SQL, then `rg -n 'DROP|NOT NULL|ALTER .* TYPE'`. Other frameworks: use the equivalent "generate SQL, don't execute" command.

*Why: low-frequency consumers such as month-end, reconciliation and annual jobs appear only at cycle boundaries. A short window never sees them.*

Machine check: a script reads the dates in transitions.md and asserts `compat_deployed < observation_start`, `observation_end - observation_start` ≥ the window minimum, the window contains the 1st of some month, and `one_way_door_date > observation_end`.

## 2. Consumer notification

**List consumers by category, one decision per row.** How to find and count them: SKILL R5.
Categories at least: direct callers (code, plugins, SDK users); downstream artifacts (reports, warehouse tables, export files, anyone who already consumed canary output); people who depend on log format, alert rules or performance characteristics (SRE, monitoring, SLA holders); affected end users.

```markdown
| Consumer | Category | How found | Depends on | Decision | Notified | Confirmed by |
|---|---|---|---|---|---|---|
| <month-end job> | downstream artifact | crontab + access logs | all columns of <table> | move to new table, dual-run and compare before the cycle | <date> | <team> |
| <alert rule> | alert | full-text search of alert config | old service metric names | rename in step, keep old names until decommission | <date> | <on-call> |
```
*Why: an unnotified consumer shows up only as an outage on the day the old path is deleted. Anyone who consumed canary output must also be told on rollback.*

**Wrong output that was already consumed gets corrected and re-checked.** If a stage produced wrong or duplicated records that downstream already read (reports, invoices, warehouse rows, exports), list the affected records by query, correct them per R6, then reconcile on the consumer side: affected records after correction = 0, with the query and count in the ledger.

Machine check: the table has > 0 rows and no empty decision cell. If a decision changes what some consumer sees and the task didn't authorize it, escalate to the owner per R6(b).

**Alerts and dashboards are consumers.** Diff the metric names and label sets exposed on old and new `/metrics`; require old ⊆ new.
```bash
# metric name + label keys per series (Prometheus text format)
series() { curl -s "$1/metrics" | grep -v '^#' | sed -E 's/="([^"\\]|\\.)*"//g; s/ .*$//' | sort -u; }
test -z "$(comm -23 <(series http://old:8000) <(series http://new:8000))"   # present in old, missing in new: must be empty
```
In staging, inject a fault (kill a dependency, force 5xx) and assert the alert arrives within the agreed time. When the replaced component's own output is the health signal (it reports its own health or metrics), add an independent external monitor (a black-box probe from outside).
*Why: renamed metrics or dropped labels don't break any test. The alert just stays silent, and a broken new component may report itself healthy.*

## 3. Decommission and deletion: fail loudly first, then delete, then zero

**Make old-path use fail loudly first.** Before deleting old interfaces, tables or switches, turn them into hard failures or deprecation warnings that identify the caller (source IP, service name, top stack frame).
Instrument every layer: API gateway, application logs, database audit or query stats, message-queue consumer groups, object-storage access logs.
*Why: reading code finds only the callers you know about. Loudness flushes out the ones you don't.*

**Zero-call evidence at every layer, for the Default strictness observation-window duration.** Paste the evidence into the matching transitions.md row: query, time range, result 0. A missing layer means no evidence.

**Before dropping a table: measure coverage, set a disposition, reconcile per table, keep a snapshot.** Use the cutover §4 output: `tables_mismatch = 0`, `missing_rows = 0`. Record the snapshot path and retention period in the ledger, and actually drill restoring the snapshot once.

**Before deleting the old implementation, seal a runnable referee** (image digest recorded); see review §7.

**After deletion, residue reaches zero, enforced in CI as a no-backflow guard.** Judge direct and transitive dependencies separately:
```bash
# Direct: references to the old path = 0 (names are placeholders: use this project's old module, table and switch names)
test "$(rg -c '<old module>|<old table>|<old switch>' src/ config/ | wc -l)" -eq 0
# Rust dependency tree: the old crate no longer appears
! cargo tree -i <old crate> --edges normal 2>/dev/null | grep -q .
# Old artifact files
test "$(find . -path ./target -prune -o -name '*_legacy*' -print | wc -l)" -eq 0
```
When transitive dependencies (old components pulled in by third-party libraries) can't be fully removed, list them in a separate table with the check "no longer loaded by the process": absent from runtime-loaded modules (Python `sys.modules`, Linux `/proc/<pid>/maps`, macOS `vmmap`).
Guard exemptions go only into a ratchet allowlist file (Default strictness table, source-guard row).
*Why: without a CI guard, someone following old docs will add the old call back within months.*

**Archive by retention period and privacy class.** Deleted does not mean destroyable. First check legal or contractual retention and privacy class (personal data, payment data), then decide where to archive, how to encrypt and when to destroy. Data under a deletion obligation (for example personal data of closed accounts) is deleted, not archived. Cache/session data is discarded per cutover §4.1, with the reason in the ledger.

**Before dropping the database, run a retrieval drill: fixed-seed sample, retrieve from the archive, compare byte for byte with the old DB.**
1. Sample from the old DB with the seed and count written in acceptance.md (by business key; with many tables, sample each; stratify large tables by PK range).
2. While the old DB still exists, run the business query for each sample and write it to a file with fixed column order and serialization.
3. Using only the archive (not the old DB), retrieve by the same business key and write with the same serialization.
4. `cmp` or compare `sha256` per item: mismatches = 0; items compared = items sampled.
5. Record retrieval time per item (median, p99, slowest) and compare with the legal or contractual retrieval deadline.

```yaml
# seed matches acceptance.md; compared must == sampled; sla_ms comes from the legal or contractual retrieval deadline
archive_retrieval_drill: {date: <date>, seed: <seed>, sampled: <n>, compared: <n>, byte_mismatch: 0, elapsed_ms: {p50: <ms>, p99: <ms>, max: <ms>}, sla_ms: <ms>}
```
*Why: archives often change format, encoding or compression. Field-by-field "looks the same" misses changes in precision, time zone, encoding and null representation. Once the old DB is gone there is nothing to compare against, so do it before the drop, byte for byte.*

## 4. Client-distributed artifacts

Desktop apps, mobile apps and CLI packages run on users' machines: no server-side switch, and a shipped version stays out there.
**Ramp by release channel: prerelease → opt-in → stable.** The denominator is install count or opt-in telemetry, not downloads. Each channel gets a numeric gate in acceptance.md like the cutover §6 stages.

**If possible, ship old and new implementations in the same release behind a runtime switch** (config or remote flag), so rollback is a flip as in cutover §5.
Otherwise rollback means shipping a higher version number that contains the old implementation. Measure each channel's publish latency (build, signing, store review, mirror propagation) and record it as `rollback_max_s`.

**Local state migrations must stay readable by the rollback version.** Config files, caches and local databases written by vN must still load in the version you would roll back to. Use the §1 compatibility rule: ship a reader for the new format before writing it.

**Drill vN-1 → vN → vN+1 on a local tap, repo or package index.** Install, upgrade, then upgrade again to the rollback build; assert state is intact and the app starts at each step.
```yaml
client_rollback_drill: {date: <date>, channel: <prerelease|opt-in|stable>, path: "vN-1 -> vN -> vN+1(old impl)", state_readable: true, starts_ok: true, rollback_max_s: <measured publish latency>}
```
*Why: once a client build is installed, you can't recall it. The only rollback is the next release, and if that release can't read the state the bad one wrote, users lose data.*

## 5. Changes to the old system during dual-run

1. Someone needs to fix or extend the old implementation while the new one is in dual-run. Check transitions.md first: which dual-writes, shadows and stages are active for the affected code.
2. Pick one:
   - (a) Fix old and new together. Write a test that goes red on the bug and run it against both implementations.
   - (b) Ramp the new path down to 0, fix the old one, then port the fix and ramp back up through the stages.
3. Re-pin the referee: record the new sha256 of the old build and register the change (what changed, which goldens re-recorded per checks §7) in transitions.md and `decisions.md`.

*Why: the old implementation is the referee (R1). Changing it silently moves the target, so the differential report starts flagging the fix as a regression, or the new code is accepted against a referee nobody pinned.*

## 6. Security-driven migrations: fail closed

When the migration exists to remove a defect in the old implementation (a vulnerability, memory unsafety), reverse the fallback direction:
- **Errors fail closed: reject the input.** Don't fall back to the old path on error, because that sends attacker-controlled input straight back to the vulnerable code.
- **The rollback switch is usable only after the old path is patched or the dangerous inputs are blocked in front of it** (input filter, WAF rule, size or format limit).
- Write both into the rollback drill and the ramp gates:
```yaml
security_migration:
  on_error: reject                    # never "fallback: legacy"
  rollback_precondition: "old path patched (commit <sha>) OR blocking rule <id> deployed"   # drill asserts the switch is refused otherwise
  drill: {exploit_input_after_rollback: rejected, fallback_to_legacy_count: "== 0 req"}
```
*Why: a fallback that fires on exactly the malformed inputs an attacker sends turns the safety net into the exploit path.*
