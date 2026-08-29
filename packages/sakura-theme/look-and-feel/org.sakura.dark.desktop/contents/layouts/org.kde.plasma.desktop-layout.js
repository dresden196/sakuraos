// Default SakuraOS desktop layout.
//
// Same as Plasma's default panel, with opacity forced to translucent so the
// blur effect has something to act on. Left at Adaptive -- Plasma's default --
// the panel turns opaque the moment a window is maximised, which is most of
// the time, and the frosted look would essentially never be seen.
var panel = new Panel;
panel.location = "bottom";
panel.height = Math.round(gridUnit * 2.4);
panel.alignment = "center";
panel.hiding = "none";
panel.opacity = "translucent";

panel.addWidget("org.kde.plasma.kickoff");
panel.addWidget("org.kde.plasma.pager");
var tasks = panel.addWidget("org.kde.plasma.icontasks");

// Pin what we actually ship. Left unset, icontasks falls back to Plasma's
// built-in defaults, which pin Discover -- a store we do not install, so the
// launcher pointed at a .desktop file that does not exist and showed up as a
// broken icon on a fresh desktop.
//
// Deliberately short. Every pin is a claim that a new user needs this in the
// first minute, and a panel that arrives full is one the user has to tidy
// before it is theirs.
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:org.sakuraos.store.desktop",
    "applications:org.kde.konsole.desktop",
].join(","));
panel.addWidget("org.kde.plasma.marginsseparator");
panel.addWidget("org.kde.plasma.systemtray");
panel.addWidget("org.kde.plasma.digitalclock");
panel.addWidget("org.kde.plasma.showdesktop");

var desktop = desktopForScreen(0) || desktops()[0];
if (desktop) {
    desktop.wallpaperPlugin = "org.kde.image";
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktop.writeConfig("Image", "Sakura");
}
