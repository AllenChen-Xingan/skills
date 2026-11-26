#!/usr/bin/env python3
"""Tests for context-size.py, on fake session logs in a temp dir. Run: python3 -I scripts/context-size.test.py"""
import importlib.util
import io
import json
import os
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("context_size", os.path.join(HERE, "context-size.py"))
cs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cs)

PROJ = "/work/my repo"          # encodes to -work-my-repo
PREFIX = "-work-my-repo"


def asst(inp, read, create, cwd=PROJ, sidechain=False, out=50):
    return {"type": "assistant", "isSidechain": sidechain, "cwd": cwd,
            "message": {"role": "assistant", "usage": {
                "input_tokens": inp, "cache_read_input_tokens": read,
                "cache_creation_input_tokens": create, "output_tokens": out}}}


def user(text="hi", cwd=PROJ):
    return {"type": "user", "cwd": cwd, "message": {"role": "user", "content": text}}


class ContextSizeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.now = time.time()

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, dirname, sid, entries, age_h=0.1, tail_garbage=False):
        d = os.path.join(self.root, dirname)
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, sid + ".jsonl")
        with open(p, "w") as f:
            for e in entries:
                f.write(json.dumps(e) + "\n")
            if tail_garbage:
                f.write('{"type":"assistant","usage": trunc')  # half-written last line
        t = self.now - age_h * 3600
        os.utime(p, (t, t))
        return p

    def test_encode_matches_claude_code_dir_names(self):
        self.assertEqual(cs.encode("/work/my repo"), PREFIX)
        self.assertEqual(cs.encode("/a/b.worktrees/x_y"), "-a-b-worktrees-x-y")

    def test_last_assistant_usage_wins_and_sums_three_fields(self):
        self.write(PREFIX, "aaaaaaaa-1", [asst(1, 100_000, 0), user(), asst(2, 450_000, 3_000), user()])
        rows = cs.scan(self.root, PREFIX, 3, None, now=self.now)
        self.assertEqual([(r[0], r[1]) for r in rows], [(453_002, "aaaaaaaa")])

    def test_skips_sidechain_zero_usage_and_broken_tail(self):
        self.write(PREFIX, "bbbbbbbb-1", [asst(0, 300_000, 0), asst(0, 900_000, 0, sidechain=True),
                                          asst(0, 0, 0)], tail_garbage=True)
        rows = cs.scan(self.root, PREFIX, 3, None, now=self.now)
        self.assertEqual(rows[0][0], 300_000)

    def test_hours_window_over_threshold_and_sort(self):
        self.write(PREFIX, "small000-1", [asst(1, 120_000, 0)])
        self.write(PREFIX, "big00000-1", [asst(1, 700_000, 0)])
        self.write(PREFIX, "mid00000-1", [asst(1, 410_000, 0)])
        self.write(PREFIX, "old00000-1", [asst(1, 800_000, 0)], age_h=5)
        self.write(PREFIX, "nousage0-1", [user(), user()])
        rows = cs.scan(self.root, PREFIX, 3, None, now=self.now)
        self.assertEqual([r[1] for r in rows], ["big00000", "mid00000", "small000"])
        rows = cs.scan(self.root, PREFIX, 3, 400_000, now=self.now)
        self.assertEqual([r[1] for r in rows], ["big00000", "mid00000"])
        rows = cs.scan(self.root, PREFIX, 6, None, now=self.now)
        self.assertEqual(rows[0][1], "old00000")

    def test_worktree_dirs_included_named_by_cwd_others_excluded(self):
        wt = PROJ + ".worktrees/api"
        self.write(cs.encode(wt), "cccccccc-1", [asst(1, 200_000, 0, cwd=wt)])
        self.write(PREFIX + "-wt-docs", "dddddddd-1", [{"type": "assistant", "message": {
            "usage": {"input_tokens": 5, "cache_read_input_tokens": 10, "cache_creation_input_tokens": 0}}}])
        self.write("-other-project", "eeeeeeee-1", [asst(1, 999_000, 0, cwd="/other/project")])
        rows = cs.scan(self.root, PREFIX, 3, None, now=self.now)
        self.assertEqual({(r[1], r[2]) for r in rows}, {("cccccccc", "api"), ("dddddddd", "wt-docs")})

    def test_large_file_read_from_the_end(self):
        filler = [user("x" * 5000) for _ in range(600)]  # ~3 MB, spans several 1 MiB chunks
        self.write(PREFIX, "ffffffff-1", [asst(1, 50_000, 0)] + filler + [asst(1, 600_000, 0)] + filler[:3])
        self.assertEqual(cs.scan(self.root, PREFIX, 3, None, now=self.now)[0][0], 600_001)

    def test_cli_output_and_read_only(self):
        p = self.write(PREFIX, "gggggggg-1", [asst(1, 420_000, 0)])
        before = (os.path.getmtime(p), os.path.getsize(p))
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = cs.main([PROJ, "--projects-dir", self.root, "--over", "400000"])
        out = buf.getvalue()
        self.assertEqual(rc, 0)
        self.assertIn("gggggggg", out)
        self.assertIn("420k", out)
        self.assertEqual(before, (os.path.getmtime(p), os.path.getsize(p)))
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = cs.main([PROJ, "--projects-dir", self.root, "--over", "900000"])
        self.assertEqual(rc, 0)
        self.assertIn("No sessions", buf.getvalue())

    def test_missing_projects_dir_is_an_error(self):
        with redirect_stdout(io.StringIO()):
            sys_stderr = sys.stderr
            sys.stderr = io.StringIO()
            try:
                self.assertEqual(cs.main([PROJ, "--projects-dir", os.path.join(self.root, "nope")]), 1)
            finally:
                sys.stderr = sys_stderr


if __name__ == "__main__":
    unittest.main(verbosity=2)
