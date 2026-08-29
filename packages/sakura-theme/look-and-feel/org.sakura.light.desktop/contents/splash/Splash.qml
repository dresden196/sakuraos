import QtQuick
import org.kde.plasma.core as PlasmaCore

// The splash between login and a usable desktop. Deliberately almost nothing:
// it exists to cover a gap, not to be looked at, and anything that asks to be
// read is being shown at the one moment nobody is willing to read.
Rectangle {
    id: root
    color: "#fdf6f8"

    property int stage
    onStageChanged: if (stage === 1) blossom.opacity = 1

    Image {
        id: blossom
        anchors.centerIn: parent
        width: Math.round(parent.width * 0.11)
        height: width
        source: "images/blossom.png"
        smooth: true
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 420 } }

        RotationAnimation on rotation {
            from: 0; to: 360
            duration: 9000
            loops: Animation.Infinite
            running: true
        }
    }
}
