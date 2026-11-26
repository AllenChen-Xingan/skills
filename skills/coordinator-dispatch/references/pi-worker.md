# pi: the coding hand of a Claude Code worker

pi (`@earendil-works/pi-coding-agent`) runs in the background in RPC mode, backed by a cheap model on isoquant.ai (default `isoquant/deepseek-v4.1-flash-1017-fast`).
It does not live in a tmux window and does not use cross-session messages. The **Claude Code worker that started it** talks to it through `scripts/pi-worker` and Claude Code's **Monitor** tool.

This file is the source of truth for who starts pi, what pi does (including what it may do in git), and what stays with the Claude Code worker. SKILL.md, the worker protocol, the brief and common-rules templates, the board template, the wrap-up checklist and the git workflow only point here.

## Contents
1. Roles: three tiers (and pi's git rules) · 2. One-time setup · 3. How a Claude Code worker uses pi · 4. Events and what the worker does · 5. pi brief template · 6. Setting the budget · 7. Failures

## 1. Roles: three tiers

**Coordinator -> Claude Code worker -> pi.** The human's words: "code goes to pi; everything else is done as usual", "pi is dispatched by the Claude Code worker, not by the coordinator; pi is just a hand that does the work", "pi only writes code", and later "pi can commit, and commits can be very fine-grained, but PRs or issues need a dedicated Claude Code worker; commits are there to make rollback and the like easy".

| Tier | Starts | Does | Does not |
|---|---|---|---|
| Coordinator | Claude Code workers only (`spawn-worker.sh`) | Splits work, writes briefs (including each worker's pi budget cap), hands out slots, does acceptance review, merges, talks to the human | Never starts, steers, answers, grants or stops pi itself; never runs `pi-worker` |
| Claude Code worker | pi, with `scripts/pi-worker start <worker>-pi<n> --repo <main repo> --base w/<worker> --task-file … --budget …`, watched with Monitor | Everything except writing code: research, running jobs (heavy builds, experiments, cloud machines), writing pi's brief, answering pi, getting slots for pi from the coordinator, reviewing pi's commits, rerunning the tests itself, sending back with `pi-worker follow`, merging pi's branch into its own, opening issues, pushing, opening the PR, reporting to the coordinator (including pi spend) | Does not write or change code itself, including test code; does not edit pi's worktree while pi runs; does not merge into main |
| pi | Nothing | **Only writes code** (product code and test code) from its brief, runs the targeted tests named there, **commits each small step on its own branch**, reports with `report_to_claude`, asks with `ask_claude`. Both go to the Claude Code worker that started it | Does not research, run cloud machines or heavy jobs on its own, review, coordinate or dispatch work; does not push, open or edit issues or PRs, merge, delete branches or touch any branch but its own; never talks to the coordinator or the human |

Why: cheaper models hold up well on one well-specified coding task, but tend to break down when they have to research, judge or coordinate. So pi only writes code, the Claude Code worker owns the workstream, and the coordinator owns the batch.

Rules that follow from the table:
- **Code means pi.** When a workstream needs code written or changed, the Claude Code worker hands that part to pi. Non-code files (docs, briefs, handoff pages) are written by the worker as usual.
- **One pi at a time per worker**: each pi branches from the worker's current tip, and two at once would conflict when merged back. While pi works, the worker does not change the files pi owns on its own branch either. If two coding tasks are independent, run them one after another, or ask the coordinator for a second workstream.
- **pi works in its own worktree on its own branch** (`w/<worker>-pi<n>`, cut from the worker's branch `w/<worker>`, under `<main repo>.worktrees/<worker>-pi<n>`). Reason: the worker's Claude Code session may run a PostToolUse auto-commit hook in its worktree, which would commit pi's unreviewed, half-written code under the worker's name. No Claude session runs in pi's worktree, so no hook touches it.
- **pi commits fine-grained.** Each small logical step (one function, one test, one fix) is one commit, because commits are rollback points: the worker can review step by step and drop or revert a bad step without losing the rest. Every pi commit carries two trailers, `Agent: pi` and `Model: <model>`. `claude-bridge.ts` tells pi the exact command with its model filled in (from `PI_WORKER_COMMIT_MODEL`, which `pi-worker start` sets to `--model`) and blocks a `git commit` that lacks `Agent: pi` (`--amend --no-edit` is allowed). The extension does not check the `Model:` value; the worker checks it at acceptance.
- **Issues, pushing and PRs belong only to the Claude Code worker; merging into main belongs only to the coordinator.** The extension blocks every `git push` from pi and every `gh pr` / `gh issue` command except read-only ones (view, list, status, diff, checks), on top of the rules that apply to all workers (`git-workflow.md`).
- **Worker acceptance of pi's work**: read pi's commit range (`git -C <main repo> log -p w/<worker>..w/<worker>-pi<n>`), rerun the tests yourself in pi's worktree or your own, then bring pi's branch into yours from your own worktree with `git merge --ff-only w/<worker>-pi<n>` (if your branch moved on meanwhile, `git merge --no-ff w/<worker>-pi<n>`). Record the pi commit range (`<first>..<last>`) and pi spend on your handoff page, then `pi-worker clean <worker>-pi<n>`, which removes pi's worktree and branch once they are merged into `w/<worker>`. Only then push and open or update the PR.
- **Fallback, `--cwd <worker's worktree>`**: pi runs in the worker's worktree on `w/<worker>`. Use it only if the worker's worktree has no auto-commit hook (check the project's `.claude/settings*.json` hooks); otherwise the hook commits pi's half-written code under the worker's name. pi's commit rules are the same; there is nothing to merge or clean afterwards.
- **pi never reaches past its worker.** pi's `ASK` that needs the human goes up as the worker's own "needs a human decision" item; pi's `QUOTA` goes up as the worker's own slot request (section 4).

## 2. One-time setup (skip if already installed)

```bash
npm i -g @earendil-works/pi-coding-agent
cp scripts/pi/models.isoquant.json ~/.pi/agent/models.json     # if other providers already exist, merge the providers field instead of overwriting
# the human stores the key (it never goes into the chat):
#   ! mkdir -p ~/.config/isoquant && read -s k && echo "ISOQUANT_API_KEY=$k" > ~/.config/isoquant/.env && chmod 600 ~/.config/isoquant/.env
pi --list-models isoquant                                       # seeing the models is enough
bash scripts/pi/test/e2e-mock.sh                                # zero-cost self-test, should print PASS
```

The config has zero data retention turned on (`Isoquant-ZDR: required`), and the key is read from the file only at request time. The coordinator checks setup once before the batch; if it is missing, it asks the human (setup is not a worker's job).

## 3. How a Claude Code worker uses pi

The coordinator's seven steps (SKILL.md) do not change: it dispatches Claude Code workers and puts two things in each brief, the absolute path of `scripts/pi-worker` and the worker's **pi budget cap** (section 6). Everything below is done by the Claude Code worker.

| Step | What the worker does |
|---|---|
| 1 Write pi's brief | Write `<batch>/pi-<worker>-<n>.md` from the template in section 5, **outside any worktree** so it is never committed. pi sees only `AGENTS.md` / `CLAUDE.md` in its worktree plus this brief, so put every key point in the brief: files to change, the tests to run, what done means. Commit your own branch first: pi's branch starts from its current tip |
| 2 Start pi | `<path>/pi-worker start <worker>-pi<n> --repo <main repo> --base w/<worker> --task-file <batch>/pi-<worker>-<n>.md --budget <usd>`. Prefix the name with the worker's own name (pi state is machine-wide). This creates pi's own worktree `<main repo>.worktrees/<worker>-pi<n>` on branch `w/<worker>-pi<n>` from your branch; the extension pins that branch (section 1; `--cwd` only as the fallback described there) |
| 3 Watch | **Monitor** on `<path>/pi-worker watch <worker>-pi<n>` with `timeout_ms` 1800000; re-attach when it expires (watch resumes from its cursor, with no loss or duplication). Log "started pi <name>, cap $<x>" on the handoff page |
| 4 Handle events | Section 4. Meanwhile do non-code work that does not touch pi's files |
| 5 Review | After `REPORT done` plus `SETTLED`: read pi's commits one by one (`git -C <main repo> log -p w/<worker>..w/<worker>-pi<n>`; `git -C <pi worktree> status` must be clean), check each commit has the `Agent: pi` / `Model:` trailers and stayed inside pi's allowlist, rerun the tests yourself. Gaps go back in one message: `pi-worker follow <name> "1) … 2) …"`; pi fixes them in new commits. A bad step can be dropped by having pi `git revert` it. Repeat until clean |
| 6 Take it into your branch | `pi-worker stop <name>` -> in your own worktree `git merge --ff-only w/<worker>-pi<n>` (or `--no-ff` if your branch moved on) -> write the pi commit range and spend on your handoff page -> `pi-worker clean <name>` -> push -> open or update the PR (section 1) |
| 7 Report | Report to the coordinator as usual (`worker-protocol.md` section 6), adding pi spend and range: `pi <name> $<spent>/$<cap>, commits <first>..<last>` (from `pi-worker status`) |

**What the extension enforces** (`scripts/pi/claude-bridge.ts`), not good behavior:
- git (`scripts/git/git-policy.ts`, role `pi`): any `git push`, `gh pr` / `gh issue` writes, merging PRs, deleting branches, tagging, changing config and editing worktrees are blocked, and so is a `git commit` without the `Agent: pi` trailer (`GIT blocked` appears in the watch); leaving the pinned branch produces `GIT worker left its branch`. Commits on pi's own branch are allowed
- Heavy-work commands stop and wait for `grant`, and the slot is returned automatically when they finish. The rule lives in one place, `scripts/pi/heavy.ts` (table-tested by `node scripts/pi/heavy.test.ts`). By default it covers:
  - toolchain builds and full test runs, matched anywhere in the command: `make`, `ninja`, `cmake --build`, `cargo build|test|bench|clippy|nextest`, `zig build`, `xcodebuild`, `swift build|test`, `npm|pnpm|yarn|bun [run] build|test`, `pytest`, `tox`, `go build|test`, `gradle(w)`, `mvn`, `bazel`, `docker build`
  - any `--release` build or run
  - the project's own test scripts: a `.sh` / `.py` whose file name starts with, or has after `-` `_` `.`, one of `acceptance`, `smoke`, `e2e`, `integration`, `test(s)` (`cli-acceptance.sh`, `run-tests.sh`, `smoke_test.py`, `e2e-mock.sh`), **only when run**: in command position, optionally behind `VAR=x`, `env`, `time`, `timeout N`, `nice`, `nohup`, `sudo` and a `bash|sh|zsh|python|uv run` launcher. `bash scripts/cli-acceptance.sh` and `./scripts/smoke.sh` wait for a slot; `cat`, `grep`, `ls`, `sed -n`, `git add` on the same file do not

  **Adding a project's own heavy commands**: pass `--heavy-extra-re RE` to `start` (or export `PI_WORKER_HEAVY_EXTRA_RE`); it is added to the default, so you only name what the default misses, e.g. `--heavy-extra-re '\bjust\s+(bench|ci)\b|\bscripts/(bench|load)\.sh\b'`. If every pi of a project needs the same addition, write it into the project's common rules so each worker passes it. `--heavy-re RE` (or `PI_WORKER_HEAVY_RE`) **replaces** the default entirely; use it only when the default is wrong for the project, and remember it also drops the script and `--release` rules. A false positive only costs one `grant`; a miss lets pi run a full suite without the slot, so add rather than narrow
- At 80% of the cost cap it warns; at 100% it aborts the current turn and blocks all tool calls until the cap is raised with `pi-worker budget`

## 4. Events and what the worker does

watch prints one event per line, prefixed with the time.

| Event | What the Claude Code worker does |
|---|---|
| `REPORT progress/done/blocked/failed: …` | Log it on the handoff page; done goes to review (section 3 step 5); for blocked/failed, look at the reason and reply with `steer` or `follow` |
| `ASK id=<id>: …` | If you can answer it (read code, check the brief), `pi-worker answer <name> <id> "…"`. If it needs a human decision, add it to your handoff page's "Needs a human decision" list, report it to the coordinator, and answer pi "Go with the conservative option for now; it is on the pending list". If there is no answer within 20 minutes, pi picks the conservative option itself |
| `QUOTA id=<id>: <command>` | Do not grant on your own. Send the coordinator the usual slot request, `<window> requests slot: <command> (for pi <name>, about N min)`. When you receive "slot is yours", `pi-worker grant <name> <id>`. If the command should not run, `pi-worker deny <name> <id> "reason/alternative"` and tell the coordinator to drop the request. pi waits up to 60 minutes |
| `QUOTA_RETURN passed/failed` | Return the slot to the coordinator at once: `<window> slot returned: <passed/failed, one line>` |
| `BUDGET 80% used` | Estimate what is left; if it fits inside your pi cap from the brief, raise it with `pi-worker budget <name> <usd>`; if it would go over that cap, ask the coordinator first |
| `BUDGET exceeded` + `SETTLED (aborted)` | Check `status` to judge whether it is worth continuing. Within your cap: `budget`, then `follow "continue"`. Over your cap: ask the coordinator with the spend so far and what is left. If it is not worth it: stop pi and split the task smaller |
| `SPEND $x of $y` | Cumulative cost at the end of each turn; put the latest figure in your next report |
| `TOOL_ERROR` / `LLM_ERROR` / `RETRY_FAILED` / `CMD_FAIL` / `EXT_ERROR` | Ignore occasional ones; if they keep coming, check the logs with `status`, and `abort` if necessary |
| `GIT blocked: <command> — <reason>` | Usually pi switches to the right approach itself (for example adds the trailers). If it recurs, `steer` it: "Commit on your branch with the Agent/Model trailers; never push or open PRs/issues; I do that". If the work genuinely needs a push, issue or PR, you do it; merging into main is the coordinator's |
| `GIT worker left its branch` | `steer <name> "git switch w/<worker>-pi<n>, and stay on it"` |
| `SETTLED` | pi is idle: if there was no `REPORT done`, it finished without reporting; `follow "Report done as the brief says"` |
| `EXITED code=N` | The process exited; if it was not caused by `stop`, check `~/.local/state/pi-worker/<name>/stderr.log` |

Two ways to interject: `steer` inserts after the current tool step finishes and before the next model call (for course correction); `follow` is delivered after the current turn finishes (for sending back; when idle it starts a new turn).

`pi-worker review` (a read-only pi reviewer) is **not** part of this flow: pi does not review. The worker reviews pi's diff itself; a cheap first review round, when wanted, is a cheaper Claude subagent or a cross-model review (`wrap-up-checklist.md`).

## 5. pi brief template (written by the Claude Code worker)

```markdown
# pi brief: <worker>-pi<n>

## Who you are
You are pi, the coding hand of Claude Code worker `<worker>`. You only write code (product code and tests) for the task below.
Report progress with report_to_claude and ask with ask_claude; both go to `<worker>`. Do not contact anyone else.
You work in `<pi worktree>` on your own branch `w/<worker>-pi<n>`. Stay on this branch.

## Task
- Goal: ……
- Change only these files / directories: …… (touch nothing else)
- Out of scope: …… (no research beyond the code you need to read, no refactors outside the task)

## Read first
- <path>: why to read it

## Check your work (run these yourself before reporting done)
- `<targeted test command>` passes (heavy commands wait for a slot automatically; do not work around it)
- ……

## Commit
- Commit each small logical step (one function, one test, one fix) on your branch; commits are rollback points
- `git add <files> && git commit -m "<type>(<scope>): <what>" --trailer "Agent: pi" --trailer "Model: <model>"`
- To undo a step, `git revert <commit>`; do not rewrite history `<worker>` has already reviewed

## Do not
- Push, open or edit issues or PRs, merge, delete branches or switch branches: `<worker>` reviews your commits and does all of that
- Start long jobs, experiments, benchmarks or remote machines

## When done
Call report_to_claude(status=done) once: your commits (`git log --oneline <base>..HEAD`), which commands you ran and their results, anything left undone. Leave no uncommitted changes.
```

## 6. Setting the budget

- Prices (per million tokens): input $0.035, cache hit $0.005, output $0.37. Most of the cost comes from rereading context
- Starting points per pi task: small change $0.20, single feature $1, larger feature $3
- **Who sets what**: the coordinator writes each Claude Code worker's total pi cap in its brief; the worker sets `--budget` per pi task inside that cap and asks the coordinator before going over it
- Going over budget is itself a signal: usually pi's brief is unclear or the task is too big. Split it smaller first, then consider adding money
- The worker reports pi spend at each stage and at wrap-up; the coordinator copies it into the "Cost" column of the board's worker table

## 7. Failures (handled by the Claude Code worker)

| If | Then |
|---|---|
| `start` reports pi failed to start | Check `stderr.log`: model not found -> `pi --list-models isoquant`; key cannot be read -> report blocked to the coordinator, who asks the human to store the key as in section 2 |
| `start` prints `base=origin/main` (or another base) instead of `base=w/<worker>` | You left out `--base w/<worker>`; `pi-worker clean <name> --force` (nothing of value yet), then start again with `--base` |
| `start` says the worktree is on a protected branch (fallback `--cwd` only) | Your worktree is wrong; report blocked to the coordinator |
| `pi-worker clean` says the branch is not merged | You have not brought pi's branch into `w/<worker>` yet (section 1); merge it first, or if you are discarding pi's work on purpose, note that on the handoff page and add `--force` |
| Constant `RETRY` (429 / 5xx) | isoquant is short on capacity; `abort`, then `follow "continue"` after a few minutes, or restart with `--model` |
| `LLM_ERROR` 401/402/403 | Invalid key / insufficient balance / no access to that model: report blocked to the coordinator, do not retry |
| pi never calls report_to_claude and just stops when done | `SETTLED` still arrives; `follow` with "Report done as the brief says" |
| pi tries to get around the slot (splitting heavy work into differently named commands), or a heavy project command runs without a `QUOTA` line | Restart it with that command added through `--heavy-extra-re` (section 3); if it keeps happening, split the task smaller. If the miss is a common pattern (not one project's name), add it to `scripts/pi/heavy.ts` with a row in `heavy.test.ts` |
| pi keeps getting the same thing wrong after two send-backs | Stop it, rewrite the brief smaller and more concrete, start a new pi. Do not write the code yourself; if it still fails, report blocked to the coordinator |
| Monitor expires | Re-attach the same watch; it resumes from its cursor |
| The Claude Code worker session dies or is replaced | pi runtime state is in `~/.local/state/pi-worker/` and does not depend on the session; the replacement worker runs `pi-worker list`, finds `<worker>-pi*`, and re-attaches the watch; pi's commits are safe on `w/<worker>-pi<n>` |
