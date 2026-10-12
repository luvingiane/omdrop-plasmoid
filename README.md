# omdrop-plasmoid

A KDE Plasma 6 widget for [omdrop](https://github.com/brentkearney/omdrop-plugin):
AirDrop with nearby Apple devices. omdrop ships as a bar widget for Omarchy;
this is the equivalent for Plasma.

It holds no AirDrop logic of its own. Every action is a call to the `omdrop`
command, so if `omdrop` works in a terminal, it works here.

## What it does

- **Panel icon**, coloured while this computer is visible. Click opens the
  popup; middle-click turns AirDrop on or off.
- **Switch** for visibility and a **duration** for the window: 10 minutes,
  30 minutes, 1 hour, one file only, or until you turn it off. Changing the
  duration while a window is open reschedules it.
- **Status** with a countdown. An error from omdrop appears as a banner under
  the heading.
- **Nearby devices**, by name. **Send…** opens a file chooser for that device,
  or drag files from Dolphin onto its row. The result of a send arrives as a
  notification.
- **Received files folder**, from the button at the top right or the context
  menu.

Names are looked up automatically while the popup is open and a device has no
name yet, at most every 15 seconds. Asking for a name connects to each device
and announces this computer over Bluetooth, which is why it only happens with
the popup open. A device answers only while its AirDrop receiver is awake: an
iPhone with its screen off stays "Apple device".

## Requirements

- KDE Plasma 6.
- `omdrop`, installed and working, on the `PATH` or in `~/.local/bin`, in a
  version that has `status --json` and `peers --json`.
- An omdrop radio backend that suits your Wi-Fi card. This widget was written
  and tested with [omdrop-owl](https://github.com/t4t5/omdrop-owl) on an Intel
  AX200.
- `notify-send` (the `libnotify` package), for the send notifications.

On a desktop other than Omarchy, omdrop calls a few `omarchy-*` commands for
its own notifications and for opening received links. Without them files still
arrive, but with no notification. Stand-ins are included: see
[Stand-ins for the omarchy commands](#stand-ins-for-the-omarchy-commands).

## Install

```bash
./install.sh
```

The script installs the package the first time and updates it afterwards. It
also copies the icon to `~/.local/share/icons/hicolor/scalable/apps/` as
`omdrop-plasmoid.svg`, where the widget list and the tray's settings look for
it. Then right-click the panel, choose **Add or Manage Widgets…** and search for
**Omdrop**. It also lives in the system tray, where it sits among the hidden
icons while AirDrop is off unless you set it to "Always shown".

After an update Plasma keeps the old version in memory:

```bash
systemctl --user restart plasma-plasmashell.service
```

## Stand-ins for the omarchy commands

Optional, and separate from the plasmoid. `shims/` holds replacements for the
three Omarchy commands omdrop calls:

| Command | What the stand-in does |
|---|---|
| `omarchy-notification-send` | sends the notification through `notify-send`; `--exec` runs when it is clicked |
| `omarchy-launch-browser` | opens the URL with `xdg-open` |
| `omarchy-default-terminal` | prints Plasma's default terminal, else `$TERMINAL`, else the first common one installed |

```bash
./install-shims.sh               # into /usr/local/bin (uses sudo)
./install-shims.sh --user        # into ~/.local/bin, no root
./install-shims.sh --uninstall   # remove them (add --user for that copy)
```

With `--user` the script also writes
`~/.config/environment.d/10-local-bin.conf`, which puts `~/.local/bin` on the
`PATH` of every systemd user unit, not only omdrop's: omdrop's watcher runs as
one and would not find the commands otherwise. `/usr/local/bin` is already on
that `PATH`, so the default install changes nothing else.

The script installs nothing on an Omarchy system, or where it finds one of
these commands that it did not install itself, and it only ever replaces or
removes its own files. If omdrop is on, turn it off and on again afterwards.

## Languages

The interface is in English, with an Italian translation. Plasma picks the
language from the session.

Catalogues are in `po/`, and the compiled ones are committed under
`package/contents/locale/` so that installing needs no build step. After
changing a string or a translation, run `po/build.sh` (it needs `gettext`). To
add a language:

```bash
msginit --locale=de --input=po/template.pot --output-file=po/de.po
# translate po/de.po, then:
po/build.sh
```

## Layout

| File | Role |
|---|---|
| `package/contents/ui/main.qml` | state, the calls to `omdrop`, the panel icon |
| `package/contents/ui/FullRepresentation.qml` | the popup |
| `package/contents/config/main.xml` | the two saved settings: duration and send wait |
| `package/contents/icons/omdrop.svg` | the icon |
| `package/contents/icons/omdrop-off.svg` | the icon struck through, for the popup while AirDrop is off |
| `po/` | translation template, catalogues and their build script |

Status comes from `omdrop status --json`, every 2 seconds with the popup open
and every 10 with it closed. Devices come from `omdrop peers --json`, every
4 seconds and only with the popup open. Sending runs
`omdrop send --to <address> --wait 60`.

## Limits

- No settings page. The duration is chosen in the popup; the send wait
  (60 seconds) can only be changed by hand in Plasma's configuration file.
- No "Contacts Only" mode and no known-senders list: use the `omdrop` command
  for those.
- No progress for a send, only "sending" and then the result.
- Tested on one machine (Plasma 6.7, Manjaro).
