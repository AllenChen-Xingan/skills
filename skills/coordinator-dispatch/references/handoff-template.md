# Worker handoff page template

The handoff page is the worker's "black box": when the session dies, a worker is replaced, or the human asks about progress, this is what everyone relies on. **One page per worker**; file name = window name.

Writing tips:

- The top two fields (Status, Where I am) must be readable at a glance -- the human may be listening with a screen reader, so use short sentences with the status word first
- The log is append-only, never rewritten; `HH:MM` is enough for times
- Every item under "Needs a human decision" needs options and a recommendation, otherwise the coordinator can't ask them all in one go

`scripts/new-batch.py` does not generate handoff pages (workers create their own); copy the template below when needed.

<!-- template:start -->
# Handoff page · {{WORKER}} (batch {{BATCH_NAME}})

- **Status**: dispatched / checked in / in progress / blocked / wrapped up
- **Working on**: <one-line task>
- **Brief**: `{{BATCH}}/{{WORKER}}.md`
- **Where I am** ({{DATE}}): <latest one or two sentences>
- **Next**: <one line>

## Files changed
| File | What changed |
|---|---|

## Findings
- <surprises, pitfalls, things that affect other workstreams>

## Needs a human decision
1. **<question>**
   - A. <option> -- cost: <…> <- recommended
   - B. <option> -- cost: <…>

## Hand-offs (out of scope, left for the coordinator)
- <…>

## Log
- HH:MM <what I did> -> <result>
<!-- template:end -->
