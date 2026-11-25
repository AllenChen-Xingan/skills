#!/usr/bin/env bash
# Test the Claude Code worker git hook against a throwaway repo. Run: bash scripts/git/hook.test.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
git init -q -b main "$T/r" && git -C "$T/r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$T/r" switch -q -c w/x
fails=0
check() { # check <expect allow|block> <branch-env> <command>
	local rc=0
	printf '%s' "$(jq -nc --arg c "$3" --arg d "$T/r" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')" \
		| CD_WORKER_BRANCH="$2" node "$HERE/claude-hook.ts" 2>/dev/null || rc=$?
	local got; got=$([[ $rc -eq 2 ]] && echo block || echo allow)
	[[ "$got" == "$1" ]] || { echo "FAIL expected $1, got $got: [$2] $3"; fails=$((fails + 1)); }
}
check allow w/x  "git commit -m 'feat: x'"
check allow w/x  "git push -u origin w/x"
check block w/x  "git push origin main"
check block w/x  "gh pr merge 3"
check allow ""   "git push origin main"          # not a worker session (coordinator): hook stays out
git -C "$T/r" switch -q main
check block w/x  "git commit -m sneaky"          # off its branch: writes refused
check allow w/x  "git status"
check allow w/x  "git switch w/x"                # going back is allowed
[[ $fails -eq 0 ]] || { echo "hook: $fails failures"; exit 1; }
echo "PASS hook (8 cases)"
