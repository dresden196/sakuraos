import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Dialogs

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
    // The app the review dialog is about. Held here rather than read off the
    // page, so closing the page mid-submission cannot leave the dialog
    // pointing at nothing.
    property string reviewAppId: ""
    property string reviewAppName: ""
    property string reviewVersion: ""

    // Where the app page was opened from, so leaving it goes back there.
    // Back used to return to the last search whenever there had ever been
    // one, which dropped you into a stale result list you had left long ago
    // -- open something from the front page, press back, land in a search.
    property string cameFrom: "discover"

    // Every route to the app page goes through here, so none of them can
    // forget to record where it came from.
    function showApp(id) {
        if (root.view !== "app") {
            root.cameFrom = root.view
        }
        backend.openApp(id)
        root.view = "app"
    }

    // Which sources the store searches. A source is listed here only once
    // the user has switched it off, so one that appears later -- snapd gets
    // installed -- is searched without anybody having to go and tick it.
    property var sourcesOff: []

    function searchesSource(id) {
        return root.sourcesOff.indexOf(id) < 0
    }

    function toggleSource(id) {
        const off = root.sourcesOff.slice()
        const i = off.indexOf(id)
        if (i < 0) {
            off.push(id)
        } else {
            off.splice(i, 1)
        }
        root.sourcesOff = off
        if (root.lastQuery) {
            backend.search(root.lastQuery, root.sourceArg())
        }
    }

    // What the engine is asked for: the ids still switched on, or nothing at
    // all when every one of them is, so the ordinary case does not build a
    // list. Everything unticked asks for a source that does not exist, which
    // finds nothing -- the honest answer to having switched them all off.
    function sourceArg() {
        const list = backend.sources || []
        let on = [], anyOff = false
        for (let i = 0; i < list.length; ++i) {
            if (!list[i].available) continue
            if (root.searchesSource(list[i].id)) {
                on.push(list[i].id)
            } else {
                anyOff = true
            }
        }
        if (!anyOff) return ""
        return on.length ? on.join(",") : "none"
    }
    property string lastQuery: ""

    Component.onCompleted: {
        // Opened with an application id -- the handoff from the Windows-program
        // guard. Go straight to that app rather than the front page, and still
        // load the featured list behind it so Back has somewhere to land.
        backend.loadFeatured();
        const wanted = typeof openAppId !== "undefined" ? openAppId : "";
        if (wanted !== "") {
            root.cameFrom = "discover";
            root.showApp(wanted);
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

    // Two gates stand between an AUR result and an install, and they need
    // different sentences. The switch in Settings is the user's and they can
    // change it; the review step is ours and they cannot. Saying "turn it on
    // in Settings" when that would change nothing is a small lie that costs
    // somebody a trip to Settings.
    readonly property bool aurEnabled: {
        const list = backend.sources || [];
        for (let i = 0; i < list.length; ++i)
            if (list[i].id === "aur") return !!list[i].available;
        return false;
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
        id: act
        property bool quiet: false
        // A button that has started something becomes the progress indicator
        // for it. A separate bar elsewhere on the page makes you look in two
        // places to answer one question.
        property bool showsProgress: false
        property real progress: 0
        padding: 12; leftPadding: 26; rightPadding: 26
        contentItem: QQC2.Label {
            text: parent.text
            color: act.showsProgress ? root.accentText
                 : !parent.enabled ? root.dim
                 : (parent.quiet ? root.text : root.accentText)
            font.pixelSize: 15; font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 9
            clip: true
            color: act.showsProgress ? Qt.darker(root.accent, 1.8)
                 : !parent.enabled ? root.card
                 : parent.quiet ? (parent.down ? root.cardUp : "transparent")
                 : (parent.down ? Qt.darker(root.accent, 1.15) : root.accent)
            border.width: parent.quiet && !act.showsProgress ? 1 : 0
            border.color: root.line

            Rectangle {
                visible: act.showsProgress && act.progress > 0
                height: parent.height; radius: 9; color: root.accent
                width: parent.width * Math.min(1, act.progress / 100)
                Behavior on width { NumberAnimation { duration: 240 } }
            }
            // Until the first percentage arrives the fill sweeps rather than
            // sitting at zero: a bar that has not moved in eight seconds is
            // indistinguishable from nothing having happened.
            Rectangle {
                id: sweep
                visible: act.showsProgress && act.progress <= 0
                height: parent.height; radius: 9; color: root.accent
                width: parent.width * 0.34
                SequentialAnimation on x {
                    running: sweep.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: -sweep.width; to: act.width
                                      duration: 1150; easing.type: Easing.InOutQuad }
                }
            }
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
            Layout.preferredWidth: 236
            Layout.fillHeight: true
            color: panel

            // The rail can be taller than the window -- eight categories and
            // six sources with descriptions do not fit at 800px. Scrolled
            // rather than clipped, because the alternative is a sources list
            // whose last entry is permanently half-hidden behind the account
            // row.
            QQC2.ScrollView {
                anchors.fill: parent
                anchors.margins: 18
                anchors.bottomMargin: 18 + 52 + 12   // room for the account row
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    width: 236 - 36
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
                            elide: Text.ElideRight
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    root.view = "category"
                                    backend.loadCategory(modelData.id, modelData.name)
                                }
                            }
                        }
                    }

                }
                Item { Layout.fillHeight: true }

                }
            }

            // ---- who is signed in, and the things that belong to them ------
            // Anchored to the bottom of the rail rather than pushed there by a
            // spacer: the lists above can be taller than the window, and a
            // spacer in an overflowing column pushes this off the screen
            // entirely. Anchoring means it is always where it says it is.
                // Bottom of the sidebar because it is about you rather than
                // about software: the same place every desktop application
                // that has an identity puts it.
                Rectangle {
                    id: accountRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 12
                    height: 52
                    radius: 12
                    color: accountHover.hovered || accountMenu.visible
                           ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    HoverHandler { id: accountHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: accountMenu.visible ? accountMenu.close()
                                                      : accountMenu.open()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 10
                        spacing: 10

                        // Avatar, or the initial if this account has never set
                        // one -- which is most of them.
                        Rectangle {
                            Layout.preferredWidth: 32; Layout.preferredHeight: 32
                            radius: 16
                            color: root.accent
                            Image {
                                id: avatarImage
                                anchors.fill: parent
                                source: backend.userAvatar
                                visible: false          // shown through the mask
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                            }
                            MultiEffect {
                                anchors.fill: parent
                                source: avatarImage
                                visible: backend.userAvatar !== ""
                                         && avatarImage.status === Image.Ready
                                maskEnabled: true
                                maskSource: avatarMask
                            }
                            // The circle the photo is cut to. Kept out of the
                            // layout so it is only ever a mask.
                            Item {
                                id: avatarMask
                                width: 32; height: 32
                                layer.enabled: true
                                visible: false
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: "black"
                                }
                            }
                            QQC2.Label {
                                anchors.centerIn: parent
                                visible: backend.userAvatar === ""
                                         || avatarImage.status !== Image.Ready
                                text: (backend.userDisplayName || "?").charAt(0).toUpperCase()
                                color: root.accentText
                                font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: backend.userDisplayName
                                color: root.text
                                font.pixelSize: 13; font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                visible: backend.userName !== backend.userDisplayName
                                text: backend.userName
                                color: root.dim; font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }

                        // The affordance. Points up because the menu comes up.
                        Canvas {
                            Layout.preferredWidth: 12; Layout.preferredHeight: 12
                            rotation: accountMenu.visible ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: 140 } }
                            onPaint: {
                                const c = getContext("2d");
                                c.reset();
                                c.strokeStyle = root.dim;
                                c.lineWidth = 1.6;
                                c.lineCap = "round";
                                c.lineJoin = "round";
                                c.beginPath();
                                c.moveTo(2.5, 7.5); c.lineTo(6, 4); c.lineTo(9.5, 7.5);
                                c.stroke();
                            }
                        }
                    }

                    QQC2.Menu {
                        id: accountMenu
                        y: -height - 6
                        width: Math.max(accountRow.width, 210)
                        modal: true

                        background: Rectangle {
                            radius: 12
                            color: root.card
                            border.width: 1
                            border.color: root.line
                        }

                        QQC2.MenuItem {
                            text: "App Sync"
                            icon.name: "folder-sync"
                            onTriggered: appSync.open()
                        }
                        QQC2.MenuItem {
                            text: "Sakura Store settings"
                            icon.name: "configure"
                            onTriggered: storeSettings.open()
                        }
                    }
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
                        onClicked: root.view = root.cameFrom
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
                                    backend.search(text, root.sourceArg())
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
                                    onClicked: root.showApp(modelData.id)
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
                            onOpened: root.showApp(modelData.id)
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
                        onOpened: root.showApp(modelData.id)
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
                        + "Nothing here reviewed it, and no signature was checked. "
                        + "Install it only if you trust where it came from."
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
                      + "The AUR publishes no categories, so it is not represented here. Search finds it."
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
                        onOpened: root.showApp(modelData.id)
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
                            root.showApp(modelData.id)
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
                                  " offers this. Sources that are switched off cannot be searched. " +
                                  "Turn them on in SakuraOS Settings."
                            color: root.dim; font.pixelSize: 12
                        }
                    }

                    RowLayout {
                        spacing: 12
                        Layout.topMargin: 6
                        Action {
                            readonly property var pick: appRoot.options[appRoot.chosen] || null
                            // Only this app's own button turns into a bar. An
                            // install started here and then navigated away from
                            // must not light up every other Install on screen.
                            readonly property bool mine:
                                backend.busy && !!pick && backend.busyId === pick.id
                            // The AUR install path refuses until the review
                            // step exists, so offering the button was walking
                            // the user several steps down a path with no end.
                            readonly property bool blocked:
                                !!(pick && pick.source === "aur")
                            Layout.minimumWidth: 196
                            showsProgress: mine
                            progress: backend.percent
                            text: mine ? root.stageLabel(backend.stage)
                                 : blocked ? (root.aurEnabled ? "Not available yet"
                                                           : "AUR is switched off")
                                 : (pick && pick.installed ? "Reinstall" : "Install")
                            enabled: !backend.busy && !!pick && !blocked
                            onClicked: backend.install(pick.id, pick.source)
                        }
                        QQC2.Label {
                            readonly property var pick: appRoot.options[appRoot.chosen] || null
                            visible: !!(pick && pick.source === "aur")
                            Layout.maximumWidth: 420
                            wrapMode: Text.WordWrap
                            text: root.aurEnabled
                                ? "An AUR package is a build script nobody has reviewed. "
                                  + "SakuraOS will not run one without showing you what it "
                                  + "does first, and that step is not built yet."
                                : "The AUR is switched off. Turn it on in SakuraOS Settings "
                                  + "to install this. It is off by default because AUR packages "
                                  + "are build scripts written by other people, and nobody "
                                  + "reviews them."
                            color: root.dim; font.pixelSize: 12
                        }
                        Action {
                            readonly property var pick: appRoot.options[appRoot.chosen] || null
                            visible: !!(pick && pick.source === "aur") && !root.aurEnabled
                            text: "Open Settings"
                            onClicked: Qt.openUrlExternally("systemsettings://kcm_sakura")
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
                // Only failures now. Progress lives in the button that
                // started the work, so there is one place to look.
                visible: backend.error !== ""
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
                // Also for an installed app nobody has reviewed yet, which is
                // exactly the case where a review is worth asking for.
                visible: !!appRoot.a.rating || !!appRoot.a.installed
                         || (appRoot.a.reviews || []).length > 0
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
                            text: "Reviews come from the Open Desktop Ratings Service, so a review written here helps everyone using Linux, not just SakuraOS."
                            color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, .8)
                            font.pixelSize: 12
                        }
                        Action {
                            quiet: true
                            Layout.topMargin: 4
                            Layout.alignment: Qt.AlignLeft
                            // Only for an app you have. Reviewing something
                            // you have never run is how a ratings service
                            // fills up with opinions about screenshots.
                            visible: !!appRoot.a.installed
                            text: "Write a review"
                            onClicked: {
                                root.reviewAppId = appRoot.a.id || ""
                                root.reviewAppName = appRoot.a.name || ""
                                root.reviewVersion = appRoot.a.installed_version || ""
                                backend.resetReview()
                                reviewDialog.open()
                            }
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

        // ---- App Sync ------------------------------------------------------
        // A list of what is installed, so a second machine can end up with the
        // same software. It carries names, not data: no settings, no home
        // directory, nothing private. That is a deliberate limit rather than a
        // missing feature -- a file that looks like a backup but silently
        // omits your documents is worse than no backup.
        QQC2.Dialog {
            id: appSync
            anchors.centerIn: parent
            width: Math.min(620, root.width - 120)
            modal: true
            padding: 0
            background: Rectangle { radius: 16; color: root.card
                                    border.width: 1; border.color: root.line }

            onOpened: backend.clearImportPlan()
            onClosed: backend.clearImportPlan()

            contentItem: ColumnLayout {
                spacing: 0

                ColumnLayout {
                    Layout.margins: 24
                    Layout.fillWidth: true
                    spacing: 6
                    QQC2.Label {
                        text: "App Sync"
                        color: root.text; font.pixelSize: 19; font.weight: Font.DemiBold
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Save the list of applications on this machine, and install "
                            + "the same set on another one. The list holds names only. "
                            + "No settings and no files, so nothing private travels with it."
                        color: root.dim; font.pixelSize: 12
                    }
                }

                // Nothing loaded: offer the two directions.
                RowLayout {
                    visible: !appSync.hasPlan
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.bottomMargin: 24
                    spacing: 10
                    QQC2.Button {
                        text: "Save this machine\u2019s list\u2026"
                        onClicked: exportDialog.open()
                    }
                    QQC2.Button {
                        text: "Open a list\u2026"
                        onClicked: importDialog.open()
                    }
                    Item { Layout.fillWidth: true }
                }

                // A list has been read. Say exactly what it would do, first.
                ColumnLayout {
                    visible: appSync.hasPlan
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.bottomMargin: 20
                    Layout.fillWidth: true
                    spacing: 10

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: root.text; font.pixelSize: 13
                        text: {
                            const c = backend.importPlan.counts || {};
                            const from = backend.importPlan.from || "another machine";
                            return (c.install || 0) + " to install from " + from
                                 + ", " + (c.present || 0) + " already here"
                                 + ((c.unavailable || 0) ? ", " + c.unavailable
                                    + " from a source switched off here" : "")
                                 + ((c.manual || 0) ? ", " + c.manual
                                    + " AppImages you will need to fetch yourself" : "")
                                 + ".";
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 230
                        radius: 10
                        color: Qt.rgba(0, 0, 0, 0.18)
                        border.width: 1; border.color: root.line
                        clip: true
                        ListView {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 1
                            model: backend.importPlan.apps || []
                            delegate: RowLayout {
                                required property var modelData
                                width: ListView.view.width
                                height: 30
                                spacing: 8
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: modelData.state === "install" ? root.text : root.dim
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                QQC2.Label {
                                    text: root.sourceLabel(modelData.source)
                                    color: root.dim; font.pixelSize: 11
                                }
                                QQC2.Label {
                                    text: modelData.state === "install"    ? "will install"
                                        : modelData.state === "present"    ? "already here"
                                        : modelData.state === "unavailable"? "source off"
                                        :                                    "fetch yourself"
                                    color: modelData.state === "install" ? root.accent : root.dim
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        QQC2.Button {
                            text: "Install " + ((backend.importPlan.counts || {}).install || 0)
                                  + " applications"
                            enabled: ((backend.importPlan.counts || {}).install || 0) > 0
                                     && !backend.busy
                            highlighted: true
                            onClicked: appSync.installAll()
                        }
                        QQC2.Button {
                            text: "Cancel"
                            onClicked: { backend.clearImportPlan(); appSync.close(); }
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }

            readonly property bool hasPlan:
                !!backend.importPlan.apps && backend.importPlan.apps.length > 0

            // Installed one at a time through the ordinary install path, so
            // each one shows the progress and the failures it normally would.
            function installAll() {
                const apps = backend.importPlan.apps || [];
                for (let i = 0; i < apps.length; ++i) {
                    if (apps[i].state === "install") {
                        backend.install(apps[i].id, apps[i].source);
                    }
                }
                appSync.close();
                root.view = "installed";
                backend.loadInstalled();
            }
        }

        FileDialog {
            id: exportDialog
            title: "Save the application list"
            fileMode: FileDialog.SaveFile
            nameFilters: ["SakuraOS app list (*.json)"]
            defaultSuffix: "json"
            onAccepted: backend.exportAppList(selectedFile)
        }

        FileDialog {
            id: importDialog
            title: "Open an application list"
            fileMode: FileDialog.OpenFile
            nameFilters: ["SakuraOS app list (*.json)", "All files (*)"]
            onAccepted: backend.readAppList(selectedFile)
        }

        // ---- Store settings ------------------------------------------------
        // The store has few settings of its own; the ones that matter live in
        // System Settings because they change what the machine does, not what
        // this window does. Rather than duplicate them, point at them.
        QQC2.Dialog {
            id: storeSettings
            anchors.centerIn: parent
            width: Math.min(560, root.width - 120)
            modal: true
            padding: 0
            background: Rectangle { radius: 16; color: root.card
                                    border.width: 1; border.color: root.line }
            contentItem: ColumnLayout {
                Layout.margins: 24
                spacing: 14
                QQC2.Label {
                    Layout.leftMargin: 24; Layout.topMargin: 24
                    text: "Sakura Store settings"
                    color: root.text; font.pixelSize: 19; font.weight: Font.DemiBold
                }
                QQC2.Label {
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Which sources the store searches. They are tried in this "
                        + "order, so an app that is in the official repositories is never "
                        + "installed from anywhere else."
                    color: root.dim; font.pixelSize: 12
                }
                ColumnLayout {
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.fillWidth: true
                    spacing: 11
                    Repeater {
                        // From the engine, which knows what is actually
                        // present -- a hardcoded list showed Snap on machines
                        // with no snapd, where the box could only ever return
                        // nothing.
                        //
                        // AppImage is deliberately absent: it has no catalogue
                        // to search, so a box for it could only ever return
                        // nothing either. What it is is explained below.
                        //
                        // Sources that are off are shown rather than dropped.
                        // Hiding them means nobody can discover that the AUR
                        // exists, let alone that it is theirs to switch on.
                        model: (backend.sources || [])
                                .filter(function (s) { return s.id !== "appimage" })
                                .map(function (s) {
                                    return {k: s.id, n: root.sourceLabel(s.id),
                                            avail: s.available, why: s.reason || ""}
                                })
                        delegate: RowLayout {
                            id: srow
                            required property var modelData
                            readonly property bool usable: modelData.avail
                            // A source that is switched off system-wide reads
                            // as unticked here rather than as ticked and
                            // quietly ignored.
                            readonly property bool ticked:
                                usable && root.searchesSource(modelData.k)
                            Layout.fillWidth: true
                            spacing: 9
                            opacity: usable ? 1 : 0.45
                            Rectangle {
                                width: 15; height: 15; radius: 4
                                color: srow.ticked ? root.accent : "transparent"
                                border.width: 1
                                border.color: srow.ticked ? root.accent : root.line
                                QQC2.Label {
                                    anchors.centerIn: parent; text: "\u2713"
                                    visible: srow.ticked
                                    color: root.accentText; font.pixelSize: 10
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: srow.modelData.n
                                    color: srow.ticked ? root.text : root.dim
                                    font.pixelSize: 13
                                }
                                // Why a source cannot be ticked, said here
                                // rather than by the box quietly refusing.
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    visible: !!srow.modelData.why
                                    text: srow.modelData.why
                                    wrapMode: Text.WordWrap
                                    color: root.dim; font.pixelSize: 10
                                }
                                // The AUR's caveat belongs on the AUR, not in
                                // a warning somewhere else that appears only
                                // once it happens to be selected.
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    visible: srow.modelData.k === "aur" && srow.usable
                                    text: "Build scripts written by other users. Nobody reviews them."
                                    wrapMode: Text.WordWrap
                                    color: root.warn; font.pixelSize: 10
                                }
                            }
                            TapHandler {
                                enabled: srow.usable
                                onTapped: root.toggleSource(srow.modelData.k)
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }
                    }
                }
                QQC2.Label {
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "AppImage is not in the list. An AppImage is a single file you "
                        + "download and run yourself, and there is no index of them "
                        + "anywhere to search. The store can install one you already "
                        + "have, but it has nothing to show you here. Whether the AUR is "
                        + "allowed, and when updates are applied, are settings for the "
                        + "whole machine rather than for this window, so they live in "
                        + "System Settings."
                    color: root.dim; font.pixelSize: 11
                }
                RowLayout {
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.bottomMargin: 24
                    spacing: 10
                    QQC2.Button {
                        text: "Open System Settings"
                        icon.name: "configure"
                        onClicked: {
                            Qt.openUrlExternally("systemsettings://kcm_sakura");
                            storeSettings.close();
                        }
                    }
                    QQC2.Button { text: "Close"; onClicked: storeSettings.close() }
                    Item { Layout.fillWidth: true }
                }
        }
        }

        // ---- writing a review ---------------------------------------------
        // Publishing here is not like the rest of the store: it leaves the
        // machine, it is public, and it cannot be taken back. The dialog says
        // all three before the button is reachable, because a person who
        // learns this afterwards has already been surprised by it.
        QQC2.Dialog {
            id: reviewDialog
            anchors.centerIn: parent
            width: Math.min(580, root.width - 120)
            modal: true
            padding: 0
            closePolicy: backend.reviewBusy ? QQC2.Popup.NoAutoClose
                                            : QQC2.Popup.CloseOnEscape
            background: Rectangle { radius: 16; color: root.card
                                    border.width: 1; border.color: root.line }

            // A star the pointer can land on, which is the whole rating
            // control -- five of them and nothing else.
            component Star : QQC2.Label {
                required property int value
                text: reviewStars.rating >= value ? "\u2605" : "\u2606"
                color: root.accent
                font.pixelSize: 26
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: reviewStars.rating = value }
            }

            contentItem: ColumnLayout {
                spacing: 12

                QQC2.Label {
                    Layout.leftMargin: 24; Layout.topMargin: 24
                    Layout.rightMargin: 24
                    Layout.fillWidth: true
                    text: backend.reviewDone ? "Thank you"
                                             : "Review " + (root.reviewAppName || "this app")
                    elide: Text.ElideRight
                    color: root.text; font.pixelSize: 19; font.weight: Font.DemiBold
                }

                // ---- what happens when you press the button ---------------
                QQC2.Label {
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.fillWidth: true
                    visible: !backend.reviewDone
                    wrapMode: Text.WordWrap
                    text: "This is published to the Open Desktop Ratings Service, "
                        + "the same one GNOME Software and Discover read. Anyone "
                        + "using Linux can see it, and there is no way to delete "
                        + "it afterwards. You can review each app once."
                    color: root.dim; font.pixelSize: 12
                }

                RowLayout {
                    id: reviewStars
                    property int rating: 0
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    visible: !backend.reviewDone
                    spacing: 4
                    Star { value: 1 }
                    Star { value: 2 }
                    Star { value: 3 }
                    Star { value: 4 }
                    Star { value: 5 }
                    QQC2.Label {
                        Layout.leftMargin: 8
                        text: reviewStars.rating === 0 ? "Choose a rating"
                                                       : reviewStars.rating + " of 5"
                        color: root.dim; font.pixelSize: 12
                    }
                }

                QQC2.TextField {
                    id: reviewSummary
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.fillWidth: true
                    visible: !backend.reviewDone
                    // The server's own limit. Enforced here so the sentence
                    // cannot be finished and then refused.
                    maximumLength: 70
                    placeholderText: "One line: what is it like to use?"
                    color: root.text
                    background: Rectangle {
                        radius: 8; color: root.cardUp
                        border.width: reviewSummary.activeFocus ? 2 : 1
                        border.color: reviewSummary.activeFocus ? root.accent : root.line
                    }
                }

                QQC2.ScrollView {
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.fillWidth: true
                    Layout.preferredHeight: 130
                    visible: !backend.reviewDone
                    QQC2.TextArea {
                        id: reviewText
                        wrapMode: TextEdit.Wrap
                        placeholderText: "What worked, what did not, and who else would want it."
                        color: root.text
                        background: Rectangle {
                            radius: 8; color: root.cardUp
                            border.width: reviewText.activeFocus ? 2 : 1
                            border.color: reviewText.activeFocus ? root.accent : root.line
                        }
                    }
                }

                RowLayout {
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.fillWidth: true
                    visible: !backend.reviewDone
                    spacing: 10
                    QQC2.Label {
                        text: "Shown as"
                        color: root.dim; font.pixelSize: 12
                    }
                    QQC2.TextField {
                        id: reviewName
                        Layout.fillWidth: true
                        maximumLength: 40
                        // Prefilled, not silently taken: this name goes onto a
                        // public page, and the first time somebody sees it
                        // should be before they publish, not after.
                        text: backend.userDisplayName || ""
                        placeholderText: "Anonymous"
                        color: root.text
                        background: Rectangle {
                            radius: 8; color: root.cardUp
                            border.width: reviewName.activeFocus ? 2 : 1
                            border.color: reviewName.activeFocus ? root.accent : root.line
                        }
                    }
                }
                QQC2.Label {
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.fillWidth: true
                    visible: !backend.reviewDone
                    wrapMode: Text.WordWrap
                    text: "This name is public. Leave it as anything you like."
                    color: Qt.rgba(root.dim.r, root.dim.g, root.dim.b, .8)
                    font.pixelSize: 11
                }

                // ---- how it went ------------------------------------------
                QQC2.Label {
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.fillWidth: true
                    visible: backend.reviewError !== ""
                    wrapMode: Text.WordWrap
                    text: backend.reviewError
                    color: "#ff9db0"; font.pixelSize: 12
                }
                QQC2.Label {
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.fillWidth: true
                    visible: backend.reviewDone
                    wrapMode: Text.WordWrap
                    text: "Your review is published. It may take a little while to "
                        + "appear here, and it will show up in GNOME Software and "
                        + "Discover too."
                    color: root.dim; font.pixelSize: 12
                }

                RowLayout {
                    Layout.leftMargin: 24; Layout.rightMargin: 24
                    Layout.bottomMargin: 24
                    Layout.fillWidth: true
                    spacing: 10
                    Action {
                        visible: !backend.reviewDone
                        showsProgress: backend.reviewBusy
                        text: backend.reviewBusy ? "Publishing" : "Publish"
                        // Nothing to publish until there is a rating and
                        // something written; the server would refuse it and
                        // the refusal would arrive as a surprise.
                        enabled: !backend.reviewBusy
                                 && reviewStars.rating > 0
                                 && reviewSummary.text.trim().length > 1
                                 && reviewText.text.trim().length > 1
                        onClicked: backend.submitReview(
                            root.reviewAppId, reviewStars.rating,
                            reviewSummary.text, reviewText.text,
                            reviewName.text, root.reviewVersion)
                    }
                    QQC2.Button {
                        text: backend.reviewDone ? "Close" : "Cancel"
                        enabled: !backend.reviewBusy
                        onClicked: {
                            reviewDialog.close()
                            reviewStars.rating = 0
                            reviewSummary.text = ""
                            reviewText.text = ""
                            backend.resetReview()
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }

}
