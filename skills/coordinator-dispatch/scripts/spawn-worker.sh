#!/usr/bin/env bash
# spawn-worker.sh — open a tmux window, start Claude Code, wait until ready,
# paste the first-message FILE (never inline text), press Enter, print pane tail.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: spawn-worker.sh <session> <window> <workdir> <first-message-file> [options]

Open window <window> in tmux session <session> (creating the session if it does not exist),
start Claude Code in <workdir>, wait until the UI is ready, paste the contents of
<first-message-file> and press Enter, then print the pane tail.
The first message is always read from a file, never spliced into the command line.

Options:
  --cmd CMD            start command (default $CD_CLAUDE_CMD or "claude"), e.g. "claude --model opus"
  --name NAME          session name others message it by (appends --name NAME to the command); a coordinator always gets $(coordinator-name.sh <dir>)
  --ready-pattern RE   regex that means "ready" (grep -E; default matches the Claude Code input prompt)
  --block-pattern RE   if this appears, treat the worker as stuck on a confirmation dialog and do not handle it automatically (default matches trust-folder / permission prompts)
  --timeout SEC        seconds to wait for ready (default 60)
  --tail N             number of pane-tail lines to print at the end (default 20)
  --settle SEC         seconds to wait after pasting, before Enter (default 1)
  --base B             base branch of the worker's branch (default origin/<default branch>; only used in git-guard messages)
  --no-git-guard       do not attach the git-guard hook (default: attached automatically when <workdir> is on a non-protected branch; see references/git-workflow.md)
  --dry-run            only print the tmux actions that would run; do not run them
  -h, --help           show this help

Exit codes: 0 success · 1 bad arguments · 2 window already exists · 3 timed out waiting for ready · 4 stuck on a confirmation dialog
Example: spawn-worker.sh myws api "/path/with space/proj" "/path/with space/proj/_tmp/b1/msg-api.txt"
USAGE
}

CMD="${CD_CLAUDE_CMD:-claude}"
READY_RE='(\? for shortcuts|^[[:space:]]*[>❯$][[:space:]]*$|Try "|bypass permissions|accept edits|auto mode on)'
BLOCK_RE='(Do you trust|trust the files|trust this folder|one you trust|Enter y/n|Yes, proceed|Do you want to proceed|1\. Yes)'
TIMEOUT=60; TAIL=20; SETTLE=1; DRY=0; GUARD=1; BASE=""; NAME=""
POS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --cmd) CMD="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --ready-pattern) READY_RE="$2"; shift 2 ;;
    --block-pattern) BLOCK_RE="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --tail) TAIL="$2"; shift 2 ;;
    --settle) SETTLE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --no-git-guard) GUARD=0; shift ;;
    --base) BASE="$2"; shift 2 ;;
    --) shift; POS+=("$@"); break ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done
[[ ${#POS[@]} -eq 4 ]] || { echo "Expected 4 positional arguments, got ${#POS[@]}" >&2; usage >&2; exit 1; }
SESSION="${POS[0]}"; WINDOW="${POS[1]}"; WORKDIR="${POS[2]}"; MSG="${POS[3]}"

command -v tmux >/dev/null || { echo "tmux not found" >&2; exit 1; }
[[ -d "$WORKDIR" ]] || { echo "Working directory does not exist: $WORKDIR" >&2; exit 1; }
[[ -f "$MSG" && -s "$MSG" ]] || { echo "First-message file is missing or empty: $MSG" >&2; exit 1; }
[[ "$WINDOW" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Window name may only contain letters, digits, _ . -: $WINDOW" >&2; exit 1; }
if [[ -n "$NAME" ]]; then
  [[ "$NAME" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Session name may only contain letters, digits, _ . -: $NAME" >&2; exit 1; }
  CMD="$CMD --name $NAME"
fi

# Git guard: a worker on its own branch gets the PreToolUse hook (same policy as the pi extension).
# The branch is pinned through the environment so switching to main does not lift the rules.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTECTED_RE="${PI_WORKER_PROTECTED:-main|master|develop|trunk|release/.*|production}"
if [[ $GUARD -eq 1 ]] && BR="$(git -C "$WORKDIR" rev-parse --abbrev-ref HEAD 2>/dev/null)"; then
  if [[ "$BR" =~ ^($PROTECTED_RE)$ ]]; then
    echo "Note: $WORKDIR is on protected branch $BR; a worker should work in its own worktree/branch (scripts/git/worktree.sh new). Not attaching the git guard this time." >&2
  else
    [[ -n "$BASE" ]] || BASE="$("$HERE/git/worktree.sh" base "$WORKDIR" 2>/dev/null || true)"
    GDIR="$HOME/.local/state/coordinator-dispatch"; mkdir -p "$GDIR"
    GSET="$GDIR/git-guard.settings.json"
    jq -n --arg c "node $(printf %q "$HERE/git/claude-hook.ts")" \
      '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$c}]}]}}' >"$GSET"
    CMD="CD_WORKER_BRANCH=$(printf %q "$BR") CD_WORKER_BASE=$(printf %q "$BASE") $CMD --settings $(printf %q "$GSET")"
    echo "git guard: worker branch ${BR} (base branch ${BASE:-unknown})"
  fi
fi

TARGET="$SESSION:$WINDOW"
run() { if [[ $DRY -eq 1 ]]; then printf '[dry-run]'; printf ' %q' "$@"; echo; else "$@"; fi; }

if tmux has-session -t "=$SESSION" 2>/dev/null; then
  if tmux list-windows -t "=$SESSION" -F '#{window_name}' | grep -Fxq "$WINDOW"; then
    echo "Window already exists: ${TARGET} (wrap up the old one first, or pick another name)" >&2; exit 2
  fi
  run tmux new-window -d -t "=$SESSION:" -n "$WINDOW" -c "$WORKDIR" "$CMD"
else
  echo "Session $SESSION does not exist; creating it"
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
    echo "Stuck on a confirmation dialog (trust folder / permission); a human needs to handle it in window $TARGET, then resend:" >&2
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
# After a long paste the first Enter is often swallowed (observed 2026-10-25), so send another after a few seconds; an extra Enter on an empty input box is harmless
sleep 3
tmux send-keys -t "=$SESSION:$WINDOW" Enter
sleep 2
echo "Sent the first message to ${TARGET} (waited ${waited}s for ready). Pane tail:"
tailpane
