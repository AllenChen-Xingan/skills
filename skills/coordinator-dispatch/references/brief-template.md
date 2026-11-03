# Template: brief for one worker

Every brief answers four things: **who you are · what the job is · what to read first · who to report to when done**. Leave one out and the worker guesses, and its guess is usually the average case.

`scripts/new-batch.py` copies the content between the two markers below into `<batch>/<window>.md` and fills in the `{{…}}` placeholders. After generating it, fill in each section and delete lines that don't apply.

## How to fill it in

- **Intent**: paste the human's own words verbatim into the quote block. Don't expand, rewrite or fix typos. Put your interpretation in a separate "i.e.: …" paragraph so the worker can tell what the human said from what you said.
- **Your job**: numbered steps; each says what "done" looks like. For any step with an outside dependency (something from the human, the slot), say how to ask for it.
- **Files you may write**: an allowlist. Several workers writing the same file is the number-one cause of parallel conflicts.
- **Red lines**: only the ones specific to this line (e.g. "never put this value in any message"). Shared red lines live in the common rules; don't repeat them.
- **Deliverables**: file path + one-line acceptance criterion. The last item is always the handoff page.

## Template

<!-- template:start -->
# Brief · worker {{WORKER}}: <one sentence describing this line>

You are worker session `{{WORKER}}`. The coordinator is session `{{BOSS}}`. First read `{{BATCH}}/common.md` and follow it. When you're done reading, check in with the coordinator using inter-session messaging (one sentence: "{{WORKER}} checked in, read the brief, starting <first step>").

## Intent (human's words, verbatim)
> <paste the human's words>

i.e.: <one or two sentences of your interpretation; if ambiguous, write "Ambiguity: …, going with A for now, added to pending decisions">

## Read first
1. The parts of the project onboarding doc (e.g. `CLAUDE.md`) relevant to this job
2. <files this line must read · path:line>
3. <reference material; for large files write "grep by keyword, don't read the whole thing">

## Your job
1. <step 1: what done looks like>
2. <step 2: needs the slot? write "request the slot first">
3. <step 3: needs something from the human? write "ask the coordinator for: <what>, once per item">
4. Self-review: one pass from several opposing perspectives; fix what they find before handing in

## Files you may write
- <path 1>
- {{HANDOFF_DIR}}/{{WORKER}}.md (handoff page)

## Red lines (specific to this line)
- <e.g. a value must never appear in messages, handoff pages, logs or echoed commands; report only "written, N characters">
- After 2–3 failed attempts, stop and report to the coordinator. Don't keep forcing it.

## Deliverables
- <file path>: <one-line acceptance criterion>
- {{HANDOFF_DIR}}/{{WORKER}}.md: says "wrapped up", which files changed, and any pending decisions
- When everything is done, tell the coordinator "{{WORKER}} ready to wrap" + deliverable paths
<!-- template:end -->
