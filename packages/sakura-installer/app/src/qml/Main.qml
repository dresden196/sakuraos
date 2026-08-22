import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window

QQC2.ApplicationWindow {
    id: root

    width: 1000
    height: 660
    minimumWidth: 900
    minimumHeight: 600
    visible: true
    title: "Install SakuraOS"

    // ---- palette -----------------------------------------------------------
    // The dark scheme's accent, because the installer runs before the user has
    // chosen light or dark and dark is the default.
    readonly property color accent:     "#ffb7c5"
    readonly property color accentDeep: "#d81b60"
    readonly property color bg:         "#26161e"
    readonly property color panel:      "#2f1f28"
    readonly property color card:       "#3a2731"
    readonly property color text:       "#f6eef2"
    readonly property color dim:        "#bfa8b4"

    color: bg

    // ---- collected answers -------------------------------------------------
    property var answers: ({
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

    property int step: 0
    readonly property var steps: [
        { title: "Keyboard",   blurb: "How your keys are laid out" },
        { title: "Time",       blurb: "Where you are, and how you read a clock" },
        { title: "Appearance", blurb: "Light or dark" },
        { title: "Disk",       blurb: "Where SakuraOS goes" },
        { title: "Account",    blurb: "Who this machine belongs to" },
        { title: "Browser",    blurb: "How you get online" },
        { title: "Updates",    blurb: "Staying current, safely" },
        { title: "Sakura",     blurb: "What this system does for you" },
        { title: "Privacy",    blurb: "What leaves this machine" },
        { title: "Install",    blurb: "" }
    ]

    function canContinue() {
        switch (step) {
        case 3: return answers.disk !== ""
        case 4: return answers.username.length > 0 && answers.password.length >= 4
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
        implicitHeight: inner.implicitHeight + 26
        radius: 10
        color: selected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) : root.card
        border.width: selected ? 2 : 1
        border.color: selected ? root.accent : Qt.rgba(1, 1, 1, 0.07)

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
        selectedTextColor: "#1b1e20"
        leftPadding: 12
        topPadding: 10
        bottomPadding: 10
        background: Rectangle {
            radius: 8
            color: root.card
            border.width: parent.activeFocus ? 2 : 1
            border.color: parent.activeFocus ? root.accent : Qt.rgba(1, 1, 1, 0.09)
        }
    }

    // ---- layout ------------------------------------------------------------
    RowLayout {
        anchors.fill: parent
        spacing: 0

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
                            color: "#3a2731"
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
                                    color: index < root.step ? "#3a2731"
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

                Loader {
                    id: pageLoader
                    width: parent.width
                    sourceComponent: {
                        switch (root.step) {
                        case 0: return keyboardPage
                        case 1: return timePage
                        case 2: return themePage
                        case 3: return diskPage
                        case 4: return accountPage
                        case 5: return browserPage
                        case 6: return updatesPage
                        case 7: return featuresPage
                        case 8: return privacyPage
                        default: return installPage
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.rgba(1, 1, 1, 0.08)
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 20
                spacing: 12

                QQC2.Button {
                    text: "Back"
                    visible: root.step > 0 && root.step < 9
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
                    text: root.step === 8 ? "Install SakuraOS" : "Continue"
                    visible: root.step < 9
                    enabled: root.canContinue()
                    padding: 11
                    leftPadding: 26
                    rightPadding: 26
                    onClicked: root.step++
                    contentItem: QQC2.Label {
                        text: parent.text
                        color: parent.enabled ? "#3a2731" : root.dim
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
        id: keyboardPage
        ColumnLayout {
            anchors.margins: 40
            spacing: 18
            Item { Layout.preferredHeight: 22 }
            Heading {
                title: "Keyboard layout"
                subtitle: "Type in the box below to check it before continuing. Getting this wrong locks you out at your first login prompt."
            }
            QQC2.ComboBox {
                id: kb
                Layout.fillWidth: true
                Layout.maximumWidth: 460
                model: backend.keyboardLayouts()
                textRole: "name"
                valueRole: "code"
                Component.onCompleted: currentIndex = indexOfValue(root.answers.keyboard)
                onActivated: { root.answers.keyboard = currentValue; root.answersChanged() }
            }
            Field { placeholderText: "Try typing here…"; Layout.maximumWidth: 460 }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: timePage
        ColumnLayout {
            anchors.margins: 40
            spacing: 18
            Item { Layout.preferredHeight: 22 }
            Heading { title: "Time"; subtitle: "Used for your clock, and for checking that updates are signed correctly." }
            QQC2.Label { text: "Time zone"; color: root.dim; font.pixelSize: 13 }
            QQC2.ComboBox {
                Layout.fillWidth: true
                Layout.maximumWidth: 460
                model: backend.timezones()
                editable: true
                Component.onCompleted: {
                    var guess = backend.guessTimezone()
                    var idx = find(guess)
                    if (idx < 0) {
                        guess = "UTC"
                        idx = find(guess)
                    }
                    root.answers.timezone = guess
                    currentIndex = idx
                }
                onActivated: { root.answers.timezone = currentText; root.answersChanged() }
            }
            QQC2.Label { text: "Clock"; color: root.dim; font.pixelSize: 13; topPadding: 10 }
            Choice {
                Layout.maximumWidth: 460
                heading: "24-hour"; detail: "19:44"
                selected: root.answers.hour24
                onPicked: { root.answers.hour24 = true; root.answersChanged() }
            }
            Choice {
                Layout.maximumWidth: 460
                heading: "12-hour"; detail: "7:44 PM"
                selected: !root.answers.hour24
                onPicked: { root.answers.hour24 = false; root.answersChanged() }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: themePage
        ColumnLayout {
            anchors.margins: 40
            spacing: 18
            Item { Layout.preferredHeight: 22 }
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
            anchors.margins: 40
            spacing: 16
            Item { Layout.preferredHeight: 22 }
            Heading {
                title: "Where should SakuraOS go?"
                subtitle: "Everything on the disk you choose will be erased."
            }
            Repeater {
                model: backend.disks()
                delegate: Choice {
                    required property var modelData
                    Layout.maximumWidth: 560
                    heading: (modelData.model !== "" ? modelData.model : "Disk") + "  ·  " + modelData.sizeText
                    detail: modelData.device + (modelData.removable ? "  ·  removable" : "")
                    selected: root.answers.disk === modelData.device
                    onPicked: { root.answers.disk = modelData.device; root.answersChanged() }
                }
            }
            QQC2.Label {
                Layout.maximumWidth: 560
                wrapMode: Text.WordWrap
                color: root.dim
                font.pixelSize: 13
                text: "SakuraOS will use BTRFS with automatic restore points, so a bad update can be undone from the boot menu."
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: accountPage
        ColumnLayout {
            anchors.margins: 40
            spacing: 14
            Item { Layout.preferredHeight: 22 }
            Heading { title: "Create your account" }

            Flow {
                Layout.fillWidth: true
                Layout.maximumWidth: 620
                spacing: 10
                Repeater {
                    model: backend.avatars()
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
                QQC2.Button {
                    text: "Choose a photo…"
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
            anchors.margins: 40
            spacing: 14
            Item { Layout.preferredHeight: 22 }
            Heading {
                title: "Pick a browser"
                subtitle: "You can install any of the others later from the store. This just decides what is ready on first boot."
            }
            Repeater {
                model: [
                    { pkg: "zen-browser-bin", name: "Zen", detail: "SakuraOS default. A Firefox-based browser built around tabs you actually keep." },
                    { pkg: "firefox",         name: "Firefox", detail: "Independent engine, strong privacy defaults." },
                    { pkg: "brave",           name: "Brave", detail: "Chromium-based, blocks ads and trackers by default." },
                    { pkg: "google-chrome",   name: "Chrome", detail: "Chromium-based, by Google." }
                ]
                delegate: Choice {
                    required property var modelData
                    Layout.maximumWidth: 560
                    heading: modelData.name
                    detail: modelData.detail
                    selected: root.answers.browser === modelData.pkg
                    onPicked: { root.answers.browser = modelData.pkg; root.answersChanged() }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: updatesPage
        ColumnLayout {
            anchors.margins: 40
            spacing: 16
            Item { Layout.preferredHeight: 22 }
            Heading {
                title: "Updates"
                subtitle: "SakuraOS updates continuously rather than in big releases. Falling months behind is riskier than updating often, so this is on by default."
            }
            Choice {
                Layout.maximumWidth: 560
                heading: "Install updates automatically"
                detail: "A restore point is taken first, so a bad update is one reboot from fixed."
                selected: root.answers.autoUpdate
                onPicked: { root.answers.autoUpdate = !root.answers.autoUpdate; root.answersChanged() }
            }
            Choice {
                Layout.maximumWidth: 560
                heading: "Only install updates that were tested first"
                detail: "SakuraOS installs and restarts each update on its own machines before offering it to yours."
                selected: root.answers.canaryOnly
                onPicked: { root.answers.canaryOnly = !root.answers.canaryOnly; root.answersChanged() }
            }
            RowLayout {
                spacing: 12
                QQC2.Label { text: "Install at"; color: root.dim; font.pixelSize: 13 }
                Field {
                    Layout.maximumWidth: 90
                    text: root.answers.updateTime
                    inputMask: "99:99"
                    onTextChanged: { root.answers.updateTime = text; root.answersChanged() }
                }
                QQC2.Label { text: "and only when plugged in"; color: root.dim; font.pixelSize: 13 }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: featuresPage
        ColumnLayout {
            anchors.margins: 40
            spacing: 14
            Item { Layout.preferredHeight: 22 }
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
                    Layout.maximumWidth: 600
                    implicitHeight: c.implicitHeight + 28
                    radius: 10
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
            anchors.margins: 40
            spacing: 16
            Item { Layout.preferredHeight: 22 }
            Heading { title: "Privacy" }
            ColumnLayout {
                Layout.maximumWidth: 600
                spacing: 9
                Repeater {
                    model: [
                        "No telemetry is collected, and none is switched on behind your back.",
                        "Nothing about this machine is sent anywhere unless you ask for it.",
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
            Choice {
                Layout.maximumWidth: 600
                heading: "Send crash reports"
                detail: "Off unless you turn it on. A distribution that cannot see what breaks cannot fix it — but that is our problem, not a reason to take your data without asking."
                selected: root.answers.crashReports
                onPicked: { root.answers.crashReports = !root.answers.crashReports; root.answersChanged() }
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: installPage
        ColumnLayout {
            anchors.margins: 40
            spacing: 20
            Item { Layout.preferredHeight: 40 }
            Heading {
                title: backend.running ? "Installing SakuraOS"
                     : backend.percent === 100 ? "SakuraOS is installed"
                     : "Ready to install"
                subtitle: backend.running ? backend.currentStep : ""
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.maximumWidth: 600
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
                Layout.maximumWidth: 600
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
