#!/usr/bin/env bash
# spawn-worker.sh — open a tmux window, start Claude Code, wait until ready,
# paste the first-message FILE (never inline text), press Enter, print pane tail.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: spawn-worker.sh <session> <window> <workdir> <first-message-file> [options]

Open window <window> in tmux session <session> (creating the session if needed), start
Claude Code in <workdir>, wait until its UI is ready, paste the contents of
<first-message-file> and press Enter, then print the pane tail.
The first message is always read from a file, never inlined in a command line.

Options:
  --cmd CMD            Start command (default $CD_CLAUDE_CMD or "claude"), e.g. "claude --model opus"
  --ready-pattern RE   Regex that means "ready" (grep -E; default matches Claude Code's input prompt)
  --block-pattern RE   Regex that means "stuck on a prompt", never auto-answered (default: trust-folder / permission prompts)
  --timeout SEC        Seconds to wait for ready (default 60)
  --tail N             Pane-tail lines to print at the end (default 20)
  --settle SEC         Seconds to wait after pasting, before Enter (default 1)
  --dry-run            Only print the tmux actions that would run
  -h, --help           Show this help

Exit codes: 0 success · 1 bad arguments · 2 window exists · 3 timed out waiting for ready · 4 stuck on a prompt
Example: spawn-worker.sh myws api "/path/with space/proj" "/path/with space/proj/_tmp/b1/msg-api.txt"
USAGE
}

CMD="${CD_CLAUDE_CMD:-claude}"
READY_RE='(\? for shortcuts|^[[:space:]]*[>❯$][[:space:]]*$|Try "|bypass permissions|accept edits|auto mode on)'
BLOCK_RE='(Do you trust|trust the files|trust this folder|one you trust|Enter y/n|Yes, proceed|Do you want to proceed|1\. Yes)'
TIMEOUT=60; TAIL=20; SETTLE=1; DRY=0
POS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --cmd) CMD="$2"; shift 2 ;;
    --ready-pattern) READY_RE="$2"; shift 2 ;;
    --block-pattern) BLOCK_RE="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --tail) TAIL="$2"; shift 2 ;;
    --settle) SETTLE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --) shift; POS+=("$@"); break ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done
[[ ${#POS[@]} -eq 4 ]] || { echo "Expected 4 positional arguments, got ${#POS[@]}" >&2; usage >&2; exit 1; }
SESSION="${POS[0]}"; WINDOW="${POS[1]}"; WORKDIR="${POS[2]}"; MSG="${POS[3]}"

command -v tmux >/dev/null || { echo "tmux not found" >&2; exit 1; }
[[ -d "$WORKDIR" ]] || { echo "Working directory does not exist: $WORKDIR" >&2; exit 1; }
[[ -f "$MSG" && -s "$MSG" ]] || { echo "First-message file missing or empty: $MSG" >&2; exit 1; }
[[ "$WINDOW" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Window names may only contain letters, digits, _ . -: $WINDOW" >&2; exit 1; }

TARGET="$SESSION:$WINDOW"
run() { if [[ $DRY -eq 1 ]]; then printf '[dry-run]'; printf ' %q' "$@"; echo; else "$@"; fi; }

if tmux has-session -t "=$SESSION" 2>/dev/null; then
  if tmux list-windows -t "=$SESSION" -F '#{window_name}' | grep -Fxq "$WINDOW"; then
    echo "Window already exists: ${TARGET} (wrap up the old one or pick another name)" >&2; exit 2
  fi
  run tmux new-window -d -t "=$SESSION:" -n "$WINDOW" -c "$WORKDIR" "$CMD"
else
  echo "Session $SESSION does not exist, creating it"
  run tmux new-session -d -s "$SESSION" -n "$WINDOW" -c "$WORKDIR" "$CMD"
fi
# keep the window around if the command exits, so its last screen can be read
run tmux set-option -w -t "=$SESSION:$WINDOW" remain-on-exit on

if [[ $DRY -eq 1 ]]; then
  echo "[dry-run] after waiting for ready (/$READY_RE/, up to ${TIMEOUT}s): load-buffer \"$MSG\" → paste-buffer → Enter"
  exit 0
fi

pane() { tmux capture-pane -p -t "=$SESSION:$WINDOW" -S -60 2>/dev/null || true; }
tailpane() { pane | grep -v '^[[:space:]]*$' | tail -n "$TAIL" || true; }
waited=0
until pane | grep -Eq -- "$READY_RE"; do
  if pane | grep -Eq -- "$BLOCK_RE"; then
    echo "Stuck on a prompt (trust folder / permission). Ask the human to handle it in window $TARGET, then feed again:" >&2
    tailpane >&2; exit 4
  fi
  if [[ $waited -ge $TIMEOUT ]]; then
    echo "Timed out after ${TIMEOUT}s waiting for ready. Pane tail:" >&2; tailpane >&2; exit 3
  fi
  sleep 1; waited=$((waited + 1))
done

BUF="cd-first-msg-$WINDOW-$$"
tmux load-buffer -b "$BUF" "$MSG"
tmux paste-buffer -d -p -b "$BUF" -t "=$SESSION:$WINDOW"
sleep "$SETTLE"
tmux send-keys -t "=$SESSION:$WINDOW" Enter
# After a long paste the first Enter is often swallowed (observed 2026-10-25), so press it again a few
# seconds later; an extra Enter on an empty input box does nothing
sleep 3
tmux send-keys -t "=$SESSION:$WINDOW" Enter
sleep 2
echo "Fed first message to ${TARGET} (waited ${waited}s for ready). Pane tail:"
tailpane
