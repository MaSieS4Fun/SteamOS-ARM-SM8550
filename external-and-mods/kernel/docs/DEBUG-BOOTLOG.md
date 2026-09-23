# Debug boot log — `/boot/masi-boot.log`

Diagnostic builds capture the full kernel ring buffer to a **text file on the FAT boot partition**, so testers can send logs without photographing the screen.

## Build (does not affect normal releases)

```bash
cd Kernel_MaSi-OS

DEBUG_BOOTLOG=1 OUTPUT_SUFFIX=masi-debug ./make.sh
sudo ./update.sh
sudo reboot
```

Optional extra cmdline tokens:

```bash
DEBUG_BOOTLOG=1 KERNEL_CMDLINE_EXTRA="initcall_debug msm_drm.debug=0x1" ./make.sh
```

(`initcall_debug` only prints if the kernel was built with `CONFIG_INITCALL_DEBUG`.)

## What gets written

| When | Where | Content |
|------|--------|---------|
| Initramfs `local-premount` | `/boot/masi-boot.log` | New session, cmdline, DT `model`, full `dmesg` |
| Every ~2 s in initramfs | same file | Incremental `dmesg -c` |
| Initramfs `local-bottom` | same file | Final `dmesg` before `switch_root` |
| First 120 s after login (systemd) | same file | Userspace `dmesg` (if boot continues) |

The log is **plain text**, suitable for email or GitHub issue attachment.

## Tester workflow (black screen)

1. Install debug kernel: `sudo ./update.sh` on **their** device (UUID repack).
2. ABL → correct device model → boot MaSi kernel.
3. Wait ~30 s (even if screen is black).
4. Power off.
5. Boot **ROCKNIX** or another Linux image on the **same SD card**.
6. Copy the log:

```bash
ls -la /boot/masi-boot.log
cp /boot/masi-boot.log ~/masi-boot.log
# or from PC: pull the SD boot partition
```

7. Send `masi-boot.log` (not a photo).

## What you can grep in the log

```bash
grep -iE 'panic|Oops|BUG:|error|fail|drm|dsi|panel|msm|mdss|Unable|timeout' masi-boot.log
grep -i 'Odin\|model\|cmdline' masi-boot.log | head -20
```

## Limits

- Messages from the first milliseconds of boot may be missing if the ring buffer wrapped (mitigated with `log_buf_len=2M` in cmdline).
- If the kernel hangs **before** initramfs runs, nothing is written — then only UART or pstore helps.
- `/boot` must be a mountable VFAT/exFAT partition (normal on these handhelds).

## Normal release builds

Leave `DEBUG_BOOTLOG` unset (default `0`). No boot log hook is added to the initramfs.
