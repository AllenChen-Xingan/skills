#!/usr/bin/env bash
# close-worker.sh — print the pane tail, ask for confirmation, then kill one window.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: close-worker.sh <session> <window> [options]

Print the tail of window <session>:<window>, then close that window after confirmation
(only this one window; other windows in the session are left alone).
Refuses to close the window it is running in (so the coordinator can't close itself).

Options:
  --yes      Don't ask, just close (only after a human has already read the pane tail)
  --tail N   Number of pane-tail lines to print (default 15)
  -h, --help Show this help
Exit codes: 0 closed · 1 bad arguments / not found · 5 cancelled by user · 6 refused to close current window
USAGE
}

YES=0; TAIL=15; POS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --yes) YES=1; shift ;;
    --tail) TAIL="$2"; shift 2 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done
[[ ${#POS[@]} -eq 2 ]] || { usage >&2; exit 1; }
SESSION="${POS[0]}"; WINDOW="${POS[1]}"
T="=$SESSION:$WINDOW"

tmux has-session -t "=$SESSION" 2>/dev/null || { echo "No such session: $SESSION" >&2; exit 1; }
tmux list-windows -t "=$SESSION" -F '#{window_name}' | grep -Fxq "$WINDOW" || { echo "No such window: $SESSION:$WINDOW" >&2; exit 1; }

if [[ -n "${TMUX_PANE:-}" ]]; then
  here="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_name}')"
  [[ "$here" == "$SESSION:$WINDOW" ]] && { echo "Refusing to close the current window $here" >&2; exit 6; }
fi

echo "== $SESSION:$WINDOW pane tail:"
tmux capture-pane -p -t "$T" -S -200 | grep -v '^[[:space:]]*$' | tail -n "$TAIL" | sed 's/^/   | /' || true

if [[ $YES -ne 1 ]]; then
  if [[ ! -t 0 ]]; then echo "Non-interactive: pass --yes to confirm closing" >&2; exit 5; fi
  read -r -p "Close window $SESSION:$WINDOW? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Cancelled"; exit 5; }
fi
tmux kill-window -t "$T"
echo "Closed $SESSION:$WINDOW"
