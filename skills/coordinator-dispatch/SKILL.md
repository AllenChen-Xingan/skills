---
name: coordinator-dispatch
description: "Multi-session collaboration with 1 coordinator + N workers: split a job into parallel workstreams, write briefs, start Claude Code workers in tmux windows or pi workers in the background (cheap model writes code, events stream live to the coordinator), hand out and take back heavy-work slots, cap each worker's cost, run cheap-first review, track progress with a board and handoff pages, and wrap up after acceptance review. Use when the user says \"dispatch\", \"start a worker\", \"send a worker to do it\", \"let pi write it\", \"use a cheap model to write code\", \"you are the coordinator\", \"run a few sessions in parallel\", \"how is it going\", \"wrap up / close the windows\", or when a job splits into 2 or more workstreams that do not touch the same files and each take over half an hour. Not for a single workstream you will not hand to a cheap model, or a job done in ten-odd minutes: an in-session subagent (Agent tool) is enough. Not for pure code review or git merge strategy."
---

# Coordinator dispatch (coordinator-dispatch)

One main session acts as the **coordinator**: it only splits work, dispatches it, hands out slots, manages cost, collects results, does acceptance review, and talks to the human. The real work is done by **workers**, of two kinds: Claude Code workers in tmux windows, and pi workers in the background (a cheap model, see `references/pi-worker.md`). The pattern comes from the "1 coordinator + N workers" approach described publicly by Yang Zhiping.

Five principles (they always hold):

1. **The human faces a single entry point**: only the coordinator talks to the human. Anything a worker needs to ask the human, or needs from the human, goes through the coordinator.
2. **Handoffs are written as files**: briefs, common rules, first messages, handoff pages and the board all live on disk. Conversations break; files do not.
3. **Slots, order, cost and merging belong to the coordinator**: the coordinator decides who goes first, who may use heavy resources (full builds, runs that grab the foreground), how much each worker may spend, who merges into the main branch first, and when to wrap up.
4. **One worker = one worktree = one branch**: workers commit, push and open PRs on their own branch; merging, deleting branches and releasing belong only to the coordinator. The source of truth is `references/git-workflow.md`.
5. **Cheap-first review**: keep small changes simple; for changes to core logic, run one review round with a cheap model first, fix, then have an expensive model (the coordinator, or a cross-model review) do the final review.

## When to use / not use

| Situation | Which path |
|---|---|
| 2 or more workstreams, not touching the same files, each at least half an hour | This skill: tmux workers |
| A coding workstream with a clear brief and machine-checkable acceptance (even just one), and you want to save quota | This skill: pi worker, read `references/pi-worker.md` |
| One workstream, or done in ten-odd minutes | In-session subagent (the Agent tool), no window |
| Several workstreams need to change the same files | Serialize first; when parallel, one worktree per workstream (`scripts/git/worktree.sh new`, opened by the coordinator, no nesting), and the workstream merged later resolves conflicts with its own rebase |
| Just asking "how is it going" | Jump straight to step 5, "progress board" |

## Read the project's own conventions first (do not guess from this skill)

Before starting, check whether the project has the following; if it does, **the project wins**, and this skill only fills gaps:

- Clauses about dispatching, slots, git and dialogs in the project's `AGENTS.md` / `CLAUDE.md` (or a similar onboarding manual). **If `AGENTS.md` has no "Git" section, add one from `references/agents-md-template.md` first**, and add a line `@AGENTS.md` to `CLAUDE.md` (section 5 of `git-workflow.md`)
- Where the board file lives (commonly `state/coord.md`, `docs/coord.md`; if none, create one from `references/coord-board-template.md`, asking the human for the location or using the project's state directory)
- The handoff page directory (commonly `state/handoff/`) and batch directory (commonly `_tmp/<date>-<batch>/`)
- The tmux workspace (session) name: project convention > what the human specifies > ask the human from the existing sessions; **do not invent one and then forget it**

Placeholders used below: workspace `<ws>`, coordinator session name `<boss>`, batch directory `<batch>`, handoff page directory `<handoff-dir>`, board `<board>`.

## Roles

| Role | Who | Does | Does not |
|---|---|---|---|
| Coordinator | The main session the human is talking to | Splits work, writes briefs, opens worktrees and branches, starts workers, hands out slots, collects reports, spot-checks, merges into the main branch, deletes branches, releases, talks to the human | Does not do the work it has handed out |
| Worker | Claude Code in a window of `<ws>`, in its own worktree | Works from the brief, commits, pushes and opens PRs on its own branch, maintains its handoff page, reports, requests slots | Does not talk to the human, does not merge, does not touch the main branch or other workers' branches or files (enforced by the git guard hook) |
| pi worker | A background pi process (cheap model), one worktree per workstream | Writes code from the brief, commits, pushes and opens PRs on its own branch, reports with `report_to_claude`, asks with `ask_claude`; slots, git rules and the cost cap are enforced by the extension | Does not coordinate, does not dispatch further work, does not merge |
| Reviewer (optional) | A model from another vendor / a multi-perspective workflow | Finds faults | Does not change files (cross-model review has its own skill) |

## Seven-step flow

1. **Check resources**: how much is left (`df -h .`; each worktree takes a full copy of the space), who holds the slots (read `<board>`), which windows already exist in `<ws>` (`scripts/list-workers.sh <ws>`). If a window with the same name already exists, pick another name or wrap up the old one first.
2. **Write briefs**: first generate the skeleton with `scripts/new-batch.py <batch> --boss <boss> --workers a,b,c` (common rules + a brief per worker + a first message per worker; existing files are never overwritten), then fill in each one.
   - A brief must answer four things: **who you are · what the work is · what to read first · whom to report to when done**. Template: `references/brief-template.md`
   - One set of common rules per batch: `references/common-rules-template.md`
   - The human's own words go in the "Intent" section **verbatim**, not expanded or rewritten
3. **Start workers**: first open a workstream with `scripts/git/worktree.sh new <repo> <name>` (giving `<repo>.worktrees/<name>`, branch `w/<name>`), and record the branch name on the board. For a pi worker, use `scripts/pi-worker start` plus Monitor on `pi-worker watch` instead; how steps 3-7 work for it is in section 3 of `references/pi-worker.md`. Claude Code worker: `scripts/spawn-worker.sh <ws> <window> <workdir> <batch>/msg-<window>.txt`. Use that worktree as the working directory; the script attaches the git guard hook automatically. The first message is a single sentence, "Read the brief and follow it; check in with the coordinator once you have read it". **Write it to a file first, then feed it in**; never splice it into a command line. The script waits for Claude Code to be ready, pastes, presses Enter and prints the pane tail; if it is not ready it exits with an error rather than pressing keys blindly.
4. **Update the board + wait for check-in**: add a row to the worker table in `<board>` (window · task · brief · handoff page · status=dispatched). Once the worker checks in, change it to "checked in". If there is no check-in after about 5 minutes, look at the pane tail with `list-workers.sh`; usually it is stuck on a trust-directory / permission confirmation dialog. Tell the human to click it; do not click it for them.
5. **Slots and reports**: the slot message format, queueing and returns are in section 3 of `references/worker-protocol.md`. On every report, update the worker table and the "progress board" in `<board>` right away. When the human asks for progress, first get the machine-side status with `list-workers.sh <ws> --handoff-dir <handoff-dir>`, then answer in the progress board format (section 5 of `references/coord-board-template.md`): **one line per worker, status first, no more than one screen**.
6. **Acceptance review**: after a worker reports "ready to wrap up", changes to core logic first get a cheap review round (for pi workers, `pi-worker review`), then spot-check against `references/wrap-up-checklist.md`: are the deliverables there, were the self-tests really run, were any hard rules broken, have the things that need a human decision been added to the pending-decisions list. If it does not pass, write the specific gaps as one message back to the worker (send back); do not fill them in yourself.
7. **Wrap up**: the worker's handoff page says "wrapped up" -> `scripts/close-worker.sh <ws> <window>` (prints the pane tail first, asks for confirmation) -> merge: one at a time, following steps 8-9 of section 2 of `references/git-workflow.md` (merge, `worktree.sh clean`), then tell the other running workers to rebase -> set the board to "done, wrapped up (window closed)" and record the merge commit -> report to the human in one sentence + the path.

## Scripts (all support `--help`; quote paths with spaces)

| Script | Purpose | Key parameters |
|---|---|---|
| `scripts/new-batch.py` | Generate the brief skeleton for a batch | `<batch-dir> --boss --workers [--handoff-dir] [--board] [--date] [--path-prefix] [--dry-run]` |
| `scripts/spawn-worker.sh` | Open a window, start Claude Code, wait until ready, feed the first message | `<ws> <window> <workdir> <msg-file> [--cmd] [--ready-pattern] [--timeout] [--tail] [--dry-run]` |
| `scripts/list-workers.sh` | List windows + each window's pane tail + the handoff page's "Where I am" | `<ws> [--lines N] [--handoff-dir D] [--window W]` |
| `scripts/close-worker.sh` | Print the pane tail, close the window after confirmation | `<ws> <window> [--yes] [--tail N]` |
| `scripts/git/worktree.sh` | Open / clean a workstream: one worktree and one branch per worker; shared by both kinds of worker | `base <repo>` · `new <repo> <name> [--base B] [--branch BR]` · `clean <repo> <name> [--delete-remote] [--force]` |
| `scripts/pi-worker` | Every operation on pi workers: start · watch · grant/deny · answer · steer/follow · budget · review · status · stop · list | `start <name> (--repo R [--base B] \| --cwd D) --task-file F [--budget USD] [--model M] [--heavy-re RE] [--readonly]` · `clean <name> [--delete-remote]`; the rest are in `--help` |

`--cmd` defaults to `claude`; to set a model or permission mode, pass the whole command (e.g. `--cmd "claude --model opus"`), or set the environment variable `CD_CLAUDE_CMD`. `--cmd` is interpreted by the shell, so quote any paths in it yourself.

`scripts/git/` also holds the single implementation of the git rules, `git-policy.ts` (case table `git-policy.test.ts`), and the Claude Code worker's PreToolUse hook `claude-hook.ts` (attached automatically by `spawn-worker.sh`, tested by `hook.test.sh`).

`scripts/pi/` holds the pi worker extension `claude-bridge.ts` (the report / ask tools, plus enforcement of slots, git hard rules and the cost cap), the isoquant config `models.isoquant.json`, and the zero-cost end-to-end self-test `test/e2e-mock.sh` (must be run after changing pi-worker or the extension; it should print PASS).

`evals/` has 4 test cases (a dry run dispatching two workstreams, answering a progress question, not opening a window for a small job, handling pi slot and budget events), for skill-creator or `claude plugin eval` to run.

## references (read as needed, not all at once)

| File | When to read |
|---|---|
| `references/brief-template.md` | Writing a single worker's brief |
| `references/common-rules-template.md` | Writing a batch's common rules |
| `references/worker-protocol.md` | The full worker-side protocol; you can also have workers read it directly (check in · report · slots · handoff page · wrap up) |
| `references/handoff-template.md` | The shape of a worker's handoff page |
| `references/coord-board-template.md` | Creating or tidying the board / progress board |
| `references/wrap-up-checklist.md` | Acceptance review and wrap-up |
| `references/failure-matrix.md` | When something goes wrong (window did not start, worker lost contact, slot held, the human closed a window...) |
| `references/git-workflow.md` | Source of truth for the git flow: who may do what, the nine steps of a workstream from open to clean, how to merge several workstreams, enforcement, failures |
| `references/agents-md-template.md` | Template for the "Git" section of the project's `AGENTS.md` (check before opening the first workstream) |
| `references/pi-worker.md` | Dispatching pi workers: when to dispatch, one-time setup, how to handle events, brief template, budget, failures |

## Common mistakes

- **The coordinator doing the work itself**: leave handed-out work alone. If you cannot resist, that means you should dispatch another worker or use a subagent.
- **Splicing the first message into `tmux send-keys "…"`**: quotes, `$` and newlines all break, and it gets executed by the shell. Always file -> `load-buffer` -> `paste-buffer`.
- **Not updating the board**: every dispatch, every collection and every slot grant must update the board; otherwise when the human asks for progress you can only go dig through windows.
- **Making decisions for the human**: items a worker flags as "needs a human decision" go into the board's pending-decisions list and are shown to the human all at once. Do not interrupt the human one item at a time, and do not choose yourself.
- **Closing a window without confirming the work is on disk**: "the window is closed" does not mean "the work is still there". Check the handoff page and deliverables first, then close.
- **Merging several workstreams together after acceptance review**: merge one at a time, then have the other workers rebase onto the new base branch; otherwise all the conflicts pile up at the end.
- **A worker working in the main checkout**: if you dispatch without opening a worktree, the git guard cannot attach, and several workers will overwrite each other. Run `worktree.sh new` first.
