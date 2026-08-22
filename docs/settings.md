# Sakura Settings

A page in System Settings, not a separate app. It binds to
`/etc/sakura/sakura.conf` — the same file the pacman hooks, the shell
integration and the update timer read — so the switch and the thing it
controls can never disagree.

Implemented as a KCM (KDE Config Module) in QML, with a privileged helper over
DBus and polkit for the writes, since these are system-wide settings. The GUI
never runs as root.

## Pages

### Terminal Assist

`Mode`: block / warn / off.

Two layers, and both are needed. The pacman hook cannot be dodged by switching
frontend — the store, a terminal, yay and a pasted shell script all go through
it — but by the time it runs the original command line is gone, so a bare
`pacman -Sy foo` is indistinguishable from a correct one. The shell layer sees
the command line but anyone can step around it. Neither is sufficient alone.

Overrides name the specific rule (`SAKURA_ASSIST_OVERRIDE=remove-critical`).
A generic "yes I'm sure" flag becomes muscle memory within a week; having to
type the rule name means you read the message. An override waives only the
rule it names — a second, different problem in the same transaction still
stops it.

### AUR

Off by default. The AUR is unreviewed third-party build scripts and a new user
has not agreed to that yet.

**Review before install.** Shows what the build script does, and what changed
since the version you last accepted. The diff matters more than the contents:
package takeover and malicious updates are the dominant real-world AUR attack,
and a diff has high signal with almost no false positives. Free metadata from
the AUR RPC feeds the same view — maintainer changed last week, adopted three
days ago, orphaned, two votes, flagged out of date.

**Known-campaign scanning.** Checks installed packages against published attack
campaigns: package lists, `pacman.log` history, known-bad file hashes,
malicious systemd units, poisoned npm/bun caches. Exact rather than heuristic,
and therefore worth running — but retrospective. It answers "was I hit by
something already published", not "is this package safe".

Builds on `aur-malware-check` (GPL-3.0, compatible with ours).

**Naming is a deliberate decision, not cosmetics.** This is not called a
malware scanner, because nothing can deliver what that name promises: a
PKGBUILD is arbitrary shell that fetches arbitrary source and compiles it. A
user who believes they are protected stops reading PKGBUILDs, which is exactly
the behaviour the feature exists to encourage. The honest name keeps the
caution that actually protects people.

**Helper**: `yay` or `none`. With `none`, no AUR helper is installed at all and
the AUR is reachable only through the store, where the review step is not
optional.

### Updates

See `updates.md`.
