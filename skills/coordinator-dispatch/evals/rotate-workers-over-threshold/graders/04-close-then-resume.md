---
type: llm
focus: trace
weight: 1
---

out/plan.md closes a rotated window with close-worker.sh only after the worker replied "ready to close", then opens the replacement with spawn-worker.sh in the same worktree, with a resume message that points to the brief, the common rules and the handoff page
