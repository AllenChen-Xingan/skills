# ai-translation · Framing units, triaging failures and capping attempts for AI translation

**Read this file in full** before an AI (you included) translates or bulk-edits code, and before you report a result in which you added any fallback, tolerance, skip or raised timeout to get green.

**Most often missed here**
- §1 Build the symbol closure and mapping table before translating; invented symbols are the largest failure class.
- §3 Write attempt caps before starting; over the cap, mark the unit unfinished and keep it in the denominator.
- §6 Disclose in your report every fallback or loosening you added yourself, register it as a transitional artifact, and bring the count to 0 at close-out.

Sections: §1 Frame the unit · §2 Failure triage · §3 Attempt caps and where failures go · §4 Translationese and options accepted but never wired up · §5 Bulk edits · §6 Disclose your own fallbacks

Rules: SKILL R1–R6; numbers: Default strictness table. This file: how an AI translates or bulk-edits code — framed units, failures triaged by which check failed, attempt caps set in advance; for non-Rust targets, swap in the target's own checklist.
Precondition: the checks meet SKILL R2 and were shown to fail (checks §6); keeping whichever draft passes a weak check amplifies its blind spots.

## 1. Frame the unit
Most of the gain comes from constraints set before generation, not repair after it, so spend effort on the frame. Write a task card per unit; don't send it until all six items are filled in:
1. **Which slice.** The smallest unit a check can localize; leaves first, in dependency order. Record the chosen granularity in `decisions.md`. Why: too fine a granularity forces translationese (SKILL R4).
2. **Symbol closure and mapping table.** From the unit's entry point, collect every symbol it uses directly or transitively (functions, types, constants, global state, macros, exception classes), including re-exports, header macros and inline functions, plus import-time side effects (module-level code, package init, static constructors). Map each one to exactly one of: *exists on the target* (real Rust path, looked up in build output or generated docs, not from memory) · *new* (in this unit or a prerequisite unit) · *not ported* (reason, logged as an intended difference in the contract, templates §2). Why: the largest class of failed translations assumes source functions, variables or import paths exist on the target; a gap in the closure gets invented. Machine check: closure count = mapping rows, and every *new* row is defined in this unit or an already-merged prerequisite.
3. **Signatures and shared types.** Pass the type-compatibility check, then freeze. Generate shared types once from a single source. Why: independent calls produce mutually incompatible definitions of the same struct.
4. **Construct-mapping rules.** A "source construct → Rust construct" table, e.g. exception or error code → which `Result` error variant, null or sentinel → `Option`. Draw it from the axes hit in py2rust or go-c-cpp. Why: without it the model translates literally into look-alike constructs.
5. **Banned patterns.** List them on the card and enforce with the guards in py2rust "Guards in general" (and go-c-cpp §4 for `unsafe`): unregistered `unwrap`/`expect`, `clone` added to satisfy the borrow checker, new `unsafe` blocks. Why: they turn the compile check green while pushing behavior differences or UB into runtime.
6. **Check commands and caps.** Which command counts as a pass, and the cap per attempt type (§3). Include an offline build with the lockfile unchanged. Why: it proves no dependency was added or bumped and that every API used exists — item 2 becomes a machine check.

The card asks for translation only. If old behavior looks wrong, note it and fix it as a separate step (review §2, SKILL R4).

## 2. Failure triage
Split by which check failed, not by how detailed the error is, so the executor can decide mechanically.

| Failed check | Default | Why |
|---|---|---|
| Compile, type, borrow, lint error | Feed the error and the current fragment back; repair locally with signatures frozen; re-run the §1 item 5 guards on the repair | Errors point at lines, so local repair converges; non-local repair ripples into other fragments and loops; borrow errors are most often "fixed" with `clone`, `unsafe` or a signature change, which swaps in a harder bug |
| Warnings (lint, deprecation, build) | Rule on each one; don't blanket-suppress or blindly change (delivery §3) | What is redundant on one platform may be required on another |
| Behavior check (tests, differential testing, fuzz) | Discard the draft and resample; the counterexample (input · expected · actual) may go in the new prompt, the failed draft does not | At equal budget, resampling beats patching the failed draft; the gain comes from draft diversity |
| The check itself is wrong (noise, environment, check bug) | Not an AI failure; the owner fixes the check (SKILL R6) | Letting the AI edit the check lets the test-taker rewrite the exam |

- Borrow errors that keep failing usually mean shared mutable structure (object graphs, callbacks mutating outer state, pointers passed everywhere) has no direct Rust equivalent: stop repairing, re-decide data ownership on the card, resample.
- Exception: if a behavior counterexample is narrowed to a few lines with a certain fix, edit directly; it counts as one behavior attempt and must pass the full check set. Why: resampling a located bug wastes budget and can add new differences.
- The equal-budget evidence for "resample first" comes from small units (functions, extracts of a few hundred lines). For file-sized units, run both strategies on a few sample units at the same budget and record the choice in `decisions.md`.
- Stamp every draft, one JSONL line each (`unit, check(compile|lint|behavior), attempt, pass, fail`):
  `jq -s 'group_by(.check) | map({check: .[0].check, stuck: map(select(.pass==false)) | length})' attempts.jsonl`

## 3. Attempt caps and where failures go
- **Write caps before starting, one per attempt type** (re-ask, compile repair, behavior resample). Don't copy numbers from another project: raise the count on sample units until more attempts rarely help; that is the cap. Don't raise it mid-run. Why: a cap raised while running is no cap.
- **Over the cap → mark unfinished and escalate to the owner.** It stays in the fixed denominator (checks §11); the check is not loosened, no case is skipped, a timeout is not a pass. Pick the destination in advance:

  | Condition | Destination | How it is counted |
  |---|---|---|
  | Signature already type-checked | Route to the old implementation through the seam (cutover) | Failure, even though the seam keeps it working |
  | Large unit, or failure already located | Keep the draft and failure report for a human to continue | Unfinished; stays in the denominator |
  | Line-level mechanical edit, where unpredictable reruns cost more than a hand edit | Discard for a human rewrite | Unfinished; stays in the denominator |

- **Batch stuck on the same step → fix the framing, not the output.** Filter the stuck group by stamp, sample enough units to cover its distinct failure shapes, tune the symbol map, construct map, banned list, prompt or script, confirm improvement on the sample, then re-run all remaining units. Why: a batch stuck on one step means the frame is wrong; hand-patching each unit never ends. The long tail still failing after several sweeps goes to a human.

## 4. Translationese and options accepted but never wired up
After a draft passes its checks and before merge (and in code review), review these five separately. Why: differential tests see only behavior and idiom review sees only local style; both assume the structure is right.
1. **Source runtime architecture copied over** — mirrored package tree; workarounds for source-runtime limits (multiprocessing around the GIL, goroutine-per-request fan-in over channels, hand-rolled C memory pools and task queues). List every concurrency, process, cache, queue and registry construct; ask "what observable behavior breaks if Rust drops it?" No answer → redesign idiomatically as a separate step; the checks still apply.
2. **Checks only the source language needed** — null checks the type system rules out, runtime type dispatch, double-free flags. Before deleting, confirm it carries no observable behavior (error type, message, ordering). Why: some of these are part of the contract.
3. **Option accepted but not wired up, silently falling back to the default** — e.g. a rewritten CLI that accepts a reference-time-file option without error, then prints the current time. Feature-list tests prove only that the option exists. Diff-test every old option, argument and config key at least once; red if new output with and without the option is identical while old output differs. Unused-field warnings are a first filter, not a verdict.
   `for opt in $(cat options.txt); do [ "$(new $opt $ARGS)" = "$(new $ARGS)" ] && [ "$(old $opt $ARGS)" != "$(old $ARGS)" ] && echo "RED $opt"; done`
4. **Editing tests to go green** — the AI does not touch check files (SKILL R2). Why: a weakened check stays green with no signal; a plain-text replacement meant for one assertion once also loosened an identical guard from "called exactly once" to "called".
   `git diff --name-only "$BASE" | grep -E "$CHECK_PATHS_RE" && { echo "AI edited a check; rejected"; exit 1; }`
5. **Rust written to please the compiler** — `unwrap`/`expect` turning errors into panics (py2rust §4); `clone` or `Rc<RefCell>` silently turning "shared" into "separate copies"; `unsafe` copying source pointer aliasing or type punning (go-c-cpp §3); source integer widths and casts (py2rust §1). Fix each, or justify it inline and add it to the no-backflow exemption list. Why: the compiler proves legality, not sameness, and these are the shortcuts taken under borrow-error pressure.

## 5. Bulk edits
For one mechanical transform across many call sites, including dependency or toolchain upgrades.
- **Encode the transform once as a generator.** Learn it on a few sites, write it as a rewrite script, and on conflict rerun the script instead of merging by hand. Worth it when call sites × per-site cost exceeds the cost of building the tool.
- **Only mechanical transforms go in bulk.** Changes that need per-site redesign (SKILL R4) are framed one unit at a time per §1.
- **Edit structured code with syntax-aware tools or exact, position-anchored replacements, never cross-line regex** — business code as much as tests. Why: a multi-line regex over nested calls once truncated mid-expression and left unbalanced brackets across files. Afterwards compare expected vs actual edit count in the diff; any mismatch → roll back the whole batch.
- **The generator's call-site list is the batch's fixed denominator.** Failures go through §2 and §3; none are dropped from the list.
- **Bulk output gets normal code review**, focused on §4 and on reviewer-chosen inputs derived from the old source (review §3), not just spot checks of outliers.

## 6. Disclose your own fallbacks
- Any fallback or loosening you add to get a check green — `try/except` falling back to the old path, widened tolerance, skipped or `xfail` case, raised timeout — is disclosed in the final report and registered as a transitional artifact (SKILL R5). Why: an undisclosed fallback makes the check report a pass the new code never earned.
- At close-out the self-added fallback count is 0 (SKILL R2); report it as check name · score · threshold · pass/fail · evidence file.
- When a behavior check fails, discard and redo per §2; don't patch around it.
