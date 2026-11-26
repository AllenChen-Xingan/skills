// Table test for the heavy-work matcher. Run: node scripts/pi/heavy.test.ts
import { heavyRe } from "./heavy.ts";

const heavy = [
	// toolchains
	"make -j8",
	"cd core && cargo build",
	"cargo build --release",
	"cargo test -p kb-core",
	"cargo clippy --all-targets -- -D warnings",
	"cargo nextest run",
	"cargo run --release -- index ./docs",
	"npm test",
	"pnpm run build",
	"python -m pytest tests/",
	"go test ./...",
	"xcodebuild -scheme App",
	"./gradlew assemble",
	"docker build -t x .",
	// the project's own test / acceptance / smoke / e2e scripts
	"bash scripts/cli-acceptance.sh",
	"./scripts/cli-acceptance.sh",
	"scripts/smoke.sh",
	"sh ./run-tests.sh",
	"zsh tools/e2e.sh --fast",
	"python3 scripts/acceptance_check.py",
	"uv run python scripts/smoke_test.py",
	"python test_api.py",
	"bash -x scripts/integration-test.sh",
	"cd app && bash scripts/smoke.sh",
	"cargo fmt && ./scripts/e2e-mock.sh",
	"RUST_LOG=debug ./scripts/smoke.sh",
	"timeout 900 bash scripts/cli-acceptance.sh",
	"time ./scripts/smoketest.sh",
	"env CI=1 bash scripts/tests.sh",
];

const light = [
	// reading, searching or editing a script is not running it
	"cat scripts/cli-acceptance.sh",
	"less scripts/cli-acceptance.sh",
	"grep -n cargo scripts/cli-acceptance.sh",
	"ls scripts/test.sh scripts/smoke.sh",
	"head -40 scripts/e2e.sh",
	"chmod +x scripts/smoke.sh",
	"git add scripts/cli-acceptance.sh && git commit -m 'test: add acceptance'",
	"git diff -- scripts/smoke.sh",
	"sed -n 1,20p tools/run-tests.sh",
	"wc -l test_api.py",
	"cat a.txt | grep smoke.sh",
	// names that only contain the letters
	"./latest.sh",
	"bash scripts/contest.sh",
	"python manifest.py",
	// light toolchain commands
	"cargo fmt",
	"cargo check -p kb-core",
	"cargo --version",
	"cat Makefile",
	"ls target/release",
	"npm install",
	"git status",
];

const re = heavyRe({});
let bad = 0;
for (const c of heavy) if (!re.test(c)) { bad++; console.log(`MISS (should be heavy): ${c}`); }
for (const c of light) if (re.test(c)) { bad++; console.log(`FALSE (should be light): ${c}`); }

// replace vs. append
const only = heavyRe({ PI_WORKER_HEAVY_RE: "HEAVYMARK" });
if (!only.test("echo HEAVYMARK") || only.test("cargo build")) { bad++; console.log("PI_WORKER_HEAVY_RE must replace the default"); }
const plus = heavyRe({ PI_WORKER_HEAVY_EXTRA_RE: "\\bjust\\s+bench\\b" });
if (!plus.test("just bench") || !plus.test("cargo build") || plus.test("cat justfile")) { bad++; console.log("PI_WORKER_HEAVY_EXTRA_RE must add to the default"); }
const both = heavyRe({ PI_WORKER_HEAVY_RE: "HEAVYMARK", PI_WORKER_HEAVY_EXTRA_RE: "OTHER" });
if (!both.test("HEAVYMARK") || !both.test("OTHER") || both.test("cargo build")) { bad++; console.log("EXTRA must add to a replaced base too"); }

const n = heavy.length + light.length + 3;
if (bad) { console.log(`FAIL ${bad}/${n}`); process.exit(1); }
console.log(`PASS ${n}/${n}`);
