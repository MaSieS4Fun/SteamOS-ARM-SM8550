# MaSi kernel overlays (post-Armbian)

Applied after the Armbian `sm8550-7.0` patch set via `lib/kbuild/patches.sh`.

| File | Purpose |
|------|---------|
| `1000-add-qcom-haptics-driver.patch` | Qualcomm HV haptics driver (`qcom-hv-haptics`) |
| `1002-haptics-driver-support-periodic-sine-and-fixes.patch` | Haptics sine/periodic + timing fixes |
| `1003-rsinput-add-ff.patch` | Route gamepad FF to PMIC haptics (controller rumble) |
| `1004-haptics-steam-ff-deadlock-fix.patch` | Safer HPWR brake poll + skip erase when idle |
| `1005-thor-ch13726a-reset-polarity-fix.patch` | Thor bottom AMOLED: fix inverted reset GPIO in `panel-ddic-ch13726a` |
| Thor touch (build hook + `fix-thor-screen/`) | `apply_masi_thor_touch_dts` in kernel; userspace via `output/.../fix-thor-screen/fix-thor.sh` — see `docs/THOR-TOUCH.md` |
| `1024-input-edt-ft5x06-retain-power-in-suspend.patch` | Thor bottom FT5452: skip power-off on deep suspend without wake IRQ |
| `1014-drm-hdmi-audio-hw-params.patch` | DP/HDMI: call `msm_dp_audio_prepare` from hdmi-codec `hw_params` |
| `1015-q6apm-dp-graph-start-on-trigger.patch` | DP/HDMI: defer `q6apm_graph_start` to PCM `trigger` |
| `1025-misc-fastrpc-adsp-sensor-pd-and-legacy-ioctl.patch` | FastRPC SensorsPD routing + PDR + Qualcomm legacy ioctl (gyro) |
| `1033-sound-aw88166-quiet-early-iis-probe.patch` | Odin/AYN: demote aw88166 early IIS/PLL retry `dev_err` → `dev_dbg` (panel spam ~21s boot) |
| `1026-dt-bindings-misc-qcom-fastrpc-pd-routing.patch` | DT bindings for `qcom,pd-type` / SensorsPD |
| `qcs8550-ayn-gyro-fastrpc.dtsi.frag` | Remote heap + SensorsPD FastRPC overrides (all AYN SM8550) |
| Gyro userspace | **External** project `giroscopio` (`./install.sh`) — not staged in kernel output; see `docs/GYRO.md` |
| `1013` | TSENS: skip uplow wake on all `qcom,sm8550` (PR #2954; was Thor-only) |
| `qcs8550-ayn-haptics.dtsi.frag` | Device-tree nodes for `pm8550b` haptics (all AYN boards) |
| `qcs8550-retroidpocket-rp6.dts` | Retroid Pocket 6 board DTS |

Patches `1006`–`1013` are the deep-suspend stack (ROCKNIX PR [#2952](https://github.com/ROCKNIX/distribution/pull/2952) / [#2954](https://github.com/ROCKNIX/distribution/pull/2954)). `1013` uses SoC-wide `qcom,sm8550` (not Thor-only). Re-fetch with `scripts/fetch-rocknix-suspend-patches.py` only for **missing** files (`--force` replaces vendored copies — avoid unless intentional). Set `SUSPEND_DEEP_PATCHES=0` to skip.

**Apply order:** `1011` (QMP RX LineCfg) runs before `1009`/`1010` so `ufs-qcom.c` hunks still match linux-7.0. The vendored `1011` also anchors on `qmp_ufs_init_registers()` (upstream name) instead of downstream `qmp_ufs_init()`.

Kconfig (also in `config/golden.config`): `CONFIG_INPUT_QCOM_HV_HAPTICS`, `CONFIG_JOYSTICK_RSINPUT`, `CONFIG_INPUT_FF_MEMLESS`.

See `docs/SUSPEND.md` for deep sleep testing and `docs/GYRO.md` for Thor/Odin 2 motion (ADSP Sensor Core → DSU :26760).

## AYANEO Pocket (SM8550)

- `ayaneo/` — common dtsi + ACE/DMG/DS/EVO/S1 board DTS (slots 9–13).
- `1020` AR02 DMG panel, `1021` AR11 DS secondary, `1022`/`1023` Renesas R63419 (Pocket S 2K).
