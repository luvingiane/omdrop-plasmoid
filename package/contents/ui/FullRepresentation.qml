// The popup, laid out as Plasma's own applets are: the switch and the window's
// length in the heading, an error under it, then what omdrop is doing and the
// Apple devices nearby, each with a way to send to it.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.ksvg as KSvg
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

    // The list's margin, as in Plasma's own lists, and where a row's content
    // starts inside it: text outside the list lines up with the rows.
    readonly property real listMargin: Kirigami.Units.smallSpacing * 2
    readonly property real rowInset: Kirigami.Units.smallSpacing

    Durations {
        id: durations
    }

    // Files dragged from a file manager. One area over the whole popup, the
    // heading included, tells main.qml that they are still here; dropped on a
    // device, they go to it. The row under them lights up as under the pointer.
    background: DropArea {
        z: 1

        function rowAt(x, y) {
            const p = mapToItem(peerList, x, y);
            if (!peerList.contains(p))
                return null;
            return peerList.itemAt(p.x + peerList.contentX, p.y + peerList.contentY);
        }

        onContainsDragChanged: {
            root.dragOverPopup = containsDrag;
            if (!containsDrag)
                peerList.currentIndex = -1;
        }
        onPositionChanged: drag => {
            const row = rowAt(drag.x, drag.y);
            peerList.currentIndex = row ? row.index : -1;
        }
        onDropped: drop => {
            const row = rowAt(drop.x, drop.y);
            if (row && drop.hasUrls)
                root.sendFiles(row.modelData.mac, drop.urls);
        }
    }

    header: PlasmaExtras.PlasmoidHeading {
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Switch {
                // The margin Plasma's applets leave before their switches.
                Layout.leftMargin: Kirigami.Units.smallSpacing
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
                id: durationBox

                function sync() {
                    currentIndex = Math.max(0, indexOfValue(root.duration));
                }

                model: durations.list
                textRole: "label"
                valueRole: "value"
                enabled: root.installed && root.pending === ""
                Component.onCompleted: sync()
                onActivated: root.setDuration(currentValue)

                // The settings page changes it too.
                Connections {
                    target: root
                    function onDurationChanged() {
                        durationBox.sync();
                    }
                }

                PlasmaComponents.ToolTip {
                    text: i18n("How long to stay visible")
                }
            }

            PlasmaComponents.ToolButton {
                id: folderButton

                text: i18n("Open the received files folder")
                icon.name: "folder-download"
                display: PlasmaComponents.AbstractButton.IconOnly
                enabled: root.downloadDir !== ""
                onClicked: root.openFolder()

                PlasmaComponents.ToolTip {
                    text: folderButton.text
                }
            }

            PlasmaComponents.ToolButton {
                id: pinButton

                text: i18n("Keep Open")
                icon.name: "window-pin"
                display: PlasmaComponents.AbstractButton.IconOnly
                visible: !root.inTray
                checkable: true
                checked: root.pinned
                onToggled: root.setPinned(checked)

                PlasmaComponents.ToolTip {
                    text: pinButton.text
                }
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            position: Kirigami.InlineMessage.Position.Header
            text: root.lastError
            visible: root.lastError !== ""
            showCloseButton: true
            // Its close button hides it by hand, which drops the binding.
            onVisibleChanged: {
                if (!visible) {
                    root.lastError = "";
                    visible = Qt.binding(() => root.lastError !== "");
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: full.listMargin
            Layout.leftMargin: full.listMargin + full.rowInset
            Layout.rightMargin: full.listMargin + full.rowInset
            visible: root.installed && (root.receiving || root.pending !== "")
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.visibilityText
                wrapMode: Text.WordWrap
            }

            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignTop
                text: root.windowText
                visible: text !== ""
                opacity: 0.75
                // Digits of one width, so the countdown does not shift as it runs.
                font.features: { "tnum": 1 }
            }
        }

        PlasmaComponents.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth - contentItem.leftMargin - contentItem.rightMargin
            PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

            contentItem: ListView {
                id: peerList

                clip: true
                model: root.receiving ? root.peers : []
                currentIndex: -1
                topMargin: Kirigami.Units.smallSpacing
                bottomMargin: full.listMargin
                leftMargin: full.listMargin
                rightMargin: full.listMargin
                spacing: Kirigami.Units.smallSpacing

                highlight: PlasmaExtras.Highlight {}
                highlightMoveDuration: Kirigami.Units.shortDuration
                highlightResizeDuration: Kirigami.Units.shortDuration

                header: count > 0 ? peersHeader : null

                // PlasmaExtras.ListSectionHeader, with room for the refresh
                // button at the end of its line.
                Component {
                    id: peersHeader

                    RowLayout {
                        width: peerList.width - peerList.leftMargin - peerList.rightMargin
                        spacing: Kirigami.Units.largeSpacing

                        Kirigami.Heading {
                            Layout.leftMargin: full.rowInset
                            level: 5
                            type: Kirigami.Heading.Primary
                            font.weight: Font.Bold
                            opacity: 0.75
                            text: i18n("Nearby devices")
                            elide: Text.ElideRight
                        }

                        KSvg.SvgItem {
                            Layout.fillWidth: true
                            imagePath: "widgets/line"
                            elementId: "horizontal-line"
                        }

                        PlasmaComponents.BusyIndicator {
                            Layout.preferredWidth: refreshButton.implicitHeight
                            Layout.preferredHeight: refreshButton.implicitHeight
                            Layout.rightMargin: full.rowInset
                            running: root.naming
                            visible: running
                        }

                        PlasmaComponents.ToolButton {
                            id: refreshButton

                            Layout.rightMargin: full.rowInset
                            text: i18n("Refresh names")
                            icon.name: "view-refresh"
                            display: PlasmaComponents.AbstractButton.IconOnly
                            visible: !root.naming
                            onClicked: root.lookUpNames()

                            PlasmaComponents.ToolTip {
                                text: refreshButton.text + "\n"
                                      + i18n("Connects to each device and announces this computer over Bluetooth")
                            }
                        }
                    }
                }

                delegate: PlasmaExtras.ExpandableListItem {
                    id: row

                    required index
                    required property var modelData
                    readonly property bool busy: root.sending[modelData.mac] === true

                    width: peerList.width - peerList.leftMargin - peerList.rightMargin

                    icon: {
                        if (/mac/i.test(modelData.name))
                            return "computer-laptop";
                        return /ipad/i.test(modelData.name) ? "tablet" : "phone-apple-iphone";
                    }
                    title: modelData.name || i18n("Apple device")
                    subtitle: busy ? i18n("Sending: accept it on the device") : modelData.mac
                    isBusy: busy
                    defaultActionButtonAction: QQC2.Action {
                        text: i18n("Send…")
                        icon.name: "document-send"
                        onTriggered: root.pickAndSend(row.modelData.mac)
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 4
                    visible: peerList.count === 0
                    spacing: Kirigami.Units.gridUnit

                    // PlaceholderMessage takes its icon by name, from the icon
                    // theme. Ours is a file, drawn here the way it draws its own.
                    Kirigami.Icon {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.round(Kirigami.Units.iconSizes.huge * 1.5)
                        Layout.preferredHeight: Math.round(Kirigami.Units.iconSizes.huge * 1.5)
                        source: Qt.resolvedUrl(root.receiving ? "../icons/omdrop.svg" : "../icons/omdrop-off.svg")
                        isMask: true
                        color: Kirigami.Theme.textColor
                        opacity: 0.75
                    }

                    PlasmaExtras.PlaceholderMessage {
                        Layout.fillWidth: true
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
}
