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
5. **Runs that open pop-up windows / steal focus**: <fill in per project rules, e.g.: up to 1 minute per run may go ahead directly; longer, ask the human through the coordinator first>; if the human closes the window, let it close -- never intercept or reopen it
6. **Handoff page**: `{{HANDOFF_DIR}}/<your window>.md` (Working on · Where I am · Next · Log); log one line the moment you do anything
7. **Report**: send the coordinator one line when you finish a stage, get blocked, or find something unexpected; anything longer than about 300 words goes in a file, and the message gives only the path + a one-line summary
8. **Things a human must decide** go on a "Needs a human decision" list (question · options · cost · recommendation) on your handoff page; don't decide for them
9. **You may dispatch your own sub-agents** to read material, draft and self-review; sub-agents are bound by the same rules -- copy the rules verbatim into their prompt
10. **Wrap up once a natural chunk of work is done**: write "wrapped up" on your handoff page and report "<window> ready to wrap up, branch w/<window>, PR <link|none>"; the coordinator closes the window and starts a fresh worker to take over
<!-- template:end -->
