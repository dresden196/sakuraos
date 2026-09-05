import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Dialogs
import QtQuick.Effects

QQC2.ApplicationWindow {
    id: root

    // Full screen. Installing is the only thing anyone does on this boot, and
    // a window is something to be minimised, moved behind a file manager, or
    // simply not noticed on a large display. There is nothing else here to
    // get to.
    visibility: Window.FullScreen
    width: Screen.width
    height: Screen.height
    minimumWidth: 900
    minimumHeight: 600
    visible: true
    title: "Install SakuraOS"


    // ---- palette -----------------------------------------------------------
    // Bound to the appearance answer rather than fixed, so choosing light or
    // dark on that screen repaints the installer itself. Showing someone the
    // theme they picked beats describing it.
    //
    // The two accents differ for the same reason the shipped colour schemes
    // do: the blossom pink measures 1.60:1 on a light background, well under
    // the 3.0:1 controls need, but 10.24:1 on a dark one.
    readonly property bool  dark:   answers.dark
    // Light mode used #d81b60, which is legible and is not the colour this
    // operating system is named after -- it reads as magenta beside a page of
    // blossom pink. The constraint behind it is real, though: the literal
    // #ffb7c5 manages 1.64:1 against a light background, far under the 3:1 a
    // border or a focus ring needs to be seen at all.
    //
    // #e0648c is the pinkest colour that clears it -- 3.30:1 on white -- and
    // it takes dark ink at 4.21:1. That last number is knowingly short of the
    // 4.5:1 wanted for normal-size text, and is the reason this comment
    // exists rather than being a thing to discover later: the alternative was
    // 2.80:1, or a brand colour that is not the brand.
    readonly property color accent: dark ? "#ffb7c5" : "#e0648c"
    readonly property color accentText: "#3a2731"
    readonly property color bg:     dark ? "#26161e" : "#faf6f8"
    readonly property color panel:  dark ? "#2f1f28" : "#f1e7ec"
    readonly property color card:   dark ? "#3a2731" : "#ffffff"
    readonly property color text:   dark ? "#f6eef2" : "#2b1f25"
    readonly property color dim:    dark ? "#bfa8b4" : "#6f5c66"
    readonly property color line:   dark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.10)

    color: bg
    Behavior on color { ColorAnimation { duration: 180 } }

    // One content width, centred, rather than every page picking its own
    // max-width and hugging the left edge of a much wider pane.
    // How wide the questions are. Fixed at 620 it left most of a 1920 display
    // empty either side of a narrow strip -- fine in a window, odd once the
    // installer went full screen. Grows with the display and then stops:
    // running text past about 900 pixels is harder to read, not easier.
    readonly property int contentWidth:
        Math.max(560, Math.min(900, width - 520))

    // The summary shows what was chosen, not the codes those choices are
    // stored as. "en_US.UTF-8" and "us" are what the system wants; nobody
    // checks their answers against them.
    function localeName(code) {
        var all = backend.languages()
        for (var i = 0; i < all.length; ++i) {
            if (all[i].code === code) {
                return all[i].native
            }
        }
        return code
    }
    function layoutName(code) {
        var all = backend.keyboardLayouts()
        for (var i = 0; i < all.length; ++i) {
            if (all[i].code === code) {
                return all[i].name
            }
        }
        return code
    }

    // ---- collected answers -------------------------------------------------
    property var answers: ({
        locale: "en_US.UTF-8",
        diskMode: "wipe",
        encrypt: false,
        encryptPassword: "",
        encryptConfirm: "",
        keyboard: "us",
        timezone: "UTC",
        hour24: true,
        dark: true,
        disk: "",
        fullname: "",
        username: "",
        // The accent, as a hex string. Cherry blossom by default -- it is the
        // name of the operating system -- but somebody who does not want a
        // pink desktop should not have to live with one.
        accent: "#ffb7c5",
        hostname: "sakura",
        password: "",
        avatar: "",
        browser: "zen-browser-bin",
        autoUpdate: true,
        canaryOnly: true,
        updateTime: "03:00",
        acOnly: true,
        crashReports: false
    })

    property int step: -3
    readonly property var steps: [
        { title: "Language",   blurb: "What this machine speaks" },
        { title: "Keyboard",   blurb: "How your keys are laid out" },
        { title: "Network",    blurb: "Getting this machine online" },
        { title: "Time",       blurb: "Where you are, and how you read a clock" },
        { title: "Appearance", blurb: "Light or dark" },
        { title: "Disk",       blurb: "Where SakuraOS goes" },
        { title: "Encryption", blurb: "Whether the disk is readable without you" },
        { title: "Account",    blurb: "Who this machine belongs to" },
        { title: "Browser",    blurb: "How you get online" },
        { title: "Updates",    blurb: "Staying current, safely" },
        { title: "Sakura",     blurb: "What this system does for you" },
        { title: "Privacy",    blurb: "What leaves this machine" },
        { title: "Summary",    blurb: "Check before anything is written" },
        { title: "Install",    blurb: "" }
    ]

    // Guards for the steps that have a wrong answer as well as a right one.
    //
    // These are indices into steps[], so inserting a step shifts every one of
    // them. Adding Network in third place and not moving these left Continue
    // dead on Appearance, because Appearance had become case 4 and case 4
    // asks whether a disk has been chosen. Whenever a step is added, this
    // switch moves with it -- it is the one place the numbers are not
    // obviously about pages.
    // One or two letters from whatever has been typed so far. Two words give
    // two initials, one word gives one; nothing typed gives nothing, and the
    // caller draws a plain circle rather than a letter that is not there.
    // Whether the clock question has been answered by hand. Until it has, the
    // answer follows the time zone: somebody in Chicago expects 2:30 PM and
    // somebody in Berlin expects 14:30, and making them both correct it is a
    // question that did not need asking.
    property bool hour24Touched: false

    // Zones whose country writes the time on a 12-hour clock. A list rather
    // than a rule, because there is no rule: Brazil and Argentina are in the
    // Americas and write 24-hour, India and the Philippines are in Asia and
    // write 12-hour. Everything not named here defaults to 24-hour, which is
    // what most of the world uses.
    readonly property var twelveHourZones: [
        "America/New_York", "America/Detroit", "America/Chicago", "America/Denver",
        "America/Phoenix", "America/Los_Angeles", "America/Anchorage", "America/Adak",
        "America/Boise", "America/Juneau", "America/Sitka", "America/Nome",
        "America/Menominee", "America/Puerto_Rico", "Pacific/Honolulu",
        "America/Toronto", "America/Vancouver", "America/Edmonton",
        "America/Winnipeg", "America/Halifax", "America/St_Johns", "America/Regina",
        "America/Mexico_City", "America/Tijuana", "America/Monterrey", "America/Cancun",
        "America/Bogota", "Asia/Manila", "Asia/Kolkata", "Asia/Karachi",
        "Asia/Dhaka", "Asia/Kuala_Lumpur", "Africa/Cairo", "Pacific/Auckland"
    ]

    function zoneUsesTwelveHour(tz) {
        if (twelveHourZones.indexOf(tz) >= 0)
            return true
        // The US and Australian zones have a lot of members; matching the
        // prefix catches Indiana/* and Kentucky/* without listing all of them.
        return tz.indexOf("America/Indiana/") === 0
            || tz.indexOf("America/Kentucky/") === 0
            || tz.indexOf("America/North_Dakota/") === 0
            || tz.indexOf("Australia/") === 0
    }

    // The stored update time is always 24-hour "HH:MM", because that is what
    // the installer writes into the config and what the timer reads. Only the
    // presentation changes, so a machine set to a 12-hour clock does not end
    // up with a differently-shaped config file.
    function updateTimeDisplay() {
        var parts = (answers.updateTime || "03:00").split(":")
        var h = parseInt(parts[0], 10); var m = parts[1] || "00"
        if (isNaN(h)) { h = 3; m = "00" }
        if (answers.hour24)
            return (h < 10 ? "0" + h : "" + h) + ":" + m
        var h12 = h % 12; if (h12 === 0) h12 = 12
        return h12 + ":" + m
    }

    function updateTimeMeridiem() {
        var h = parseInt((answers.updateTime || "03:00").split(":")[0], 10)
        return (isNaN(h) || h < 12) ? "AM" : "PM"
    }

    // Parse whatever was typed back into 24-hour form. Anything unreadable
    // leaves the stored value alone rather than silently becoming midnight.
    function setUpdateTimeFrom(text, meridiem) {
        var parts = ("" + text).split(":")
        var h = parseInt(parts[0], 10)
        var m = parseInt(parts[1], 10)
        if (isNaN(h) || isNaN(m) || m < 0 || m > 59)
            return
        if (!answers.hour24) {
            if (h < 1 || h > 12) return
            h = h % 12
            if (meridiem === "PM") h += 12
        } else if (h < 0 || h > 23) {
            return
        }
        answers.updateTime = (h < 10 ? "0" + h : "" + h) + ":" + (m < 10 ? "0" + m : "" + m)
        answersChanged()
    }

    function initialsFor(name) {
        var parts = (name || "").trim().split(/\s+/).filter(function (w) {
            return w.length > 0
        })
        if (parts.length === 0) return ""
        if (parts.length === 1) return parts[0].charAt(0).toUpperCase()
        return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase()
    }

    function canContinue() {
        switch (step) {
        case 5: return answers.disk !== ""
        // Both fields, matching. A mistyped passphrase on an encrypted disk
        // is discovered at the next boot, when it is far too late.
        case 6: return !answers.encrypt
                    || (answers.encryptPassword.length >= 6
                        && answers.encryptPassword === answers.encryptConfirm)
        case 7: return answers.username.length > 0 && answers.password.length >= 4
        default: return true
        }
    }

    // ---- shared building blocks -------------------------------------------
    component Heading : ColumnLayout {
        id: headingRoot
        property string title
        property string subtitle
        // Centred only where a screen has something above it to centre under.
        // Everything else is left-aligned, and mixing the two on one screen
        // reads as a mistake rather than as emphasis.
        property bool centred: false
        Layout.fillWidth: true
        spacing: 6
        QQC2.Label {
            Layout.fillWidth: true
            text: headingRoot.title
            color: root.text
            font.pixelSize: 26
            font.weight: Font.Medium
            horizontalAlignment: headingRoot.centred ? Text.AlignHCenter
                                                     : Text.AlignLeft
        }
        QQC2.Label {
            text: headingRoot.subtitle
            color: root.dim
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            visible: text !== ""
            horizontalAlignment: headingRoot.centred ? Text.AlignHCenter
                                                     : Text.AlignLeft
        }
    }

    component Choice : Rectangle {
        property bool selected: false
        property string heading
        property string detail
        signal picked()

        Layout.fillWidth: true
        implicitHeight: inner.implicitHeight + 34
        radius: 14
        color: selected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) : root.card
        border.width: selected ? 2 : 1
        border.color: selected ? root.accent : root.line

        Behavior on color { ColorAnimation { duration: 110 } }

        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: 13
            spacing: 3
            QQC2.Label {
                text: heading
                color: root.text
                font.pixelSize: 15
                font.weight: selected ? Font.DemiBold : Font.Normal
            }
            QQC2.Label {
                text: detail
                color: root.dim
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                visible: text !== ""
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: picked()
        }
    }

    component Field : QQC2.TextField {
        Layout.fillWidth: true
        color: root.text
        placeholderTextColor: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.7)
        selectionColor: root.accent
        selectedTextColor: root.accentText
        leftPadding: 12
        topPadding: 10
        bottomPadding: 10
        background: Rectangle {
            radius: 10
            color: root.card
            border.width: parent.activeFocus ? 2 : 1
            border.color: parent.activeFocus ? root.accent : root.line
        }
    }

    // ---- layout ------------------------------------------------------------
    // ---- welcome -----------------------------------------------------------
    // ---- what this is built on ---------------------------------------------
    // Off the tour rather than in the sequence: nobody should have to page
    // past a credits screen to install an operating system, and burying it
    // where nobody finds it is not much better than not having one.
    QQC2.ScrollView {
        anchors.fill: parent
        visible: root.step === -1
        contentWidth: availableWidth
        clip: true

        // Centred when it fits, scrolled when it does not. These pages had
        // the column centred in the window with nothing to scroll, so on a
        // screen shorter than the content -- 1024x768, where plenty of older
        // laptops live -- it overflowed equally top and bottom: the heading
        // above the edge and the buttons below it, unreachable, with no way
        // to get to them. The spacer keeps the centred look on a tall screen.
        Item {
            width: parent.width
            implicitHeight: Math.max(inner1.implicitHeight + 80,
                                     root.height)

        ColumnLayout {
            id: inner1
            anchors.centerIn: parent
            width: Math.min(940, parent.width - 100)
            spacing: 20

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                text: "Made possible by"
                color: root.text
                font.pixelSize: 30
                font.weight: Font.Light
            }
            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "SakuraOS would not exist without these projects, and the people who give their work away so that things like it can be built."
                color: root.dim
                font.pixelSize: 14
            }

            Item { Layout.preferredHeight: 6 }

            GridLayout {
                id: creditRow
                Layout.fillWidth: true
                columnSpacing: 18
                rowSpacing: 18
                // Wraps. This was a RowLayout when there were three of these,
                // and adding four more squeezed every card until the text
                // clipped and the last one ran off the right edge -- on a
                // 1024-wide screen, which is not an unusual screen. Cards per
                // row is decided by the width there actually is.
                columns: Math.max(2, Math.min(4, Math.floor(width / 220)))
                Repeater {
                    model: [
                        {
                            // Arch's logo ships in the filesystem package, so
                            // it is read from disk and matches whatever the
                            // machine has. KDE's and Limine's are bundled,
                            // taken from kde.org's brand assets and Limine's
                            // own repository -- their marks, from their own
                            // hands, rather than off a clip-art site.
                            icon: "file:///usr/share/pixmaps/archlinux-logo.svg",
                            name: "Arch Linux",
                            body: "The distribution SakuraOS is built from, and the repositories "
                                + "it installs from. Its packaging, its documentation and its "
                                + "insistence on keeping things simple are why this could be "
                                + "built at all."
                        },
                        {
                            icon: "qrc:/assets/credit-kde.svg",
                            name: "KDE",
                            body: "Plasma is the desktop: the panel, the settings, the file "
                                + "manager, the login screen. Almost everything anyone will "
                                + "touch on this system is KDE's, and made by KDE."
                        },
                        {
                            icon: "qrc:/assets/credit-limine.png",
                            name: "Limine",
                            body: "The bootloader, and the menu that offers a restore point or "
                                + "another operating system. Every recovery SakuraOS promises "
                                + "starts with Limine handing over."
                        },
                        {
                            icon: "qrc:/assets/credit-cachyos.svg",
                            name: "CachyOS",
                            body: "The kernel. Its scheduler work, its build configuration and "
                                + "its hardware patches are what make this machine feel quick, "
                                + "and SakuraOS builds their work rather than its own."
                        },
                        {
                            icon: "qrc:/assets/credit-linux.svg",
                            name: "Linux",
                            body: "The kernel underneath all of it. Every drive, every network "
                                + "card and every screen this system will ever talk to, it "
                                + "talks to through Linux."
                        },
                        {
                            icon: "qrc:/assets/credit-gnu.png",
                            name: "GNU",
                            body: "The compiler, the C library and the shell -- the tools "
                                + "everything else here was built with, and largely built "
                                + "from. There is no version of this project without them."
                        },
                        {
                            icon: "qrc:/assets/credit-systemd.svg",
                            name: "systemd",
                            body: "What starts this machine, keeps its services running and "
                                + "puts it back together when something fails. The restore "
                                + "points and the recovery boot are built on it."
                        },
                        {
                            icon: "qrc:/assets/credit-btrfs.svg",
                            name: "Btrfs",
                            body: "The filesystem, and the reason this system can be put back. "
                                + "Every restore point is one of its snapshots, taken in a "
                                + "moment and costing almost nothing until something changes."
                        }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        // Equal heights come from the grid now. The card used
                        // to measure its own content, hand that to a shared
                        // tallest-card value, and read that value back as its
                        // own height -- a binding loop Qt reported on every
                        // launch. A GridLayout already gives every cell in a
                        // row the height of the tallest, which is the same
                        // result asked for once instead of in a circle.
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        implicitHeight: credit.implicitHeight + 36
                        radius: 14
                        color: root.card
                        border.width: 1
                        border.color: root.line
                        ColumnLayout {
                            id: credit
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top; anchors.margins: 18
                            spacing: 10
                            Image {
                                Layout.alignment: Qt.AlignHCenter
                                source: modelData.icon
                                sourceSize: Qt.size(140, 64)
                                fillMode: Image.PreserveAspectFit
                                Layout.preferredHeight: 56
                                // Height alone does not bound a logo. These
                                // marks are not all square -- systemd's is a
                                // wordmark several times wider than it is
                                // tall -- and with only a height set the item
                                // took its natural width, burst out of its
                                // card and shoved the text off the side.
                                Layout.maximumWidth: 140
                                Layout.maximumHeight: 56
                            }
                            QQC2.Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.name
                                color: root.accent
                                font.pixelSize: 16; font.weight: Font.DemiBold
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.body
                                color: root.dim
                                font.pixelSize: 13
                                lineHeight: 1.3
                            }
                        }
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                // Named because they are load-bearing, not as a list of
                // dependencies. Each of these is doing something SakuraOS
                // claims as its own on the previous screen.
                text: "And, among others: snapper for the restore points, "
                    + "mkinitcpio for the recovery environment, Flatpak, Snap and AppImage "
                    + "for the software, ODRS for the reviews, and cryptsetup for the "
                    + "encryption.\n\n"
                    + "Behind those are thousands more projects, and the people who "
                    + "maintain them mostly without being paid for it. SakuraOS is a "
                    + "small amount of new work resting on a very large amount of "
                    + "theirs."
                color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.85)
                font.pixelSize: 12
                lineHeight: 1.3
            }
            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "Wallpaper credits are in /usr/share/licenses/sakura-wallpapers."
                color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.7)
                font.pixelSize: 11
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                spacing: 14
                QQC2.Button {
                    text: "Back"
                    padding: 12; leftPadding: 26; rightPadding: 26
                    onClicked: root.step = -2
                    contentItem: QQC2.Label {
                        text: parent.text; color: root.text
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 9; color: parent.down ? root.cardUp : "transparent"
                        border.width: 1; border.color: root.line
                    }
                }
                QQC2.Button {
                    text: "Set it up"
                    padding: 13; leftPadding: 40; rightPadding: 40
                    onClicked: root.step = 0
                    contentItem: QQC2.Label {
                        text: parent.text
                        color: root.accentText
                        font.pixelSize: 15; font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 9
                        color: parent.down ? Qt.darker(root.accent, 1.15) : root.accent
                    }
                }
            }
        }
        }
    }

    // ---- what this distribution actually does differently -------------------
    // Between the welcome and the questions, because somebody who has just
    // booted an unfamiliar system has no idea what they are agreeing to set
    // up. Every claim here is one the machine can be held to; the ones that
    // are not yet true are not on this page.
    QQC2.ScrollView {
        anchors.fill: parent
        visible: root.step === -2
        contentWidth: availableWidth
        clip: true

        // Centred when it fits, scrolled when it does not. These pages had
        // the column centred in the window with nothing to scroll, so on a
        // screen shorter than the content -- 1024x768, where plenty of older
        // laptops live -- it overflowed equally top and bottom: the heading
        // above the edge and the buttons below it, unreachable, with no way
        // to get to them. The spacer keeps the centred look on a tall screen.
        Item {
            width: parent.width
            implicitHeight: Math.max(inner2.implicitHeight + 80,
                                     root.height)

        ColumnLayout {
            id: inner2
            anchors.centerIn: parent
            width: Math.min(880, parent.width - 100)
            spacing: 20

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                text: "What SakuraOS does differently"
                color: root.text
                font.pixelSize: 30
                font.weight: Font.Light
            }
            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "A UI-first, terminal-second distribution."
                color: root.dim
                font.pixelSize: 14
            }

            Item { Layout.preferredHeight: 6 }

            GridLayout {
                id: tourGrid
                Layout.fillWidth: true
                columns: width > 700 ? 2 : 1
                columnSpacing: 18
                rowSpacing: 18

                // Every card the height of the tallest.
                //
                // Sized to their own text they came out ragged -- six boxes of
                // six different heights, which reads as a broken layout rather
                // than as six things worth reading. The grid equalises them.

                Repeater {
                    model: [
                        {
                            title: "Built for modern machines, and older ones",
                            // About what this machine does, not about whose
                            // patches we build. The credits page is where
                            // upstream is thanked; a tour card that reads as
                            // an advertisement for somebody else tells the
                            // person nothing about their own computer.
                            body: "SakuraOS uses a kernel tuned by CachyOS, with our own "
                                + "tuning on top of it. Don't have a 2013 or newer processor? "
                                + "That is fine -- SakuraOS notices and falls back to the "
                                + "standard kernel for older machines. You are not asked, and "
                                + "there is nothing to undo."
                        },
                        {
                            title: "It can undo itself",
                            body: "The disk is BTRFS with automatic snapshots. A restore point is taken "
                                + "before every change, and you can take one yourself from the Update "
                                + "Center before doing something risky. If an update goes wrong, go "
                                + "back. Your documents and photos are never part of a restore point."
                        },
                        {
                            title: "Updates just happen",
                            body: "Checked and applied seamlessly in the background, overnight and on "
                                + "mains power, always behind a restore point. Applications keep "
                                + "themselves current too. Nothing waits for you to remember."
                        },
                        {
                            title: "Terminal Assist",
                            body: "Using a terminal for the first time is daunting, and one command can "
                                + "take a whole system with it. Terminal Assist recognises the commands "
                                + "that do real damage: partial upgrades, removing the last kernel, "
                                + "force-removing packages other things depend on. It stops them "
                                + "and tells you what to run instead."
                        },
                        {
                            title: "A store built from scratch",
                            body: "Flatpak, Snap, AppImage, the AUR and SakuraOS's own packages in one "
                                + "place, with the same app matched across them so you choose where it "
                                + "comes from. It keeps your applications updated, installs AppImages by "
                                + "opening the file, and can bring your software with you if you move to "
                                + "another SakuraOS machine."
                        },
                        {
                            title: "Private by default",
                            body: "Nothing here reports what you install, what you run, or who you are. "
                                + "The only telemetry on this system is KDE's own, it goes to KDE and "
                                + "never to us, and it is off unless you switch it on."
                        }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        // Equal heights come from the grid. Measuring its own
                        // content, feeding that to a shared tallest value and
                        // reading that back as its own height was a binding
                        // loop, reported on every launch; fillHeight in a
                        // GridLayout gives every cell in a row the height of
                        // the tallest without the circle.
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        implicitHeight: card.implicitHeight + 34
                        radius: 14
                        color: root.card
                        border.width: 1
                        border.color: root.line
                        ColumnLayout {
                            id: card
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top; anchors.margins: 17
                            spacing: 7
                            QQC2.Label {
                                text: modelData.title
                                color: root.accent
                                font.pixelSize: 16; font.weight: Font.DemiBold
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: modelData.body
                                color: root.dim
                                font.pixelSize: 13
                                lineHeight: 1.3
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 10 }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 14
                QQC2.Button {
                    text: "Back"
                    padding: 12; leftPadding: 26; rightPadding: 26
                    onClicked: root.step = -3
                    contentItem: QQC2.Label {
                        text: parent.text; color: root.text
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 9; color: parent.down ? root.cardUp : "transparent"
                        border.width: 1; border.color: root.line
                    }
                }
                QQC2.Button {
                    text: "Continue"
                    padding: 13; leftPadding: 40; rightPadding: 40
                    onClicked: root.step = -1
                    contentItem: QQC2.Label {
                        text: parent.text
                        color: root.accentText
                        font.pixelSize: 15; font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 9
                        color: parent.down ? Qt.darker(root.accent, 1.15) : root.accent
                    }
                }
            }
        }
        }
    }

    QQC2.ScrollView {
        anchors.fill: parent
        visible: root.step === -3
        contentWidth: availableWidth
        clip: true

        // Centred when it fits, scrolled when it does not. These pages had
        // the column centred in the window with nothing to scroll, so on a
        // screen shorter than the content -- 1024x768, where plenty of older
        // laptops live -- it overflowed equally top and bottom: the heading
        // above the edge and the buttons below it, unreachable, with no way
        // to get to them. The spacer keeps the centred look on a tall screen.
        Item {
            width: parent.width
            implicitHeight: Math.max(inner3.implicitHeight + 80,
                                     root.height)

        ColumnLayout {
            id: inner3
            anchors.centerIn: parent
            width: Math.min(560, parent.width - 100)
            spacing: 0

            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 150
                Layout.preferredHeight: 150
                source: "qrc:/assets/sakura-mark.svg"
                sourceSize: Qt.size(264, 264)
                fillMode: Image.PreserveAspectFit
            }

            Item { Layout.preferredHeight: 26 }

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                text: "Welcome to SakuraOS"
                color: root.text
                font.pixelSize: 34
                font.weight: Font.Light
            }

            Item { Layout.preferredHeight: 10 }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: versionLabel.implicitWidth + 22
                    Layout.preferredHeight: 26
                    radius: 13
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                    border.width: 1
                    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
                    QQC2.Label {
                        id: versionLabel
                        anchors.centerIn: parent
                        text: "1.0  ·  Cherry Blossom"
                        color: root.dark ? root.accent : "#a01449"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }

            Item { Layout.preferredHeight: 26 }

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                text: "A Linux distribution for the modern age."
                color: root.text
                font.pixelSize: 19
                font.weight: Font.Medium
            }

            Item { Layout.preferredHeight: 12 }

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "Welcome to SakuraOS. A privacy-first, Arch-based distribution built around ease of use, performance, and not having to open a terminal."
                color: root.dim
                font.pixelSize: 14
                lineHeight: 1.35
            }

            Item { Layout.preferredHeight: 34 }

            QQC2.Button {
                Layout.alignment: Qt.AlignHCenter
                text: "Get started"
                padding: 13
                leftPadding: 40
                rightPadding: 40
                onClicked: root.step = -2
                contentItem: QQC2.Label {
                    text: parent.text
                    color: root.accentText
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 9
                    color: parent.down ? Qt.darker(root.accent, 1.15) : root.accent
                }
            }
        }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        visible: root.step >= 0

        // Step rail
        Rectangle {
            Layout.preferredWidth: 248
            Layout.fillHeight: true
            color: panel

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 20

                RowLayout {
                    spacing: 10
                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: root.accent
                        QQC2.Label {
                            anchors.centerIn: parent
                            text: "✿"
                            color: root.accentText
                            font.pixelSize: 17
                        }
                    }
                    QQC2.Label {
                        text: "SakuraOS"
                        color: root.text
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: root.steps
                        delegate: RowLayout {
                            required property int index
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 11

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                width: 22; height: 22; radius: 11
                                color: index < root.step ? root.accent
                                     : index === root.step ? "transparent" : "transparent"
                                border.width: index === root.step ? 2 : 0
                                border.color: root.accent
                                QQC2.Label {
                                    anchors.centerIn: parent
                                    text: index < root.step ? "✓" : (index + 1)
                                    color: index < root.step ? root.accentText
                                         : index === root.step ? root.accent : root.dim
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                topPadding: 7; bottomPadding: 7
                                text: modelData.title
                                color: index === root.step ? root.text
                                     : index < root.step ? root.dim
                                     : Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.55)
                                font.pixelSize: 13
                                font.weight: index === root.step ? Font.DemiBold : Font.Normal
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }

        // Page area
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // A ScrollView takes its implicit height from its content, so
                // a tall page made the column ask for more room than the
                // window has and pushed Back and Continue off the bottom of
                // the screen -- on 1024x768, where a good number of older
                // laptops still live, and where the buttons being unreachable
                // means the install cannot be completed at all. Asking for
                // nothing and filling what is left is the whole fix.
                Layout.preferredHeight: 0
                Layout.minimumHeight: 0
                clip: true
                contentWidth: availableWidth

                // Back to the top on every page. Without this the scroll
                // position carries over, so stepping from a long page to a
                // short one opens it already scrolled down with its heading
                // above the fold -- which reads as a page that is cut off.
                id: pageScroll
                Connections {
                    target: root
                    function onStepChanged() {
                        if (pageScroll.contentItem)
                            pageScroll.contentItem.contentY = 0
                    }
                }

                Item {
                    width: parent.width
                    implicitHeight: pageLoader.implicitHeight

                Loader {
                    id: pageLoader
                    width: Math.min(root.contentWidth, parent.width - 80)
                    anchors.horizontalCenter: parent.horizontalCenter
                    sourceComponent: {
                        switch (root.step) {
                        // Language first: everything after this is easier to
                        // read once it is in a language you know.
                        case 0: return languagePage
                        case 1: return keyboardPage
                        // Network before anything that needs it. Most of an
                        // install is fetched from Arch's mirrors, so a machine
                        // that is not online cannot finish one -- and a laptop
                        // with only wifi could not get online at all until
                        // this step existed.
                        case 2: return networkPage
                        case 3: return timePage
                        case 4: return themePage
                        case 5: return diskPage
                        case 6: return encryptPage
                        case 7: return accountPage
                        case 8: return browserPage
                        case 9: return updatesPage
                        case 10: return featuresPage
                        case 11: return privacyPage
                        case 12: return summaryPage
                        default: return installPage
                        }
                    }
                }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.line
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 20
                spacing: 12

                QQC2.Button {
                    text: "Back"
                    // Every question screen, including the last one. The
                    // bound was left behind when language was added, so Back
                    // vanished on the final screen -- the one place somebody
                    // is most likely to want to check an earlier answer.
                    visible: root.step > 0 && root.step < 13
                    padding: 11
                    leftPadding: 20
                    rightPadding: 20
                    onClicked: root.step--
                    contentItem: QQC2.Label {
                        text: parent.text
                        color: root.dim
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    // Must be overridden as well: leaving the style's own
                    // background in place means the style also paints the
                    // label, and "Back" renders twice, slightly offset.
                    background: Rectangle {
                        radius: 8
                        color: parent.down ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                    }
                }
                Item { Layout.fillWidth: true }
                // The end of the job. The install page had no action at all
                // when it finished -- it said "SakuraOS is installed" and left
                // the person sitting in front of a window with nothing to
                // press, which is a strange way to end an installation.
                QQC2.Button {
                    id: rebootButton
                    text: "Restart now"
                    visible: root.step >= 13 && !backend.running
                             && backend.percent === 100
                             && backend.currentStep !== "Failed"
                    padding: 11
                    leftPadding: 26
                    rightPadding: 26
                    onClicked: backend.reboot()
                    contentItem: QQC2.Label {
                        text: parent.text
                        color: root.accentText
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        radius: 8
                        color: parent.down ? Qt.darker(root.accent, 1.15) : root.accent
                    }
                }
                QQC2.Button {
                    // Ten screens now that language leads: 0..9, with the
                    // install itself at 10.
                    text: root.step === 12 ? "Install SakuraOS" : "Continue"
                    visible: root.step < 13
                    enabled: root.canContinue()
                    padding: 11
                    leftPadding: 26
                    rightPadding: 26
                    onClicked: root.step++
                    contentItem: QQC2.Label {
                        text: parent.text
                        color: parent.enabled ? root.accentText : root.dim
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                    }
                    background: Rectangle {
                        radius: 8
                        color: !parent.enabled ? root.card
                             : parent.down ? Qt.darker(root.accent, 1.15) : root.accent
                    }
                }
            }
        }
    }

    // ---- pages -------------------------------------------------------------
    Component {
        id: languagePage
        ColumnLayout {
            spacing: 18
            Item { Layout.preferredHeight: 34 }
            // A turning earth with blossom drifting past it, centred above
            // the heading. It sat off to the right of the title before, where
            // it read as an ornament somebody had left there; this is the
            // first screen anyone sees, and it can carry a hero.
            Canvas {
                id: globe
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 132
                Layout.preferredHeight: 132

                property real spin: 0
                // Slow. A globe that whips round is a loading spinner, and
                // this is not telling anyone to wait for anything.
                NumberAnimation on spin {
                    from: 0; to: 360
                    duration: 42000
                    loops: Animation.Infinite
                    running: globe.visible
                }
                onSpinChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var cx = width / 2, cy = height / 2
                    var r = Math.min(cx, cy) - 16

                    // A globe, not a rendering of the Earth. Procedural
                    // continents at this size read as blemishes rather than
                    // as coastlines -- tried, and no amount of tuning fixed
                    // it. A clean sphere with a few turning meridians says
                    // "somewhere in the world" immediately, which is all this
                    // has to say. The blossom carries the character.
                    var sphere = ctx.createRadialGradient(
                        cx - r * 0.4, cy - r * 0.4, r * 0.05, cx, cy, r)
                    sphere.addColorStop(0, "#6b3c50")
                    sphere.addColorStop(1, "#2a1721")
                    ctx.fillStyle = sphere
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, Math.PI * 2)
                    ctx.fill()

                    ctx.save()
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, Math.PI * 2)
                    ctx.clip()

                    ctx.strokeStyle = Qt.rgba(root.accent.r, root.accent.g,
                                              root.accent.b, 0.22)
                    ctx.lineWidth = 1

                    // Two parallels. They do not move: a line of latitude is
                    // the same circle however far the globe has turned.
                    for (var lat = -35; lat <= 35; lat += 35) {
                        if (lat === 0) {
                            continue
                        }
                        var rad = lat * Math.PI / 180
                        var y = cy - r * Math.sin(rad)
                        var rx = r * Math.cos(rad)
                        ctx.beginPath()
                        ctx.ellipse(cx - rx, y - rx * 0.18, rx * 2, rx * 0.36)
                        ctx.stroke()
                    }
                    // The equator, heavier, so the sphere has an axis.
                    ctx.strokeStyle = Qt.rgba(root.accent.r, root.accent.g,
                                              root.accent.b, 0.34)
                    ctx.beginPath()
                    ctx.ellipse(cx - r, cy - r * 0.2, r * 2, r * 0.4)
                    ctx.stroke()

                    // Three meridians, turning. Each is a circle seen at an
                    // angle, so its width is the cosine of how far round it
                    // has gone, and it fades as it approaches edge-on --
                    // which is the whole reason the sphere looks like it is
                    // rotating rather than sitting still.
                    for (var m = 0; m < 3; ++m) {
                        var a = (m * 60 + globe.spin) * Math.PI / 180
                        var w = Math.cos(a)
                        ctx.globalAlpha = 0.10 + 0.30 * Math.abs(w)
                        ctx.strokeStyle = root.accent
                        ctx.beginPath()
                        ctx.ellipse(cx - Math.abs(w) * r, cy - r,
                                    Math.abs(w) * r * 2, r * 2)
                        ctx.stroke()
                    }
                    ctx.globalAlpha = 1
                    ctx.restore()

                    // The rim.
                    ctx.strokeStyle = Qt.rgba(root.accent.r, root.accent.g,
                                              root.accent.b, 0.45)
                    ctx.lineWidth = 1.5
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, Math.PI * 2)
                    ctx.stroke()

                    // One blossom over the lower right, still. Petals
                    // orbiting looked like dust on the screen.
                    globe.blossom(ctx, cx + r * 0.74, cy + r * 0.72, 19)
                }

                // A cherry blossom, which is a specific shape rather than a
                // five-petalled flower.
                //
                // What makes it read as sakura: each petal is narrow where it
                // joins the centre and widest near the tip, and the tip is
                // split by a deep cleft into two rounded lobes. Without that
                // cleft it is a plum blossom; with a rounded tip it is
                // nothing in particular. The cleft is cut into the outline
                // rather than painted over afterwards, so it works over the
                // sphere, over the background, and over anything else this
                // ends up sitting on.
                function petalPath(ctx, h) {
                    var w = h * 0.46
                    ctx.beginPath()
                    ctx.moveTo(0, 0)
                    // Left edge: narrow at the base, swelling towards the tip.
                    ctx.bezierCurveTo(-w * 0.55, -h * 0.22,
                                      -w * 1.05, -h * 0.58,
                                      -w * 0.80, -h * 0.90)
                    // Left lobe, rounded over the top.
                    ctx.quadraticCurveTo(-w * 0.62, -h * 1.04,
                                         -w * 0.30, -h * 0.94)
                    // Into the cleft, and back out the other side.
                    ctx.lineTo(0, -h * 0.70)
                    ctx.lineTo(w * 0.30, -h * 0.94)
                    ctx.quadraticCurveTo(w * 0.62, -h * 1.04,
                                         w * 0.80, -h * 0.90)
                    ctx.bezierCurveTo(w * 1.05, -h * 0.58,
                                      w * 0.55, -h * 0.22,
                                      0, 0)
                    ctx.closePath()
                }

                function blossom(ctx, x, y, size) {
                    ctx.save()
                    ctx.translate(x, y)
                    ctx.rotate(-0.25)

                    for (var i = 0; i < 5; ++i) {
                        ctx.save()
                        // A little under a fifth of a turn each, so the
                        // petals sit apart rather than merging into a disc.
                        ctx.rotate(i * 2 * Math.PI / 5)
                        var g = ctx.createLinearGradient(0, 0, 0, -size)
                        g.addColorStop(0, "#f8c2d2")
                        g.addColorStop(0.55, "#ffd9e4")
                        g.addColorStop(1, "#fff2f6")
                        ctx.fillStyle = g
                        globe.petalPath(ctx, size)
                        ctx.fill()
                        // A hairline edge, which is what separates one petal
                        // from the one behind it at this size.
                        ctx.strokeStyle = Qt.rgba(0.86, 0.55, 0.65, 0.55)
                        ctx.lineWidth = 0.7
                        ctx.stroke()
                        ctx.restore()
                    }

                    // Stamens. A cherry blossom has a lot of them and they
                    // are long; a plain dot in the middle is what makes a
                    // drawn flower look like a clip-art daisy.
                    ctx.strokeStyle = Qt.rgba(0.85, 0.45, 0.55, 0.75)
                    ctx.lineWidth = 0.8
                    for (var t = 0; t < 9; ++t) {
                        var a = t * 2 * Math.PI / 9 + 0.2
                        var len = size * (0.34 + (t % 3) * 0.07)
                        ctx.beginPath()
                        ctx.moveTo(0, 0)
                        ctx.lineTo(Math.cos(a) * len, Math.sin(a) * len)
                        ctx.stroke()
                        ctx.fillStyle = "#ffe9a8"
                        ctx.beginPath()
                        ctx.arc(Math.cos(a) * len, Math.sin(a) * len,
                                size * 0.055, 0, Math.PI * 2)
                        ctx.fill()
                    }
                    ctx.restore()
                }
            }

            Heading {
                Layout.fillWidth: true
                centred: true
                title: "Language"
                subtitle: "This sets the language of the desktop and how dates, numbers and currency are written."
            }

            Field {
                id: langFilter
                placeholderText: "Search languages…"
                Layout.maximumWidth: 460
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 300
                radius: 12
                color: root.card
                border.width: 1; border.color: root.line

                QQC2.ScrollView {
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    ListView {
                        id: langList
                        // Searchable in the language itself and in English, so
                        // it works whether you are finding your own language
                        // or being talked through it by somebody else.
                        model: backend.languages().filter(function (l) {
                            var q = langFilter.text.toLowerCase()
                            return q === ""
                                || l.native.toLowerCase().indexOf(q) !== -1
                                || l.english.toLowerCase().indexOf(q) !== -1
                                || l.code.toLowerCase().indexOf(q) !== -1
                        })
                        delegate: Rectangle {
                            required property var modelData
                            width: langList.width
                            height: 44
                            radius: 8
                            color: root.answers.locale === modelData.code
                                   ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                                   : (langHover.hovered ? root.cardUp : "transparent")
                            HoverHandler { id: langHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    root.answers.locale = modelData.code
                                    root.answersChanged()
                                }
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14; anchors.rightMargin: 14
                                spacing: 10
                                ColumnLayout {
                                    spacing: 0
                                    QQC2.Label {
                                        text: modelData.native
                                        color: root.text; font.pixelSize: 14
                                    }
                                    QQC2.Label {
                                        text: modelData.english
                                        color: root.dim; font.pixelSize: 11
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                QQC2.Label {
                                    visible: root.answers.locale === modelData.code
                                    text: "\u2713"
                                    color: root.accent; font.pixelSize: 15
                                }
                            }
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: keyboardPage
        ColumnLayout {
            spacing: 18
            Item { Layout.preferredHeight: 34 }
            Heading {
                title: "Keyboard layout"
                subtitle: "Type in the box below to check it before continuing. Getting this wrong locks you out at your first login prompt."
            }
            QQC2.ComboBox {
                id: kb
                Layout.fillWidth: true
                model: backend.keyboardLayouts()
                textRole: "name"
                valueRole: "code"
                Component.onCompleted: currentIndex = indexOfValue(root.answers.keyboard)
                onActivated: { root.answers.keyboard = currentValue; root.answersChanged() }
            }
            // The layout, drawn as a keyboard rather than as four rows of
            // squares. Reading "German (no dead keys)" tells you very little;
            // seeing where Z and Y sit tells you immediately whether this is
            // the board in front of you -- but only if it looks enough like
            // one to compare against.
            //
            // The character keys come from xkbcommon. The modifiers are drawn
            // in because they are the same everywhere and their widths are
            // most of what makes a keyboard recognisable: the stepped left
            // edge, the long Enter, the space bar.
            ColumnLayout {
                id: kbPreview
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 4
                property var rows: backend.keyboardPreview(root.answers.keyboard)
                // One key-width. Everything else is a multiple of it, which is
                // how a real board is specified.
                //
                // Taken from the page width, not from this item's own width:
                // the caps size from the unit and the container sizes from
                // the caps, so deriving it from `width` is a loop, and the
                // loop resolves to zero -- every key collapsed on top of the
                // next.
                readonly property real unit:
                    Math.max(16, (root.contentWidth - 14 * spacing) / 15)

                Connections {
                    target: root
                    function onAnswersChanged() {
                        kbPreview.rows = backend.keyboardPreview(root.answers.keyboard)
                    }
                }

                component Cap : Rectangle {
                    property string label: ""
                    property real units: 1
                    property bool modifier: false
                    Layout.preferredWidth: kbPreview.unit * units
                    Layout.preferredHeight: 34
                    radius: 5
                    color: modifier ? Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.13)
                                    : root.card
                    border.width: 1
                    border.color: root.line
                    QQC2.Label {
                        anchors.centerIn: parent
                        text: label
                        color: modifier ? root.dim : root.text
                        font.pixelSize: label.length > 2 ? 9 : 13
                    }
                }

                // Characters for one xkb row, as caps. Takes a list rather
                // than a row index so the caller can move a key: xkb puts the
                // backslash keycode at the end of the home row, where an
                // ANSI board has it above Enter instead.
                component CharRow : Repeater {
                    property var keys: []
                    model: keys
                    delegate: Cap {
                        required property var modelData
                        label: modelData || ""
                    }
                }

                readonly property var rowNumber: rows.length > 0 ? rows[0] : []
                // Top row plus the key xkb files under the home row.
                readonly property var rowTop:
                    rows.length > 2 ? rows[1].concat(rows[2].slice(-1))
                                    : (rows.length > 1 ? rows[1] : [])
                readonly property var rowHome:
                    rows.length > 2 ? rows[2].slice(0, -1) : []
                readonly property var rowBottom: rows.length > 3 ? rows[3] : []

                RowLayout {
                    Layout.fillWidth: true
                    spacing: kbPreview.spacing
                    CharRow { keys: kbPreview.rowNumber }
                    Cap { label: "Backspace"; units: 2; modifier: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: kbPreview.spacing
                    Cap { label: "Tab"; units: 1.5; modifier: true }
                    CharRow { keys: kbPreview.rowTop }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: kbPreview.spacing
                    Cap { label: "Caps"; units: 1.75; modifier: true }
                    CharRow { keys: kbPreview.rowHome }
                    Cap { label: "Enter"; units: 2.25; modifier: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: kbPreview.spacing
                    Cap { label: "Shift"; units: 2.25; modifier: true }
                    CharRow { keys: kbPreview.rowBottom }
                    Cap { label: "Shift"; units: 2.75; modifier: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: kbPreview.spacing
                    Cap { label: "Ctrl"; units: 1.25; modifier: true }
                    Cap { label: "Meta"; units: 1.25; modifier: true }
                    Cap { label: "Alt";  units: 1.25; modifier: true }
                    Cap { label: "";     units: 6.25; modifier: true }
                    Cap { label: "Alt";  units: 1.25; modifier: true }
                    Cap { label: "Meta"; units: 1.25; modifier: true }
                    Cap { label: "Ctrl"; units: 1.25; modifier: true }
                }

                QQC2.Label {
                    visible: kbPreview.rows.length === 0
                    text: "This layout could not be drawn, but it will still be used."
                    color: root.dim; font.pixelSize: 12
                }
            }

            // Directly under the keyboard and the same width as it. It was
            // half the width and hanging off to the left, which made it read
            // as belonging to something else rather than as the place to test
            // the layout drawn immediately above it.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 6
                QQC2.Label {
                    text: "Try it here"
                    color: root.dim; font.pixelSize: 12
                }
                Field {
                    Layout.fillWidth: true
                    placeholderText: "Type a few keys to check they come out right…"
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: networkPage
        ColumnLayout {
            id: netCol
            spacing: 16

            property var state: ({})
            property var networks: []
            property string busy: ""
            property string error: ""
            property bool manual: false
            property string joining: ""

            function refresh() {
                state = backend.networkState()
                if (backend.hasWifiHardware()) {
                    networks = backend.wifiNetworks()
                }
            }

            Component.onCompleted: refresh()

            // Something has to keep this honest while the page is open: a
            // cable pulled out, or a lease arriving a few seconds after the
            // page was drawn, should show without anybody pressing anything.
            Timer {
                interval: 4000; running: true; repeat: true
                onTriggered: if (netCol.busy === "") netCol.refresh()
            }

            Item { Layout.preferredHeight: 34 }
            Heading {
                title: "Network"
                subtitle: "SakuraOS installs from the disc, so this can wait. Connect now and the machine arrives up to date, with your graphics driver already on it."
            }

            // ---- where things stand ---------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                radius: 12
                color: root.card
                border.width: 1
                border.color: netCol.state.connected ? root.accent : root.line

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: netCol.state.connected ? "#8fd694" : root.warn
                    }
                    ColumnLayout {
                        spacing: 1
                        QQC2.Label {
                            text: netCol.state.connected
                                  ? (netCol.state.type === "wifi"
                                     ? "Connected to " + (netCol.state.name || "wifi")
                                     : "Connected by cable")
                                  : "Not connected"
                            color: root.text; font.pixelSize: 14; font.weight: Font.DemiBold
                        }
                        QQC2.Label {
                            text: netCol.state.connected
                                  ? (netCol.state.address || "waiting for an address")
                                    + "  ·  " + (netCol.state.device || "")
                                  : "Choose a network below, or plug in a cable."
                            color: root.dim; font.pixelSize: 12
                        }
                    }
                    Item { Layout.fillWidth: true }
                    QQC2.Button {
                        text: "Refresh"
                        visible: backend.hasWifiHardware()
                        onClicked: { backend.rescanWifi(); netCol.refresh() }
                    }
                }
            }

            // ---- wifi ------------------------------------------------------
            QQC2.Label {
                text: "Wireless networks"
                color: root.dim; font.pixelSize: 13
                visible: backend.hasWifiHardware()
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: !backend.hasWifiHardware()
                text: "This machine has no wireless hardware, so it needs a cable."
                color: root.dim; font.pixelSize: 12
            }

            QQC2.ScrollView {
                id: wifiScroll
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(200, netCol.networks.length * 46 + 4)
                visible: backend.hasWifiHardware() && netCol.networks.length > 0
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    // Named, not walked to. parent.parent from inside a
                    // ScrollView is the Flickable's content item rather than
                    // the ScrollView, so availableWidth came back undefined,
                    // the column had no width, and every fillWidth item in the
                    // row collapsed to nothing -- which is why the tick sat on
                    // top of the network's name instead of beside it.
                    width: wifiScroll.availableWidth
                    spacing: 2
                    Repeater {
                        model: netCol.networks
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: 8
                            color: netCol.joining === modelData.ssid ? root.cardUp
                                 : modelData.active ? Qt.rgba(1,1,1,0.05) : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10
                                QQC2.Label {
                                    // Fixed width, so the row keeps its
                                    // columns whether or not there is a glyph
                                    // to put here.
                                    Layout.preferredWidth: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    // A padlock is U+1F512, which is outside
                                    // the BMP: "\u1F512" is not that
                                    // character, it is \u1F51 followed by a
                                    // literal 2, because \u takes exactly
                                    // four digits. That rendered as a stray
                                    // box that ate the gap and sat on top of
                                    // the network name. U+00B7 is a dot, is
                                    // in the BMP, and cannot do this.
                                    text: modelData.active ? "\u2713"
                                        : modelData.secure ? "\u00B7" : ""
                                    color: modelData.active ? root.accent : root.dim
                                    font.pixelSize: 13
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: modelData.ssid
                                    elide: Text.ElideRight
                                    color: root.text; font.pixelSize: 13
                                }
                                QQC2.Label {
                                    // Bars rather than a percentage: nobody
                                    // acts differently on 62 than on 58.
                                    text: modelData.signal >= 70 ? "\u2022\u2022\u2022"
                                        : modelData.signal >= 40 ? "\u2022\u2022"
                                        : "\u2022"
                                    color: root.dim; font.pixelSize: 13
                                }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    netCol.error = ""
                                    netCol.joining = netCol.joining === modelData.ssid
                                                     ? "" : modelData.ssid
                                }
                            }
                        }
                    }
                }
            }

            // ---- joining one ----------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                visible: netCol.joining !== ""
                spacing: 10
                Field {
                    id: wifiPass
                    Layout.fillWidth: true
                    placeholderText: "Password for " + netCol.joining
                    echoMode: TextInput.Password
                    onAccepted: joinButton.clicked()
                }
                QQC2.Button {
                    id: joinButton
                    text: netCol.busy !== "" ? "Connecting…" : "Connect"
                    enabled: netCol.busy === ""
                    onClicked: {
                        netCol.busy = netCol.joining
                        netCol.error = ""
                        var err = backend.connectWifi(netCol.joining, wifiPass.text)
                        netCol.busy = ""
                        netCol.error = err
                        if (err === "") {
                            netCol.joining = ""
                            wifiPass.text = ""
                        }
                        netCol.refresh()
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: netCol.error !== ""
                wrapMode: Text.WordWrap
                text: netCol.error
                color: "#ff9db0"; font.pixelSize: 12
            }

            // ---- addresses by hand -----------------------------------------
            QQC2.Button {
                text: netCol.manual ? "Use an automatic address"
                                    : "Set the address myself"
                flat: true
                onClicked: {
                    netCol.manual = !netCol.manual
                    if (!netCol.manual && netCol.state.device) {
                        netCol.error = backend.useAutomaticAddress(netCol.state.device)
                        netCol.refresh()
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: netCol.manual
                spacing: 8
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "For a network with no DHCP. The address needs its prefix "
                        + "length, as in 192.168.1.50/24."
                    color: root.dim; font.pixelSize: 12
                }
                Field { id: ipAddr; Layout.fillWidth: true; placeholderText: "Address, e.g. 192.168.1.50/24" }
                Field { id: ipGw;   Layout.fillWidth: true; placeholderText: "Gateway, e.g. 192.168.1.1" }
                Field { id: ipDns;  Layout.fillWidth: true; placeholderText: "DNS, e.g. 1.1.1.1 (optional)" }
                QQC2.Button {
                    text: "Apply"
                    enabled: ipAddr.text.trim() !== "" && !!netCol.state.device
                    onClicked: {
                        netCol.error = backend.applyStaticAddress(
                            netCol.state.device, ipAddr.text.trim(),
                            ipGw.text.trim(), ipDns.text.trim())
                        netCol.refresh()
                    }
                }
            }

            // Said plainly rather than by disabling Continue with no reason
            // given. Somebody installing onto a machine that will be online
            // later is allowed to carry on and find out; somebody who simply
            // has not noticed needs telling.
            QQC2.Label {
                Layout.fillWidth: true
                visible: !netCol.state.connected
                wrapMode: Text.WordWrap
                text: "You can continue without a connection, but the install will "
                    + "stop when it tries to fetch packages."
                color: root.warn; font.pixelSize: 12
            }

            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: timePage
        ColumnLayout {
            spacing: 18
            Item { Layout.preferredHeight: 34 }
            Heading { title: "Time"; subtitle: "Used for your clock, and for checking that updates are signed correctly." }
            QQC2.Label { text: "Time zone"; color: root.dim; font.pixelSize: 13 }
            Field {
                id: tzFilter
                Layout.fillWidth: true
                placeholderText: "Search for a city…"
                Component.onCompleted: {
                    var guess = backend.guessTimezone()
                    root.answers.timezone = guess === "" ? "UTC" : guess
                    // Same rule as picking one by hand: the detected zone
                    // decides the clock until the user overrides it.
                    if (!root.hour24Touched)
                        root.answers.hour24 = !root.zoneUsesTwelveHour(root.answers.timezone)
                    root.answersChanged()
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                radius: 12
                color: root.card
                border.width: 1; border.color: root.line
                QQC2.ScrollView {
                    anchors.fill: parent
                    anchors.margins: 7
                    clip: true
                    ListView {
                        id: tzList
                        // Matches the city, the region or the identifier, so
                        // "new york", "america" and "New_York" all find it.
                        model: backend.timezoneChoices().filter(function (z) {
                            var q = tzFilter.text.toLowerCase().trim()
                            return q === "" || z.search.indexOf(q) !== -1
                        })
                        delegate: Rectangle {
                            required property var modelData
                            width: tzList.width
                            height: 36
                            radius: 7
                            color: root.answers.timezone === modelData.id
                                   ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                                   : (tzHover.hovered ? root.cardUp : "transparent")
                            HoverHandler { id: tzHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    root.answers.timezone = modelData.id
                                    // Follow the region until somebody says
                                    // otherwise. Picking Chicago and then
                                    // being shown 14:30 is a small thing that
                                    // reads as the installer not listening.
                                    if (!root.hour24Touched)
                                        root.answers.hour24 = !root.zoneUsesTwelveHour(modelData.id)
                                    root.answersChanged()
                                }
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12; anchors.rightMargin: 12
                                spacing: 8
                                QQC2.Label {
                                    text: modelData.city
                                    color: root.text; font.pixelSize: 13
                                }
                                QQC2.Label {
                                    text: modelData.region
                                    color: root.dim; font.pixelSize: 11
                                }
                                Item { Layout.fillWidth: true }
                                QQC2.Label {
                                    visible: root.answers.timezone === modelData.id
                                    text: "\u2713"
                                    color: root.accent; font.pixelSize: 13
                                }
                            }
                        }
                    }
                }
            }
            // What time it is in the zone that is selected. This is the one
            // thing on this screen a person can check against the watch on
            // their wrist, which makes it worth more than the zone's name.
            Item {
                id: clock
                Layout.fillWidth: true
                Layout.preferredHeight: 158
                Layout.topMargin: 6

                // Epoch milliseconds, shifted into the chosen zone. Reading
                // the UTC parts of that then gives that zone's wall clock,
                // without needing a timezone database in QML.
                property real shifted: 0
                readonly property int hours:   new Date(shifted).getUTCHours()
                readonly property int minutes: new Date(shifted).getUTCMinutes()
                readonly property int seconds: new Date(shifted).getUTCSeconds()

                function retime() {
                    shifted = Date.now() + backend.utcOffset(root.answers.timezone) * 1000
                    face.requestPaint()
                }
                Component.onCompleted: retime()
                Timer {
                    interval: 1000; running: true; repeat: true
                    onTriggered: clock.retime()
                }
                Connections {
                    target: root
                    function onAnswersChanged() { clock.retime() }
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 26

                    Canvas {
                        id: face
                        Layout.preferredWidth: 136
                        Layout.preferredHeight: 136
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            var cx = width / 2, cy = height / 2
                            var r = Math.min(cx, cy) - 3

                            ctx.strokeStyle = root.line
                            ctx.lineWidth = 2
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, 0, Math.PI * 2)
                            ctx.stroke()

                            // Twelve marks, the quarters longer. Numbers at
                            // this size would be unreadable.
                            for (var i = 0; i < 12; i++) {
                                var a = i * Math.PI / 6
                                var inner = r - (i % 3 === 0 ? 12 : 6)
                                ctx.strokeStyle = i % 3 === 0 ? root.text : root.dim
                                ctx.lineWidth = i % 3 === 0 ? 2 : 1
                                ctx.beginPath()
                                ctx.moveTo(cx + Math.sin(a) * inner, cy - Math.cos(a) * inner)
                                ctx.lineTo(cx + Math.sin(a) * (r - 2), cy - Math.cos(a) * (r - 2))
                                ctx.stroke()
                            }

                            function hand(angle, length, width, colour) {
                                ctx.strokeStyle = colour
                                ctx.lineWidth = width
                                ctx.lineCap = "round"
                                ctx.beginPath()
                                ctx.moveTo(cx, cy)
                                ctx.lineTo(cx + Math.sin(angle) * length,
                                           cy - Math.cos(angle) * length)
                                ctx.stroke()
                            }
                            // The hour hand moves with the minutes, as a real
                            // one does; a clock that jumps on the hour looks
                            // broken.
                            var m = clock.minutes + clock.seconds / 60
                            var h = (clock.hours % 12) + m / 60
                            hand(h * Math.PI / 6, r * 0.52, 4, root.text)
                            hand(m * Math.PI / 30, r * 0.74, 3, root.text)
                            hand(clock.seconds * Math.PI / 30, r * 0.80, 1.5, root.accent)

                            ctx.fillStyle = root.accent
                            ctx.beginPath()
                            ctx.arc(cx, cy, 3.5, 0, Math.PI * 2)
                            ctx.fill()
                        }
                    }

                    ColumnLayout {
                        spacing: 4
                        QQC2.Label {
                            text: {
                                var h = clock.hours
                                var suffix = ""
                                if (!root.answers.hour24) {
                                    suffix = h < 12 ? " AM" : " PM"
                                    h = h % 12
                                    if (h === 0) h = 12
                                }
                                var mm = clock.minutes < 10 ? "0" + clock.minutes
                                                            : "" + clock.minutes
                                return (root.answers.hour24 && h < 10 ? "0" + h : h)
                                     + ":" + mm + suffix
                            }
                            color: root.text
                            font.pixelSize: 38; font.weight: Font.Light
                        }
                        QQC2.Label {
                            text: root.answers.timezone
                            color: root.dim; font.pixelSize: 13
                        }
                        QQC2.Label {
                            // Says plainly what to do if it is wrong, rather
                            // than leaving the reader to infer it.
                            text: "If this is not the time where you are, choose a different zone."
                            color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.75)
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.maximumWidth: 260
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            QQC2.Label { text: "Clock"; color: root.dim; font.pixelSize: 13; topPadding: 10 }
            // Side by side rather than stacked: they are two readings of the
            // same moment, so seeing both at once is the comparison being
            // asked for -- and stacked, the second one fell below the fold.
            RowLayout {
            spacing: 14
            Choice {
                // The real time, not an example. A made-up time next to a
                // clock showing a different one reads as a mistake.
                heading: "24-hour"
                detail: (clock.hours < 10 ? "0" : "") + clock.hours + ":"
                      + (clock.minutes < 10 ? "0" : "") + clock.minutes
                selected: root.answers.hour24
                onPicked: { root.answers.hour24 = true; root.hour24Touched = true; root.answersChanged() }
            }
            Choice {
                heading: "12-hour"
                detail: ((clock.hours % 12) === 0 ? 12 : clock.hours % 12) + ":"
                      + (clock.minutes < 10 ? "0" : "") + clock.minutes
                      + (clock.hours < 12 ? " AM" : " PM")
                selected: !root.answers.hour24
                onPicked: { root.answers.hour24 = false; root.hour24Touched = true; root.answersChanged() }
            }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: themePage
        ColumnLayout {
            spacing: 18
            Item { Layout.preferredHeight: 34 }
            Heading { title: "Appearance"; subtitle: "You can change this at any time in System Settings." }
            RowLayout {
                spacing: 18
                Repeater {
                    model: [
                        { dark: true,  name: "Dark",  wall: "/usr/share/wallpapers/Sakura/contents/images_dark/1920x1080.jpg" },
                        { dark: false, name: "Light", wall: "/usr/share/wallpapers/Sakura/contents/images/1920x1080.jpg" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: 260; height: 190
                        radius: 12
                        color: root.card
                        border.width: root.answers.dark === modelData.dark ? 3 : 1
                        border.color: root.answers.dark === modelData.dark ? root.accent : Qt.rgba(1,1,1,0.08)
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            Image {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 128
                                source: "file://" + modelData.wall
                                fillMode: Image.PreserveAspectCrop
                                clip: true
                            }
                            QQC2.Label {
                                text: modelData.name
                                color: root.text
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.answers.dark = modelData.dark; root.answersChanged() }
                        }
                    }
                }
            }
            QQC2.Label {
                text: "The wallpaper follows: the same street in Tokyo, by day or by night."
                color: root.dim
                font.pixelSize: 13
            }

            QQC2.Label {
                text: "Accent colour"
                color: root.dim; font.pixelSize: 13
                topPadding: 10
            }
            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: 560
                wrapMode: Text.WordWrap
                text: "Used for highlights, folders and the shape of the cursor's "
                    + "attention. It can be changed later in System Settings."
                color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.85)
                font.pixelSize: 12
            }

            Flow {
                Layout.fillWidth: true
                spacing: 12
                Repeater {
                    // The first is the default and says so. The rest are
                    // spaced around the wheel rather than being six shades of
                    // the same idea, and each is mid-toned so a white glyph
                    // on a folder stays readable -- the same constraint the
                    // folder icons are recoloured under.
                    model: [
                        { hex: "#ffb7c5", name: "Cherry blossom" },
                        { hex: "#e8799a", name: "Rose" },
                        { hex: "#c58bd6", name: "Lilac" },
                        { hex: "#7aa2f7", name: "Cornflower" },
                        { hex: "#5fbf9f", name: "Jade" },
                        { hex: "#e0a458", name: "Amber" },
                        { hex: "#d96f6f", name: "Clay" },
                        { hex: "#9aa5b1", name: "Slate" }
                    ]
                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        spacing: 5
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 46; height: 46; radius: 23
                            color: modelData.hex
                            border.width: root.answers.accent === modelData.hex ? 3 : 0
                            border.color: root.text
                            QQC2.Label {
                                anchors.centerIn: parent
                                visible: root.answers.accent === modelData.hex
                                text: "\u2713"
                                color: "#3a2731"
                                font.pixelSize: 20; font.weight: Font.DemiBold
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    root.answers.accent = modelData.hex
                                    root.answersChanged()
                                }
                            }
                        }
                        QQC2.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: index === 0 ? "Default" : modelData.name
                            color: root.answers.accent === modelData.hex ? root.text : root.dim
                            font.pixelSize: 11
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: diskPage
        ColumnLayout {
            spacing: 16
            Item { Layout.preferredHeight: 34 }
            Heading {
                title: "Where should SakuraOS go?"
                subtitle: "Choose a disk, then choose whether to keep what is already on it."
            }
            Repeater {
                model: backend.disks()
                delegate: Choice {
                    required property var modelData
                    heading: (modelData.model !== "" ? modelData.model : "Disk") + "  ·  " + modelData.sizeText
                    detail: modelData.device + (modelData.removable ? "  ·  removable" : "")
                    selected: root.answers.disk === modelData.device
                    onPicked: {
                        root.answers.disk = modelData.device
                        // A disk with nothing on it has nothing to install
                        // beside, so the safe answer becomes the obvious one
                        // only where it is actually a choice.
                        var l = backend.diskLayout(modelData.device)
                        root.answers.diskMode =
                            (l.hasEsp && l.freeMiB >= 25600) ? "alongside" : "wipe"
                        root.answersChanged()
                    }
                }
            }

            // What is on the chosen disk, and therefore what the two options
            // actually mean here. Shown only once a disk is picked, because
            // before that it would be describing nothing.
            ColumnLayout {
                visible: root.answers.disk !== ""
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12
                property var layout: root.answers.disk === ""
                                     ? null : backend.diskLayout(root.answers.disk)

                Choice {
                    readonly property var l: parent.layout
                    enabled: !!(l && l.hasEsp && l.freeMiB >= 25600)
                    opacity: enabled ? 1 : 0.45
                    heading: "Install alongside what is here"
                    detail: {
                        var l2 = parent.layout
                        if (!l2) return ""
                        if (!l2.hasEsp)
                            return "Not possible: nothing on this disk boots in UEFI mode"
                        if (l2.freeMiB < 25600)
                            return "Not possible: only " + Math.round(l2.freeMiB / 1024)
                                 + " GB unallocated, and 25 GB is needed"
                        return "Uses " + Math.round(l2.freeMiB / 1024)
                             + " GB of unallocated space"
                             + (l2.systems.length > 0
                                ? ", keeping " + l2.systems.join(" and ") : "")
                    }
                    selected: root.answers.diskMode === "alongside"
                    onPicked: {
                        if (!enabled) return
                        root.answers.diskMode = "alongside"
                        root.answersChanged()
                    }
                }
                Choice {
                    heading: "Erase the whole disk"
                    detail: {
                        var l3 = parent.layout
                        return l3 && l3.systems.length > 0
                            ? "Removes " + l3.systems.join(" and ") + " and everything else"
                            : "Everything on this disk is replaced"
                    }
                    selected: root.answers.diskMode === "wipe"
                    onPicked: { root.answers.diskMode = "wipe"; root.answersChanged() }
                }

                // Said here rather than discovered afterwards. Shrinking a
                // Windows partition is the one step SakuraOS deliberately
                // does not do: Windows can move its own unmovable files and
                // we cannot, and getting it wrong costs somebody data that no
                // restore point of ours can bring back.
                QQC2.Label {
                    visible: !!(parent.layout && parent.layout.freeMiB < 25600
                                && parent.layout.systems.length > 0)
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "To keep what is here, there has to be unallocated space for "
                        + "SakuraOS to go into. Shrink an existing partition first, from "
                        + "Windows' own Disk Management if this machine has Windows on it, "
                        + "then come back."
                    color: root.dim; font.pixelSize: 12
                    lineHeight: 1.3
                }
            }

            QQC2.Label {
                wrapMode: Text.WordWrap
                color: root.dim
                font.pixelSize: 13
                text: "SakuraOS will use BTRFS with automatic restore points, so a bad update can be undone from the boot menu."
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: encryptPage
        ColumnLayout {
            spacing: 18
            Item { Layout.preferredHeight: 34 }
            Heading {
                title: "Encryption"
                subtitle: "Without it, anyone who takes this machine can read everything on it by putting the disk in another computer."
            }
            Choice {
                heading: "Encrypt this disk"
                detail: "You enter a passphrase each time the machine starts"
                selected: root.answers.encrypt
                onPicked: { root.answers.encrypt = true; root.answersChanged() }
            }
            Choice {
                heading: "Leave it unencrypted"
                detail: "The machine starts straight to the login screen"
                selected: !root.answers.encrypt
                onPicked: { root.answers.encrypt = false; root.answersChanged() }
            }

            ColumnLayout {
                visible: root.answers.encrypt
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8
                Field {
                    id: cryptPass
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    placeholderText: "Passphrase"
                    onTextChanged: {
                        root.answers.encryptPassword = text
                        root.answersChanged()
                    }
                }
                Field {
                    id: cryptConfirm
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    placeholderText: "Passphrase again"
                    onTextChanged: {
                        root.answers.encryptConfirm = text
                        root.answersChanged()
                    }
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    visible: cryptConfirm.text.length > 0
                             && cryptConfirm.text !== cryptPass.text
                    text: "These do not match."
                    color: "#ff9db0"; font.pixelSize: 12
                }
                // The one thing about disk encryption that people are not
                // told until it is too late.
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "There is no way to recover this passphrase. If you forget it, "
                        + "everything on the disk is gone. Not locked, gone. It is separate "
                        + "from your login password, and you type it before the machine starts."
                    color: root.dim; font.pixelSize: 12
                    lineHeight: 1.3
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Restore points and going back to one work exactly the same on an "
                        + "encrypted disk. Decide now, though. Changing your mind later "
                        + "means reinstalling."
                    color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.8)
                    font.pixelSize: 12
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: accountPage
        ColumnLayout {
            spacing: 14
            Item { Layout.preferredHeight: 34 }
            Heading { title: "Create your account" }

            Flow {
                Layout.fillWidth: true
                spacing: 10

                // Your initials in the colour you picked, and the one that is
                // used unless something else is chosen. It costs nothing, it
                // is never a photograph of somebody who is not you, and it
                // fills in as the name is typed rather than sitting empty
                // waiting to be noticed.
                Rectangle {
                    width: 54; height: 54; radius: 27
                    color: root.answers.accent
                    border.width: root.answers.avatar === "" ? 3 : 1
                    border.color: root.answers.avatar === "" ? root.text : Qt.rgba(1,1,1,0.1)
                    QQC2.Label {
                        anchors.centerIn: parent
                        text: root.initialsFor(root.answers.fullname)
                        // Dark ink on every swatch in the picker: they are all
                        // mid-toned for exactly this reason.
                        color: "#3a2731"
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: { root.answers.avatar = ""; root.answersChanged() }
                    }
                }

                Repeater {
                    // A picture chosen from disk is prepended so it appears in
                    // the ring already selected, rather than being recorded
                    // invisibly with nothing on screen changing.
                    model: {
                        var list = backend.avatars()
                        var chosen = root.answers.avatar
                        if (chosen !== "" && list.indexOf(chosen) < 0)
                            return [chosen].concat(list)
                        return list
                    }
                    delegate: Rectangle {
                        required property string modelData
                        width: 54; height: 54; radius: 27
                        color: root.card
                        border.width: root.answers.avatar === modelData ? 3 : 1
                        border.color: root.answers.avatar === modelData ? root.accent : Qt.rgba(1,1,1,0.1)

                        // Round pictures need a mask. layer.enabled on its own
                        // -- which is what was here -- allocates a texture and
                        // draws nothing differently, so every picture sat as a
                        // square inside a circular border with its corners
                        // hanging over the edge.
                        Item {
                            id: shot
                            anchors.fill: parent
                            anchors.margins: 3
                            Image {
                                id: shotImage
                                anchors.fill: parent
                                source: modelData
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: false
                            }
                            Rectangle {
                                id: shotMask
                                anchors.fill: parent
                                radius: width / 2
                                visible: false
                                layer.enabled: true
                            }
                            MultiEffect {
                                anchors.fill: parent
                                source: shotImage
                                maskEnabled: true
                                maskSource: shotMask
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.answers.avatar = modelData; root.answersChanged() }
                        }
                    }
                }
            }
            RowLayout {
                FileDialog {
                    id: avatarDialog
                    title: "Choose a picture"
                    nameFilters: ["Images (*.png *.jpg *.jpeg *.webp)"]
                    onAccepted: {
                        root.answers.avatar = selectedFile.toString()
                        root.answersChanged()
                    }
                }
                QQC2.Button {
                    text: "Choose a photo…"
                    onClicked: avatarDialog.open()
                    padding: 9
                    leftPadding: 14
                    rightPadding: 14
                    contentItem: QQC2.Label {
                        text: parent.text
                        color: root.accent
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                    }
                    // Overridden for the same reason as Back: with the
                    // style's background left in place the style paints the
                    // label too, and the text renders twice.
                    background: Rectangle {
                        radius: 8
                        color: parent.down ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                    }
                }
            }

            QQC2.Label { text: "Your name"; color: root.dim; font.pixelSize: 13; topPadding: 8 }
            Field {
                id: fullNameField
                Layout.maximumWidth: 420
                // Not an example name. This said "Dresden", which is the name
                // of the person who wrote it, shown to everybody else who ever
                // installs this -- and any name put here is somebody's.
                placeholderText: "The name you go by"
                onTextChanged: {
                    root.answers.fullname = text; root.answersChanged()
                    // Follow the name until the username is edited by hand.
                    // The old guard was "username is still empty", but writing
                    // autoUser.text fires its own onTextChanged, which filled
                    // answers.username on the very first keystroke -- so the
                    // guard was false from the second letter on and the
                    // username stayed stuck at "d" for anyone called Dresden.
                    if (!autoUser.editedByHand)
                        autoUser.text = text.toLowerCase().replace(/[^a-z0-9]/g, "")
                }
            }
            QQC2.Label { text: "Username"; color: root.dim; font.pixelSize: 13 }
            Field {
                id: autoUser
                Layout.maximumWidth: 420
                // Says what the field wants rather than naming a person.
                placeholderText: "lowercase, no spaces"
                // textEdited fires only for typing, never for a binding or an
                // assignment, which is exactly the distinction needed here.
                property bool editedByHand: false
                onTextEdited: editedByHand = true
                onTextChanged: { root.answers.username = text; root.answersChanged() }
            }
            QQC2.Label { text: "Password"; color: root.dim; font.pixelSize: 13 }
            Field {
                Layout.maximumWidth: 420
                echoMode: TextInput.Password
                placeholderText: "At least 4 characters"
                onTextChanged: { root.answers.password = text; root.answersChanged() }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: browserPage
        ColumnLayout {
            spacing: 14
            Item { Layout.preferredHeight: 34 }
            Heading {
                title: "Pick a browser"
                subtitle: "You can install any of the others later from the store. This just decides what is ready on first boot."
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 14
                rowSpacing: 14

                Repeater {
                    // Brand colours only, no logos. Shipping vendor marks is
                    // fine as nominative use, but the assets have to come from
                    // each vendor's brand pack under their own terms -- not
                    // scraped off their site. Drop real icons in here once
                    // that is checked; the layout does not change.
                    // Every package name here is installed by pacstrap during
                    // the install, so each one has to resolve from a
                    // repository the target can reach. Three of the original
                    // four did not: zen-browser-bin, brave and google-chrome
                    // are AUR-only, and "brave" is not even the AUR name (it
                    // is brave-bin). Picking the default browser would have
                    // failed the install. They are rebuilt into sakura-extra
                    // now -- see packages/aur/manifest.txt -- and
                    // build/check-browsers.sh fails the build if any name
                    // here stops resolving.
                    model: [
                        { pkg: "zen-browser-bin", name: "Zen", icon: "zen",
                          detail: "SakuraOS default. Firefox-based, built around tabs you actually keep." },
                        { pkg: "firefox",         name: "Firefox", icon: "firefox",
                          detail: "Independent engine. Strong privacy defaults." },
                        { pkg: "brave-bin",       name: "Brave", icon: "brave",
                          detail: "Chromium-based. Blocks ads and trackers by default." },
                        { pkg: "vivaldi",         name: "Vivaldi", icon: "vivaldi",
                          detail: "Chromium-based. Heavily customisable, with tab tiling and stacking." },
                        { pkg: "helium-browser-bin", name: "Helium", icon: "helium",
                          detail: "Chromium-based, stripped of the tracking. Minimal by design." },
                        // Named in full: "Chrome" alone reads as Chromium to
                        // exactly the audience most likely to confuse them.
                        { pkg: "google-chrome",   name: "Google Chrome", icon: "chrome",
                          detail: "Chromium-based, by Google." }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool picked: root.answers.browser === modelData.pkg

                        Layout.fillWidth: true
                        Layout.preferredHeight: 148
                        radius: 14
                        color: picked ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14)
                                      : root.card
                        border.width: picked ? 2 : 1
                        border.color: picked ? root.accent : root.line
                        Behavior on color { ColorAnimation { duration: 110 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 8

                            Image {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                source: "qrc:/assets/browser-" + modelData.icon + ".png"
                                sourceSize: Qt.size(96, 96)
                                fillMode: Image.PreserveAspectFit
                            }
                            QQC2.Label {
                                text: modelData.name
                                color: root.text
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                            }
                            QQC2.Label {
                                text: modelData.detail
                                color: root.dim
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.answers.browser = modelData.pkg; root.answersChanged() }
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: updatesPage
        ColumnLayout {
            spacing: 16
            Item { Layout.preferredHeight: 34 }
            Heading {
                title: "Updates"
                subtitle: "SakuraOS updates continuously rather than in big releases. Falling months behind is riskier than updating often, so this is on by default."
            }
            Choice {
                heading: "Install updates automatically"
                detail: "A restore point is taken first, so a bad update is one reboot from fixed."
                selected: root.answers.autoUpdate
                onPicked: { root.answers.autoUpdate = !root.answers.autoUpdate; root.answersChanged() }
            }
            Choice {
                heading: "Only install updates that were tested first"
                detail: "SakuraOS installs and restarts each update on its own machines before offering it to yours."
                selected: root.answers.canaryOnly
                onPicked: { root.answers.canaryOnly = !root.answers.canaryOnly; root.answersChanged() }
            }
            RowLayout {
                spacing: 12
                QQC2.Label { text: "Install at"; color: root.dim; font.pixelSize: 13 }
                Field {
                    id: updateTimeField
                    Layout.maximumWidth: 92
                    // The mask follows the clock the user chose. It was always
                    // "99:99", so a machine set to a 12-hour clock still asked
                    // for the update time in 24-hour and offered no AM or PM --
                    // the one place in the installer that contradicted an
                    // answer the user had just given.
                    inputMask: root.answers.hour24 ? "99:99" : "x9:99"
                    // Set once rather than bound: binding text to the answer
                    // while writing that answer back on every keystroke makes
                    // the binding re-evaluate itself.
                    Component.onCompleted: text = root.updateTimeDisplay()
                    onEditingFinished: root.setUpdateTimeFrom(text, meridiem.label)
                    // Re-render when the clock format changes on the earlier
                    // screen, so going back and switching to 12-hour does not
                    // leave "15:00" sitting in the box.
                    Connections {
                        target: root
                        function onAnswersChanged() {
                            if (!updateTimeField.activeFocus)
                                updateTimeField.text = root.updateTimeDisplay()
                        }
                    }
                }
                // AM/PM, and only when it means something.
                QQC2.Button {
                    id: meridiem
                    property string label: root.updateTimeMeridiem()
                    visible: !root.answers.hour24
                    text: label
                    implicitWidth: 54
                    onClicked: {
                        label = (label === "AM") ? "PM" : "AM"
                        root.setUpdateTimeFrom(updateTimeField.text, label)
                    }
                }
                QQC2.Label { text: "and only when plugged in"; color: root.dim; font.pixelSize: 13 }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: featuresPage
        ColumnLayout {
            spacing: 14
            Item { Layout.preferredHeight: 34 }
            Heading { title: "What SakuraOS does for you" }
            Repeater {
                model: [
                    { t: "Terminal Assist", d: "Commands known to break Arch systems get stopped and explained before they run. You can always override one, and it tells you exactly how." },
                    { t: "Restore points", d: "A snapshot is taken before every update. If something breaks, pick Recovery in the boot menu and go back. No live USB, no chroot." },
                    { t: "The AUR is off", d: "The Arch User Repository is build scripts written by other users that nobody reviews. Turn it on in Settings when you want it, and Sakura will show you what a package does before it builds." }
                ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: c.implicitHeight + 34
                    radius: 14
                    color: root.card
                    ColumnLayout {
                        id: c
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 5
                        RowLayout {
                            spacing: 9
                            Rectangle { width: 7; height: 7; radius: 4; color: root.accent }
                            QQC2.Label {
                                text: modelData.t; color: root.text
                                font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                        }
                        QQC2.Label {
                            text: modelData.d; color: root.dim
                            font.pixelSize: 13; wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: privacyPage
        ColumnLayout {
            spacing: 16
            Item { Layout.preferredHeight: 34 }
            Heading { title: "Privacy" }
            ColumnLayout {
                spacing: 9
                Repeater {
                    model: [
                        "SakuraOS collects nothing about you or this computer.",
                        "Nothing is sent anywhere unless you ask for it.",
                        "There is no account to create and nothing to sign in to."
                    ]
                    delegate: RowLayout {
                        required property string modelData
                        spacing: 10
                        QQC2.Label { text: "✓"; color: root.accent; font.pixelSize: 15 }
                        QQC2.Label {
                            text: modelData; color: root.text; font.pixelSize: 14
                            wrapMode: Text.WordWrap; Layout.fillWidth: true
                        }
                    }
                }
            }
            QQC2.Label {
                text: "Help KDE improve Plasma"
                color: root.text
                font.pixelSize: 15
                font.weight: Font.DemiBold
                topPadding: 8
            }
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: root.dim
                font.pixelSize: 13
                text: "This one is not ours. Plasma, the desktop SakuraOS uses, is made by KDE, and they can accept anonymous information about your hardware and which features you use, to find bugs. It goes to KDE, never to SakuraOS, and it is off unless you switch it on here."
            }
            Choice {
                heading: root.answers.crashReports ? "Sending basic information to KDE"
                                                   : "Sending nothing to KDE"
                detail: "You can change this later in System Settings under User Feedback."
                selected: root.answers.crashReports
                onPicked: { root.answers.crashReports = !root.answers.crashReports; root.answersChanged() }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: summaryPage
        ColumnLayout {
            spacing: 16
            Item { Layout.preferredHeight: 34 }
            Heading {
                title: "Before anything is written"
                subtitle: "Nothing has been changed on this machine yet. Everything below happens when you continue."
            }

            // The destructive part, on its own and stated in the plainest
            // words available. It names the disk, because "the disk" is not
            // specific enough to check and this is the last chance to notice
            // the wrong one is selected.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: warnCol.implicitHeight + 30
                radius: 12
                color: root.answers.diskMode === "alongside"
                       ? root.card : Qt.rgba(0.78, 0.32, 0.31, 0.16)
                border.width: 1
                border.color: root.answers.diskMode === "alongside"
                              ? root.line : Qt.rgba(0.78, 0.32, 0.31, 0.55)
                ColumnLayout {
                    id: warnCol
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; anchors.margins: 15
                    spacing: 5
                    QQC2.Label {
                        text: root.answers.diskMode === "alongside"
                            ? "SakuraOS will be added to " + root.answers.disk
                            : "Everything on " + root.answers.disk + " will be erased"
                        color: root.answers.diskMode === "alongside"
                               ? root.text : "#ff9db0"
                        font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        // Two different things happen here, and the warning
                        // has to say which. A screen that shouts about erasing
                        // a disk it is not going to erase teaches people to
                        // skip the warning that matters.
                        text: root.answers.diskMode === "alongside"
                            ? "It goes into unallocated space. Existing partitions are not "
                            + "touched, and the systems already installed here keep working. "
                            + "They will be offered in the boot menu alongside SakuraOS."
                            : "Every file, every other operating system, and every partition on "
                            + "that disk. This cannot be undone, and it starts as soon as you "
                            + "press Install. Other disks in this machine are not touched."
                        color: root.dim; font.pixelSize: 13
                        lineHeight: 1.3
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 26
                rowSpacing: 9
                Repeater {
                    model: [
                        { k: "Language",  v: root.localeName(root.answers.locale) },
                        { k: "Keyboard",  v: root.layoutName(root.answers.keyboard) },
                        { k: "Time zone", v: root.answers.timezone },
                        { k: "Clock",     v: root.answers.hour24 ? "24-hour" : "12-hour" },
                        { k: "Appearance", v: root.answers.dark ? "Dark" : "Light" },
                        { k: "Disk",      v: root.answers.disk
                                             + (root.answers.diskMode === "alongside"
                                                ? "  \u00b7  installing alongside what is there"
                                                : "  \u00b7  erasing everything") },
                        { k: "Encryption", v: root.answers.encrypt
                                              ? "On, you enter a passphrase at every start"
                                              : "Off" },
                        { k: "Computer name", v: root.answers.hostname },
                        { k: "Your account",  v: root.answers.username },
                        { k: "Browser",   v: root.answers.browser === "none"
                                             ? "None" : root.answers.browser },
                        { k: "Updates",   v: "Installed automatically, behind a restore point" }
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.columnSpan: 2
                        spacing: 12
                        QQC2.Label {
                            Layout.preferredWidth: 130
                            text: modelData.k
                            color: root.dim; font.pixelSize: 13
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: modelData.v
                            color: root.text; font.pixelSize: 13
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: installPage
        ColumnLayout {
            spacing: 18

            // How long each slide holds. A copy install finishes in a couple
            // of minutes, so a slower rotation would show two slides and stop
            // -- the deck is paced to be seen, not to fill an hour.
            readonly property int slideHold: 9000

            readonly property var slides: [
                {
                    t: "Nothing you type can quietly break it",
                    d: `Terminal Assist stops the commands known to wreck an Arch \
system and explains what they would have done. You can always override one, \
and it tells you exactly how.`
                },
                {
                    t: "Every update is reversible",
                    d: `A snapshot is taken before anything changes. If an update \
goes wrong, pick Recovery in the boot menu and you are back where you were. \
No live USB, no chroot, no forum thread.`
                },
                {
                    t: "Software without the guesswork",
                    d: `The App Store shows you what a package actually is before \
it installs, and where it came from. The AUR stays off until you turn it on, \
and Sakura reads the build script to you when you do.`
                },
                {
                    t: "Tuned for the machine you have",
                    d: `SakuraOS checks what your processor supports and installs \
the kernel that suits it. Older hardware gets the one that runs everywhere, \
newer hardware gets the faster build.`
                }
            ]
            property int slideIndex: 0

            Item { Layout.preferredHeight: 40 }

            // The backend reports a failure by leaving running false with the
            // step set to "Failed". Testing only running and percent meant a
            // failed install fell through to "Ready to install" -- the screen
            // a customer sees BEFORE starting -- over a stale progress bar,
            // with no error anywhere. That happened on a real machine and the
            // machine was left unbootable.
            readonly property bool failed: !backend.running
                                           && backend.currentStep === "Failed"

            Heading {
                title: backend.running ? "Installing SakuraOS"
                     : failed ? "The install did not finish"
                     : backend.percent === 100 ? "You are all set"
                     : "Ready to install"
                subtitle: backend.running ? backend.currentStep
                        : failed ? "Nothing was written that cannot be written again. The details below say what happened."
                        : backend.percent === 100
                          ? "SakuraOS is installed on this machine. Restart to use it, and take the installation media out when the screen goes black."
                          : ""
            }

            // The deck. It holds the space whether or not it is showing
            // anything, so the progress bar underneath never jumps.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 150
                visible: !showLog.checked

                ColumnLayout {
                    id: deck
                    // Capped rather than full-bleed: a line of body text that
                    // runs the whole width of a 1080p screen is measurably
                    // harder to read, and this is a screen people sit and
                    // stare at with nothing else to do.
                    width: Math.min(parent.width, 760)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    opacity: 1
                    Behavior on opacity { NumberAnimation { duration: 300 } }

                    QQC2.Label {
                        text: slides[slideIndex].t
                        color: root.text
                        font.pixelSize: 21
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    QQC2.Label {
                        text: slides[slideIndex].d
                        color: root.dim
                        font.pixelSize: 14
                        lineHeight: 1.35
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            // Which slide you are on. Repeater delegates are siblings, so the
            // row is the parent and each dot sizes itself.
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 7
                visible: !showLog.checked
                Repeater {
                    model: slides.length
                    delegate: Rectangle {
                        required property int index
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        radius: 3
                        color: index === slideIndex ? root.accent : root.card
                        Behavior on color { ColorAnimation { duration: 250 } }
                    }
                }
            }

            // The log, for when something has gone wrong and the slides are
            // no longer the interesting thing on screen.
            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // A ScrollView takes its implicit height from its content, so
                // without a floor it collapsed to nothing the moment the deck
                // beside it was hidden: the log was there and none of it was
                // on screen, which is how a failed install showed an empty
                // details pane.
                Layout.minimumHeight: 220
                visible: showLog.checked
                QQC2.TextArea {
                    readOnly: true
                    // Only bound while the pane is open. A binding keeps being
                    // re-evaluated when its item is invisible -- visibility is
                    // not laziness -- so this was rebuilding the whole text
                    // document of an ever-growing log on every chunk of
                    // installer output, hidden, for the entire install.
                    // pacman's progress bars emit many chunks a second, which
                    // left no time for anything else and froze the slideshow
                    // in place.
                    text: showLog.checked ? backend.log : ""
                    color: root.dim
                    font.family: "monospace"
                    font.pixelSize: 11
                    background: Rectangle { color: "#1e1218"; radius: 8 }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                color: root.card
                Rectangle {
                    width: parent.width * (backend.percent / 100)
                    height: parent.height
                    radius: 3
                    color: root.accent
                    Behavior on width { NumberAnimation { duration: 320 } }
                }
            }

            QQC2.CheckBox {
                id: showLog
                text: "Show details"
                // Opened automatically when the install fails. Asking somebody
                // to go looking for the error is asking them to guess that
                // there is one.
                checked: false
                Connections {
                    target: backend
                    function onRunningChanged() {
                        if (!backend.running && backend.currentStep === "Failed")
                            showLog.checked = true
                    }
                }
                font.pixelSize: 12
                Layout.alignment: Qt.AlignHCenter
                contentItem: QQC2.Label {
                    text: showLog.text
                    color: root.dim
                    font.pixelSize: 12
                    leftPadding: showLog.indicator.width + 6
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Item { Layout.preferredHeight: 6 }

            // Advance in two beats: fade out, swap the text while it is
            // invisible, fade back in. Swapping and fading at once shows the
            // next slide arriving half-written.
            Timer {
                interval: slideHold
                running: backend.running && !showLog.checked
                repeat: true
                onTriggered: { deck.opacity = 0; swap.restart() }
            }
            Timer {
                id: swap
                interval: 320
                onTriggered: {
                    slideIndex = (slideIndex + 1) % slides.length
                    deck.opacity = 1
                }
            }

            Component.onCompleted: backend.install(root.answers)
        }
    }
}
