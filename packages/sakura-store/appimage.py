"""AppImage handling for the Sakura Store.

Follows the approach AppManager (github.com/kem-a/AppManager, GPL-3.0) worked
out: zsync delta updates from the AppImage's own embedded update information,
checksum verification, and proper desktop integration so an AppImage behaves
like an installed application rather than a file in Downloads.

Reimplemented rather than shipped because AppManager is GTK4/libadwaita and
this is a Plasma desktop, and because managing applications in two separate
places is the confusion the store exists to remove. The protocol work is not
ours: zsync is a real tool in Arch's repositories and does the delta transfer.
"""
from __future__ import annotations

import hashlib
import os
import re
import shutil
import struct
import subprocess
from dataclasses import dataclass
from pathlib import Path

# Where installed AppImages live. Under the user's home because an AppImage is
# not a system package and does not need root to install -- which is half of
# why people like them.
APPS = Path(os.environ.get("SAKURA_APPIMAGE_DIR",
                           str(Path.home() / "Applications")))
DESKTOP = Path.home() / ".local/share/applications"
ICONS = Path.home() / ".local/share/icons/hicolor/256x256/apps"


@dataclass
class UpdateInfo:
    kind: str          # "zsync" | "github" | ""
    url: str = ""

    @property
    def updatable(self) -> bool:
        return bool(self.kind and self.url)


def read_update_information(path: Path) -> UpdateInfo:
    """Pull the update string out of an AppImage's .upd_info ELF section.

    Two formats are in use and they are not the same shape:

        zsync|https://host/path/App-latest-x86_64.AppImage.zsync
        gh-releases-zsync|OWNER|REPO|RELEASE|App-*-x86_64.AppImage.zsync

    The second is a pattern, not a URL, and has to be resolved against the
    GitHub releases API before zsync can use it.

    Both are OPTIONAL. An author who did not add one leaves the file with no
    way to know it is stale, and nothing on our side changes that.
    """
    out = subprocess.run(["readelf", "-x", ".upd_info", str(path)],
                         capture_output=True, text=True).stdout
    if not out:
        return UpdateInfo("")

    # Decode the hex columns rather than readelf's ASCII gutter. The gutter
    # renders every non-printable byte as '.', which is indistinguishable from
    # a real dot -- and update strings are full of real dots.
    raw = bytearray()
    for line in out.splitlines():
        m = re.match(r"\s*0x[0-9a-f]+\s+((?:[0-9a-f]{2,8}\s+){1,4})", line)
        if m:
            raw += bytes.fromhex(m.group(1).replace(" ", ""))
    text = raw.split(b"\x00", 1)[0].decode("utf-8", "replace").strip()
    if not text:
        return UpdateInfo("")

    if text.startswith("zsync|"):
        return UpdateInfo("zsync", text.split("|", 1)[1].strip())

    if text.startswith("gh-releases-zsync|"):
        parts = text.split("|")
        if len(parts) >= 5:
            _, owner, repo, release, filename = parts[:5]
            return UpdateInfo("gh-releases",
                              f"{owner}/{repo}/{release}/{filename}")
    return UpdateInfo("")


def resolve_zsync_url(info: UpdateInfo) -> str:
    """Turn a gh-releases pattern into the URL zsync can actually fetch."""
    if info.kind == "zsync":
        return info.url
    if info.kind != "gh-releases":
        return ""

    owner, repo, release, pattern = info.url.split("/", 3)
    # Only "latest" means the latest-release endpoint. "continuous" is an
    # ordinary tag that happens to be a rolling pre-release, and asking for
    # /releases/latest returns a different release entirely -- for AppImageKit
    # it returns tag 13 rather than the continuous build the AppImage came
    # from, so the update would silently never resolve.
    api = (f"https://api.github.com/repos/{owner}/{repo}/releases/latest"
           if release == "latest" else
           f"https://api.github.com/repos/{owner}/{repo}/releases/tags/{release}")
    try:
        import json as _json
        import urllib.request
        req = urllib.request.Request(
            api, headers={"User-Agent": "sakura-store/0.1",
                          "Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = _json.loads(r.read().decode())
    except Exception:
        return ""

    # The filename is a glob: appimagetool-*-x86_64.AppImage.zsync
    rx = re.compile("^" + re.escape(pattern).replace(r"\*", ".*") + "$")
    for asset in data.get("assets", []):
        if rx.match(asset.get("name", "")):
            return asset.get("browser_download_url", "")
    return ""


def verify(path: Path, sha256: str) -> bool:
    """Checksum before anything is made executable.

    An AppImage is an executable someone downloaded over the network. Marking
    it +x before knowing it arrived intact is the one step worth never
    skipping.
    """
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().lower() == sha256.lower()


def extract_metadata(path: Path, name: str) -> dict:
    """Pull the .desktop entry and icon out of the AppImage itself.

    Every AppImage carries them; using them means the launcher entry says what
    the author intended rather than a filename we guessed at.
    """
    work = APPS / f".extract-{name}"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True, exist_ok=True)
    meta: dict = {}
    try:
        subprocess.run([str(path), "--appimage-extract", "*.desktop"],
                       cwd=work, capture_output=True, timeout=60)
        subprocess.run([str(path), "--appimage-extract", "*.png"],
                       cwd=work, capture_output=True, timeout=60)
        root = work / "squashfs-root"
        for d in root.glob("*.desktop"):
            meta["desktop"] = d.read_text(errors="replace")
            break
        best, best_px = None, 0
        for p in root.rglob("*.png"):
            m = re.search(r"(\d+)x\1", str(p))
            px = int(m.group(1)) if m else 0
            if px >= best_px:
                best, best_px = p, px
        if best:
            meta["icon"] = best
    except (subprocess.SubprocessError, OSError):
        pass
    return meta


def install(path: Path, name: str, keep_original: bool = False) -> Path:
    """Put an AppImage where it belongs and make it appear in the launcher.

    keep_original matters for a file the user already had. A download lives in
    a temporary directory and moving it is right; a file somebody opened from
    their Downloads folder is theirs, and having it disappear when they
    installed it is not what anyone expects.
    """
    APPS.mkdir(parents=True, exist_ok=True)
    DESKTOP.mkdir(parents=True, exist_ok=True)
    ICONS.mkdir(parents=True, exist_ok=True)

    dest = APPS / f"{name}.AppImage"
    if path.resolve() != dest.resolve():
        if keep_original:
            shutil.copy2(str(path), dest)
        else:
            shutil.move(str(path), dest)
    dest.chmod(0o755)

    meta = extract_metadata(dest, name)
    icon_name = f"sakura-appimage-{name}"

    if "icon" in meta:
        shutil.copy2(meta["icon"], ICONS / f"{icon_name}.png")

    entry = meta.get("desktop", "")
    if entry:
        # Point Exec and Icon at where the file actually is now. The entry
        # inside the AppImage refers to paths that only exist while mounted.
        entry = re.sub(r"^Exec=.*$", f"Exec={dest} %U", entry, flags=re.M)
        entry = re.sub(r"^Icon=.*$", f"Icon={icon_name}", entry, flags=re.M)
    else:
        entry = ("[Desktop Entry]\nType=Application\n"
                 f"Name={name}\nExec={dest} %U\nIcon={icon_name}\n"
                 "Terminal=false\nCategories=Utility;\n")
    entry = entry.rstrip("\n") + "\nX-Sakura-Source=appimage\n"
    (DESKTOP / f"sakura-appimage-{name}.desktop").write_text(entry)

    shutil.rmtree(APPS / f".extract-{name}", ignore_errors=True)
    subprocess.run(["update-desktop-database", str(DESKTOP)],
                   capture_output=True)
    return dest


# zsync 0.6.6, which is what Arch ships, predates widespread HTTPS and cannot
# fetch a control file over it at all -- every real AppImage update URL is
# https, so the packaged tool is useless here. zsync2 is the maintained
# rewrite that speaks it.
ZSYNC = shutil.which("zsync2") or shutil.which("zsync") or "zsync"


class UpdateCheck:
    """Three outcomes, not two.

    'Could not ask' is not the same as 'up to date', and it is certainly not
    the same as 'update available'. Conflating the first with the last makes a
    store that reports an update forever and fails to apply it every time.
    """
    CURRENT = "current"
    AVAILABLE = "available"
    UNKNOWN = "unknown"


def check_update(path: Path) -> str:
    url = resolve_zsync_url(read_update_information(path))
    if not url:
        return UpdateCheck.UNKNOWN
    try:
        r = subprocess.run([ZSYNC, "-i", str(path), "-o", os.devnull, url],
                           capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.SubprocessError):
        return UpdateCheck.UNKNOWN

    output = (r.stdout + r.stderr).lower()
    if r.returncode != 0 or "could not read control file" in output or "failed on url" in output:
        return UpdateCheck.UNKNOWN
    if "no need to download" in output:
        return UpdateCheck.CURRENT
    return UpdateCheck.AVAILABLE


def update(path: Path) -> bool:
    """Fetch only the changed blocks.

    This is why zsync matters for AppImages: a 200 MB application whose new
    release changed 4 MB transfers 4 MB. Without it every update is the whole
    file again, which is why people stop updating AppImages at all.
    """
    url = resolve_zsync_url(read_update_information(path))
    if not url:
        return False
    tmp = path.with_suffix(".AppImage.new")
    r = subprocess.run([ZSYNC, "-i", str(path), "-o", str(tmp), url],
                       capture_output=True, text=True, timeout=1800)
    if r.returncode != 0 or not tmp.exists():
        tmp.unlink(missing_ok=True)
        return False
    tmp.chmod(0o755)
    tmp.replace(path)
    return True


def installed() -> list[dict]:
    if not APPS.exists():
        return []
    out = []
    for f in sorted(APPS.glob("*.AppImage")):
        info = read_update_information(f)
        out.append({
            "name": f.stem,
            "path": str(f),
            "size": f.stat().st_size,
            # Surfaced per app, because "this one cannot tell you when it is
            # out of date" is a fact about that AppImage the user should see
            # rather than a silent gap in the update story.
            "updatable": info.updatable,
        })
    return out
