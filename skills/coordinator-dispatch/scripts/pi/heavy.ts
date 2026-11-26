/**
 * Which bash commands count as heavy work (wait for the machine-wide slot). The one copy of this rule:
 * claude-bridge.ts uses it, pi-worker only passes the env vars through. Pure, no pi imports, so it can be
 * table-tested with plain node (heavy.test.ts). See references/pi-worker.md section 3.
 *
 *   PI_WORKER_HEAVY_RE        replaces the default below (rarely needed)
 *   PI_WORKER_HEAVY_EXTRA_RE  is added to the default (or to the replacement): the usual way for a project
 *                             to name its own heavy commands
 */

// Toolchain builds and full test runs. Matched anywhere in the command (a false positive only costs a grant).
const TOOLS =
	"\\b(?:make|ninja|cmake\\s+--build|cargo\\s+(?:build|test|bench|clippy|nextest)|zig\\s+build|xcodebuild|swift\\s+(?:build|test)|" +
	"(?:npm|pnpm|yarn|bun)\\s+(?:run\\s+)?(?:build|test)|pytest|tox|go\\s+(?:build|test)|gradlew?|mvn|bazel|docker\\s+build)\\b";

// Any release build or run (cargo run --release, swift build -c release is covered by TOOLS).
const RELEASE = "\\s--release\\b";

// The project's own test / acceptance / smoke / e2e / integration scripts (*.sh, *.py), but only when they
// are *run*: the script must sit in command position (start, or after ; & | $( ), optionally behind
// VAR=x / env / time / timeout N / nice / nohup / sudo and a bash|sh|zsh|python|uv run launcher.
// So `bash scripts/cli-acceptance.sh` is heavy while `cat scripts/cli-acceptance.sh` is not.
// The keyword must start the file name or follow - _ . (run-tests.sh yes, latest.sh no).
const SCRIPTS =
	"(?:^|[;&|\\n]|\\$\\()\\s*" +
	"(?:(?:\\w+=\\S*|env|time|nice|nohup|sudo|timeout\\s+\\S+)\\s+)*" +
	"(?:(?:bash|sh|zsh|python3?|uv\\s+run(?:\\s+python3?)?)\\s+(?:-\\S+\\s+)*)?" +
	"(?:\\S*/)?(?:[\\w.-]*[-_.])?(?:acceptance|smoke|e2e|integration|tests?)[\\w.-]*\\.(?:sh|py)\\b";

export const DEFAULT_HEAVY = [TOOLS, RELEASE, SCRIPTS].map((s) => `(?:${s})`).join("|");

export function heavyRe(env: Record<string, string | undefined>): RegExp {
	const base = env.PI_WORKER_HEAVY_RE || DEFAULT_HEAVY;
	const extra = env.PI_WORKER_HEAVY_EXTRA_RE;
	return new RegExp(extra ? `(?:${base})|(?:${extra})` : base, "i");
}
