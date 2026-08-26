# The kernel claim, and what to read before honouring it

## What we currently claim

The installer's tour page tells the user SakuraOS tunes the kernel. Nothing
tunes the kernel. `linux-sakura` does not exist; installs run stock `linux`
from Arch. This is tracked in claims.md as unmet and is one of the reasons
nothing ships yet.

## What to review first

Two CachyOS repositories, before writing any of our own:

- **github.com/CachyOS/linux-cachyos** -- the PKGBUILDs. Worth reading not for
  the patches themselves but for the packaging shape: they build several
  flavours from one source tree, and how they express that is the decision we
  would otherwise get wrong by inventing it.
- **github.com/CachyOS/kernel-patches** -- the patch set, organised per kernel
  version. This is the part that ages: a patch set is a maintenance commitment
  that arrives every time upstream releases, and taking it on is a bigger
  promise than shipping a config.

## The question to answer, which is not "which patches"

The honest question is whether we can carry a kernel at all. A tuned kernel
that lags upstream security fixes is worse than the stock one, and the
schedule is set by upstream, not by us. So the options in order of increasing
commitment:

1. Ship stock `linux` and drop the claim from the tour. Cheapest, and honest.
2. Ship stock `linux` with a tuned **config** -- scheduler and preemption
   settings, no source patches. Rebuilds are mechanical and track Arch's own
   kernel releases.
3. Carry a patch set. Real work, forever, and only defensible if we can say
   what it buys a desktop user in terms they would notice.

Nothing here justifies 3 yet. What would justify it is a measurement on the
kind of machine SakuraOS is for, not a benchmark table from someone else's
repository.

## Credit

CachyOS is GPL-2.0 and does this work in the open. If we take any of it --
config, packaging approach, or patches -- it gets an ATTRIBUTION file the way
the Zorin work did.
