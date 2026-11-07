# templates · decisions.md, contract.md, acceptance.md, transitions.md

**Copy the matching template** the moment you create one of these files, and keep every field; write "n/a + reason" rather than deleting one. Field meanings are explained in the file each template cites (decide.md, checks.md, review.md, cutover.md, closeout.md).

**Sections** · §1 decisions.md: why, what, how much, verdict · §2 contract.md: consumers, implicit behaviors, equivalence rules, attribution table · §3 acceptance.md: referee fingerprint, denominators, thresholds, conclusion · §4 transitions.md: every transitional artifact with owner, deadline and deletion condition

## 1. decisions.md template

Field meanings are in the decide.md section cited on each heading; this is just the structure.

```markdown
# decision · <migration target>

#### Precondition probes (decide §1)
probes: [{probe, command, exit_code, time, kind: ok | missing-permission | referee-rebuilt}]

#### Root cause, goal and hotspots (decide §2)
root_cause:   goal:
tuning_tried: {tried: [], fixable_in_old_stack: [], not_fixable_in_old_stack: []}   # third empty → no-go
raw_profile:   hotspots: [{name, incl_pct, grep_cmd}]   recompute_cmd:
amdahl: {p, s, formula, upper_bound, target, pass}

#### Performance measurements (decide §3)
e2e_table:   boundary_crossings_per_request: <n> × <cost per crossing>
gate_feasibility: [{gate, lower_bound, how_measured, reachable}]

#### Payback and maintainer capacity (decide §4)
consumers: <count and source>   roi:   contract_cost:
sunset_date:   maintainers_12m:   rust_capable:   change_freq_12m:   write_freeze_window:
handover_doc:   backup_maintainer:   pairing_commits: []   # required when rust_capable < 2

#### Slices and mode (decide §5, §6)
<slice table>   first_cut:
pattern:   preconditions: [☑/☐ each]   rejected_patterns: [{pattern, reason}]
failure_isolation: [{pattern, panic_survived, bad_input_survived, recovered_without_restart}]
blast_radius: <dirs you may change; dirs you may not>

#### Dependencies, delivery surface and schedule (decide §7, §8)
<dependency table>   gaps:   unevaluated: ∅   delivery_matrix:
<phase table>   options_side_by_side:

#### Process tier (decide §10)
tier: light | full   basis: {consumers, cost_of_being_wrong, money, persisted_data, security, one_way_door}

#### R6 classification and verdict
self_decided (a): [{item, evidence, alternatives, reason}]
to_owner (b): [<IDs from pending-decisions.md>]   # pending items live only there
proposals (out of scope): [{item, benefit, cost, status: awaiting-ruling | approved | rejected, ruling_date}]
verdict: go | go-partial | no-go   freeze: <for no-go or partial; see decide §9>   archive_branch: <if parked midway>
```

## 2. contract.md template
**Consumer table** (R5): each row `caller | location (file:line or service name) | how it's used (fields read, behaviors relied on) | comparison granularity this implies`.
Below the table, the search command (e.g. `rg -n '<public name>' <whole repo and plugin dirs>`) and the count; the count matches the command output.

**Implicit behaviors**: odd branches and implicit guarantees found by reading source, `git blame` and introspection; each row `behavior | source location | origin (blame or issue) | case ID that pins it`. Don't fix them in passing; fixes go through review §2.

**Equivalence rules**: the checks §3 YAML blocks, one per rule (only for channels where the old code is nondeterministic). Owner-approved loosenings are listed separately with decision ID and bound.

**Attribution table**: append-only; claim only when unattributed differences = 0.

| ID | Difference (input → old / new, with command) | Category | Decision | Rationale | Owner | Allowed channel | Flag or CHANGELOG | Status |
|---|---|---|---|---|---|---|---|---|
| D-<n> | `<command>` → old <rc, output> / new <rc, output> | <category> | <fix / accept / pending> | <basis, incl. consumer search command and count> | <self (R6a) or owner (R6b, decision ID)> | `<channel>:` | <…> | <…> |

Category values: `translation defect` (fix); `harness` (old-vs-old also red; change the comparator and register an equivalence rule only if the old code is itself nondeterministic, otherwise fix the harness); `intended difference` (decide yourself per R6(a) if the task requires it, otherwise R6(b)); `old bug fix` (review §2); `platform limit` (checks §5);
`needs decision` (R6(b) items only: changes behavior existing consumers can see and the task didn't ask for it; add to `pending-decisions.md` with a recommendation and a default). Machine check: `grep -c` of rationale and owner fields == entry count.

## 3. acceptance.md template
```markdown
# acceptance · <module>
Freeze commit: <sha> (before first implementation commit <sha>)
#### Referee fingerprint
Interpreter: <full version>  Path: <realpath>  Key libraries: <name=version…>
Data tables: unicode=<…> tzdb=<…>  Lockfile sha256: <…>  Old-code copy sha256: <…>
Compiler/service (if any): <version, flags, target width / server config, session variables>
#### Denominators
Total cases N=<…> (content-derived IDs); real corpus files=<…>; skip baseline=<…>; allowlist entries=<…> (ratchets down)
#### Minimums and thresholds (stricter of the Default strictness table and the contract)
Differential/property cases: <…>    Mutation: <category list>, cases per high-risk point per R2, non-equivalent survivors = 0
Flakes: p=<…>, repeated runs n=<…>, thread counts {…}, seed set <…>
Fuzz: <target list>, until coverage stops growing; service keeps serving after a panic
Perf, per load class: <load class>: median new/old ≤ <…>, worst pairing ≤ <…>, peak RSS ≤ <k>×input; mixed load: <…>
Replay: flips = 0 (or each one attributed)
#### Changes to old tests (R2 exceptions)
<test location | bug it asserts | R6(a) decision | archived red-output path>
#### Golden re-records
<fingerprint mismatch | affected-input predicate | changed files ⊆ predicate (command, result) | commit>
#### Platform limits
<input class | reason | environments tried (local, container, other runners) | error-path case ID tested instead>
#### Fixture target-input counts
<target input (code point, boundary value…) | occurrences (must be >0) | count command>
#### Conclusion
Generated by `<command that produces verdict.json>`, not filled by hand. One line per check:
<check · score · threshold · pass/fail · evidence file>
```

## 4. transitions.md ledger template

One row per transitional artifact: dual-write, shadow comparison, compatibility read, compatibility switch, fallback path, reverse-sync job, reconciliation script, old-table snapshot, deprecation warning, exemption list. The owner, deadline and deletion-condition columns correspond to SKILL R5; CI checks they are non-empty.

```markdown
# transitions.md

| id | Artifact | Type | Owner | Added | Deadline | Deletion condition (machine-checkable) | Made loud how / when | Zero-call evidence | Status |
|---|---|---|---|---|---|---|---|---|---|
| T01 | <table> dual-write | dual-write | <team> | <date> | <date> | 100% stage passed observation window; per-write-path dual-read mismatch = 0 for every path | none (internal) | dual-read count log <range> | active |
| T02 | <switch>=legacy | compatibility switch | <team> | <date> | <date> | requests taking legacy = 0 during observation window | WARN when legacy taken, <date> | gateway query link + result 0 | loud |
| T03 | <old table> | old table | <DBA> | — | <date> | T01, T02 deleted; coverage measured; tables_mismatch=0; snapshot restore drilled | write permission revoked, <date> | audit log: 0 hits in window | pending-delete |
| T04 | <fallback path> | fallback path | <owner> | <date> | none (frozen) | reconsider when: fallbacks > <ratio> of calls | counter metric | — | frozen |

#### Observation window and one-way door dates
- compat_deployed: <date>; observation_start: <date>; observation_end: <date>; one_way_door_date: <date>

#### Residue-zero CI
- job: legacy-residue-zero (direct reference count = 0; old crate absent from dependency tree)
- transitive-dependency table: transitions-transitive.md, check "no longer loaded by the process"
```
An artifact you decide not to delete is marked `frozen` with a numeric trigger for reconsidering it, not left with an empty deadline (R5). Status values: `active`, `loud`, `pending-delete`, `deleted`, `frozen`.

**Expired artifacts fail CI.** Rows with deadline < today and status ∉ {deleted, frozen} must be 0:
```bash
# columns: $7 = Deadline, $11 = Status (leading | makes $1 empty); adjust if the table changes
awk -F'|' -v t="$(date +%F)" '$2 ~ /T[0-9]+/ { d=$7; s=$11; gsub(/ /,"",d); gsub(/ /,"",s)
  if (d ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ && d < t && s != "deleted" && s != "frozen") { print; n++ } }
  END { exit n > 0 }' transitions.md
```
Moving a deadline later is a loosening: the commit must cite an owner-decision ID from `decisions.md`. Check it with `git log -p -- transitions.md`: for every `-`/`+` pair of the same row id where the deadline increased, the commit message must contain an ID that exists in `decisions.md`.
While any item is expired, don't start a new slice.
*Why: deadlines nobody enforces quietly become permanent, and every new slice adds more transitional artifacts on top.*
