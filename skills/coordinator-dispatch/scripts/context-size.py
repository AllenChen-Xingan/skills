#!/usr/bin/env python3
"""context-size.py: how big is each recent Claude Code session's context right now? (read-only)

Usage: python3 -I context-size.py [PROJECT] [options]

PROJECT is the project's main directory (absolute path; default: the current directory)
or a directory name under the projects dir. Every directory under the projects dir
(default ~/.claude/projects) whose name starts with the encoded project name is scanned,
so worktrees such as <repo>.worktrees/<name> or <repo>-wt-<name> are included.

For each session file (<dir>/<session-id>.jsonl) changed within the last --hours,
the last assistant message that carries `usage` gives the current context size:
input_tokens + cache_read_input_tokens + cache_creation_input_tokens.
Output: session id (first 8) · directory (worktree name) · context in k tokens ·
last change time, largest first.

Options:
  --hours H          only sessions changed within the last H hours (default 3)
  --over N           only sessions whose context is at least N tokens (e.g. 400000)
  --projects-dir D   where Claude Code keeps session logs (default ~/.claude/projects)
  -h, --help         show this help

Exit codes: 0 ok (also when nothing matched) · 1 bad arguments / projects dir missing
Nothing is written; files are read from the end, so large logs are cheap.
"""
import argparse
import json
import os
import re
import sys
import time

CHUNK = 1 << 20  # read session logs backwards, 1 MiB at a time


def encode(path):
    """Claude Code names a project's log dir after its path, every non-alphanumeric char -> '-'."""
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def lines_backwards(f):
    """Yield complete lines of an open binary file, last line first."""
    f.seek(0, os.SEEK_END)
    pos = f.tell()
    rest = b""
    while pos > 0:
        step = min(CHUNK, pos)
        pos -= step
        f.seek(pos)
        buf = f.read(step) + rest
        parts = buf.split(b"\n")
        rest = parts[0]  # may be a partial line; joined with the next chunk
        for line in reversed(parts[1:]):
            if line.strip():
                yield line
    if rest.strip():
        yield rest


def last_context(path):
    """(context_tokens, cwd) from the last assistant message with usage, or (None, None)."""
    with open(path, "rb") as f:
        for raw in lines_backwards(f):
            if b'"usage"' not in raw:
                continue
            try:
                d = json.loads(raw)
            except ValueError:
                continue
            if d.get("type") != "assistant" or d.get("isSidechain"):
                continue
            u = (d.get("message") or {}).get("usage")
            if not isinstance(u, dict):
                continue
            total = sum(int(u.get(k) or 0) for k in
                        ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
            if total <= 0:
                continue  # synthetic / errored turn; keep looking for a real one
            return total, d.get("cwd")
    return None, None


def scan(projects_dir, prefix, hours, over, now=None):
    now = time.time() if now is None else now
    cutoff = now - hours * 3600
    rows = []
    for d in sorted(os.listdir(projects_dir)):
        full = os.path.join(projects_dir, d)
        if not d.startswith(prefix) or not os.path.isdir(full):
            continue
        for name in os.listdir(full):
            if not name.endswith(".jsonl"):
                continue
            p = os.path.join(full, name)
            mtime = os.path.getmtime(p)
            if mtime < cutoff:
                continue
            ctx, cwd = last_context(p)
            if ctx is None or (over is not None and ctx < over):
                continue
            if cwd:
                where = os.path.basename(cwd.rstrip("/")) or cwd
            else:
                where = d[len(prefix):].lstrip("-") or "(main)"
            rows.append((ctx, name[:8], where, mtime))
    rows.sort(key=lambda r: (-r[0], r[1]))
    return rows


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("project", nargs="?")
    ap.add_argument("--hours", type=float, default=3.0)
    ap.add_argument("--over", type=int)
    ap.add_argument("--projects-dir", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("-h", "--help", action="store_true")
    try:
        a = ap.parse_args(argv)
    except SystemExit:
        print(__doc__, file=sys.stderr)
        return 1
    if a.help:
        print(__doc__)
        return 0
    if not os.path.isdir(a.projects_dir):
        print(f"Projects dir does not exist: {a.projects_dir}", file=sys.stderr)
        return 1
    project = a.project or os.getcwd()
    if "/" in project or project.startswith(("~", ".")):  # a path, not a log-dir name
        prefix = encode(os.path.abspath(os.path.expanduser(project)).rstrip("/"))
    else:
        prefix = project
    rows = scan(a.projects_dir, prefix, a.hours, a.over)
    if not rows:
        what = f" over {a.over} tokens" if a.over is not None else ""
        print(f"No sessions{what} changed in the last {a.hours:g}h under {prefix}*")
        return 0
    print(f"{'session':<8}  {'dir':<28}  {'context':>8}  last change")
    for ctx, sid, where, mtime in rows:
        print(f"{sid:<8}  {where[:28]:<28}  {ctx / 1000:>7.0f}k  {time.strftime('%m-%d %H:%M', time.localtime(mtime))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
