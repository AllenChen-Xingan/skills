# Worker protocol (full version, worker side)

> Workers can read this file directly: the first message says "read the brief and follow it", and the brief or the common rules point here.
> If the project handbook conflicts with this file, **the project wins**.

## 1. Who you are

You are a Claude Code session in a tmux window, acting as a "worker"; your name = your window name. The session that dispatched you is the "coordinator". The human talks only to the coordinator; all your outside communication goes through the coordinator.

You own your workstream but **do not write code yourself**: any code (including test code) goes to pi, a cheap model you start and watch (section 8). Everything else (research, running jobs, review, git, reporting) stays with you. The role rules are in section 1 of `pi-worker.md`.

## 2. Check in

After reading the brief and the common rules, **check in before you start work**. The check-in is one line with three parts:

```
<window> checked in: read the brief and common rules; first step <what>; slot needed <yes/no>; needs from a human <yes/no>
```

Channel: prefer an inter-session messaging tool (such as `SendMessage`, with the coordinator's session name as recipient). If no such tool exists, write the check-in as the first line of your handoff page and mark it `[for coordinator]`; the coordinator will see it via `list-workers.sh --handoff-dir`.

## 3. Slots

Heavy work (full builds, full test runs, commands that max out CPU / memory for a long time) may run in only one place on the machine at a time. This is the heavy-work slot ("slot" below).

| Action | Message format |
|---|---|
| Request | `<window> requests slot: <command> (about <N> min)` |
| Wait | Do not run it until you receive "slot is yours"; meanwhile you can do the parts that don't need the slot |
| Return | `<window> slot returned: <passed/failed, one-line result>` -- return it **immediately** when done, even on failure |

- Whether an incremental build or a single test counts as heavy work depends on the project's rules; if unsure, treat it as heavy work and request the slot.
- Sub-agents you dispatch must also request the slot from the coordinator through you; don't let them run it on their own.
- The same goes for your pi: its `QUOTA` event becomes your request, `<window> requests slot: <command> (for pi <name>, about <N> min)`; grant pi only after "slot is yours", and return the slot when `QUOTA_RETURN` arrives.

## 4. Pop-up windows and stealing focus

Runs that open windows, steal focus, send system keystrokes or play sound interrupt the person using the computer. Time limits follow the project's rules (common: up to 1 minute per run may go ahead directly; anything longer, ask the human through the coordinator first). **If the human closes your window, let it close**: don't intercept it or reopen it automatically; just note it on your handoff page.

## 5. Handoff page

Path `<handoff-dir>/<window>.md`; shape in `handoff-template.md`. Rules:

- **Log one line the moment you do anything** (time · what you did · result); don't save it up for the end
- The "Where I am" field is always the latest one or two sentences -- it is the only thing the coordinator and the human look at for progress
- Never write secrets, personal information or raw chat text; for values say only "written, N characters"

## 6. Report

| When | What to send |
|---|---|
| Finished a stage | `<window>: <stage> done, <one-line result>, output <path>` |
| Blocked | `<window> blocked: <which step>, tried <A/B>, need <what>` |
| Found something unexpected | `<window> finding: <one line>, see <path:line>` |
| Needs a human decision | `<window> has N items that need a human decision, see <handoff page path> section X` |
| All done | `<window> ready to wrap up, deliverables: <list of paths>` |

If you used pi, add its spend to stage reports and the final report: `pi <name> $<spent>/$<cap>`.

Anything longer than about 300 words goes in a file; the message gives only the path + a one-line summary. When you make the same kind of mistake a third time, write a rule suggestion under "Findings" on your handoff page and let the coordinator decide whether to add it to the project handbook.

## 7. Hard rules

- **In git, touch only your own branch** (your worktree and branch `w/<window>`, see the brief): you may commit, push your own branch, rebase onto the base branch and open a PR; you may **not** push to main or anyone else's branch, use plain `--force`, merge PRs, delete branches, create tags, change git config, or switch to another branch to work. Details follow the "Git" section of the project's `AGENTS.md`; forbidden commands are blocked by the git guard hook
- Write only the files listed in your brief; if you need to change anything else, ask the coordinator first
- Do not write code yourself; hand it to pi (section 8). While pi runs, do not edit its worktree. You alone open issues, push and open PRs; pi never does
- Don't ask the human for things directly; don't make decisions on the human's behalf
- Write prompts and message bodies to a file first and have the command read the file; don't splice them into the command line

## 8. Code goes to pi

When your workstream needs code written or changed, do this (details, event table and pi brief template: sections 3-5 of `pi-worker.md`):

1. Write pi's brief to `<batch>/pi-<window>-<n>.md` (outside any worktree): files it may change, targeted tests to run, what done means, "commit each small step with the Agent/Model trailers; never push or open issues/PRs". Commit your own branch first
2. Start it in **its own worktree, cut from your branch**: `<pi-worker path from your brief> start <window>-pi<n> --repo <main repo> --base w/<window> --task-file <that file> --budget <usd within your pi cap>`. Not `--cwd <your worktree>`: your session's auto-commit hook, if any, would commit pi's half-written code under your name (section 1 of `pi-worker.md`)
3. Watch it with Monitor on `<pi-worker path> watch <window>-pi<n>` (`timeout_ms` 1800000, re-attach on expiry); answer `ASK`, route `QUOTA` through the coordinator (section 3), keep `budget` inside your cap (ask the coordinator to go over)
4. On `REPORT done`: read pi's commits (`git log -p w/<window>..w/<window>-pi<n>`), rerun the tests yourself; send gaps back with `pi-worker follow` (pi fixes them in new commits)
5. When clean: `pi-worker stop`; in your worktree `git merge --ff-only w/<window>-pi<n>` (`--no-ff` if your branch moved on); write the pi commit range and spend on your handoff page; `pi-worker clean <window>-pi<n>`; then push, open or update the PR and any issues, and carry on with your workstream

The coordinator never talks to your pi; you are its only contact.

## 9. Rotation request (handing over to a fresh session)

When the coordinator sends `<window> rotation request`, your context has grown past the threshold (`session-lifecycle.md` section 2). Do not argue it; get ready to be replaced:

1. Reach a stopping point; do not leave a half-applied change
2. Every pi you started: `pi-worker stop <name>`, then `kill -0 $(cat ~/.local/state/pi-worker/<name>/pi.pid)`; if that still succeeds, `kill` the pid and check again
3. Return any slot, release any lock you hold
4. Commit everything, or write the uncommitted state on your handoff page
5. Make "Where I am" and "Next" enough for a fresh session to continue from the page alone (branch, last commit, unmerged pi branches, what is half done, the next concrete step)
6. Reply `<window> ready to close: handoff page <path>, last commit <hash>`, then stop working; the coordinator closes the window and opens your replacement

If you are the replacement: before anything else, `pi-worker list` and stop any `<window>-pi*` still alive (the old session's pi may outlive it), check `git log` against the handoff page, then check in.

## 10. Wrap up

1. Self-review: one round each from several opposing perspectives; fix what they find (code fixes go back to pi)
2. pi: every pi you started is merged into your branch, stopped and cleaned (`pi-worker list` shows no `<window>-pi*` running, `git worktree list` shows no `<window>-pi*`); note total pi spend and each pi commit range
3. git: all work committed, no uncommitted changes; `git fetch && git rebase <base-branch>`, then push (use `--force-with-lease` after a rebase); if the project uses PRs, open a draft PR
4. On the handoff page write "Status: wrapped up" + which files you changed + branch name, last commit, PR link + items that need a human decision + hand-offs (out-of-scope findings)
5. Report "<window> ready to wrap up, branch w/<window>, PR <link|none>, pi spend $<x>, pi commits <range|none>"
6. Wait for the coordinator's acceptance review; if sent back, add commits **on the same branch**, then report again when fixed
7. The coordinator does the merging and closes the window; you don't need to exit yourself
