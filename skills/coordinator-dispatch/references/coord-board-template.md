# Board (coordinator's dashboard) template

The board is the **only** record of dispatched work: every worker dispatched or collected, every slot handed out, every finding received gets updated here. Location follows project convention (if there is none, ask the human; it usually goes in the project's state directory).

## Contents
1. Header · 2. Workers · 3. Rules · 4. Slots · 5. Progress board · 6. Findings · 7. Pending decisions

## How to write each section

- **Header**: coordinator session name, tmux workspace name (update here after a handover), one line on where the method comes from
- **Workers**: keep rows of wrapped-up workers (they are history), newest on top; the status column uses fixed words: dispatched / checked in / in progress / blocked / ready to wrap up / done, wrapped up (window closed); the type column says `claude` or `pi`; the cost column says "spent / cap" for pi workers (from `SPEND` events or `pi-worker status`) and "—" for Claude Code workers
- **Rules**: only the rules the project sets for workers, or a pointer to the common rules template; mark rules the human changed with "human decided <date>"
- **Slots**: current holder + queue; when empty write "empty" -- don't delete the table; when a pi worker holds it write `pi:<name>`
- **Merge queue**: workstreams that passed acceptance review and are waiting to merge, in order; after each merge record the merge commit and tell the other running workers to rebase (`git-workflow.md` section 3)
- **Progress board**: for the human; format in section 5 below
- **Findings**: facts workers reported along the way, with date and source window
- **Pending decisions**: things that need a human decision collect here so the human sees them all at once; once decided, tick the item and give the path where the decision was recorded; keep the question text on file

## Section 5 · Progress board format

When the human asks "how's it going?", answer in this format (and write it on the board too). Rules: **one line per worker · status word first · fits on one screen · no logs pasted**. If the human uses a screen reader, don't nest tables and don't replace words with fancy symbols.

```
Progress (HH:MM)
- in progress · <window>: <where it is, one line>; next <one line>
- blocked · <window>: <where it's stuck>, needs you to <do what>
- ready to wrap up · <window>: waiting for my acceptance review
- cost: pi workers total $<x> (<name> $<a>/$<cap>…)
- slot: <holder or empty>; queue <N>
- waiting on you: <N> items (see pending decisions)
```

When a long background task starts (build, test run, batch job), write a progress file right away and put its path on the board; on completion, a short sound (e.g. macOS `afplay /System/Library/Sounds/Glass.aiff`) can replace a long spoken announcement -- provided the human accepts this kind of alert; ask first.

## Template

<!-- template:start -->
# Coordinator board

> Only the coordinator talks to the human. Workers report finishing, being blocked, or needing the slot only to the coordinator.
> Coordinator session name: `{{BOSS}}` (update here after a handover). tmux workspace: `<ws>`.

## Workers

| Window | Type | Task | Branch / PR | Brief | Handoff page | Cost | Status |
|---|---|---|---|---|---|---|---|

## Rules

- See the "Dispatch" section of the project handbook; this board records only items the human changed later (marked "human decided <date>")

## Slots

| Slot | Current holder |
|---|---|
| Heavy build / full test run (1) | empty |

Queue: (empty)

## Merge queue (merge one at a time; after each merge tell the other workers to rebase)

- (empty)

Pop-up / long foreground runs awaiting the human's permission: (empty)

## Progress board

Progress (HH:MM)
- (no workers yet)

## Findings

- <date> · <window>: <one line>

## Pending decisions (collected for the human to review in one go)

- [ ] <question> -- source <window handoff page path:section>
<!-- template:end -->
