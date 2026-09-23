SteamOS ARM for AYN Odin 2 / SM8550
===================================

Preconfigured user:  steamos  (uid 1000, no password until first-boot setup)
Default session:     gamescope (Game Mode)

What this image changes
-----------------------
- Kernel 7.0.14-edge-sm8550 (modules + firmware + ABL KERNEL)
- gamescope with MSM backlight via sysfs
- MangoHud from the external-and-mods tree
- lsfg-vk + Decky plugin staged in this home
- Patched Freedreno / Turnip Vulkan
- Box64 (SD8G2) for Decky / x86_64
- Steam ROM Manager, UFS installer, Decky installer
- Gamepad: rsinput ±740 + InputPlumber deck-uhid + keyboard (OSK haptics)

Controller
----------
The kernel exposes "AYN Odin2 Gamepad" (phys rsinput-gamepad/input0).
InputPlumber turns it into "Valve Steam Deck Controller" (deck-uhid).
Steam uses the official stack (QAM, Steam Input). It is not an Xbox 360 pad.

Targets: deck-uhid + keyboard (on-screen keyboard haptics).
If a USB or Bluetooth keyboard or mouse is connected, the virtual keyboard
is turned off; it comes back on disconnect. The Valve uhid pad is ignored
for that toggle.

sm8550-fixpad applies EVIOCSABS ±740 before InputPlumber starts.

Partitions (steamos-sm8550.img)
-------------------------------
p1 vfat BOOT  — KERNEL for ABL (not the Steam Deck ESP)
p2 ext4 root  — system
p3 ext4 home  — /home/steamos, grown on first boot

This is the SteamOS PC/handheld layout (root + home), not Deck A/B.
ABL does not use EFI, so p1 is FAT with KERNEL.

Image
-----
make-steamos-sm8550.sh downloads SteamOS if needed, applies the overlay,
embeds the root UUID in KERNEL, and writes the .img.

  sudo ./make-steamos-sm8550.sh
  sudo dd if=steamos-sm8550.img of=/dev/sdX bs=4M status=progress conv=fsync

On ABL (Vol- at power on): Set the Device → Odin 2 → Linux → START.

Decky
-----
The decky-lsfg-vk plugin is already under ~/homebrew/plugins.
Box64 is on the system (binfmt). Install the loader from the desktop
"Decky Loader" shortcut if you want it.

SM8550-Power and SM8550-LED come from the SteamOS-Ubuntu project
(https://github.com/MaSieS4Fun/SteamOS-Ubuntu).

lsfg-vk
-------
Vulkan layer: /usr/local/lib/liblsfg-vk.so
Config: ~/.config/lsfg-vk/conf.toml
Lossless Scaling DLL (after you install it in Steam):
  ~/.local/share/Steam/steamapps/common/Lossless Scaling/Lossless.dll
