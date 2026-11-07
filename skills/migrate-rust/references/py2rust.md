# Python → Rust/PyO3: likely differences

**Read this file in full** before you write Rust or PyO3 code for a Python original, and on any port for the Rust-side traps (overflow, panic boundary, HashMap order, async and blocking), or when outputs differ, a panic reaches Python, or a call hangs.

**Most often missed here**
- §1 Rounding and float-to-text differ by default (Python rounds half to even, Rust `f64::round` half away from zero). On money paths a guard keeps `round_dp(` / `.round()` at 0, and any type change (Decimal ↔ f64) is a difference to diff-test.
- §4 A panic becomes `PanicException`, which `except Exception` doesn't catch. Map every expected error back to the class the old code raised.
- §5 Extract inputs into Rust-owned data first, then release the GIL. Never call Python while holding a Rust lock.
- §10 Export the old per-field defaults table and diff it key by key against the new one.

Rules: SKILL R1–R6; numbers: Default strictness table. This file: how — **likely Python → Rust/PyO3 differences to diff-test**, not bans: run the inputs on the old code first, then make the new code do the same (f64 stays f64, wraparound is written explicitly).

Each item has the form: **difference** → diff-test (concrete inputs) → guard (source scan, optional).

## Contents

1. Numbers and formatting · 2. Text and encoding · 3. Time · 4. Exceptions and the panic boundary
5. GIL, global state and reload · 6. Object protocols · 7. async and blocking · 8. Side effects: atomicity and exactly-once
9. Processes and the OS · 10. Defaults · 11. Output rewritten by the old runtime and frameworks · 12. Dependencies and structure · 13. Using this list for other migrations

## Guards in general

- Each `rg` guard asserts 0 hits in CI. Clippy restriction lints go in `#![deny(...)]` at the crate root or in `[lints.clippy]`.
- Hits you must keep go in one `guards-allowlist` file, one `file:line:reason` per line. CI asserts the count now ≤ the count at the last commit; it only goes down. Inline comment exemptions in source are not accepted.
- Panic guards (`unwrap_used`, `expect_used`, `indexing_slicing`, `string_slice`, `panic`) take no exemptions; see the source-guards row of the Default strictness table.
- Guards for `unsafe` (the unsafe ratchet, lints, no-backflow) live in go-c-cpp §4.

## 1. Numbers and formatting

- **Rounding.** Python `round()` on floats rounds half to even, and `round(2.675, 2)` gives 2.67 (the binary value is slightly below). `Decimal` follows its context's rounding. Rust `f64::round` rounds half away from zero; `round_ties_even` also exists. Measure how `{:.2}` breaks ties on the locked rustc.
  - Diff-test: 0.5, 1.5, 2.5, -0.5, 2.675, ±0.125. Guard: on money paths `rg 'round_dp\(|\.round\(\)'` is 0. Why: one cent off is a reconciliation difference.
- **Float to text.** Python `repr` is shortest round-trip: `1e-05`, `1e+16`, `nan`, `-0.0`, `1.0`. Rust `Display` gives `0.00001`, `10000000000000000`, `NaN`, `-0`, `1`.
  - Diff-test: a golden table compared line by line as text, including 1e-05, 1e16, -0.0, nan, inf, 1e300, 5e-324, `0.1+0.2`, `1e-7`.
  - Put pairs on both sides of each switch point: repr switches at exponent < -4 or ≥ 16 (`1e-4`/`1e-5`, `1e15`/`1e16`); `%g` switches at 6 significant digits (`123456`/`1234567`, `0.0001`/`0.00001`).
  - Give every format the old code uses (`repr`, `str`, f-string, `%`, `format`) its own column. Rust has no ready `%g`, and ryu-style crates don't match repr exactly; measure on the locked version.
  - Guard: `rg 'format!\("\{\}", .*f64|to_string\(\)'` hits only inside the formatting module. Why: `NaN` and `nan` are different contracts.
- **Integer width and overflow.** Python ints don't overflow. Rust fixed-width ints panic in debug and silently wrap in release. Where the old code used fixed-width types like numpy uint8, it already wrapped; write that out with `wrapping_add`.
  - Diff-test: i64::MAX±1, 2**64, -2**63-1, uint8 255+1 and 0-1; run both debug and release. Why: all green in debug doesn't mean release is right.
  - Guard: `clippy::arithmetic_side_effects`, `cast_possible_truncation`, `cast_sign_loss`.
- **`//` and `%`.** Python floors, and the remainder takes the divisor's sign (`-7//2=-4`, `-7%3=2`, `7%-3=-2`). Rust truncates toward zero; `rem_euclid` is always non-negative, so it also mismatches when the divisor is negative.
  - Diff-test: all four sign combinations plus divisor 0. Guard: `clippy::integer_division`, `modulo_arithmetic`; check each site.
- **Negative indexes, out-of-range slices and "not found".** A literal `a[len - k]` underflows usize and panics when `len < k`. Python slices clamp (`a[10:20]` is empty); Rust panics out of range.
  - Write "not found" sentinels (an old `find` returning -1 and the like) as `Option<usize>` on the new side, and map back to the old value only at the Python boundary.
  - Diff-test: empty sequence, length 1, k equal to and greater than len, not found. Guard: `clippy::indexing_slicing` (panic guard, no exemptions).
- **Sums and numeric types.** `0.1+0.2` is the same binary on both sides; compare the text as in the item above. Numeric differences come from changing type (Decimal ↔ f64) or changing the summation algorithm.
  - Since Python 3.12, float `sum()` uses compensated summation, so `sum([0.1]*10) == 1.0`; Rust `iter().sum()` doesn't match, and `math.fsum` is different again. Why: the algorithm follows the interpreter version, which is part of what SKILL R1 pins.
  - Diff-test: `[0.1]*10`, `[1e16, 1.0, -1e16]`, run on the referee interpreter.
- **String to number.** Python `int()` and `float()` accept leading/trailing whitespace, underscores and Unicode digits; `float()` also accepts `'Infinity'` and `'nan'`. Rust `parse` accepts none of these.
  - Diff-test: `' 7 '`, `'1_0'`, `'١٢'` (Arabic-Indic 12), `'+5'`, `'-0'`, `'1e400'`, `'nan'`. Guard: `rg '\.parse::<(i|u|f)\d+>'` hits only inside the Python-compatible parsing module.

## 2. Text and encoding

- **Units of length and slicing.** Python counts and slices by code point. Rust `len` counts bytes, and `&s[a..b]` panics mid-character. Where the old code sliced bytes and decoded with `errors='ignore'`/`'replace'`, do the same.
  - Diff-test: `'é'`, emoji, CJK plus combining characters, with the cut at every byte offset. Guard: `clippy::string_slice` (no exemptions).
- **Line splitting.** `splitlines()` also splits on `\r`, `\x0b`, `\x0c`, `\x1c`–`\x1e`, `\x85`, `\u2028`, `\u2029`; Rust `lines()` only on `\n` and `\r\n`. Text-mode `open()` turns `\r\n` and lone `\r` into `\n`; `read_to_string` keeps them.
  - Diff-test: one line per separator, plus a lone `\r` and no trailing newline. Why: the lone `\r` is the one most often missed.
- **Character predicates.** `isspace`, `isalnum`, `isprintable`, `isdigit` and `strip()` use Python's own Unicode tables, which change with the interpreter version. Rust predicates cover different ranges (Python counts `\x1c`–`\x1f` as whitespace; Rust doesn't).
  - Export the predicates you use as tables from the referee interpreter, and commit the generator with them. Why: tables generated with the system Python disagree in whole blocks.
  - Diff-test: code points added between the two Unicode versions, plus NBSP, U+200B, U+2028, U+FEFF, U+00AD.
  - Guard: `rg 'is_whitespace|is_alphanumeric|is_numeric|\.trim\(\)'` hits only inside the table module.
- **Regex.** The `regex` crate has no lookaround or backreferences. Python `$` without MULTILINE also matches before a trailing `\n`. `re.match` anchors only at the start. Check the Unicode ranges of `\w` and `\d`.
  - Put every regex in one wrapper module, each with a counterexample that targets a semantic difference, e.g. `'abc\n'` against `abc$`. Guard: outside that module `rg 'Regex::new'` is 0.
- **Non-UTF-8 and surrogateescape.** CPython decodes argv, environ and paths with surrogateescape: bad bytes pass back unchanged to exec, open and the environment, and show as `\udcXX` in stderr.
  - Rust `to_str().unwrap()` panics, `to_string_lossy` substitutes U+FFFD, and `filter_map(..ok()?)` drops the entry. Why: dropping one non-UTF-8 environment variable overwrites the user's own value.
  - Diff-test: put `\xff` in argv, an environment key and value, and a path; output has no U+FFFD. Where the platform can't produce such bytes, record the platform limit and test the error path instead.
  - Guard: `rg 'to_str\(\)\.unwrap|to_string_lossy|into_string\(\)\.ok'` is 0.
- **BOM, GBK, lone surrogates.** `utf-8-sig` strips the BOM, `utf-8` keeps it; write a BOM on output exactly when the old code did. encoding_rs maps per WHATWG, which doesn't fully match codecs. Diff-test: a file with BOM, GBK bytes, `'\ud800'`.
- **NFC/NFD.** Neither side normalizes on comparison. Differences come from the new code adding a normalization the old code didn't do, or from a filesystem returning the other form (some macOS volumes return NFD).
  - Diff-test: both forms of `é` as keys, file names and comparison operands. Why: one extra normalization merges two distinct keys.

## 3. Time

- **Time zones and DST.** In Python, subtracting aware datetimes with the same tzinfo uses wall-clock time and ignores DST; only different tzinfos go through UTC. chrono always uses absolute time. `datetime.now()` has no time zone.
  - Diff-test: subtraction across DST, the repeated hour with `fold=1`, old dates with historical LMT offsets. Guard: `rg 'Utc::now\(\)\.date_naive|Local::now'` is 0.
- **Formats and calendar.** ISO week numbers use `%G`, not `%Y`. `strftime` goes through the platform libc, so `%-d` and `%c` vary by platform and locale. datetime's upper bound is 9999-12-31; overflow raises OverflowError.
  - Diff-test: every day from 12-28 to 01-04, 9999-12-31 plus one day, around the epoch. Guard: `rg '%Y-W%V'` is 0.
- **tz data version.** zoneinfo uses the system tzdata or the tzdata package; chrono-tz compiles it into the binary. Before diff-testing, assert both sides have the same tzdb version.

## 4. Exceptions and the panic boundary

- **A panic becomes a BaseException.** PyO3 turns a panic into `PanicException`, which `except Exception` doesn't catch. Route every expected error through `PyResult`, mapped back to the class the old code raised at that point.
  - Diff-test: compare `type(e)` on every error branch; fuzz to compare "which class the old code raises vs. the new", not just "doesn't crash".
  - Guard: `clippy::unwrap_used`, `expect_used`, `indexing_slicing`, `panic`; `rg 'lock\(\)\.unwrap'` is 0; no exemptions.
- **The extern "C" boundary.** A panic crossing `extern "C"` aborts; the catch rule and its test are in go-c-cpp §4.
- **Exception identity, message and chain.** If the old code has its own exception class, reference that class from the old module. If the old code panicked and has no class, pick an exception the old callers can catch, per SKILL R6(a), and register it.
  - Compare `type(e) is`, `str(e)`, `e.args`, `__context__`, `__cause__` one by one. Old code raising inside an `except` block carries `__context__`; a direct raise from Rust doesn't. Write any dimension you don't compare into the equivalence rule.
- **process::exit and signal death skip Drop.** Python `sys.exit` raises SystemExit, so `finally` and `atexit` run and stdio is flushed; SIGINT becomes KeyboardInterrupt and also runs `finally`.
  - Rust `process::exit`, `abort`, `panic = "abort"` and default signal death don't unwind: BufWriter isn't flushed, temp files aren't deleted, locks aren't released. Why: unit tests don't show it.
  - Return from main for every exit. For each signal under which the old code cleaned up (SIGTERM doesn't by default in Python either), the new code sets a flag in a handler and returns normally.
  - Diff-test: on error paths and under SIGINT and SIGTERM, compare whether the last line reached disk, the exit code, and the count of leftover temp files.
  - Guard: `clippy::exit`; `rg 'process::exit|process::abort'` hits only in main; `panic = "abort"` goes in the guards-allowlist.

## 5. GIL, global state and reload

- **Cached host objects.** Classes cached by `import_exception!` or `GILOnceCell`/`PyOnceLock` (verify the name against the locked version) go stale after `importlib.reload`: exceptions aren't caught and `isinstance` fails.
  - Cache only standard-library objects; fetch host objects that may be reloaded on every use. Diff-test: call, reload, call again; assert `except NewClass` catches it.
- **Py objects held in statics.** `static`, `lazy_static!`, `Lazy` and `OnceLock<Py<..>>` holding Python objects have two more problems.
  - Deadlock: A holds the GIL, enters the init closure, and the closure calls Python, which releases the GIL. B takes the GIL and waits on the Rust init lock held by A; A waits for the GIL. Why: single-threaded and sequential tests are green; it hangs only on the first concurrent request.
  - Teardown: a `Py<T>` in a `static` isn't released correctly after the interpreter shuts down, and subinterpreters share the same object.
  - Old module-level globals are assigned at import by a single thread holding the GIL, so they have neither problem. In new code, use a GIL-bound once-cell, or fetch at module init and attach to the module object.
  - Diff-test: after a cold start, make simultaneous first calls at the "occasional, concurrent" level of the Default strictness table; 0 hangs. Then reload and call again.
  - Guard: `rg 'lazy_static!|static\s+\w+\s*:.*Py<|(OnceLock|OnceCell|Lazy)<\s*Py'` hits only entries in the guards-allowlist.
- **Releasing the GIL and callbacks under a lock.** Calling Python code that may release the GIL while holding a Rust Mutex deadlocks. Release the GIL before long computations (`allow_threads`/`detach`; verify against the locked version).
  - Extract the inputs into Rust-owned data first, then release the GIL. The closure touches only Rust-owned data, never `Bound`/`Py` objects or borrowed buffers. Why: touching Python objects without the GIL is undefined, and borrowed buffers can change under you.
  - When parallelism is the goal, write the parallel scaling ratio (N-thread / 1-thread throughput) as a gate fixed in advance, before measuring. Why: releasing the GIL without a ratio gate can look done while throughput stays flat.
  - Diff-test: load-test at the "occasional, concurrent" level; 0 hangs. On a hang, dump all thread stacks first (SKILL R3).
- **Thread count and fork at import.** An old pure-Python module usually has 1 thread after import, and forked children work normally. Building a rayon/tokio runtime at import changes both. Old behavior wins: defer to first use.
  - Diff-test: thread count after import matches; under `multiprocessing` fork mode, child results match and nothing hangs.
- **Implicit constraints of the old platform.** Smoke-test on the prototype: it runs on both GIL and free-threaded builds (the latter declares `gil_used`); dropping `Py<T>` on another thread doesn't crash; import in a subinterpreter fails with a clear error; the pool idle timeout is shorter than the load balancer's.
- **pyo3 cfg branches.** `cfg(Py_GIL_DISABLED)`, `Py_LIMITED_API`, `PyPy` and `Py_3_x` branches aren't compiled by default CI. Why: a branch never compiled has neither diff-tests nor type checks.
  - For each branch, pick one and write the reason in acceptance.md: a CI matrix cell actually enables it and runs the full diff-test suite; or don't write the branch, and the matching `rg 'cfg\(...'` is 0.
- **Recursion limit.** Python raises a catchable RecursionError past the limit; native Rust recursion overflows the stack and crashes. Set an explicit depth limit below Python's actual depth; beyond it, fall back or raise the same exception.
  - Diff-test: limit−1, limit, limit+1, far past the limit, plus self-referencing containers.

## 6. Object protocols

- **Protocols vs. shortcuts.** Old `for x in obj`, `k, v = kv` and `obj.items()` go through the protocol for any object; `PyList::iter`, `PyDict::iter` and `extract::<(A, B)>()` are equivalent only for exact types.
  - Take the fast path on `is_exact_instance_of`; hand everything else back to the host (`call_method0("items")`, `try_iter()`). Diff-test: subclasses overriding `__iter__`/`items`, `items()` returning a list of pairs or triples.
- **Mutation during iteration.** A callback mutates the container: for dict the old code raises `RuntimeError`, PyO3 may panic; for list the old code rechecks the length every step, PyO3 may truncate. Diff-test: a callback adding a dict key, appending to a list.
- **Dispatch order.** Copy the old order. `bool` is a subclass of `int`, and `extract::<i64>` succeeds on True, so check bool first. Diff-test: True next to 1, False next to 0.
- **User hooks first.** The old code checks user-registered handlers before built-in types; the fast path checks hooks first too. Diff-test: register handlers for int and str themselves.
- **Implicit copies.** `BytesIO(b)`, `list(x)` and `dict(d)` take snapshots; zero-copy borrows of bytearray and memoryview see what a callback changed. Diff-test: a callback mutating the input bytearray.
- **Numeric protocols.** `extract::<i64>`/`<f64>` call `__index__` and `__float__`, which the old code may have rejected with `isinstance`. Diff-test: an object implementing only `__index__`, numpy scalars, Decimal.
- **Hash seed and iteration order.** set iteration order changes with `PYTHONHASHSEED`; dict keeps insertion order. Rust `HashMap`/`HashSet` are randomly seeded per process.
  - Run the seed procedure in checks §8. Outputs the old code keeps stable across seeds use `IndexMap`/`BTreeMap` or an explicit sort; the source guard is in checks §8 too.
- **Shape of public objects.** Compare `type(ret)`, `__module__`, `is` identity, in-place mutation or not, pickle round-trip, iterators shared across threads, and the module's `dir()`. New names in the wrapper start with `_`.
- **cimport and PyCapsule.** If the old extension was Cython, downstream code may `cimport` its `.pxd` or fetch a function-pointer table via `PyCapsule_Import`; Python-level diff-tests can't see this. Why: an order off by one just calls the wrong function.
  - Ship the `.pxd` as before; keep the capsule name, function order in the table, signatures, calling convention and `__pyx_capi__` export names unchanged.
  - Diff-test: build a minimal downstream extension, link it against old and new, call each function and compare; compare export names with `nm`/`dir()`.
- **Fallback paths.** Output doesn't show whether the fast path ran. Count entries to the fallback: 0 on normal input, > 0 past the threshold.

## 7. async and blocking

- **Blocking calls inside async.** Check which blocking points the old code isolated with `run_in_executor` or threads. Sync IO, `thread::sleep` or a sync client translated literally into an async fn stalls the worker. Why: it doesn't show at concurrency 1.
  - Diff-test: p99 and throughput at the "occasional, concurrent" level.
  - Guard: list sync client methods under `disallowed-methods` in `clippy.toml`, enable `await_holding_lock`; `rg 'thread::sleep'` in the handler directory is 0.
- **Rate limits and timeouts.** Replace rate limiting the old code had implicitly (a single-threaded event loop is naturally serial) with an explicit token bucket, tuned to the old observed values.
  - Capacity gate for service replacements: connection pool size = min(the old workers' actual concurrency, DB connection limit ÷ replica count). Load-test against a same-period control at peak × a headroom derived from growth; the count of pool-timeout log lines is 0. Why: a Rust service handles more concurrency per process, so a pool sized to the new process can exhaust the database that the old one never touched. cutover §6 cites this gate.
- **tokio execution order.** asyncio is single-threaded FIFO; on tokio's multi-thread runtime spawn order is undefined, and `select!` picks a ready branch at random (write `biased;` for ordered). Fix the order of observable side effects with explicit dependencies.
  - For ordering tests use a single-threaded runtime with a paused clock (`current_thread` + `start_paused`), and advance timeouts on virtual time.
  - Diff-test: repeat runs with the same seed; the distinct sha256 count of the side-effect sequence is 1. Where the old code is itself nondeterministic, switch to invariant comparison per SKILL R2. Retry guard: checks §8.
- **Cancellation.** asyncio raises CancelledError at an await and runs `finally`; a Rust future can be dropped at any await point. For every await point, write down what happens if it is cancelled.
  - Port the old platform's cancellation propagation (asyncio task cancellation, request deadlines passed to downstream calls) as it was; the short-deadline test is in go-c-cpp §2 ("Port the context chain itself"). Why: a dropped future whose spawned work keeps running still hits downstream services after the caller gave up.

## 8. Side effects: atomicity and exactly-once

- **Inventory of writes.** List every write after an await point, a retry or a backfill, with its cancellation and transaction semantics.
  - Diff-test: inject kill -9, network loss and timeouts; 0 inconsistencies, each side effect exactly once. Guard: `rg` for external calls (HTTP, MQ, email) inside transaction bodies is 0.
- **Isolation level and retries.** Driver defaults differ: psycopg2 opens transactions implicitly, sqlx autocommits, sqlite3 uses legacy implicit transactions.
  - Under SERIALIZABLE, retry the whole transaction on 40001 and redo the reads. Copy backoff, limits and whether 40P01 is retried from the old code or driver config. Don't add retries the old code didn't have; past the limit, report errors the way the old code did.
  - Diff-test: concurrent read-modify-write on the same row; the old result is the expected value; also count retries and final failures. Guard: `rg '40001|serialization_failure'` hits only in one retry wrapper.
- **Temp files and replace.** Copy the old OS call order (create temp file, chmod, replace) and the file names in error messages. `os.path.abspath` collapses `..` lexically; `std::path::absolute` doesn't.
  - Diff-test: read-only directory, target is a directory, across filesystems, `sub/../x` through a symlink; leftover `.tmp*` is 0.
- **Stream, don't collect.** Where the old code wrote while reading, `collect::<Vec<_>>()` changes peak memory and time to first byte. Diff-test: time to first line with slow input; peak RSS per the streaming level of the resources row in the Default strictness table.
- **Serialized state versions.** The new code must read state the old code wrote to disk (pickle, caches, binaries), and stamp a version on what it writes. Diff-test: round-trip real production old samples; the old code reading new state either reads it or fails clearly, per the contract.

## 9. Processes and the OS

- **exec and environment order.** `os.execvpe` keeps environ order. `Command` sorts the whole environment once you change any variable, falls back to `/bin/sh` on ENOEXEC, and resets SIGPIPE. Where the old code called execve directly, port `_execvpe` line by line and treat PATH as bytes.
  - Diff-test: spawn an `env` child from old and new and compare order; a script without a shebang; `sh -c 'yes | head -n1'`.
- **NUL bytes.** Python raises `ValueError: embedded null byte`. Rust errors too, but with a different type, message and timing, and truncates when handing to C. Diff-test: `\0` in an argument, an environment value and a file name.
- **Signals, pipes and flush.** Python ignores SIGPIPE, raises BrokenPipeError on a broken pipe, and exits with 120 when the final flush fails. Rust `println!` panics on EPIPE with code 101.
  - Python stdout is block-buffered on a pipe; Rust is always line-buffered, which changes `2>&1` interleaving. Long Rust loops must call `py.check_signals()` periodically.
  - Diff-test: exit code under `| head -1`; exit latency and code after SIGINT; the byte sequence under `2>&1`; a lowered `ulimit -n`; deep directories.
- **locale.** PEP 538 rewrites LC_CTYPE under the C locale; PEP 540 UTF-8 mode applies to both C and POSIX. Their conditions differ, so write them separately. macOS also rewrites `__CF_USER_TEXT_ENCODING`. Children see all of this.
  - Diff-test: under `env -i`, set LC_ALL, `LC_CTYPE=C`/`POSIX`, `PYTHONCOERCECLOCALE=0`/`warn` separately.
- **Path expansion.** Keep how many times `expanduser` is called, how `abspath` normalizes, and what relative paths are relative to. Diff-test: `~`, `~user`, `a/../b`, `..` across a symlink.

## 10. Defaults

- **Per-field defaults table.** `#[derive(Default)]` gives 0, "", false; the old code may use None, another constant, or compute at use. Export the old defaults table and diff it key by key against the new. Guard: `rg 'derive\(.*Default'` on config types is 0.
- **Library default inference.** CSV null sets (pandas recognizes `NA`, `null` and more; polars only the empty string), dtype inference, JSON key order (serde_json without `preserve_order` sorts), NaN serialization, `ensure_ascii`, HTTP timeouts and retries.
  - Write each one out explicitly. Diff-test: CSV containing `NA` and `null`; JSON containing NaN and non-ASCII.

## 11. Output rewritten by the old runtime and frameworks

- **Framework rewrites are contract too.** For example, click's `echo` strips ANSI when not on a tty, while `print` and logging don't; help text, "Did you mean", and eager-option order are observable too.
  - Decide whether it falls within the equivalence rules before choosing a library. If it must be byte-identical, estimate that cost up front in `decisions.md`.
  - Diff-test: fixtures containing ESC and DEL, with the test runner on a pipe; cover unknown subcommands, near-miss spellings, and `--help` vs. `--version` order.
- **Interpreter rewrites.** PEP 538/540: see §9. `repr` escapes characters for which `isprintable` is false. `json.dumps` defaults to `ensure_ascii`.
  - How to find them: grep the old framework's output path for strip, encode, wrap, escape; give each rule at least one fixture byte.

## 12. Dependencies and structure

- **Dependency allowlist.** Every new crate brings its own set of default differences. CI asserts `cargo tree --depth 1` is a subset of the allowlist; anything outside goes through the out-of-scope approval gate in SKILL R6.
- **Centralize output exits.** Error codes, stdout and exit live only in designated modules; core logic is pure functions. Guard: the core crate denies `print_stdout`, `print_stderr`, `exit`.
- **ABI versions.** Pin the abi3 minimum, `#[repr(C)]` layouts and system library SONAMEs; compare exported symbols with `nm`, and actually import in a clean container. Details in `delivery.md`.
- **Plugin ABI version number.** When loaded via dlopen, export an ABI version symbol that the host reads before any other symbol; on mismatch, reject the way the old code did. Bump it whenever the layout changes; where old hosts have a protocol, keep it. Why: a mismatch doesn't fail at load; it silently reads the wrong fields.
  - Diff-test: fake plugins with version ±1 are rejected, with the old exit code and message. Guard: on the host side, a version check immediately follows `dlsym`/`Library::new`.

## 13. Using this list for other migrations

For Go and C/C++ sources, start with go-c-cpp.md, which applies the same method to those platforms. For framework upgrades, database swaps and other migrations, use this list as a **generator**:

1. Go through the 12 categories above and ask of each: **what did the old platform quietly do for me?** For example: a framework upgrade's new defaults and middleware order; a new library's isolation level, collation and NULL ordering.
2. Write each guarantee into the implicit-behavior list in `contract.md`, in the form difference → diff-test inputs → source guard.
3. When unsure whether anyone depends on it, find the real callers per SKILL R5; don't infer.

Why: implicit semantics of the old platform and gaps in the input space don't show in a feature list, and most differences found by the adversarial self-review in SKILL R2 fall into these two kinds.
