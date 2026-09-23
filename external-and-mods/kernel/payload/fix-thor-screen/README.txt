AYN Thor — fix-thor-screen
==========================

Kernel/DTB (touch axis remap, bottom panel suspend) is already in boot/KERNEL
after ./make.sh. This folder is the **userspace** layer — run it manually on
the device after kernel install.

Quick start
-----------

  sudo ./update.sh          # from this repo (installs kernel)
  sudo reboot
  cd output/.../fix-thor-screen
  ./fix-thor.sh             # asks for root password; system-wide install only

What fix-thor.sh installs (root, under /usr and /etc only)
------------------------------------------------------------

  • udev rules        → /etc/udev/rules.d/99-thorch-touchscreen-calibration.rules
  • systemd           → thorch-touchscreen-setup.service
  • /usr/bin          → thorch-kwin-touch-map, thorch-display-setup, thorch-touchscreen-setup
  • KDE autostart     → /etc/xdg/autostart/ (touch map + display layout)

Nothing is copied into /home or ~/.config.

Requirements
------------

  • AYN Thor (ABL slot 4)
  • KDE Plasma on Wayland
  • qdbus6, kscreen-doctor (for display autostart)

Based on thorch-os/thorch — see docs/THOR-TOUCH.md in the kernel tree.
