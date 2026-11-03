#!/usr/bin/env bash
# list-workers.sh — machine side of the progress board: windows + pane tails
# (+ the "Status/Progress" lines from each worker's handoff page, if a dir is given).
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: list-workers.sh <session> [options]

List every window in tmux session <session>: window name · current command · exited or not ·
last N non-blank lines of the pane. With --handoff-dir, also show the "Status" and "Progress"
lines from <dir>/<window>.md.

Options:
  --lines N          Pane-tail lines to print per window (default 5)
  --handoff-dir DIR  Handoff-page directory (file name = <window>.md)
  --window W         Show only this window
  -h, --help         Show this help
Example: list-workers.sh myws --lines 8 --handoff-dir "/path/with space/proj/state/handoff"
USAGE
}

LINES=5; HDIR=""; ONLY=""; POS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --lines) LINES="$2"; shift 2 ;;
    --handoff-dir) HDIR="$2"; shift 2 ;;
    --window) ONLY="$2"; shift 2 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done
[[ ${#POS[@]} -eq 1 ]] || { usage >&2; exit 1; }
SESSION="${POS[0]}"
tmux has-session -t "=$SESSION" 2>/dev/null || { echo "No such session: $SESSION" >&2; exit 1; }

tmux list-windows -t "=$SESSION" -F '#{window_name}	#{pane_current_command}	#{pane_dead}' |
while IFS=$'\t' read -r name cmd dead; do
  [[ -n "$ONLY" && "$name" != "$ONLY" ]] && continue
  state="running"; [[ "$dead" == "1" ]] && state="exited"
  echo "== $name · $cmd · $state"
  if [[ -n "$HDIR" && -f "$HDIR/$name.md" ]]; then
    grep -E '^\s*-?\s*\*\*(Status|Progress)' "$HDIR/$name.md" | head -n 4 | sed 's/^/   handoff /' || true
  fi
  tmux capture-pane -p -t "=$SESSION:$name" -S -200 2>/dev/null |
    grep -v '^[[:space:]]*$' | tail -n "$LINES" | sed 's/^/   | /' || true
done
