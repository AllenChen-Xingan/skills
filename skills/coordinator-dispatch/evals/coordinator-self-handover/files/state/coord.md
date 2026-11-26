# Coordinator board

> Coordinator window: `coord-1`. tmux workspace: `demo-ws`. Batch: `_tmp/b4`. Handoff pages: `state/handoff/`. Session table: `state/sessions.md`.
> Red lines: `AGENTS.md` section "Hard rules"; secrets rules: `_tmp/b4/common.md` rule 1 (keys live in `.env.local`, never in chat or files).

## Workers

| Window | Task | Brief | Handoff page | Cost (pi) | Status |
|---|---|---|---|---|---|
| api-2 | REST endpoints for export (rotated from api at 612k) | _tmp/b4/api.md | state/handoff/api.md | $1.10/$2 | in progress, feature 3 of 3 |
| ui | Settings page | _tmp/b4/ui.md | state/handoff/ui.md | $0.40/$1 | sent back 16:05: missing validation tests |

## Slots

| Slot | Current holder |
|---|---|
| Heavy build / full test run (1) | coordinator itself: benchmark `scripts/bench.sh --full` started 16:10, output `_tmp/b4/bench.log`, about 25 min left, run in background |

Queue: api-2 (cargo test --release, about 6 min)

## Locks
- `state/.merge.lock` held by coordinator since 16:12, for merging ui once the benchmark is green

## Pending decisions
1. Keep the v1 export format for one more release? A. yes (recommended) B. drop it now

## Spend
- Batch pi spend so far: $1.50; coordinator's own session about 520k context
