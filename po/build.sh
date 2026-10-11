#!/bin/bash
# Refresh the translation template from the QML sources, merge it into every
# catalogue, and compile the catalogues into the package.
#
#   po/build.sh
#
# To add a language: msginit --locale=<code> --input=po/template.pot
# --output-file=po/<code>.po, translate it, and run this again.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
domain=plasma_applet_local.omdrop

xgettext --from-code=UTF-8 --language=JavaScript -ki18n:1 -ki18np:1,2 \
  --package-name=omdrop-plasmoid --no-wrap -o po/template.pot \
  package/contents/ui/*.qml

for po in po/*.po; do
  lang=$(basename "$po" .po)
  msgmerge --quiet --update --backup=none --no-wrap "$po" po/template.pot
  out="package/contents/locale/$lang/LC_MESSAGES"
  mkdir -p "$out"
  msgfmt --check --statistics -o "$out/$domain.mo" "$po"
done
