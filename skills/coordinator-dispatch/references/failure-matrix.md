# Failure matrix (if X, then Y)

One goal: **never stall**. If one line is blocked, move the others forward and record the blocked one in the ledger.

| If | Then |
|---|---|
| `spawn-worker.sh` times out before the window is ready | Read the pane tail it prints. Trust-folder / permission prompt → ask the human to click it in that window (never confirm it for them with send-keys). Command not found → check `--cmd`. Anything else → close the window and retry once; if it fails again, tell the human |
| Worker doesn't respond after the paste | `list-workers.sh --window <w>` to see the pane tail. If the paste is sitting in the input box unsubmitted → `tmux send-keys -t <ws>:<w> Enter` once (the only keypress you may send by hand) |
| A window with the same name already exists | Check whether it's an old worker that never wrapped up. If so, run the wrap-up process; if not, pick another window name |
| Worker hasn't checked in after 5 minutes / no reports for a long time | Check the pane tail and handoff page. Waiting on a tool permission → tell the human. Session died → read its handoff page, start a replacement worker whose brief says "continue from <handoff page path>" |
| Two workers want the slot at the same time | First come, first served; the other is queued. Record the queue in the ledger |
| The slot holder goes silent | Check the pane tail to see whether the command is still running. Reclaim the slot only once you've confirmed it stopped, and note it in the ledger |
| A worker edited another worker's files | Tell it to stop and list the changes on its handoff page. The coordinator decides whether to keep or revert them (don't revert with an overwriting copy if the human has edited the file) |
| A worker wants to do a git write / asks the human directly | Stop it and route the request through the coordinator |
| The human closed a window a worker opened | Don't block it or reopen it. Record it on the handoff page and in the ledger's "Findings" |
| Workers hand in many pending decisions | Collect them in the ledger's pending list and ask them all at once when the batch wraps up (pairs well with a decision-batching skill) |
| Not enough disk space for another worktree | Run one fewer line, or wrap up finished workers first and delete their merged worktrees (confirm the work is on disk before deleting) |
| The same kind of failure happens a third time | Propose a rule to the human; with their OK, add it to the project onboarding doc or memory |
