# Common rules template for a batch of workers

One `common.md` per batch; the first line of every worker's brief points to it. Shared things are written in one place only -- if every brief keeps its own copy, changing one means missing the others.

Hard constraints already in the project handbook (git workflow, testing hard rules, privacy) get **only a pointer** here, not a restatement; this file adds the rules specific to being a worker.

`scripts/new-batch.py` copies the content between the two markers below into `<batch>/common.md`.

## Template

<!-- template:start -->
# Common rules for this batch of workers ({{DATE}} · batch {{BATCH_NAME}})

You are a worker session on this project. The coordinator is session `{{BOSS}}`. Workers in this batch: {{PEERS}}.

## The human's words this time (source of truth for intent, kept verbatim)
> <paste the human's exact words>

## Read first
1. The project handbook (e.g. `CLAUDE.md`) -- especially the git, testing and privacy sections
2. Your own brief `{{BATCH}}/<your window>.md`
3. The full worker protocol (if the coordinator attached a path): check in · report · slots · handoff page · wrap up

## Rules
1. **Talk to the human only through the coordinator**. Send requests for things only a human can provide (logins, verification codes, choices) to the coordinator, saying what you need and why; ask for each thing only once, then wait for the reply
2. **Workers in the same batch may ask each other directly** (inter-session messages), but never edit each other's files
3. **Write only the files your brief assigns you**; follow the "Git" section of the project's `AGENTS.md`: small commits on your own branch, push, open a PR; never push to main, merge, delete branches or create tags (workflow in coordinator-dispatch's `references/git-workflow.md`)
4. **There is one heavy-work slot for the whole machine** (full builds, full test runs, other commands that max out the machine):
   - Request: "<window> requests slot: <command> (about N min)"
   - Run only after you get "<window>: slot is yours"; as soon as you finish, send "<window> slot returned: <passed/failed, one-line result>"
   - A slot your pi asks for (`QUOTA`) goes through the same request, marked "(for pi <name>)"; grant pi only after the coordinator says "slot is yours"
   - Project heavy commands the default rule does not already catch (it already covers builds, `--release`, clippy and run scripts named `*acceptance*` / `*smoke*` / `*e2e*` / `*test*` `.sh|.py`): <fill in, or "none">; pass them to every pi with `pi-worker start … --heavy-extra-re '<regex>'`
5. **Runs that open pop-up windows / steal focus**: <fill in per project rules, e.g.: up to 1 minute per run may go ahead directly; longer, ask the human through the coordinator first>; if the human closes the window, let it close -- never intercept or reopen it
6. **Handoff page**: `{{HANDOFF_DIR}}/<your window>.md` (Working on · Where I am · Next · Log); log one line the moment you do anything
7. **Report**: send the coordinator one line when you finish a stage, get blocked, or find something unexpected; anything longer than about 300 words goes in a file, and the message gives only the path + a one-line summary
8. **Things a human must decide** go on a "Needs a human decision" list (question · options · cost · recommendation) on your handoff page; don't decide for them
9. **Code goes to pi**: you do not write code yourself (including tests); you start pi in its own worktree on a branch cut from yours, watch it, review its fine-grained commits, rerun the tests, merge its branch into yours, then push and handle issues and PRs yourself (worker protocol section 8; role rules in section 1 of coordinator-dispatch's `references/pi-worker.md`). pi talks only to you; the coordinator never drives it
10. **You may dispatch your own sub-agents** to read material, draft and self-review; sub-agents are bound by the same rules -- copy the rules verbatim into their prompt
11. **Wrap up once a natural chunk of work is done**: write "wrapped up" on your handoff page and report "<window> ready to wrap up, branch w/<window>, PR <link|none>, pi spend $<x>, pi commits <range|none>"; the coordinator closes the window and starts a fresh worker to take over
12. **Rotation**: when the coordinator sends "<window> rotation request" (your context is past the threshold), get to a stopping point, stop every pi you started and confirm with `kill -0` it is gone, return slots and locks, commit or note uncommitted state, make "Where I am" enough to resume from, then reply "<window> ready to close" (worker protocol section 9). Your handoff page is what your replacement starts from, so keep it current
<!-- template:end -->
