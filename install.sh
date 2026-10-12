#!/bin/bash
# Install or update the plasmoid for the current user.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
id=local.omdrop

# The widget list and the tray's settings find the icon by name, in the icon
# theme, and not inside the package.
install -Dm644 "$here/package/contents/icons/omdrop.svg" \
  "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/omdrop-plasmoid.svg"

if kpackagetool6 -t Plasma/Applet -s "$id" >/dev/null 2>&1; then
  kpackagetool6 -t Plasma/Applet -u "$here/package"
  echo "Updated. To load the new version: systemctl --user restart plasma-plasmashell.service"
else
  kpackagetool6 -t Plasma/Applet -i "$here/package"
  echo "Installed. Add it from the panel: right-click > Add or Manage Widgets > Omdrop"
fi
