#!/usr/bin/env bash
# End-to-end check of pi-worker + claude-bridge against a scripted mock API (no key, no cost).
#   1 basic   report · steer · ask/answer · SETTLED · re-armed watch resumes · watch ends on exit · no orphans
#   2 quota   heavy command waits for grant, QUOTA_RETURN after it
#   3 budget  80% warning, cap aborts the run, `budget` raises it and work resumes
#   4 review  `review` starts a read-only reviewer on everything since the base and its report arrives
#   5 git     --repo makes worktree + own branch; worker commits and pushes its branch; push to main,
#             force push are blocked; leaving the branch is flagged; coordinator merges; clean removes all
#   (the git policy itself is table-tested in scripts/git/git-policy.test.ts)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; BIN="$HERE/../../pi-worker"
T="$(mktemp -d)"; PORT=$(( 18000 + RANDOM % 1000 ))
export PI_WORKER_HOME="$T/state" PI_CODING_AGENT_DIR="$T/agent" PI_WORKER_MODEL=mock/mock-model PI_WORKER_HEAVY_RE=HEAVYMARK
mkdir -p "$PI_CODING_AGENT_DIR"
# cost: 10 prompt tokens per call x 100000 USD/M = $1 per call (makes the budget test exact)
cat >"$PI_CODING_AGENT_DIR/models.json" <<EOF
{"providers":{"mock":{"baseUrl":"http://127.0.0.1:$PORT/v1","api":"openai-completions","apiKey":"x",
 "models":[{"id":"mock-model","contextWindow":100000,"maxTokens":1000,"cost":{"input":100000,"output":0,"cacheRead":0,"cacheWrite":0}}]}}}
EOF
node "$HERE/mock-openai.mjs" $PORT 2>/dev/null & MOCK=$!
cleanup() { for w in t1 t2 t3 t4 t4-review t5; do "$BIN" stop $w >/dev/null 2>&1 || true; done; kill $MOCK 2>/dev/null || true; rm -rf "$T"; }
trap cleanup EXIT
sleep 0.5

CUR=""
fail() { echo "FAIL: $*"; [[ -n "$CUR" ]] && { echo "--- watch"; cat "$T/$CUR.out" 2>/dev/null; echo "--- events (tail)"; tail -n 15 "$PI_WORKER_HOME/$CUR/events.jsonl" | cut -c1-300; echo "--- stderr"; cat "$PI_WORKER_HOME/$CUR/stderr.log"; }; exit 1; }
wait_for() { # wait_for <file> <regex> <seconds>
	for _ in $(seq $(( $3 * 10 ))); do grep -qE "$2" "$1" 2>/dev/null && return 0; sleep 0.1; done; fail "timeout waiting for /$2/ in $(basename "$1")"
}
id_of() { sed -n "s/.*$2 id=\([^:]*\):.*/\1/p" "$1" | tail -1; }
exited() { for _ in $(seq 80); do [[ -f "$PI_WORKER_HOME/$1/exit" ]] && return 0; sleep 0.1; done; fail "$1 did not exit"; }

# 1 basic ------------------------------------------------------------------
CUR=t1; mkdir -p "$T/w1"
"$BIN" start t1 --cwd "$T/w1" --task "Format the code." >/dev/null
"$BIN" watch t1 >"$T/t1.out" & W=$!
"$BIN" steer t1 "STEER-MARKER keep it small" >/dev/null
wait_for "$T/t1.out" 'REPORT progress' 15
wait_for "$T/t1.out" 'ASK id=' 15
"$BIN" answer t1 "$(id_of "$T/t1.out" ASK)" "ANSWER-MARKER tabs" >/dev/null
wait_for "$T/t1.out" 'REPORT done: .*ANSWER-MARKER' 15
grep -q 'REPORT done: .*STEER-MARKER' "$T/t1.out" || fail "steer text not seen by model"
wait_for "$T/t1.out" 'SPEND \$' 15
wait_for "$T/t1.out" 'SETTLED' 15
kill $W 2>/dev/null; wait $W 2>/dev/null || true
"$BIN" follow t1 "second round" >/dev/null
"$BIN" watch t1 >"$T/t1b.out" & W=$!
wait_for "$T/t1b.out" 'SETTLED' 15
grep -q 'ASK id=' "$T/t1b.out" && fail "re-armed watch replayed old events"
"$BIN" stop t1 >/dev/null; exited t1
for _ in $(seq 50); do kill -0 $W 2>/dev/null || break; sleep 0.1; done
kill -0 $W 2>/dev/null && fail "watch kept running after pi exited"
grep -q 'EXITED' "$T/t1b.out" || fail "watch did not report EXITED"
echo "ok 1 basic"

# 2 quota + red line ---------------------------------------------------------
CUR=t2; mkdir -p "$T/w2"
"$BIN" start t2 --cwd "$T/w2" --task "SCENARIO:quota build it" >/dev/null
"$BIN" watch t2 >"$T/t2.out" & W=$!
wait_for "$T/t2.out" 'QUOTA id=.*HEAVYMARK' 15
sleep 1
ran_early=$(grep '"type":"tool_execution_end"' "$PI_WORKER_HOME/t2/events.jsonl" | grep -c '"toolName":"bash"' || true)
[[ "$ran_early" -eq 0 ]] || fail "heavy command ran before the grant"
"$BIN" grant t2 "$(id_of "$T/t2.out" QUOTA)" >/dev/null
wait_for "$T/t2.out" 'QUOTA_RETURN passed' 15
wait_for "$T/t2.out" 'REPORT done: heavy=\[HEAVYMARK-ran' 15
kill $W 2>/dev/null; wait $W 2>/dev/null || true
"$BIN" stop t2 >/dev/null
echo "ok 2 quota"

# 3 budget -----------------------------------------------------------------
CUR=t3; mkdir -p "$T/w3"
"$BIN" start t3 --cwd "$T/w3" --task "SCENARIO:budget loop" --budget 2.5 >/dev/null
"$BIN" watch t3 >"$T/t3.out" & W=$!
wait_for "$T/t3.out" 'BUDGET 80% used' 20
wait_for "$T/t3.out" 'BUDGET exceeded' 20
wait_for "$T/t3.out" 'SETTLED \(aborted\)' 20
before=$(grep -c 'REPORT progress' "$T/t3.out")
"$BIN" budget t3 5 >/dev/null
wait_for "$T/t3.out" 'BUDGET cap set to \$5' 10
"$BIN" follow t3 "continue" >/dev/null
wait_for "$T/t3.out" 'BUDGET exceeded: spent \$5' 30
after=$(grep -c 'REPORT progress' "$T/t3.out")
[[ $after -gt $before ]] || fail "work did not resume after raising the budget"
[[ "$("$BIN" status t3 | sed -n 's/^spent=\$//p' | cut -d. -f1)" -le 6 ]] || fail "spent far past the cap"
kill $W 2>/dev/null; wait $W 2>/dev/null || true
"$BIN" stop t3 >/dev/null
echo "ok 3 budget"

# 4 review -----------------------------------------------------------------
CUR=t4-review; mkdir -p "$T/w4"
git -C "$T/w4" init -q -b main && echo a >"$T/w4/a.txt" && git -C "$T/w4" add a.txt && git -C "$T/w4" -c user.email=t@t -c user.name=t commit -qm init
"$BIN" start t4 --repo "$T/w4" --task "change a.txt" >/dev/null; "$BIN" stop t4 >/dev/null
echo committed >"$T/w4.worktrees/t4/a.txt" && git -C "$T/w4.worktrees/t4" -c user.email=t@t -c user.name=t commit -qam "feat: change a"
echo uncommitted >"$T/w4.worktrees/t4/b.txt"
"$BIN" review t4 >/dev/null
grep -q '^+committed' "$PI_WORKER_HOME/t4-review/diff.patch" || fail "review diff missing the committed change"
grep -q 'feat: change a' "$PI_WORKER_HOME/t4-review/diff.patch" || fail "review diff missing the commit list"
grep -q '^b.txt' "$PI_WORKER_HOME/t4-review/diff.patch" || fail "review diff missing untracked files"
grep -q 'readonly=true' "$PI_WORKER_HOME/t4-review/meta" || fail "reviewer not read-only"
"$BIN" watch t4-review >"$T/t4-review.out" & W=$!
wait_for "$T/t4-review.out" 'REPORT done: P1 a.txt:1 REVIEW-MARKER' 15
kill $W 2>/dev/null; wait $W 2>/dev/null || true
"$BIN" stop t4-review >/dev/null
echo "ok 4 review"

# 5 git workflow -------------------------------------------------------------
CUR=t5; R="$T/r5"; git init -q --bare "$T/remote5.git"
git init -q -b main "$R" && echo a >"$R/a.txt" && git -C "$R" add a.txt && git -C "$R" -c user.email=t@t -c user.name=t commit -qm init
git -C "$R" remote add origin "$T/remote5.git" && git -C "$R" push -q -u origin main && git -C "$R" remote set-head origin main
"$BIN" start t5 --repo "$R" --task "SCENARIO:git" >"$T/t5.start"
grep -q "branch=w/t5 base=origin/main" "$T/t5.start" || fail "start did not set branch/base: $(cat "$T/t5.start")"
[[ "$(git -C "$R.worktrees/t5" rev-parse --abbrev-ref HEAD)" == "w/t5" ]] || fail "worktree not on w/t5"
"$BIN" watch t5 >"$T/t5.out" & W=$!
wait_for "$T/t5.out" 'REPORT done' 30
grep -q 'GIT blocked: git push origin HEAD:main' "$T/t5.out" || fail "push to main not blocked"
grep -q 'GIT blocked: git push --force' "$T/t5.out" || fail "force push not blocked"
grep -q 'GIT worker left its branch: now on sneaky' "$T/t5.out" || fail "leaving the branch not flagged"
grep -q 'REPORT done: 0=\[COMMITTED\] 1=\[PUSHED\]' "$T/t5.out" || fail "commit/push of own branch did not work"
grep -q '5=\[BACK\]' "$T/t5.out" || fail "switch back failed"
git -C "$T/remote5.git" rev-parse -q --verify refs/heads/w/t5 >/dev/null || fail "branch not on remote"
[[ "$(git -C "$T/remote5.git" rev-list --count main)" == 1 ]] || fail "remote main was changed"
"$BIN" status t5 >"$T/t5.status" 2>&1 || true
grep -q '1 ahead, 0 behind' "$T/t5.status" || fail "status missing ahead/behind: $(cat "$T/t5.status")"
grep -q 'unpushed: 0' "$T/t5.status" || fail "status unpushed wrong: $(cat "$T/t5.status")"
kill $W 2>/dev/null; wait $W 2>/dev/null || true
"$BIN" clean t5 2>/dev/null && fail "clean must refuse an unmerged branch"
git -C "$R" fetch -q origin && git -C "$R" merge -q --ff-only origin/w/t5 && git -C "$R" push -q origin main   # coordinator merges
"$BIN" clean t5 --delete-remote >/dev/null
[[ -d "$R.worktrees/t5" ]] && fail "worktree not removed"
git -C "$R" rev-parse -q --verify refs/heads/w/t5 >/dev/null && fail "local branch not deleted"
git -C "$T/remote5.git" rev-parse -q --verify refs/heads/w/t5 >/dev/null && fail "remote branch not deleted"
echo "ok 5 git workflow"

sleep 0.5
pgrep -f "$PI_WORKER_HOME" >/dev/null && fail "processes left behind: $(pgrep -fl "$PI_WORKER_HOME")"
node "$HERE/../../git/git-policy.test.ts" || fail "git-policy table test"
echo "PASS e2e-mock (basic, quota, budget, review, git workflow)"
