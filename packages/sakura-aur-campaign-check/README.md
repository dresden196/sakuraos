# sakura-aur-campaign-check

Compares what is installed against lists of AUR packages that are already
known to have been compromised.

**This is not a malware scanner and must never be described as one.** It
answers "am I holding something from a campaign somebody has already
published". It cannot say anything about a package nobody has reported yet.
The review step in the store — showing the build script and the diff since
you last accepted it — is the part that faces forward; this one faces back.
Neither replaces the other.

## Upstream

[`lenucksi/aur-malware-check`](https://github.com/lenucksi/aur-malware-check),
GPL-3.0 (verified through the GitHub API, not taken from its README).

Pinned by commit, not by tag: at the time of packaging the `v3.0.0` tag was 66
commits behind `master`, and for a tool whose entire job is integrity a moving
branch is not a dependency, it is a hole. Bumping the pin is a deliberate act:
change `_commit` in the PKGBUILD and read the diff.

The upstream tree is installed unmodified under
`/usr/lib/sakura/aur-campaign-check`, so it can be diffed against the pinned
commit without unpicking our packaging. Only the test suite is dropped.

## What we decided that upstream cannot

**Whether it runs.** Gated on `AUR.KnownCampaignScanning` in
`/etc/sakura/sakura.conf`.

**Where the data lives.** Upstream refreshes package lists in place. Pointed at
`/usr` that fails on a read-only tree and leaves files pacman fights with on
upgrade. The packaged copy under `/usr/share` is the read-only baseline; a
writable copy is seeded into `/var/lib/sakura/aur-campaign-check/data`, and new
campaigns arriving in a package update are copied in without overwriting a list
this machine has refreshed.

**What happens on a finding.** A report at
`/var/lib/sakura/aur-campaign-check/last-report.json` that the store and the
update centre can read, plus a notification sent to whoever is actually logged
in — found through logind, because the scan runs as root from a timer where
there is no session and no bus. A non-zero exit into a journal nobody opens is
not a safeguard.

## `--all-time`, and why it is not optional

Every campaign carries a date window, and by default a package is only reported
if it was installed inside it. That is correct for the question upstream was
built to answer — *was I hit in June* — and wrong for ours.

Measured: a package on the list, installed today, is reported **clean** by the
default windowed scan, because today is outside the June 2026 window. With
`--all-time` the same package is reported, exit 2.

The cost is real and is stated rather than hidden: a package compromised in
June, cleaned since, and installed today still matches the list. So a hit means
*this name appears on a published campaign list*, not *you are infected*, and
the notification says so.

A future refinement worth having: run both, and separate "installed inside the
campaign window" (you were probably hit) from "on the list at some point"
(worth a look).

## Refresh, and the line we draw

`--refresh` is used. It pulls the current package list, which for the June 2026
campaign comes from **Arch's own HedgeDoc**, not from this tool's repository —
that is the whole point, since it catches packages disclosed after they were
installed.

`--refresh-campaigns` is deliberately never passed. That one fetches
`campaigns.json`, which declares where all the other data comes from. Letting a
weekly timer rewrite its own sources unattended is a different and larger act
of trust than fetching a list.

## When it runs

| Trigger | Scan | Cost |
|---|---|---|
| `90-…hook`, PostTransaction | `--quick --all-time` — package + log check | ~0.35s measured |
| `…timer`, weekly | `--refresh --full --scan-all-homes --all-time` | minutes; `Nice=10`, idle I/O |

`--scan-all-homes` matters more than it looks: the payload targets npm, bun,
yarn and pnpm caches, which live in the desktop user's home. A root scan
without it looks in root's home and finds nothing.

## Exit codes

Upstream's, Nagios-shaped: `0` clean, `1` warnings (a log it could not read),
`2` a match, `3` could not scan. A warning is recorded and not announced — a
popup that cries wolf about a rotated log teaches people to dismiss the one
that matters.
