# What CachyOS actually changes, and what we should do about it

Measured on 2026-08-26 against `cachyos-7.2.0-1` and the running Arch kernel
`7.1.8-arch1-3`. Numbers here came from the GitHub compare API and from
reading the configs, not from the feature list.

## First: it is not a patch set

`kernel-patches/7.2` looks small because the base patchset is not in it. The
PKGBUILD's `source=()` pulls a **pre-patched tarball** from
`github.com/CachyOS/linux/releases`, which is a 6.3 GB fork of
`torvalds/linux`. `kernel-patches` holds only the opt-in extras -- BORE, PRJC,
handheld, aufs, hardened, the NVIDIA fixups.

So "take the CachyOS kernel and tweak it" does not mean cherry-picking
patches. It means becoming a downstream of their tree. That is a different
commitment and it should be named accurately before anyone signs up for it.

## The size and shape of the delta

    v7.2 ... cachyos-7.2.0-1     256 commits ahead, 0 behind
                                 +20,662 / -463 lines across 240 files

**Zero behind** is the important half. They rebase onto every upstream
release, and upstream sets that pace, not them:

    7.1.7    2026-08-09
    7.1.8    2026-08-10
    7.2-rc6  2026-08-03      7.2-rc7  2026-08-10
    7.2.0    2026-08-17

Six releases in two weeks. Inheriting the tree means inheriting that cadence,
because the alternative -- lagging -- means shipping a kernel that is missing
upstream security fixes. A tuned kernel that lags is worse than a stock one.

## What the 256 commits are

Mostly hardware enablement, not scheduler magic:

| commits | area |
|---|---|
| 19 | HID (Steam Deck, ROG Ally, MSI Claw) |
| 18 | drm/amd/display |
| 10 | applesmc (T2 Macs) |
| 9 | sched/fair |
| 9 | cpufreq/amd-pstate |
| 8 | drm/edid |
| 8 | smp (preempt-IPI series) |
| 12 | ALSA + ASoC |

Their own tuning is tagged `CACHY:` and is **eight commits**. All eight, in
full:

- sched/fair: Tweak EEVDF for interactivity
- Enable background reclaim of hugepages
- Disable watermark boosting by default
- Disable proactive compaction by default
- Disable split lock mitigation by default
- Use BFQ for SQ devices and mq-deadline for MQ devices
- mm: lru-gen: Protect the working set of the last 100 jiffies
- v4l2-core: add v4l2loopback

That list is worth staring at, because most of it is not a code change at all.
It is a change of *default*.

## Most of the advertised wins are already true on stock Arch

Checked against the running kernel, not assumed:

| | CachyOS | Arch stock |
|---|---|---|
| `HZ` | 1000 | **1000** |
| `PREEMPT_DYNAMIC` | y | **y** |
| `SCHED_CLASS_EXT` (sched-ext) | y | **y** |
| `TRANSPARENT_HUGEPAGE_ALWAYS` | y | **y** |
| `LRU_GEN` + `LRU_GEN_ENABLED` | y | **y** |
| `TCP_CONG_BBR` | m | **m** |

One correction worth recording: the `config` checked into their repo says
`HZ=300`, which looks like a difference and is not one. The PKGBUILD rewrites
it at build time (`_HZ_ticks:=1000`, `scripts/config --set-val HZ`). Reading
the file without reading the build would have produced a wrong answer.

## Five of the eight are reachable without a kernel at all

Verified present and writable on stock Arch:

| CachyOS commit | equivalent on stock |
|---|---|
| Disable watermark boosting | `vm.watermark_boost_factor` (is 15000) |
| Disable proactive compaction | `vm.compaction_proactiveness` (is 20) |
| lru-gen working set protection | `/sys/kernel/mm/lru_gen/min_ttl_ms` (is 0) |
| BFQ for SQ, mq-deadline for MQ | udev rule on `queue/scheduler` |
| Disable split lock mitigation | `split_lock_detect=off` on the cmdline |

That leaves two that genuinely need a patched tree -- the EEVDF interactivity
tweak and background hugepage reclaim -- plus v4l2loopback, which Arch already
packages separately.

A sysctl file, a udev rule and one kernel parameter get most of the way. None
of it requires maintaining a fork.

## sched-ext is the part that changes the decision

`/sys/kernel/sched_ext` exists on the stock Arch kernel, and `scx-scheds
1.1.2-1` is in `extra` with **fifteen** schedulers: bpfland, lavd, rusty,
flash, layered, p2dq, cake, cosmos, flow, forge, chaos, tickless, rustland,
beerland, pandemonium.

Schedulers are BPF programs now. They load and unload at runtime. The thing
CachyOS needs a fork and a rebuild to offer -- pick your scheduler -- is
available on a stock kernel, switchable while the machine is running, with no
reboot and no compile.

## Recommendation

Do not fork the kernel. Three steps, in order of cost:

1. **Keep stock `linux`.** It already has the tick rate, the preemption model,
   the memory-management generation and sched-ext.
2. **Ship the defaults as configuration.** A sysctl drop-in, a udev rule for
   the I/O scheduler, one cmdline parameter. This is where the measurable part
   of "CachyOS Sauce" actually lives, and it is a package we can write in an
   afternoon and revert per-machine.
3. **Put the scheduler in Settings**, backed by `scx_loader`. This is the
   honest version of the tour's claim, and it is *our* differentiator rather
   than a borrowed one: not "we compiled a kernel for you" but "change how
   this machine schedules work, now, and change it back if you do not like
   it." CachyOS's own Kernel Manager is heading the same way.

What this does not buy: BORE, ThinLTO, AutoFDO/Propeller, x86-64-v3/v4 builds,
prebuilt NVIDIA and ZFS modules. Those need the fork. Each is real, and none
of them is worth a permanent rebase treadmill until somebody has measured what
they are worth **on the machines SakuraOS is for**. AutoFDO alone means
building the kernel twice, per release, forever.

## If we take their kernel anyway

The proposal was: default to the CachyOS kernel, fall back to stock for
anything below x86-64-v3, or non-Ryzen. Checked, and the fallback is not
needed -- the premise is wrong in a useful direction.

`script.sh`, which is what builds their main repo, sets
`_processor_opt:=GENERIC`. The default `linux-cachyos` is a plain x86-64
build, `arch=('x86_64')`, and runs on anything from a Core 2 upward. The
v3/v4/znver4 variants are *separate repositories* of whole-system rebuilds
(`script-v3-v4.sh` sets `GENERIC_V3`, `script-znver4.sh` sets `zen4`), not a
requirement of the kernel. There is no CPU baseline to fall back from and
nothing Ryzen-specific: the amd-pstate work helps AMD, it does not exclude
Intel.

**Do not add their repositories.** `cachyos` alone carries 840 packages --
whole-system rebuilds that would shadow Arch's, and pacman has no per-package
repo pinning to stop that. Adding it to a non-CachyOS system is unsupported by
them and would quietly change packages far outside the kernel.

**Take it through the AUR instead.** `linux-cachyos` is in the AUR at 7.2.0-1,
so it goes through the rebuild pipeline `sakura-core` already runs for
`limine-snapper-sync` and the rest: build from the PKGBUILD, sign with our
key, publish to our repo. No dependency on anyone else's mirror, and the
result is a package we control.

What that commits us to, and it is not small:

- **Their cadence, weekly.** 0 commits behind upstream is a promise to rebuild
  whenever upstream moves.
- **Modules in lockstep.** Proprietary NVIDIA and ZFS must be rebuilt against
  each kernel or they break on boot, for exactly the users least able to
  recover.
- **Twice the boot surface.** Two kernels means two UKIs, two mkinitcpio
  presets, two things to sign for Secure Boot, and a longer boot menu that the
  recovery watchdog has to reason about.
- **Build cost that is unmeasured.** ThinLTO is expensive and AutoFDO builds
  the kernel twice. Neither has been timed on the hardware we actually have,
  which is a laptop running a container. That number should exist before the
  decision, not after.

The fallback worth having is a different one. Not "older CPUs get stock" but
**stock stays installed as the second boot entry** -- a known-good kernel to
choose when a fast-moving one regresses. That is the same shape as the
snapshot rollback we already ship, applied to the kernel, and it is useful
precisely because their tree moves quickly.

And the honest reason to want their tree is not speed. It is hardware: 19 HID
commits, 10 for T2 Macs, the ASUS/Lenovo/HP WMI work. Configuration cannot
give us those. Performance, we can mostly reach without them.

## The build was measured, and it settles the question

Run on 2026-08-26 on the development laptop: 14 cores, 10 given to the build,
`nice -n 10`, in the same container the rest of our packages build in.
Deliberately the *cheap* configuration -- GCC rather than Clang, ThinLTO off,
AutoFDO off, Propeller off, no ZFS, no NVIDIA, `GENERIC` x86-64.

After **eight hours**:

    objects compiled     11,949
    modules linked            0   of 6,314 configured
    still in              drivers/usb/storage
    build tree              8.4 GB
    -O3                    yes (CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3, from _cc_harder)

Not stuck -- `cc1` was pinned at 98% throughout and objects were appearing
every few seconds. It is simply a distro kernel: 6,314 modules, compiled at
-O3, and after eight hours it had not finished compiling, let alone started
linking a single module. Twenty hours is a conservative estimate for the whole
job, and this was the configuration chosen to be fast. AutoFDO, which is what
the headline `linux-cachyos` package actually ships, builds the kernel *twice*.

The build was stopped at that point rather than run to completion. The number
needed was an order of magnitude, and eight hours of load 12 on somebody's
daily driver is enough to establish one.

**So: not on this hardware.** Carrying this kernel is not a code problem, it is
an infrastructure problem, and it needs answering before the kernel is
promised to anyone:

- A dedicated builder -- 32 to 64 cores -- rented per kernel release. A few
  hours of a large cloud instance is a few dollars, weekly. That is a real
  answer and a small budget, but it is a standing bill and a second machine to
  keep working.
- `-O2` instead of `-O3` (`_cc_harder=no`) would cut this materially and
  costs almost nothing measurable in return. Worth doing whatever else we
  decide.
- Nothing else scales. The module count is what it is; a distro kernel cannot
  drop modules for hardware the user might have, and `_localmodcfg` -- build
  only what this machine loads -- produces a kernel that boots on the build
  box and nowhere else.

One further friction found on the way: the AUR PKGBUILD cannot be reconfigured
with its checksums intact. Changing `_use_llvm_lto` changes the length of the
`source=()` array while `b2sums` stays fixed, and makepkg refuses with
"Integrity checks (b2) differ in size from the source array". `--skipinteg`
was used for the measurement and must never be used for a shipped build;
a real pipeline has to regenerate the sums after configuring, which is what
CachyOS's own scripts do inside their build image.

## Credit

CachyOS is GPL-2.0 and does this in the open. If we take their sysctl values,
their udev policy, or anything else, it gets an ATTRIBUTION file the way the
Zorin work did -- the measurements above are theirs, we are only reading them.
