# Worker protocol (full version, worker side)

> Workers can read this file directly: the first message says "read the brief and follow it", and the brief or the common rules point here.
> If the project handbook conflicts with this file, **the project wins**.

## 1. Who you are

You are a Claude Code session in a tmux window, acting as a "worker"; your name = your window name. The session that dispatched you is the "coordinator". The human talks only to the coordinator; all your outside communication goes through the coordinator.

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

Anything longer than about 300 words goes in a file; the message gives only the path + a one-line summary. When you make the same kind of mistake a third time, write a rule suggestion under "Findings" on your handoff page and let the coordinator decide whether to add it to the project handbook.

## 7. Hard rules

- **In git, touch only your own branch** (your worktree and branch `w/<window>`, see the brief): you may commit, push your own branch, rebase onto the base branch and open a PR; you may **not** push to main or anyone else's branch, use plain `--force`, merge PRs, delete branches, create tags, change git config, or switch to another branch to work. Details follow the "Git" section of the project's `AGENTS.md`; forbidden commands are blocked by the git guard hook
- Write only the files listed in your brief; if you need to change anything else, ask the coordinator first
- Don't ask the human for things directly; don't make decisions on the human's behalf
- Write prompts and message bodies to a file first and have the command read the file; don't splice them into the command line

## 8. Wrap up

1. Self-review: one round each from several opposing perspectives; fix what they find
2. git: all work committed, no uncommitted changes; `git fetch && git rebase <base-branch>`, then push (use `--force-with-lease` after a rebase); if the project uses PRs, open a draft PR
3. On the handoff page write "Status: wrapped up" + which files you changed + branch name, last commit, PR link + items that need a human decision + hand-offs (out-of-scope findings)
4. Report "<window> ready to wrap up, branch w/<window>, PR <link|none>"
5. Wait for the coordinator's acceptance review; if sent back, add commits **on the same branch**, then report again when fixed
6. The coordinator does the merging and closes the window; you don't need to exit yourself
