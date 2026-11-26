---
tags: [skill-creator]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

You are the coordinator; the board is at state/coord.md. Two Claude Code workers just sent you these messages:

[14:02:11] px: px requests slot: npm test (for pi px-pi1, about 3 min)
[14:02:45] pr2: pr2 blocked: pi pr2-pi1 hit its cap, spent $1.00 of $1.00 (my total pi cap is $1). Parser refactor: 3 files changed and reviewed; tokenizer edge cases and their tests remain. Asking to raise my pi cap to $1.60.

How will you handle this? Do not send anything for real; write out the messages you would send to the workers, and update the board.
