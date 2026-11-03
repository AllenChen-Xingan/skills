#!/usr/bin/env python3
"""Generate a dispatch batch skeleton from the skill's reference templates.

Creates, inside <batch-dir>:
  common.md            shared rules (from references/common-rules-template.md)
  <worker>.md          one brief per worker (from references/brief-template.md)
  msg-<worker>.txt     the one-line first message to paste into the worker
Optionally (--board PATH, only if PATH does not exist) a ledger from
references/coord-board-template.md.

Existing files are NEVER overwritten (they are reported as "skip").
Only the text between <!-- template:start --> and <!-- template:end --> is used.
"""
import argparse
import datetime as _dt
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.normpath(os.path.join(HERE, "..", "references"))
NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")

MSG = ("You are worker session {worker}. Read your brief {brief} in full and follow it "
       "(its first line tells you to read {common} first). When done reading, check in with "
       "the coordinator {boss} via inter-session messaging.\n")


def template(name):
    path = os.path.join(REF, name)
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"<!-- template:start -->\n(.*?)<!-- template:end -->", text, re.S)
    if not m:
        sys.exit(f"Template markers missing: {path}")
    return m.group(1)


def fill(text, values):
    return re.sub(r"\{\{([A-Z_]+)\}\}", lambda m: values.get(m.group(1), m.group(0)), text)


def write_new(path, content, dry):
    if os.path.exists(path):
        print(f"skip (exists, not overwritten): {path}")
        return
    if dry:
        print(f"[dry-run] would write: {path}")
        return
    with open(path, "x", encoding="utf-8") as f:
        f.write(content)
    print(f"wrote: {path}")


def main():
    p = argparse.ArgumentParser(
        description="Generate a batch of worker brief skeletons from templates (common.md + one brief and one first message per worker). Existing files are never overwritten.",
        epilog='Example: new-batch.py "/path/with space/proj/_tmp/20990101-b1" --boss main-01 --workers api,tree '
               '--handoff-dir state/handoff')
    p.add_argument("batch_dir", help="Batch directory (created if missing)")
    p.add_argument("--boss", required=True, help="Coordinator session name")
    p.add_argument("--workers", required=True, help="Comma-separated worker window names, e.g. api,tree,infra")
    p.add_argument("--handoff-dir", default="state/handoff", help="Handoff-page directory, as written into the briefs (default state/handoff)")
    p.add_argument("--board", help="Ledger path; if given and the file does not exist, create it from the template")
    p.add_argument("--date", default=_dt.date.today().isoformat(), help="Date (default today)")
    p.add_argument("--path-prefix", default="",
                   help="How briefs and messages refer to the batch directory (default: batch_dir as given), e.g. a project-relative path")
    p.add_argument("--dry-run", action="store_true", help="Only list which files would be written")
    a = p.parse_args()

    workers = [w.strip() for w in a.workers.split(",") if w.strip()]
    if not workers:
        sys.exit("--workers is empty")
    bad = [w for w in workers if not NAME_RE.match(w)]
    if bad:
        sys.exit(f"Window names may only contain letters, digits, _ . -: {bad}")
    if len(set(workers)) != len(workers):
        sys.exit("--workers contains duplicates")

    batch_ref = (a.path_prefix or a.batch_dir).rstrip("/")
    base = {
        "BOSS": a.boss,
        "BATCH": batch_ref,
        "BATCH_NAME": os.path.basename(os.path.normpath(a.batch_dir)),
        "HANDOFF_DIR": a.handoff_dir.rstrip("/"),
        "DATE": a.date,
    }
    if not a.dry_run:
        os.makedirs(a.batch_dir, exist_ok=True)

    common = fill(template("common-rules-template.md"),
                  dict(base, PEERS=", ".join(f"`{w}`" for w in workers)))
    write_new(os.path.join(a.batch_dir, "common.md"), common, a.dry_run)

    brief_t = template("brief-template.md")
    for w in workers:
        vals = dict(base, WORKER=w)
        write_new(os.path.join(a.batch_dir, f"{w}.md"), fill(brief_t, vals), a.dry_run)
        msg = MSG.format(worker=w, brief=f"{batch_ref}/{w}.md", common=f"{batch_ref}/common.md", boss=a.boss)
        write_new(os.path.join(a.batch_dir, f"msg-{w}.txt"), msg, a.dry_run)

    if a.board:
        write_new(a.board, fill(template("coord-board-template.md"), base), a.dry_run)

    left = []
    for root, _, files in os.walk(a.batch_dir):
        for fn in files:
            fp = os.path.join(root, fn)
            try:
                with open(fp, encoding="utf-8") as f:
                    if "{{" in f.read():
                        left.append(fp)
            except (OSError, UnicodeDecodeError):
                pass
    if left:
        print("Note: unreplaced {{…}} placeholders remain in:", *left, sep="\n  ")
    print("Next: fill in the <…> blanks in each file, then start workers with spawn-worker.sh.")


if __name__ == "__main__":
    main()
