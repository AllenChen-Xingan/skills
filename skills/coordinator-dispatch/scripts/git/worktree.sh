#!/usr/bin/env bash
# worktree.sh — the coordinator's side of the worker git workflow (references/git-workflow.md).
# One worker = one worktree = one branch w/<name>, cut from the integration base.
#
#   worktree.sh base  <repo>                                   # print the default base (origin/<default> or current branch)
#   worktree.sh new   <repo> <name> [--base B] [--branch BR]   # create <repo>.worktrees/<name> on BR (default w/<name>)
#                                                              # prints: cwd=… branch=… base=…
#   worktree.sh clean <repo> <name> [--base B] [--branch BR] [--delete-remote] [--force]
#                                                              # after merge: remove worktree + local (and remote) branch
# Env: PI_WORKER_PROTECTED  regex alternation of branches a worker may never own (default below)
set -euo pipefail

PROTECTED_RE="${PI_WORKER_PROTECTED:-main|master|develop|trunk|release/.*|production}"
die() { echo "worktree.sh: $*" >&2; exit 1; }
is_protected() { [[ "$1" =~ ^($PROTECTED_RE)$ ]]; }
toplevel() { git -C "$1" rev-parse --show-toplevel 2>/dev/null || die "not a git repository: $1"; }

default_base() {
	local r="$1" d
	if git -C "$r" remote get-url origin >/dev/null 2>&1; then
		git -C "$r" fetch -q origin 2>/dev/null || true
		d="$(git -C "$r" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
		[[ -n "$d" ]] && { echo "$d"; return; }
		for b in main master; do git -C "$r" rev-parse -q --verify "origin/$b" >/dev/null && { echo "origin/$b"; return; }; done
	fi
	# no remote: the branch checked out in the main worktree (not a worker's own branch)
	local main; main="$(git -C "$r" worktree list --porcelain | sed -n '1s/^worktree //p')"
	git -C "$main" rev-parse --abbrev-ref HEAD
}

parse_common() { # sets base branch delete_remote force from "$@"
	base="" branch="" delete_remote=false force=false
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--base) base="$2"; shift 2 ;;
			--branch) branch="$2"; shift 2 ;;
			--delete-remote) delete_remote=true; shift ;;
			--force) force=true; shift ;;
			*) die "unknown option $1" ;;
		esac
	done
}

cmd_new() {
	local repo name; repo="$(toplevel "${1:?repo}")"; name="${2:?name}"; shift 2
	parse_common "$@"
	[[ -n "$base" ]] || base="$(default_base "$repo")"
	[[ -n "$branch" ]] || branch="w/$name"
	is_protected "$branch" && die "a worker branch may not be a protected branch: $branch"
	local cwd="$repo.worktrees/$name"
	if [[ -d "$cwd" ]]; then
		[[ "$(git -C "$cwd" rev-parse --abbrev-ref HEAD)" == "$branch" ]] || die "$cwd exists but is not on $branch"
	elif git -C "$repo" rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
		git -C "$repo" worktree add -q "$cwd" "$branch"
	else
		# --no-track: the branch's upstream must become origin/<branch> on first push, never the base
		git -C "$repo" worktree add -q --no-track -b "$branch" "$cwd" "$base"
	fi
	printf 'cwd=%s\nbranch=%s\nbase=%s\n' "$cwd" "$branch" "$base"
}

cmd_clean() {
	local repo name; repo="$(toplevel "${1:?repo}")"; name="${2:?name}"; shift 2
	parse_common "$@"
	[[ -n "$base" ]] || base="$(default_base "$repo")"
	[[ -n "$branch" ]] || branch="w/$name"
	local cwd="$repo.worktrees/$name"
	if [[ -d "$cwd" && -n "$(git -C "$cwd" status --porcelain)" ]] && ! $force; then
		die "$cwd has uncommitted changes; commit/discard them or pass --force"
	fi
	git -C "$repo" fetch -q origin 2>/dev/null || true
	# merged = reachable from base, or every commit already applied there (rebase merge), or its PR is MERGED (squash)
	local merged=false
	if git -C "$repo" merge-base --is-ancestor "$branch" "$base" 2>/dev/null; then merged=true
	elif [[ -z "$(git -C "$repo" cherry "$base" "$branch" 2>/dev/null | grep '^+' || true)" ]]; then merged=true
	elif command -v gh >/dev/null && [[ "$(cd "$repo" && gh pr view "$branch" --json state -q .state 2>/dev/null)" == "MERGED" ]]; then merged=true; fi
	$merged || $force || die "$branch is not merged into $base yet; merge first or pass --force"
	[[ -d "$cwd" ]] && git -C "$repo" worktree remove $($force && echo --force) "$cwd"
	git -C "$repo" branch -D "$branch" >/dev/null 2>&1 || true
	if $delete_remote && git -C "$repo" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
		git -C "$repo" push -q origin --delete "$branch"
	fi
	echo "cleaned: removed $cwd, deleted $branch$($delete_remote && echo " (and origin/$branch)")"
}

case "${1:-}" in
	base) default_base "$(toplevel "${2:?repo}")" ;;
	new) shift; cmd_new "$@" ;;
	clean) shift; cmd_clean "$@" ;;
	*) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; [[ -z "${1:-}" || "$1" == -h || "$1" == --help ]] || exit 1 ;;
esac
