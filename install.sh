#!/bin/bash
# Install or update the plasmoid for the current user.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
id=local.omdrop

if kpackagetool6 -t Plasma/Applet -s "$id" >/dev/null 2>&1; then
  kpackagetool6 -t Plasma/Applet -u "$here/package"
  echo "Updated. To load the new version: systemctl --user restart plasma-plasmashell.service"
else
  kpackagetool6 -t Plasma/Applet -i "$here/package"
  echo "Installed. Add it from the panel: right-click > Add or Manage Widgets > Omdrop"
fi
