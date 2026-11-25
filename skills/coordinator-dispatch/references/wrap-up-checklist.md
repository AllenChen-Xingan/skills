# Acceptance review and wrap-up checklist (coordinator side)

Go through each item after a worker reports "ready to wrap up". **Spot-checking is not rereading its report** -- look at the files and rerun the checks it says it ran.

## 1. Acceptance review (if it fails, send back with the gaps spelled out)

- [ ] Review tier (cheap-first review): copy / UI-only changes get a light review; core-logic changes first get a cheap review (for pi workers, `scripts/pi-worker review <name>`; send back P0/P1 and have them fixed first), then a final review by the coordinator or a cross-model review
- [ ] Every file listed under "Deliverables" in the brief exists and is within the "Write only these files" allowlist (`git status` to check for out-of-bounds changes)
- [ ] Of the self-tests / checks it says it ran, rerun one or two yourself (if they need the slot, give yourself the slot first)
- [ ] The handoff page's "Status" says "wrapped up", and "Where I am" matches reality
- [ ] Hard rules: no secrets, personal information or raw chat text in the deliverables or handoff page (a rough scan: `grep -nE 'sk-|ghp_|api[_-]?(key|hash|secret)|@.+\.(com|edu|org)|\+[0-9]{6,}'`)
- [ ] git (`git-workflow.md` section 2): all commits are on `w/<name>`, main and other workers' branches untouched; rebased onto the latest base branch (`git rev-list --count w/<name>..origin/main` is 0); pushed (for pi workers check `unpushed: 0` in `pi-worker status`); commit messages follow the format and contain no changes from other workstreams; `git diff origin/main...w/<name>` contains only allowlisted files
- [ ] Slot returned (the board's slot table is empty or has a new holder)
- [ ] pi workers: cost copied into the board's Workers table; `pi-worker stop` run (review workers must be stopped too)
- [ ] Items that need a human decision moved into the board's "Pending decisions", each with options and a recommendation
- [ ] Out-of-scope "hand-offs" recorded under the board's "Findings" or opened as new tasks

Send-back message format: `<window> send-back: 1) <gap> 2) <gap>; fix and report ready to wrap up again`

## 2. Wrap up

1. `scripts/close-worker.sh <ws> <window>`: first read the printed pane tail and confirm no command is running and no question is unanswered, then confirm closing the window
2. Board Workers table: change status to "done, wrapped up (window closed)" + anything left for a human to do (e.g. "human listening test remaining")
3. Remove this worker's line from the progress board or mark it done
4. Merge (`git-workflow.md` section 2, steps 8-9): merge one at a time; merge only when CI is green; after merging run `scripts/git/worktree.sh clean <repo> <name> --delete-remote` (pi workers: `pi-worker clean`); record the merge commit on the board; tell the other running workers to rebase
5. Tell the human in one line: what was done · deliverable paths · how many items wait for their decision
6. After the whole batch is wrapped up: keep the batch directory for traceability (don't delete it); update the board's "Top / Next"

## 3. Handover (when the coordinator itself is leaving)

- Change the coordinator session name in the board header
- Send each in-progress worker one line: "coordinator is now <new session name>, report to it from now on"
- The new coordinator starts by reading the board + the handoff page of each in-progress worker, then cross-checks with `list-workers.sh`
