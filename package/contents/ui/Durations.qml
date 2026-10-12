// The lengths a window can have: what the user reads, and what `omdrop on` is
// given. Shared by the popup and the settings page.
import QtQuick

QtObject {
    readonly property var list: [
        { label: i18n("10 minutes"), value: "10m" },
        { label: i18n("30 minutes"), value: "30m" },
        { label: i18n("1 hour"), value: "1h" },
        { label: i18n("One file only"), value: "once" },
        { label: i18n("Until I turn it off"), value: "forever" }
    ]
}
