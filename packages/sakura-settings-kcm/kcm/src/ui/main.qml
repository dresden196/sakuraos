import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    property var cfg: kcm

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        type: Kirigami.MessageType.Error
        text: cfg.saveError
        visible: cfg.saveError !== ""
    }

    Kirigami.FormLayout {
        id: form

        // ---- Terminal Assist ----------------------------------------------

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Terminal Assist") }

        QQC2.ComboBox {
            id: assistMode
            Kirigami.FormData.label: i18n("When a command would break the system:")
            textRole: "label"
            valueRole: "value"
            model: [
                { label: i18n("Stop it and explain why"), value: "block" },
                { label: i18n("Warn, but continue"),      value: "warn"  },
                { label: i18n("Do nothing"),              value: "off"   },
            ]
            Layout.minimumWidth: Kirigami.Units.gridUnit * 15
            currentIndex: indexOfValue(cfg.terminalAssistMode)
            onActivated: cfg.terminalAssistMode = currentValue
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("Checks commands and package changes that are known to break Arch systems — partial upgrades, removing the last kernel, force-removing core packages. You can always override a specific check.")
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("AUR") }

        // ---- AUR ----------------------------------------------------------

        QQC2.CheckBox {
            id: aurEnabled
            Kirigami.FormData.label: i18n("Arch User Repository:")
            text: i18n("Allow installing packages from the AUR")
            checked: cfg.aurEnabled
            onToggled: cfg.aurEnabled = checked
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("The AUR is build scripts written by other users. Nobody reviews them before publication.")
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Before installing:")
            text: i18n("Review packages before they build")
            enabled: aurEnabled.checked
            checked: cfg.aurReview
            onToggled: cfg.aurReview = checked
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            enabled: aurEnabled.checked
            text: i18n("Shows what a package's build script does, what changed since the version you last accepted, and flags risk signals — a maintainer who changed recently, an unusual download location, code that runs outside the build directory.")
        }

        QQC2.CheckBox {
            id: campaignScan
            Kirigami.FormData.label: i18n("Security scanning:")
            text: i18n("Check for known compromised packages")
            enabled: aurEnabled.checked
            checked: cfg.aurCampaignScanning
            onToggled: cfg.aurCampaignScanning = checked
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            enabled: aurEnabled.checked
            // Saying plainly what this cannot do is the point. A user who
            // believes they are protected stops reading build scripts, which
            // is the behaviour this feature exists to encourage.
            text: i18n("Compares what you have installed against published attack campaigns. This cannot detect an attack that nobody has reported yet — it is not a substitute for reading what you install.")
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Command-line helper:")
            enabled: aurEnabled.checked
            textRole: "label"
            valueRole: "value"
            model: [
                { label: i18n("yay"),                       value: "yay"  },
                { label: i18n("None — use the store only"), value: "none" },
            ]
            Layout.minimumWidth: Kirigami.Units.gridUnit * 15
            currentIndex: indexOfValue(cfg.aurHelper)
            onActivated: cfg.aurHelper = currentValue
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            enabled: aurEnabled.checked
            text: i18n("With no helper installed, the AUR is reachable only through the store, where the review step is not optional.")
        }

        // ---- Updates ------------------------------------------------------

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Updates") }

        QQC2.CheckBox {
            id: autoApply
            Kirigami.FormData.label: i18n("Automatic updates:")
            text: i18n("Install updates automatically")
            checked: cfg.updatesAutoApply
            onToggled: cfg.updatesAutoApply = checked
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("A snapshot is taken before every update. If one causes a problem, you can go back to the previous state from the boot menu.")
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Only install:")
            text: i18n("Updates that have been tested first")
            enabled: autoApply.checked
            checked: cfg.updatesRequireCanary
            onToggled: cfg.updatesRequireCanary = checked
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            enabled: autoApply.checked
            text: i18n("SakuraOS installs and restarts each update on its own machines before offering it to yours. Anything that has not passed, or that needs a manual step, waits for you instead.")
        }

        QQC2.TextField {
            Kirigami.FormData.label: i18n("Install updates at:")
            enabled: autoApply.checked
            text: cfg.updatesWindow
            inputMask: "99:99"
            maximumLength: 5
            onEditingFinished: cfg.updatesWindow = text
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Power:")
            text: i18n("Only when plugged in")
            enabled: autoApply.checked
            checked: cfg.updatesRequireAC
            onToggled: cfg.updatesRequireAC = checked
        }
    }
}
