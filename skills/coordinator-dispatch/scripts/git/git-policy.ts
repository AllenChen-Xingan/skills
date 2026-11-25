/**
 * Git policy for pi workers (pure, no pi imports, so it can be unit-tested with plain node).
 * Workers commit and push freely, but only their own branch; everything that changes
 * shared history or other people's refs stays with the coordinator. See references/git-workflow.md.
 */

export interface GitPolicy {
	branch: string; // the worker's own branch; "" = no branch restriction
	base: string; // integration branch, e.g. "origin/main"; always protected
	protected: string; // regex alternation of protected branch names; "" = default
}

export const DEFAULT_PROTECTED = "main|master|develop|trunk|release/.*|production";

/** Returns why a shell command breaks the worker git policy, or undefined if it is fine. */
export function gitViolation(cmd: string, policy: GitPolicy): string | undefined {
	const BRANCH = policy.branch;
	const PROTECTED = new RegExp(`^(${policy.protected || DEFAULT_PROTECTED})$`);
	const isProtected = (b: string) => PROTECTED.test(b) || (policy.base !== "" && b === policy.base.replace(/^origin\//, ""));
	if (/\bgh\s+pr\s+merge\b/.test(cmd)) return "Merging PRs is the coordinator's job; report done and let it merge.";
	if (/\bgh\s+(release|repo\s+(delete|edit|rename|archive))\b/.test(cmd)) return "Releases and repo settings are the coordinator's job.";
	for (const part of cmd.split(/&&|\|\||;|\||\n/)) {
		// drop shell redirections (2>&1, >log, 2>/dev/null, <in) so they are not read as refspecs
		const clean = part.replace(/\d*>&\d+|\d*>>?\s*\S+|<\s*\S+/g, " ");
		const m = clean.trim().match(/^(?:\w+=\S*\s+)*git\s+(?:(?:-C|-c)\s+\S+\s+|--[\w-]+(?:=\S+)?\s+)*([\w-]+)(.*)$/s);
		if (!m) continue;
		const sub = m[1];
		const rest = m[2] ?? "";
		const args = rest.trim().split(/\s+/).filter(Boolean);
		const flags = args.filter((a) => a.startsWith("-"));
		const words = args.filter((a) => !a.startsWith("-"));
		if (sub === "push") {
			if (flags.some((f) => f === "-f" || f === "--force") || words.some((w) => w.startsWith("+")))
				return "Plain force push is not allowed; after a rebase of your own branch use --force-with-lease.";
			if (flags.some((f) => /^(-d|--delete|--mirror|--all|--tags|--prune)$/.test(f)))
				return "Deleting remote refs or pushing all branches/tags is the coordinator's job.";
			for (const ref of words.slice(1)) {
				if (ref.startsWith(":") || ref.endsWith(":")) return "Deleting remote branches is the coordinator's job.";
				const dst = (ref.includes(":") ? ref.split(":").pop()! : ref).replace(/^refs\/heads\//, "");
				if (dst === "HEAD") continue;
				if (isProtected(dst)) return `Never push to ${dst}; push only your own branch ${BRANCH || "(see your brief)"}.`;
				if (BRANCH && dst !== BRANCH) return `Push only your own branch ${BRANCH}, not ${dst}.`;
			}
		}
		if (sub === "branch" && flags.some((f) => /^(-d|-D|--delete|-m|-M|--move|-f|--force)$/.test(f)))
			return "Deleting, renaming or force-moving branches is the coordinator's job.";
		if (sub === "tag" && (words.length > 0 || flags.some((f) => /^(-d|-a|-s|-f)$/.test(f))))
			return "Tags are the coordinator's job.";
		if (sub === "config" && !flags.some((f) => /^(--get|--get-all|--list|-l|--show-origin)$/.test(f)))
			return "Do not change git config.";
		if (sub === "worktree" && words[0] !== "list") return "Worktrees are managed by the coordinator.";
		if (sub === "filter-branch" || sub === "filter-repo" || sub === "replace") return "History rewriting tools are not allowed.";
		if ((sub === "switch" || sub === "checkout") && words.some((w) => isProtected(w)) && !args.includes("--"))
			return `Stay on your own branch ${BRANCH || ""}; read other branches with git show/diff/log instead.`;
	}
	return undefined;
}

