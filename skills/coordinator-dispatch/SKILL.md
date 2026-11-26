---
name: coordinator-dispatch
description: "Three-tier multi-session work, coordinator → Claude Code workers → pi: split a job into parallel workstreams, write briefs, start workers in tmux windows (each worker hands all code to pi, a cheap model it runs in the background), hand out heavy-work slots, cap pi spend, cheap-first review, track a board and handoff pages, wrap up after acceptance, and rotate sessions (workers and the coordinator itself) before their context grows too large. Use when the user says \"dispatch\", \"start a worker\", \"let pi write it\", \"you are the coordinator\", \"run a few sessions in parallel\", \"how is it going\", \"wrap up / close the windows\", \"hand over\", \"rotate the session\", \"context is too big\", \"close the window and reopen\", \"coordinator handover\" (交接, 轮换, 上下文太大, 关窗口重开, 大总管交接), or when a job splits into 2+ workstreams that do not touch the same files and each take over half an hour. Not for a ten-minute job (use an in-session subagent), pure code review or git merge strategy."
---

# Coordinator dispatch (coordinator-dispatch)

One main session acts as the **coordinator**: it only splits work, dispatches it, hands out slots, manages cost, collects results, does acceptance review, and talks to the human. The real work is done by **Claude Code workers** in tmux windows. A worker does not write code itself: it hands every piece of code (including tests) to **pi**, a cheap model it starts and watches in the background. So there are three tiers, coordinator -> Claude Code worker -> pi; the coordinator never starts pi. The role rules for pi are in section 1 of `references/pi-worker.md`. The pattern comes from the "1 coordinator + N workers" approach described publicly by Yang Zhiping.

Five principles (they always hold):

1. **The human faces a single entry point**: only the coordinator talks to the human. Anything a worker needs to ask the human, or needs from the human, goes through the coordinator. pi talks only to the worker that started it.
2. **Handoffs are written as files**: briefs, common rules, first messages, handoff pages and the board all live on disk. Conversations break; files do not.
3. **Slots, order, cost and merging belong to the coordinator**: the coordinator decides who goes first, who may use heavy resources (full builds, runs that grab the foreground), how much each worker may spend on pi, who merges into the main branch first, and when to wrap up. A pi's slot request reaches the coordinator only as its worker's own request.
4. **One worker = one worktree = one branch**: workers commit, push, open issues and PRs on their own branch (pi commits fine-grained on its own branch cut from its worker's branch, never pushes or opens issues/PRs; see section 1 of `references/pi-worker.md`); merging, deleting branches and releasing belong only to the coordinator. The source of truth is `references/git-workflow.md`.
5. **Cheap-first review**: keep small changes simple; for changes to core logic, run one review round with a cheaper model first (a cheaper Claude subagent, or a cross-model review; not pi, which only writes code), fix, then have an expensive model (the coordinator, or a cross-model review) do the final review.

## When to use / not use

| Situation | Which path |
|---|---|
| 2 or more workstreams, not touching the same files, each at least half an hour | This skill: Claude Code workers in tmux |
| A workstream needs code written or changed (even just one workstream) | Still a Claude Code worker; the worker hands the code to pi (`references/pi-worker.md`). The coordinator never starts pi |
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

**The coordinator is always named `<project>-meta`** (e.g. `shop-meta`), the same name through every rotation, so workers, briefs and the board never need a new name. `scripts/coordinator-name.sh <coordinator workdir>` prints it (pass the coordinator's own directory, not a worker worktree). The moment a session takes the coordinator role, before dispatching anything, it names itself with `scripts/coordinator-name.sh <coordinator workdir> --rename-self` (types `/rename <project>-meta` into its own pane; it takes effect when the current turn ends). `<boss>` below is always this name.

## Roles

| Role | Who | Does | Does not |
|---|---|---|---|
| Coordinator | The main session the human is talking to | Splits work, writes briefs (with each worker's pi budget cap), opens worktrees and branches, starts Claude Code workers, hands out slots, collects reports, spot-checks, merges into the main branch, deletes branches, releases, talks to the human | Does not do the work it has handed out; never starts or drives pi |
| Claude Code worker | Claude Code in a window of `<ws>`, in its own worktree | Everything in its workstream except writing code: research, running jobs, starting and watching pi, reviewing pi's commits, rerunning tests, merging pi's branch into its own, committing, pushing, opening issues and PRs on its own branch, maintaining its handoff page, reporting (including pi spend), requesting slots (also for its pi) | Does not write code itself; does not talk to the human, does not merge, does not touch the main branch or other workers' branches or files (enforced by the git guard hook) |
| pi | A background cheap-model process started by a Claude Code worker, in its own worktree and branch cut from the worker's branch | Only writes code and commits it in small steps; full rules in section 1 of `references/pi-worker.md` | Everything else, including push, issues, PRs and merging |
| Reviewer (optional) | A model from another vendor / a multi-perspective workflow | Finds faults | Does not change files (cross-model review has its own skill) |

## Seven-step flow

1. **Check resources**: how much is left (`df -h .`; each worktree takes a full copy of the space, and each running pi has its own worktree too), who holds the slots (read `<board>`), which windows already exist in `<ws>` (`scripts/list-workers.sh <ws>`). If a window with the same name already exists, pick another name or wrap up the old one first. If any workstream needs code, check once that pi is set up (section 2 of `references/pi-worker.md`).
2. **Write briefs**: first generate the skeleton with `scripts/new-batch.py <batch> --boss <boss> --workers a,b,c` (common rules + a brief per worker + a first message per worker; existing files are never overwritten), then fill in each one.
   - A brief must answer four things: **who you are · what the work is · what to read first · whom to report to when done**. Template: `references/brief-template.md`
   - If the workstream needs code, fill in the brief's "Code goes to pi" section: the absolute path of `scripts/pi-worker` and the worker's pi budget cap
   - One set of common rules per batch: `references/common-rules-template.md`
   - The human's own words go in the "Intent" section **verbatim**, not expanded or rewritten
3. **Start workers**: first open a workstream with `scripts/git/worktree.sh new <repo> <name>` (giving `<repo>.worktrees/<name>`, branch `w/<name>`), and record the branch name on the board. Then `scripts/spawn-worker.sh <ws> <window> <workdir> <batch>/msg-<window>.txt`. Use that worktree as the working directory; the script attaches the git guard hook automatically. The first message is a single sentence, "Read the brief and follow it; check in with the coordinator once you have read it". **Write it to a file first, then feed it in**; never splice it into a command line. The script waits for Claude Code to be ready, pastes, presses Enter and prints the pane tail; if it is not ready it exits with an error rather than pressing keys blindly. Starting pi is the worker's job, not this step.
4. **Update the board + wait for check-in**: add a row to the worker table in `<board>` (window · task · brief · handoff page · status=dispatched). Once the worker checks in, change it to "checked in". If there is no check-in after about 5 minutes, look at the pane tail with `list-workers.sh`; usually it is stuck on a trust-directory / permission confirmation dialog. Tell the human to click it; do not click it for them.
5. **Slots and reports**: the slot message format, queueing and returns are in section 3 of `references/worker-protocol.md`; a request "for pi <name>" is handled like any other request from that worker. A worker asking to raise its pi cap is a cost decision for the coordinator. On every report, update the worker table (including pi spend) and the "progress board" in `<board>` right away. When the human asks for progress, first get the machine-side status with `list-workers.sh <ws> --handoff-dir <handoff-dir>`, then answer in the progress board format (section 5 of `references/coord-board-template.md`): **one line per worker, status first, no more than one screen**.
6. **Acceptance review**: after a worker reports "ready to wrap up", changes to core logic first get a cheap review round (principle 5), then spot-check against `references/wrap-up-checklist.md`: are the deliverables there, were the self-tests really run, were any hard rules broken, has the worker merged, stopped and cleaned its pi and reported pi spend and commit range, have the things that need a human decision been added to the pending-decisions list. If it does not pass, write the specific gaps as one message back to the worker (send back); do not fill them in yourself.
7. **Wrap up**: the worker's handoff page says "wrapped up" -> `scripts/close-worker.sh <ws> <window>` (prints the pane tail first, asks for confirmation) -> merge: one at a time, following steps 8-9 of section 2 of `references/git-workflow.md` (merge, `worktree.sh clean`), then tell the other running workers to rebase -> set the board to "done, wrapped up (window closed)" and record the merge commit -> report to the human in one sentence + the path.

## Session lifecycle: open, close and hand over on time

Every session in the batch, **the coordinator included**, gets rotated on time, and the coordinator does the opening, closing and handing over itself, without waiting to be asked. Why: with prompt caching at ~99%, a long session's cost is mostly re-reading its own context every step, so a session at 600k tokens costs several times more per step than a fresh one that reads a short handoff page, and it reasons worse over stale detail. Full procedure: `references/session-lifecycle.md`.

- **Thresholds** (defaults, the project may change them): context about 400k or more -> rotate at the next stopping point; a feature just finished and context about 250k or more -> rotate now; the workstream's work is all done -> close and do not reopen.
- **Measure**: `python3 -I scripts/context-size.py <project main dir> [--over 400000]` (read-only) lists recent sessions per worktree with their current context size, largest first. Run it when you update the board.
- **Worker rotation**: rotation request -> the worker reaches a stopping point, stops every pi it started and confirms with `kill -0` that each is gone, returns slots and locks, leaves the worktree clean (or says on the handoff page what is not), writes "Where I am" so a fresh session can continue from the page alone, replies "ready to close" -> you read the pane tail, `close-worker.sh <ws> <window> --yes` -> `spawn-worker.sh` a new window in the same worktree with a resume message (brief, common rules, handoff page) -> update the session table (e.g. `state/sessions.md`).
- **Coordinator rotation**: finish or write down anything running in the background -> write `state/handoff/coordinator.md` -> rename yourself out of the way with `coordinator-name.sh <dir> --retire` (`<project>-meta-old`) -> `spawn-worker.sh ... --name <project>-meta` a new coordinator window in the same tmux session, first message "load this skill, read the handoff page, report to the human" -> after it reports, the **new** coordinator closes the old window (`close-worker.sh` refuses to close its own window, so the old one cannot close itself first) -> tell the human which window to talk in. Workers keep messaging `<project>-meta`; the name never changes.
- **After a crash** (tmux gone): old pi processes may still be running unwatched. Before anything else, stop every pi of the workstream and confirm it exited, check the last commits, and keep one pi per worktree at a time.

## Scripts (all support `--help`; quote paths with spaces)

| Script | Purpose | Key parameters |
|---|---|---|
| `scripts/new-batch.py` | Generate the brief skeleton for a batch | `<batch-dir> --boss --workers [--handoff-dir] [--board] [--date] [--path-prefix] [--dry-run]` |
| `scripts/spawn-worker.sh` | Open a window, start Claude Code, wait until ready, feed the first message | `<ws> <window> <workdir> <msg-file> [--name] [--cmd] [--ready-pattern] [--timeout] [--tail] [--dry-run]` |
| `scripts/list-workers.sh` | List windows + each window's pane tail + the handoff page's "Where I am" | `<ws> [--lines N] [--handoff-dir D] [--window W]` |
| `scripts/close-worker.sh` | Print the pane tail, close the window after confirmation | `<ws> <window> [--yes] [--tail N]` |
| `scripts/coordinator-name.sh` | The coordinator's fixed name `<project>-meta`; rename the current session to it, or retire it to `-meta-old` before a handover | `[coordinator workdir] [--project NAME] [--rename-self \| --retire] [--dry-run]` |
| `scripts/context-size.py` | Read-only: current context size of each recent Claude Code session, largest first (run with `python3 -I`; tests in `scripts/context-size.test.py`) | `[project dir] [--hours 3] [--over N] [--projects-dir D]` |
| `scripts/git/worktree.sh` | Open / clean a workstream: one worktree and one branch per worker | `base <repo>` · `new <repo> <name> [--base B] [--branch BR]` · `clean <repo> <name> [--delete-remote] [--force]` |
| `scripts/pi-worker` | **Run by Claude Code workers, not the coordinator**: start · watch · grant/deny · answer · steer/follow · budget · status · stop · list for the pi it started | `start <worker>-pi<n> --repo <main repo> --base w/<worker> --task-file F [--budget USD] [--model M] [--heavy-extra-re RE]` (adds project commands to the default heavy-work set in `scripts/pi/heavy.ts`) · `clean <name>` after the worker merged pi's branch; the rest are in `--help` |

`--cmd` defaults to `claude`; to set a model or permission mode, pass the whole command (e.g. `--cmd "claude --model opus"`), or set the environment variable `CD_CLAUDE_CMD`. `--cmd` is interpreted by the shell, so quote any paths in it yourself.

`scripts/git/` also holds the single implementation of the git rules, `git-policy.ts` (case table `git-policy.test.ts`), and the Claude Code worker's PreToolUse hook `claude-hook.ts` (attached automatically by `spawn-worker.sh`, tested by `hook.test.sh`).

`scripts/pi/` holds the pi extension `claude-bridge.ts` (the report / ask tools, plus enforcement of slots, git hard rules and the cost cap), the single heavy-work rule `heavy.ts` (case table `heavy.test.ts`, run with `node`), the isoquant config `models.isoquant.json`, and the zero-cost end-to-end self-test `test/e2e-mock.sh` (must be run after changing pi-worker or the extension; it should print PASS).

`evals/` has 6 test cases (a dry run dispatching two workstreams, answering a progress question, not opening a window for a small job, handling a worker's slot and pi-budget requests for its pi, rotating workers over the context threshold, the coordinator handing itself over), for skill-creator or `claude plugin eval` to run.

## references (read as needed, not all at once)

| File | When to read |
|---|---|
| `references/brief-template.md` | Writing a single worker's brief |
| `references/common-rules-template.md` | Writing a batch's common rules |
| `references/worker-protocol.md` | The full worker-side protocol; you can also have workers read it directly (check in · report · slots · handoff page · code goes to pi · wrap up) |
| `references/handoff-template.md` | The shape of a worker's handoff page |
| `references/coord-board-template.md` | Creating or tidying the board / progress board |
| `references/wrap-up-checklist.md` | Acceptance review and wrap-up |
| `references/session-lifecycle.md` | Rotating a worker or the coordinator itself, closing for good, recovering after tmux died |
| `references/failure-matrix.md` | When something goes wrong (window did not start, worker lost contact, slot held, the human closed a window...) |
| `references/git-workflow.md` | Source of truth for the git flow: who may do what, the nine steps of a workstream from open to clean, how to merge several workstreams, enforcement, failures |
| `references/agents-md-template.md` | Template for the "Git" section of the project's `AGENTS.md` (check before opening the first workstream) |
| `references/pi-worker.md` | Source of truth for pi: the three-tier role rules, setup, how a Claude Code worker starts and drives pi, events, pi brief template, budget, failures |

## Common mistakes

- **The coordinator doing the work itself**: leave handed-out work alone. If you cannot resist, that means you should dispatch another worker or use a subagent.
- **The coordinator starting or driving pi**: pi belongs to the Claude Code worker that started it. The coordinator answers that worker's slot and cap requests, never pi's events.
- **A Claude Code worker writing code itself**: code goes to pi; if pi keeps failing, the worker splits the task smaller or reports blocked.
- **Splicing the first message into `tmux send-keys "…"`**: quotes, `$` and newlines all break, and it gets executed by the shell. Always file -> `load-buffer` -> `paste-buffer`.
- **A coordinator left with an auto-generated name** (`shop-ba`, `shop-05`...): every rotation then renames the coordinator and every worker has to be told again. Name it `<project>-meta` when it takes the role and when it is spawned.
- **Not updating the board**: every dispatch, every collection and every slot grant must update the board; otherwise when the human asks for progress you can only go dig through windows.
- **Making decisions for the human**: items a worker flags as "needs a human decision" go into the board's pending-decisions list and are shown to the human all at once. Do not interrupt the human one item at a time, and do not choose yourself.
- **Closing a window without confirming the work is on disk**: "the window is closed" does not mean "the work is still there". Check the handoff page and deliverables first, then close.
- **Merging several workstreams together after acceptance review**: merge one at a time, then have the other workers rebase onto the new base branch; otherwise all the conflicts pile up at the end.
- **Letting sessions run until the batch ends**: a worker at 800k tokens is the most expensive thing in the batch. Check `context-size.py` and rotate at the threshold, the coordinator too.
- **A worker working in the main checkout**: if you dispatch without opening a worktree, the git guard cannot attach, and several workers will overwrite each other. Run `worktree.sh new` first.
