/**
 * claude-bridge — makes pi behave as the coding hand of the Claude Code worker that started it
 * (pi writes code and commits small steps on its own branch; the worker reviews, merges pi's
 * branch into its own, pushes, opens issues/PRs and talks to the coordinator).
 *
 * Talks to that worker through pi's RPC stream (read by `pi-worker watch`):
 *   report_to_claude  tool   non-blocking report (progress / done / blocked / failed)
 *   ask_claude        tool   blocking question; answered with `pi-worker answer`
 *
 * Enforces the worker protocol mechanically instead of trusting the model:
 *   slot   heavy bash commands (heavy.ts; PI_WORKER_HEAVY_EXTRA_RE adds, PI_WORKER_HEAVY_RE replaces)
 *          wait for `pi-worker grant|deny`;
 *          the slot is returned automatically when the command ends
 *   git    pi stays on its own branch (PI_WORKER_BRANCH) and commits there in small steps; every
 *          commit must carry an `Agent: pi` trailer (Model: comes from PI_WORKER_COMMIT_MODEL).
 *          Any push, gh pr/issue writes, deleting branches/tags, merging PRs, editing git config
 *          or worktrees are blocked (git-policy.ts, role "pi"); leaving the branch is flagged
 *   budget cumulative model cost is tracked; at PI_WORKER_BUDGET_USD the run is aborted
 *          and further tool calls are blocked until `/budget <usd>` raises the cap
 *
 * Outside RPC mode (no Claude worker attached) ask_claude and the quota gate degrade
 * to "decide yourself" / "run", so nothing ever hangs.
 */

import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { gitViolation } from "../git/git-policy.ts";
import { heavyRe } from "./heavy.ts";

const env = process.env;
const ASK_TIMEOUT_MS = Number(env.PI_WORKER_ASK_TIMEOUT_MS ?? 20 * 60 * 1000);
const QUOTA_TIMEOUT_MS = Number(env.PI_WORKER_QUOTA_TIMEOUT_MS ?? 60 * 60 * 1000);
const HEAVY_RE = heavyRe(env); // default + PI_WORKER_HEAVY_EXTRA_RE, or PI_WORKER_HEAVY_RE (heavy.ts)
const BRANCH = env.PI_WORKER_BRANCH || ""; // the worker's own branch ("" = not a git worker)
const BASE = env.PI_WORKER_BASE || "";
const POLICY = { branch: BRANCH, base: BASE, protected: env.PI_WORKER_PROTECTED || "", role: "pi" as const };
const MODEL = env.PI_WORKER_COMMIT_MODEL || "<your model>";

const GRANT = "granted";
const DENY = "denied";

let budget = Number(env.PI_WORKER_BUDGET_USD ?? 0); // 0 = no cap
let spent = 0;
let warned = false;
let over = false;
const holding = new Set<string>();

async function currentBranch(pi: ExtensionAPI, cwd: string): Promise<string | undefined> {
	const r = await pi.exec("git", ["rev-parse", "--abbrev-ref", "HEAD"], { cwd, timeout: 5000 });
	return r.code === 0 ? r.stdout.trim() : undefined;
}
const fmt = (n: number) => `$${n.toFixed(4)}`;

const reportTool = defineTool({
	name: "report_to_claude",
	label: "Report to Claude",
	description:
		"Send a short status report to the Claude Code worker that started you. Does not wait for a reply. " +
		"Use at milestones, when tests pass/fail, when blocked, and once when the task is done.",
	promptSnippet: "Report milestones, blockers and completion to the Claude worker that started you",
	promptGuidelines: [
		"Call report_to_claude with status=done exactly once when the whole task is finished: list changed files and how you verified them (commands + results).",
		"Call report_to_claude with status=blocked when you cannot proceed, then ask_claude if you need a decision.",
		"Do not report trivial steps; one report per real milestone.",
		"You only write code (and its tests). Git: stay on the current branch and commit each small logical step there (commits are rollback points): " +
			`git add <files> && git commit -m "<type>(<scope>): <what>" --trailer "Agent: pi" --trailer "Model: ${MODEL}". ` +
			"Never push, open issues or PRs, or merge; the Claude worker reviews your commits and does that.",
		"Heavy commands (full builds, full test suites) block until the Claude worker grants the machine-wide slot; prefer the targeted tests your brief names.",
	],
	parameters: Type.Object({
		status: Type.Union(
			[Type.Literal("progress"), Type.Literal("done"), Type.Literal("blocked"), Type.Literal("failed")],
			{ description: "progress | done | blocked | failed" },
		),
		message: Type.String({ description: "What happened, with evidence (commands run, results, files)." }),
	}),
	async execute(_id, params) {
		return {
			content: [{ type: "text", text: `Report delivered (${params.status}). Continue unless you are done.` }],
			details: { status: params.status },
		};
	},
});

const askTool = defineTool({
	name: "ask_claude",
	label: "Ask Claude",
	description:
		"Ask the Claude Code worker that started you about requirements, architecture or acceptance criteria and wait for the answer. " +
		"Only for decisions you should not make alone; never for things you can find in the code.",
	promptSnippet: "Ask the Claude worker for a decision and wait for the answer",
	parameters: Type.Object({
		question: Type.String({ description: "The question, the options you see, and your recommendation." }),
	}),
	async execute(_id, params, signal, _onUpdate, ctx) {
		if (!ctx.hasUI || ctx.mode !== "rpc") {
			return {
				content: [{ type: "text", text: "No Claude worker connected. Choose the conservative option and mention it in your final report." }],
				details: { answered: false },
			};
		}
		const answer = await ctx.ui.input(`[ask_claude] ${params.question}`, "answer", { timeout: ASK_TIMEOUT_MS, signal });
		if (answer === undefined || answer.trim() === "") {
			return {
				content: [{ type: "text", text: "The Claude worker did not answer in time. Choose the conservative option and mention it in your report." }],
				details: { answered: false },
			};
		}
		return { content: [{ type: "text", text: `Answer from the Claude worker: ${answer}` }], details: { answered: true } };
	},
});

export default function (pi: ExtensionAPI) {
	pi.registerTool(reportTool);
	pi.registerTool(askTool);

	// Budget: count every assistant message's cost.
	pi.on("message_end", async (event, ctx) => {
		const m: any = event.message;
		if (m?.role !== "assistant") return;
		spent += Number(m.usage?.cost?.total ?? 0);
		if (budget <= 0) return;
		if (!over && spent >= budget) {
			over = true;
			ctx.ui.notify(`[budget] exceeded: spent ${fmt(spent)} of ${fmt(budget)}; run aborted. Raise with: pi-worker budget <name> <usd>`, "error");
			ctx.abort();
		} else if (!warned && spent >= budget * 0.8) {
			warned = true;
			ctx.ui.notify(`[budget] 80% used: spent ${fmt(spent)} of ${fmt(budget)}`, "warning");
		}
	});

	pi.on("agent_end", async (_event, ctx) => {
		ctx.ui.notify(`[spend] ${fmt(spent)}${budget > 0 ? ` of ${fmt(budget)}` : " (no cap)"}`, "info");
	});

	pi.registerCommand("budget", {
		description: "Set the worker's USD budget cap (0 = no cap)",
		handler: async (args, ctx) => {
			const v = Number(String(args ?? "").trim());
			if (!Number.isFinite(v) || v < 0) {
				ctx.ui.notify(`[budget] invalid value: ${args}`, "error");
				return;
			}
			budget = v;
			over = budget > 0 && spent >= budget;
			warned = budget > 0 && spent >= budget * 0.8;
			ctx.ui.notify(`[budget] cap set to ${budget > 0 ? fmt(budget) : "none"}; spent ${fmt(spent)}`, "info");
		},
	});

	// Red lines + budget + slot gate on every bash call.
	pi.on("tool_call", async (event, ctx) => {
		if (over) {
			return { block: true, reason: `Budget exhausted (${fmt(spent)} of ${fmt(budget)}). Stop and call report_to_claude with status=blocked.` };
		}
		if (event.toolName !== "bash") return undefined;
		const cmd = String((event.input as any)?.command ?? "");
		const why = gitViolation(cmd, POLICY);
		if (why) {
			ctx.ui.notify(`[git] blocked: ${cmd.slice(0, 200)} — ${why}`, "warning");
			return { block: true, reason: `Git policy: ${why}` };
		}
		if (!HEAVY_RE.test(cmd) || !ctx.hasUI || ctx.mode !== "rpc") return undefined;
		const v = await ctx.ui.select(`[quota] ${cmd}`, [GRANT, DENY], { timeout: QUOTA_TIMEOUT_MS });
		if (v !== GRANT) {
			return { block: true, reason: "The Claude worker did not grant the heavy-work slot. Do parts that do not need it, report progress, or ask_claude." };
		}
		holding.add(event.toolCallId);
		return undefined;
	});

	// Leaving the assigned branch is detected after the fact (covers every way of switching).
	pi.on("tool_result", async (event, ctx) => {
		if (!BRANCH || event.toolName !== "bash") return undefined;
		const now = await currentBranch(pi, ctx.cwd);
		if (now === undefined || now === BRANCH) return undefined;
		ctx.ui.notify(`[git] worker left its branch: now on ${now}, expected ${BRANCH}`, "error");
		return {
			content: [
				...(event.content ?? []),
				{ type: "text", text: `\nWARNING: you are now on branch ${now}; your branch is ${BRANCH}. Run: git switch ${BRANCH}` },
			],
		};
	});

	pi.on("tool_execution_end", async (event, ctx) => {
		if (!holding.delete(event.toolCallId)) return;
		ctx.ui.notify(`[quota-return] ${event.isError ? "failed" : "passed"} (${Math.round((event.durationMs ?? 0) / 1000)}s)`, event.isError ? "warning" : "info");
	});
}
