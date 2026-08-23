# Sakura Store

The reason for not shipping Discover. This is the piece that has to be
excellent, so it is worth being precise about what is actually possible before
designing around what isn't.

## What the ecosystems actually provide

Checked against the live APIs rather than assumed:

| | Reality |
|---|---|
| **Flathub** | 3,332 apps. **No ratings and no reviews of any kind.** The summary API has no such field. |
| **Discover's reviews** | Not Discover's. They come from **ODRS** (odrs.gnome.org) — an open service GNOME Software and Discover both read. 10,700 apps with star distributions, free API, anyone can post. |
| **Snap Store** | The info API returns title, summary, publisher. No ratings. |
| **AppImageHub** | Pling/Opendesktop network; ratings exist but are per-listing, not per-app-across-sources. |
| **AUR** | Votes and popularity, not reviews. A different kind of signal — "many people use this" rather than "people liked it". |

**So "combine ratings from Flathub, Discover, Snapcraft and AppImageHub" does
not survive contact.** Two of those four have no ratings to give, and the third
(Discover) is really ODRS. What is left is essentially one review source plus
two popularity signals.

That is a better position than it sounds. ODRS is open both ways: a review a
SakuraOS user writes goes into the same pool that helps every Linux user, and
we inherit 10,700 apps of existing reviews on day one without asking anyone to
seed a new system. A store with its own private review pool starts empty and
stays empty.

**An averaged cross-source rating would be a lie anyway.** 4.6 from twelve ODRS
reviews and 3.9 from forty thousand Snap ratings are not commensurable, and
averaging them produces a number that means nothing. Show each source with its
count and let the reader weigh them. Precision here is a feature — the whole
distribution is built on not overselling.

## Auto-updates: the thing worth getting right

Neither Discover nor GNOME Software keeps applications current on their own.
A store that does, across every source, is a genuine first and fits the rest of
the system exactly.

| Source | How | Honest limit |
|---|---|---|
| Flatpak | `flatpak update`, proper revision tracking | None. This works. |
| Snap | snapd already auto-refreshes | None, if snapd is present at all |
| Repo / AUR | Already handled by the update engine | AUR needs a rebuild on soname bumps |
| **AppImage** | Embedded zsync update information | **Opt-in by the developer.** An AppImage without it has no way to know it is stale. |

Two things had to be established by testing rather than assumption:

The update string is not always a URL. `zsync|https://...` is one form;
`gh-releases-zsync|OWNER|REPO|RELEASE|pattern.zsync` is the other, and it is a
pattern that has to be resolved against the GitHub releases API first. Only
the literal tag `latest` means the latest-release endpoint — `continuous` is
an ordinary rolling tag, and asking for `/releases/latest` returns a different
release entirely.

Arch's `zsync` is version 0.6.6, which predates widespread HTTPS and cannot
read a control file over it. Every real AppImage update URL is https, so the
packaged tool cannot update anything at all. `zsync2` is the maintained
rewrite and is rebuilt into sakura-core alongside snapd.

The AppImage gap is real and cannot be engineered away for apps whose authors
did not add update information. Where it is absent, the honest options are to
watch the origin the file came from, or to say plainly that this one cannot
update itself. Claiming otherwise would be the same overselling this project
keeps refusing elsewhere.

## Matching one app across sources

Selecting Flatpak by default and offering the same app from another source
needs a link between identities that do not share a namespace: Flatpak uses
reverse-DNS (`org.mozilla.firefox`), Snap and the AUR use bare names
(`firefox`), AppImages use whatever the author called the file.

AppStream component IDs join Flatpak and repository packages reliably. The rest
needs a mapping table that somebody maintains. That is ongoing curation, not a
clever algorithm, and it should be a data file in this repository that anyone
can send a correction to.

## Decisions

**Ratings come from ODRS, popularity is shown separately.** ODRS is one pool
that GNOME Software and Discover both read, it takes anonymous submissions
with no account, and it already covers 10,700 apps. A review written in
SakuraOS therefore helps every Linux user, and we start with history rather
than an empty table. Flathub install counts and AUR votes appear beside it,
labelled as popularity rather than opinion. There is no blended figure.

**Snap is supported properly.** snapd is rebuilt into sakura-core so Snap works
without requiring the AUR. Verified to build. This is a standing commitment:
we maintain snapd on Arch, including the confinement gaps that come from Arch
not carrying Ubuntu's AppArmor policies.

## Snap on Arch, in detail

`snapd` is not in Arch's repositories — it is AUR-only. That creates a loop:
the AUR is off by default in SakuraOS, so enabling a store backend would
require enabling the thing the store is supposed to gate. Confinement also
depends on AppArmor policies that do not fully apply outside Ubuntu, so Snap
sandboxing on Arch is weaker than it appears. And the Arch community's opinion
of Snap is not neutral.

Including it is defensible; it should be a decision rather than an assumption.

## Flatpak permissions and AppImage management

Neither needs a third-party application.

Plasma already ships `flatpak-kcm`, which is Flatseal's job done natively in
Qt and already present in our build. The store links to it per application
rather than duplicating it — the control belongs where the user is already
thinking about that app, not in a separate GTK window.

AppImage handling follows the approach AppManager
(github.com/kem-a/AppManager, GPL-3.0) worked out: zsync delta updates from
the file's own embedded update information, checksum verification before
anything is made executable, and desktop integration so an AppImage behaves
like an installed application. Reimplemented rather than shipped, because
AppManager is GTK4/libadwaita on a Plasma desktop and because managing
applications in two separate places is the confusion this store exists to
remove. The protocol work is not ours — zsync2 does the delta transfer.

## Developer uploads

Hosting other people's software is not a feature, it is a business: submission,
review, signing, storage, bandwidth, moderation, abuse, takedowns, and a
security contact who answers. Nothing about the store's design should make it
hard to add a first-party source later — the source abstraction below is built
for exactly that — but it should not be promised until someone owns the
operational side.

## Architecture

**A source is an interface, not a special case.** Flatpak, Snap, AppImage, the
AUR, our repositories, and one day a Sakura-hosted source all implement the
same small contract: search, detail, install, remove, check for updates,
report progress. Adding a source is implementing that contract, not editing
the UI.

**One transaction queue, one lock.** Every install failure people blame on
Discover comes from two things happening to the same package database at once.
The store and the update engine share the lock that already exists.

**Progress is a state machine, not a spinner.** Resolving, downloading (bytes
and rate), verifying, installing, configuring, done. Every one of those is
nameable, so the store can always say what it is doing rather than showing a
bar that stops at 40%.

**Failures are resumable and explicit.** A dropped download resumes. A failed
install says what failed and offers the next step. Nothing is left half
applied.

## Interim sync

The account can wait. What is small and useful now is an exportable list of
installed applications and their sources — a file you carry to another SakuraOS
machine and import. It also becomes the payload the account syncs later, so it
is not throwaway work.
