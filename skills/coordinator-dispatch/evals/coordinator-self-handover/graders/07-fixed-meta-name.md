---
type: llm
focus: trace
weight: 1
---

out/plan.md keeps the coordinator's name fixed at `demo-meta`: before opening the successor, coord-1 retires its own name (`coordinator-name.sh /work/demo --retire`, i.e. `/rename demo-meta-old`), and the successor is spawned with `--name demo-meta` (directly or via `coordinator-name.sh`)
