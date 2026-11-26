// Scripted OpenAI-compatible streaming server for pi-worker tests.
// The scenario is chosen by a marker in the first user message:
//   (default)          report(progress) -> ask_claude -> report(done: answer + steer seen) -> text
//   SCENARIO:quota     bash "echo HEAVYMARK" -> report(done: tool result) -> text
//   SCENARIO:git       add -> commit without trailer (blocked) -> commit with trailers -> second commit
//                      -> push own branch (blocked) -> push main (blocked) -> gh pr create (blocked)
//                      -> switch away (flagged) -> switch back -> report(done: all results) -> text
//   SCENARIO:budget    report(progress) forever (the budget cap must stop it)
//   SCENARIO:review    report(done: findings) -> text
// Usage: node mock-openai.mjs <port>
import http from "node:http";

const port = Number(process.argv[2] ?? 18731);
let calls = 0;

function sse(res, chunks) {
	res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache" });
	for (const c of chunks) res.write(`data: ${JSON.stringify(c)}\n\n`);
	res.write("data: [DONE]\n\n");
	res.end();
}
const base = { id: "mock", object: "chat.completion.chunk", created: 0, model: "mock-model" };
const usage = { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 };
const toolCall = (name, args) => [
	{ ...base, choices: [{ index: 0, delta: { role: "assistant", tool_calls: [{ index: 0, id: `call_${name}_${++calls}`, type: "function", function: { name, arguments: "" } }] } }] },
	{ ...base, choices: [{ index: 0, delta: { tool_calls: [{ index: 0, function: { arguments: JSON.stringify(args) } }] } }] },
	{ ...base, choices: [{ index: 0, delta: {}, finish_reason: "tool_calls" }], usage },
];
const text = (t) => [
	{ ...base, choices: [{ index: 0, delta: { role: "assistant", content: t } }] },
	{ ...base, choices: [{ index: 0, delta: {}, finish_reason: "stop" }], usage },
];
const textOf = (m) => (typeof m.content === "string" ? m.content : (m.content ?? []).map((p) => p.text ?? "").join(" "));

const scenarios = {
	default(n, tools, users) {
		if (n === 0) return toolCall("report_to_claude", { status: "progress", message: "started; read the task" });
		if (n === 1) return toolCall("ask_claude", { question: "Use tabs or spaces? I recommend tabs." });
		if (n === 2) return toolCall("report_to_claude", { status: "done", message: `got: ${textOf(tools[1])} | steer seen: ${users.slice(1).join(" / ") || "none"}` });
		return text("All done.");
	},
	quota(n, tools) {
		if (n === 0) return toolCall("bash", { command: "echo HEAVYMARK-ran" });
		if (n === 1) return toolCall("report_to_claude", { status: "done", message: `heavy=[${textOf(tools[0])}]` });
		return text("All done.");
	},
	git(n, tools) {
		const steps = [
			"echo hi > f.txt && git add f.txt && echo ADDED",
			"git -c user.email=w@w -c user.name=w commit -qm 'feat: add f'",
			"git -c user.email=w@w -c user.name=w commit -qm 'feat: add f' --trailer 'Agent: pi' --trailer 'Model: mock/mock-model' && echo COMMITTED",
			"echo two > g.txt && git add g.txt && git -c user.email=w@w -c user.name=w commit -qm 'test: add g' --trailer 'Agent: pi' --trailer 'Model: mock/mock-model' && echo COMMITTED2",
			"git push -q -u origin HEAD 2>&1 && echo PUSHED",
			"git push origin HEAD:main",
			"gh pr create --draft --title x --body y",
			"git switch -q -c sneaky",
			"git switch -q - && echo BACK",
		];
		if (n < steps.length) return toolCall("bash", { command: steps[n] });
		if (n === steps.length) return toolCall("report_to_claude", { status: "done", message: tools.map((t, i) => `${i}=[${textOf(t).trim()}]`).join(" ") });
		return text("All done.");
	},
	budget(n) {
		return toolCall("report_to_claude", { status: "progress", message: `loop ${n}` });
	},
	review(n) {
		if (n === 0) return toolCall("report_to_claude", { status: "done", message: "P1 a.txt:1 REVIEW-MARKER" });
		return text("Reviewed.");
	},
};

http
	.createServer((req, res) => {
		let body = "";
		req.on("data", (d) => (body += d));
		req.on("end", () => {
			if (!req.url.endsWith("/chat/completions")) { res.writeHead(404).end(); return; }
			const msgs = JSON.parse(body).messages ?? [];
			const tools = msgs.filter((m) => m.role === "tool");
			const users = msgs.filter((m) => m.role === "user").map(textOf);
			const first = users[0] ?? "";
			const name = (first.match(/SCENARIO:(\w+)/) ?? [])[1] ?? (first.includes("code reviewer") ? "review" : "default");
			const n = tools.length;
			// slow the first call so a steer can land mid-run
			setTimeout(() => sse(res, scenarios[name](n, tools, users)), n === 0 ? 1500 : 150);
		});
	})
	.listen(port, "127.0.0.1", () => console.error(`mock on ${port}`));
