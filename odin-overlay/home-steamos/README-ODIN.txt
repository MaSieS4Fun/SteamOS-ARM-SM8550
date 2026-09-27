SteamOS ARM for AYN Odin 2 / SM8550
===================================

⛔ CRITICAL — DO NOT run sync-frame-from-working-ubuntu-system.sh on Frame SD
   → black screen + cursor top-left. See CRITICAL-DO-NOT-UBUNTU-SESSION.txt
   Recovery: sudo ./scripts/restore-frame-hybrid-session-to-root.sh

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
- Gamepad: rsinput ±740 + InputPlumber deck-uhid (Steam Deck controller)

Controller
----------
The kernel exposes "AYN Odin2 Gamepad" (phys rsinput-gamepad/input0).
InputPlumber turns it into "Valve Steam Deck Controller" (deck-uhid).
Steam uses the official stack (QAM, Steam Input). It is not an Xbox 360 pad.

Target: deck-uhid + keyboard (OSK haptics). Touch: panel uses I2C (FT5426);
rsinput "Gamepad Touchpad" is ignored at image build time via udev
(72-sm8550-touch-dedupe.rules) so OSK does not duplicate keys.
gamescope --default-touch-mode 4 (Holo).
The Valve uhid pad is never treated as external HID.

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
Box64 is the system x86_64 converter (binfmt) — Decky PluginLoader uses it.
Valve FEX-Emu (from Steam when you force Proton x86_64) is for games only;
it must not replace Box64 globally. If Decky stops after a Steam update:
  pkexec /usr/lib/steamos/sm8550-restore-decky-box64
Install the loader from ARM-Manager → Decky if needed.

SM8550-Power and SM8550-LED come from the SteamOS-Ubuntu project
(https://github.com/MaSieS4Fun/SteamOS-Ubuntu).

SSH
---
OpenSSH server is enabled on port 22. Set a user password first
(Desktop → steamos-set-root-password or first-boot setup), then:
  ssh steamos@<device-ip>
Developer Mode in Steam also enables sshd (stock SteamOS path).

Power button
------------
Short press → suspend (systemd-logind). Stock SteamOS ignored the key
and relied on steamos-powerbuttond + steamvr, which is masked on SM8550.

Desktop keyboard (Plasma)
-------------------------
Virtual keyboard: Qt Virtual Keyboard (touch a text field in Desktop).
Game Mode uses Steam's built-in OSK (gamescope touch passthrough + xim).

lsfg-vk
-------
Vulkan layer: /usr/local/lib/liblsfg-vk.so
Config: ~/.config/lsfg-vk/conf.toml
Lossless Scaling DLL (after you install it in Steam):
  ~/.local/share/Steam/steamapps/common/Lossless Scaling/Lossless.dll
