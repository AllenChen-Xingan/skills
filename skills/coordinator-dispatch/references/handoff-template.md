# Template: worker handoff page

The handoff page is the worker's "black box". When the session breaks, when there's a handover, when the human asks for status, this page is what everyone relies on. **One page per worker**; file name = window name.

How to write it:

- The top two items (Status, Progress) must be readable at a glance. The human may be listening with a screen reader: short sentences, status word first
- The log is append-only; `HH:MM` is enough for times
- Every pending decision needs options and a recommendation, or the coordinator can't ask them all at once

`scripts/new-batch.py` doesn't generate handoff pages (workers create their own). Copy the template below when needed.

<!-- template:start -->
# Handoff page · {{WORKER}} (batch {{BATCH_NAME}})

- **Status**: dispatched / checked in / in progress / blocked / wrapped up
- **Current task**: <one-sentence task>
- **Brief**: `{{BATCH}}/{{WORKER}}.md`
- **Progress** ({{DATE}}): <latest one or two sentences>
- **Next step**: <one sentence>

## Files changed
| File | What changed |
|---|---|

## Findings
- <surprises, pitfalls, anything that affects other lines>

## Pending decisions
1. **<question>**
   - A. <option>: cost <…> ← recommended
   - B. <option>: cost <…>

## Hand-offs (out of scope, left for the coordinator)
- <…>

## Log
- HH:MM <what was done> → <result>
<!-- template:end -->
