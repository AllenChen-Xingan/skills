# Failure matrix (if X, then Y)

There is only one goal: **never stall** -- when one workstream is stuck, move the others forward first and record the stuck one on the board.

| If | Then |
|---|---|
| `spawn-worker.sh` times out before the worker is ready | Read the pane tail it prints: trust-directory / permission prompt -> ask the human to click it in that window (don't confirm for them with send-keys); command not found -> check `--cmd`; anything else -> close the window and restart once; if it fails again, tell the human |
| The worker doesn't respond after pasting | `list-workers.sh --window <w>` to see the pane tail; if the paste is sitting in the input box unsubmitted -> `tmux send-keys -t <ws>:<w> Enter` to send one Enter (this is the only keypress you may send) |
| A window with the same name already exists | First check whether it is an old worker that never wrapped up; if so, run the wrap-up process; if not, pick another window name |
| Worker hasn't checked in after 5 minutes / no report for a long time | Look at the pane tail and handoff page; waiting for a tool permission -> tell the human; session dead -> read the handoff page, start a replacement worker and write "continue from <handoff page path>" in its brief |
| Two workers want the slot at the same time | First come, first served; the other joins the queue; record the queue on the board |
| The slot holder has gone silent | Check the pane tail to see whether the command is still running; take the slot back only after confirming it has stopped, and note it on the board |
| A worker changed someone else's files out of bounds | Have it stop and list the changes on its handoff page; the coordinator decides whether to keep or revert them (don't revert files someone else has edited by copying over them) |
| A worker wants to merge, push to main, delete a branch, create a tag / ask the human for things directly | Stop it (the git guard usually already has), and have the coordinator do it or relay it instead |
| git-related surprises (rebase conflict, secret committed by mistake, clean refused) | See `git-workflow.md` section 6 |
| The human closed a window a worker opened | Don't intercept or reopen; record it on the handoff page and under the board's "Findings" |
| A worker hands in many items that need a human decision | Collect them in the board's pending-decisions list and ask them all at once when the batch wraps up (can be paired with a decision-batching skill) |
| Not enough disk space for a new worktree | Open one fewer workstream, or wrap up finished workers first and remove merged worktrees with `worktree.sh clean` (confirm the work is saved before removing) |
| A worker's pi misbehaves (won't start, keeps retrying, over its cost cap, never reports done, bypasses the slot) | The worker handles it (`pi-worker.md` section 7); the coordinator only answers the worker's slot and cap requests and its blocked reports. Do not run `pi-worker` yourself |
| A worker writes code itself instead of handing it to pi | Send it back: the code goes to pi (section 1 of `pi-worker.md`); if pi cannot do it, the worker reports blocked and you re-split the work |
| A worker ran pi with `--cwd` in its own worktree and its auto-commit hook committed pi's half-written code | Have the worker review those commits like pi's, and from then on start pi with `--repo <main repo> --base w/<worker>` (section 1 of `pi-worker.md`) |
| A `w/<worker>-pi*` branch shows up on the remote, or pi opened an issue / PR | Should not happen (the extension blocks it); you delete the remote branch, the worker closes the issue / PR; check the version of `claude-bridge.ts`, and add the case to `git-policy.test.ts` |
| A session's context is past the threshold (`context-size.py --over 400000`) | Rotate it: `session-lifecycle.md` section 4 (worker) or 5 (coordinator) |
| tmux died / windows are gone, workers' pi may still be running | `session-lifecycle.md` section 7: stop and `kill -0`-check every pi first, check the last commits, one pi per worktree, then reopen workers one at a time with resume messages |
| `pi-worker stop` returned but the process is still alive (`kill -0 <pid>` succeeds) | `kill <pid>` (pid in `~/.local/state/pi-worker/<name>/pi.pid`) and check again before starting another pi in that worktree |
| The same kind of failure happens a third time | Write a rule suggestion for the human; once approved, add it to the project handbook or memory |
