// What the helper dropdown passes on when somebody picks an item.
//
// This exists because the thing could not be tested any other way. The control
// is a QQC2 ComboBox, its list is a popup on its own surface, and synthetic
// input cannot reach a popup -- proven by driving an unrelated dropdown on the
// same page, which ignored clicks and keys identically. So the only way to know
// what the handler does is to emit the signal it listens to and watch what
// comes out.
//
// The bug it guards against is specific and quiet: currentIndex is bound to
// which helper is installed, and that binding is live while an item is being
// chosen. Read currentValue in the handler and it can already have been pulled
// back to the installed value -- so choosing "yay" applies "none", which with
// nothing installed does nothing at all, with no error to explain it.
import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "HelperSelector"
    when: windowShown
    width: 400
    height: 200

    // Stands in for the settings object, and records what it was told.
    QtObject {
        id: fakeCfg
        property bool aurEnabled: true
        property bool aurHelperBusy: false
        property string aurHelperInstalled: "none"
        property string aurHelper: ""
        property var appliedWith: []
        function applyAurHelper(name) {
            appliedWith.push(name)
        }
    }

    HelperSelector {
        id: selector
        cfg: fakeCfg
    }

    function init() {
        fakeCfg.appliedWith = []
        fakeCfg.aurHelperInstalled = "none"
        fakeCfg.aurHelper = ""
    }

    function test_choosing_yay_applies_yay() {
        selector.activated(0)
        compare(fakeCfg.appliedWith.length, 1)
        compare(fakeCfg.appliedWith[0], "yay")
        compare(fakeCfg.aurHelper, "yay")
    }

    function test_choosing_paru_applies_paru() {
        selector.activated(1)
        compare(fakeCfg.appliedWith[0], "paru")
    }

    function test_choosing_none_applies_none() {
        selector.activated(2)
        compare(fakeCfg.appliedWith[0], "none")
    }

    // The regression this component was extracted for. With yay installed the
    // binding holds currentIndex at yay; picking paru must still apply paru
    // rather than the value the binding is holding.
    function test_binding_does_not_override_the_choice() {
        fakeCfg.aurHelperInstalled = "yay"
        selector.activated(1)
        compare(fakeCfg.appliedWith[0], "paru",
                "the choice must come from the signal, not from currentValue")
    }

    // Reflects the machine rather than the stored preference.
    function test_shows_what_is_installed() {
        fakeCfg.aurHelperInstalled = "paru"
        compare(selector.currentIndex, 1)
        fakeCfg.aurHelperInstalled = "none"
        compare(selector.currentIndex, 2)
    }

    // Both switches that can take it away.
    function test_disabled_when_the_aur_is_off() {
        fakeCfg.aurEnabled = false
        compare(selector.enabled, false)
        fakeCfg.aurEnabled = true
        fakeCfg.aurHelperBusy = true
        compare(selector.enabled, false)
        fakeCfg.aurHelperBusy = false
        compare(selector.enabled, true)
    }

    // All three, in the order the page presents them, yay first.
    function test_offers_yay_paru_and_none() {
        compare(selector.count, 3)
        compare(selector.valueAt(0), "yay")
        compare(selector.valueAt(1), "paru")
        compare(selector.valueAt(2), "none")
    }
}
