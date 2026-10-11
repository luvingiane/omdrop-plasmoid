// Omdrop for Plasma: a panel front end to the `omdrop` command.
//
// Everything goes through the CLI: `status --json` and `peers --json` are
// polled, and the switch, the duration and the send buttons run `on`, `off`
// and `send`. The applet keeps no state of its own beyond the chosen duration.
import QtQuick
import QtQuick.Dialogs
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // What `omdrop status --json` last said.
    property bool installed: true
    property bool receiving: false
    property string mode: "off"          // off, timed, once, forever
    property int remaining: -1           // seconds left; -1 without a deadline
    property string deviceName: ""
    property string downloadDir: ""
    property string visibility: "everyone"

    // A command of ours that is still running: "on", "off" or "".
    property string pending: ""
    property string lastError: ""

    property var peers: []               // [{mac, name, rssi}]
    property var peerNames: ({})         // mac -> name, kept across polls
    property bool naming: false
    property double lastNaming: 0        // when names were last asked for, ms
    property var sending: ({})           // mac -> true while a send runs
    property string sendTarget: ""

    property bool statusBusy: false
    property bool peersBusy: false

    readonly property string duration: Plasmoid.configuration.duration
    readonly property int sendWait: Plasmoid.configuration.sendWait

    // plasmashell is a systemd user unit, and its PATH need not hold
    // ~/.local/bin, which is where `omdrop setup` puts the command.
    readonly property string path: 'PATH="$HOME/.local/bin:$PATH"'
    readonly property string omdrop: path + " omdrop"

    readonly property string statusText: {
        if (!installed)
            return i18n("The omdrop command is not installed");
        if (pending === "on")
            return i18n("Waking the radio…");
        if (pending === "off")
            return i18n("Turning off…");
        if (!receiving)
            return i18n("Off");
        let text = visibility === "contacts"
            ? i18n("Visible to contacts as “%1”", deviceName)
            : i18n("Visible to everyone as “%1”", deviceName);
        if (mode === "once")
            text += " · " + i18n("until the first file");
        else if (mode === "forever")
            text += " · " + i18n("until you turn it off");
        else if (remaining >= 0)
            text += " · " + formatTime(remaining);
        return text;
    }

    function formatTime(seconds) {
        const m = Math.floor(seconds / 60), s = seconds % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    function quote(text) {
        return "'" + String(text).replace(/'/g, "'\\''") + "'";
    }

    // omdrop animates its slow commands with carriage returns; the line that
    // says what happened is the last one.
    function lastLine(text) {
        const lines = String(text || "").split(/[\r\n]+/).map(l => l.trim()).filter(l => l !== "");
        return lines.length ? lines[lines.length - 1] : "";
    }

    function refresh() {
        if (statusBusy)
            return;
        statusBusy = true;
        exec.run(omdrop + " status --json", (code, out) => {
            statusBusy = false;
            installed = code !== 127;
            let status;
            try {
                status = JSON.parse(out);
            } catch (e) {
                return;
            }
            receiving = status.receiving === true;
            mode = status.mode || "off";
            remaining = typeof status.remaining === "number" ? status.remaining : -1;
            deviceName = status.name || "";
            downloadDir = status.dir || "";
            visibility = status.visibility || "everyone";
            if (!receiving)
                peers = [];
        });
    }

    function turnOn() {
        if (pending !== "")
            return;
        pending = "on";
        lastError = "";
        exec.run(omdrop + " on " + quote(duration), (code, out, err) => {
            pending = "";
            if (code !== 0)
                lastError = lastLine(err) || lastLine(out) || i18n("omdrop on exited with code %1", code);
            refresh();
        });
    }

    function turnOff() {
        if (pending !== "")
            return;
        pending = "off";
        lastError = "";
        exec.run(omdrop + " off", (code, out, err) => {
            pending = "";
            if (code !== 0)
                lastError = lastLine(err) || lastLine(out) || i18n("omdrop off exited with code %1", code);
            refresh();
        });
    }

    function toggle() {
        if (receiving)
            turnOff();
        else
            turnOn();
    }

    function setDuration(value) {
        if (value === duration)
            return;
        Plasmoid.configuration.duration = value;
        // A window that is already open takes the new length.
        if (receiving)
            turnOn();
    }

    function withNames(list) {
        return list.map(p => ({
            mac: p.mac,
            rssi: p.rssi,
            name: p.name || peerNames[p.mac] || ""
        }));
    }

    function refreshPeers() {
        if (peersBusy || naming || !receiving)
            return;
        peersBusy = true;
        exec.run(omdrop + " peers --json", (code, out) => {
            peersBusy = false;
            try {
                peers = withNames(JSON.parse(out));
            } catch (e) {
                peers = [];
            }
            // As omdrop's own panel does while its send section is open: a
            // device without a name is asked for it, but not on every poll.
            if (peers.some(p => !p.name) && Date.now() - lastNaming > 15000)
                lookUpNames();
        });
    }

    // Asking for names connects to each device and announces this computer
    // over Bluetooth, so it only happens while the popup is open.
    function lookUpNames() {
        if (naming || !receiving)
            return;
        naming = true;
        lastNaming = Date.now();
        exec.run(path + " timeout 60 omdrop peers -n --json", (code, out) => {
            naming = false;
            let list;
            try {
                list = JSON.parse(out);
            } catch (e) {
                return;
            }
            const names = Object.assign({}, peerNames);
            for (const p of list) {
                if (p.name)
                    names[p.mac] = p.name;
            }
            peerNames = names;
            peers = withNames(list);
        });
    }

    function markSending(mac, on) {
        const map = Object.assign({}, sending);
        if (on)
            map[mac] = true;
        else
            delete map[mac];
        sending = map;
    }

    function pickAndSend(mac) {
        sendTarget = mac;
        fileDialog.open();
    }

    function sendFiles(mac, urls) {
        const paths = [];
        for (const url of urls) {
            const text = String(url);
            if (text.startsWith("file://"))
                paths.push(decodeURIComponent(text.substring(7)));
        }
        if (paths.length === 0 || sending[mac])
            return;
        const who = peerNames[mac] || mac;
        markSending(mac, true);
        lastError = "";
        exec.run(omdrop + " send --to " + quote(mac) + " --wait " + sendWait
                 + " -- " + paths.map(quote).join(" "), (code, out, err) => {
            markSending(mac, false);
            if (code === 0) {
                notify("document-send", i18n("Sent to %1", who),
                       paths.length === 1 ? paths[0].replace(/^.*\//, "")
                                          : i18np("%1 file", "%1 files", paths.length));
            } else {
                lastError = lastLine(err) || lastLine(out) || i18n("omdrop send exited with code %1", code);
                notify("dialog-error", i18n("Could not send to %1", who), lastError);
            }
        });
    }

    function notify(icon, title, body) {
        exec.run("notify-send -a Omdrop -i " + quote(icon) + " -- " + quote(title) + " " + quote(body), null);
    }

    function openFolder() {
        if (downloadDir !== "")
            exec.run("xdg-open " + quote(downloadDir), null);
    }

    Plasmoid.icon: "document-share"
    Plasmoid.status: receiving || pending !== "" ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipMainText: "AirDrop"
    toolTipSubText: statusText

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: root.receiving ? i18n("Turn AirDrop Off") : i18n("Turn AirDrop On")
            icon.name: root.receiving ? "network-disconnect" : "network-connect"
            enabled: root.installed && root.pending === ""
            onTriggered: root.toggle()
        },
        PlasmaCore.Action {
            text: i18n("Open the received files folder")
            icon.name: "folder-download"
            enabled: root.downloadDir !== ""
            onTriggered: root.openFolder()
        }
    ]

    // One shell command per source. The executable engine keys a source by its
    // command line, so a numbered comment keeps two runs of the same command
    // apart.
    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []

        property var callbacks: ({})
        property int serial: 0

        function run(command, callback) {
            const source = command + " #" + (++serial);
            callbacks[source] = callback;
            connectSource(source);
        }

        onNewData: (source, data) => {
            const callback = callbacks[source];
            delete callbacks[source];
            disconnectSource(source);
            if (callback)
                callback(data["exit code"], data["stdout"], data["stderr"]);
        }
    }

    Timer {
        interval: root.expanded || root.pending !== "" ? 2000 : 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Count down between polls, so the time left moves every second.
    Timer {
        interval: 1000
        running: root.receiving && root.remaining > 0
        repeat: true
        onTriggered: root.remaining -= 1
    }

    Timer {
        interval: 4000
        running: root.expanded && root.receiving
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshPeers()
    }

    FileDialog {
        id: fileDialog
        title: i18n("Choose the files to send")
        fileMode: FileDialog.OpenFiles
        onAccepted: root.sendFiles(root.sendTarget, selectedFiles)
    }

    compactRepresentation: MouseArea {
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                root.toggle();
            else
                root.expanded = !root.expanded;
        }

        Kirigami.Icon {
            anchors.fill: parent
            source: Qt.resolvedUrl("../icons/omdrop.svg")
            isMask: true
            color: root.receiving ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
            opacity: root.pending !== "" ? 0.5 : (root.receiving ? 1 : 0.8)
            active: parent.containsMouse
        }
    }

    fullRepresentation: FullRepresentation {}
}
