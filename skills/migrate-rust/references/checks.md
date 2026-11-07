# checks · building checks and differential tests

**Read this file in full** before you write acceptance.md, a differential harness, a comparator, a normalizer or a perf gate. Rules: SKILL R1–R6; numbers: Default strictness table. Templates: templates.md.

**Most often missed here**
- §3 Differences you can't remove go into an allowlist, and the affected owner confirms each entry. You never set a tolerance yourself.
- §3 Compare as a set only where the old output has no defined order (e.g. SQL without ORDER BY), under an equivalence rule. Everything else is byte for byte.
- §5 Inputs you can't build locally go to another environment or CI runner before you write them off as a platform limit.
- §7 Pass bars, goldens and allowlists are committed on their own, before the first implementation change (commit timestamps prove it).
- §9 After a failure, compare old vs new resulting file state, not only the exit code; failure paths never overwrite user data (SKILL R4).
- §10 Each load class has its own perf gate, written before measuring and never loosened.

**Sections** · §1 Which exact old build is the truth? · §2 Where may expected values come from? · §3 When may a comparison be relaxed? · §4 Which channels must be compared? · §5 Which inputs, and how many? · §6 How do I prove the check can fail? · §7 What is frozen, and when? · §8 Why does it flake? · §9 What happens on bad input and faults? · §10 How are speed and memory gated fairly? · §11 How do I make sure "0 differences" isn't "0 compared"?

## 1. Pin the referee
- Before any run, a script prints and asserts the referee fingerprint (R1): full interpreter version (`python -c 'import sys;print(sys.version)'`, not `pyvenv.cfg`, which may stop at the minor version), interpreter path after `realpath`, key library versions, data-table versions (`unicodedata.unidata_version`, tzdb, locale data), lockfile hash. If any item differs from acceptance.md, refuse to run. Why: floating symlinks in package managers swap the referee between two runs without telling you.
- Compiled referee: also pin compiler version, flags (optimization level, `-f…` options, defines) and target width (pointer size, `long` size, endianness). Service referee (a database, a broker): pin the server version, server config, and session variables (SQL mode, time zone, collation, isolation level), and assert them at connect time. Why: the same source compiled or queried under different settings is a different referee.
- Referee, CI and local machines use one image or one lockfile; assert the versions are equal across all three. Skip count is 0 or ≤ baseline. Why: different data-table versions classify the same character differently.
- Single sources exported from the referee (character tables, error-message tables, constant tables) go into the repo with their generation command; CI reruns the generator and runs `git diff --exit-code`. Why: a generator that lives only in a chat transcript can't regenerate or verify the source.
- Take dependency and toolchain versions from the package manager (`cargo search <crate> --limit 1`, `pip index versions <pkg>`), not from docs or a guide on the main branch. Why: docs can run ahead of the released version.
- Before using the old code as referee, make its own tests pass in a controlled environment (`--impl=old`, 0 failed). On failures or odd output, check the environment (PATH, working directory) and your own invocation (shell word-splitting; pass arguments as arrays) before suspecting the old code. Why: if the referee isn't green, no differential result is trustworthy, and most early "referee failures" are setup mistakes, e.g. a venv missing from PATH, or a capture loop the shell didn't word-split.
- At startup the test harness `canonicalize`s both executables or module paths and checks their sha256. Why: relative paths break once a subprocess changes directory.
- Existing goldens: at kickoff, re-run a sample (default: 5% or 50 entries, whichever is larger, chosen by a fixed seed) under the pinned referee and compare byte-for-byte. Any mismatch means they were recorded by a different referee; re-record per §7. Why: goldens inherited from an unknown environment encode that environment, not the referee.
- Borrowed upstream test suites: write down what they don't cover (channels, input classes, platforms) and which tests touch global state (env vars, cwd, locale, registries, files outside a temp dir). Run the polluting ones isolated (own process) and add your own cases for the gaps. Why: a green upstream suite says nothing about what it never tests, and leaked global state makes later tests pass or fail by order.
- C/C++ referees can emit bytes that depend on undefined behavior; detect and register them per go-c-cpp §3 before freezing goldens.
- Rebuilt referee (the original runtime is end-of-life and you had to rebuild it, image pinned by digest): pass a fidelity gate first. Re-run archived production inputs and compare against the outputs that were actually shipped; byte-identical count == archived count. Why: a rebuilt referee is a new implementation until proven otherwise.

## 2. Where expected values come from
- Goldens are generated by a fixed, committed script that calls the old code. Test files contain no hand-written expected literals (guard: `rg` the test dirs for long literals or hex strings). Why: expectations written by hand or derived from a spec come from the same understanding as the new code and share its blind spots.
- Keep a frozen copy of the old code with a hash (an `_orig` module or a separate venv; sha256 in acceptance.md). Check the hash before generating any new golden. Existing goldens are append-only, see SKILL R2. Why: if the referee gets edited in passing, goldens drift with it.
- Evidence for an intended difference (R1) contains at least: a copy-pasteable command (env vars, locale, tty or pipe), the old code's raw stdout/stderr bytes (or sha256 plus file path), exit code, referee fingerprint. The "difference" column of the attribution table (templates §2) cites this evidence directly. Why: a conclusion without the command can't be re-checked.
- If the owner names a referee version different from production, list the drift between the two as differences, decide each one, and only then start translating.

## 3. Comparison rules and the equivalence template
By default compare raw bytes with exact types (`True≠1`, `-0.0≠0.0`, NaN bit patterns, `dict≠OrderedDict`, key order all count), with zero normalizers on data (SKILL R2).
Every normalizing function, tolerance, sort or filter in the comparator source needs a matching entry under "Equivalence rules" in contract.md. Unregistered normalizers: 0.

The equivalence template is **only for channels where the old code is itself nondeterministic** (order, time, addresses). You decide these yourself per R6(a):

```yaml
- id: EQ-<n>
  scope: which channel / which cases (as narrow as possible)
  nondeterminism: where the old code is nondeterministic (command and result of two old-vs-old runs that differ)
  relaxation: what the comparison becomes (e.g. set comparison; strip `0x[0-9a-f]+` addresses from repr)
  why_safe: why it can't hide a real difference
  proof: mutation or counterexample showing it still goes red (command + result)
  decided_by: self (R6a)
```

- Any other loosening (float tolerance, allowlist, comparing only some channels, dropping fields, soft categories) is not yours to register. Escalate to the owner per R6(b) with a recommendation and a default; once approved, record the decision ID and the bound in contract.md. An approved float tolerance is derived from dtype precision (e.g. `k × np.finfo(dtype).eps × |expected|`) with the origin of k written down; everything outside the tolerance (step counts, counts, shapes, integer fields) stays exactly equal. Why: a tolerance that "looks small enough" also swallows regressions in accumulated error.
- Prove each normalizer with at least one mutation: inject a difference it should preserve; the comparison still goes red.
- When comparing async replicas (read replicas, caches, search indexes, CDC consumers, materialized views), read at a consistency point; this is not a loosening. Record the source watermark (LSN, binlog position, transaction ID, event offset), wait until the replica reports it has applied ≥ that watermark, then read both. Don't use a "wait N seconds" window. Why: a time window happens to suffice at low load and not at high load, so results flip randomly; with a watermark, red means a real inconsistency.
- Soft categories ("bytes differ but semantics match") are red by default. A warning-only result is a pass in disguise. Why: an exception message got changed, every test stayed green, and the only trace was one warning.
- Scope an intended difference to its channel: label it `stdout:`, `stderr:`, `refuse:`; other channels stay strict. Why: "this group of cases may differ" also hides unrelated bugs in the same group.

## 4. Every observable channel
Every row of a differential record has at least these fields; the harness goes red if one is missing:

| Channel | Fields | Notes |
|---|---|---|
| stdout, stderr | `stdout`, `stderr` (raw bytes) | test both pipe and tty |
| Exit | `exit_code`, `signal` | killed-by-signal recorded separately |
| Exceptions | `exc_type` (`type(e).__module__ + __qualname__`), `exc_args`, `str(e)`, `__cause__`/`__context__` type chain, `isinstance` against the original class | the class name alone isn't enough: same name, different class won't be caught |
| Files | content bytes, permission bits, symlink targets, leftover temp files | compare before/after snapshots |
| Subprocesses | argv seen, environment (order and values), signal dispositions | runtimes modify the environment |
| Network / service responses | HTTP status, headers, body | |
| Outbound requests | method, target (host, path, query), headers, body, idempotency key | captured by a recording sink, matched by business key; see cutover §6 |
| Rendered output | pixels (screenshot diff at fixed viewport, fonts, DPI), DOM (serialized tree) | pin the renderer like the referee |
| Side-effect order | order of prints, file writes, errors | order is behavior (R4) |
| Path | fast path hit vs fallback (counter) | see §6 step 4 |

- Exceptions Python raises implicitly (`RecursionError`, `RuntimeError: dictionary changed size`, `UnicodeDecodeError`) get an explicit mapping table, one case per row; new cases assert `PanicException` does not appear. An old test that asserts `PanicException` is raised is changed only under the R2 exception: it asserts the very bug being fixed; write an R6(a) decision and archive the red output from before the change. Why: a panic or stack overflow on the native side turns a catchable exception into a process crash.

## 5. Corpus: derive it from the old code paths
- Open the old code and the runtime and framework source it depends on. List every rule that rewrites output (ANSI stripping, encoding, wrapping, repr escaping, JSON escaping), every OS-call boundary, every except/error branch, every dispatch order. Cases per item follow the Default strictness table; the list's row count equals the number of items derived from source. Why: a corpus written from the feature list went all green, then inputs picked from code paths found several differences.
- Multiply each input group by environment axes: tty / pipe, locale (UTF-8, C, POSIX, non-UTF-8), permissions, read-only dirs, HOME and cwd shapes, paths through symlinks. Combine file states (e.g. "read-only dir + contains an invalid line").
- The harness's data types must represent the full input domain first: arguments, env vars and paths as bytes (`OsString`/`bytes`), not `String`/`str`. Why: the type excludes non-UTF-8 input as a class, so not a single case can be written.
- Before running, a script counts occurrences of target inputs in the fixtures (code points under test, boundary values, odd encodings, specific file states). Every count > 0; the count table goes into acceptance.md. Add fixtures for any zero and re-run. Why: if the target character isn't in the fixtures, the diff is still green and "covered" is only apparent.
- Inputs you can't build locally (e.g. APFS rejects non-UTF-8 filenames): move to an environment that can (Linux container, a volume with another filesystem, another CI runner) and diff-test old and new there. Only when no available environment can, record it under "Platform limits" in acceptance.md (with the environments tried) and test its error path instead; don't drop it silently. Why: the filename is legal on Linux and real users hit it; recording it as a local limit leaves that input class untested.
- Case IDs are derived from content hashes, not position; check for duplicates on generation. Why: positional IDs shift on every insertion and old reports stop matching the mutation table.
- Write the minimums into acceptance.md and tick them by script: corpus size, every boundary-list item hit, property-test case count (per Default strictness table), full real corpus.

## 6. Prove the check can fail
R2 requires each check to prove it can fail. Do these in order and archive each step's command and result:

1. **Negative control**: swap the new code for something obviously wrong (point the executable under test at `/bin/echo`, a stub that returns a constant). The whole suite reports DIFF and exits ≠0.
2. **Empty selection**: `--only <nonexistent ID>` selecting 0 cases exits non-zero; the summary must not say "0 diffs".
3. **Artifact under test**: print and assert the build sha at runtime (e.g. `__build_sha__ == $GITHUB_SHA`), release/debug, target config, so you know you tested this build.
4. **Path hit**: with a fast path plus fallback, put a counter on the fallback entry: normal input → 0, input past the threshold → > 0. Why: if the fast path is skipped the output is still right, so comparing outputs can't see it.
5. **Mutation**: cover boundaries, dispatch order, error branches, encoding tables, side-effect order, and more. Cases catching each high-risk point follow R2; add cases for points caught by only 1. Mutants must compile. For a survivor, first decide whether it's an equivalent mutant and write why; don't add tests to "kill" an equivalent one. Target: non-equivalent survivors = 0.
6. **Red before fixing a bug** (SKILL "How to work" item 1): run the same command before the fix, archive the red output, then fix.
7. **Membership, not just counts**: compare sets and contents; order-preserving when order is in the contract. Prove by script that each exemption appears 0 times in the corpus. Write down "what this check does not compare"; that line is the entry point for review §3.
8. **Self-consistency**: where an output points into itself or its input (offsets and spans, counts, totals, checksums, IDs that must resolve), assert the invariant on every case (e.g. `input[start:end] == extracted_text`, sum of parts == total) in addition to equality with the old code. Why: old and new can agree on a wrong output; an invariant is a check that doesn't depend on the referee.

After fixing a bug in the harness itself, add a negative control proving it still goes red.

## 7. Freeze and tighten-only
- Commit goldens, thresholds, tolerances and allowlists on their own, before the first implementation change. Prove the check commit predates the implementation commit with `git log --format=%ct`.
- Before claiming a pass, run `git diff <freeze commit> -- tests/ golden/ <lockfile>`: tests and goldens show additions only (SKILL R2). Machine check: `git diff --diff-filter=MDR --name-only <freeze commit> -- tests/ golden/` is empty except for exceptions listed in acceptance.md. Handle the exceptions per R2 and record the decision and red-output path in acceptance.md. Thresholds and tolerances only tighten.
- Re-recording goldens recorded by the wrong referee (fingerprint mismatch, found by the §1 kickoff sample): re-record the whole set with the committed script under the pinned referee, in a commit of its own. The diff may touch only files the fingerprint difference explains (e.g. only cases involving code points whose Unicode data changed); list the predicate and check it by script. No hand edits. Why: a re-record is the one sanctioned way to change existing goldens, so it has to be mechanical and bounded.
- The CI comparison step must block the pipeline on failure: `rg 'continue-on-error|\|\| true'` over the CI config for comparison steps returns 0 hits; print the denominator and skip count in the CI log. Why: a comparison step that swallows its exit code is no gate.
- Edit test code with exact replacements (unique-match or by line number) and read the diff to confirm no assertion got weaker (ai-translation §4 item 4).
- Exemptions go only into the one guards allowlist; ratchet rule in py2rust "Guards in general". Record the count in acceptance.md. Panic guards have no exemptions.

## 8. Determinism and flakes
- Source-scan guard: no unordered hash-map iteration, wall clock, or unseeded RNG on output paths (e.g. `rg 'HashMap|HashSet|SystemTime::now|thread_rng|rand::rng'` returns 0 in output-related modules, or there is a registered sort). Why: these three sources make the same input produce different output, so the diff flakes red and won't reproduce.
- Same input, same seed, each thread count in the Default strictness table, N runs per count: distinct output sha256 = 1. With a different seed, distinct > 1, proving the seed matters.
- For each perturbation axis, write the expectation (changes / doesn't) before running: `PYTHONHASHSEED` in {0, 1, random}, each thread count, each pool-size env var. Where the old code is invariant on an axis, the new code must be too. Where the old code itself varies with the hash seed (e.g. prints set iteration order), confirm with old-vs-old, then switch to set or invariant comparison per R2 and register an equivalence rule (§3). Every setting where actual ≠ expected is a difference and goes into the attribution table. Why: one hash seed and one thread count can't separate "deterministic by luck" from "deterministic"; old code depending on the hash seed while new code fixes the order is also a difference.
- The number of repeated runs to rule out flakes follows the Default strictness table; the seed set is fixed and replayable.
- Retry guard: `rg 'reruns|flaky|retries|retry\('` in test config returns 0. Why: retries report "sometimes wrong" as green, hiding exactly the flakes you're looking for.
- When something flakes red, first run **old vs old**. Also red → the harness is at fault (the comparator doesn't handle addresses that naturally differ); register per §3. Not red → the implementation is at fault. Pin the counterexample as a fixed case. Why: random tests sometimes hit repr address differences and fail in pure-old mode too.

## 9. Fault injection and bad input
- Write a fault matrix, one assertion per row: disk full, permission denied, rename failure (incl. cross-filesystem), interruption (SIGINT/SIGTERM timing), duplicate delivery, partial write, very deep nesting, self-referential structures, truncated input, malformed encoding. Each row compares old and new output, exit, and resulting file state.
- Fuzz each target until coverage stops growing; crashes, aborts and non-OK counts = 0; after a panic the service keeps serving requests normally.
- Before claiming, run fuzzing, soak and rolling restarts on a release build with production config; assert config == production; old and new conserve state identically (counts, balances, row counts).
- Test host-language resource limits at each step: recursion depth in {1, limit−1, limit, limit+1, far above}; memory per the Default strictness table "resources" row. Why: where the original raises a catchable exception, native recursion segfaults.
- Paths that sort, group or buffer a whole input get a bounded-memory test: an input several times larger than the peak-RSS cap, peak RSS stays under the cap (spill to disk / external sort where the old code streamed or the contract requires it). Why: tests on small inputs never show unbounded buffering.

## 10. Perf gates and benchmark fairness
Pass determinism and bit-exact differential testing before reporting any ratio; every benchmark sample also carries an output comparison (empty diff). Rules in SKILL R3; run counts in the Default strictness table "benchmark" row.

**Gate each load class separately, not overall.** Split the workload into load classes by input size and kind (e.g. small/medium/large × each request type, plus inputs that take slow or fallback paths). Each load class has its own gate: new/old ≤ its threshold, written before measuring. An overall ratio is not a conclusion, because a big win in one load class hides a regression in another. Each resource (median and tail latency, peak memory, startup, boundary-crossing cost) is a separate gate too. A mixed load (production-like blend, fixed seed) is gated on its own row, not inferred from the load classes. After fixing a regression, re-measure once on full production volume (snapshot or replay), not just the load class that failed. Why: a fix for one load class often shifts cost to another, and small inputs don't show growth that only appears at full size.

Tick the fairness checklist item by item in the report:
- [ ] Thresholds were in acceptance.md before the run and unchanged after (adding a target after measuring is a counterexample). Same machine, same command, old and new **interleaved** (hyperfine multi-command mode or in-process A/B alternation), not one side first.
- [ ] GC, caches, thread pools set as in production; timeit-style tools disable GC by default, so enable it explicitly. Report median and spread (max/min or IQR); give ratios as intervals; worst pairing = old fastest ÷ new slowest.
- [ ] Inputs include slow-path types (subclasses, rare types, shapes that fall back); large objects aren't one reference repeated. Time end to end, including boundary-crossing and startup. Peak RSS via `/usr/bin/time -l` (macOS) or `-v` (Linux).
- [ ] Time on a production snapshot or real load distribution; label synthetic data separately. Ratios always come from timing; profiling is only for locating (cProfile inflates ratios substantially).
- [ ] List uncontrolled conditions (frequency scaling, big/little cores, co-located load, cold/warm cache).
- [ ] Load tests name the tool, duration, arrival rate and concurrency, and judge the error rate (e.g. 5xx share) against the old path measured in the same period, with the threshold written in advance.
- [ ] Every number in the report is computed by script from raw JSON, with the recompute command attached.

## 11. Fixed denominators and machine verdicts
- Before declaring 0 differences, assert: compared count == total (`compared` rows == `find`/manifest count), ≥1, skips ≤ baseline; a monitoring query returns exactly 1 series. Why: a harness that selects 0 cases and exits 0 reports "didn't run" as "all passed".
- A script generates the verdict file (e.g. `verdict.json`): it reads thresholds from acceptance.md plus the raw data and outputs `verdict ∈ {pass, fail, inconclusive}` with each number. Human reports only cite it; recomputing gives an empty `diff`.
- Every conclusion in a report is written as check · score · threshold · pass/fail · evidence file. Grep-guard number-free conclusion words ("basically matches", "clearly faster", "should be fine"): 0 hits. Why: a conclusion without a number can't be recomputed or proven wrong.
