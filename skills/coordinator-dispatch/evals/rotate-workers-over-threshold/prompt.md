---
tags: [skill-creator]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

You are the coordinator. Check how big the workers' contexts have got and deal with whatever needs dealing with. The project main dir is /work/demo; for this demo the Claude Code session logs are in fake-projects/ instead of ~/.claude/projects. tmux is not available here, so do not open or close any window for real: write each message you would send into out/msg-<window>.txt, put the commands you would run, in order, in out/plan.md, and update the board and the session table.

Input files: state/coord.md, state/sessions.md, state/handoff/api.md, state/handoff/docs.md, state/handoff/ui.md, state/handoff/lint.md, _tmp/b3/common.md, fake-projects/
