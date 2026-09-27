#!/bin/sh
# Discover runs flatpak in the user session; revokefs unmount is client-side.
if [ -r /usr/lib/steamos/sm8550-flatpak-env ]; then
  # shellcheck source=/dev/null
  . /usr/lib/steamos/sm8550-flatpak-env
fi
