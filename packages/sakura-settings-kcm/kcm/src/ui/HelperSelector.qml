// The command-line AUR helper dropdown, on its own so it can be tested.
//
// It was inline in main.qml, where the only way to exercise it was to run
// System Settings and click -- and synthetic clicks cannot reach a QQC2 popup
// menu, so it could not be exercised at all. Pulled out here, a test can load
// this file, hand it a stand-in for the settings object and emit activated()
// directly, which is the part worth checking: what value the handler reads and
// passes on.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

QQC2.ComboBox {
    id: control

    // The settings object. A property rather than the ambient `cfg` so a test
    // can supply one; main.qml passes the real thing.
    property var cfg

    enabled: !!cfg && cfg.aurEnabled && !cfg.aurHelperBusy
    textRole: "label"
    valueRole: "value"
    model: [
        { label: i18n("yay"),                      value: "yay"  },
        { label: i18n("paru"),                     value: "paru" },
        { label: i18n("None, use the store only"), value: "none" },
    ]
    Layout.minimumWidth: Kirigami.Units.gridUnit * 15

    // Follows the machine, not a stored preference: somebody who removes yay
    // with pacman sees that here.
    currentIndex: indexOfValue((cfg && cfg.aurHelperInstalled) || "none")

    // The value at the index the signal carries, not currentValue.
    //
    // currentIndex above is a live binding on what is installed, and it is
    // still live when an item is chosen: it puts the index back to the
    // installed helper, so currentValue can read "none" the moment after
    // picking "yay". Reading valueAt(index) takes the choice from the signal,
    // which no binding can overwrite. tst_helperselector covers exactly this.
    onActivated: (index) => {
        const chosen = valueAt(index)
        if (!cfg) {
            return
        }
        cfg.aurHelper = chosen
        cfg.applyAurHelper(chosen)
    }
}
