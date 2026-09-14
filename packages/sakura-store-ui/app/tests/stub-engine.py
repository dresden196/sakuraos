#!/usr/bin/env python3
"""A stand-in for the store engine that emits scripted progress.

The queue decides what may run beside what and what must wait behind what.
Neither is observable by installing a package by hand: the answer depends on
several transactions overlapping in time, which is exactly what a person
clicking buttons cannot arrange reliably. So the tests drive the real Backend
against this, which reports when it starts and stops in a form the test can
check the ordering of.

Every invocation appends to $SAKURA_STUB_LOG:  START <source> <id> <epoch_ms>
and END <source> <id> <epoch_ms>.
"""
import json
import os
import sys
import time

def stamp(event, source, ident):
    path = os.environ.get("SAKURA_STUB_LOG")
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(f"{event} {source} {ident} {int(time.time() * 1000)}\n")

def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()

def main() -> int:
    args = sys.argv[1:]
    if not args:
        return 2
    verb = args[0]
    ident = args[1] if len(args) > 1 and not args[1].startswith("--") else "*"
    source = ""
    if "--source" in args:
        source = args[args.index("--source") + 1]

    # How long this job takes, and whether it fails, are set per package so a
    # test can arrange a slow job and a fast one and check which finished when.
    hold = float(os.environ.get(f"SAKURA_STUB_MS_{ident}", os.environ.get("SAKURA_STUB_MS", "400"))) / 1000.0
    fail = os.environ.get(f"SAKURA_STUB_FAIL_{ident}", "") == "1"

    # Only transactions. The backend also asks this same binary for featured
    # lists, installed lists and available updates, and those appeared in the
    # log as jobs with no source and an id of "*" -- so a test counting lines
    # counted four startup queries as two installs. What the queue schedules is
    # what belongs here.
    if verb not in ("install", "remove", "update"):
        emit({"stage": "done"})
        return 0

    stamp("START", source or "-", ident)
    emit({"stage": "resolving"})
    time.sleep(hold / 4)
    emit({"stage": "downloading", "percent": 25, "bytes": 1_000_000, "total": 4_000_000})
    time.sleep(hold / 4)
    emit({"stage": "downloading", "percent": 60, "bytes": 2_400_000, "total": 4_000_000})
    time.sleep(hold / 4)
    if fail:
        emit({"stage": "failed", "error": f"{ident} could not be installed",
              "detail": "stub failure"})
        stamp("END", source or "-", ident)
        return 1
    emit({"stage": "installing", "percent": 80, "count": 1, "count_total": 2})
    time.sleep(hold / 4)
    emit({"stage": "done", "percent": 100})
    stamp("END", source or "-", ident)
    return 0

if __name__ == "__main__":
    sys.exit(main())
