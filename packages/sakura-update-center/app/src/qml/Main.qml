import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

QQC2.ApplicationWindow {
    id: root
    width: 900; height: 640
    minimumWidth: 720; minimumHeight: 520
    visible: true
    title: "Update Center"

    palette.window: bg
    palette.windowText: text
    color: bg

    // The update window is stored as 24-hour "HH:MM" -- that is what goes into
    // sakura.conf and what the timer reads -- and only its presentation
    // follows this machine's clock. Keeping one canonical form means a machine
    // set to a 12-hour clock does not end up with a differently-shaped config
    // file from one set to 24.
    function displayTime(stored) {
        var parts = ("" + (stored || "03:00")).split(":")
        var h = parseInt(parts[0], 10)
        var m = parts[1] || "00"
        if (isNaN(h)) { h = 3; m = "00" }
        if (backend.uses24Hour)
            return (h < 10 ? "0" + h : "" + h) + ":" + m
        var h12 = h % 12
        if (h12 === 0) h12 = 12
        return h12 + ":" + m
    }

    function meridiemOf(stored) {
        var h = parseInt(("" + (stored || "03:00")).split(":")[0], 10)
        return (isNaN(h) || h < 12) ? "AM" : "PM"
    }

    // Anything unreadable falls back to 03:00 rather than to midnight: a
    // silent 00:00 is a schedule change nobody asked for.
    function storedTime(shown, meridiemLabel) {
        var parts = ("" + shown).split(":")
        var h = parseInt(parts[0], 10)
        var m = parseInt(parts[1], 10)
        if (isNaN(h) || isNaN(m) || m < 0 || m > 59) return "03:00"
        if (!backend.uses24Hour) {
            if (h < 1 || h > 12) return "03:00"
            h = h % 12
            if (meridiemLabel === "PM") h += 12
        } else if (h < 0 || h > 23) {
            return "03:00"
        }
        return (h < 10 ? "0" + h : "" + h) + ":" + (m < 10 ? "0" + m : "" + m)
    }

    // The restore point awaiting confirmation, or null. Rolling back replaces
    // the whole system with an earlier copy of itself, so it is never one
    // click away.
    property var confirmRollback: null
    // The restore point awaiting a delete confirmation, or null.
    property var confirmDelete: null

    readonly property color accent: "#ffb7c5"
    readonly property color accentText: "#3a2731"
    readonly property color bg: "#26161e"
    readonly property color panel: "#2f1f28"
    readonly property color card: "#3a2731"
    readonly property color text: "#f6eef2"
    readonly property color dim: "#bfa8b4"
    readonly property color line: Qt.rgba(1, 1, 1, 0.09)
    readonly property color good: "#8fd3a4"
    readonly property color warn: "#f6c76b"

    property int tab: 0
    readonly property var tabs: ["Status", "Available", "History", "Schedule"]

    Component.onCompleted: { backend.check(); backend.loadHistory() }

    // ---- shared pieces -----------------------------------------------------
    component Head : ColumnLayout {
        property string title
        property string subtitle
        Layout.fillWidth: true
        spacing: 5
        QQC2.Label {
            text: parent.title; color: root.text
            font.pixelSize: 25; font.weight: Font.DemiBold
        }
        QQC2.Label {
            text: parent.subtitle; color: root.dim; font.pixelSize: 14
            wrapMode: Text.WordWrap; Layout.fillWidth: true
            visible: text !== ""
        }
    }

    component Pill : Rectangle {
        property string label
        property color tint: root.accent
        implicitWidth: t.implicitWidth + 18
        implicitHeight: 22
        radius: 11
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.16)
        border.width: 1
        border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.45)
        QQC2.Label {
            id: t; anchors.centerIn: parent; text: label; color: tint
            font.pixelSize: 12 ; font.weight: Font.DemiBold
        }
    }

    component Btn : QQC2.Button {
        property bool quiet: false
        padding: 10; leftPadding: 22; rightPadding: 22
        contentItem: QQC2.Label {
            text: parent.text
            color: parent.enabled ? (parent.quiet ? root.text : root.accentText) : root.dim
            font.pixelSize: 14; font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 8
            color: !parent.enabled ? root.card
                 : parent.quiet ? (parent.down ? Qt.rgba(1,1,1,.10) : "transparent")
                 : (parent.down ? Qt.darker(root.accent, 1.15) : root.accent)
            border.width: parent.quiet ? 1 : 0
            border.color: root.line
        }
    }

    // ---- window ------------------------------------------------------------
    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.preferredWidth: 190
            Layout.fillHeight: true
            color: panel

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 18

                RowLayout {
                    spacing: 9
                    // The mark itself rather than the "✿" florette: the same
                    // drawing the site, the installer and the boot screen use.
                    Image {
                        source: "qrc:/assets/sakura-mark.svg"
                        sourceSize: Qt.size(48, 48)
                        width: 24; height: 24
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    QQC2.Label { text: "Updates"; color: root.text; font.pixelSize: 16; font.weight: Font.DemiBold }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: root.tabs
                        delegate: Rectangle {
                            required property int index
                            required property string modelData
                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: 8
                            color: index === root.tab ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                                                      : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 11
                                anchors.rightMargin: 9
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: modelData
                                    color: index === root.tab ? root.accent : root.dim
                                    font.pixelSize: 14
                                    font.weight: index === root.tab ? Font.DemiBold : Font.Normal
                                }
                                Pill {
                                    visible: index === 1 && backend.updates.length > 0
                                    label: backend.updates.length.toString()
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.tab = index; if (index === 2) backend.loadHistory() }
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                QQC2.Label {
                    text: backend.lastChecked === "" ? "" : "Checked " + backend.lastChecked
                    color: root.dim; font.pixelSize: 12
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 20
                Layout.bottomMargin: 0
                implicitHeight: 44
                radius: 9
                visible: backend.error !== ""
                color: Qt.rgba(1, 0.36, 0.48, 0.14)
                border.width: 1
                border.color: Qt.rgba(1, 0.36, 0.48, 0.4)
                QQC2.Label {
                    anchors.fill: parent; anchors.margins: 12
                    text: backend.error; color: "#ff9db0"
                    font.pixelSize: 14; verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                }
            }

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
                    width: Math.min(660, parent.width - 72)
                    anchors.horizontalCenter: parent.horizontalCenter
                    sourceComponent: root.tab === 0 ? statusPage
                                   : root.tab === 1 ? availablePage
                                   : root.tab === 2 ? historyPage : schedulePage

                    // Each page fades and lifts as it is swapped in, so
                    // moving between them reads as one window changing rather
                    // than four unrelated screens.
                    opacity: 0
                    y: 10
                    onSourceComponentChanged: swap.restart()
                    Component.onCompleted: swap.start()
                    NumberAnimation on opacity {
                        id: swap
                        running: false
                        from: 0; to: 1; duration: 220
                        easing.type: Easing.OutCubic
                    }
                    Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    onOpacityChanged: if (opacity > 0.99) y = 0
                }
                }
            }
        }
    }

    // ---- status ------------------------------------------------------------
    Component {
        id: statusPage
        ColumnLayout {
            spacing: 20
            Item { Layout.preferredHeight: 30 }

            RowLayout {
                spacing: 16
                Item {
                    width: 68; height: 68
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b,
                                       backend.updates.length ? 0.16 : 0.0)
                        border.width: 2
                        border.color: backend.busy ? root.dim
                                    : backend.updates.length ? root.accent : root.good
                        Behavior on border.color { ColorAnimation { duration: 260 } }
                        Behavior on color { ColorAnimation { duration: 260 } }
                    }
                    // A sweep round the ring while checking, rather than a
                    // spinner bolted on beside it. The ring already is the
                    // status; it should be the thing that moves.
                    Item {
                        anchors.fill: parent
                        opacity: backend.busy ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        RotationAnimator on rotation {
                            running: backend.busy
                            from: 0; to: 360; duration: 1200; loops: Animation.Infinite
                        }
                        Rectangle {
                            width: 7; height: 7; radius: 3.5
                            color: root.accent
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: -3
                        }
                    }
                    QQC2.Label {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: backend.busy ? "" : (backend.updates.length ? backend.updates.length : "✓")
                        color: backend.updates.length ? root.accent : root.good
                        font.pixelSize: backend.updates.length ? 26 : 30
                        font.weight: Font.DemiBold
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                }
                ColumnLayout {
                    spacing: 3
                    QQC2.Label {
                        text: backend.busy ? "Checking…"
                            : backend.updates.length === 0 ? "Everything is up to date"
                            : backend.updates.length === 1 ? "1 update available"
                            : backend.updates.length + " updates available"
                        color: root.text; font.pixelSize: 30; font.weight: Font.Light
                    }
                    QQC2.Label {
                        // Read the setting rather than asserting the default.
                        // This claimed updates install overnight even when the
                        // user had turned that off on the very next tab.
                        text: {
                            if (backend.updates.length) {
                                return "A restore point is taken before anything is installed."
                            }
                            var s = backend.schedule()
                            return s && s.autoApply
                                ? "Updates install automatically at " + (s.window || "03:00") + "."
                                : "Automatic updates are off. You install them when you choose to."
                        }
                        color: root.dim; font.pixelSize: 14
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: rr.implicitHeight + 26
                radius: 11
                visible: backend.restartRequired
                color: Qt.rgba(root.warn.r, root.warn.g, root.warn.b, 0.12)
                border.width: 1
                border.color: Qt.rgba(root.warn.r, root.warn.g, root.warn.b, 0.4)
                ColumnLayout {
                    id: rr
                    anchors.fill: parent; anchors.margins: 13; spacing: 3
                    QQC2.Label { text: "A restart is needed"; color: root.warn; font.pixelSize: 16; font.weight: Font.DemiBold }
                    QQC2.Label {
                        text: "Some of these replace parts of the running system. They install now and take effect when you restart."
                        color: root.dim; font.pixelSize: 14; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
            }

            // Facts under the headline, so the landing screen states something
            // rather than being a button with a sentence over it.
            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                columns: width > 470 ? 3 : 1
                columnSpacing: 12
                rowSpacing: 12

                Repeater {
                    model: [
                        { k: "Held back",
                          v: backend.updates.filter(function(u){ return u.held !== "" }).length.toString(),
                          d: "waiting on a manual step" },
                        { k: "Needs a restart",
                          v: backend.updates.filter(function(u){ return u.restart }).length.toString(),
                          d: "replaces part of the running system" },
                        { k: "Restore points",
                          v: backend.history.length.toString(),
                          d: "points you can go back to" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        // Sized from its content, because the caption wraps to
                        // two or three lines depending on column width and a
                        // fixed height pushed the last line outside the box.
                        // fillHeight then squares the row off, so one taller
                        // caption does not leave the row ragged.
                        Layout.fillHeight: true
                        implicitHeight: tile.implicitHeight + 30
                        radius: 12
                        color: root.card
                        ColumnLayout {
                            id: tile
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 15
                            spacing: 2
                            QQC2.Label {
                                text: modelData.v; color: root.text
                                font.pixelSize: 26; font.weight: Font.Light
                            }
                            QQC2.Label {
                                text: modelData.k; color: root.text
                                font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                            QQC2.Label {
                                text: modelData.d; color: root.dim; font.pixelSize: 12
                                wrapMode: Text.WordWrap; Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            RowLayout {
                spacing: 10
                Btn {
                    text: backend.applying ? "Installing…" : "Install now"
                    enabled: !backend.applying && !backend.busy && backend.updates.length > 0
                    onClicked: backend.apply()
                }
                Btn {
                    text: "Check again"; quiet: true
                    enabled: !backend.busy && !backend.applying
                    onClicked: backend.check()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 190
                radius: 10
                visible: backend.log !== ""
                color: "#1e1218"
                border.width: 1; border.color: root.line
                QQC2.ScrollView {
                    anchors.fill: parent; anchors.margins: 10; clip: true
                    QQC2.TextArea {
                        readOnly: true; text: backend.log; color: root.dim
                        font.family: "monospace"; font.pixelSize: 12
                        background: null; wrapMode: Text.NoWrap
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ---- available ---------------------------------------------------------
    Component {
        id: availablePage
        ColumnLayout {
            spacing: 16
            Item { Layout.preferredHeight: 30 }
            Head {
                title: "What will be installed"
                subtitle: "Version numbers tell you nothing on their own, so each one says what it is and what on this machine needs it."
            }

            QQC2.Label {
                visible: backend.updates.length === 0 && !backend.busy
                text: "Nothing to install."
                color: root.dim; font.pixelSize: 16
            }

            Repeater {
                model: backend.updates
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: c.implicitHeight + 26
                    radius: 11
                    color: root.card
                    opacity: modelData.held !== "" ? 0.62 : 1.0
                    ColumnLayout {
                        id: c
                        anchors.fill: parent; anchors.margins: 13; spacing: 5
                        RowLayout {
                            spacing: 9
                            QQC2.Label {
                                text: modelData.name; color: root.text
                                font.pixelSize: 16; font.weight: Font.DemiBold
                            }
                            QQC2.Label {
                                text: modelData.old + " → " + modelData["new"]
                                color: root.dim; font.pixelSize: 12
                                font.family: "monospace"
                            }
                            Item { Layout.fillWidth: true }
                            Pill { visible: modelData.restart; label: "RESTART"; tint: root.warn }
                            Pill { visible: modelData.held !== ""; label: "HELD"; tint: root.dim }
                        }
                        QQC2.Label {
                            visible: modelData.summary !== ""
                            text: modelData.summary; color: root.dim
                            font.pixelSize: 14; wrapMode: Text.WordWrap; Layout.fillWidth: true
                        }
                        QQC2.Label {
                            visible: modelData.neededBy !== ""
                            text: "Needed by " + modelData.neededBy
                            color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.8)
                            font.pixelSize: 12
                        }
                        QQC2.Label {
                            visible: modelData.held !== ""
                            text: modelData.held; color: root.warn; font.pixelSize: 12
                            wrapMode: Text.WordWrap; Layout.fillWidth: true
                        }
                    }
                }
            }

            ColumnLayout {
                visible: backend.holds.length > 0
                Layout.fillWidth: true
                spacing: 8
                QQC2.Label {
                    text: "Why some are held"; color: root.text
                    font.pixelSize: 16; font.weight: Font.DemiBold
                    topPadding: 8
                }
                Repeater {
                    model: backend.holds
                    delegate: QQC2.Label {
                        required property var modelData
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: root.dim; font.pixelSize: 14
                        // The engine puts the affected package names in
                        // "reason" and this dropped them, so the one thing
                        // this section exists to say -- which of your updates
                        // it is about -- never reached the screen.
                        text: (modelData.reason ? modelData.reason + ". " : "")
                            + "Arch published a manual step: " + modelData.title
                    }
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.8)
                    font.pixelSize: 12
                    text: "Everything else installs as normal. Held packages wait until the step has been done."
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ---- history -----------------------------------------------------------
    Component {
        id: historyPage
        ColumnLayout {
            spacing: 16
            Item { Layout.preferredHeight: 30 }
            Head {
                title: "Restore points"
                subtitle: "One is taken before every change. Going back restarts the machine and undoes everything after that point. The files in your home folder are not touched."
            }
            // Taking one before doing something risky is the reason people
            // want restore points at all, and until now the only way to get
            // one was to install a package.
            RowLayout {
                spacing: 10
                QQC2.TextField {
                    id: newPointName
                    Layout.preferredWidth: 300
                    placeholderText: "What are you about to change?"
                    color: root.text
                    font.pixelSize: 13
                    background: Rectangle {
                        radius: 8; color: root.card
                        border.width: 1
                        border.color: newPointName.activeFocus ? root.accent : root.line
                    }
                }
                Btn {
                    text: "Save a restore point"
                    enabled: !backend.busy
                    onClicked: {
                        backend.createRestorePoint(newPointName.text)
                        newPointName.text = ""
                    }
                }
            }
            QQC2.Label {
                visible: backend.error !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: backend.error
                color: "#ff9db0"; font.pixelSize: 12
            }
            QQC2.Label {
                visible: backend.history.length === 0 && !backend.busy
                text: "No restore points yet."
                color: root.dim; font.pixelSize: 16
            }
            Repeater {
                model: backend.history
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 58
                    radius: 10
                    color: root.card
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 13; spacing: 12
                        Rectangle {
                            width: 8; height: 8; radius: 4; color: root.accent
                            Layout.alignment: Qt.AlignVCenter
                        }
                        ColumnLayout {
                            spacing: 2
                            QQC2.Label {
                                text: modelData.description === "" ? "Restore point" : modelData.description
                                color: root.text; font.pixelSize: 14
                            }
                            QQC2.Label { text: modelData.date; color: root.dim; font.pixelSize: 12 }
                        }
                        Item { Layout.fillWidth: true }
                        QQC2.Label {
                            text: "#" + modelData.number
                            color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.7)
                            font.pixelSize: 12; font.family: "monospace"
                        }
                        // The action the whole tab exists for. Without it this
                        // was a list of restore points and a sentence telling
                        // people to find the boot menu themselves -- which the
                        // documentation itself calls not a safety net.
                        QQC2.Button {
                            text: "Delete"
                            enabled: !backend.busy
                            onClicked: root.confirmDelete = modelData
                            contentItem: QQC2.Label {
                                text: parent.text
                                color: root.dim; font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 7
                                color: parent.down ? root.cardUp : "transparent"
                                border.width: 1; border.color: root.line
                            }
                            padding: 8; leftPadding: 12; rightPadding: 12
                        }
                        QQC2.Button {
                            text: "Go back to this"
                            enabled: !backend.busy
                            onClicked: root.confirmRollback = modelData
                            contentItem: QQC2.Label {
                                text: parent.text
                                color: root.text; font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 7
                                color: parent.down ? root.cardUp
                                     : parent.hovered ? Qt.rgba(1, 1, 1, 0.10)
                                     : Qt.rgba(1, 1, 1, 0.05)
                                border.width: 1; border.color: root.line
                            }
                            padding: 8; leftPadding: 14; rightPadding: 14
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ---- schedule ----------------------------------------------------------
    Component {
        id: schedulePage
        ColumnLayout {
            spacing: 16
            property var s: backend.schedule()
            Item { Layout.preferredHeight: 30 }
            Head {
                title: "When updates install"
                subtitle: "These are the same settings as the SakuraOS page in System Settings. Changing them here changes them there."
            }

            QQC2.CheckBox {
                id: autoBox
                text: "Install updates automatically"
                checked: parent.s.autoApply
                contentItem: QQC2.Label {
                    text: parent.text; color: root.text; font.pixelSize: 14
                    leftPadding: parent.indicator.width + 8
                    verticalAlignment: Text.AlignVCenter
                }
            }
            // The canary fleet does not exist. Nothing anywhere holds an
            // update back for want of evidence, so a switch offering that
            // choice is describing infrastructure, not controlling it. Left
            // visible because it is genuinely planned, switched off because
            // the alternative is a promise about updates that is not kept.
            QQC2.CheckBox {
                id: canaryBox
                enabled: false
                text: "Only updates that were tested first"
                checked: false
                contentItem: QQC2.Label {
                    text: parent.text; color: parent.enabled ? root.text : root.dim
                    font.pixelSize: 14
                    leftPadding: parent.indicator.width + 8
                    verticalAlignment: Text.AlignVCenter
                }
            }
            QQC2.CheckBox {
                id: acBox
                enabled: autoBox.checked
                text: "Only when plugged in"
                checked: parent.s.acOnly
                contentItem: QQC2.Label {
                    text: parent.text; color: parent.enabled ? root.text : root.dim
                    font.pixelSize: 14
                    leftPadding: parent.indicator.width + 8
                    verticalAlignment: Text.AlignVCenter
                }
            }
            RowLayout {
                spacing: 10
                QQC2.Label { text: "Install at"; color: root.dim; font.pixelSize: 14 }
                QQC2.TextField {
                    id: timeField
                    enabled: autoBox.checked
                    Layout.preferredWidth: 90
                    // Follows this machine's clock. It was fixed at 24-hour,
                    // so somebody who chose a 12-hour clock during the install
                    // was asked for the update time in the other format, with
                    // no AM or PM to pick.
                    inputMask: backend.uses24Hour ? "99:99" : "x9:99"
                    color: root.text
                    // The stored value is always 24-hour "HH:MM": it goes into
                    // sakura.conf and is read by a timer, so only the display
                    // changes.
                    Component.onCompleted: text = root.displayTime(parent.parent.s.window)
                    background: Rectangle {
                        radius: 7; color: root.card
                        border.width: 1; border.color: parent.activeFocus ? root.accent : root.line
                    }
                }
                QQC2.Button {
                    id: meridiem
                    property string label: root.meridiemOf(timeField.parent.parent.s.window)
                    visible: !backend.uses24Hour
                    enabled: autoBox.checked
                    text: label
                    implicitWidth: 54
                    onClicked: label = (label === "AM") ? "PM" : "AM"
                }
            }
            QQC2.Label {
                Layout.maximumWidth: 520
                wrapMode: Text.WordWrap
                text: "SakuraOS installs each update on its own machines and restarts "
                    + "them before offering it to yours, and holds back anything that "
                    + "breaks. Updates are also held back when Arch publishes a notice "
                    + "about them."
                color: root.dim; font.pixelSize: 12
            }
            Btn {
                text: "Save"
                Layout.topMargin: 6
                onClicked: backend.setSchedule({
                    "autoApply": autoBox.checked,
                    "canary": canaryBox.checked,
                    "acOnly": acBox.checked,
                    "window": root.storedTime(timeField.text, meridiem.label)
                })
            }
            Item { Layout.fillHeight: true }
        }
    }
    // ---- confirm deleting a restore point -----------------------------------
    Rectangle {
        anchors.fill: parent
        z: 200
        visible: root.confirmDelete !== null
        color: Qt.rgba(0, 0, 0, 0.6)
        TapHandler { onTapped: {} }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(500, parent.width - 70)
            implicitHeight: delBody.implicitHeight + 46
            radius: 16
            color: root.card
            border.width: 1; border.color: root.line

            ColumnLayout {
                id: delBody
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: parent.top; anchors.margins: 23
                spacing: 13

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Delete the restore point from "
                        + (root.confirmDelete ? (root.confirmDelete.date || "this point") : "") + "?"
                    color: root.text
                    font.pixelSize: 20; font.weight: Font.Light
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    // Says what is lost, which is the ability to return -- not
                    // any of the files the machine is holding right now.
                    text: "Nothing on this system changes. What is lost is the "
                        + "option of coming back to how things were at that moment."
                    color: root.dim; font.pixelSize: 13
                }
                RowLayout {
                    Layout.topMargin: 3
                    Layout.alignment: Qt.AlignRight
                    spacing: 10
                    QQC2.Button {
                        text: "Cancel"
                        onClicked: root.confirmDelete = null
                        contentItem: QQC2.Label {
                            text: parent.text; color: root.text; font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 8; color: parent.down ? root.cardUp : "transparent"
                            border.width: 1; border.color: root.line
                        }
                        padding: 10; leftPadding: 20; rightPadding: 20
                    }
                    QQC2.Button {
                        text: "Delete"
                        enabled: !backend.busy
                        onClicked: {
                            backend.deleteRestorePoint(String(root.confirmDelete.number))
                            root.confirmDelete = null
                        }
                        contentItem: QQC2.Label {
                            text: parent.text; color: "#ffffff"
                            font.pixelSize: 13; font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle { radius: 8; color: "#c8524f" }
                        padding: 10; leftPadding: 20; rightPadding: 20
                    }
                }
            }
        }
    }

    // ---- confirm a rollback -------------------------------------------------
    Rectangle {
        anchors.fill: parent
        z: 200
        visible: root.confirmRollback !== null
        color: Qt.rgba(0, 0, 0, 0.6)
        TapHandler { onTapped: {} }          // swallow clicks on what is behind

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(540, parent.width - 70)
            implicitHeight: body.implicitHeight + 46
            radius: 16
            color: root.card
            border.width: 1; border.color: root.line

            ColumnLayout {
                id: body
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: parent.top; anchors.margins: 23
                spacing: 14

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Go back to " + (root.confirmRollback
                          ? (root.confirmRollback.date || "this restore point") : "") + "?"
                    color: root.text
                    font.pixelSize: 21; font.weight: Font.Light
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.confirmRollback && root.confirmRollback.description
                          ? root.confirmRollback.description : ""
                    visible: text !== ""
                    color: root.accent; font.pixelSize: 13
                }
                // What it does, in the terms a person actually cares about.
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Every program and system change made since then will be undone. "
                        + "Your documents, photos and other personal files are not part of a "
                        + "restore point and are left exactly as they are.\n\n"
                        + "The machine restarts to do this, and it cannot be stopped once it "
                        + "begins."
                    color: root.dim; font.pixelSize: 13
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: backend.error !== ""
                    wrapMode: Text.WordWrap
                    text: backend.error
                    color: "#ff9db0"; font.pixelSize: 12
                }
                RowLayout {
                    Layout.topMargin: 3
                    Layout.alignment: Qt.AlignRight
                    spacing: 10
                    QQC2.Button {
                        text: "Cancel"
                        onClicked: root.confirmRollback = null
                        contentItem: QQC2.Label {
                            text: parent.text; color: root.text
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 8; color: parent.down ? root.cardUp : "transparent"
                            border.width: 1; border.color: root.line
                        }
                        padding: 10; leftPadding: 20; rightPadding: 20
                    }
                    QQC2.Button {
                        text: "Restart and go back"
                        enabled: !backend.busy
                        onClicked: backend.rollback(root.confirmRollback.number)
                        contentItem: QQC2.Label {
                            text: parent.text; color: root.accentText
                            font.pixelSize: 13; font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle { radius: 8; color: root.accent }
                        padding: 10; leftPadding: 20; rightPadding: 20
                    }
                }
            }
        }
    }

}
