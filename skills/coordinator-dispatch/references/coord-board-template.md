# Template: ledger (coordinator board)

The ledger is the **only** record of dispatch. Every dispatch, wrap-up, slot handoff and finding gets written here. Its location follows the project's convention (if there is none, ask the human; a common choice is the project's state directory).

## Contents
1. Header · 2. Worker table · 3. Rules · 4. Slots · 5. Progress board · 6. Findings · 7. Pending decisions

## How to write each section

- **Header**: coordinator session name, tmux workspace name (update after a handover), one line on where the method comes from
- **Worker table**: keep wrapped-up rows (they're the history), newest at the top. The status column uses fixed words: dispatched / checked in / in progress / blocked / ready to wrap / done, wrapped (window closed)
- **Rules**: only rules the project set for workers, or a pointer to the common-rules template. Mark rules the human changed with "set by human <date>"
- **Slots**: current holder + queue. If empty, write "free". Don't delete the table
- **Progress board**: for the human; format in section 5
- **Findings**: facts workers reported mid-run, with date and source window
- **Pending decisions**: collect decisions for the human here and show them all at once. Once decided, check the box and give the path where the decision is recorded. Keep the questions as a record

## Section 5 · Progress board format

Answer "how's it going?" in this format (and write it into the ledger too). Rules: **one line per worker · status word first · fits on one screen · no logs**. If the human uses a screen reader, don't nest tables or use decorative symbols in place of words.

```
Progress (HH:MM)
- In progress · <window>: <where it is, one sentence>; next <one sentence>
- Blocked · <window>: <where it's stuck>, needs you to <do what>
- Ready to wrap · <window>: waiting for my review
- Slot: <holder or free>; queue <N>
- Waiting on you: <N> decisions (see pending list)
```

When a long background job starts (build, tests, batch processing), write a progress file right away and put its path in the ledger. When it finishes, a short sound (e.g. macOS `afplay /System/Library/Sounds/Glass.aiff`) can replace a long spoken status, but only if the human is fine with that kind of alert. Ask first.

## Template

<!-- template:start -->
# Coordinator board

> Only the coordinator talks to the human. Workers report finishing, getting blocked or needing the slot to the coordinator only.
> Coordinator session: `{{BOSS}}` (update here after a handover). tmux workspace: `<ws>`.

## Workers

| Window | Task | Brief | Handoff page | Status |
|---|---|---|---|---|

## Rules

- See the "dispatch" section of the project onboarding doc. This ledger only records rules the human changed later (marked "set by human <date>")

## Slots

| Slot | Current holder |
|---|---|
| Heavy build / full test run (1) | free |

Queue: (empty)

Pop-ups / long foreground runs awaiting the human's OK: (none)

## Progress board

Progress (HH:MM)
- (no workers yet)

## Findings

- <date> · <window>: <one sentence>

## Pending decisions (collected for the human to review at once)

- [ ] <question>: source <window handoff page path:section>
<!-- template:end -->
