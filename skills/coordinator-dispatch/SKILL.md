---
name: coordinator-dispatch
description: Runs "one coordinator + N workers" multi-session collaboration in Claude Code. Split a job into parallel lines, write brief files, start Claude Code workers in tmux windows and feed them their first message, hand out and reclaim the heavy-job slot, track progress with a ledger and per-worker handoff pages, then review the work and close the windows. Use when the user says "dispatch", "spin up workers", "send a worker to do this", "you're the coordinator", "run a few sessions in parallel", "how's it going?", "wrap up / close the windows", or when a job splits into 2+ lines that touch different files and each take 30+ minutes. Do not use for a single line of work or anything that takes ~15 minutes; in-session subagents (the Agent tool) are enough. Not for pure code review or git merge strategy.
---

# Coordinator dispatch (coordinator-dispatch)

One main session acts as the **coordinator**. It only splits the work, dispatches it, hands out slots, collects results, reviews them, and talks to the human. Claude Code **workers** running in tmux windows do the actual work. The pattern comes from the "1 coordinator + N workers" approach described publicly by Yang Zhiping (阳志平).

Three principles that always hold:

1. **The human has one point of contact.** Only the coordinator talks to the human. Anything a worker needs to ask or get from the human goes through the coordinator.
2. **Handoffs are files.** Briefs, common rules, first messages, handoff pages and the ledger are all written to disk. Conversations break; files don't.
3. **The coordinator owns slots and ordering.** It decides who goes first, who may hold heavy resources (full builds, runs that grab the foreground), and when each line wraps up.

## When to use it / when not to

| Situation | Route |
|---|---|
| 2+ lines, no shared files, each ≥ 30 min | This skill: tmux workers |
| One line, or done in ~15 minutes | In-session subagent (Agent tool), no windows |
| Several lines must edit the same files | Run them in sequence, or give each line its own git worktree (the coordinator creates worktrees; workers don't nest them) |
| Just asking "how's it going?" | Jump to step 5, "Progress board" |

## Read the project's own conventions first (don't guess from this skill)

Before starting, check whether the project already defines these. If it does, **the project wins**; this skill only fills gaps:

- Rules on dispatching, slots, git and pop-up windows in the project's `CLAUDE.md` (or similar onboarding doc)
- Where the ledger lives (commonly `state/coord.md` or `docs/coord.md`; if none exists, create one from `references/coord-board-template.md` and ask the human where, or use the project's state directory)
- The handoff-page directory (commonly `state/handoff/`) and batch directory (commonly `_tmp/<date>-<batch>/`)
- The tmux workspace (session) name: project convention > name the human gave > ask the human about existing sessions. **Don't invent one and then forget it.**

Placeholders used below: workspace `<ws>`, coordinator session name `<boss>`, batch directory `<batch>`, handoff-page directory `<handoff-dir>`, ledger `<board>`.

## Roles

| Role | Who | Does | Does not |
|---|---|---|---|
| Coordinator | The main session the human is talking to | Splits work, writes briefs, starts workers, hands out slots, collects reports, spot-checks, does git writes, talks to the human | Do the work it dispatched |
| Worker | Claude Code in one window of `<ws>` | Works from its brief, keeps its handoff page current, reports, requests slots | Talk to the human, do git writes, touch other workers' files |
| Reviewer (optional) | A model from another vendor / a multi-perspective workflow | Finds problems | Edit files (cross-model review is its own skill) |

## Seven steps

1. **Check resources.** Check free disk space (`df -h .`; each worktree is a full copy), who holds the slot (read `<board>`), and which windows already exist in `<ws>` (`scripts/list-workers.sh <ws>`). If a window with the same name exists, rename the new one or wrap up the old one first.
2. **Write the briefs.** Run `scripts/new-batch.py <batch> --boss <boss> --workers a,b,c` to generate the skeleton (common rules + one brief and one first message per worker; existing files are never overwritten), then fill in each file.
   - Every brief answers four things: **who you are · what the job is · what to read first · who to report to when done**. Template: `references/brief-template.md`
   - One set of common rules per batch: `references/common-rules-template.md`
   - Paste the human's own words into the "Intent" section **verbatim**. Don't expand or rewrite them.
3. **Start the workers.** `scripts/spawn-worker.sh <ws> <window> <workdir> <batch>/msg-<window>.txt`. The first message is a single sentence ("read your brief and follow it; check in with the coordinator when done reading"). **Write it to a file first, then feed it**; never inline it in a command line. The script waits for Claude Code to be ready, pastes, presses Enter and prints the end of the pane. If the window never becomes ready, it exits with an error instead of pressing keys blindly.
4. **Record it and wait for check-in.** Add a row to the worker table in `<board>` (window · task · brief · handoff page · status = dispatched). Change it to "checked in" when the worker reports in. If ~5 minutes pass with no check-in, look at the end of its pane with `list-workers.sh`. It's usually stuck on a trust-folder or permission prompt. Tell the human to click it; don't click it for them.
5. **Slots and reports.** Message formats for requesting, queueing and returning the slot are in section 3 of `references/worker-protocol.md`. Update the worker table and "Progress board" in `<board>` as soon as each report arrives. When the human asks how it's going, first run `list-workers.sh <ws> --handoff-dir <handoff-dir>` for the machine-side state, then answer in the progress-board format (section 5 of `references/coord-board-template.md`): **one line per worker, status first, no more than one screen**.
6. **Review.** When a worker reports "ready to wrap", spot-check it with `references/wrap-up-checklist.md`: do the deliverables exist, were the self-tests really run, were any red lines crossed, are the open decisions collected in the pending list? If it fails, send the worker one message listing the specific gaps. Don't fix them yourself.
7. **Wrap up.** The worker's handoff page says "wrapped up" → `scripts/close-worker.sh <ws> <window>` (prints the end of the pane and asks for confirmation) → mark the ledger row "done, wrapped (window closed)" → the coordinator does git writes following the project's process → tell the human in one sentence, with paths.

## Scripts (all support `--help`; quote paths that contain spaces)

| Script | Purpose | Key arguments |
|---|---|---|
| `scripts/new-batch.py` | Generate the brief skeleton for a batch | `<batch-dir> --boss --workers [--handoff-dir] [--board] [--date] [--path-prefix] [--dry-run]` |
| `scripts/spawn-worker.sh` | Open a window, start Claude Code, wait until ready, feed the first message | `<ws> <window> <workdir> <msg-file> [--cmd] [--ready-pattern] [--timeout] [--tail] [--dry-run]` |
| `scripts/list-workers.sh` | List windows + the end of each pane + "Progress" from each handoff page | `<ws> [--lines N] [--handoff-dir D] [--window W]` |
| `scripts/close-worker.sh` | Print the end of the pane, then close the window after confirmation | `<ws> <window> [--yes] [--tail N]` |

`--cmd` defaults to `claude`. To choose a model or permission mode, pass the full command (e.g. `--cmd "claude --model opus"`) or set the `CD_CLAUDE_CMD` environment variable. `--cmd` is interpreted by the shell, so quote any paths inside it yourself.

## References (read as needed, not all at once)

| File | When to read |
|---|---|
| `references/brief-template.md` | Writing one worker's brief |
| `references/common-rules-template.md` | Writing a batch's common rules |
| `references/worker-protocol.md` | The full worker-side protocol; you can also hand it to workers directly (check-in · reports · slots · handoff page · wrap-up) |
| `references/handoff-template.md` | The shape of a worker's handoff page |
| `references/coord-board-template.md` | Creating or tidying the ledger / progress board |
| `references/wrap-up-checklist.md` | Review and wrap-up |
| `references/failure-matrix.md` | When something goes wrong (window didn't start, worker went silent, slot is stuck, human closed a window…) |

## Common mistakes

- **The coordinator does the work itself.** Leave dispatched work alone. If you're tempted, that's a sign you need another worker or a subagent.
- **Inlining the first message in `tmux send-keys "…"`.** Quotes, `$` and newlines all break, and the shell executes the text. Always go file → `load-buffer` → `paste-buffer`.
- **Not updating the ledger.** Every dispatch, wrap-up and slot handoff changes the ledger. Otherwise, when the human asks for status, you're stuck digging through windows.
- **Deciding for the human.** Collect the workers' open decisions in the ledger's pending list and show them to the human in one go. Don't interrupt them one at a time, and don't choose for them.
- **Closing a window before confirming the work is on disk.** "Window closed" doesn't mean "work saved". Check the handoff page and deliverables first, then close.
