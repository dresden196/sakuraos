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

    // Removing a Windows program deletes the prefix it lives in, and that
    // takes everything it installed with it. Worth asking first.
    Kirigami.PromptDialog {
        id: confirmRemove

        property string slug: ""
        property string appName: ""

        function ask(app) {
            slug = app.slug;
            appName = app.name !== "" ? app.name : app.slug;
            open();
        }

        title: i18n("Remove %1?", appName)
        subtitle: i18n("This deletes the Windows environment it runs in, "
                     + "along with anything it saved there. Files in your "
                     + "home folder are not touched.")
        standardButtons: Kirigami.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action {
                text: i18n("Remove")
                icon.name: "edit-delete"
                onTriggered: { cfg.removeWindowsApp(confirmRemove.slug); confirmRemove.close(); }
            },
            Kirigami.Action {
                text: i18n("Cancel")
                icon.name: "dialog-cancel"
                onTriggered: confirmRemove.close()
            }
        ]
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
            text: i18n("Checks commands and package changes that are known to break Arch systems: partial upgrades, removing the last kernel, force-removing core packages. You can always override a specific check.")
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

        // Both of these were built after this screen was written, and the
        // screen went on saying they were not: the store has shown the build
        // script and recorded what was accepted for a while now, and the
        // campaign scanner ships as a package with a hook and a timer. A
        // settings page that reports working features as missing is worse
        // than one that is merely out of date -- it teaches people not to
        // believe it, including about the things it says are switched on.
        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Before installing:")
            text: i18n("Review packages before they build")
            enabled: cfg.aurEnabled
            checked: cfg.aurReview
            onToggled: cfg.aurReview = checked
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("The store shows you the build script before it builds anything, and shows what changed since the last time you accepted one. Turning this off builds AUR packages without asking, which is what an unattended AUR helper does.")
        }

        QQC2.CheckBox {
            id: campaignScan
            Kirigami.FormData.label: i18n("Security scanning:")
            text: i18n("Check for known compromised packages")
            enabled: cfg.aurEnabled
            checked: cfg.aurCampaignScanning
            onToggled: cfg.aurCampaignScanning = checked
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("Compares what you have installed against published attack campaigns, after every transaction and once a day. It cannot detect an attack nobody has reported yet, so it is not a substitute for reading what you install.")
        }

        HelperSelector {
            Kirigami.FormData.label: i18n("Command-line helper:")
            // root.cfg, not cfg: inside this component `cfg` is its own
            // property, so the unqualified name binds the property to itself.
            cfg: root.cfg
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: cfg.aurHelperStatus !== ""
                ? cfg.aurHelperStatus
                : i18n("A terminal tool for the AUR. Choosing one installs it and removes the other; both are built and signed by SakuraOS rather than compiled on this machine. The store reaches the AUR without either of them.")
        }

        // ---- Windows programs ---------------------------------------------
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Windows programs")
        }

        QQC2.CheckBox {
            id: wineBox
            Kirigami.FormData.label: i18n("Wine:")
            text: i18n("Run Windows programs")
            enabled: !cfg.wineBusy
            checked: cfg.wineEnabled
            // Not bound to a config key: this reports what is installed, and
            // toggling it does the installing. Rebound after every change so
            // a failed one puts the switch back where it was rather than
            // leaving it showing something that is not true.
            onToggled: cfg.setWineEnabled(checked)
            Component.onCompleted: {
                cfg.refreshWine()
                // The helper dropdown shows what is installed, so it has to
                // ask before it can show anything.
                cfg.refreshAurHelper()
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("Wine is a compatibility layer that lets some Windows programs run on Linux. Turning this on downloads Wine and the runtimes most programs need, about a gigabyte, and makes .exe and .msi files openable. Turning it off removes them again.")
        }

        QQC2.Label {
            visible: cfg.wineStatus !== ""
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            color: cfg.wineBusy ? Kirigami.Theme.textColor
                                : Kirigami.Theme.disabledTextColor
            text: cfg.wineStatus
        }

        QQC2.Label {
            visible: cfg.wineEnabled
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            // The part that makes this better than installing Wine yourself.
            text: i18n("Opening a Windows program asks first. Where a Linux version of the same application exists, SakuraOS offers that instead. Running an installer through a compatibility layer is rarely what anybody actually wanted.")
        }

        // Each Windows program runs in its own prefix, so this list is also
        // the uninstall: removing one is deleting its directory, with nothing
        // of it left behind in a shared one.
        // The Repeater lives inside its own ColumnLayout rather than directly
        // in the FormLayout. A Repeater's delegates are siblings wherever it
        // sits, and when the model changes the re-created ones are appended
        // at the end of the parent's children -- which in a FormLayout means
        // a remaining app jumping to the bottom of the page, below the next
        // section. One container, and they re-flow inside it.
        ColumnLayout {
            Kirigami.FormData.label: i18n("Installed:")
            // Against a multi-row column the label would otherwise centre
            // itself, landing beside whichever app happens to be in the
            // middle rather than at the top of the list it names.
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            visible: cfg.wineEnabled && cfg.windowsApps.length > 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                text: i18np("%1 Windows program", "%1 Windows programs",
                            cfg.windowsApps.length)
            }

            Repeater {
                model: cfg.wineEnabled ? cfg.windowsApps : []
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: modelData.name !== "" ? modelData.name : modelData.slug
                    }
                    QQC2.ToolButton {
                        icon.name: "edit-delete"
                        text: i18n("Remove")
                        display: QQC2.AbstractButton.IconOnly
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: i18n("Remove this program and everything it installed")
                        onClicked: confirmRemove.ask(modelData)
                    }
                }
            }
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

        // The canary exists now: it installs a machine from scratch every
        // night, applies the day's updates, restarts it and re-checks it, and
        // publishes what failed. sakura-update reads that list and holds those
        // packages back, so this switch controls something real -- it was
        // written when it did not, and stayed that way after it did.
        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Only install:")
            text: i18n("Updates that have been tested first")
            checked: cfg.updatesRequireCanary
            onToggled: cfg.updatesRequireCanary = checked
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("Every night a machine is installed from scratch, the day's updates are applied to it and it is restarted and checked. Anything that fails is held back from your machine until it is fixed, as is anything Arch publishes a manual step for. Turning this off installs updates as soon as they are published.")
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

        // These two settings are the whole of updates that belongs on a
        // settings page. What is being installed, what is held back and why,
        // and the restore points you can return to are a different question
        // from configuration, and they get their own window.
        QQC2.Button {
            Kirigami.FormData.label: i18n("More:")
            text: i18n("Open Update Center")
            icon.name: "system-software-update"
            onClicked: Qt.openUrlExternally("application:///org.sakuraos.updatecenter.desktop")
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            text: i18n("The settings above are all there is to configure. To see what is being installed, why anything is held back, and the restore points you can go back to, open the Update Center.")
        }
    }
}
