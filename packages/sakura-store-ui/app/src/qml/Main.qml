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

    Component.onCompleted: {
        // Opened with an application id -- the handoff from the Windows-program
        // guard. Go straight to that app rather than the front page, and still
        // load the featured list behind it so Back has somewhere to land.
        backend.loadFeatured();
        const wanted = typeof openAppId !== "undefined" ? openAppId : "";
        if (wanted !== "") {
            backend.openApp(wanted);
            root.view = "app";
        }
    }

    // Which source to offer first when an app exists in several. Official
    // packages before Flatpak because they are what SakuraOS actually
    // maintains and what system updates already cover; AUR last because it is
    // unreviewed and off by default.
    readonly property var sourceRank: ({
        "repo": 0, "flatpak": 1, "snap": 2, "appimage": 3, "aur": 4
    })

    function preferredIndex(opts) {
        if (!opts || opts.length === 0)
            return 0;
        // Installed from somewhere already: show that one. The page should
        // describe the machine it is running on before it offers anything --
        // arriving from a link and being shown "Install" for a copy you
        // already have is how somebody ends up with two.
        for (let i = 0; i < opts.length; ++i)
            if (opts[i].installed)
                return i;
        let best = 0, bestRank = 999;
        for (let i = 0; i < opts.length; ++i) {
            const known = root.sourceRank[opts[i].source];
            const rank = known === undefined ? 500 : known;
            if (rank < bestRank) { bestRank = rank; best = i; }
        }
        return best;
    }

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
    // Tiles were a fixed 250px in a variable-width column, so three of them
    // left ~110px of dead space on the right and the whole grid read as
    // shoved to the left. Sizing the cell to the column instead means the
    // grid always fills the width and lines up with the heading above it.
    function stageLabel(stage) {
        return ({
            resolving:   "Working out what is needed",
            downloading: "Downloading",
            installing:  "Installing",
            configuring: "Setting up",
            removing:    "Uninstalling",
            done:        "Done",
        })[stage] || stage
    }

    function cellWidth(avail, cols, gap) {
        return Math.max(180, Math.floor((avail - (cols - 1) * gap) / cols))
    }

    // Where a package comes from is the single most consequential fact about
    // it -- sandboxing, update path and trust model all follow from it -- so
    // it gets a name and a colour rather than being left implicit.
    function sourceLabel(s) {
        return ({ repo: "SakuraOS", flatpak: "Flatpak",
                  aur: "AUR", appimage: "AppImage", snap: "Snap" })[s] || s || ""
    }
    function sourceTint(s) {
        // AUR is deliberately the only warm one: it is the only source that
        // builds unreviewed code on the user's machine.
        return ({ repo: root.accent, flatpak: "#4a90d9", aur: "#d98c3f",
                  appimage: "#8e7cc3", snap: "#7ea67e" })[s] || root.dim
    }

    // A continuously rotating arc. RotationAnimator runs on the render
    // thread, so it stays smooth even while the engine is parsing a response
    // on the GUI thread -- which is exactly when it is on screen.
    component Spinner : Item {
        property int size: 46
        property color tint: root.accent
        implicitWidth: size
        implicitHeight: size

        Canvas {
            id: arc
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var r = width / 2 - 3
                ctx.lineWidth = 3
                ctx.lineCap = "round"
                // Faint full ring, so the gap reads as motion rather than as
                // something half-drawn.
                ctx.strokeStyle = Qt.rgba(tint.r, tint.g, tint.b, 0.18)
                ctx.beginPath()
                ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2)
                ctx.stroke()
                ctx.strokeStyle = tint
                ctx.beginPath()
                ctx.arc(width / 2, height / 2, r, 0, Math.PI * 0.72)
                ctx.stroke()
            }
            RotationAnimator on rotation {
                loops: Animation.Infinite
                from: 0; to: 360
                duration: 950
                running: arc.visible
            }
        }
    }

    // Centred spinner with a line of text under it, for a whole page that has
    // nothing to show yet.
    //
    // An Item with an anchored Column rather than a ColumnLayout: relying on
    // Layout.fillWidth reaching a custom inline component left the spinner
    // pinned to the left edge, and anchoring inside a plain Item does not
    // depend on the attached property propagating at all.
    component Loading : Item {
        id: loadingRoot
        property string label: ""
        Column {
            anchors.centerIn: parent
            spacing: 14
            Spinner { anchors.horizontalCenter: parent.horizontalCenter }
            QQC2.Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: loadingRoot.label
                visible: !!loadingRoot.label
                color: root.dim; font.pixelSize: 14
            }
        }
    }

    // The magnifier was the "\u2315" glyph, whose ink sits high in its em box
    // and moves with whatever font resolves -- no amount of vertical
    // alignment centres a glyph that is not centred in its own metrics.
    // Drawing it means the circle really is in the middle of the item.
    component SearchIcon : Canvas {
        property color tint: root.dim
        property real weight: 1.6
        implicitWidth: 17
        implicitHeight: 17
        onTintChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = tint
            ctx.lineWidth = weight
            ctx.lineCap = "round"
            // Circle plus handle, sized so the whole glyph is centred in the
            // item rather than sitting against one edge.
            var r = width * 0.30
            var cx = width * 0.42
            var cy = height * 0.42
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.stroke()
            ctx.beginPath()
            var d = r * 0.70
            ctx.moveTo(cx + d, cy + d)
            ctx.lineTo(width - weight, height - weight)
            ctx.stroke()
        }
    }

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
        // The Installed list removes things directly rather than routing
        // through the app page: an AUR or repository-only application has no
        // Flathub entry, so that page would have nothing to show.
        property bool showRemove: false
        signal opened()
        signal removeRequested()
        width: 250          // overridden by grids that size cells to fit
        height: 120
        radius: 14
        color: hov.hovered ? root.cardUp : root.card
        Behavior on color { ColorAnimation { duration: 120 } }

        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: opened() }

        // Only on hover: a delete control that is always visible invites
        // being hit by accident.
        Rectangle {
            visible: showRemove && hov.hovered
            anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 7
            width: 26; height: 26; radius: 13
            color: rmHover.hovered ? "#c8524f" : Qt.rgba(1, 1, 1, 0.10)
            Behavior on color { ColorAnimation { duration: 120 } }
            HoverHandler { id: rmHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: removeRequested() }
            QQC2.Label {
                anchors.centerIn: parent
                text: "\u2715"
                color: rmHover.hovered ? "#ffffff" : root.dim
                font.pixelSize: 12; font.weight: Font.DemiBold
            }
        }

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
                    // Which source a result came from, before you click it --
                    // otherwise two identically-named rows are indistinguishable.
                    Rectangle {
                        visible: !!appData.source
                        implicitWidth: sl.implicitWidth + 12
                        implicitHeight: 17
                        radius: 4
                        color: Qt.rgba(root.sourceTint(appData.source).r,
                                       root.sourceTint(appData.source).g,
                                       root.sourceTint(appData.source).b, 0.16)
                        QQC2.Label {
                            id: sl
                            anchors.centerIn: parent
                            text: root.sourceLabel(appData.source)
                            color: root.sourceTint(appData.source)
                            font.pixelSize: 10; font.weight: Font.DemiBold
                        }
                    }
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
                        Layout.topMargin: 6
                        text: "BROWSE"
                        color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, .75)
                        font.pixelSize: 11; font.weight: Font.DemiBold
                        font.letterSpacing: 1.2
                    }
                    Repeater {
                        // Categories come from the engine, which has them for
                        // Flatpak and the repositories. The AUR publishes no
                        // categories at all and Snap uses its own taxonomy, so
                        // neither appears here rather than being faked.
                        model: backend.categories
                        delegate: QQC2.Label {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.leftMargin: 2
                            padding: 5
                            text: modelData.name
                            color: root.view === "category"
                                   && backend.categoryName === modelData.name
                                   ? root.accent : root.text
                            font.pixelSize: 13
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    root.view = "category"
                                    backend.loadCategory(modelData.id, modelData.name)
                                }
                            }
                        }
                    }

                    QQC2.Label {
                        Layout.topMargin: 10
                        text: "SOURCES"; color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, .75)
                        font.pixelSize: 11; font.weight: Font.DemiBold
                        font.letterSpacing: 1.4
                    }
                    Repeater {
                        // Listed in the same order the engine resolves them,
                        // so the sidebar reads as the priority it actually is.
                        // From the engine, which knows what is actually
                        // present -- a hardcoded list showed Snap on machines
                        // with no snapd, where the filter could only ever
                        // return nothing.
                        //
                        // Unavailable sources are shown rather than dropped.
                        // Hiding them means nobody can discover that the AUR
                        // exists, let alone that it is theirs to switch on.
                        // The name comes from sourceLabel so the sidebar and
                        // the chips on the tiles say the same word.
                        model: [{k: "all", n: "Everything", avail: true, why: ""}].concat(
                            (backend.sources || []).map(function (s) {
                                return {k: s.id, n: root.sourceLabel(s.id),
                                        avail: s.available, why: s.reason || ""}
                            }))
                        delegate: RowLayout {
                            required property var modelData
                            readonly property bool usable: modelData.avail
                            Layout.fillWidth: true
                            spacing: 9
                            opacity: usable ? 1 : 0.45
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
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: modelData.n
                                    color: root.sourceFilter === modelData.k ? root.text : root.dim
                                    font.pixelSize: 13
                                }
                                // Why a source cannot be used, said here
                                // rather than by the filter quietly returning
                                // nothing.
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    visible: !!modelData.why
                                    text: modelData.why
                                    wrapMode: Text.WordWrap
                                    color: root.dim; font.pixelSize: 10
                                }
                            }
                            TapHandler {
                                enabled: parent.usable
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
                            SearchIcon {
                                Layout.alignment: Qt.AlignVCenter
                                tint: field.activeFocus ? root.accent : root.dim
                            }
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
                    implicitHeight: pageLoader.implicitHeight + failures.height
                // Anything the engine could not do, on every page rather than
                // only on search results. A blank Discover with no explanation
                // is indistinguishable from a broken store.
                Column {
                    id: failures
                    width: Math.min(940, parent.width)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    spacing: 4
                    Repeater {
                        model: Object.keys(backend.unavailable)
                        delegate: QQC2.Label {
                            required property var modelData
                            width: failures.width - 52
                            x: 26
                            topPadding: 8
                            wrapMode: Text.WordWrap
                            text: modelData === "engine"
                                  ? "The store ran into a problem: "
                                    + backend.unavailable[modelData]
                                  : modelData + " could not be reached ("
                                    + backend.unavailable[modelData]
                                    + "). Its results are missing."
                            color: root.warn; font.pixelSize: 13
                        }
                    }
                }
                Loader {
                    id: pageLoader
                    anchors.top: failures.bottom
                    width: Math.min(940, parent.width)
                    anchors.horizontalCenter: parent.horizontalCenter
                    sourceComponent: root.view === "app" ? appPage
                                   : root.view === "results" ? resultsPage
                                   : root.view === "installed" ? installedPage
                                   : root.view === "category" ? categoryPage
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
                        model: backend.popular
                        delegate: Tile {
                            width: root.cellWidth(popularFlow.width, 3, 13)
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

            Loading {
                visible: backend.searching
                Layout.fillWidth: true
                Layout.preferredHeight: 260
                label: "Asking every enabled source"
            }

            Flow {
                id: resultsFlow
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                Layout.leftMargin: 26; Layout.rightMargin: 26
                spacing: 13
                Repeater {
                    model: backend.results
                    delegate: Tile {
                        width: root.cellWidth(resultsFlow.width, 3, 13)
                        required property var modelData
                        appData: modelData
                        onOpened: { backend.openApp(modelData.id); root.view = "app" }
                    }
                }
            }
            Item { Layout.preferredHeight: 30 }
        }
    }

    Connections {
        target: backend
        // Refresh whatever is on screen. The Installed list is always
        // reloaded because it is now wrong; the app page is re-opened only
        // when it is the page being looked at.
        function onRemoved(id, source) {
            backend.loadInstalled()
            if (root.view === "app") {
                backend.openApp(id)
            }
        }
    }

    // ---- an AppImage opened from a file -------------------------------------
    // Opening a file must never install it on its own. This says what the
    // file is, where it came from, and what installing it will and will not
    // do, and then waits.
    Rectangle {
        id: appImagePrompt
        property string path: typeof openFile !== "undefined" ? openFile : ""
        property bool dismissed: false
        anchors.fill: parent
        z: 150
        visible: path !== "" && !dismissed
        color: Qt.rgba(0, 0, 0, 0.6)
        TapHandler { onTapped: {} }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(560, parent.width - 80)
            implicitHeight: aiBody.implicitHeight + 46
            radius: 16
            color: root.card
            border.width: 1; border.color: root.line

            ColumnLayout {
                id: aiBody
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: parent.top; anchors.margins: 23
                spacing: 13

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Install this AppImage?"
                    color: root.text
                    font.pixelSize: 21; font.weight: Font.Light
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                    text: appImagePrompt.path
                    color: root.accent
                    font.pixelSize: 12; font.family: "monospace"
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "It will be copied to your Applications folder and added to "
                        + "your menu. The file you downloaded stays where it is."
                    color: root.dim; font.pixelSize: 13
                }
                // The thing that makes an AppImage different from everything
                // else in this store, said before it is installed rather than
                // discovered later.
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "An AppImage comes from whoever you downloaded it from. "
                        + "Nothing here reviewed it, and no signature was checked \u2014 "
                        + "install it only if you trust where it came from."
                    color: root.warn; font.pixelSize: 12
                }
                RowLayout {
                    Layout.topMargin: 3
                    Layout.alignment: Qt.AlignRight
                    spacing: 10
                    Action {
                        text: "Cancel"; quiet: true
                        onClicked: appImagePrompt.dismissed = true
                    }
                    Action {
                        text: backend.busy ? "Installing…" : "Install"
                        enabled: !backend.busy
                        onClicked: {
                            backend.installLocalAppImage(appImagePrompt.path)
                            appImagePrompt.dismissed = true
                            root.view = "installed"
                        }
                    }
                }
            }
        }
    }

    // ---- uninstall confirmation ------------------------------------------
    // Shown over everything, because it is the one destructive action in the
    // application and it must not be possible to trigger it by accident.
    Rectangle {
        id: confirmRemove
        anchors.fill: parent
        z: 100
        readonly property var plan: backend.removalPlan
        readonly property string appName: plan && plan.id ? plan.id : ""
        readonly property bool blocked: !!(plan && plan.blocked)
        visible: !!(plan && plan.id)
        color: Qt.rgba(0, 0, 0, 0.55)

        // Swallow clicks so nothing behind the sheet can be reached.
        TapHandler { onTapped: {} }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(560, parent.width - 80)
            implicitHeight: sheet.implicitHeight + 44
            radius: 16
            color: root.card
            border.width: 1
            border.color: root.line

            ColumnLayout {
                id: sheet
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 22
                spacing: 13

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: confirmRemove.blocked
                          ? "Cannot uninstall " + confirmRemove.appName
                          : "Uninstall " + confirmRemove.appName + "?"
                    color: root.text
                    font.pixelSize: 21; font.weight: Font.Light
                }

                Loading {
                    visible: backend.planningRemoval
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    label: "Working out what this would remove"
                }

                // Refused: say why, offer nothing but a way out.
                QQC2.Label {
                    visible: confirmRemove.blocked && !backend.planningRemoval
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: confirmRemove.plan ? (confirmRemove.plan.reason || "") : ""
                    color: root.warn; font.pixelSize: 14
                }

                // Allowed: state exactly what goes, never just "are you sure".
                QQC2.Label {
                    visible: !confirmRemove.blocked && !backend.planningRemoval
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: {
                        var n = confirmRemove.plan && confirmRemove.plan.packages
                                ? confirmRemove.plan.packages.length : 0
                        if (n <= 1) {
                            return "This removes the application. Files you "
                                 + "created with it are not touched."
                        }
                        var deps = n - 1
                        return "This removes " + n + " packages: the "
                             + "application and " + deps + " "
                             + (deps === 1 ? "dependency" : "dependencies")
                             + " nothing else needs."
                    }
                    color: root.dim; font.pixelSize: 14
                }

                // The list itself, scrollable, because a cascade can be long.
                Rectangle {
                    visible: !confirmRemove.blocked && !backend.planningRemoval
                             && !!(confirmRemove.plan
                                   && confirmRemove.plan.packages
                                   && confirmRemove.plan.packages.length > 1)
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(150, pkgList.contentHeight + 16)
                    radius: 9
                    color: root.bg
                    QQC2.ScrollView {
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true
                        ListView {
                            id: pkgList
                            model: confirmRemove.plan && confirmRemove.plan.packages
                                   ? confirmRemove.plan.packages : []
                            delegate: QQC2.Label {
                                required property var modelData
                                text: modelData
                                color: root.dim; font.pixelSize: 12
                            }
                        }
                    }
                }

                // Why dependencies were kept, when they were.
                QQC2.Label {
                    visible: !confirmRemove.blocked && !backend.planningRemoval
                             && !!(confirmRemove.plan && confirmRemove.plan.reason)
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: confirmRemove.plan ? (confirmRemove.plan.reason || "") : ""
                    color: root.accent; font.pixelSize: 12
                }

                QQC2.CheckBox {
                    id: alsoData
                    visible: !confirmRemove.blocked && !backend.planningRemoval
                             && !!(confirmRemove.plan
                                   && confirmRemove.plan.source === "flatpak")
                    text: "Also remove its settings and saved data"
                    checked: false
                    contentItem: QQC2.Label {
                        text: alsoData.text
                        leftPadding: alsoData.indicator.width + 8
                        verticalAlignment: Text.AlignVCenter
                        color: root.dim; font.pixelSize: 13
                    }
                }

                RowLayout {
                    Layout.topMargin: 4
                    Layout.alignment: Qt.AlignRight
                    spacing: 10
                    Action {
                        text: confirmRemove.blocked ? "Close" : "Cancel"
                        quiet: true
                        onClicked: backend.clearRemovalPlan()
                    }
                    Action {
                        visible: !confirmRemove.blocked
                        enabled: !backend.planningRemoval && !backend.busy
                        text: "Uninstall"
                        onClicked: backend.remove(confirmRemove.plan.id,
                                                  confirmRemove.plan.source,
                                                  alsoData.checked)
                    }
                }
            }
        }
    }

    // ---- one category -----------------------------------------------------
    Component {
        id: categoryPage
        ColumnLayout {
            spacing: 15
            QQC2.Label {
                Layout.leftMargin: 26; Layout.topMargin: 6
                text: backend.categoryName
                color: root.text; font.pixelSize: 22; font.weight: Font.Light
            }
            QQC2.Label {
                visible: !backend.loadingCategory
                Layout.leftMargin: 26
                Layout.maximumWidth: 640
                wrapMode: Text.WordWrap
                text: backend.categoryApps.length + " applications. Categories come from "
                      + "Flatpak and the SakuraOS repositories, which share one set of them. "
                      + "The AUR publishes no categories, so it is not represented here \u2014 search finds it."
                color: root.dim; font.pixelSize: 14
            }
            Loading {
                visible: backend.loadingCategory
                Layout.fillWidth: true
                Layout.preferredHeight: 300
                label: "Loading " + backend.categoryName
            }
            Flow {
                id: categoryFlow
                Layout.fillWidth: true
                Layout.leftMargin: 26; Layout.rightMargin: 26
                Layout.preferredHeight: childrenRect.height
                spacing: 13
                Repeater {
                    model: backend.categoryApps
                    delegate: Tile {
                        width: root.cellWidth(categoryFlow.width, 3, 13)
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
            id: installedRoot
            spacing: 15
            Component.onCompleted: { backend.loadInstalled(); backend.checkUpdates() }

            QQC2.Label {
                Layout.leftMargin: 26; Layout.topMargin: 6
                text: "Installed"
                color: root.text; font.pixelSize: 22; font.weight: Font.Light
            }
            QQC2.Label {
                Layout.leftMargin: 26
                Layout.maximumWidth: 620
                wrapMode: Text.WordWrap
                visible: !backend.loadingInstalled
                text: backend.installed.length + " applications, from every source. "
                        // Not "what you installed": most of these arrived
                        // with the system rather than by anyone choosing
                        // them, now that the list no longer filters on
                        // install reason.
                        + "Libraries and system packages are not listed."
                color: root.dim; font.pixelSize: 14
            }
            // Updates first, because it is the only thing on this page that
            // asks anything of the reader.
            Rectangle {
                visible: backend.updates.length > 0
                Layout.fillWidth: true
                Layout.leftMargin: 26; Layout.rightMargin: 26
                Layout.preferredHeight: upRow.implicitHeight + 26
                radius: 12
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
                border.width: 1
                border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.4)

                RowLayout {
                    id: upRow
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16; anchors.rightMargin: 16
                    spacing: 14
                    ColumnLayout {
                        spacing: 2
                        QQC2.Label {
                            text: backend.updates.length === 1
                                ? "1 application has an update"
                                : backend.updates.length + " applications have updates"
                            color: root.text
                            font.pixelSize: 15; font.weight: Font.DemiBold
                        }
                        QQC2.Label {
                            // Names them rather than only counting them: "3
                            // updates" tells you nothing about whether you
                            // want them now.
                            Layout.maximumWidth: 520
                            elide: Text.ElideRight
                            text: backend.updates.map(function (u) {
                                return u.name
                            }).join(", ")
                            color: root.dim; font.pixelSize: 12
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Action {
                        text: backend.busy ? "Updating…" : "Update all"
                        enabled: !backend.busy
                        onClicked: backend.applyUpdates("", "")
                    }
                }
            }
            QQC2.Label {
                visible: backend.checkingUpdates && backend.updates.length === 0
                Layout.leftMargin: 26
                text: "Checking for updates…"
                color: root.dim; font.pixelSize: 12
            }

            Loading {
                visible: backend.loadingInstalled
                Layout.fillWidth: true
                Layout.preferredHeight: 260
                label: "Looking at what is installed"
            }

            Flow {
                id: installedFlow
                Layout.fillWidth: true
                Layout.leftMargin: 26; Layout.rightMargin: 26
                Layout.topMargin: 6
                // A Flow reports no implicit height to a ColumnLayout, so
                // without this the row collapses and nothing is drawn.
                Layout.preferredHeight: childrenRect.height
                spacing: 14
                Repeater {
                    model: backend.installed
                    delegate: Tile {
                        width: root.cellWidth(installedFlow.width, 3, 14)
                        required property var modelData
                        appData: modelData
                        showRemove: true
                        onRemoveRequested: backend.planRemoval(modelData.id,
                                                              modelData.source)
                        onOpened: {
                            // Repository rows carry the AppStream id, which is
                            // what the app page looks things up by.
                            backend.openApp(modelData.id)
                            root.view = "app"
                        }
                    }
                }
            }
            Item { Layout.preferredHeight: 30 }
        }
    }

    // ---- app page ---------------------------------------------------------
    Component {
        id: appPage
        ColumnLayout {
            // The instantiated item needs its own id: `appPage` names the
            // Component, which has no property `a`, so bindings through it
            // threw a TypeError and QML silently left every `visible` at its
            // default of true -- an empty source chip, an "Installed" badge on
            // an app that is not installed, and an "Also available from"
            // heading with nothing under it.
            id: appRoot
            property bool showDetail: false
            spacing: 22
            property var a: backend.app

            // Every source that has this app, primary first. also_from holds
            // whatever the engine matched; the primary is not in it.
            readonly property var options: !a || !a.source ? [] : [{
                    source: a.source, id: a.id,
                    version: a.version || "",
                    installed: a.installed || false
                }].concat(a.also_from || [])
            // Not simply the first: the primary is whichever id we were asked
            // about, and that is an accident of how the user arrived. Opening
            // "org.mozilla.firefox" from the Windows-program guard must not
            // default to Flatpak when SakuraOS ships Firefox itself.
            // Driven by optionsChanged rather than aChanged. Reading `options`
            // inside the handler for the property it derives from gives the
            // value from before the change -- the list was still empty there,
            // so this always picked index 0, which is the primary, which is
            // whichever id we happened to be asked about. Its own signal fires
            // after it has been recomputed.
            property int chosen: 0
            onOptionsChanged: chosen = root.preferredIndex(options)

            Loading {
                visible: backend.loadingApp
                Layout.fillWidth: true
                Layout.preferredHeight: 320
                label: "Fetching details"
            }

            // header
            RowLayout {
                visible: !backend.loadingApp && !!appRoot.a.id
                Layout.fillWidth: true
                Layout.leftMargin: 26; Layout.rightMargin: 26
                Layout.topMargin: 8
                spacing: 22
                Image {
                    Layout.preferredWidth: 96; Layout.preferredHeight: 96
                    Layout.alignment: Qt.AlignTop
                    source: appRoot.a.icon || ""
                    sourceSize: Qt.size(192, 192)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 7
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: appRoot.a.name || ""
                        color: root.text; font.pixelSize: 32; font.weight: Font.Light
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        spacing: 14
                        QQC2.Label {
                            text: appRoot.a.developer || ""
                            color: root.accent; font.pixelSize: 15
                        }
                        QQC2.Label {
                            visible: !!appRoot.a.rating
                            text: root.stars(appRoot.a.rating) + "  "
                                  + (appRoot.a.rating || "")
                                  + "  ·  " + (appRoot.a.rating_count || 0)
                                  + " reviews"
                            color: root.dim; font.pixelSize: 14
                        }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: appRoot.a.summary || ""
                        color: root.dim; font.pixelSize: 15
                        wrapMode: Text.WordWrap
                    }
                    // Where this will come from -- a choice, not a label.
                    // Listing the alternatives without letting anyone pick one
                    // was the wrong half of the feature.
                    ColumnLayout {
                        Layout.topMargin: 4
                        spacing: 6
                        QQC2.Label {
                            visible: appRoot.options.length > 1
                            text: "Install from"
                            color: root.dim; font.pixelSize: 13
                        }
                        RowLayout {
                            spacing: 8
                            Repeater {
                                model: appRoot.options
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    readonly property bool picked: index === appRoot.chosen
                                    readonly property color hue: root.sourceTint(modelData.source)
                                    implicitWidth: srcRow.implicitWidth + 22
                                    implicitHeight: 30
                                    radius: 8
                                    color: picked ? Qt.rgba(hue.r, hue.g, hue.b, 0.22)
                                                  : Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.10)
                                    border.width: picked ? 1 : 0
                                    border.color: hue
                                    Behavior on color { ColorAnimation { duration: 130 } }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: appRoot.chosen = index }
                                    RowLayout {
                                        id: srcRow
                                        anchors.centerIn: parent
                                        spacing: 7
                                        QQC2.Label {
                                            text: root.sourceLabel(modelData.source)
                                            color: picked ? hue : root.text
                                            font.pixelSize: 12; font.weight: Font.DemiBold
                                        }
                                        QQC2.Label {
                                            visible: !!modelData.version
                                            text: modelData.version || ""
                                            color: root.dim; font.pixelSize: 12
                                        }
                                        QQC2.Label {
                                            visible: !!modelData.installed
                                            text: "installed"
                                            color: "#8fd3a4"; font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }
                            }
                        }
                        // A single option usually means the other sources are
                        // switched off, which is worth saying rather than
                        // leaving the short list unexplained.
                        QQC2.Label {
                            visible: appRoot.options.length === 1
                            Layout.maximumWidth: 540
                            wrapMode: Text.WordWrap
                            text: "Only " + root.sourceLabel(appRoot.a.source) +
                                  " offers this. Sources that are switched off cannot be searched \u2014 " +
                                  "turn them on in SakuraOS Settings."
                            color: root.dim; font.pixelSize: 12
                        }
                    }

                    RowLayout {
                        spacing: 12
                        Layout.topMargin: 6
                        Action {
                            readonly property var pick: appRoot.options[appRoot.chosen] || null
                            // The AUR install path refuses until the review
                            // step exists, so offering the button was walking
                            // the user several steps down a path with no end.
                            readonly property bool blocked:
                                !!(pick && pick.source === "aur")
                            text: backend.busy ? "Installing…"
                                 : blocked ? "Not available yet"
                                 : (pick && pick.installed ? "Reinstall" : "Install")
                            enabled: !backend.busy && !!pick && !blocked
                            onClicked: backend.install(pick.id, pick.source)
                        }
                        QQC2.Label {
                            readonly property var pick: appRoot.options[appRoot.chosen] || null
                            visible: !!(pick && pick.source === "aur")
                            Layout.maximumWidth: 420
                            wrapMode: Text.WordWrap
                            text: "An AUR package is a build script nobody has reviewed. "
                                + "SakuraOS will not run one without showing you what it "
                                + "does first, and that step is not built yet."
                            color: root.dim; font.pixelSize: 12
                        }
                        Action {
                            readonly property var pick: appRoot.options[appRoot.chosen] || null
                            visible: !!(pick && pick.installed)
                            enabled: !backend.busy
                            text: "Uninstall"; quiet: true
                            onClicked: backend.planRemoval(pick.id, pick.source)
                        }
                        Action {
                            text: "Permissions"; quiet: true
                            // Meaningless for an app that is not installed --
                            // there is no sandbox to adjust yet.
                            visible: !!appRoot.a.installed
                            onClicked: backend.openPermissions(appRoot.a.id)
                        }
                        Chip {
                            visible: !!appRoot.a.license
                            label: appRoot.a.license || ""
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
                        // Capitalising the engine's stage name gave
                        // "Removing" and "Configuring"; these say what is
                        // happening in the words a person would use.
                        text: backend.error !== ""
                            ? (backend.stage === "removing"
                               ? "Could not uninstall" : "Could not install")
                            : root.stageLabel(backend.stage)
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
                    // No progress bar once it has failed: a bar frozen at 40%
                    // beside an error reads as though it is still trying.
                    visible: backend.error === ""
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
                    Layout.maximumWidth: 620
                    text: backend.error; color: "#ff9db0"; font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    visible: backend.error !== ""
                    spacing: 14
                    // The tool's own words, for when the sentence above is
                    // wrong or not specific enough to act on.
                    QQC2.Label {
                        visible: backend.errorDetail !== ""
                        text: appRoot.showDetail ? "Hide details" : "Show details"
                        color: root.accent; font.pixelSize: 12
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: appRoot.showDetail = !appRoot.showDetail }
                    }
                    QQC2.Label {
                        text: "Dismiss"
                        color: root.dim; font.pixelSize: 12
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: { appRoot.showDetail = false; backend.clearError() }
                        }
                    }
                }
                Rectangle {
                    visible: backend.error !== "" && appRoot.showDetail
                             && backend.errorDetail !== ""
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(160, rawText.implicitHeight + 18)
                    radius: 9
                    color: root.bg
                    QQC2.ScrollView {
                        anchors.fill: parent; anchors.margins: 9
                        clip: true
                        QQC2.Label {
                            id: rawText
                            width: parent.width
                            text: backend.errorDetail
                            color: root.dim
                            font.pixelSize: 11; font.family: "monospace"
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }

            // screenshots
            ColumnLayout {
                visible: (appRoot.a.screenshots || []).length > 0
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
                            model: appRoot.a.screenshots || []
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
                visible: !!appRoot.a.description
                Layout.fillWidth: true
                Layout.leftMargin: 26; Layout.rightMargin: 26
                // Deliberate, unlike the cap that used to be on the review
                // cards: this is running prose, and ~90 characters a line is
                // where it stays readable.
                Layout.maximumWidth: 720
                text: appRoot.a.description || ""
                textFormat: Text.RichText
                color: root.dim; font.pixelSize: 15
                wrapMode: Text.WordWrap
                lineHeight: 1.35
            }

            // ratings and reviews
            ColumnLayout {
                visible: !!appRoot.a.rating || (appRoot.a.reviews || []).length > 0
                Layout.fillWidth: true
                Layout.leftMargin: 26; Layout.rightMargin: 26
                spacing: 13

                RowLayout {
                    spacing: 26
                    ColumnLayout {
                        spacing: 2
                        QQC2.Label {
                            text: (appRoot.a.rating || "—").toString()
                            color: root.text; font.pixelSize: 40; font.weight: Font.Light
                        }
                        QQC2.Label {
                            text: root.stars(appRoot.a.rating)
                            color: root.accent; font.pixelSize: 15
                        }
                        QQC2.Label {
                            text: (appRoot.a.rating_count || 0) + " reviews"
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
                    model: appRoot.a.reviews || []
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        // No width cap: capped at 720 inside a ~890px column
                        // these sat against the left edge with a wide empty
                        // strip beside them, which is what read as off-centre.
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
