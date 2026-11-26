# Template for the "Git" section of a project's AGENTS.md

Put it in `AGENTS.md` at the project root (create one if there is none), then add a line `@AGENTS.md` to `CLAUDE.md`. pi reads `AGENTS.md` automatically and Claude Code reads it through the import in `CLAUDE.md`, so Claude Code workers and the pi they start see the same rules.
Replace each `<…>` with this project's actual value. The reasoning and details of the flow are in `git-workflow.md`; this only holds the part workers need to follow.

<!-- template:start -->
## Git

In this project a coordinating session (the coordinator) dispatches workers to work in parallel. Each worker works in its own worktree on its own branch `w/<name>`.

**You may (on your own branch only)**
- Commit in small steps: one thing per commit; run the relevant tests before committing: `<smallest-test-command>`
- Push: `git push -u origin w/<name>`; push at each milestone, and once more before reporting done
- Sync: before reporting done, run `git fetch origin && git rebase <base-branch, e.g. origin/main>`; after a rebase use `git push --force-with-lease`
- Open a PR: `gh pr create --draft --base <main-branch> --head w/<name>`; the body says what was done, how it was verified, and what was not done

**You may not**
- Push to `<main-branch>` or anyone else's branch; plain `--force` (without lease); delete remote branches
- Merge PRs, approve your own PR, tag, release
- Delete or rename branches, change git config, add or remove worktrees
- Switch to another branch to work (to look at another branch, use `git show <branch>:<path>` or `git diff`)

**Commit format**
```
<type>(<scope>): <one sentence, imperative>

<why it changed and how it was verified>

Worker: <your name> (claude, <model>)     <- pi writes the trailers "Agent: pi" and "Model: <model>" instead
```
type: feat / fix / refactor / test / docs / chore. Do not commit secrets, `.env*`, generated files, or `<other-paths-kept-out-of-the-repo>`.

**If you are pi** (started by a Claude Code worker through `pi-worker`): you only write code and run the tests your brief names. You work on your own branch `w/<worker>-pi<n>`; commit each small logical step there (commits are rollback points) with `--trailer "Agent: pi" --trailer "Model: <model>"`. Do not push, open issues or PRs, merge or switch branches; the worker that started you reviews your commits and does that. The push / PR / sync steps above are not yours. Your brief wins over this section.

**Conflicts**: resolve them only in files you changed; if a conflict involves someone else's files, run `git rebase --abort` and report to the coordinator.

**Merging**: the coordinator merges after acceptance review, using `<squash | rebase | merge>`. When sent back, add commits on the same branch; do not open a new branch.
<!-- template:end -->
