// The popup: the switch and the window's length in the heading, then what
// omdrop is doing, then the Apple devices nearby and a way to send to each.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

PlasmaExtras.Representation {
    id: full

    Layout.minimumWidth: Kirigami.Units.gridUnit * 20
    Layout.minimumHeight: Kirigami.Units.gridUnit * 18
    Layout.preferredWidth: Kirigami.Units.gridUnit * 22
    Layout.preferredHeight: Kirigami.Units.gridUnit * 22
    collapseMarginsHint: true

    readonly property var durations: [
        { label: i18n("10 minutes"), value: "10m" },
        { label: i18n("30 minutes"), value: "30m" },
        { label: i18n("1 hour"), value: "1h" },
        { label: i18n("One file only"), value: "once" },
        { label: i18n("Until I turn it off"), value: "forever" }
    ]

    header: PlasmaExtras.PlasmoidHeading {
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Switch {
                text: "AirDrop"
                checked: root.receiving
                enabled: root.installed && root.pending === ""
                onToggled: {
                    root.toggle();
                    // The switch shows what omdrop says, not what was clicked.
                    checked = Qt.binding(() => root.receiving);
                }
            }

            PlasmaComponents.BusyIndicator {
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                running: root.pending !== ""
                visible: running
            }

            Item {
                Layout.fillWidth: true
            }

            PlasmaComponents.ComboBox {
                model: full.durations
                textRole: "label"
                valueRole: "value"
                enabled: root.installed && root.pending === ""
                Component.onCompleted: currentIndex = Math.max(0, indexOfValue(root.duration))
                onActivated: root.setDuration(currentValue)

                PlasmaComponents.ToolTip {
                    text: i18n("How long to stay visible")
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "folder-download"
                enabled: root.downloadDir !== ""
                onClicked: root.openFolder()

                PlasmaComponents.ToolTip {
                    text: i18n("Open the received files folder")
                }
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        PlasmaComponents.Label {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            text: root.statusText
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            visible: root.lastError !== ""
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                Layout.alignment: Qt.AlignTop
                source: "dialog-error"
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.lastError
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
            }

            PlasmaComponents.ToolButton {
                Layout.alignment: Qt.AlignTop
                icon.name: "dialog-close"
                onClicked: root.lastError = ""
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            Layout.topMargin: Kirigami.Units.smallSpacing
            visible: root.receiving

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 5
                text: i18n("Nearby devices")
                opacity: 0.7
            }

            PlasmaComponents.BusyIndicator {
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                running: root.naming
                visible: running
            }

            PlasmaComponents.ToolButton {
                text: i18n("Refresh names")
                icon.name: "view-refresh"
                enabled: root.peers.length > 0 && !root.naming

                onClicked: root.lookUpNames()

                PlasmaComponents.ToolTip {
                    text: i18n("Connects to each device and announces this computer over Bluetooth")
                }
            }
        }

        PlasmaComponents.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: peerList

                clip: true
                model: root.receiving ? root.peers : []
                topMargin: Kirigami.Units.smallSpacing
                bottomMargin: Kirigami.Units.smallSpacing

                delegate: Item {
                    id: row

                    required property var modelData
                    readonly property bool busy: root.sending[modelData.mac] === true

                    width: peerList.width
                    height: rowLayout.implicitHeight + Kirigami.Units.smallSpacing * 2

                    // Files dragged from the file manager onto a device go to it.
                    DropArea {
                        id: drop
                        anchors.fill: parent
                        onDropped: dropEvent => {
                            if (dropEvent.hasUrls)
                                root.sendFiles(row.modelData.mac, dropEvent.urls);
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        anchors.rightMargin: Kirigami.Units.smallSpacing
                        radius: Kirigami.Units.cornerRadius
                        color: Kirigami.Theme.highlightColor
                        opacity: drop.containsDrag ? 0.3 : 0
                    }

                    RowLayout {
                        id: rowLayout

                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.largeSpacing
                        anchors.rightMargin: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing

                        Kirigami.Icon {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                            source: /mac/i.test(row.modelData.name) ? "computer-laptop" : "smartphone"
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: row.modelData.name || i18n("Apple device")
                                elide: Text.ElideRight
                            }

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: row.busy ? i18n("Sending: accept it on the device") : row.modelData.mac
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                                elide: Text.ElideRight
                            }
                        }

                        PlasmaComponents.BusyIndicator {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            running: row.busy
                            visible: running
                        }

                        PlasmaComponents.Button {
                            text: i18n("Send…")
                            icon.name: "document-send"
                            enabled: !row.busy
                            onClicked: root.pickAndSend(row.modelData.mac)
                        }
                    }
                }

                PlasmaExtras.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 4
                    visible: peerList.count === 0
                    iconName: root.receiving ? "smartphone" : "network-disconnect"
                    text: {
                        if (!root.installed)
                            return i18n("omdrop is not installed");
                        return root.receiving ? i18n("No Apple devices in sight") : i18n("AirDrop is off");
                    }
                    explanation: {
                        if (!root.installed)
                            return i18n("The omdrop command is needed in ~/.local/bin or on the PATH.");
                        if (root.receiving)
                            return i18n("On the iPhone, set AirDrop to “Everyone for 10 Minutes” and open the share sheet.");
                        return i18n("Turn it on to receive files and see nearby devices.");
                    }
                }
            }
        }
    }
}
