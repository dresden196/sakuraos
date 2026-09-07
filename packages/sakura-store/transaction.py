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
import functools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

# /run, not /var/lib: a lock is meaningless across a reboot, and a stale one
# on disk only blocks installs on a machine that crashed. Created by
# tmpfiles at boot so the unprivileged store can open it.
LOCK = Path(os.environ.get("SAKURA_STORE_LOCK", "/run/sakura/store.lock"))

# Named steps rather than a percentage. A bar that sits at 40% tells the user
# nothing; "verifying" tells them the download finished and nothing has been
# written yet.
RESOLVING = "resolving"
DOWNLOADING = "downloading"
VERIFYING = "verifying"
INSTALLING = "installing"
CONFIGURING = "configuring"
REMOVING = "removing"
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
    try:
        LOCK.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(LOCK, os.O_CREAT | os.O_RDWR, 0o666)
    except OSError as exc:
        # Serialising is a safeguard, not the operation. Refusing to install
        # anything because the lock could not be created would turn a missing
        # tmpfiles entry into a store that does nothing at all -- which is
        # exactly how this was found.
        emit(CONFIGURING,
             warning=f"could not take the transaction lock ({exc}); "
                     f"continuing without it")
        yield
        return
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


# What went wrong, in a sentence somebody can act on.
#
# The tools underneath report failures to other programmers: flatpak explains
# that it could not get a revokefs-fuse socket from the system helper, pacman
# that it is unable to lock the database. Passing that through unchanged makes
# the store look broken and tells the reader nothing about what to do. The raw
# text is still carried, under Details, because when a message here is wrong
# the original is the only way to find out.
#
# Ordered: the first pattern that matches wins, so the specific ones come
# before the general.
_EXPLANATIONS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"free space, but only|[Nn]ot enough (disk )?space|"
                r"No space left on device"),
     "There is not enough free space on this device."),
    (re.compile(r"not allowed for user|[Nn]ot authorized|"
                r"Authentication (is )?(required|failed)|polkit"),
     "Permission was not given, so nothing was changed."),
    (re.compile(r"unable to lock database|could not lock database"),
     "Another install or update is running. Try again when it has finished."),
    (re.compile(r"Could not resolve host|Temporary failure in name resolution|"
                r"[Nn]etwork is unreachable|Failed to connect|Connection refused|"
                r"Could not connect"),
     "Could not reach the server. Check your internet connection."),
    (re.compile(r"signature|PGP|corrupted|invalid or corrupted package|"
                r"key .* is unknown"),
     "A download could not be verified, so it was not installed."),
    (re.compile(r"target not found|[Nn]o such ref|[Nn]othing matches|"
                r"[Nn]ot found in remote|404"),
     "This application is no longer available from that source."),
    (re.compile(r"conflicting files|exists in filesystem"),
     "Another package already owns files this one needs."),
]


def explain(text: str) -> str:
    for pattern, message in _EXPLANATIONS:
        if pattern.search(text):
            return message
    # Nothing recognised. The last non-empty line is usually the actual error
    # rather than the trace leading to it, and is better than six lines of
    # context.
    for line in reversed(text.splitlines()):
        line = line.strip()
        if line:
            return line[:200]
    return "The operation did not finish."


def stream(args: list[str], stage: str, parse=None) -> int:
    """Run a command, turning its output into progress rather than swallowing it."""
    # Each pacman run announces its own Total Download Size, and an install
    # can be several runs (dependencies, then the package). Carrying the
    # previous run's total into the next one would report the second download
    # against the first one's size.
    reset_download_total()
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
        raw = "\n".join(tail[-12:])
        emit(FAILED, error=explain(raw), detail=raw, code=proc.returncode)
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


def remove_flatpak(app_id: str, delete_data: bool = False) -> int:
    emit(REMOVING, source="flatpak", app=app_id, packages=[app_id])
    args = ["flatpak", "uninstall", "--noninteractive", "--assumeyes"]
    if delete_data:
        # Off by default: settings and saved files are the user's, and a
        # reinstall should find them where they were left.
        args.append("--delete-data")
    return stream(args + [app_id], REMOVING)


def install_snap(name: str) -> int:
    emit(RESOLVING, source="snap", app=name)
    return stream(["snap", "install", name], DOWNLOADING)


def remove_snap(name: str) -> int:
    emit(REMOVING, source="snap", app=name, packages=[name])
    # snapd keeps a snapshot of the snap's data for 31 days by default, so
    # this is recoverable without us doing anything.
    return stream(["snap", "remove", name], REMOVING)


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


# "Total Download Size:   123.45 MiB". pacman prints this once, before it
# starts fetching, and it is the only place the whole size of the download
# appears -- the per-file lines are per file. Kept so that a percentage can be
# reported as an amount, because "48 MB of 96 MB" answers "how much longer"
# and "50%" does not.
_PACMAN_TOTAL = re.compile(
    r"Total Download Size:\s*([0-9.]+)\s*([KMG])iB", re.I)
# "Packages (14) foo-1.0  bar-2.0 ..." -- how many are coming.
_PACMAN_COUNT = re.compile(r"^Packages \((\d+)\)")
# " neovim-0.12.5-1-x86_64 downloading..." -- one per package, as it starts.
_PACMAN_ONE = re.compile(r"\S+\s+downloading\.\.\.\s*$")
_UNIT = {"K": 1024, "M": 1024 ** 2, "G": 1024 ** 3}

# Module state, reset per command run. The parser is called once per output
# line and has nowhere else to remember what it has seen.
#
# Deliberately counting packages rather than bytes. Piped -- which is how the
# store runs it -- pacman prints no percentage at all: just a total size up
# front and one "downloading..." line per package. Deriving an amount from the
# package number against the total size would read as bytes while actually
# being a package count, and would be wrong by however much the packages
# differ in size. The count is what pacman really tells us, so the count is
# what gets reported, next to the total size it also really tells us.
_dl_total = 0
_dl_count = 0
_dl_seen = 0


def reset_download_total() -> None:
    global _dl_total, _dl_count, _dl_seen
    _dl_total = _dl_count = _dl_seen = 0


def _pacman_progress(line: str, main_stage: str = INSTALLING):
    """Which phase pacman is in.

    Without this every line is reported as "downloading", so the UI claims a
    download is still running while packages are already being written to
    disk. pacman announces its phases plainly; this reads them.

    main_stage is what ":: Processing package changes" means for the operation
    in hand -- installing for an install, removing for a removal. Hardcoding
    it made an uninstall report itself as an install halfway through.
    """
    global _dl_total
    stripped = line.strip()

    global _dl_count, _dl_seen
    m = _PACMAN_TOTAL.search(stripped)
    if m:
        _dl_total = int(float(m.group(1)) * _UNIT[m.group(2).upper()])
    mc = _PACMAN_COUNT.match(stripped)
    if mc:
        _dl_count = int(mc.group(1))

    if stripped.startswith(":: Retrieving") or "downloading" in stripped:
        out = {"stage": DOWNLOADING, "detail": stripped[:160]}
        if _PACMAN_ONE.search(stripped):
            _dl_seen += 1
        if _dl_count:
            out["count"] = min(_dl_seen, _dl_count)
            out["count_total"] = _dl_count
            out["percent"] = min(100, _dl_seen * 100 // _dl_count)
        if _dl_total:
            out["total"] = _dl_total
        return out
    if (stripped.startswith(":: Processing package changes")
            or stripped.startswith(("installing ", "upgrading ",
                                    "reinstalling ", "removing "))):
        return {"stage": main_stage, "detail": stripped[:160]}
    if "transaction hooks" in stripped or stripped.startswith("("):
        return {"stage": CONFIGURING, "detail": stripped[:160]}
    return None


def _pacman_removing(line: str):
    return _pacman_progress(line, REMOVING)


def _is_installed_package(name: str) -> bool:
    if not _PKG_NAME.match(name):
        return False
    return subprocess.run(["pacman", "-Q", "--", name],
                          stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


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


def remove_repo(name: str, source: str = "repo") -> int:
    """Remove a pacman package -- repository or AUR, they are the same thing.

    Once an AUR package is installed it is an ordinary pacman package, so this
    path serves both. The plan decides whether dependencies come with it, and
    it refuses outright rather than removing anything the desktop needs.
    """
    plan = removal_plan(name, source)
    if plan["blocked"]:
        emit(FAILED, error=plan["reason"], recoverable=False)
        return 2
    emit(REMOVING, source=source, app=name,
         packages=plan["packages"], mode=plan["mode"])
    # -R, not -Rns: -n also deletes files in /etc that another package may
    # have come to rely on, and -s is added only when the plan says the
    # cascade is safe.
    flags = "-Rs" if plan["mode"] == "with-dependencies" else "-R"
    return stream(["pkexec", "pacman", flags, "--noconfirm", "--", name],
                  REMOVING, _pacman_removing)


# Packages whose removal would break the desktop or the boot. pacman refuses
# to remove a package another package depends on, but that is not enough on
# its own: nothing depends on the kernel or the bootloader, so pacman would
# take them without complaint, and `-Rs` cascades into dependencies that are
# no longer needed by anything -- which is the case that actually breaks
# systems.
# Stands in for "the protected set could not be computed". It is a name no
# package can have, so it never matches a real removal, but its presence makes
# the intersection test below conservative.
_NO_PACTREE = "\x00pactree-missing"

ESSENTIAL_ROOTS = [
    "base", "linux", "linux-firmware", "systemd", "sudo",
    "sddm", "plasma-desktop", "plasma-workspace", "networkmanager",
    "limine", "sakura-desktop",
]


@functools.lru_cache(maxsize=1)
def protected_packages() -> frozenset[str]:
    """Everything the desktop and the boot chain depend on, transitively.

    Roughly 576 packages on a stock install. Ordinary applications -- konsole,
    dolphin, ark, kate -- are deliberately outside it: the point is to stop a
    removal cascading into the system, not to stop anyone uninstalling an app.
    """
    if not shutil.which("pactree"):
        # Fail safe. An empty protected set would silently mean "nothing is
        # protected", which is the opposite of what this function is for, so
        # the sentinel below makes every cascade look unsafe and removals fall
        # back to taking the application alone.
        return frozenset({_NO_PACTREE})
    found: set[str] = set()
    for root in ESSENTIAL_ROOTS:
        if subprocess.run(["pacman", "-Q", "--", root],
                          stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode != 0:
            continue
        r = subprocess.run(["pactree", "-u", "-l", "--", root],
                           capture_output=True, text=True)
        found.update(line.strip() for line in r.stdout.splitlines()
                     if line.strip())
    return frozenset(found)


def _pacman_removal_cascade(name: str, recursive: bool) -> tuple[list[str], str]:
    """What pacman says it would remove. Needs no privileges."""
    args = ["pacman", "-Rs" if recursive else "-R",
            "--print", "--print-format", "%n", "--", name]
    r = subprocess.run(args, capture_output=True, text=True)
    if r.returncode != 0:
        return [], (r.stderr.strip().splitlines() or ["pacman refused"])[-1]
    return [l.strip() for l in r.stdout.splitlines() if l.strip()], ""


def removal_plan(name: str, source: str) -> dict:
    """What uninstalling would actually do, before anyone commits to it.

    Returned rather than acted on so the confirmation can show it: the list of
    packages, whether dependencies come with them, and why not when they do
    not.
    """
    if source in ("flatpak", "snap", "appimage"):
        # Self-contained by construction. Nothing else on the system can be
        # depending on them, so there is no cascade to reason about.
        return {"packages": [name], "mode": "app-only", "blocked": False,
                "reason": "", "extra": []}

    if not _is_installed_package(name):
        return {"packages": [], "mode": "", "blocked": True,
                "reason": f"{name} is not installed.", "extra": []}

    protected = protected_packages()
    if name in protected:
        return {"packages": [], "mode": "", "blocked": True,
                "reason": f"{name} is part of the SakuraOS desktop or the "
                          f"boot system. Removing it would leave this "
                          f"machine unable to start or log in.",
                "extra": []}

    cascade, err = _pacman_removal_cascade(name, recursive=True)
    if err:
        return {"packages": [], "mode": "", "blocked": True,
                "reason": err, "extra": []}

    unsafe = sorted(set(cascade) & protected)
    if _NO_PACTREE in protected and len(cascade) > 1:
        unsafe = ["(could not verify: pactree is not installed)"]
    if unsafe:
        # Removing the dependencies would take the system with it, so keep
        # them. They stay as orphans, which is untidy and harmless.
        only, err = _pacman_removal_cascade(name, recursive=False)
        if err:
            return {"packages": [], "mode": "", "blocked": True,
                    "reason": err, "extra": []}
        return {"packages": only, "mode": "app-only", "blocked": False,
                "reason": "Dependencies are being kept: removing them would "
                          "have taken parts of the desktop with them.",
                "extra": unsafe}

    return {"packages": cascade, "mode": "with-dependencies", "blocked": False,
            "reason": "", "extra": [p for p in cascade if p != name]}


def install_appimage_file(path: str, name: str = "") -> tuple[int, str]:
    """Install an AppImage the user already has on disk.

    The other sources are catalogues; this one is a file somebody downloaded.
    Nothing verifies it -- there is no signature to check and no publisher to
    check it against -- so the honest thing is to install it and say where it
    came from, not to imply a review that did not happen.
    """
    import appimage

    src = Path(path).expanduser()
    if not src.is_file():
        emit(FAILED, error=f"{src} is not a file.", recoverable=False)
        return 2, ""
    if not os.access(src, os.R_OK):
        emit(FAILED, error=f"{src.name} cannot be read.", recoverable=False)
        return 2, ""

    # The name it will be known by. Taken from the file, since a local
    # AppImage has no catalogue entry to name it.
    stem = name or src.stem
    stem = re.sub(r"[-_.]?(x86_64|amd64|linux)$", "", stem, flags=re.I)
    stem = re.sub(r"[^A-Za-z0-9._-]", "-", stem).strip("-") or "appimage"

    emit(RESOLVING, source="appimage", app=stem, detail=str(src))
    emit(INSTALLING, source="appimage", app=stem,
         detail="adding it to your applications")
    try:
        # The user's own file is copied, not moved: it stays where they left
        # it.
        appimage.install(src, stem, keep_original=True)
    except Exception as exc:
        emit(FAILED, error=f"{src.name} could not be installed: {exc}",
             recoverable=False)
        return 1, ""
    emit(CONFIGURING, detail="checking whether it can update itself")
    # The caller needs the derived name: it is what the app is now called, and
    # a "done" event naming nothing is no use to a UI that has to show it.
    return 0, stem


def update_one(source: str, app_id: str, unattended: bool = False) -> int:
    """Update one application, whichever kind it is.

    Unattended matters: a nightly run has nobody to answer a password prompt,
    so anything needing one is skipped rather than left hanging on a dialog
    nobody will ever see. Those are reported, not silently dropped -- an
    update that never happens and never says so is the worst outcome here.
    """
    needs_root = source in ("repo", "snap")
    if unattended and needs_root and os.geteuid() != 0:
        emit(CONFIGURING,
             detail=f"{app_id} needs administrator rights; leaving it for you")
        return 0

    if source == "flatpak":
        emit(DOWNLOADING, source=source, app=app_id)
        return stream(["flatpak", "update", "--noninteractive", "--assumeyes",
                       app_id], DOWNLOADING, _flatpak_progress)

    if source == "snap":
        emit(DOWNLOADING, source=source, app=app_id)
        return stream(["snap", "refresh", app_id], DOWNLOADING)

    if source == "repo":
        if not _is_installed_package(app_id):
            emit(FAILED, error=f"{app_id} is not installed.", recoverable=False)
            return 2
        emit(DOWNLOADING, source=source, app=app_id)
        # -S --needed on the one package rather than -Syu: this is an
        # application update, and taking the whole system with it is the
        # update engine's job and its snapshot, not this one's.
        cmd = ["pacman", "-S", "--noconfirm", "--needed", "--", app_id]
        if os.geteuid() != 0:
            cmd = ["pkexec", *cmd]
        return stream(cmd, DOWNLOADING, _pacman_progress)

    if source == "appimage":
        import appimage
        emit(DOWNLOADING, source=source, app=app_id)
        path = appimage.APPS / f"{app_id}.AppImage"
        if not path.is_file():
            emit(FAILED, error=f"{app_id} is no longer there.",
                 recoverable=False)
            return 2
        try:
            ok = appimage.update(path)
        except Exception as exc:
            emit(FAILED, error=f"{app_id} could not be updated: {exc}",
                 recoverable=True)
            return 1
        if not ok:
            emit(FAILED, error=f"{app_id} could not be updated.",
                 recoverable=True)
            return 1
        return 0

    emit(FAILED, error=f"Unknown source: {source}", recoverable=False)
    return 2


def _aur_accepted_sha(name: str) -> str:
    """The hash of the build script this user last read and accepted."""
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    try:
        acc = json.loads(
            Path(base).joinpath("sakura/store/aur-accepted.json")
                      .read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return ""
    return (acc.get(name) or {}).get("sha256", "")


def _aur_srcinfo_deps(name: str) -> list:
    """Dependencies declared by the package, from .SRCINFO.

    makepkg -s would resolve these itself, but it does that by calling sudo,
    and there is no terminal behind a store window to answer it. So they are
    installed first, through the same polkit prompt as any other install, and
    makepkg is then run with no privileges at all.
    """
    import urllib.request
    url = f"https://aur.archlinux.org/cgit/aur.git/plain/.SRCINFO?h={name}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "sakura-store/0.1"})
        with urllib.request.urlopen(req, timeout=20) as r:
            text = r.read().decode("utf-8", "replace")
    except Exception:
        return []
    deps = []
    for line in text.splitlines():
        k, _, v = line.partition("=")
        if k.strip() in ("depends", "makedepends") and v.strip():
            # Strip any version constraint: pacman resolves that itself.
            deps.append(re.split(r"[<>=]", v.strip())[0])
    return sorted(set(deps))


def install_aur(name: str) -> int:
    """Build and install an AUR package the user has read the script for.

    An AUR package is an unreviewed build script that compiles on this
    machine. The store shows it first and records the acceptance by hash;
    this refuses anything that does not match what was accepted, so the
    check cannot be walked past by calling the engine directly either.
    """
    import hashlib
    import shutil
    import tempfile
    import urllib.request

    # 1. The script must be the exact one this user read. Not the package, not
    #    the version -- the bytes. A maintainer can publish a changed script
    #    under an unchanged version number, and that is the case worth
    #    catching.
    accepted = _aur_accepted_sha(name)
    if not accepted:
        emit(FAILED, error=f"{name} has not been reviewed yet. Read its build "
                           f"script first -- SakuraOS will not run one it has "
                           f"not shown you.", recoverable=False)
        return 2
    try:
        req = urllib.request.Request(
            f"https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h={name}",
            headers={"User-Agent": "sakura-store/0.1"})
        with urllib.request.urlopen(req, timeout=20) as r:
            current = r.read().decode("utf-8", "replace")
    except Exception as e:
        emit(FAILED, error=f"The build script for {name} could not be "
                           f"fetched: {e}", recoverable=True)
        return 2
    if hashlib.sha256(current.encode()).hexdigest() != accepted:
        emit(FAILED, error=f"The build script for {name} has changed since you "
                           f"read it. Review it again before installing.",
             recoverable=False)
        return 2

    # 2. Dependencies, through polkit, before anything of the package's own
    #    runs. Marked --asdeps so removing the package can take them with it.
    emit(RESOLVING, source="aur", app=name)
    # base-devel first: building from source needs a compiler and the rest of
    # the toolchain, and a desktop install rightly does not ship one. It is
    # pulled in on the first AUR install rather than on every machine that
    # never touches the AUR.
    # git as well as base-devel, and it is not a detail: the AUR is fetched by
    # cloning, base-devel on Arch does not include git, and a desktop install
    # has no reason to have it. Missing, this failed with a bare
    # FileNotFoundError naming 'git' after the dependencies had already been
    # installed -- which only showed up on a machine that had never been
    # developed on. Every VM used for testing already had it.
    deps = ["base-devel", "git"] + _aur_srcinfo_deps(name)
    if deps:
        rc = stream(["pkexec", "pacman", "-S", "--noconfirm", "--needed",
                     "--asdeps", "--"] + deps, DOWNLOADING, _pacman_progress)
        if rc != 0:
            emit(FAILED, error=f"The dependencies of {name} could not be "
                               f"installed.", recoverable=True)
            return rc

    # 3. Build as the ordinary user. makepkg refuses to run as root and it is
    #    right to: this is the step that executes somebody else's shell script.
    work = tempfile.mkdtemp(prefix="sakura-aur-")
    try:
        if not shutil.which("git"):
            emit(FAILED, error="git is needed to fetch from the AUR and is "
                               "not installed.", recoverable=True)
            return 2
        rc = stream(["git", "clone", "--depth", "1",
                     f"https://aur.archlinux.org/{name}.git",
                     f"{work}/{name}"], DOWNLOADING)
        if rc != 0:
            emit(FAILED, error=f"{name} could not be fetched from the AUR.",
                 recoverable=True)
            return rc

        built = Path(work) / name
        rc = stream(["env", "-C", str(built), "makepkg", "--noconfirm",
                     "--noprogressbar", "--nodeps"], INSTALLING)
        if rc != 0:
            emit(FAILED, error=f"{name} failed to build. The build script ran "
                               f"but did not produce a package.",
                 recoverable=False)
            return rc

        # makepkg also emits a -debug package when debug symbols are on, which
        # they are by default on Arch. Installing it would silently double the
        # download and leave symbol packages nobody asked for on the machine.
        pkgs = sorted(str(f) for f in built.glob("*.pkg.tar.*")
                      if not str(f).endswith(".sig")
                      and "-debug-" not in f.name)
        if not pkgs:
            emit(FAILED, error=f"{name} built without producing a package "
                               f"file.", recoverable=False)
            return 2

        # 4. Install what was just built, again through polkit.
        return stream(["pkexec", "pacman", "-U", "--noconfirm", "--"] + pkgs,
                      INSTALLING, _pacman_progress)
    finally:
        shutil.rmtree(work, ignore_errors=True)
