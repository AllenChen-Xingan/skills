# Template: common rules for a batch of workers

One `common.md` per batch. The first line of every worker's brief points to it. Shared rules live in one place only: if each brief carries its own copy, a change to one gets missed in the others.

Hard constraints already in the project onboarding doc (git workflow, testing rules, privacy) get **only a pointer** here, not a restatement. This file adds the rules specific to being a worker.

`scripts/new-batch.py` copies the content between the two markers below into `<batch>/common.md`.

## Template

<!-- template:start -->
# Common rules for this batch of workers ({{DATE}} · batch {{BATCH_NAME}})

You are a worker session on this project. The coordinator is session `{{BOSS}}`. Workers in this batch: {{PEERS}}.

## The human's words this time (source of truth for intent, verbatim)
> <paste the human's words>

## Read first
1. The project onboarding doc (e.g. `CLAUDE.md`), especially the git, testing and privacy rules
2. Your own brief, `{{BATCH}}/<your window name>.md`
3. The full worker protocol, if the coordinator gave you its path: check-in · reports · slots · handoff page · wrap-up

## Rules
1. **Talk to the human only through the coordinator.** Send requests for anything from the human (logins, verification codes, choices) to the coordinator, saying what you need and why. Ask once per item and wait for the reply.
2. **Workers in the same batch may ask each other questions directly** (inter-session messages), but never edit each other's files.
3. **Write only the files your brief assigns to you.** **No git writes of any kind** (add / commit / push / branch / merge); commits belong to the coordinator.
4. **There is one heavy-job slot for the whole machine** (full builds, full test runs, anything else that saturates the machine):
   - Request: "<window> requesting slot: <command>"
   - Run only after you receive "<window> slot is yours". As soon as you finish: "<window> returning slot: <one-line result>"
5. **Runs that pop up windows or grab the foreground**: <fill in per project, e.g. under 1 minute per run is fine; longer runs need the human's OK via the coordinator>. If the human closes the window, let it stay closed. Never block it or reopen it.
6. **Handoff page**: `{{HANDOFF_DIR}}/<your window name>.md` (current task · progress · next step · log). Log one line for everything you do, as you do it.
7. **Reports**: send the coordinator one sentence whenever you finish a stage, get blocked, or find something unexpected. For anything over ~300 words, write a file and send only the path + a one-line summary.
8. **Decisions for the human** go in a "Pending decisions" list (question · options · cost · recommendation) on your handoff page. Don't decide for the human.
9. **You may dispatch your own subagents** for reading material, drafting and self-review. They are bound by these same rules: include the rules verbatim in their prompt.
10. **Wrap up after each natural chunk of work**: mark your handoff page "wrapped up" and report "<window> ready to wrap". The coordinator closes the window and starts a fresh worker to continue.
<!-- template:end -->
