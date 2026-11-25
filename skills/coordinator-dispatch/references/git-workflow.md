# Git workflow (coordinator + workers)

This file is the source of truth for the git workflow. SKILL.md, the worker protocol, the brief template, the wrap-up checklist and the pi worker doc all only point here; none of them keeps its own copy.
When the project has its own git conventions (`AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`), the project wins, and this file only fills in what the project does not cover.

## Contents
1. Principles and division of labor · 2. The full flow of one workstream · 3. Merging several workstreams · 4. Enforcement · 5. Writing it into the project's AGENTS.md · 6. Failures

## 1. Principles and division of labor

**One worker = one worktree = one branch `w/<name>`.** A worker manages its own branch; the coordinator manages everything shared.

| Operation | Worker | Coordinator |
|---|---|---|
| add / commit / amend / reset / stash on its own branch | ✅ | — |
| `git push -u origin w/<name>`; `--force-with-lease` after a rebase | ✅ own branch only | — |
| fetch, rebase or merge the base branch into its own branch | ✅ | — |
| Open a PR (`gh pr create`), reply to review comments in the PR | ✅ | — |
| Create worktrees and branches (`scripts/git/worktree.sh new`) | ❌ | ✅ |
| Push to the main branch or a protected branch (main / master / develop / trunk / release/* / production), push to someone else's branch | ❌ | ✅ |
| Plain `--force` (without lease), delete remote branches, `--all` / `--tags` / `--mirror` | ❌ | Per project rules |
| Merge PRs (`gh pr merge`), merge into the base branch | ❌ | ✅ |
| Delete or rename branches, tag, release, change git config, change repository settings | ❌ | ✅ |
| Delete worktrees (`scripts/git/worktree.sh clean`) | ❌ | ✅ |

Why split it this way: committing and pushing are part of the worker's job. The worker knows best what each step changed and writes the most accurate commit messages; having the coordinator write them loses information. Merging, releasing and deleting branches affect everyone, so they must have a single entry point.

## 2. The full flow of one workstream

| # | Who | What | Command |
|---|---|---|---|
| 1 | Coordinator | **Open a workstream**: cut a branch and worktree from the latest base branch, record the branch name in the board's worker table | `scripts/git/worktree.sh new <repo> <name>` (pi workers use `pi-worker start <name> --repo <repo>`, which calls the same script) -> `<repo>.worktrees/<name>`, branch `w/<name>`, base branch defaults to `origin/<default-branch>` |
| 2 | Worker | **Commit in small steps**: one thing per commit; run the relevant tests before committing | `git add <files-you-changed> && git commit` (commit format below) |
| 3 | Worker | **Push**: set the upstream on the first push; then push at each milestone, and once more before reporting done. Skip if there is no remote | `git push -u origin w/<name>`, then `git push` |
| 4 | Worker | **Sync**: rebase onto the latest base branch before reporting done. Resolve conflicts only in files you changed; if a conflict involves someone else's files, stop and report to the coordinator | `git fetch origin && git rebase origin/main`, then `git push --force-with-lease` |
| 5 | Worker | **Open a PR** (if the project uses PRs): a draft PR whose body says what was done, how it was verified, what was not done, and which issue it relates to | `gh pr create --draft --base main --head w/<name> --title "<same as commit format>" --body-file <file>` |
| 6 | Worker | **Report done**: include the branch name, PR link, verification commands and results | Claude Code workers send a cross-session message; pi workers call `report_to_claude(status=done)` |
| 7 | Coordinator | **Acceptance review**: read all the changes, cheap review first then final review, rerun the tests yourself. If it fails, send it back; the worker **adds commits on the same branch**, no new branch | `git diff origin/main...w/<name>`; `pi-worker review <name>`; `wrap-up-checklist.md` |
| 8 | Coordinator | **Merge**: only when CI is green and it has been rebased onto the latest base branch. Use the project's merge method; if the project does not say, squash | `gh pr ready <n> && gh pr merge <n> --squash`; without a PR: `git merge --ff-only w/<name> && git push origin main` |
| 9 | Coordinator | **Wrap up**: delete the worktree, the local branch and the remote branch, record the merge commit on the board | `scripts/git/worktree.sh clean <repo> <name> --delete-remote` (pi workers use `pi-worker clean <name> --delete-remote`) |

**Commit format** (when the project has none):

```
<type>(<scope>): <one sentence, imperative, ≤ 72 characters>

<why it changed and how it was verified; one item per line>

Worker: <worker name> (<claude|pi>, <model>)
```

`type` is one of feat / fix / refactor / test / docs / chore. Never commit: secrets, `.env*`, generated files, large binaries, handoff pages and batch files (those live in the state directory of the coordinator's main checkout, not in the worktree).

## 3. Merging several workstreams

- **Merge one at a time.** Keep a "merge queue" on the board; whichever passes acceptance review first merges first.
- After each merge, tell the other running workers to rebase: Claude Code workers get a cross-session message, pi workers get `pi-worker steer <name> "Base branch updated: git fetch && git rebase origin/main, then push --force-with-lease"`.
- If two workstreams changed the same files: the one merged later has its own worker resolve the conflicts by rebasing; the coordinator does not resolve them for it. If the conflicts are severe, serialize: wait for the first to merge before opening the next.
- If CI goes red on the base branch after a merge, the coordinator deals with it immediately: first revert the workstream just merged, then open a fix workstream. Do not leave a broken base branch hanging.

## 4. Enforcement (not relying on good behavior)

Both kinds of worker use the **same** rule code: `scripts/git/git-policy.ts`. The case table `scripts/git/git-policy.test.ts` covers twenty-odd cases each for allowed and blocked.

| Worker | How it takes effect | What happens when blocked |
|---|---|---|
| pi worker | The extension `scripts/pi/claude-bridge.ts` checks every bash command before it runs; the branch comes from `PI_WORKER_BRANCH`, written by `pi-worker start` | The command does not run and pi receives the reason; `GIT blocked: …` appears in the coordinator's watch. If the worker later leaves its branch, `GIT worker left its branch` appears and pi is reminded to switch back |
| Claude Code worker | When `spawn-worker.sh` finds the working directory on a non-protected branch, it automatically adds `--settings` to claude, attaching the PreToolUse hook `scripts/git/claude-hook.ts`, and pins the branch with `CD_WORKER_BRANCH` | The hook blocks with exit code 2 and the reason is shown to the model. After switching to another branch, only switching back and read-only commands are allowed |
| Coordinator | No hook | — |

Why pin the branch: if the check were based on "whichever branch you are on now", a worker could bypass the rules by running `git switch main` first.
The project can also turn on branch protection on the remote (no direct pushes to main, PRs required, CI must be green) as a last line of defense; it does not conflict with any of the above.

## 5. Writing it into the project's AGENTS.md

The first thing a worker reads is the project's own instructions. pi automatically loads `AGENTS.md` and `CLAUDE.md` in the worktree; Claude Code reads `CLAUDE.md`, which can pull in `AGENTS.md` with a line `@AGENTS.md`. So:

1. Before opening the first workstream, the coordinator checks whether `AGENTS.md` at the project root has a "Git" section. If not, add one from `references/agents-md-template.md`, fill in this project's actual base branch, merge method and commit format, and add a line `@AGENTS.md` to `CLAUDE.md`.
2. This change follows the same flow: the coordinator commits it on the main branch itself (it counts as "changing repository settings"), and tells the human.
3. Briefs only contain the workstream's own branch name and worktree path. Do not copy the general git rules again; just write "Follow the Git section of AGENTS.md".

## 6. Failures

| If | Then |
|---|---|
| A rebase conflict is in someone else's files | The worker runs `git rebase --abort` and reports to the coordinator; the coordinator decides whether to serialize or re-split the work |
| A worker committed a secret by mistake | Stop it immediately and do not push again. Not pushed yet: the worker drops that commit with `git reset`. Already pushed: the coordinator rotates the secret, deletes the remote branch, cleans history per the project's process, and tells the human |
| `GIT blocked` appears in the watch | Check the reason: if the worker used the wrong command, reply with the correct way; if the work genuinely needs that operation (e.g. tagging), the coordinator does it |
| `clean` says it is not merged | First confirm it really was merged: `gh pr view w/<name>`. After a squash merge `git cherry` cannot recognize it, so the script checks the PR state again; if it still fails and you have confirmed it is fine, add `--force` |
| `clean` says there are uncommitted changes | First ask the worker whether those changes are wanted. If so, have the worker commit and push; add `--force` only when you are sure they are not wanted |
| A local repository with no remote | Skip pushing and PRs; merge with `git merge --ff-only w/<name>`, and the base branch is the branch the main worktree is on |
| Not enough disk to open a new worktree | First clean workstreams that are already merged; every worktree takes a full copy of the workspace's space |
