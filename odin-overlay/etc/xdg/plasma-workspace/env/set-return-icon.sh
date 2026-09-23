#!/bin/bash
# Always put "Return to Gaming Mode" on the desktop (this is not a Jupiter).
# Icon is the same steamos-gamemode mark used on this handheld's current desktop.
set -eu

dest_icon="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
mkdir -p "$dest_icon"
if [[ -f /usr/share/icons/hicolor/scalable/apps/steamos-gamemode.svg ]]; then
  ln -sfn /usr/share/icons/hicolor/scalable/apps/steamos-gamemode.svg \
    "$dest_icon/steamos-gamemode.svg"
fi

mkdir -p "$HOME/Desktop"
if [[ -f /etc/skel/Desktop/Return.desktop ]]; then
  cp /etc/skel/Desktop/Return.desktop "$HOME/Desktop/Return.desktop"
  chmod 0755 "$HOME/Desktop/Return.desktop"
fi
rm -f "$HOME/Desktop/Decky Loader.desktop" \
      "$HOME/Desktop/install-decky.desktop"
