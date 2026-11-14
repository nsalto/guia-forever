#!/bin/bash
# Guia Forever updater for macOS: double click to install or update the addon from GitHub.
set -e
ADDONS="/Applications/World of Warcraft/_forever_/Interface/AddOns"
CFG="$HOME/Library/Application Support/GuiaForever/addons-path.txt"
[ -f "$CFG" ] && ADDONS="$(cat "$CFG")"
if [ ! -d "$ADDONS" ]; then
  ADDONS="$(osascript -e 'POSIX path of (choose folder with prompt "Elegí la carpeta World of Warcraft/_forever_/Interface/AddOns")' | sed 's#/$##')"
fi
mkdir -p "$(dirname "$CFG")"; printf '%s' "$ADDONS" > "$CFG"
echo "Carpeta de addons: $ADDONS"
TMP="$(mktemp -d)"
echo "Bajando la última versión..."
curl -fsSL -o "$TMP/guia.zip" "https://github.com/nsalto/guia-forever/releases/latest/download/GuiaForever.zip"
unzip -q "$TMP/guia.zip" -d "$TMP"
SRC="$TMP/GuiaForever"
rm -rf "$ADDONS/GuiaForever" "$ADDONS/GuiaForever_Data"
mv "$SRC" "$ADDONS/GuiaForever"
rm -rf "$TMP"
V="$(sed -n 's/^## Version: //p' "$ADDONS/GuiaForever/GuiaForever.toc")"
echo
echo "Listo: Guía Forever $V instalada. Si el juego está abierto, cerralo y abrilo de nuevo."
read -n 1 -s -r -p "Apretá una tecla para cerrar."
