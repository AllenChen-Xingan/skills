// Claude Code PreToolUse hook (matcher: Bash) that applies the worker git policy to Claude Code workers.
// Same rules as pi workers (git-policy.ts). Installed by spawn-worker.sh through `claude --settings`,
// so it only exists in worker sessions, never in the coordinator's.
//
// The worker's own branch comes from CD_WORKER_BRANCH (set by spawn-worker.sh at launch), not from the
// current checkout, so switching to main does not lift the rules: while off its branch the worker may
// only run git commands that bring it back.
// Exit 0 = allow; exit 2 = block (stderr is shown to Claude).
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { gitViolation } from "./git-policy.ts";

const branch = process.env.CD_WORKER_BRANCH ?? "";
let input: any = {};
try {
	input = JSON.parse(readFileSync(0, "utf8"));
} catch {
	process.exit(0);
}
if (input.tool_name !== "Bash" || !branch) process.exit(0);
const cmd = String(input.tool_input?.command ?? "");
const cwd = String(input.cwd ?? process.cwd());

const block = (why: string) => {
	process.stderr.write(`Git policy (worker branch ${branch}): ${why} See AGENTS.md "Git".\n`);
	process.exit(2);
};

const why = gitViolation(cmd, { branch, base: process.env.CD_WORKER_BASE ?? "", protected: process.env.PI_WORKER_PROTECTED ?? "" });
if (why) block(why);

if (/\bgit\b/.test(cmd)) {
	let now = "";
	try {
		now = execFileSync("git", ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
	} catch {
		process.exit(0); // not inside a repo: nothing to protect
	}
	const goingBack = new RegExp(`\\bgit\\s+(switch|checkout)\\s+${branch.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&")}(\\s|$)`).test(cmd);
	const readOnly = /^\s*git\s+(status|log|diff|show|branch|rev-parse|fetch)\b/.test(cmd);
	if (now && now !== branch && !goingBack && !readOnly) block(`you are on ${now}; switch back first: git switch ${branch}.`);
}
process.exit(0);
