---
name: migrate-rust
description: >-
  Behavior-preserving migration to Rust, where the old implementation decides what "correct" means.
  Use when porting or rewriting existing code in Rust (e.g. Python via PyO3/maturin, Go, C/C++),
  moving a hot path into a Rust extension, or replacing a service, CLI or library with a Rust one,
  even if the user never says "migration", including when asked for a plan, decision memo or
  runbook for such a port. At any step: whether it is worth it; continuing, pausing or
  abandoning a port already under way; differential testing old vs new, including parity scored by
  a noisy judge such as an LLM; AI-assisted translation; parity or speedup claims; shadow traffic,
  rollout, rollback; deleting the old code or tables; undoing port steps taken without
  approval. Prefer it to generic code review for Rust-port PRs. Also use for bugs after
  such a port (PanicException, GIL deadlocks, broken wheels, output or speed differs from the old
  code). Not for greenfield Rust, or upgrades and data migrations that move no code to Rust.
---

# migrate-rust · the old implementation is the referee

Agents migrating code usually know to write goldens, diffs and benchmarks. They fail on **strictness**: expectations derived by hand, outputs normalized before comparing, corpora too small, thresholds loosened after the fact, observation windows too short, decisions pushed to a human when the evidence was already there.

**Terms.** *Referee*: the pinned old version whose real output is the expected value. *Check*: a machine-run command + threshold + denominator; a *gate* is a check that blocks the next step. *Differential testing*: old and new run on the same inputs, outputs compared byte for byte. *Transitional artifacts*: flags, shims, dual-writes, exemptions and `unsafe` workarounds that must eventually be deleted. *Close-out*: the old code and every transitional artifact deleted, with a guard against the old path coming back. *Owner*: whoever may approve a change that consumers will see.

## Step 0 · pick the process tier

| Tier | When | What you run |
|---|---|---|
| Light | Small port, no external consumers, no money, persisted data or security, one revert undoes it | Record a behavior baseline, diff-test the full fixture set against a worktree of the old commit, keep existing tests green, and delete the old code, all in one PR. One read-only adversarial subagent instead of 2–3; no observation window, no transitions.md |
| Full | Any external consumer, money, persisted data, security, or a one-way door; or you are unsure | Everything below; details in `references/decide.md` §10 |

R1 and R2 hold in both tiers. Switch to full the moment a full-tier condition appears.

## Step 1 · read the matching references in full, before you write anything

This file is a summary. The thresholds, minimum fields, commands and step orders the rules depend on live in `references/`, and plans built from this summary alone keep missing them. **Before you write a plan, a check, Rust code, a cutover step, a review verdict or a go/no-go answer, Read every file whose row matches the task, whole: one Read call with no offset or limit.** Each file is short and opens with its own "most often missed" list. Use Grep only afterwards, to find your way back; a symptom word rarely matches the section that answers it. A full-tier plan usually matches decide, checks and templates plus the topic rows; a light-tier port, checks plus the language file.

| File | When the task involves |
|---|---|
| `decide.md` | whether a port is worth it; goal vs root cause; reading a profile, Amdahl; choosing between two designs or modes; continuing, pausing or parking a port; maintainers leaving; slices; process tier |
| `checks.md` | acceptance.md; the differential harness; normalizers, tolerances, allowlists; corpus; proving a check fails; freezing pass bars before the first implementation change; flakes; faults; perf gates per load class; slower than the old code, speedup claims |
| `review.md` | after green: adversarial self-review; parity scored by an LLM judge or other noisy scorer; PII, secrets or regulated data; official conformance suites; old code already deleted; reviewing someone else's port PR |
| `py2rust.md` | writing Rust or PyO3 for Python code; output mismatch, panic, hang, GIL, memory growth; any port: Rust-side traps (overflow, panic boundary, HashMap order, async and blocking) |
| `go-c-cpp.md` | porting from Go or C/C++; `unsafe`, FFI, UB in the old code |
| `ai-translation.md` | an AI (you included) translating or bulk-editing code; fallbacks added to get green |
| `cutover.md` | dual-write, shadow, backfill, reconciliation, rollback, canary or ramp (read closeout.md with it once the plan goes past the ramp) |
| `closeout.md` | one-way doors; consumers, alerts and dashboards; wrong data already consumed; deleting old code, tables or archives; client-installed releases; security-driven ports |
| `delivery.md` | wheels, install failures, CI layers, slow CI, build profiles, licenses, type stubs |
| `templates.md` | creating decisions.md, contract.md, acceptance.md or transitions.md |

## How to work (every step)

1. **Write the check before the change.** Put "what done looks like" in `acceptance.md`: command, threshold, denominator. Before fixing a bug, bad data or a stored inconsistency, write a test that is red on the current state, archive the red output, then fix and watch the same command turn green.
2. **Run every check after every step.** Fix red before stacking more work on it.
3. **Conclusions carry numbers:** check name · score · threshold · pass/fail · evidence file (query result, differential report, benchmark JSON). Where no check exists, say "no check yet" and draw no conclusion. An empty gate query is not zero: first assert it returned one series or a non-zero row count.
4. **What you can't run becomes a test marked "skipped, run manually"** with the manual steps written out, so the gap stays visible.
5. **Tool flags and API names change between versions.** Take versions from the package manager, and check every command in the references against the versions the project has locked.

## Six rules (always in force)

**R1 The old implementation is the referee.** Expected values come only from running the version the owner named: not hand-written, not derived from a spec, never generated by the new code. Before registering an *intended difference*, run the old code on those inputs and paste its real output, because guessed differences are often wrong. Pin the referee first: full interpreter or compiler version, resolved paths, Unicode/tzdb tables (checks §1). Verify the data premises you're given ("the new DB has all history", "nobody reads this table") yourself.

**R2 Checks: every channel, byte-exact, proven to fail, then frozen.**
- Compare stdout, stderr, exit code, exception type/message/chain, files, permissions, the environment child processes see, outbound requests, and rendered output (checks §4). **By default, no normalizer touches the data.** Only where the old code is itself nondeterministic (order, time, addresses) use an invariant or set comparison, written as an equivalence rule with a counterexample showing it can't hide a real difference. Any other loosening (tolerance, allowlist, fewer channels, dropped fields) goes to the owner per R6(b). Fallbacks or loosenings you added yourself to get green are disclosed and registered, and their count is 0 at close-out (ai-translation §6).
- Before relying on a check, watch it go red on a deliberately broken implementation. A run that selects zero cases must fail, warn-only categories count as red, and every high-risk point is caught by at least 2 cases (checks §6).
- **Thresholds are tighten-only and existing tests and goldens are append-only.** CI compares acceptance.md thresholds with the freeze commit and fails on any loosening; at the end, `git diff <start commit> -- <tests> <goldens>` shows only additions. Exceptions, each with a one-line ruling and the archived before-output: a test asserting the very bug you fix (R6(a)); goldens recorded under a wrong referee, re-recorded by script (checks §7); tests rewritten for a framework change, where per-file assertion counts, coverage and a sampled mutation score must not drop.
- Once the differential run is green, send 2–3 read-only subagents to pick inputs from the old source (review §3). Green only proves the cases you thought of; in one real porting trial a green suite still hid 9 differences.

**R3 Measure before you claim.** Every number must be recomputable from raw data, with the command attached. Hotspot share is inclusive: a sample counts once if the function is anywhere on its stack. Compute the Amdahl ceiling 1/(1−p) and check that the target is physically reachable. Speedups come from same-machine runs that alternate old and new; profiles show where time goes, they don't measure speedups. For a hang, capture all thread stacks (native ones too) before concluding anything.

**R4 One variable at a time; port the obligations, not the shape.** First translate literally until the checks are green, then make an idiomatic pass, then swap or upgrade libraries, each in its own commit; fixing an old bug is a separate step. If the new library version removed the old API, see decide §5. Internal details no consumer can observe (non-atomic steps, nondeterministic order, line-at-a-time processing) may change once R1/R2 hold, but flush timing, streaming latency and side-effect order are observable, so port them. Failure paths don't overwrite user data; take a backup first. When the migration exists to remove a defect in the old code (a vulnerability, memory unsafety), errors fail closed instead of falling back to the old path (closeout §6).

**R5 The contract is everything any consumer can see.** Before you write down the contract, find the real callers (whole repo, plugins, traffic, logs, alerts, dashboards, downstream jobs) (for alerts: inject a fault in staging and assert the alert fires in time, closeout §2), count them, and set comparison granularity by how they actually use the output. The delivery surface (wheel matrix, interpreter variants, install artifacts) is contract too. Every transitional artifact has an owner, a deadline and a deletion condition, and CI goes red when a deadline passes (templates §4).

**R6 Decide yourself, or escalate.**
- (a) Decide yourself by default. Put the options in one table with the same numeric columns and units (no "TBD"), name your pick, and say why each other option lost. Changes the task itself requires belong here too: the failure you were asked to fix, or turning a crash callers can't handle (panic, abort, deadlock) into a catchable error. Before that, `rg` for code that already catches that crash type, because the change alters what those callers see.
- (b) A change that existing consumers will see and the task didn't ask for goes into `pending-decisions.md`, the only place pending items live (stable ID, question, options, cost, recommendation, default). Ask the owner when an item blocks the next step or four have piled up, at most four per batch; your recommendation is the default. Keep working on everything that doesn't depend on the ruling. Decided items move to `decisions.md`.
- Out-of-scope work (optimizations without a numeric target, extra features) is proposed, not written. If migration work already went past what was approved (scaffolding created, old code deleted, commits pushed), stop, list every change, keep it recoverable (`git revert` on shared branches, never a force-push; parked code per decide §9), and ask before redoing it. Project policies and approval gates are hard constraints; list them before you start.

## Default strictness (when the task or contract gives a number, use the stricter one)

| Item | Default |
|---|---|
| Differential / property cases | Pure functions <1 ms per case: ≥1e6; <100 ms: ≥1e4; money, security, parsing ×10; domain ≤2^24: exhaustive; real corpus: all of it |
| Where cases come from | The old code paths, not the feature list: ≥2 cases per output-rewriting rule, OS boundary and error branch; vary environment axes (tty, locale, permissions) |
| Flaky / concurrent | n ≥ 3/p runs (p = 1% → 300); thread levels {1, 2, cores, ≥16, ≥ production concurrency}; run old-vs-old first; retries never count as green |
| Sampling and drills | Fixed seed; compare bytes (cmp, sha256), not fields |
| Benchmarks | ≥10 alternating same-machine runs, thresholds written in advance; gate each load class (size × kind) separately, because an overall ratio can hide a regression in one class |
| Resources | Batch peak RSS ≤ k × input size, k measured on the old code; streaming at 1× and 10× input, peak ratio ≤ 1.1 |
| Observation window | Covers the longest business cycle and at least one month boundary; usually ≥35 days |
| Source guards | Each look-alike pitfall becomes an `rg` or clippy guard with 0 hits; exemptions live in one allowlist that only shrinks; panic guards take no exemptions. New `unsafe`: go-c-cpp §4 |
| Protected data | PII, credentials and regulated data stay out of corpora, goldens, logs, panic messages and AI context; detector hits = 0 (review §5) |

## Often skipped (reminders, not a substitute for Step 1)

- **Parking or pausing** a port: new code goes to an archive branch with a STATUS file, CI asserts `git grep -n '<new crate or toolchain>'` = 0 on release branches, and the decision names at least one numeric restart trigger and a review date (decide §9).
- **decisions.md minimum**: root_cause, goal, raw_profile, recompute_cmd, hotspots with incl_pct, amdahl {p, s, upper_bound, target, pass}, verdict (templates §1).
- **Every plan step has a rollback cell**; a step with an empty one is a one-way door and goes last (cutover §1).

Before finalizing a high-stakes conclusion (public API, money, deleting data), have another model family or a person review it read-only, and respond to every finding.
