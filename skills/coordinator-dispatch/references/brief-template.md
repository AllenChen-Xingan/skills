# Brief template for a single worker

A brief must answer four things: **who you are · what the job is · what to read first · who to report to when done**. Leave one out and the worker will guess, and the guess tends to be the average case.

`scripts/new-batch.py` copies the content between the two markers below into `<batch>/<window>.md` and substitutes the `{{…}}` placeholders. After generating, fill in each section and delete lines that don't apply.

## Filling it in

- **Intent**: paste the human's exact words into the quote block -- don't expand, rewrite or fix typos. Write your own reading of them in a separate paragraph starting "I.e.: ...", so the worker can tell which sentences are the human's and which are yours.
- **Your job**: numbered steps; for each step say "what done looks like". For a step with external dependencies (something from a human, the slot), say how to ask for it.
- **Files you may write**: an allowlist. Several workers writing the same file is the number one source of parallel conflicts.
- **Hard rules**: the ones specific to this workstream (e.g. "this value never goes into any message"). Shared hard rules live in the common rules; don't repeat them.
- **Deliverables**: file paths + a one-line acceptance criterion; the last item is always the handoff page.

## Template

<!-- template:start -->
# Brief · worker {{WORKER}}: <one sentence describing this workstream>

You are worker session `{{WORKER}}`. The coordinator is session `{{BOSS}}`. First read `{{BATCH}}/common.md` and follow it; when done, check in with the coordinator via an inter-session message (one line: "{{WORKER}} checked in: read the brief and common rules; first step <what>; slot needed <yes/no>; needs from a human <yes/no>").

## Intent (the human's exact words, kept verbatim)
> <paste the human's exact words>

I.e.: <your one- or two-sentence reading of the words; if ambiguous, write "Ambiguity: ..., going with A for now, added to the pending decisions">

## Your branch
- worktree: `<repo>.worktrees/{{WORKER}}` (work only here)
- branch: `w/{{WORKER}}`, base branch `<origin/main>`; git rules are in the "Git" section of the project's `AGENTS.md`

## Read first
1. The parts of the project handbook (`AGENTS.md` / `CLAUDE.md`) relevant to this job, especially the "Git" section
2. <files this workstream must read · path:line>
3. <reference material; for large files write "grep by keyword, don't read the whole thing">

## Your job
1. <step 1 -- what done looks like>
2. <step 2 -- needs the slot? write "request the slot first">
3. <step 3 -- needs something from a human? write "ask the coordinator for: <what>, ask for each thing only once">
4. Self-review: one round from several opposing perspectives; fix what they find before handing in

## Write only these files
- <path 1>
- {{HANDOFF_DIR}}/{{WORKER}}.md (handoff page)

## Hard rules (specific to this workstream)
- <e.g. a certain value never goes into messages, the handoff page, logs or command-line echo; report only "written, N characters">
- After 2-3 failures, stop and report to the coordinator; don't keep forcing it

## Deliverables
- <file path> -- <one-line acceptance criterion>
- {{HANDOFF_DIR}}/{{WORKER}}.md -- says "wrapped up", which files changed, items that need a human decision (if any)
- Branch `w/{{WORKER}}` rebased onto the latest base branch and pushed; if the project uses PRs, include the draft PR link
- When everything is done, report "{{WORKER}} ready to wrap up, branch w/{{WORKER}}, PR <link|none>" to the coordinator, with the deliverable paths
<!-- template:end -->
