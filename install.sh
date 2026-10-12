#!/bin/bash
# Install or update the plasmoid for the current user, or remove it.
#
#   ./install.sh
#   ./install.sh --uninstall
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
id=io.github.luvingiane.omdrop
# What the releases up to 1.0.0 were installed as.
old_id=local.omdrop

# The widget list and the tray's settings find the icon by name, in the icon
# theme, and not inside the package.
icon="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/omdrop-plasmoid.svg"

installed() {
  kpackagetool6 -t Plasma/Applet -s "$1" >/dev/null 2>&1
}

case "${1:-}" in
  "") ;;
  --uninstall)
    for package in "$id" "$old_id"; do
      if installed "$package"; then
        kpackagetool6 -t Plasma/Applet -r "$package"
      fi
    done
    rm -f -- "$icon"
    echo "Removed. If the widget is still on a panel, take it off there too."
    exit 0
    ;;
  *)
    echo "Usage: $0 [--uninstall]" >&2
    exit 2
    ;;
esac

install -Dm644 "$here/package/contents/icons/omdrop.svg" "$icon"

if installed "$old_id"; then
  kpackagetool6 -t Plasma/Applet -r "$old_id"
  echo "Removed $old_id, the id of the releases up to 1.0.0."
  echo "A widget already on a panel is that one: remove it and add Omdrop again."
fi

if installed "$id"; then
  kpackagetool6 -t Plasma/Applet -u "$here/package"
  echo "Updated. To load the new version: systemctl --user restart plasma-plasmashell.service"
else
  kpackagetool6 -t Plasma/Applet -i "$here/package"
  echo "Installed. Add it from the panel: right-click > Add or Manage Widgets > Omdrop"
fi
