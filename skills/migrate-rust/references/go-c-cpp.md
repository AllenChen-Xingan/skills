# go-c-cpp.md · Go and C/C++ deltas

**Read this file in full** before porting Go or C/C++ code, or when the task involves `unsafe`, FFI, `extern "C"` boundaries or undefined behavior in the old code. Read py2rust.md §1, §4, §7 with it for the Rust-side traps.

**Most often missed here**
- §2 Go strings are arbitrary bytes. Send invalid UTF-8 through every input channel and see what the old code does.
- §3 Referee output that depends on UB gets detected and registered before goldens are frozen; unwinding across `extern "C"` is a UB risk.
- §4 The unsafe count lives in a ratcheted baseline. Every exported `extern "C"` function catches panics and rejects bad pointers.

Rules: SKILL R1–R6; numbers: Default strictness table. This file: how — what Go and C/C++ quietly guarantee that py2rust.md doesn't cover, plus the unsafe ratchet and no-backflow guards.

**Contents**: §1 How to use · §2 Go → Rust · §3 C/C++ → Rust (incl. UB bytes in referee output) · §4 unsafe ratchet, lints and no-backflow

## 1. How to use

- Old behavior wins. Each item is a possible drift to diff-test, not a ban: run the old implementation on the input, then make the new code do the same. Intended differences go through SKILL R1 and R6.
- Format, same as py2rust: **what drifts** → test (concrete inputs, expected values from the referee) → guard (an `rg` or clippy guard, optional). Every item ends as a test case or a "not tested" line with the reason.
- Start by grepping the old code for each mechanism, so you only build inputs for what is actually used. Count the hits into a fixed denominator (checks §11).
- Rust-side traps shared by every source language (overflow by profile, panic boundaries, HashMap order, async cancellation, blocking in async) are in py2rust §1, §4, §7 and checks §8. Not repeated here.
- The toolchain is part of the referee fingerprint (checks §1). Go: toolchain version and the `go` line in go.mod, which changes semantics such as per-iteration loop variables. C/C++: compiler, version, flags, libc. Pin them before recording goldens.

## 2. Go → Rust

Text and numbers
- **Go `string` is arbitrary bytes; Rust `String` must be UTF-8.** Go passes invalid UTF-8 through and only substitutes U+FFFD when ranging over runes. → For each input channel (argv, env, filenames, request bodies) send one value with invalid bytes; see whether the old code passes, replaces or rejects. → Guard: no `String::from_utf8_lossy` / `to_string_lossy` outside the boundary module; use bytes or `OsStr` where the old code treated text as bytes.
- **`len`, indexing and slicing are bytes.** Go truncation can cut a multi-byte character in half and print it; slicing a Rust `str` there panics. → Truncate at every byte offset of a multi-byte character. → Truncate on `&[u8]`, then apply the old rule to the fragment.
- **`encoding/json` escapes `<`, `>`, `&`, U+2028/U+2029 as `\u…` and writes U+FFFD for invalid UTF-8.** Common Rust encoders don't escape and may reject. → Golden lines containing each. Why: signatures, cache keys and goldens consume the bytes.
- **Integer overflow wraps by spec; shift ≥ width gives 0 (all ones for signed `>>`); `MinInt / -1` returns MinInt.** Rust panics or masks the shift. → Upper bound, lower bound, one past each, shift by width and width+1, `i64::MIN / -1`, run on the shipped build. → Write `wrapping_*` / `checked_*` explicitly where the old code relied on it.
- **JSON numbers decoded into `interface{}` become float64**, so integers above 2^53 silently lose precision; Rust JSON crates keep integers. The lossy behavior is the spec unless the owner decides otherwise. → 2^53 and 2^53+1 through decode-encode.
- **Float text has several Go rule sets** (`%v`, `strconv` shortest, JSON exponent thresholds), and Go's JSON encoder errors on NaN/Inf where a Rust crate may write `null`. → Generate a single-source table from the pinned Go toolchain across magnitudes, -0, NaN, ±Inf, subnormals; compare cell by cell. Don't write the mapping from memory.
- **`time.Time` carries its location and a monotonic reading.** RFC3339 output follows the value's location (TZ env or system zoneinfo), fractional seconds drop trailing zeros, subtraction uses the monotonic clock, `==` compares location too. → TZ matrix including a DST-switch day. → Map each use explicitly: durations/timeouts → `Instant`, persisted or emitted → wall clock.

Errors and failure
- **Error text is an interface.** Wrapping joins messages with `: `; clients, alert regexes and scripts match substrings. → One input per error path; record final text and status; match it the way the consumer does. Count sources: `rg -n 'fmt\.Errorf|errors\.New|status\.Errorf|panic\(' --type go | wc -l`.
- **`errors.Is` / `errors.As` check identity somewhere in the wrap chain.** → For each call site, wrap the error two levels deep and assert the new code takes the same branch via the `source()` chain.
- **Unstable parts of error text** (`%v` of a pointer, map iteration, timestamps). → If consumers match only a stable prefix, register the rest as an equivalence rule (checks §3); if they match the unstable part, make the old side deterministic first, confirm nothing else changed, then port.
- **Typed nil is not nil**: a nil pointer in an `error` makes `err != nil` true. Port what the old code actually does (a non-nil error with no content), not what its author probably meant.
- **Panic scope.** An unrecovered goroutine panic kills the process (exit code 2, all stacks on stderr); `net/http` recovers per request and drops only that connection. A Rust task panic ends only that task. → For each entry point, record who catches the panic in the old code and match it both ways (no longer crashing is also a change: supervisors stop restarting).
- **`defer` ≠ `Drop`.** Defers run LIFO on return or panic, can recover and change named results; defers in a loop pile up until function exit; `os.Exit` and `log.Fatal` skip them all. `Drop` can't return errors or await and doesn't run on abort. → Defers doing IO (flush, rollback, release a remote lock) become explicit close steps, with a test for "does cleanup run on failure".

Concurrency and lifecycle
- **Cancellation propagation.** A Go handler that ignores `ctx` keeps running after the client disconnects; a Rust async server drops the future at any `.await`, leaving multi-step writes half done. → Disconnect at each `.await`; assert the final state equals the old one. If the old code ran to completion, move the side-effect sequence into a detached task or a single transaction; don't "fix" it into cancel-on-disconnect.
- **Port the context chain itself.** List every context: who sets a deadline, who checks `Done()`, which downstream calls carry the deadline (RPC frameworks forward it). Ignore it where the old code ignored it, and note that in the contract. → Run with a very short deadline (for example 1 ms) and count downstream calls; assert count ≤ a ratio derived from the old implementation's downstream call count under the same deadline, written into the contract before the run. Why: a missing propagation shows up as the new code still fanning out after the deadline.
- **Go never blocks other goroutines on a syscall; a sync call inside a Rust executor blocks a worker.** → List each blocking call (DB, cache, file, DNS); confirm async API or `spawn_blocking`; load-test at production concurrency.
- **Channels and `select`.** Unbuffered = handshake, buffer size = backpressure limit, `select` picks randomly among ready cases, closed channels yield zero values. → Match capacity and close semantics per channel; fan-in order was already nondeterministic, so ask whether consumers depend on order before comparing it.
- **Map iteration is deliberately randomized**, so old-vs-old may differ. → Run old-vs-old first. Stable old output means the code sorted: copy the sort. Unstable output: register an equivalence rule per checks §3 with the old-vs-old evidence.
- **Data races and concurrent map writes.** → Run the old tests with `-race`. Racy spots make the old output nondeterministic (checks §8); the locks Rust forces on you can change interleavings; log that in difference attribution.
- **GC tail latency is often the root cause; prove it first** (decide §2). Rust still pays for frees: dropping a ten-million-entry map spikes at the drop site. → Measure tail latency during eviction, rebuild and shutdown; compare RSS under the same load, and long-run resource curves, because silent goroutine leaks become task leaks with a different growth rate.
- **Runtime knobs** (`GOGC`, `GOMEMLIMIT`, `GOMAXPROCS`, `GODEBUG`, container CPU quota) are hidden defaults. → Snapshot both environments; port each as explicit config or record "not ported".
- **`init()` and package vars run before `main` in import order** and may exit on failure. → Make startup steps explicit in the same order; fail each precondition once and diff exit code and stderr. Shutdown: test in-flight completion within the orchestrator's grace period; Go CLIs writing to a closed stdout die silently on SIGPIPE.

Protocols and delivery
- **Zero value vs missing.** Missing JSON fields decode to zero; `Option` or required fields reject old requests. nil slice → `null`, empty slice → `[]`. → Three cases per field: missing, explicit zero, explicit `null`.
- **`encoding/json` is lenient**: case-insensitive key match, unknown fields ignored, last duplicate wins, embedded structs promoted. → Configure each and add one case each.
- **Encoding order and `omitempty`.** Structs in declaration order, maps sorted by key; `omitempty` drops zero, `""`, false, nil, empty containers, but not zero structs. → Zero and non-zero case per `omitempty` field, byte-exact.
- **protobuf.** proto3 scalars equal to default aren't sent; Go preserves unknown fields and unknown enum values on re-encode. → Messages from a newer schema through a forwarding service; compare forwarded bytes. JSON mapping (field names, int64 as strings, default emission) as its own group.
- **gRPC status.** A plain Go error returns `UNKNOWN` with the error text; clients retry on code + substring. Keep the codes, even where a "better" code exists.
- **`net/http` defaults** canonicalize header names, sniff Content-Type, clean paths with redirects. → Replay recorded requests on both; compare status, headers, body.
- **Log lines are a protocol** for alert regexes and pipelines. → List rules that parse log text; inject a fault and confirm the alert fires on the new code.
- **Static binary.** `CGO_ENABLED=0` binaries run on scratch images with pure-Go DNS and cert lookup; Rust links the system libc by default. → Boot once per image × arch × libc cell (delivery §2), then a DNS and TLS smoke test.
- **cgo, build stamping, internal libs.** cgo boundaries keep the C library's thread, locale and signal assumptions (see §3). `-ldflags -X` version stamps and build tags are observable. In-house Go libraries (templating, secrets, metrics, tracing) have no Rust equivalent and get left out of estimates; export the full dependency graph (decide §7) and diff template renders and metric names line by line.

## 3. C/C++ → Rust

Undefined behavior in the referee
- **UB in the old binary is only "what this compiler did".** Out-of-bounds reads, uninitialized reads, signed overflow and aliasing violations produce output that changes with the build. Treating it as expected values pins an accident as spec.
- **Mark UB-tainted bytes.** Run the old referee over the whole golden corpus under MemorySanitizer or valgrind memcheck. Mark every output byte derived from uninitialized memory or an out-of-bounds read as a separate "UB-tainted" channel. Also run UBSan and TSan builds; inputs that trigger reports aren't evidence for the old behavior.
- **Judge "the old implementation is nondeterministic" with cross-build perturbation, not just repeated runs.** Vary `-O` level, compiler, environment size (shifts the stack) and ASLR. Repeated runs of one binary often agree on garbage bytes.
- **Register tainted bytes as an equivalence rule (checks §3) scoped to exact offsets**, with the sanitizer log as evidence; every other byte stays byte-exact. Deterministic, externally visible results (for example the field count returned on truncated input) are kept.
- **Check whether tainted bytes leak data** (stack, heap, key material, other users' records). If so, record it as a security fix in difference attribution, and have the new code write defined bytes.

```sh
valgrind --tool=memcheck --track-origins=yes --error-exitcode=99 --log-file=ub/%p.log ./old < case.in > out.bin
clang -fsanitize=memory -fsanitize-memory-track-origins -g -O1 old.c -o old-msan   # whole program incl. libs instrumented
for o in -O0 -O2 -O3; do cc $o old.c -o old$o; ./old$o < case.in > out$o.bin; done
setarch "$(uname -m)" -R ./old < case.in > out-noaslr.bin                 # ASLR off (Linux)
env -i PAD="$(head -c 8192 /dev/zero | tr '\0' x)" ./old < case.in > out-bigenv.bin
cmp -l out-O0.bin out-O2.bin | awk '{print $1-1}' > tainted-offsets.txt   # 0-based offsets that move
```

- **Preprocessor configurations.** Translators and AI see one platform's macro expansion; other `#ifdef` branches vanish. → Export supported configurations from the build system; translate or review each; dropped branches get an explicit "not ported".

Text and numbers
- **NUL-terminated vs pointer + length.** Interior NULs truncate silently in C; `CString::new` fails on them. → Per entry point: interior NUL, exactly-full buffer, overlong value. State whether lengths include the terminator.
- **Truncation is behavior** (fixed buffers, `snprintf` returning the needed length). Confirm truncation point and return value on the old binary; don't upgrade to full output.
- **Bytes, not characters**; `wchar_t` width and `ctype`/case/multibyte results depend on platform and locale; passing a negative `char` to `isalpha` is UB. → Record one baseline per supported platform × locale; generate tables from the old code.
- **Signed overflow is UB and integer promotion hides it.** Two `uint8_t` add in `int` in C but overflow in Rust `u8`; mixed signed/unsigned comparisons convert negatives to huge values. → Boundary values per mixed-width or mixed-sign expression; write wrapping/saturating/checked explicitly at each site.
- **`char` signedness and `long` width are per platform.** → Use `core::ffi::c_char`, `c_long`, `libc::time_t`, `off_t`, `size_t`; run checks on each target arch. Cases past 4 GB files and 32-bit time.
- **Float output varies with flags** (x87 extended precision, FMA contraction, `-ffast-math`). Pin the old flags into the fingerprint; derive any tolerance from the old code's own spread across builds, escalated per R6(b). `printf` `%g` and locale decimal points: single-source table from the old binary.

Errors, concurrency, lifecycle
- **Return codes per function** (0/-1, negative errno, NULL, out-param status): map `Result` back at the seam and diff the code values. `errno` is thread-local and only meaningful on failure; check which call each read refers to. Out-params half-written on failure are read by callers: compare them on failure paths too.
- **`assert` disappears under `NDEBUG`.** Judge failure behavior on the shipped build, not the debug one. A segfault on bad input is also a failure mode; changing it to an error exit changes supervisors and retries: log it as an intended difference.
- **C++ exceptions and `setjmp`/`longjmp` stay on the C++/C side.** Catch in a thin C++ shim and convert to codes; a panic must not unwind into C/C++ (§4 boundary). Record which exceptions escape and which `noexcept` functions would terminate.
- **Unwinding across a plain `extern "C"` boundary is undefined behavior** for a C++ exception entering Rust, and a Rust panic leaving an `extern "C"` function aborts the process on current toolchains. List every such boundary as a UB risk and catch on both sides (§4).
- **Races that "happen to work"** on strong memory models; `volatile` gives neither atomicity nor ordering. → Run TSan on the old concurrent tests, decide the intended semantics per race, then pick the Rust primitive. Don't wrap the race in `unsafe` and carry it over.
- **Non-reentrant libc** (`strtok`, `localtime`, `getenv` buffers) shares static buffers. Diff single-threaded first, concurrency separately. List lock order and callbacks invoked while holding a lock.
- **Static init/destruction order, constructor attributes, `atexit`.** Rust has no pre-main code and doesn't run static destructors. Schedule each startup/exit action explicitly and test both ends.
- **stdout is line-buffered on a tty, fully buffered on a pipe**; stderr unbuffered. Interleaving and bytes written before a kill are observable: record tty and pipe baselines. Diff signal dispositions and masks (children inherit them); keep handlers async-signal-safe. `fork` without `exec` keeps one thread and possibly held locks.

ABI, ownership, delivery
- **Translate macros and templates after expansion** (`-E`, instantiation): double evaluation, precedence, overload resolution. One case per macro with side-effecting args and per overload-triggering argument type.
- **Ownership lives in comments.** Record per interface: borrowed or transferred, who frees, with which allocator. Each "hand out" function gets a "take back"; memory is freed by the side that allocated it.
- **Aliasing is legal in C and UB in Rust.** Literal translations keep raw pointers; switch to references only after proving non-overlap. Iterator invalidation and use-after-move in C++: confirm with sanitizers on the old side first.
- **The C header is the single source for layout.** Generate bindings (bindgen); CI asserts size, alignment and every field offset. Bitfields and packing follow the C compiler: assert measured offsets.
- **When Rust replaces a linked C library, the ABI is the contract**: symbol names and versions, calling convention, headers, soname. Downstream binaries built against the old headers must link and pass the checks unchanged.
- **Bridges cost something** (cxx, autocxx, bindgen): unsupported std containers, extra smart pointers and copies, generated-code bloat. Measure all three on one sample module; time-box any transitional perf regression. **The build system does more than compile** (install, config headers, platform probes, end-to-end tests). List every output and probe before deleting CMake. glibc vs musl is its own matrix axis (locale, DNS, `getopt` reordering).

## 4. unsafe ratchet, lints and no-backflow

The unsafe ratchet
- Store the new code's unsafe count in a baseline file, ratcheted like the guards allowlist (py2rust "Guards in general"); lower the baseline in the same commit as the drop. Track raw-pointer derefs the same way for translated code.
- Target 0 outside designated boundary modules (FFI, bindings). Set `unsafe_code = "deny"` workspace-wide and allow it only in those modules; guard that the allow appears nowhere else.
- Every unsafe block has a `// SAFETY:` comment naming its preconditions (non-null, initialized, no alias, lifetime), enforced by `clippy::undocumented_unsafe_blocks` at deny, plus a test that breaks the precondition or a note on why it is unreachable.
- Every crate containing unsafe runs Miri and sanitizer-enabled fuzzing; UB count and crash count = 0. Miri can't run foreign calls: those paths get ASan fuzzing and a "not covered by Miri" line.
- Every exported `extern "C"` function catches panics and returns an error code, and rejects null, zero-length and misaligned pointer arguments. Test each with a panicking input and bad pointers; assert the process survives.

```sh
n=$(rg -c '\bunsafe\b' --type rust crates/ | awk -F: '{s+=$2} END{print s+0}')
[ "$n" -le "$(cat unsafe-baseline.txt)" ] || { echo "unsafe count rose: $n"; exit 1; }
rg -l '#!?\[allow\(unsafe_code\)\]' --type rust | rg -v '^crates/[^/]+/src/ffi/' && exit 1 || true
cargo +nightly miri test -p <crate-with-unsafe>
cargo +nightly fuzz run <target> --sanitizer address -- -max_total_time=600
```

Automatic translators (c2rust, or AI literal translation) go in two steps
1. Mechanical translation, kept green on the same differential checks. No behavior change.
2. Unsafe removal: raw pointers → references, manual memory → ownership, error codes → `Result`, one unit per commit, each through the same checks, each lowering the ratchet (SKILL R4).

Remaining unsafe workarounds and literal-translation TODOs are transitional artifacts: owner, deadline, deletion condition (SKILL R5).
When memory safety is the reason for the migration, don't claim completion or delete the old code (closeout §3) until these gates pass: ratchet at target, every block documented, Miri and fuzz at 0. Why: otherwise the migration ships the problem it was meant to fix under a new name.

Lints
- After fixing a class of drift, ban it with a lint (`unwrap_used`, `as` narrowing via `cast_possible_truncation`, default hashers on output paths, blocking calls in async via `disallowed_methods` / `disallowed_types`). Allowed uses go into the one guards allowlist (ratchet rule: py2rust "Guards in general").
- Prove the lint can fail: commit a deliberate violation in a new or edge member crate, see CI go red, revert. Why: a misconfigured lint is silently off.
- Workspace lints apply only to members that declare `[lints] workspace = true`; new crates don't by default. Check every member:

```sh
cargo metadata --no-deps --format-version 1 | jq -r '.packages[].manifest_path' |
  while read -r m; do awk '/^\[lints\]/{f=1;next} /^\[/{f=0} f&&/workspace *= *true/{ok=1} END{exit !ok}' "$m" || echo "not inheriting: $m"; done |
  tee /dev/stderr | [ "$(wc -l)" -eq 0 ]
```

- Warn level doesn't block: set deny, run CI with `-D warnings`. Macro output, generated code, `build.rs` and tests may escape lints; `rg`-count them too, or state they aren't covered.

No-backflow
- The old library must not be re-linked. Guard sources and artifacts: `rg -n 'rustc-link-lib=.*<oldlib>|#\[link\(name *= *"<oldlib>"'` and the old `-sys` crate in `Cargo.lock` = 0; on the shipped binary, `ldd` / `otool -L` show no old library and `nm` shows no old symbol prefix. For Go, no calls to the old service endpoint or module path remain. Wire these into the close-out residue check (closeout §3).
