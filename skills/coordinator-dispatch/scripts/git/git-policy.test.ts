// Table test for the worker git policy. Run: node scripts/git/git-policy.test.ts
import { gitViolation } from "./git-policy.ts";

const policy = { branch: "w/feat-x", base: "origin/main", protected: "" };
const allowed = [
	"git status",
	"git add -A && git commit -m 'feat(parser): handle empty input'",
	"git commit --amend --no-edit",
	"git push -u origin w/feat-x",
	"git push -u origin HEAD",
	"git push",
	"git push --force-with-lease origin w/feat-x",
	"git fetch origin && git rebase origin/main",
	"git merge origin/main",
	"git -C /tmp/x log --oneline main..HEAD",
	"git diff origin/main...HEAD",
	"git show main:README.md",
	"git checkout -- src/a.ts",
	"git stash && git stash pop",
	"git reset --hard HEAD~1",
	"git branch",
	"git branch -a",
	"git tag",
	"git config --get user.name",
	"git worktree list",
	"gh pr create --draft --title 'feat: x' --body-file pr.md",
	"gh pr view",
	"echo git push origin main",
	"git push -q -u origin HEAD 2>&1 && echo PUSHED",
	"git push origin w/feat-x > push.log 2>/dev/null",
];
const blocked = [
	"git push origin main",
	"git push origin HEAD:main",
	"git push origin w/feat-x:master",
	"git push origin other-branch",
	"git push --force origin w/feat-x",
	"git push -f",
	"git push origin +w/feat-x",
	"git push origin --delete w/feat-x",
	"git push origin :w/feat-x",
	"git push --all",
	"git push --tags",
	"git add . && git commit -m x && git push origin main",
	"git branch -D old",
	"git branch -m new-name",
	"git tag v1.0",
	"git config user.email x@y",
	"git worktree add ../x",
	"git checkout main",
	"git switch main",
	"git filter-branch --tree-filter x",
	"gh pr merge 12 --squash",
	"gh release create v1",
	"git push origin main 2>/dev/null",
	"git push origin main >/dev/null 2>&1 || true",
];

// pi: commits on its own branch with trailers; never pushes, never touches PRs or issues
const piPolicy = { branch: "w/feat-x-pi1", base: "w/feat-x", protected: "", role: "pi" as const };
const piAllowed = [
	"git status",
	"git diff",
	"git add src/a.ts && git commit -qm 'feat(a): parse x' --trailer 'Agent: pi' --trailer 'Model: m'",
	"git commit -m 'fix: y\n\nAgent: pi\nModel: m'",
	"git commit --amend --no-edit",
	"git log --oneline w/feat-x..HEAD",
	"git reset --soft HEAD~1",
	"gh pr view 3",
	"gh issue list",
];
const piBlocked = [
	"git commit -m 'feat: no trailer'",
	"git push",
	"git push -u origin HEAD",
	"git push -u origin w/feat-x-pi1",
	"git push --force-with-lease origin w/feat-x-pi1",
	"git add . && git commit -m x --trailer 'Agent: pi' && git push",
	"gh pr create --draft --title x --body-file b.md",
	"gh pr edit 3 --title y",
	"gh pr comment 3 --body hi",
	"gh issue create --title x --body y",
	"gh issue close 4",
	"gh pr merge 3",
	"git switch w/feat-x",
	"git checkout main",
];

let bad = 0;
for (const c of piAllowed) if (gitViolation(c, piPolicy)) { bad++; console.log(`FAIL pi should allow: ${c}  -> ${gitViolation(c, piPolicy)}`); }
for (const c of piBlocked) if (!gitViolation(c, piPolicy)) { bad++; console.log(`FAIL pi should block: ${c}`); }
for (const c of allowed) if (gitViolation(c, policy)) { bad++; console.log(`FAIL should allow: ${c}  -> ${gitViolation(c, policy)}`); }
for (const c of blocked) if (!gitViolation(c, policy)) { bad++; console.log(`FAIL should block: ${c}`); }
// a branch-less worker (not a git worker) may still not touch protected branches
if (!gitViolation("git push origin main", { branch: "", base: "", protected: "" })) { bad++; console.log("FAIL protected without branch"); }
if (bad) { console.log(`git-policy: ${bad} failures`); process.exit(1); }
console.log(`PASS git-policy (worker: ${allowed.length} allowed, ${blocked.length} blocked; pi: ${piAllowed.length} allowed, ${piBlocked.length} blocked)`);
