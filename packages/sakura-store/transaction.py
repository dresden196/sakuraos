"""Installing and removing, across every source.

Every install failure people blame on a software centre comes down to two
things: two processes touching the same package database at once, and progress
that is a spinner rather than a statement. Both are addressed here rather than
in the interface, so the command line and the window fail the same way.

Progress is emitted as JSON lines so a caller can read it incrementally
without waiting for the process to end.
"""
from __future__ import annotations

import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

LOCK = Path("/var/lib/sakura/store.lock")

# Named steps rather than a percentage. A bar that sits at 40% tells the user
# nothing; "verifying" tells them the download finished and nothing has been
# written yet.
RESOLVING = "resolving"
DOWNLOADING = "downloading"
VERIFYING = "verifying"
INSTALLING = "installing"
CONFIGURING = "configuring"
DONE = "done"
FAILED = "failed"


def emit(stage: str, **fields) -> None:
    print(json.dumps({"stage": stage, **fields}), flush=True)


@contextmanager
def transaction_lock():
    """One transaction at a time, shared with the update engine.

    An advisory lock on a real file rather than a PID check: a store killed
    mid-install must not leave a stale marker that blocks every future one.
    The kernel drops this when the process dies, however it dies.
    """
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(LOCK, os.O_CREAT | os.O_RDWR, 0o644)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            emit(FAILED, error="Another install or update is already running.",
                 recoverable=True)
            raise SystemExit(4)
        yield
    finally:
        os.close(fd)


def stream(args: list[str], stage: str, parse=None) -> int:
    """Run a command, turning its output into progress rather than swallowing it."""
    proc = subprocess.Popen(args, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, bufsize=1)
    tail: list[str] = []
    for line in proc.stdout:
        line = line.rstrip()
        if not line:
            continue
        tail.append(line)
        del tail[:-25]
        if parse:
            parsed = parse(line)
            if parsed:
                emit(**parsed)
        else:
            emit(stage, detail=line[:160])
    proc.wait()
    if proc.returncode != 0:
        emit(FAILED, error="\n".join(tail[-6:]) or "the command failed",
             code=proc.returncode)
    return proc.returncode


# --------------------------------------------------------------------------
# per-source install
# --------------------------------------------------------------------------
_FLATPAK_PCT = re.compile(r"(\d{1,3})%")


def _flatpak_progress(line: str):
    low = line.lower()
    if "installing" in low or "updating" in low:
        return {"stage": INSTALLING, "detail": line[:160]}
    m = _FLATPAK_PCT.search(line)
    if m:
        return {"stage": DOWNLOADING, "percent": int(m.group(1)),
                "detail": line[:160]}
    return None


def install_flatpak(app_id: str) -> int:
    emit(RESOLVING, source="flatpak", app=app_id)
    return stream(
        ["flatpak", "install", "--noninteractive", "--assumeyes",
         "flathub", app_id],
        DOWNLOADING, _flatpak_progress)


def remove_flatpak(app_id: str) -> int:
    emit(INSTALLING, source="flatpak", app=app_id, detail="removing")
    return stream(["flatpak", "uninstall", "--noninteractive", "--assumeyes",
                   app_id], INSTALLING)


def install_snap(name: str) -> int:
    emit(RESOLVING, source="snap", app=name)
    return stream(["snap", "install", name], DOWNLOADING)


def remove_snap(name: str) -> int:
    return stream(["snap", "remove", name], INSTALLING)


def install_appimage(url: str, name: str, sha256: str = "") -> int:
    """Download, verify, then integrate.

    Deliberately in that order. An AppImage is an executable fetched over the
    network, and making it executable before knowing it arrived intact is the
    one step never worth skipping.
    """
    import appimage

    emit(RESOLVING, source="appimage", app=name, url=url)
    tmp = Path(tempfile.gettempdir()) / f"sakura-{name}.AppImage.part"

    try:
        req = urllib.request.Request(
            url, headers={"User-Agent": "sakura-store/0.1"})
        with urllib.request.urlopen(req, timeout=60) as r:
            total = int(r.headers.get("Content-Length") or 0)
            got = 0
            last = -1
            with tmp.open("wb") as f:
                while True:
                    chunk = r.read(1 << 18)
                    if not chunk:
                        break
                    f.write(chunk)
                    got += len(chunk)
                    if total:
                        pct = got * 100 // total
                        if pct != last:
                            last = pct
                            emit(DOWNLOADING, percent=pct, bytes=got,
                                 total=total)
    except Exception as e:
        tmp.unlink(missing_ok=True)
        emit(FAILED, error=f"Download failed: {e}")
        return 1

    if sha256:
        emit(VERIFYING, detail="checking the download against its checksum")
        if not appimage.verify(tmp, sha256):
            tmp.unlink(missing_ok=True)
            emit(FAILED, error="The download did not match its checksum and "
                               "was discarded.")
            return 1

    emit(INSTALLING, detail="adding to your applications")
    try:
        dest = appimage.install(tmp, name)
    except OSError as e:
        tmp.unlink(missing_ok=True)
        emit(FAILED, error=f"Could not install: {e}")
        return 1

    info = appimage.read_update_information(dest)
    emit(CONFIGURING, detail="creating the launcher entry",
         updatable=info.updatable)
    if not info.updatable:
        # Said once, at install, rather than discovered months later when it
        # has quietly never updated.
        emit(CONFIGURING, warning="This AppImage carries no update "
                                  "information, so it cannot tell us when a "
                                  "newer version exists.")
    return 0


# Package names that pacman will be asked to act on as root. Validated
# against the sync database rather than a pattern: a name that pacman itself
# does not recognise as a repository package never reaches the command line.
_PKG_NAME = re.compile(r"\A[a-z0-9][a-z0-9@._+-]*\Z")


def _is_repo_package(name: str) -> bool:
    if not _PKG_NAME.match(name):
        return False
    return subprocess.run(["pacman", "-Si", "--", name],
                          stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


def _pacman_progress(line: str):
    """Which phase pacman is in.

    Without this every line is reported as "downloading", so the UI claims a
    download is still running while packages are already being written to
    disk. pacman announces its phases plainly; this reads them.
    """
    stripped = line.strip()
    if stripped.startswith(":: Retrieving") or "downloading" in stripped:
        return {"stage": DOWNLOADING, "detail": stripped[:160]}
    if (stripped.startswith(":: Processing package changes")
            or stripped.startswith(("installing ", "upgrading ", "reinstalling "))):
        return {"stage": INSTALLING, "detail": stripped[:160]}
    if "transaction hooks" in stripped or stripped.startswith("("):
        return {"stage": CONFIGURING, "detail": stripped[:160]}
    return None


def install_repo(name: str) -> int:
    """Install a package from the SakuraOS and Arch repositories.

    pacman needs root. There is no privileged store helper yet, so this goes
    through pkexec, which puts the request in front of the session's polkit
    agent -- the user sees what is being installed and authorises it. When the
    helper lands this is the one call that changes.
    """
    if not _is_repo_package(name):
        emit(FAILED, error=f"{name} is not a package in any enabled "
                           f"repository.", recoverable=False)
        return 2
    emit(RESOLVING, source="repo", app=name)
    # "--" so a name can never be read as an option, even though the check
    # above already rejects anything that could be.
    return stream(["pkexec", "pacman", "-S", "--noconfirm", "--needed", "--",
                   name], DOWNLOADING, _pacman_progress)


def remove_repo(name: str) -> int:
    if not _PKG_NAME.match(name):
        emit(FAILED, error=f"{name} is not a valid package name.",
             recoverable=False)
        return 2
    emit(INSTALLING, source="repo", app=name, detail="removing")
    return stream(["pkexec", "pacman", "-Rns", "--noconfirm", "--", name],
                  INSTALLING)


def install_aur(name: str) -> int:
    """Not reachable until the review step exists.

    An AUR package is an unreviewed build script that compiles on the user's
    machine. Installing one without showing what it does first would
    contradict the thing the store is for, so this refuses rather than
    silently doing it.
    """
    emit(FAILED,
         error="AUR installs go through the review step, which is not built "
               "yet. Enable the AUR and use the review flow when it lands.",
         recoverable=False)
    return 2
