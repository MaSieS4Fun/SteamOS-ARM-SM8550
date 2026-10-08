# MaSi kernel overlays (post-Armbian)

Applied after the matching Armbian `sm8550-<major.minor>` patch set (live archive + `dt/` board trees) via `lib/kbuild/patches.sh`.

| File | Purpose |
|------|---------|
| `1000-add-qcom-haptics-driver.patch` | Qualcomm HV haptics driver (`qcom-hv-haptics`) |
| `1002-haptics-driver-support-periodic-sine-and-fixes.patch` | Haptics sine/periodic + timing fixes |
| `1003-rsinput-add-ff.patch` | Route gamepad FF to PMIC haptics (controller rumble) |
| `1004-haptics-steam-ff-deadlock-fix.patch` | Safer HPWR brake poll + skip erase when idle |
| `1005-thor-ch13726a-reset-polarity-fix.patch` | Thor bottom AMOLED: fix inverted reset GPIO in `panel-ddic-ch13726a` |
| Thor touch (build hook + `fix-thor-screen/`) | `apply_masi_thor_touch_dts` in kernel; userspace via `output/.../fix-thor-screen/fix-thor.sh` — see `docs/THOR-TOUCH.md` |
| `1024-input-edt-ft5x06-retain-power-in-suspend.patch` | Thor bottom FT5452: skip power-off on deep suspend without wake IRQ |
| `1032-input-rsinput-suspend-resume-center-sticks.patch` | Center sticks + rumble cancel on suspend/resume |
| `1047-PCI-qcom-sm8550-skip-l23-and-suspend-opp.patch` | SM8550: skip PCIe L23 poll; honour `opp-suspend` (Armada 0512/0513) |
| `1048-arm64-dts-qcom-sm8550-add-a-pcie-suspend-opp.patch` | `pcie0` suspend OPP 1000 kBps DDR/LLCC floor (Armada 0520) |
| `1049-regulator-qcom-rpmh-add-suspend-state-support.patch` | RPMH SLEEP/WAKE votes for `regulator-state-mem` (Armada 0523) |
| `1050-thermal-qcom-tsens-mask-lower-irqs-across-suspend.patch` | Mask TSENS LOWER IRQs in prepare (Armada 0204) |
| `1051-tty-serial-qcom-geni-mask-non-console-irq-on-suspend.patch` | Mask gamepad UART IRQ across suspend (Armada 1006) |
| `1052-input-rsinput-quiesce-mcu-and-drop-vdd-on-suspend.patch` | Drop MCU enable/reset/VDD in suspend (Armada 1005/1007) |
| `1053` (overlay) | dwc3-qcom: `xhci-skip-phy-init-quirk` so USB PHY can `phy_exit` (Armada 0522; right-side CX heat) |
| `1054` (overlay) | sdhci-msm: mask controller IRQs while runtime suspended (Armada 0521; mmc0 IRQ storm) |
| `1055` (overlay) | ath12k: force WCN7850 `power_down` on S2RAM when HW is not OFF |
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

Patches `1006`–`1013` are the deep-suspend stack (ROCKNIX PR [#2952](https://github.com/ROCKNIX/distribution/pull/2952) / [#2954](https://github.com/ROCKNIX/distribution/pull/2954)). `1013` uses SoC-wide `qcom,sm8550` (not Thor-only). `1045`/`1046` are xiaodoudou UFS follow-ups (`recover-hibern8-enter-clk-gating`, `hold-clk-gating-across-system-pm`) needed so 7.2.8 does not hang in filesystem sync after a failed idle Hibern8 during suspend.

`1047`–`1054` are the Armada SM8550 energy subset that is compatible with MaSi **deep/S2RAM** (not their s2idle/fake-suspend default): PCIe skip L23 + suspend OPP, RPMH `regulator-state-mem`, TSENS LOWER mask, GENI UART IRQ mask, rsinput MCU quiesce, dwc3 skip-phy, sdhci IRQ mask. `1055` is MaSi: ath12k otherwise skips `power_down` unless `ATH12K_HW_STATE_OFF`. Do **not** force qcom PCIe host/pwrseq teardown when D3cold is not possible (that hung resume). Interconnect QoS (`0122`) is **not** carried (GMU HFI timeouts). Re-fetch with `scripts/fetch-rocknix-suspend-patches.py` only for **missing** 1006–1013 files. Set `SUSPEND_DEEP_PATCHES=0` to skip.

**Apply order:** `1011` (QMP RX LineCfg) runs before `1009`/`1010` so `ufs-qcom.c` hunks still match linux-7.0. The vendored `1011` also anchors on `qmp_ufs_init_registers()` (upstream name) instead of downstream `qmp_ufs_init()`.

Kconfig (also in `config/golden.config`): `CONFIG_INPUT_QCOM_HV_HAPTICS`, `CONFIG_JOYSTICK_RSINPUT`, `CONFIG_INPUT_FF_MEMLESS`.

See `docs/SUSPEND.md` for deep sleep testing and `docs/GYRO.md` for Thor/Odin 2 motion (ADSP Sensor Core → DSU :26760).

## AYANEO Pocket (SM8550)

- `ayaneo/` — common dtsi + ACE/DMG/DS/EVO/S1 board DTS (slots 9–13).
- `1020` AR02 DMG panel, `1021` AR11 DS secondary, `1022`/`1023` Renesas R63419 (Pocket S 2K).
