# Review and wrap-up checklist (coordinator side)

Go through each item after a worker reports "ready to wrap". **A spot check is not re-reading its report.** Look at the files and rerun the checks it says it ran.

## 1. Review (if anything fails, send it back with the gaps spelled out)

- [ ] Every file under "Deliverables" in the brief exists and is on the "Files you may write" allowlist (use `git status` to look for out-of-bounds changes)
- [ ] Pick one or two of the self-tests / checks it says it ran and rerun them yourself (give yourself the slot first if needed)
- [ ] The handoff page's "Status" says "wrapped up", and "Progress" matches reality
- [ ] Red lines: no secrets, personal information or raw chat text in deliverables or the handoff page (rough scan: `grep -nE 'sk-|ghp_|api[_-]?(key|hash|secret)|@.+\.(com|edu|org)|\+[0-9]{6,}'`)
- [ ] No traces of git writes (no commits from it in `git log`, no extra branches in `git branch`, nothing new in `git stash list`)
- [ ] The slot has been returned (the ledger's slot table is free or has a new holder)
- [ ] Pending decisions have been moved into the ledger's pending list, each with options and a recommendation
- [ ] Out-of-scope hand-offs are recorded in the ledger's "Findings" or opened as new tasks

Send-back format: `<window> review failed: 1) <gap> 2) <gap>; fill these and report ready to wrap again`

## 2. Wrap-up

1. `scripts/close-worker.sh <ws> <window>`: read the printed pane tail first, confirm no command is running and no question is unanswered, then confirm closing
2. Ledger worker table: set status to "done, wrapped (window closed)" + anything left for the human (e.g. "manual listening test remaining")
3. Remove this worker's line from the progress board or mark it done
4. The coordinator does git writes following the project's process (branch, commit message, PR all per project conventions). Before committing, check `git status` to confirm it contains only this line's changes
5. Tell the human in one sentence: what was done · deliverable paths · how many decisions are waiting on them
6. Once the whole batch has wrapped up: keep the batch directory for traceability (don't delete it) and update the ledger's "Top / next steps"

## 3. Handover (when the coordinator itself is leaving)

- Update the coordinator session name in the ledger header
- Tell each in-progress worker: "the coordinator is now <new session name>; report to it from now on"
- The new coordinator starts by reading the ledger + each in-progress worker's handoff page, then checks with `list-workers.sh`
