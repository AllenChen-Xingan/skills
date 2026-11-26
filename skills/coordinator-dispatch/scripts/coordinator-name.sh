#!/usr/bin/env bash
# coordinator-name.sh — the coordinator's fixed session name: <project>-meta.
# The same name across every rotation, so workers always know whom to message.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: coordinator-name.sh [project-dir] [options]

Print the coordinator's session name, <project>-meta. <project> is the directory name of the
project's main repository (a worktree resolves to its main checkout; outside git, the directory
itself), lowercased, with every run of characters other than a-z 0-9 turned into "-".
Example: .../my_shop (or any of its worktrees) -> my-shop-meta

Options:
  --project NAME   use NAME as <project> instead of deriving it (still normalized)
  --rename-self    also rename the Claude Code session in the current tmux pane ($TMUX_PANE):
                   types "/rename <name>" + Enter into it. If that session is mid-turn, the
                   command is queued and takes effect when the turn ends.
  --retire         like --rename-self, but renames to <project>-meta-old: the outgoing coordinator
                   runs this just before opening its successor, so the name stays unique
  --dry-run        with --rename-self, print the tmux actions instead of running them
  -h, --help       show this help

Exit codes: 0 success · 1 bad arguments · 2 --rename-self outside tmux
USAGE
}

DIR="."; PROJECT=""; SELF=0; RETIRE=0; DRY=0; POS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --rename-self) SELF=1; shift ;;
    --retire) SELF=1; RETIRE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) POS+=("$1"); shift ;;
  esac
done
[[ ${#POS[@]} -le 1 ]] || { echo "Expected at most 1 positional argument" >&2; usage >&2; exit 1; }
[[ ${#POS[@]} -eq 1 ]] && DIR="${POS[0]}"

if [[ -z "$PROJECT" ]]; then
  [[ -d "$DIR" ]] || { echo "Directory does not exist: $DIR" >&2; exit 1; }
  if common="$(git -C "$DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
    if [[ "$(basename "$common")" == ".git" ]]; then
      PROJECT="$(basename "$(dirname "$common")")"
    else
      PROJECT="$(basename "$common" .git)"   # bare repository
    fi
  else
    PROJECT="$(basename "$(cd "$DIR" && pwd)")"
  fi
fi

NAME="$(printf '%s' "$PROJECT" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
[[ -n "$NAME" ]] || { echo "Could not derive a project name from: ${PROJECT}" >&2; exit 1; }
NAME="$NAME-meta"
echo "$NAME"
if [[ $RETIRE -eq 1 ]]; then NAME="$NAME-old"; fi

if [[ $SELF -eq 1 ]]; then
  [[ -n "${TMUX_PANE:-}" ]] || { echo "--rename-self needs to run inside the coordinator's tmux pane (TMUX_PANE is empty); ask the human to type: /rename $NAME" >&2; exit 2; }
  if [[ $DRY -eq 1 ]]; then
    echo "[dry-run] tmux paste \"/rename $NAME\" into $TMUX_PANE, then Enter"
    exit 0
  fi
  BUF="cd-rename-$$"; TMP="$(mktemp)"
  printf '/rename %s' "$NAME" >"$TMP"
  tmux load-buffer -b "$BUF" "$TMP"; rm -f "$TMP"
  tmux paste-buffer -d -p -b "$BUF" -t "$TMUX_PANE"
  sleep 1
  tmux send-keys -t "$TMUX_PANE" Enter
  echo "Typed /rename $NAME into $TMUX_PANE (takes effect when the current turn ends)" >&2
fi
