import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Dialogs

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
    readonly property color accent: dark ? "#ffb7c5" : "#d81b60"
    readonly property color accentText: dark ? "#3a2731" : "#ffffff"
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
    readonly property int contentWidth: 620

    // ---- collected answers -------------------------------------------------
    property var answers: ({
        locale: "en_US.UTF-8",
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

    property int step: -2
    readonly property var steps: [
        { title: "Language",   blurb: "What this machine speaks" },
        { title: "Keyboard",   blurb: "How your keys are laid out" },
        { title: "Time",       blurb: "Where you are, and how you read a clock" },
        { title: "Appearance", blurb: "Light or dark" },
        { title: "Disk",       blurb: "Where SakuraOS goes" },
        { title: "Encryption", blurb: "Whether the disk is readable without you" },
        { title: "Account",    blurb: "Who this machine belongs to" },
        { title: "Browser",    blurb: "How you get online" },
        { title: "Updates",    blurb: "Staying current, safely" },
        { title: "Sakura",     blurb: "What this system does for you" },
        { title: "Privacy",    blurb: "What leaves this machine" },
        { title: "Install",    blurb: "" }
    ]

    function canContinue() {
        switch (step) {
        case 4: return answers.disk !== ""
        // Both fields, matching. A mistyped passphrase on an encrypted disk
        // is discovered at the next boot, when it is far too late.
        case 5: return !answers.encrypt
                    || (answers.encryptPassword.length >= 6
                        && answers.encryptPassword === answers.encryptConfirm)
        case 6: return answers.username.length > 0 && answers.password.length >= 4
        default: return true
        }
    }

    // ---- shared building blocks -------------------------------------------
    component Heading : ColumnLayout {
        property string title
        property string subtitle
        Layout.fillWidth: true
        spacing: 6
        QQC2.Label {
            text: parent.title
            color: root.text
            font.pixelSize: 26
            font.weight: Font.Medium
        }
        QQC2.Label {
            text: parent.subtitle
            color: root.dim
            font.pixelSize: 14
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            visible: text !== ""
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
    // ---- what this distribution actually does differently -------------------
    // Between the welcome and the questions, because somebody who has just
    // booted an unfamiliar system has no idea what they are agreeing to set
    // up. Every claim here is one the machine can be held to; the ones that
    // are not yet true are not on this page.
    Item {
        anchors.fill: parent
        visible: root.step === -1

        ColumnLayout {
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
                Layout.fillWidth: true
                columns: width > 700 ? 2 : 1
                columnSpacing: 18
                rowSpacing: 18

                Repeater {
                    model: [
                        {
                            title: "Built for a modern machine",
                            body: "A kernel tuned for better scheduling and built for the processors "
                                + "people actually own, rather than for the oldest one still "
                                + "supported. The same hardware, doing more."
                        },
                        {
                            title: "It can undo itself",
                            body: "The disk is BTRFS with automatic snapshots. A restore point is taken "
                                + "before every change, and you can take one yourself from the Update "
                                + "Center before doing something risky. If an update goes wrong, go "
                                + "back \u2014 your documents and photos are never part of a restore point."
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
                                + "that do real damage \u2014 partial upgrades, removing the last kernel, "
                                + "force-removing packages other things depend on \u2014 stops them, and "
                                + "tells you what to run instead."
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
                        Layout.fillWidth: true
                        Layout.preferredHeight: card.implicitHeight + 34
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

    Item {
        anchors.fill: parent
        visible: root.step === -2

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(560, parent.width - 100)
            spacing: 0

            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 132
                Layout.preferredHeight: 132
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
                text: "Welcome to SakuraOS \u2014 a privacy-first, Arch-based distribution built around ease of use, performance, and not having to open a terminal."
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
                onClicked: root.step = -1
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
                clip: true
                contentWidth: availableWidth

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
                        case 2: return timePage
                        case 3: return themePage
                        case 4: return diskPage
                        case 5: return encryptPage
                        case 6: return accountPage
                        case 7: return browserPage
                        case 8: return updatesPage
                        case 9: return featuresPage
                        case 10: return privacyPage
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
                    visible: root.step > 0 && root.step < 11
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
                QQC2.Button {
                    // Ten screens now that language leads: 0..9, with the
                    // install itself at 10.
                    text: root.step === 10 ? "Install SakuraOS" : "Continue"
                    visible: root.step < 11
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
            Heading {
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
            // The layout, drawn. Reading "German (no dead keys)" tells you
            // very little; seeing where Z and Y sit tells you immediately
            // whether this is the keyboard in front of you.
            ColumnLayout {
                id: kbPreview
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 5
                property var rows: backend.keyboardPreview(root.answers.keyboard)

                Connections {
                    target: root
                    function onAnswersChanged() {
                        kbPreview.rows = backend.keyboardPreview(root.answers.keyboard)
                    }
                }

                Repeater {
                    model: kbPreview.rows
                    delegate: RowLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 5
                        // Each row on a real board starts a little further in
                        // than the one above it.
                        Item {
                            Layout.preferredWidth: [0, 14, 22, 38][index] || 0
                            Layout.preferredHeight: 1
                        }
                        Repeater {
                            model: modelData
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                Layout.minimumWidth: 26
                                radius: 6
                                color: root.card
                                border.width: 1
                                border.color: root.line
                                QQC2.Label {
                                    anchors.centerIn: parent
                                    text: modelData || ""
                                    color: root.text
                                    font.pixelSize: modelData && modelData.length > 2 ? 10 : 14
                                }
                            }
                        }
                    }
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
                onPicked: { root.answers.hour24 = true; root.answersChanged() }
            }
            Choice {
                heading: "12-hour"
                detail: ((clock.hours % 12) === 0 ? 12 : clock.hours % 12) + ":"
                      + (clock.minutes < 10 ? "0" : "") + clock.minutes
                      + (clock.hours < 12 ? " AM" : " PM")
                selected: !root.answers.hour24
                onPicked: { root.answers.hour24 = false; root.answersChanged() }
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
                subtitle: "Everything on the disk you choose will be erased."
            }
            Repeater {
                model: backend.disks()
                delegate: Choice {
                    required property var modelData
                    heading: (modelData.model !== "" ? modelData.model : "Disk") + "  ·  " + modelData.sizeText
                    detail: modelData.device + (modelData.removable ? "  ·  removable" : "")
                    selected: root.answers.disk === modelData.device
                    onPicked: { root.answers.disk = modelData.device; root.answersChanged() }
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
                        + "everything on the disk is gone \u2014 not locked, gone. It is separate "
                        + "from your login password, and you type it before the machine starts."
                    color: root.dim; font.pixelSize: 12
                    lineHeight: 1.3
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Restore points and going back to one work exactly the same on an "
                        + "encrypted disk. You can also turn encryption off later without "
                        + "reinstalling."
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
                        Image {
                            anchors.fill: parent
                            anchors.margins: 3
                            source: modelData
                            fillMode: Image.PreserveAspectCrop
                            layer.enabled: true
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
                Layout.maximumWidth: 420
                placeholderText: "Dresden"
                onTextChanged: {
                    root.answers.fullname = text; root.answersChanged()
                    if (root.answers.username === "")
                        autoUser.text = text.toLowerCase().replace(/[^a-z0-9]/g, "")
                }
            }
            QQC2.Label { text: "Username"; color: root.dim; font.pixelSize: 13 }
            Field {
                id: autoUser
                Layout.maximumWidth: 420
                placeholderText: "dresden"
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
                    model: [
                        { pkg: "zen-browser-bin", name: "Zen", icon: "zen",
                          detail: "SakuraOS default. Firefox-based, built around tabs you actually keep." },
                        { pkg: "firefox",         name: "Firefox", icon: "firefox",
                          detail: "Independent engine. Strong privacy defaults." },
                        { pkg: "brave",           name: "Brave", icon: "brave",
                          detail: "Chromium-based. Blocks ads and trackers by default." },
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
                    Layout.maximumWidth: 92
                    inputMask: "99:99"
                    // Set once rather than bound: binding text to the answer
                    // while writing that answer back on every keystroke makes
                    // the binding re-evaluate itself. Nothing validates this
                    // field, so committing on edit-finished is enough.
                    Component.onCompleted: text = root.answers.updateTime
                    onEditingFinished: root.answers.updateTime = text
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
                    { t: "Terminal Assist", d: "Commands known to break Arch systems get stopped and explained before they run. You can always override one — it tells you exactly how." },
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
                text: "This one is not ours. Plasma — the desktop SakuraOS uses — is made by KDE, and they can accept anonymous information about your hardware and which features you use, to find bugs. It goes to KDE, never to SakuraOS, and it is off unless you switch it on here."
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
        id: installPage
        ColumnLayout {
            spacing: 20
            Item { Layout.preferredHeight: 48 }
            Heading {
                title: backend.running ? "Installing SakuraOS"
                     : backend.percent === 100 ? "SakuraOS is installed"
                     : "Ready to install"
                subtitle: backend.running ? backend.currentStep : ""
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
            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: backend.log !== ""
                QQC2.TextArea {
                    readOnly: true
                    text: backend.log
                    color: root.dim
                    font.family: "monospace"
                    font.pixelSize: 11
                    background: Rectangle { color: "#1e1218"; radius: 8 }
                }
            }
            Component.onCompleted: backend.install(root.answers)
        }
    }
}
