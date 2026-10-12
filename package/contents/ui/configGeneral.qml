// The settings page: how long a window lasts, how long a send waits, and the
// popup's pin.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property string cfg_duration
    property alias cfg_sendWait: sendWait.value
    property alias cfg_pin: pin.checked

    // Plasma hands the page every setting's default as well.
    property string cfg_durationDefault
    property int cfg_sendWaitDefault
    property bool cfg_pinDefault

    // What the user reads, and what `omdrop on` is given.
    readonly property var durations: [
        { label: i18n("10 minutes"), value: "10m" },
        { label: i18n("30 minutes"), value: "30m" },
        { label: i18n("1 hour"), value: "1h" },
        { label: i18n("One file only"), value: "once" },
        { label: i18n("Until I turn it off"), value: "forever" }
    ]

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: duration

            function sync() {
                currentIndex = Math.max(0, indexOfValue(page.cfg_duration));
            }

            Kirigami.FormData.label: i18n("Stay visible for:")
            model: page.durations
            textRole: "label"
            valueRole: "value"
            Component.onCompleted: sync()
            onActivated: page.cfg_duration = currentValue

            // The Defaults button changes the setting from outside.
            Connections {
                target: page
                function onCfg_durationChanged() {
                    duration.sync();
                }
            }
        }

        QQC2.SpinBox {
            id: sendWait

            Kirigami.FormData.label: i18n("Wait for the recipient for:")
            from: 5
            to: 600
            stepSize: 5
            textFromValue: value => i18np("%1 second", "%1 seconds", value)
            valueFromText: text => parseInt(text)
        }

        QQC2.CheckBox {
            id: pin

            Kirigami.FormData.label: i18n("Popup:")
            text: i18n("Keep open when another window takes the focus")
        }
    }
}
