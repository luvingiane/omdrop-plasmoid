// Omdrop for Plasma: a panel front end to the `omdrop` command.
//
// Everything goes through the CLI: `status --json` and `peers --json` are
// polled, and the switch and the send buttons run `on`, `off` and `send`. The
// applet keeps no state of its own beyond its settings.
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

    // The link being typed, and the device whose row is open on it. Kept
    // here because the popup rebuilds its rows whenever a device or a name
    // changes.
    property string linkDraft: ""
    property string linkPeer: ""

    property bool statusBusy: false
    property bool peersBusy: false

    readonly property string duration: Plasmoid.configuration.duration
    readonly property int sendWait: Plasmoid.configuration.sendWait
    readonly property bool pinned: Plasmoid.configuration.pin

    // The system tray draws the heading of the popup, with a pin of its own.
    readonly property bool inTray: Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentDrawsPlasmoidHeading

    // Files dragged from another window: over the panel icon, and over the
    // popup that opens under them. `dragOpened` holds for as long as that
    // popup is open.
    property bool dragOverIcon: false
    property bool dragOverPopup: false
    property bool dragOpened: false

    // plasmashell is a systemd user unit, and its PATH need not hold
    // ~/.local/bin, which is where `omdrop setup` puts the command.
    readonly property string path: 'PATH="$HOME/.local/bin:$PATH"'
    readonly property string omdrop: path + " omdrop"

    // Who can see this computer, or what omdrop is busy doing.
    readonly property string visibilityText: {
        if (!installed)
            return i18n("The omdrop command is not installed");
        if (pending === "on")
            return i18n("Waking the radio…");
        if (pending === "off")
            return i18n("Turning off…");
        if (!receiving)
            return i18n("Off");
        return visibility === "contacts"
            ? i18n("Visible to contacts as “%1”", deviceName)
            : i18n("Visible to everyone as “%1”", deviceName);
    }

    // How long it stays visible; empty when there is nothing to say.
    readonly property string windowText: {
        if (!installed || pending !== "" || !receiving)
            return "";
        if (mode === "once")
            return i18n("until the first file");
        if (mode === "forever")
            return i18n("until you turn it off");
        return remaining >= 0 ? formatTime(remaining) : "";
    }

    readonly property string statusText: windowText === "" ? visibilityText : visibilityText + " · " + windowText

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

    function setPinned(on) {
        Plasmoid.configuration.pin = on;
    }

    function withNames(list) {
        return list.map(p => ({
            mac: p.mac,
            rssi: p.rssi,
            name: p.name || peerNames[p.mac] || ""
        }));
    }

    // The popup rebuilds its list whenever `peers` changes, so it changes only
    // when a device or a name does: the signal strength moves on every poll.
    function setPeers(list) {
        const key = l => JSON.stringify(l.map(p => [p.mac, p.name]));
        const next = withNames(list);
        if (key(next) !== key(peers))
            peers = next;
    }

    function refreshPeers() {
        if (peersBusy || naming || !receiving)
            return;
        peersBusy = true;
        exec.run(omdrop + " peers --json", (code, out) => {
            peersBusy = false;
            try {
                setPeers(JSON.parse(out));
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
            setPeers(list);
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

    // An http or https link, as omdrop takes one, or "" for anything else.
    // An address typed without its scheme gets https://.
    function webLink(text) {
        let link = String(text).trim();
        if (link !== "" && !/^[a-z][a-z0-9+.-]*:(?!\d)/i.test(link))
            link = "https://" + link;
        return /^https?:\/\/[^\s\/][^\s]*$/i.test(link) ? link : "";
    }

    // What a drop carries: the URLs of files or links, or a link dragged as
    // plain text.
    function dropUrls(drop) {
        if (drop.hasUrls)
            return drop.urls;
        return drop.hasText ? [drop.text.trim()] : [];
    }

    function sendLink(mac, text) {
        const link = webLink(text);
        if (link !== "")
            send(mac, [link]);
    }

    // file:// URLs go as the files they name, http and https ones as links.
    // A send carries one kind or the other; given both, omdrop says so.
    function send(mac, urls) {
        const items = [];
        let files = 0;
        for (const url of urls) {
            const text = String(url);
            if (text.startsWith("file://")) {
                items.push(decodeURIComponent(text.substring(7)));
                files++;
            } else if (/^https?:\/\//i.test(text)) {
                items.push(text);
            }
        }
        if (items.length === 0 || sending[mac])
            return;
        const who = peerNames[mac] || mac;
        markSending(mac, true);
        lastError = "";
        exec.run(omdrop + " send --to " + quote(mac) + " --wait " + sendWait
                 + " -- " + items.map(quote).join(" "), (code, out, err) => {
            markSending(mac, false);
            if (code === 0) {
                let what;
                if (items.length === 1)
                    what = files ? items[0].replace(/^.*\//, "") : items[0];
                else
                    what = files ? i18np("%1 file", "%1 files", files)
                                 : i18np("%1 link", "%1 links", items.length);
                notify("document-send", i18n("Sent to %1", who), what);
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

    Plasmoid.icon: "omdrop-plasmoid"
    Plasmoid.status: receiving || pending !== "" ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipMainText: "AirDrop"
    toolTipSubText: statusText

    // Plasma closes the popup whenever the focus moves to another window, and
    // it moves as dragged files cross from the panel to the popup.
    hideOnWindowDeactivate: !pinned && !dragOpened
    onExpandedChanged: {
        if (!root.expanded)
            dragOpened = false;
    }

    // A window that is already open takes the new length from the settings.
    onDurationChanged: {
        if (receiving)
            turnOn();
    }

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
    // command line; a comment with the applet id keeps the runs of two copies
    // of the applet apart.
    //
    // A command keeps the same source name from one run to the next. With a
    // new name per run (a counter, say) the engine and the DataSource keep
    // something for every name they have ever seen, at a cost that grows with
    // them, and after hours plasmashell's main thread spends its time there.
    //
    // A source still known to the engine answers with its old result without
    // running again, so a command is started again only after the engine has
    // removed its source (sourceRemoved; the `sources` property is not updated
    // then, so it cannot tell). A request that comes earlier waits in `queued`.
    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []

        property var running: ({})       // source -> callback of the run in progress
        property var leaving: ({})       // source -> when it was disconnected, in ms
        property var queued: ({})        // source -> callbacks waiting for their turn

        function run(command, callback) {
            const source = command + " # " + Plasmoid.id;
            if (!queued[source])
                queued[source] = [];
            queued[source].push(callback);
            runQueued(source);
        }

        // Starts the next waiting run of a source, once the engine has let
        // it go.
        function runQueued(source) {
            const waiting = queued[source];
            if (!waiting || source in running || source in leaving)
                return;
            const callback = waiting.shift();
            if (waiting.length === 0)
                delete queued[source];
            running[source] = callback || null;
            connectSource(source);
        }

        onNewData: (source, data) => {
            // An update without an exit code comes before the process has
            // finished: wait for the real result.
            if (data["exit code"] === undefined || !(source in running))
                return;
            const callback = running[source];
            delete running[source];
            leaving[source] = Date.now();
            disconnectSource(source);
            if (callback)
                callback(data["exit code"], data["stdout"], data["stderr"]);
        }

        // The next run starts once the engine has finished removing the
        // source: connecting it again from inside the removal leaves the new
        // run without a removal of its own.
        onSourceRemoved: source => {
            delete leaving[source];
            Qt.callLater(() => runQueued(source));
        }
    }

    // The engine removes a source a few milliseconds after it is let go; one
    // that has not gone after a few seconds is assumed gone, so that a missed
    // removal cannot hold its command back for good.
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            const now = Date.now();
            for (const source of Object.keys(exec.leaving)) {
                if (now - exec.leaving[source] > 5000) {
                    delete exec.leaving[source];
                    exec.runQueued(source);
                }
            }
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

    // The drag that opened the popup is over neither the icon nor the popup:
    // given the time to cross from one to the other, the files were dropped or
    // taken elsewhere, and the popup closes as it opened.
    Timer {
        interval: 1000
        running: root.dragOpened && !root.dragOverIcon && !root.dragOverPopup
        onTriggered: root.expanded = false
    }

    FileDialog {
        id: fileDialog
        title: i18n("Choose the files to send")
        fileMode: FileDialog.OpenFiles
        onAccepted: root.send(root.sendTarget, selectedFiles)
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
            // Struck through while off: the colour alone does not show on
            // every theme.
            source: Qt.resolvedUrl(root.receiving ? "../icons/omdrop.svg" : "../icons/omdrop-off.svg")
            isMask: true
            color: root.receiving ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
            opacity: root.pending !== "" ? 0.5 : (root.receiving ? 1 : 0.8)
            active: parent.containsMouse
        }

        // Files held over the icon open the popup, to be dropped on a device:
        // as Plasma's default icon does for the applets that ask for it, and
        // with the same delay. Dropped on the icon itself, they go to the one
        // device in sight, when there is just one.
        DropArea {
            anchors.fill: parent
            onContainsDragChanged: {
                root.dragOverIcon = containsDrag;
                if (containsDrag) {
                    dropTimer.restart();
                    // The devices are only looked for while the popup is open.
                    root.refreshPeers();
                } else {
                    dropTimer.stop();
                }
            }
            onDropped: drop => {
                if (root.receiving && root.peers.length === 1)
                    root.send(root.peers[0].mac, root.dropUrls(drop));
            }

            Timer {
                id: dropTimer
                interval: 250
                onTriggered: {
                    if (!root.expanded) {
                        root.dragOpened = true;
                        root.expanded = true;
                    }
                }
            }
        }
    }

    fullRepresentation: FullRepresentation {}
}
