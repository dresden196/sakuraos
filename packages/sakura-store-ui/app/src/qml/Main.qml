import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

QQC2.ApplicationWindow {
    id: root
    width: 1180; height: 800
    minimumWidth: 940; minimumHeight: 620
    visible: true
    title: "Sakura Store"
    color: bg

    readonly property color accent: "#ffb7c5"
    readonly property color accentText: "#3a2731"
    readonly property color bg: "#221520"
    readonly property color panel: "#2b1c27"
    readonly property color card: "#372430"
    readonly property color cardUp: "#422c3a"
    readonly property color text: "#f7eff3"
    readonly property color dim: "#c0a9b6"
    readonly property color line: Qt.rgba(1, 1, 1, 0.08)
    readonly property color warn: "#f6c76b"

    property string view: "discover"      // discover | results | app
    property string sourceFilter: "all"
    property string lastQuery: ""

    Component.onCompleted: backend.loadFeatured()

    function stars(v) {
        if (!v) return ""
        var full = Math.round(v)
        return "★★★★★".substring(0, full) + "☆☆☆☆☆".substring(0, 5 - full)
    }
    function compact(n) {
        if (!n) return ""
        if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
        if (n >= 1000) return Math.round(n / 1000) + "k"
        return n.toString()
    }

    // ---- shared -----------------------------------------------------------
    component Chip : Rectangle {
        property string label
        property color tint: root.dim
        implicitWidth: cl.implicitWidth + 20
        implicitHeight: 24
        radius: 6
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.14)
        QQC2.Label {
            id: cl; anchors.centerIn: parent; text: label; color: tint
            font.pixelSize: 12; font.weight: Font.DemiBold
        }
    }

    component Action : QQC2.Button {
        property bool quiet: false
        padding: 12; leftPadding: 26; rightPadding: 26
        contentItem: QQC2.Label {
            text: parent.text
            color: !parent.enabled ? root.dim : (parent.quiet ? root.text : root.accentText)
            font.pixelSize: 15; font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 9
            color: !parent.enabled ? root.card
                 : parent.quiet ? (parent.down ? root.cardUp : "transparent")
                 : (parent.down ? Qt.darker(root.accent, 1.15) : root.accent)
            border.width: parent.quiet ? 1 : 0
            border.color: root.line
        }
    }

    // An app tile. Used in search results and in the front-page rows.
    component Tile : Rectangle {
        property var appData
        signal opened()
        width: 250; height: 120
        radius: 14
        color: hov.hovered ? root.cardUp : root.card
        Behavior on color { ColorAnimation { duration: 120 } }

        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: opened() }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 13
            Image {
                Layout.preferredWidth: 52; Layout.preferredHeight: 52
                Layout.alignment: Qt.AlignTop
                source: appData.icon || ""
                sourceSize: Qt.size(104, 104)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                QQC2.Label {
                    Layout.fillWidth: true
                    text: appData.name || ""
                    color: root.text
                    font.pixelSize: 15; font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: appData.summary || ""
                    color: root.dim; font.pixelSize: 12
                    wrapMode: Text.WordWrap; maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    spacing: 8
                    QQC2.Label {
                        visible: !!appData.rating
                        text: root.stars(appData.rating) + "  " + (appData.rating || "")
                        color: root.accent; font.pixelSize: 11
                    }
                    QQC2.Label {
                        visible: !!appData.installed
                        text: "Installed"; color: "#8fd3a4"; font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    // ---- window -----------------------------------------------------------
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // rail
        Rectangle {
            Layout.preferredWidth: 208
            Layout.fillHeight: true
            color: panel

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 22

                RowLayout {
                    spacing: 10
                    Rectangle {
                        width: 26; height: 26; radius: 13; color: root.accent
                        QQC2.Label { anchors.centerIn: parent; text: "✿"
                                     color: root.accentText; font.pixelSize: 15 }
                    }
                    QQC2.Label { text: "Store"; color: root.text
                                 font.pixelSize: 17; font.weight: Font.DemiBold }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: [{k: "discover", n: "Discover"},
                                {k: "installed", n: "Installed"}]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 36
                            radius: 8
                            color: root.view === modelData.k
                                   ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                                   : "transparent"
                            QQC2.Label {
                                anchors.verticalCenter: parent.verticalCenter
                                x: 12
                                text: modelData.n
                                color: root.view === modelData.k ? root.accent : root.dim
                                font.pixelSize: 14
                                font.weight: root.view === modelData.k ? Font.DemiBold : Font.Normal
                            }
                            TapHandler { onTapped: root.view = modelData.k }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 9
                    QQC2.Label {
                        text: "SOURCES"; color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, .75)
                        font.pixelSize: 11; font.weight: Font.DemiBold
                        font.letterSpacing: 1.4
                    }
                    Repeater {
                        model: [{k: "all", n: "Everything"},
                                {k: "flatpak", n: "Flatpak"},
                                {k: "appimage", n: "AppImage"},
                                {k: "snap", n: "Snap"},
                                {k: "aur", n: "AUR"}]
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 9
                            Rectangle {
                                width: 15; height: 15; radius: 4
                                color: root.sourceFilter === modelData.k ? root.accent : "transparent"
                                border.width: 1
                                border.color: root.sourceFilter === modelData.k ? root.accent : root.line
                                QQC2.Label {
                                    anchors.centerIn: parent; text: "✓"
                                    visible: root.sourceFilter === modelData.k
                                    color: root.accentText; font.pixelSize: 10
                                }
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: modelData.n
                                color: root.sourceFilter === modelData.k ? root.text : root.dim
                                font.pixelSize: 13
                            }
                            TapHandler {
                                onTapped: {
                                    root.sourceFilter = modelData.k
                                    if (root.lastQuery) backend.search(root.lastQuery, modelData.k)
                                }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }
                    }
                    QQC2.Label {
                        visible: root.sourceFilter === "aur"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "AUR packages are build scripts written by other users. Nobody reviews them."
                        color: root.warn; font.pixelSize: 11
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }

        // main
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // search bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 66
                color: root.bg
                RowLayout {
                    anchors.centerIn: parent
                    width: Math.min(940, parent.width) - 52
                    height: parent.height
                    spacing: 12
                    QQC2.Button {
                        visible: root.view === "app"
                        text: "‹"
                        onClicked: root.view = root.lastQuery ? "results" : "discover"
                        contentItem: QQC2.Label { text: parent.text; color: root.text
                                                  font.pixelSize: 22
                                                  horizontalAlignment: Text.AlignHCenter }
                        background: Rectangle { radius: 8; color: parent.down ? root.cardUp : "transparent" }
                        implicitWidth: 36
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: 10
                        color: root.card
                        border.width: field.activeFocus ? 2 : 1
                        border.color: field.activeFocus ? root.accent : root.line
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14; anchors.rightMargin: 10
                            spacing: 8
                            QQC2.Label { text: "⌕"; color: root.dim; font.pixelSize: 18 }
                            QQC2.TextField {
                                id: field
                                Layout.fillWidth: true
                                placeholderText: "Search for applications"
                                placeholderTextColor: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, .65)
                                color: root.text
                                font.pixelSize: 14
                                background: null
                                onAccepted: {
                                    root.lastQuery = text
                                    root.view = "results"
                                    backend.search(text, root.sourceFilter)
                                }
                            }
                        }
                    }
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
                    width: Math.min(940, parent.width)
                    anchors.horizontalCenter: parent.horizontalCenter
                    sourceComponent: root.view === "app" ? appPage
                                   : root.view === "results" ? resultsPage
                                   : root.view === "installed" ? installedPage
                                   : discoverPage
                }
                }
            }
        }
    }

    // ---- discover ---------------------------------------------------------
    Component {
        id: discoverPage
        ColumnLayout {
            spacing: 26

            // The carousel. Screenshots at full width, because an application
            // is a thing you look at before it is a thing you read about.
            Rectangle {
                id: carousel
                Layout.fillWidth: true
                Layout.leftMargin: 26; Layout.rightMargin: 26
                Layout.topMargin: 4
                implicitHeight: 320
                radius: 18
                color: root.card
                clip: true
                visible: backend.featured.length > 0

                property int current: 0
                Timer {
                    running: carousel.visible && backend.featured.length > 1
                    interval: 6000; repeat: true
                    onTriggered: carousel.current =
                        (carousel.current + 1) % backend.featured.length
                }

                Repeater {
                    model: backend.featured
                    delegate: Item {
                        required property int index
                        required property var modelData
                        anchors.fill: parent
                        // The incoming slide sits above the outgoing one.
                        // At equal depth both are semi-transparent mid-fade
                        // and the old text ghosts through the new.
                        z: index === carousel.current ? 1 : 0
                        opacity: index === carousel.current ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

                        Image {
                            anchors.fill: parent
                            source: modelData.icon || ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            opacity: 0.20
                        }
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(0.13,0.08,0.12,0.55) }
                                GradientStop { position: 1; color: Qt.rgba(0.13,0.08,0.12,0.94) }
                            }
                        }
                        ColumnLayout {
                            anchors.left: parent.left; anchors.bottom: parent.bottom
                            anchors.margins: 34
                            anchors.right: parent.right
                            spacing: 9
                            RowLayout {
                                spacing: 16
                                Image {
                                    Layout.preferredWidth: 68; Layout.preferredHeight: 68
                                    source: modelData.icon || ""
                                    sourceSize: Qt.size(136, 136)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                                ColumnLayout {
                                    spacing: 3
                                    QQC2.Label {
                                        text: modelData.name || ""
                                        color: root.text
                                        font.pixelSize: 34; font.weight: Font.Light
                                    }
                                    QQC2.Label {
                                        text: modelData.developer || ""
                                        color: root.dim; font.pixelSize: 14
                                    }
                                }
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                Layout.maximumWidth: 560
                                text: modelData.summary || ""
                                color: root.dim; font.pixelSize: 15
                                wrapMode: Text.WordWrap; maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                spacing: 14
                                Action {
                                    text: "View"
                                    onClicked: { backend.openApp(modelData.id); root.view = "app" }
                                }
                                QQC2.Label {
                                    visible: !!modelData.rating
                                    text: root.stars(modelData.rating) + "   " + (modelData.rating || "") +
                                          "  ·  " + (modelData.rating_count || 0) + " reviews"
                                    color: root.accent; font.pixelSize: 13
                                }
                            }
                        }
                    }
                }

                Row {
                    anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 18
                    spacing: 7
                    Repeater {
                        model: backend.featured.length
                        delegate: Rectangle {
                            required property int index
                            width: index === carousel.current ? 20 : 7
                            height: 7; radius: 3.5
                            color: index === carousel.current
                                   ? root.accent : Qt.rgba(1,1,1,0.28)
                            Behavior on width { NumberAnimation { duration: 260 } }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 26; Layout.rightMargin: 26
                spacing: 13
                QQC2.Label {
                    text: "Popular right now"
                    color: root.text; font.pixelSize: 22; font.weight: Font.Light
                }
                Flow {
                    id: popularFlow
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    spacing: 13
                    Repeater {
                        model: backend.featured
                        delegate: Tile {
                            required property var modelData
                            appData: modelData
                            onOpened: { backend.openApp(modelData.id); root.view = "app" }
                        }
                    }
                }
            }
            Item { Layout.preferredHeight: 30 }
        }
    }

    // ---- results ----------------------------------------------------------
    Component {
        id: resultsPage
        ColumnLayout {
            spacing: 15
            Layout.fillWidth: true

            QQC2.Label {
                Layout.leftMargin: 26; Layout.topMargin: 6
                text: backend.searching ? "Searching…"
                    : backend.results.length + " result" + (backend.results.length === 1 ? "" : "s")
                color: root.text; font.pixelSize: 22; font.weight: Font.Light
            }

            // A source that could not be reached is stated, never folded into
            // "no results" -- that silence is what makes a store feel broken.
            Repeater {
                model: Object.keys(backend.unavailable)
                delegate: QQC2.Label {
                    required property var modelData
                    Layout.leftMargin: 26
                    text: modelData + " could not be reached (" +
                          backend.unavailable[modelData] + "). Its results are missing."
                    color: root.warn; font.pixelSize: 13
                }
            }

            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                Layout.leftMargin: 26; Layout.rightMargin: 26
                spacing: 13
                Repeater {
                    model: backend.results
                    delegate: Tile {
                        required property var modelData
                        appData: modelData
                        onOpened: { backend.openApp(modelData.id); root.view = "app" }
                    }
                }
            }
            Item { Layout.preferredHeight: 30 }
        }
    }

    // ---- installed --------------------------------------------------------
    Component {
        id: installedPage
        ColumnLayout {
            spacing: 15
            QQC2.Label {
                Layout.leftMargin: 26; Layout.topMargin: 6
                text: "Installed"
                color: root.text; font.pixelSize: 22; font.weight: Font.Light
            }
            QQC2.Label {
                Layout.leftMargin: 26
                Layout.maximumWidth: 520
                wrapMode: Text.WordWrap
                text: "Everything you have installed, from every source. Applications update themselves unless you turn that off."
                color: root.dim; font.pixelSize: 14
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ---- app page ---------------------------------------------------------
    Component {
        id: appPage
        ColumnLayout {
            spacing: 22
            property var a: backend.app

            QQC2.Label {
                visible: backend.loadingApp
                Layout.leftMargin: 26; Layout.topMargin: 20
                text: "Loading…"; color: root.dim; font.pixelSize: 16
            }

            // header
            RowLayout {
                visible: !backend.loadingApp && !!parent.a.id
                Layout.fillWidth: true
                Layout.leftMargin: 26; Layout.rightMargin: 26
                Layout.topMargin: 8
                spacing: 22
                Image {
                    Layout.preferredWidth: 96; Layout.preferredHeight: 96
                    Layout.alignment: Qt.AlignTop
                    source: parent.parent.a.icon || ""
                    sourceSize: Qt.size(192, 192)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 7
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: parent.parent.parent.a.name || ""
                        color: root.text; font.pixelSize: 32; font.weight: Font.Light
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        spacing: 14
                        QQC2.Label {
                            text: parent.parent.parent.parent.a.developer || ""
                            color: root.accent; font.pixelSize: 15
                        }
                        QQC2.Label {
                            visible: !!parent.parent.parent.parent.a.rating
                            text: root.stars(parent.parent.parent.parent.a.rating) + "  "
                                  + (parent.parent.parent.parent.a.rating || "")
                                  + "  ·  " + (parent.parent.parent.parent.a.rating_count || 0)
                                  + " reviews"
                            color: root.dim; font.pixelSize: 14
                        }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: parent.parent.parent.a.summary || ""
                        color: root.dim; font.pixelSize: 15
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        spacing: 12
                        Layout.topMargin: 6
                        Action {
                            text: backend.busy ? "Installing…" : "Install"
                            enabled: !backend.busy
                            onClicked: backend.install(parent.parent.parent.parent.a.id, "flatpak")
                        }
                        Action {
                            text: "Permissions"; quiet: true
                            // Meaningless for an app that is not installed --
                            // there is no sandbox to adjust yet.
                            visible: !!parent.parent.parent.parent.a.installed
                            onClicked: backend.openPermissions(parent.parent.parent.parent.a.id)
                        }
                        Chip {
                            visible: !!parent.parent.parent.parent.a.license
                            label: parent.parent.parent.parent.a.license || ""
                        }
                    }
                }
            }

            // progress
            ColumnLayout {
                visible: backend.busy || backend.error !== ""
                Layout.fillWidth: true
                Layout.leftMargin: 26; Layout.rightMargin: 26
                spacing: 7
                RowLayout {
                    spacing: 10
                    QQC2.Label {
                        text: backend.error !== "" ? "Could not install"
                            : backend.stage.charAt(0).toUpperCase() + backend.stage.slice(1)
                        color: backend.error !== "" ? "#ff9db0" : root.text
                        font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    QQC2.Label {
                        text: backend.progressDetail
                        color: root.dim; font.pixelSize: 12
                        elide: Text.ElideRight; Layout.fillWidth: true
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 520
                    implicitHeight: 5; radius: 2.5
                    color: root.card
                    Rectangle {
                        width: parent.width * (backend.percent / 100)
                        height: parent.height; radius: 2.5; color: root.accent
                        Behavior on width { NumberAnimation { duration: 240 } }
                    }
                }
                QQC2.Label {
                    visible: backend.error !== ""
                    Layout.fillWidth: true
                    text: backend.error; color: "#ff9db0"; font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }

            // screenshots
            ColumnLayout {
                visible: (parent.a.screenshots || []).length > 0
                Layout.fillWidth: true
                spacing: 11
                QQC2.Label {
                    Layout.leftMargin: 26
                    text: "Screenshots"; color: root.text
                    font.pixelSize: 19; font.weight: Font.Light
                }
                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 300
                    clip: true
                    Row {
                        spacing: 14
                        leftPadding: 26; rightPadding: 26
                        Repeater {
                            model: parent.parent.parent.a.screenshots || []
                            delegate: Rectangle {
                                required property var modelData
                                width: 470; height: 280
                                radius: 12; color: root.card; clip: true
                                Image {
                                    anchors.fill: parent
                                    source: modelData.url || ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                            }
                        }
                    }
                }
            }

            // description
            QQC2.Label {
                visible: !!parent.a.description
                Layout.fillWidth: true
                Layout.leftMargin: 26; Layout.rightMargin: 26
                Layout.maximumWidth: 720
                text: parent.a.description || ""
                textFormat: Text.RichText
                color: root.dim; font.pixelSize: 15
                wrapMode: Text.WordWrap
                lineHeight: 1.35
            }

            // ratings and reviews
            ColumnLayout {
                visible: !!parent.a.rating || (parent.a.reviews || []).length > 0
                Layout.fillWidth: true
                Layout.leftMargin: 26; Layout.rightMargin: 26
                spacing: 13

                RowLayout {
                    spacing: 26
                    ColumnLayout {
                        spacing: 2
                        QQC2.Label {
                            text: (parent.parent.parent.parent.a.rating || "—").toString()
                            color: root.text; font.pixelSize: 40; font.weight: Font.Light
                        }
                        QQC2.Label {
                            text: root.stars(parent.parent.parent.parent.a.rating)
                            color: root.accent; font.pixelSize: 15
                        }
                        QQC2.Label {
                            text: (parent.parent.parent.parent.a.rating_count || 0) + " reviews"
                            color: root.dim; font.pixelSize: 12
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        QQC2.Label {
                            text: "Shared with GNOME Software and Discover"
                            color: root.dim; font.pixelSize: 13
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: "Reviews come from the Open Desktop Ratings Service, so a review written here helps everyone using Linux — not just SakuraOS."
                            color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, .8)
                            font.pixelSize: 12
                        }
                    }
                }

                Repeater {
                    model: parent.parent.a.reviews || []
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.maximumWidth: 720
                        implicitHeight: rv.implicitHeight + 26
                        radius: 11
                        color: root.card
                        ColumnLayout {
                            id: rv
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top; anchors.margins: 13
                            spacing: 4
                            RowLayout {
                                spacing: 10
                                QQC2.Label {
                                    text: root.stars(modelData.rating)
                                    color: root.accent; font.pixelSize: 12
                                }
                                QQC2.Label {
                                    text: modelData.summary || ""
                                    color: root.text; font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight; Layout.fillWidth: true
                                }
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: modelData.text || ""
                                color: root.dim; font.pixelSize: 13
                                wrapMode: Text.WordWrap
                            }
                            QQC2.Label {
                                text: (modelData.author || "Anonymous") +
                                      (modelData.version ? "  ·  version " + modelData.version : "")
                                color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, .7)
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
            Item { Layout.preferredHeight: 34 }
        }
    }
}
