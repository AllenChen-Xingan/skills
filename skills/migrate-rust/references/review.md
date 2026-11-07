# review · self-review, noisy scorers, protected data, conformance suites, reviewing others' ports

**Read this file in full** once differential testing is green and before you claim parity; also when the equivalence score comes from a noisy scorer (an LLM judge, sampled review, a random load test), when real data is sensitive, when a public test suite disagrees with the old code, when the old code is already deleted, or when you review someone else's migration PR. Rules: SKILL R1–R6.

**Most often missed here**
- §3 Send 2–3 read-only subagents to build inputs from the old source, and diff-test each one.
- §4 A noisy scorer is a check of its own: freeze model ID, temperature, prompt hash and seeds; repeat ≥5 times. Parity needs the paired-bootstrap CI inside a margin ±δ set before the run; an improvement needs the CI lower bound > 0.
- §5 A PII or secret detector hit is an incident: delete the artifact. Masking it in place doesn't count.
- §7 Before deleting the old code, seal a runnable referee image.
- §8 When reviewing a port, stay read-only and recompute the reported numbers yourself.

**Sections** · §1 Do real callers still get the same downstream result? · §2 What does a fix to an old bug record? · §3 How do I hunt for differences after green? · §4 How do I judge with a random or noisy scorer? · §5 How does protected data stay out? · §6 What if an official suite disagrees with the old code? · §7 What is the referee once the old code is gone? · §8 How do I review someone else's migration?

## 1. Real-caller replay
- Run old and new with the real callers in the contract.md consumer table and real inputs (logs, traffic recordings, input snapshots of downstream jobs). Compare **downstream** results (reports, decisions, downstream tests), not proxy metrics.
- Record `flips`: the number of downstream conclusions that flipped. Each flip goes through the attribution table.

## 2. Fields for fixing an old bug
Fixing an old bug is its own step (R4), with a test that goes red first (SKILL "How to work" item 1). First confirm the bug exists (ASan, Miri, replay, a counterexample run on the old code). Beyond what R6 requires, the decision records at least:
`effective_date`, `backfill` (number of affected stored records and how to backfill), `notify` (which consumers), `flag` (flag name, default value).

## 3. Adversarial self-review: dimensions and subagent prompt
Do this after differential testing is green and before claiming (end of SKILL R2). Build at least 1 counterexample per dimension and diff-test it against the old code:

| Dimension | Look for |
|---|---|
| Input-domain representation | inputs the harness types can't express (non-UTF-8 bytes, very long, empty, NUL) |
| Runtime rewrites | every rule by which the old runtime or framework rewrites output (ANSI, repr, JSON escaping, wrapping) |
| File-state combinations | permissions × content × symlinks × rename failure |
| Environment and locale | locale, tty, HOME, COLUMNS, env vars the runtime injects itself |
| Exception chain and identity | `__context__`/`__cause__`, args, `isinstance` against the original class |
| Subclasses and protocols | subclasses overriding `__iter__`, `items()`, `__bool__`; sequence unpacking |
| Caches and reload | cached host objects going stale after reload or with multiple interpreters |
| Registration and global state | empty / non-empty registries, monkeypatching, order dependence |
| Mutation during iteration, implicit copies | callbacks mutating containers or the input buffer |
| Resource limits | recursion limit, memory, a lowered `setrecursionlimit` |
| Measurement method | can the benchmark detect its own errors |
| Registered intended differences | does each carry evidence from running the old code |

Send 2–3 read-only subagents in parallel, each with a group of dimensions. Prompt template:

```text
You are a read-only reviewer. Don't modify any file. Goal: find observable behavior differences between the new and old implementations.
Old code: <path> (plus the runtime/framework source it depends on: <path>)
New code: <path>. Run old: `<command>`; run new: `<command>`
Channels the current checks compare: <list>. Explicitly not compared: <the line written in checks §6 step 7>
Your dimensions: <3–5 items from the dimension list>
Method: start from the old code's source, not from a feature list. Find each output-rewriting rule, OS boundary, error branch and dispatch order;
build one input for each and actually run it on both sides.
Report only items you ran that really differ. For each: dimension, input (copy-pasteable command), old output, new output (with exit code and stderr),
suspected cause. If you're unsure whether something counts as a difference, list it under "needs decision" with both actual outputs. Make no changes beyond suggesting fixes.
```

Every difference found goes into the attribution table (templates §2) and gets a fixed case in the corpus.

## 4. Non-deterministic checks
For random checks (LLM grader, sampled human review, load test with random arrivals): freeze model ID, temperature, prompt hash and seed set in acceptance.md (any change is a new check with a new baseline); repeat ≥5 times and report mean ± SD.
Claim an improvement only from a paired bootstrap over identical items whose CI lower bound for the difference is > 0; a single noisy run can show any difference you want.
To claim parity, write a non-inferiority margin δ into acceptance.md before the run (owner-approved per R6(b)); pass only if the paired-bootstrap CI for (new − old) lies entirely within ±δ. A CI that merely includes 0 is no evidence of equivalence: with few items or a noisy scorer it includes 0 almost always.

## 5. Protected data
Protected data (PII, credentials, regulated data) stays out of corpora, goldens, logs, panic messages, and context sent to AI tools.
- When real data is restricted, build the corpus from synthetic data plus boundary-constructed cases (max lengths, odd encodings, empty and null fields) shaped like the real schema. Real-data runs happen only inside the approved environment, and only verdict numbers leave it.
- Run a PII detector (pattern rules for emails, phone numbers, card and ID numbers, plus a secret scanner such as gitleaks) over logs, goldens, fixtures and captured panic/error messages. Hits = 0 is a gate; any hit blocks and the artifact is deleted, not masked in place.
- Types with sensitive fields don't `derive(Debug)`; wrap the field in a newtype with a redacting manual `Debug`. Guard, with the sensitive field names from contract.md: `rg -n -A6 'derive\([^)]*Debug' src/ | rg '<sensitive-field-regex>'` returns 0. Why: one `{:?}` in a log line or panic message ships the whole struct.
- Nothing protected goes into prompts, files or context handed to AI tools (including subagents in §3); give them synthetic samples and schemas. Why: you can't retract data once it has left the boundary.

## 6. External conformance suites
A public conformance suite (an RFC test vector set, a format's official suite) is a second referee, not a replacement for the old code.
- Keep it as its own test group, outside the golden directory, with its own pass count in acceptance.md.
- Where it conflicts with the old code, don't pick a side. First count how many real-corpus outputs the conflicting entries affect (command + count), then escalate per R6(b) with that number, a recommendation and a default. Why: "the spec says so" can still break every consumer that relies on the old behavior.

## 7. The referee after close-out
Once the old code is deleted, canonical truth = the frozen goldens + the decided differences in the attribution table.
- Before deleting the old code, seal a runnable referee: an image pinned by digest, with the fingerprint (checks §1) and a command that reproduces a sample of goldens byte-for-byte. Record the digest in acceptance.md.
- An intended change during maintenance takes its expected values from an upstream spec suite (§6) or an owner-signed spec, never from the new code's own output.
- To regenerate goldens for such a change, write the affected-input predicate first. Machine check: changed entries ⊆ entries matching the predicate; everything else byte-identical. Commit the regeneration on its own. Why: without the old code, an unbounded regeneration silently turns every new bug into the expected value.

## 8. Reviewing someone else's migration
Use this when asked to review a migration PR you didn't write.
- Stay read-only: don't push to their branch or edit their files; work in a separate checkout.
- Run the append-only check against the PR base: `git diff --diff-filter=MDR --name-only <PR base> -- tests/ golden/` is empty, or every entry maps to an R2 exception recorded in acceptance.md.
- For changed or added goldens, re-run those inputs on the old code (at the PR base) and compare. A mismatch means the expectation came from somewhere other than the referee.
- Recompute the R3 numbers (perf ratios, hotspot share, verdict.json) from the raw data in the PR; compare with the reported values.
- Output: a findings list (each with check · score · threshold · pass/fail · evidence file) and a verdict of approve or request changes.
