# AYN Thor / Odin 2 — gyroscope (kernel layer)

Thor (SH5001) and Odin 2 (LSM6DSV) expose accelerometer and gyroscope via
**Qualcomm Sensor Core** on the ADSP. This kernel tree delivers the
**kernel + firmware layer**. Userspace lives in the monorepo:

`vendor/masi-motion/` → `sudo ./scripts/install-masi-motion.sh`

## Kernel vs userspace

| Layer | Location | What |
|-------|----------|------|
| **Kernel/DTB** | `boot/KERNEL` (`./make.sh`) | FastRPC SensorsPD, PDR routing, DT gyro, `CONFIG_UHID=y` |
| **Firmware** | `firmware/qcom/sm8550/ayn/thor/` | ADSP split `.mdt` (Thor SH5001); Odin 2 `adsp.mbn` intact |
| **Userspace** | `vendor/masi-motion/` | SSC + uinput IMU + InputPlumber deck-uhid |

`update.sh` **only installs kernel + firmware + modules**. After reboot:

```bash
sudo ./update.sh
sudo reboot
# userspace:
sudo ./scripts/install-masi-motion.sh
```

## Patches / overlays in this tree

- `patches/masi/1025-misc-fastrpc-adsp-sensor-pd-and-legacy-ioctl.patch`
- `patches/masi/1026-dt-bindings-misc-qcom-fastrpc-pd-routing.patch`
- `patches/masi/qcs8550-ayn-gyro-fastrpc.dtsi.frag` — remote heap + SensorsPD (all AYN SM8550)
- `patches/masi/qcs8550-ayn-thor-gyro-fastrpc-pd.dtsi.frag` — `qcom,pd-type` on Thor only
- `lib/gyro-firmware.sh` — Thor ADSP overlay in `firmware/`
- `vendor/qcom-gyro/firmware-thor-adsp/` — Thor ADSP blobs
- `config/golden.config` — `CONFIG_UHID=y` (required for virtual Deck/DualSense userspace pads)

## Thor vs Odin 2

| Device | IMU | DT note |
|--------|-----|---------|
| **Thor** | Senodia SH5001 | `qcom,pd-type` on FastRPC |
| **Odin 2** | ST LSM6DSV | no forced pd-type (first-free banks) |

## Userspace (`vendor/masi-motion`)

Gaming Mode uses **InputPlumber + deck-uhid** (not a second virtual pad).
Odin 2 look frame is locked as **`odin2-dsu-v9`** `(X, -Z, -Y)` in `qcom-motion`.

```bash
sudo ./scripts/install-masi-motion.sh
# or: cd vendor/masi-motion && sudo ./install.sh
```

**New images:** `finalize-handheld-rootfs.sh` installs masi-motion into the rootfs and the default AYN composite includes the IMU.

Includes qrtr/hexagonrpcd/libssc and `qcom-motion` (uinput Sunshine whitelist name +
optional DSU `:26760`). InputPlumber merges rsinput gamepad + IMU into one
`deck-uhid` device for Steam.

Details: `vendor/masi-motion/README.md`

## Known kernel-layer limitations

- Odin 2 needs the Android `persist` partition for factory calibration (consumed by userspace).
- The stack waits for the handheld ALSA card before opening FastRPC (ADSP is shared with audio).
- In DT, **`qcom,pd-type` is Thor-only**. Forcing it in common prevented SSC from publishing on Odin 2.
- Install Image + modules from the **same** build (full `./update.sh`). Image-only `make Image` can black-screen.
