# Session lifecycle: open, close and hand over on time

> Applies to every Claude Code session in a batch: the workers **and the coordinator itself**. The coordinator opens, closes and hands over sessions on its own initiative; nobody has to ask it to.
> If the project's handbook sets other thresholds, **the project wins**.

## 1. Why

Once prompt caching hits ~99%, almost all of a long session's cost is re-reading its own context on every step, and quality drops as the context fills with stale detail. A session that has grown to several hundred thousand tokens costs several times more per step than a fresh one that reads a short handoff page. So rotate sessions at a threshold instead of letting them run until the batch ends: a fresh session + a good handoff page keeps the context both usable (room left) and effective (only what matters now).

## 2. Thresholds (defaults; adjust per project)

| Condition | Action |
|---|---|
| Context about **400k** tokens or more | Rotate at the next point where the work can stop |
| A feature / stage just finished **and** context about **250k** or more | Rotate now; this is the cheapest moment, the handoff page is already fresh |
| All of this workstream's work is done (accepted, merged) | Close and **do not** reopen |
| Coordinator's own context over the same thresholds | Rotate the coordinator (section 5) |

Check sizes whenever you update the board, and at least every hour or so during a batch:

```bash
python3 -I scripts/context-size.py <project main dir>            # sessions changed in the last 3 h, largest first
python3 -I scripts/context-size.py <project main dir> --over 400000   # only those over the threshold
```

It reads `~/.claude/projects/<encoded dir>*/` (worktree dirs included) and prints session id (first 8) · directory (worktree name) · context in k tokens · last change. Context = `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` of the session's last assistant message. It only reads; map a row to a window by its directory (one worker = one worktree).

## 3. Session name table

Keep one table of who is in which window, e.g. `state/sessions.md` (or a section of the board):

```
| Window | Role / workstream | Session id (8) | Started | Rotated from | Status |
|---|---|---|---|---|---|
| coord-2 | coordinator (`demo-meta`) | 1a2b3c4d | 11-25 14:10 | coord-1 | active |
| api-2 | worker api | 5e6f7a8b | 11-25 15:02 | api-1 (712k) | active |
```

Update it on every open, rotation and close. Without it, after two rotations nobody knows which window is current.

## 4. Rotating a worker

1. **Coordinator -> worker**: `<window> rotation request: context <N>k; get to a stopping point and prepare to hand over, reply "ready to close"`
2. **Worker** (in this order):
   - Get to a point where work can stop (finish or abandon the current small step; do not leave a half-applied change)
   - Stop every pi it started: `pi-worker stop <name>` for each `<window>-pi*` in `pi-worker list`, then confirm with `kill -0 <pid>` (pid in `~/.local/state/pi-worker/<name>/pi.pid`); `stop` sometimes returns while the process is still alive, so if `kill -0` succeeds, `kill <pid>` and check again
   - Return any slot it holds, release any lock it holds
   - Worktree clean (everything committed), or the uncommitted state written down on the handoff page
   - Handoff page "Where I am" + "Next" written so that a fresh session can continue **from the page alone**: last commit, branch, open pi branches not yet merged, what is half done, the next concrete step
   - Reply `<window> ready to close: handoff page <path>, last commit <hash>`
3. **Coordinator**: read the pane tail (`list-workers.sh <ws> --window <window>`) to confirm nothing is running and no question is pending, then `scripts/close-worker.sh <ws> <window> --yes`
4. **Coordinator**: open the replacement in the same worktree with a new window name (e.g. `api-2`): write a resume message to `<batch>/msg-<new window>.txt`, then `scripts/spawn-worker.sh <ws> <new window> <same worktree> <batch>/msg-<new window>.txt`. Resume message (one paragraph):
   `You are the replacement for <old window>. Read the brief <batch>/<worker>.md, the common rules <batch>/common.md, and the handoff page <handoff-dir>/<worker>.md; continue from "Where I am". First check pi-worker list for any <worker>-pi* still alive. Check in with the coordinator once you have read them.`
   Keep the handoff page file name the same (it belongs to the workstream, not the window), or say in the message which page to use.
5. **Coordinator**: update the session name table and the board's worker row (new window, "rotated from <old> at <N>k").

## 5. Rotating the coordinator itself

The coordinator rotates itself the same way, and it does not wait to be told.

1. **Wait or write down** everything running in the background: a long command, a Monitor, a lock-waiting loop, a scheduled check. Either let it finish, or list it in the handoff page so the new coordinator takes it over (what it is, how to see its output, what to do when it ends)
2. **Write `state/handoff/coordinator.md`** (or the project's equivalent):

   ```
   # Coordinator handoff (<date time>, from window <old>)
   - **Doing now**: <one or two sentences>
   - **Workstreams**: | window | session id | task | status | waiting on |
   - **Pending human decisions**: <list, or pointer to the board section>
   - **Slots, quota and spend**: who holds the slot, queue; per-worker pi caps and spend; batch spend so far
   - **Running in the background**: <command / Monitor / loop> · where its output goes · what to do when it ends
   - **Locks held**: <lock> · held by · release when
   - **Red lines and secrets rules**: where they live (project handbook / common rules path); never copy secret values here
   - **Read first**: this skill, the board <path>, the session table <path>
   ```
3. **Free the name, then open the new coordinator.** First `scripts/coordinator-name.sh <coordinator workdir> --retire`: it types `/rename <project>-meta-old` into your own pane, effective when this turn ends, so only one session holds `<project>-meta`. Then open the new coordinator in the same tmux session, in the coordinator's working directory: write the first message to a file, e.g. `You are the new coordinator, taking over from window <old>. Load the coordinator-dispatch skill, read state/handoff/coordinator.md and the board, cross-check with list-workers.sh, then report to the human that you are in charge.`, and run `scripts/spawn-worker.sh <ws> <new coord window> <coordinator workdir> <msg file> --no-git-guard --name "$(scripts/coordinator-name.sh <coordinator workdir>)"` (the coordinator is not a worker on a worker branch; `--name` gives it the fixed name `<project>-meta` from its first second)
4. **The new coordinator closes the old one**: after it has reported in, the **new** coordinator reads the old window's tail and runs `close-worker.sh <ws> <old window> --yes`. The old one cannot do it itself: `close-worker.sh` refuses to close the window it runs in, which is exactly what keeps a coordinator from closing itself before the successor is up
5. **Tell the human** where to talk from now on (`tmux select-window -t <ws>:<new window>`) and update the session table (new window, same name). Workers need no new address: they keep messaging `<project>-meta`. If a worker's message went to `<project>-meta-old` before the old window closed, the new coordinator reads it in the old pane tail before closing it

## 6. Closing for good

When a workstream is accepted and merged, close its window with the wrap-up flow (`wrap-up-checklist.md`) and do not open a replacement. When the whole batch is done, the coordinator closes the last worker windows, writes a short final coordinator handoff page (what was done, what is left for the human), and tells the human; it does not keep sessions open "just in case".

## 7. Recovering after a crash

When tmux (or the machine) died and the windows are gone:

- pi processes may **still be alive** but no longer reachable by anyone: their worker's Monitor is gone, so they can keep writing to a worktree nobody watches
- The first thing a new session does for a workstream, before any new pi: `pi-worker list`; for each of its `<worker>-pi*`, `pi-worker stop`, then `kill -0 <pid>` until it is really gone (kill it if not)
- Then see where things actually are: `git -C <worktree> log --oneline -5` and `git status` for the worker branch and each pi branch; compare with the handoff page's "Where I am" and correct the page
- **One pi per worktree at a time**: never start a new pi in a worktree that an old one might still be writing to
- The coordinator rebuilds the session table from `context-size.py` (recent sessions per worktree) and `list-workers.sh`, then reopens workers one at a time with resume messages (section 4, step 4)
