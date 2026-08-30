# The SakuraOS kernel

CachyOS's kernel, built by us, for x86-64-v3. Built by `build/build-kernel.sh`,
pinned in `kernel.conf`.

## Why this and not our own

`docs/kernel.md` has the long version. Short: stock Arch already carries
HZ=1000, PREEMPT_DYNAMIC, sched-ext and LRU_GEN, and most of what remains in
CachyOS's tuning is reachable from userspace — which is what `sakura-tuning`
already ships and why it works on the stock kernel too. What is *not* reachable
from userspace is the compile: the scheduler, ThinLTO, -O3 and the `-march`
baseline. That is the half this package exists for.

The two layers are orthogonal and must stay that way:

| | Sets | When |
|---|---|---|
| `linux-cachyos` | scheduler, LTO, -O3, `-march`, HZ, preemption | compile |
| `sakura-tuning` | sysctls, I/O scheduler | runtime |

**Never install `cachyos-settings`.** It carries its own sysctls *and* its own
I/O scheduler udev rules, which fight `sakura-tuning` for the same knobs with
load order deciding the winner. The kernel package only.

## GENERIC_V3 is a correctness requirement, not a tuning choice

Left at its upstream default, `_processor_opt` is empty and the PKGBUILD
enables `X86_NATIVE_CPU` — it compiles for whatever CPU the *build machine*
has. That produces a kernel that boots on the builder and nowhere else, and
nothing about it looks wrong until somebody else tries to start it.

`GENERIC_V3` is the value CachyOS's own release script uses for their v3
repository. `build/build-kernel.sh --verify` reads the baseline back out of
the prepared config rather than trusting that the variable arrived:

    CONFIG_GENERIC_CPU=y
    CONFIG_X86_64_VERSION=3

with `CONFIG_X86_NATIVE_CPU` absent. If that check ever prints something else,
do not ship the result.

## Why the options are environment variables, not a patch

Their PKGBUILD sets every option with `: "${_var:=default}"`, so exporting the
variable overrides it. That matters more than it looks.

Their `b2sums` covers a source array whose *length* changes with some options.
Edit the file and the sums no longer line up, and the only way to finish a
build is `--skipinteg` — which throws away integrity checking on a kernel.
Setting variables leaves the array, and therefore the sums, exactly as
published.

So this is the one package in the repository built **without** `--skipinteg`.
Every source is checked against upstream's own b2sums, and the tarball's PGP
signature is verified against the fingerprints in `validpgpkeys` at the pinned
commit. Keys are fetched by full fingerprint — a short id is not unique.

## Bumping it

1. Read what changed upstream between the pinned commit and the new one.
2. Update `KERNEL_COMMIT` in `kernel.conf`, and `KERNEL_PGP_KEYS` if
   `validpgpkeys` changed.
3. `./build/build-kernel.sh --verify` — confirm sources verify and the
   baseline still reads `X86_64_VERSION=3`.
4. `./build/build-kernel.sh` — hours, not minutes.

Their tags lag badly: when this was pinned the newest tag was 6.17.9 while
master was on 7.2.x. A tag is not a release here; pin commits.

## Which machines get it

`sakura-install` decides, by asking glibc's loader which x86-64 levels this
CPU supports — the same check the dynamic linker uses for hwcaps libraries, so
it agrees with the rest of the system by construction. v3 and above get this
kernel; anything older gets stock `linux`, quietly. `sakura-desktop` names no
kernel at all, the way Arch's `base` does not.

## Attribution and naming

The installer's credits page carries CachyOS alongside Arch, KDE and Limine,
with their own logo from cachyos.org. Their scheduler work, build
configuration and hardware patches are the reason this kernel is worth
shipping, and the credit belongs where a user will see it rather than only in
a source file.

**The kernel is not renamed, and this is a deliberate trade.** The obvious
move -- calling the package `linux-sakura` so nothing says "cachyos" -- means
patching their PKGBUILD, and that is exactly what costs the property this
package is built on: their `b2sums` and the tarball's PGP signature verify
only because the file is used byte for byte. `_pkgsuffix` is assigned
unconditionally inside their script, so it cannot be overridden from the
environment either; renaming genuinely requires a fork.

What a user actually sees at boot is already ours. The limine entries read
`SakuraOS` and `SakuraOS Recovery`, and the firmware entry is `SakuraOS`;
none of them mention the kernel package. Verified on an installed machine.

What still says `cachyos` is `uname -r` (`7.2.2-1-cachyos`) and the package
name in the store. Those are surfaces we control the *presentation* of, so
the answer is to label it there rather than to fork upstream for a string.
