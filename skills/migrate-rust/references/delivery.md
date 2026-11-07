# delivery · The delivery surface is part of the contract

**Read this file in full** before estimating or shipping anything users install: wheels, install failures, CI layout or slow CI, build profiles, licenses, offline builds, backports, type stubs.

**Most often missed here**
- §2 Build the wheel matrix from real download or telemetry shares; every cell ≥0.5% gets an explicit destination.
- §3 Install in a clean image with no toolchain and `--only-binary=:all:`. Before fixing an install failure, reproduce it there with the current release and archive the red output (SKILL "How to work" item 1).
- §4 `cargo test` and the existing tests run in CI as a required gate; type stubs are checked by stubtest.

Rules: SKILL R1–R6 (this file expands R5: the delivery surface is contract); numbers: Default strictness table. This file: how — inventory §1, wheels §2–3, CI and builds §4–6, licenses and offline builds §7–8, release lines and install artifacts §9–10.

## 1. Delivery surface inventory: list it all before estimating

Add a "delivery surface" table to `contract.md`. One row per surface: old state, new plan, who uses it (a count), how it is accepted. Write a row for every item below. If one doesn't apply, write "n/a" plus one sentence of reason.

| Surface | What to check in the old version |
|---|---|
| wheel platform × interpreter matrix | Share by platform / libc / interpreter, from download stats or telemetry |
| Fallback where no wheel exists | Does the old version install on PyPy, Pyodide, armv7l, Cygwin, old glibc? |
| sdist and source builds | Do distros (Debian, Fedora, conda-forge, Homebrew) build from source? |
| Licenses | Old dependency count and licenses; new total transitive dependency count |
| Offline reproducible builds | Do packagers build without network? Do they require two builds to match? |
| Build profiles | Which profile ships; what contributors get by default locally |
| Feature combinations | Which features or extras are public |
| Release lines | Which branches are still maintained, and where downstream pins them |
| Install artifacts | Command names, `python -m` entry, man pages, completions, data files, public names in the package |
| Upgrade path | `pip install -U`, self-update, how Docker images pin the version |

*Why: delivery work is often as large as the translation itself. If it isn't in the estimate, the schedule only covers "translation done". Packager bug reports are often entirely about delivery, with nothing about function behavior.*

## 2. Wheel matrix: order by real users, spell out every cell

**Use real data.** Build the matrix from the actual platform and interpreter distribution in download stats or telemetry, not from CI template defaults. Every cell with ≥0.5% share gets an explicit destination: ship a wheel, use the pure-Python fallback, or list it under "no longer supported" with an explanation. *Why: CI action defaults often build only a handful of wheels. Old-glibc clusters, old interpreter images and Intel Macs all fail to install.*

**List every cell** with platform tag, interpreter tag, ABI tag, build method and smoke-test environment:

```
| platform tag                | interpreter | ABI     | build                         | smoke image            |
| manylinux_2_17_x86_64       | cp39–cp312  | abi3    | maturin (manylinux container) | centos:7 + py3.9       |
| musllinux_1_2_x86_64        | cp39–cp312  | abi3    | maturin (musllinux container) | python:3.12-alpine     |
| macosx_11_0_arm64           | cp313t      | cp313t  | separate job (not abi3)       | macOS runner + 3.13t   |
| (no wheel) linux_armv7l     | —           | —       | pure-Python fallback          | arm32v7/python         |
```

Possible differences to diff-test while building the matrix. Each one is a way the new matrix can differ from the old "installs anywhere"; the old behavior wins:

- **glibc floor**: a `manylinux_2_28` wheel is not selected on glibc 2.17. pip silently falls back to the sdist and then fails because cargo is missing. If users run old glibc, ship `manylinux2014` (i.e. `manylinux_2_17`). Check with `auditwheel show dist/*.whl` that the tag matches the symbol versions actually linked.
- **musl**: Alpine and some arm64 base images need `musllinux` wheels. Changing the base image is itself a delivery change; run the differential suite before and after.
- **macOS**: ship x86_64 and arm64 separately, or universal2. Use `delocate-listdeps --all dist/*.whl` to confirm nothing links to the build machine's Homebrew dylibs. `MACOSX_DEPLOYMENT_TARGET` must match the minimum version in the tag.
  - Hand-written link args (e.g. your own `-undefined dynamic_lookup`) tend to fail on the system `/usr/bin/python3` with `Library not loaded: @rpath/Python3.framework`. Let maturin generate link args by default, and install once on the system Python to verify.
- **abi3 floor**: with several `abi3-pyXY` features enabled, the lowest one wins. One leftover low-version feature silently pulls the floor back down. Confirm with `cargo tree -e features -i pyo3` that exactly one is in effect.
- **abi3 missing capabilities**: some C APIs only enter the stable ABI at higher versions (e.g. the buffer protocol; see the abi3 limitations section of the PyO3 docs).
  - If you depend on one, either raise the abi3 floor and ship version-specific wheels for lower versions, or drop abi3 entirely. Compiling is not proof you are still zero-copy: on the lowest supported version, diff-test the old zero-copy behavior (e.g. assert memory is shared, not copied).
- **free-threaded (3.13t, 3.14t)**: free-threaded interpreters don't load abi3 wheels. When building for 3.13t, PyO3 may ignore the abi3 feature with only a warning, and CI stays green.
  - Ship a separate version-specific `cp313t` wheel, and assert in the matrix check that the tag really exists. If unsupported, say so in scope and state which path these users fall to (fallback or source build).
- **Is the GIL really off under free-threading?** If the module doesn't declare that it runs without the GIL (in PyO3, something like `#[pymodule(gil_used = false)]`), importing it silently re-enables the GIL with only a RuntimeWarning.
  - In smoke tests, assert `sys._is_gil_enabled()` (private API since 3.13) is False. Before declaring, confirm that global caches initialize once without the GIL, or that multiple initializations are harmless.
- **Platforms without wheels**: the old pure-Python version installs on PyPy, Pyodide, armv7l. That is contract. By default, keep a pure-Python fallback: degrade when the native module fails to import, plus an environment variable that forces pure Python, so these users can install without a Rust toolchain. If you keep the fallback, run the same test suite in both modes in CI. *Why: an untested fallback rots silently, and it usually takes a long time before anyone notices.*
- **Platforms without a Rust target** (e.g. Cygwin): check `rustup target list` and the Rust platform support page first, then decide what to tell users (e.g. an end date for security fixes on the old version, or WSL instructions). Record it in `transitions.md`.

**Count the real matrix size.** When abi3 shrinks the matrix, add back the exceptions above (free-threaded, version-specific wheels for missing abi3 capabilities) before reporting a number. *Why: "one abi3 wheel per platform" often doubles once the exceptions are added back.*

## 3. Clean-environment install smoke test

For every matrix cell, install for real in a clean image with **no Rust toolchain and no source tree**:

```sh
cd /tmp                                   # leave the source tree so you don't import the repo's package
python -m pip install --no-index --find-links /dist --only-binary=:all: <pkg>==<ver>
python -c "import <pkg>, <pkg>._native as n; assert n.__build_sha__ == '$GIT_SHA'"
```

- With `--only-binary=:all:`, pip cannot silently fall back to the sdist; a missing wheel goes red at once. *Why: on old glibc pip doesn't say "no wheel"; it fails later at the cargo step.*
- Have the build write the commit into a module attribute (e.g. build.rs injects `__build_sha__`) and assert it equals this CI run's commit. `__file__` under site-packages doesn't prove the artifact came from this build. *Why: `PYTHONPATH` can load a stale .so from an old build directory: green locally, red in CI.*
- Import is only step one. In each class of real environment, run a small old-vs-new differential set against the installed wheel (not just the new unit tests); the output diff must be byte-empty. Convert pixels or arrays to signed types before comparing, to avoid uint8 wraparound.
- When changing base image, libc or Python distribution channel, run the same inputs on the old and new images; ship only when the diff is empty. Include replaced base commands (`date`, `stat` and the like) in the comparison.
- For targets you can't run, run `cargo check --target <triple>` (or use `cross`) on every PR at least. Type errors inside `#[cfg(target_os = ...)]` branches only surface when compiling for that target. Verify clippy's "unnecessary cast" on each platform before removing it.
- Pick smoke-test interpreters from real users too: one system Python, one conda Python, one `module load` Python.

## 4. CI: required jobs, fast layer and full layer

**`cargo test --workspace` must run in CI.** The two usual blockers are in `Cargo.toml`:

- `crate-type` lists only `cdylib`, so integration tests under `tests/` can't `use` the crate. Change it to `["cdylib", "rlib"]`.
- PyO3's `extension-module` feature, if on by default, disables linking against libpython, and `cargo test` fails with `undefined reference to _Py...`. Don't enable it in default features; enable it only for maturin builds. Newer maturin handles this itself and PyO3 has deprecated the feature; check from which version against the locked one.

Check: `grep -n 'extension-module' Cargo.toml` shows it absent from default deps; `grep -n 'crate-type' Cargo.toml` includes `rlib`; the `cargo test` count in the CI log is >0.

**Type stubs are contract.** If the package ships `.pyi` stubs or `py.typed`, run `python -m mypy.stubtest <module>` against the built extension as a required CI job (0 errors), and diff the public names in the stubs against the old version. Why: a stub that drifts from the runtime breaks type-checked callers without any test going red.

**CI must test this build's artifact.** Use the `__build_sha__` check from §3. With both old and new backends, have each export its own name (e.g. `_backend_name()`). Differential tests first assert the two names differ, then compare results, so "old vs new" is never one implementation compared with itself.

**Two layers, driven by the same checks.** They differ only in build, sampling and matrix:

- **Fast layer, every PR push, within the PR budget.** Budget defaults to ≤30 minutes unless the project has its own. Existing tests stay here by default. It uses a fast build (no LTO), runs a sample of the differential corpus with a seed that rotates per commit so coverage accumulates to the full corpus, tests the main platform fully, smoke-tests the others, and runs a compile-only check for every shipped platform and feature combination (§3, §6).
- **Full layer, on merge (queue) or nightly, and before every ramp stage.** It uses the shipped build profile and runs the full differential corpus, the per-load-class benchmarks (checks §10) and the sanitizers, across the full platform and feature matrix. Every §2 cell is built and tested at least once.
- **Claims come from the full layer.** "Equivalent" or "meets target" counts only from a green full layer on the shipped profile; the report names the layer and the build. A red full layer blocks release and the next ramp stage; bisect over the merges since the last green full run.
- **Perf results count only from the shipped profile.** The perf step checks the profile and fails otherwise, e.g. `jq -e '.build.profile == .build.shipped_profile' perf-result.json`.
- **Layering never deletes coverage.** A cell may move from the fast layer to the full layer, never out of CI; a moved cell keeps at least its compile check in the fast layer. Matched old/new cases in the fast layer don't drop below what they were before layering. Record the fast layer's measured time and the full layer's detection lag (merge to catch) in the results file.

**When the fast layer exceeds its budget, find time in this order:**

1. Time each step to find the big one: `gh run view <id> --json jobs` gives per-job and per-step durations. The big one is often the build profile (e.g. property tests against a debug-built extension), not overly strict tests.
2. Cache dependency builds (`Swatinem/rust-cache` or sccache).
3. Change the test build profile (see §5). Don't turn on LTO for tests.
4. Remove duplicate builds: build the wheel once and pass it as an artifact to per-interpreter test jobs instead of rebuilding in each; split parallelizable jobs.
5. Shrink the matrix: one wheel per platform where abi3 allows; turn feature combinations into a check-only powerset job (§6); on PRs, run only smoke plus `cargo check --target` for non-Linux platforms and move their full runs to the full layer. This step is layering; do it only after 1–4 are exhausted, under the rules above.
6. Raising `deadline` or `max_examples`, or moving new-backend tests out of CI, loosens checks rather than speeding them up. Handle it under SKILL R2 (loosening is escalated to the owner).

Check: `gh run list --workflow <ci.yml> --json durationMs,conclusion -L 20`; take the median over PR-triggered runs and compare it with the budget written in advance in `acceptance.md`.

## 5. Build profiles: release, dev and the shipped profile

- Put `lto = "fat"` and `codegen-units = 1` in a separate `[profile.dist]` (`inherits = "release"`) used only for releases. `make test`, `cargo test` and contributors default to the dev/test profile. *Why: with LTO release as the default, contributors' cold builds become very slow, and outside PRs complain or give up.*
- If the extension is too slow to test in debug, set `opt-level = 1` in `[profile.dev]` and `opt-level = 3` in `[profile.dev.package."*"]`, or use `maturin develop --release`. No LTO.
- Benchmark the shipped profile and record the artifact hash (e.g. a sha256 prefix of the .so) in the report, so each number traces to one artifact.
- These profile options change observable behavior. Diff-test before changing them:
  - `panic = "abort"`: PyO3 normally turns a panic into a Python exception; with abort the whole process crashes.
  - `strip`, `debug`: affect crash backtraces and what users can attach to bug reports.
  - `overflow-checks`: off by default in release, so integer overflow wraps instead of panicking.
- Link choices are delivery surface too. Linking a system framework to restore old behavior, for instance, costs startup time. Record such costs in `decisions.md`; don't quietly remove them before release to get faster numbers.

## 6. Feature combinations

- On every PR, run a check-only powerset job: `cargo hack check --feature-powerset --no-dev-deps`. If combinations explode, add `--depth 2`, plus two extra cells: `--no-default-features` and `--all-features`. Don't test only default to shrink the matrix. *Why: some compile errors only appear under a particular non-default feature combination.*
- Run full tests only on default and on the feature set the shipped wheel actually uses. First confirm that `[tool.maturin] features` in `pyproject.toml` and the CI matrix name the same set.
- If the Python side has extras (`pkg[cli]` and the like), compare, extra by extra, the entry points available after installing old vs new.

## 7. License allowlist

- The old pure-Python package may have had zero dependencies; the new wheel statically links a hundred crates, and license obligations change with it. That is a contract change; write it in `contract.md`.
- Add cargo-deny with an allowlist in `[licenses]` of `deny.toml`, and run `cargo deny check licenses` (plus `bans` and `sources`) in CI.
- If a crate has no license field, replace it, or add the field upstream, wait for a release and lock the new version. `exceptions` or `clarify` only make the check green; packagers need a complete transitive license list, and the audit still fails.
- If distros require third-party license texts in the package, generate them with a tool like `cargo about generate` and confirm they ship in both wheel and sdist (check with `unzip -l` and `tar tzf`).
- New dependencies still go through the project's existing dependency approval gate (see SKILL R6, the "out of scope" item). The allowlist is the machine-checked floor, not a substitute for approval.

## 8. Offline reproducible builds and pinned toolchain

**Offline and reproducible:**
- Commit `Cargo.lock` and include it in the sdist. "Libraries don't commit the lock" applies only to pure Rust libraries. A Python extension's sdist is a final artifact; without a lock every build re-resolves dependencies. Check: `tar tzf dist/*.tar.gz | grep -c Cargo.lock` equals 1.
- Document offline steps for packagers: `cargo vendor vendor/` plus source replacement in `.cargo/config.toml`, then `cargo build --frozen` (`--frozen` = `--locked --offline`). Verify once by building the wheel from the sdist and running tests in a networkless container: `docker run --network none ...`.
- Minimum reproducibility: two builds resolve the same dependency set (identical `cargo tree --locked` output). The next level is byte-identical wheels: set `SOURCE_DATE_EPOCH`, strip build paths with `--remap-path-prefix`, and compare the sha256 of two builds.
- pytest must run offline against the **installed wheel**, without the source tree and without downloading fixtures. Packagers test the artifacts they built themselves.

**Pinned toolchain** (version sources, full-version assertions and local = CI = referee: checks §1):
- Pin an exact version in `rust-toolchain.toml` (e.g. `channel = "1.xx.y"`) with components and targets. Set `rust-version` (MSRV) in `Cargo.toml` and keep an MSRV job in CI. Give maturin lower and upper bounds in `[build-system] requires` of `pyproject.toml`.
- At the start of every CI job, print `rustc -Vv`, `cargo -V`, `maturin -V`, `python -VV` and assert them against the pinned values per checks §1.
- Upgrading a dependency crate can swap in new data tables (Unicode, tzdb). Treat it as a separate behavior change under SKILL R4; don't fold it into `cargo update`.
- When shipping plugins as Rust dylibs: the Rust ABI is not stable across rustc versions, so a host compiler upgrade breaks plugin loading. Use a C ABI or a stable-ABI scheme at the plugin boundary, and add a load test across compiler versions.

## 9. Backports across release lines

Keep a ledger row per maintained line in `transitions.md`:

```
| line        | PyO3 | rustc | wheel matrix          | downstream pins             | end date   |
| release/1.2 | 0.23 | 1.8x  | abi3-py39 only        | 3 internal services ==1.2.* | <date>     |
| main 1.4    | 0.26 | 1.9x  | abi3-py39 + cp313t    | —                           | —          |
```

- A hotfix backport fixes only that one thing and keeps the line's existing matrix. Don't claim support for new interpreters along the way. *Why: an old line that ships only abi3 can't install on free-threaded Python anyway; adding 3.13t in a backport is an empty promise.*
- The same fix may need different APIs on different lines; PyO3's one-time initialization primitive, for example, has different names across versions. Look up APIs per line against that line's locked version, and on each line reproduce first, then fix, then verify.
- Give each maintained line a scheduled CI run (weekly is enough), so toolchain or image drift doesn't surface only at backport time as "this hasn't built for months". Maintained lines are transitional artifacts; for owner, deadline and deletion condition see SKILL R5.

## 10. Install artifacts and upgrade path

Everything a user can see or invoke after installing the old version is contract. List it first, then diff-test:

```sh
pip show -f <pkg>==<old> > old-files.txt     # files the old version installed
unzip -l dist/<pkg>-<new>-*.whl > new-files.txt
python -c "import <pkg>; print(sorted(n for n in dir(<pkg>) if not n.startswith('_')))"
```

Possible differences to diff-test; the old behavior wins:

- **Command names and entry points**: `console_scripts` names, `python -m <pkg>`, exit codes, shebang. To keep the `pip install` path for a Rust binary, maturin's `bindings = "bin"` packages the binary as a platform wheel.
- **Public names in the package**: compare non-underscore names in old and new `dir(pkg)` one by one; the old list wins. Prefix new native modules, switches and helpers with `_` by default (e.g. `pkg._native`, `import os as _os`). *Why: upstream tests may count public names, and one extra `import os` in the wrapper breaks them.*
- **Man pages and shell completions**: if the old version installed man pages, install them in the same place. The completion protocol is an interface users' shell configs depend on.
  - With old click completions, users' rc files use the env-var protocol (e.g. `_PROG_COMPLETE=zsh_source prog`). Before switching to clap-generated completions, either keep the old invocation working or escalate to the owner per SKILL R6(b).
  - Output from generators (e.g. `clap_mangen`, `clap_complete`) goes into the repo or into the build artifact list.
- **Data files and default paths**: default locations of config files and cache directories, and data files installed with the package. Export platform-dependent defaults per platform and compare; one machine's output is not the single source.
- **Upgrade path**: rehearse three paths against a local index (a directory plus `pip install --index-url file://...`, or devpi):
  - `pip install -U` from the old version reaches the new one directly;
  - platforms without wheels stay on the old major version instead of getting an sdist that won't build (control with `requires-python`, platform markers, or by not shipping an sdist);
  - the old version's built-in self-update command recognizes the new artifact and rolls back on failure. If the update path itself is what breaks, fixes can't reach users, so rehearse it before release and prepare an out-of-band recovery channel.
- **Clean uninstall**: after `pip uninstall`, no leftover binaries, completion files or caches.
- **Client-distributed artifacts** (desktop, mobile, CLI packages): you can't roll these back server-side, so ramp them by release channel rather than by traffic share; see closeout §4.

## 11. Check summary

Each section above ends with, or contains, its own check; put those commands in CI or `acceptance.md` as written there. There is no separate summary table, so a check changed in its section can't drift from a copy here.
