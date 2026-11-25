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
| A pi worker misbehaves (won't start, keeps retrying, over its cost cap, never reports done, bypasses the slot) | See `pi-worker.md` section 7 |
| The same kind of failure happens a third time | Write a rule suggestion for the human; once approved, add it to the project handbook or memory |
