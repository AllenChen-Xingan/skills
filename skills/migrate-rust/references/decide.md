# decide · whether to migrate, how much, in what order, how long

**Read this file in full** before you write a migration plan or decisions.md, or when the question is whether a port is worth it, which of two designs or modes to choose, whether to continue, pause or park a port already under way, how to read a profile, or how much process the job needs. Rules: SKILL R1–R6; numbers: Default strictness table. Fill the decisions.md template in templates.md §1; fields are cited here as `field_name`.

**Most often missed here**
- §2 Hotspot share comes from the raw profile, with a recompute command. The Amdahl bound goes in the decision record. If the goal doesn't match the root cause, stop.
- §2 Profile both old and new before explaining where time goes.
- §4 If fewer than 2 people can maintain the Rust part, record a handover doc, a named backup and pairing commits; if any is missing, shrink scope or give no-go.
- §6 Every criterion you compare designs on must be measurable. Fill failure isolation by experiment: inject a panic and bad input into each candidate.
- §9 Parking: archive branch + STATUS file, a CI check that release branches contain no new-code references, and at least one numeric restart trigger.
- §10 If you're unsure of the tier, pick full.

**Sections** · §1 Can I even run the old system here? · §2 What is wrong, what is the goal, and what does the profile prove? · §3 How do I compare performance options? · §4 Does it pay back, and who will maintain it? · §5 How do I slice and order the work? · §6 Which migration mode, and does it isolate failures? · §7 Is every dependency covered? · §8 How long will it take (as a range)? · §9 How do I stop or park it properly? · §10 Light or full process?

## 1. Preconditions: one-line probes

- Before you start, probe each of these with the smallest possible command: "can run the old system", "can install dependencies", "has network", "has build quota". For example `<old interpreter> -c 'import <old_pkg>; print(<old_pkg>.__version__)'` and `cargo search <crate> --limit 1`. Record commands and exit codes in `probes`.
  Why: running the old implementation is what the whole safety net rests on (SKILL R1). Hitting a permission wall mid-run adds waiting time and a session restart on top of lost work.
- Sort each probe failure into one of two kinds:
  - **Missing permission.** List every missing permission at once and escalate to the owner. Don't rephrase the command to get around it. If the same request is refused 2–3 times, stop and report.
    Why: a rephrased command won't get through, and it makes it unclear what was actually approved. Some grants only take effect after a session restart.
  - **The referee's runtime can't be built here, or is EOL.** Don't stop. Revive the referee in a container built from the production machine's package list (for example `dpkg -l`, `rpm -qa`, `pip freeze` captured on that machine). Pin the base image by digest (`FROM <image>@sha256:<digest>`), and check the key binaries (interpreter, native libraries) against their sha256 from production. Then pass the referee fidelity gate in checks §1 before you treat its output as expected values.
    Why: an EOL runtime is the normal case for old systems, not a blocker. A rebuilt referee that differs from production in one library version silently changes the expected values, so it has to prove it reproduces production first.
- While waiting for a grant, do only work that doesn't need to execute the old system: read the source, scaffold the test harness, list consumers.
- Take toolchain and dependency versions from a live package-manager query, not from documentation.
  Why: the docs on an upstream repo's main branch may already describe an unreleased version; copying that into Cargo.toml fails to resolve.

## 2. Root cause, goal and hotspot evidence

- First write one line of `root_cause` (where it's slow, where it's wrong, where it can't be maintained), then one line of `goal` (number, unit, load, and the machine it's measured on). Support both with data on the same dimension: if the root cause is p99 latency, the evidence is p99, not throughput or line counts.
  Why: when the goal doesn't match the root cause, the metric won't move after the migration.
- Split `tuning_tried` into three columns: tuning already tried, what can still be fixed in the old stack, and what truly can't be fixed in the old stack. A migration is justified only if the third column is non-empty. When the evidence is enough to conclude, give the verdict directly; don't turn it into a pending item (SKILL R6(a)).
  Why: many "we need a rewrite" root causes go away with a different algorithm, a cache, or a dependency upgrade.
- Attach the raw profiler output for hotspot evidence (the raw py-spy / perf / cProfile files), not just a screenshot or summary. Each hotspot function name must be `grep`-able in the raw file, and each share needs a recompute command.
- The share p is measured as in SKILL R3 (inclusive sampling: a sample counts once if the hotspot is anywhere on its stack). For recursion, or when adding up several hotspots (parent/child, siblings), still deduplicate by sample; don't add per-function shares.
  Why: Rust replaces the whole subtree, so self time (self/tottime) understates p. Adding cumulative times (cumtime) counts parents and children twice; the sum can exceed 100% and inflate the Amdahl bound.
- Recompute command examples:
  - Folded stack text (`py-spy record --format raw -o raw.txt ...`, or `perf script | stackcollapse-perf.pl > raw.txt`; each line is `frame;frame;frame count`):
    ```sh
    awk -v re='(^|;)(hot_a|hot_b)([ (;]|$)' '
      { n=$NF; tot+=n; s=$0; sub(/ [0-9]+$/, "", s)
        if (s ~ re) hit+=n }          # each line (one distinct stack) is tested once
      END { printf "p=%.4f hit=%d total=%d\n", hit/tot, hit, tot }' raw.txt
    ```
    Anchor the match on frame boundaries (frames look like `hot_a (mod.py:12)`) so `hot_ab` isn't counted; adjust the regex if your frame format differs.
  - speedscope JSON (`py-spy record --format speedscope -o prof.json ...`):
    ```sh
    jq --arg f 'hot_a' '.shared.frames as $F
      | [ .profiles[] | . as $p | range(0; $p.samples|length) as $i
          | { w: $p.weights[$i], hit: ($p.samples[$i] | any($F[.].name == $f)) } ]
      | { p: ((map(select(.hit).w) | add // 0) / (map(.w) | add)) }' prof.json
    ```
  Put the command, raw file path and output together in `recompute_cmd`. Two reruns of the same command must give the same result.
- Use self time (self/tottime) only to pick which function inside the subtree to change first, never to compute p.
- Profile both the old and the new implementation on the same input before explaining where the new one spends its time or why it is (not) faster. A profile of one side alone can't attribute a difference.
- Before any profiler-estimated "N× slower" goes into decisions.md, re-measure it with timeit or hyperfine (SKILL R3), especially when the two sides make very different numbers of Python calls.
  Why: cProfile adds hook overhead only to Python calls, so the side with more calls is inflated; the estimate can be several times larger than a timed measurement.
- Amdahl: p covers only the CPU segment that actually gets faster in Rust. Subtract I/O, lock waits, network waits and boundary conversions.
  - Formula `S = 1 / ((1 − p) + p / s)`. If s is unknown, take s→∞ for the upper bound `1 / (1 − p)`.
  - Reject if the bound is below the goal. With no stated goal, reject by default when the bound is < 1.2×. Record p, s, formula and result in `amdahl`; a recompute passes only within 5%.
  - Example: p = 0.6, s = 10 gives S ≈ 2.17×; the bound at s→∞ is 2.5×. A 3× goal is out of reach.
- When profiling shows no hotspots left outside the target scope, stop at the slices already done. Record the rest as "identified, intentionally not done" with triggers for reconsidering (see §9).
  Why: migrating code that no measured load implicates only adds code to maintain.
- When the root cause is a bug, deadlock or intermittent failure, "switch to Rust" is not a fix. Fix the root cause.
  - Reproduce it first with a loop or concurrent stress test: ≥1 reproduction before the fix, 0 in the same number of runs after. Take the run count from the "intermittent, concurrent" row of the Default strictness table.
  - For masking fixes (timeouts, retries, restarts), first write a test that proves the mask doesn't hide the failure (the test must be red under that fix).

## 3. Measure performance options before comparing them

- Compare options with an end-to-end measurement table: `hyperfine --warmup 3 --runs 20 '<old>' '<new>'`; for services, measure p50/p99. State machine, load and build profile on every row. Record it in `e2e_table`.
  Why: function-level timings miss startup, serialization and boundary costs.
- For PyO3, count boundary crossings first: time one empty-function round trip, multiply by crossings per request, and compare with the time you aim to save. Designs that call back into Python per element usually die at this step; switch to a batch interface.
- Check that the lock-file and deploy-config diff between compared setups contains only the target change: `git diff --stat -- <lockfiles> <deploy config>` (e.g. Cargo.lock, uv.lock). Paste the output into the table.
  Why: SKILL R4 "change one variable at a time" needs checkable evidence; otherwise you can't tell where the gain came from.
- Before any gate (latency, throughput, memory, build time, CI time) goes into acceptance.md, check that it is physically reachable (SKILL R3). Record lower bounds and how they were measured in `gate_feasibility`. Common lower bounds, each measured or computed:
  - Process startup and dynamic-linking cost: `hyperfine` an empty program with the same link inputs and build profile. Linking one system framework can cost milliseconds.
  - Boundary floor: empty round-trip time × crossings per request.
  - Bandwidth and cores: data size ÷ measured memory or disk bandwidth, and available cores × single-core throughput, give the theoretical minimum time.
  - Amdahl bound: `1 / (1 − p)` from §2.
  If any lower bound already exceeds the gate, change the goal or the scope before you measure.
  Why: an unreachable gate only gets loosened after measuring, and checks are tighten-only (SKILL R2).
- Write the goal before measuring: its commit to acceptance.md must predate the first raw timing data.
- When CI or builds are slow, time each step before changing anything. When build profile settings (lto, codegen-units, opt-level) involve a trade-off, build once with each and measure both build time and run time.
  Why: settings tuned by feel usually save time on steps that don't matter.

## 4. Payback and maintainer capacity

- Estimate payback roughly in `roi`: `consumers × remaining life (months) × monthly benefit` versus `migration time + monthly maintenance cost × remaining life + delivery surface cost`. Take the consumer count from the real count found under SKILL R5, not "probably someone uses it".
  Why: a module about to be retired never pays back its migration.
- Look up four numbers:
  - `sunset_date`: roadmap, deprecation notices, related issues.
  - `maintainers_12m`: `git shortlog -sn --since="12 months ago" -- <path>`; count people who can read Rust separately.
  - `change_freq_12m`: `git log --since="12 months ago" --format=%h -- <path> | wc -l`.
  - `write_freeze_window`: ask the owner or check the SLA.
- If fewer than 2 people can maintain the Rust part, flag it red and fill in all three items below. If any is missing, shrink the Rust scope or give no-go for insufficient maintainer capacity:
  - `handover_doc`: in-repo path of the handover doc (build, release, troubleshooting, how to run differential testing). Create it at the start; update it each slice.
  - `backup_maintainer`: a named backup maintainer, with their commits in the last 12 months or a planned takeover date.
  - `pairing_commits`: at least one change per slice led by the backup and reviewed by the original maintainer; record commit hashes.
- At close-out, rerun the same `git shortlog` command. If the count is still < 2, write it as a reconsider trigger under §9.
- Parts that must be hand-written for byte equivalence (for example an argument parser written to match the old framework's error and help text byte for byte) are contract cost. Estimate lines and hours in `contract_cost`.

## 5. Scope, slices and order

- Split the candidate scope into a slice table and fill every field for every slice:

  | Slice | Read-only | Idempotent | Reversible | Shared state | Boundary (function/module/process/RPC) | Consumers | Depends on | Root-cause benefit | Risk |
  |---|---|---|---|---|---|---|---|---|---|

- Make the first cut the slice with a clear boundary that is read-only or idempotent and shares no state with other slices. If two slices' "Shared state" columns overlap, merge them, or split the shared state out first.
  Why: the first cut exists to run the whole differential-testing and rollback flow end to end. A stateful slice tangles the causes of failures together.
- Code that always changes together goes in one slice. Look at co-change: `git log --format='' --name-only -- <dir> | sort | uniq -c | sort -rn`, then spot-check that the high-frequency files really appear in the same commits. Within hard dependency constraints, order by root-cause benefit and risk.
  Why: if code that usually changes together is split across old and new, every future change has to be made on both sides.
- Close out each slice on its own before opening the next:
  - differential testing mismatch = 0;
  - every commit in the slice builds and tests green on its own (`cargo test` plus differential testing);
  - this slice's transitional artifacts are deleted or frozen (SKILL R5).
  Don't open a new slice while any transitional artifact anywhere is past its deadline (CI rule: templates §4).
  Why: once slices pile up you can't tell which one introduced a difference, and transitional artifacts that outlive their slice become permanent.
- Prefix commit messages with the SKILL R4 step category (e.g. `translate:` / `idiom:` / `deps:`). Count by category with `git log --oneline --grep='^translate:' | wc -l`, and check that no commit spans two kinds of change. Schedule the referee's (old implementation's) own dependency upgrades outside the migration window.
  Why: when the referee changes, the expected values change with it, and differential testing reports the referee's change as a bug in the new code.
- Exception — forward-compat step, for an upgrade whose old API is removed in the new version (SKILL R4). A single `deps:` commit can't work here, because the code must change at the same moment. Do it in this order instead:
  1. On the old version, turn on deprecation / forward-compat mode with warnings as errors (e.g. `-W error::DeprecationWarning`, `RUSTFLAGS="-D deprecated"`, or the library's own compat flag).
  2. Change the code so it runs on both versions. Every commit stays green; deprecation-warning count = 0.
  3. The last commit changes only the dependency: its source diff is empty (`git diff HEAD~1 -- <source dirs>` prints nothing; only lock and manifest files change).
  Why: this keeps "one variable at a time". Any difference after the last commit can only come from the dependency, not from your code edits.

## 6. Choosing a mode (tick every precondition)

Pick a mode, then check its preconditions one by one. If any box can't be ticked, switch modes or make filling the gap slice 0. Record the ticks in `preconditions`.

| Mode | Fits | Preconditions (all ticked to choose) | Signals it doesn't fit | Blast-radius limit | Failure isolation |
|---|---|---|---|---|---|
| Strangler (external seam) | Services or CLIs replaced entry point by entry point | ☐ RPC, HTTP or process boundary; ☐ configurable interception point (gateway, router, entry script); ☐ entry contract listed in contract.md; ☐ requests idempotent or safely replayable to a shadow instance | Fine-grained in-process calls; requests with non-replayable side effects | Change only callers and routing you control; don't touch producers or the primary database (`git diff -- <producer dir>` is empty) | Inject panic + bad input; record in `failure_isolation` |
| Branch by abstraction (in-process seam) | Replacing one module inside a library or monolith | ☐ a forward-only interface can sit in front of the call sites; ☐ old and new can switch by flag in the same process; ☐ the interface layer has its own tests | Call sites scattered across dozens of places with no way to gather them by source scan | Interface layer only translates and isolates failures; no new features | Inject panic + bad input; record in `failure_isolation` |
| Dual-write or shadow write | Changing database or storage format | ☐ every write path enumerated (`rg` for write calls, count recorded); ☐ idempotency keys; ☐ reconciliation script; ☐ rollback is a flag flip | Write paths spread across downstreams you don't control; no idempotency key | Details in `cutover.md` | Inject panic + bad input; record in `failure_isolation` |
| PyO3 hotspot | Python shell unchanged, hot functions moved to Rust | ☐ Amdahl bound from §2 meets the goal; ☐ boundary-cost budget from §3 works out; ☐ public names and exception class identity preserved; ☐ fallback path to pure Python with a switch | Hotspot calls back into Python per element; small hotspot share | Existing tests are append-only per SKILL R2; differences to diff-test listed below | Inject panic + bad input; record in `failure_isolation` |
| Whole rewrite (process level) | Small CLIs, single executables | ☐ all observable behavior is at the process boundary (stdout, stderr, exit code, files, environment); ☐ black-box differential testing possible; ☐ old runtime and framework behavior counted in the schedule | Imported as a library; has a plugin ecosystem | The old runtime (interpreter startup, forced locale, framework output rewriting) is part of what you rewrite; port it in the old call order (SKILL R4) | Inject panic + bad input; record in `failure_isolation` |

- Fill the failure-isolation column by experiment, not by argument. For each candidate, inject a panic in the new code and feed it bad input (malformed, oversized, wrong encoding). Record whether the host process survives, whether the request fails the same way the old one did, and whether the system recovers without a restart. A PyO3 panic that takes down the interpreter, or a whole rewrite that crashes where the old code returned an error, counts against the mode.
  Why: modes differ most in what one bad input does to everything else in the process, and that only shows up when you inject it.
- Possible differences to diff-test in PyO3 hotspot mode (old behavior wins):
  - The module's public name set (names in `dir()` not starting with `_`): new imports and helpers in the shell change it.
  - Exception class identity: the shell keeps the old class and the native layer only references it.
  - The rest is in `py2rust.md`.
- Also record the modes you didn't pick and why, in `rejected_patterns`.
- Strangler and dual-write are expensive to get wrong: once a producer or the primary database has changed, rollback is no longer a flag flip. Keep the blast radius small, e.g. replace only the CLI entry point you control and leave the library API others import in the old language.

## 7. Dependencies and APIs, item by item

- First list every external capability the old code uses, e.g. `rg -o --no-filename '^(from|import) [A-Za-z_][A-Za-z0-9_]*' <src dir> | sort -u`, plus C extensions, subprocesses, syscalls and environment variables. The `rg` set minus the evaluated set goes in `unevaluated` and must be empty.
  Why: a dependency you didn't evaluate usually turns out to have no matching crate halfway through translation.
- Fill these fields for every dependency:

  | Capability | Old dependency and version | Candidate crate | Official / maintained by | Latest release date | Spec version followed | License | Reuse (full/partial/none) | Gap hours | Approval record |
  |---|---|---|---|---|---|---|---|---|---|

  - Fill "Latest release" and "License" from `cargo info <crate>` or crates.io; don't leave them blank.
  - "Approval record" is the ticket or PR number from the project's approval gate (dependency allowlist, deps review, license check). Unapproved items are marked "pending approval" and don't count as evaluated (the approval gate still applies; see SKILL R6).
  Why: unmaintained crates, mismatched spec versions (e.g. the msgpack timestamp extension, Unicode version) and licenses outside the allowlist all turn into rework later.
- List gaps in a separate table (`gaps`): capabilities with no usable crate, or only partial coverage. Estimate their hours into §8.
- Check every API you use (for example PyO3's `Bound::cast` or `import_exception!`) against the docs or source of the locked version instead of writing it from memory. Write the version you checked against into the dependency table, and run `cargo check` once after writing.
- The delivery surface is a dependency too (SKILL R5). Record it in `delivery_matrix`: wheel matrix (platform × interpreter, including 3.13t), abi3 or not, distro packaging, offline reproducible builds, release/dev profiles, feature combinations, backports to each release line. Estimate hours for every cell; details in `delivery.md`.
  Why: the delivery surface is the easiest thing to leave out of an estimate, and it ends up blocking the release.

## 8. Schedule ranges

- Give the schedule per phase as a range (lower to upper bound), never a single point. Use at least four phases:

  | Phase | Content | Lower | Upper | Throughput basis (measured in this repo) |
  |---|---|---|---|---|
  | Translation | Literal translation plus alignment | | | First cut: lines/hour or functions/day |
  | Testing | Checks, differential testing, mutation, fuzzing, adversarial self-review, fixing differences | | | Test-and-fix time in the first cut |
  | Packaging | Every cell of the §7 delivery surface | | | Setup time per CI job |
  | Beta | Canary and observation window (Default strictness table, "observation window" row) | | | Business cycle |

- Derive throughput from this repo's first cut, not from rules of thumb. After the first cut, re-estimate the whole table from its actual time.
- The testing lower bound must be ≥ the translation lower bound.
  Why: adversarial self-review after everything is green (last item of SKILL R2) usually still finds differences; fixing them and adding cases often takes longer than the literal translation.
- When there are several options (different modes or scopes), put them side by side in one table (`options_side_by_side`), with the formula in every cell. Two recomputations must differ by ≤1 week.
- Book contract cost (§4) and dependency gaps (§7) into translation and testing respectively. Don't open a "misc" line.
  Why: hours in "misc" are the first to be cut in review.

## 9. Deciding not to migrate: parking

Deciding not to migrate (all of it or one slice) is a conclusion too, and it gets written down like a migration. decisions.md says `verdict: no-go`, and transitions.md gets a freeze row (owner, deadline, deletion condition; see SKILL R5):

- Freeze scope: which modules get no new features, only bug fixes.
- Owner: who maintains the old implementation.
- Dependencies pinned, with how security updates will be followed.
- At least one numeric trigger for reconsidering, e.g. p99 above X ms for N consecutive days, call volume reaching k× today's, fewer than 2 people able to maintain the old implementation, a key dependency reaching its EOL date.
- Review date; who checks the triggers, and with which command.
- If new code already exists (you stopped halfway): move it to an archive branch (e.g. `archive/rust-<target>`) with a STATUS file at its root saying what works, what doesn't, the last green commit and why it was parked. On release branches, enforce `git grep -n '<new toolchain or crate name>'` = 0 in CI. decisions.md links the archive branch.
  Why: half-finished new code left on a release branch gets built, imported or shipped by accident. An archive branch with a STATUS file keeps the work recoverable without it leaking into releases.

Why: an open-ended "not now" gets re-argued over and over. "Identified, intentionally not done" with triggers gives a decidable restart point.

## 10. Process tier (light / full)

Decide the tier first thing, and again whenever the consumers or the cost of being wrong change (a personal script gets picked up by another team, the code starts touching money or data). Record `tier` and its basis in decisions.md. What each tier runs: see SKILL Step 0; in addition:

- The tier follows from two quantities: the **cost of being wrong** (what one mistake costs: a few seconds of rerun, or lost data, wrong money, downtime) and the **number of external consumers** (who reads this output). Process is complexity too; keep it proportional to these two.
  Why: for a small internal tool, the biggest risk is that process kills the migration, not that behavior drifts.
- Find consumers by looking, not from memory: compile the repo, `grep -rn` call sites, check host-level entry points (cron tables, service and timer units) and indirect calls assembled through variables or wrapper scripts. Search by name fragments, not just full names. If you can't enumerate them all (public library, service API, text parsed by other people's scripts), count it as "has unknown consumers", which means external.
- Light tier fits only when the output is internal, inputs can be rerun at any time, and a mistake is noticed right away. Build the old-commit worktree with `git worktree add ../old <old-commit>`. The single read-only adversarial subagent (SKILL R2) still runs after the differential run is green.
- When unsure, pick full.
  Why: an unnecessary full tier costs some hours; a wrong light tier costs whatever the mistake costs.
- A light-tier task escalates to full the moment one of the full-tier conditions shows up. Change `tier` in decisions.md and add the outputs the full tier needs (observation window, transitions.md, 2–3 adversarial subagents) before going on.
- Different slices of one migration may sit in different tiers, e.g. internal helper functions light and the public output format full.
