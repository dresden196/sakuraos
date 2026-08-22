# The Sakura installer

`sakura-install` (built, tested) is the backend. This describes the face that
drives it. The graphical installer never reimplements partitioning or boot
setup — there is one implementation of the risky part and it is the one under
test.

## Principle

Someone installs an operating system once and then lives with the result for
years. The installer's job is not to be quick; it is to leave the user
understanding what they just agreed to. Every screen that asks for a decision
also says what happens if they pick wrong, and every screen that does not need
a decision does not ask one.

## Screens

**1. Language and region.** Detect from the live session; confirm rather than
ask.

**1b. Keyboard.** Layout and variant, with a test field to type into. Detected
from the live session where possible. This is one of the few screens where
getting it wrong locks someone out of their own machine at the first login
prompt, so the test field is not optional.

**1c. Time.** Timezone, picked from a map or a search field, and 12- or
24-hour format.

The format setting has to be written in more than one place or it appears to
half-work: Plasma's digital clock widget carries its own format setting
independent of the locale, and the lock screen clock is a separate surface
again. A user who picks 12-hour and sees a 24-hour clock on the lock screen
will reasonably conclude the installer ignored them.

**1d. Light or dark.** Two large previews, dark preselected. This is a
first-class question, not something buried in Settings afterwards — it is the
single biggest visual decision a user has, and they have an opinion about it
before they have an opinion about anything else here.

The wallpaper follows automatically: the same stretch of the Meguro river by
day for light, by night for dark.

**2. Disk.** One clear choice: use the whole disk, or choose partitions. The
default path never shows the word "subvolume". Encryption is a checkbox here,
not a separate screen.

**3. Who are you.** Name, username, password. Avatar picker: the ring of stock
faces from `/usr/share/sddm/faces`, plus "Choose a photo…" and a webcam
capture. This is the screen people remember, and it costs almost nothing.

**4. Browser.** Zen selected by default, with Firefox, Chrome and Brave
offered alongside. All four are one click, and the choice is reversible from
the store afterwards — which the screen should say, because a browser choice
presented as permanent makes people anxious about it.

Zen as the default carries a real obligation: it is a Firefox fork maintained
by a small team, so its security-patch lag behind upstream Firefox needs
watching. If that lag grows, the default changes. That is a maintenance
commitment, not a one-time decision.

**5. Updates.** Automatic updates on, tested-first on, a time picker, and
"only when plugged in". Same settings as the System Settings page, same file,
so the installer is not a separate source of truth. Configuring this at
install time rather than burying it is the point: it is the difference between
a machine that stays current and one that is nine months behind.

**6. What Sakura does for you.** Not a EULA. Three short cards:

- **Terminal Assist** — commands that would break the system get stopped and
  explained. You can always override.
- **Restore points** — a snapshot before every update, and a Recovery entry in
  the boot menu. A bad update is a reboot, not a reinstall.
- **The AUR** — off by default, because it is unreviewed build scripts written
  by other users. Turn it on in Settings when you want it.

**7. Privacy.** A plain statement, not a consent maze:

- No telemetry is collected by default.
- Nothing is sent anywhere without being asked first.
- Optional crash reports, off unless switched on, with a link to exactly what
  a report contains.

The honest reason to offer crash reporting at all: a distribution running
blind cannot fix what it cannot see. That reason belongs on the screen, so the
user is deciding rather than guessing.

**8. Install.** Progress with real steps, not a fake bar. The log is one click
away and reads in plain language.

## Implementation

Qt6 / QML, driving `sakura-install` over a privileged helper. The installer
process itself never runs as root.

It writes exactly two things the backend does not already own: the browser
choice (a package to add) and the update settings (a drop-in
`/etc/sakura/sakura.conf` written into the target before first boot).
