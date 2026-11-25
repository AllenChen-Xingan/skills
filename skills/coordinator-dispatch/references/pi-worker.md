# pi workers (a cheap model writes the code; the coordinator only schedules and does acceptance review)

pi (`@earendil-works/pi-coding-agent`) runs in the background in RPC mode, backed by a cheap model on isoquant.ai (default `isoquant/deepseek-v4.1-flash-1017-fast`).
It does not live in a tmux window and does not use cross-session messages; all communication with the coordinator goes through `scripts/pi-worker` and Claude Code's **Monitor** tool.

## Contents
1. When to dispatch a pi worker · 2. One-time setup · 3. How a pi worker goes through the seven steps · 4. Events and what to do · 5. Brief template · 6. Setting the budget · 7. Failures

## 1. When to dispatch a pi worker

| Work | Who |
|---|---|
| A single coding workstream with a clear brief and machine-checkable acceptance (tests / scripts) | **pi worker** |
| Needs lots of context, architectural trade-offs, or coordination across several modules | Claude Code worker (tmux) |
| Splitting work further, running its own workers | Only the coordinator; pi workers **do not coordinate** |
| First review round (cheap-first review) | pi read-only review (`pi-worker review`) |

Why: cheaper models currently hold up well on one well-specified task, but tend to break down when they have to coordinate several projects or sessions at once. So the cheap model is only used as a single-task worker, and Claude acts as the coordinator.

## 2. One-time setup (skip if already installed)

```bash
npm i -g @earendil-works/pi-coding-agent
cp scripts/pi/models.isoquant.json ~/.pi/agent/models.json     # if other providers already exist, merge the providers field instead of overwriting
# the human stores the key (it never goes into the chat):
#   ! mkdir -p ~/.config/isoquant && read -s k && echo "ISOQUANT_API_KEY=$k" > ~/.config/isoquant/.env && chmod 600 ~/.config/isoquant/.env
pi --list-models isoquant                                       # seeing the models is enough
bash scripts/pi/test/e2e-mock.sh                                # zero-cost self-test, should print PASS
```

The config has zero data retention turned on (`Isoquant-ZDR: required`), and the key is read from the file only at request time.

## 3. How a pi worker goes through the seven steps

The first two steps (check resources, write briefs) are the same as in SKILL.md; the differences start at step 3.

| Step | What to do for a pi worker |
|---|---|
| 2 Write the brief | Write `<batch>/brief-<name>.md` from the template in section 5. pi cannot see any conventions outside the common rules file, so **put every key point in the brief** |
| 3 Start the worker | `scripts/pi-worker start <name> --repo <repo> --task-file <batch>/brief-<name>.md --budget <usd>`: automatically creates `<repo>.worktrees/<name>` and branch `w/<name>` (base branch defaults to `origin/<default-branch>`, override with `--base`), and the extension enforces the git rules for that branch |
| 4 Update the board + watch | Add a row to the board's worker table with type `pi`; use **Monitor** to run `scripts/pi-worker watch <name>` with `timeout_ms` set to 1800000, and re-attach it when it expires (watch resumes from its cursor, with no loss or duplication). No need to wait for a check-in; the first `REPORT` counts as the check-in |
| 5 Slots and reports | See section 4. Slots are recorded in the board's slot table as usual, with the holder written as `pi:<name>` |
| 6 Acceptance review | After receiving `REPORT done` plus `SETTLED`: (1) start a read-only cheap review with `pi-worker review <name>` -> (2) send P0/P1 back to the original worker with `follow` -> (3) once the review is clean, the coordinator does the final review personally per `wrap-up-checklist.md` (read the diff, rerun the tests) |
| 7 Wrap up | `pi-worker stop <name>` (stop the review worker too) -> record the cost on the board (`spent=` in `pi-worker status`) -> the coordinator merges (step 8 of section 2 of `git-workflow.md`) -> `pi-worker clean <name> --delete-remote` deletes the worktree and branch |

**pi worker rules are enforced by the extension, not by good behavior** (`scripts/pi/claude-bridge.ts`):
- git (`git-workflow.md`): pi commits, pushes and opens PRs on its own branch; pushing to the main branch or someone else's branch, plain `--force`, merging PRs, deleting branches, tagging and changing config are blocked (`GIT blocked` appears in the watch); leaving its own branch produces `GIT worker left its branch`
- Heavy-work commands (by default matching make/cargo build/xcodebuild/npm test/pytest etc., changeable with `--heavy-re`) first stop and wait for a slot, and the slot is returned automatically when they finish
- At 80% of the cost cap it warns; at 100% it aborts the current turn and blocks all tool calls until the coordinator raises the cap with `pi-worker budget`

## 4. Events and what to do

watch prints one event per line, prefixed with the time.

| Event | What the coordinator does |
|---|---|
| `REPORT progress/done/blocked/failed: …` | Update the board's progress board; done goes to acceptance review; for blocked/failed, look at the reason and reply with `steer` or `follow` |
| `ASK id=<id>: …` | If you can answer it yourself, `pi-worker answer <name> <id> "…"`; if it needs a human decision, add it to the pending-decisions list first and reply "Go with the conservative option for now; it is on the pending list". By default, if there is no answer within 20 minutes, pi picks the conservative option itself |
| `QUOTA id=<id>: <command>` | Slot free: `pi-worker grant <name> <id>`, record the holder on the board; slot taken: do not reply yet (pi waits, up to 60 minutes), and grant when its turn comes; should not run: `pi-worker deny <name> <id> "reason/alternative"` |
| `QUOTA_RETURN passed/failed` | Clear the board's slot table and give the slot to the next in the queue |
| `BUDGET 80% used` | Estimate how much more it needs; if needed, raise it early with `pi-worker budget <name> <usd>` |
| `BUDGET exceeded` + `SETTLED (aborted)` | Check `status` to judge whether it is worth continuing: if so, raise it with `budget` and then `follow "continue"`; if not, stop it and switch to a Claude Code worker or split the work smaller |
| `SPEND $x of $y` | Reports the cumulative cost at the end of each turn; copy it onto the board |
| `TOOL_ERROR` / `LLM_ERROR` / `RETRY_FAILED` / `CMD_FAIL` / `EXT_ERROR` | Ignore occasional ones; if they keep coming, check the logs with `status`, and `abort` if necessary |
| `GIT blocked: <command> — <reason>` | Usually pi switches to the correct approach itself; if the same mistake keeps recurring, `steer` it with the correct command. If its work genuinely needs that operation (e.g. tagging), the coordinator does it |
| `GIT worker left its branch` | `steer <name> "git switch w/<name>, and only work on your own branch"` |
| `SETTLED` | pi is idle: if there was no `REPORT done`, it finished without reporting; `follow "Report done as the brief says"` |
| `EXITED code=N` | The process exited; if it was not caused by stop, check `~/.local/state/pi-worker/<name>/stderr.log` |

Two ways to interject: `steer` inserts after the current tool step finishes and before the next model call (for course correction); `follow` is delivered after the current turn finishes (for sending back; when idle it starts a new turn).

## 5. Brief template (pi worker)

```markdown
# Brief: <name>

## Who you are
You are a coding worker dispatched by the coordinator. Do only what is in this brief; when unsure, ask with ask_claude, and report progress with report_to_claude.
Your worktree: <repo>.worktrees/<name>; your branch: w/<name>, base branch <origin/main>. Follow the "Git" section of the project's AGENTS.md for git rules.

## Intent (the human's own words, verbatim)
> ……

## What the work is
- Goal: ……
- Change only these files / directories: …… (touch nothing else)
- Out of scope: ……

## Read first
- <path>: why to read it

## Acceptance (run all of these yourself before finishing)
- `<command>` passes (heavy work waits for a slot automatically; do not work around it)
- ……

## When done
1. Following the "Git" section of AGENTS.md, commit in small steps on your branch w/<name>; before finishing, `git fetch origin && git rebase <base-branch>`, then push (use `--force-with-lease` after a rebase); if the project uses PRs, open a draft PR
2. Call report_to_claude(status=done): branch, last commit, PR link, which files changed, which acceptance commands were run, the results, and anything left undone
```

## 6. Setting the budget

- Prices (per million tokens): input $0.035, cache hit $0.005, output $0.37. Most of the cost comes from rereading context
- Starting points: small change $0.20, single feature $1, larger feature $3; review defaults to $0.20
- Going over budget is itself a signal: usually the brief is unclear or the work is too big. Split it smaller first, then consider adding money
- Record the cost from each turn's closing `SPEND` in the "Cost" column of the board's worker table

## 7. Failures

| If | Then |
|---|---|
| `start` reports pi failed to start | Check `stderr.log`: model not found -> `pi --list-models isoquant`; key cannot be read -> ask the human to store the key as in section 2 |
| Constant `RETRY` (429 / 5xx) | isoquant is short on capacity; `abort`, then `follow "continue"` after a few minutes, or temporarily switch with `--model` |
| `LLM_ERROR` 401/402/403 | Invalid key / insufficient balance / no access to that model: report to the human, do not retry |
| pi never calls report_to_claude and just stops when done | `SETTLED` still arrives; `follow` with "Report done as the brief says" |
| pi tries to get around the slot (splitting heavy work into differently named commands) | Add that command to `--heavy-re`; if it keeps happening, reassign to a Claude Code worker |
| Monitor expires | Re-attach the same watch; it resumes from its cursor |
| The coordinator session needs to hand over | All runtime state is in `~/.local/state/pi-worker/` and is independent of the session; the new coordinator runs `pi-worker list` and re-attaches the watches |
