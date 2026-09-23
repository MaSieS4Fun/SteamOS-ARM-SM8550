# Device matrix — ABL DTB chain (14 slots)

MaSi builds a single `KERNEL` whose zImage embeds **14 concatenated DTBs** in ROCKNIX index order.
Rocknix-ABL / LinuxLoader picks `chain[device_index]`.

| Slot | Device | SoC | Source |
|------|--------|-----|--------|
| 0 | AYN Odin 3 | SM8750 | reference blob (wrong SoC for this kernel) |
| 1 | AYN Odin 2 Portal | SM8550 | kbuild `qcs8550-ayn-odin2portal.dtb` |
| 2 | AYN Odin 2 | SM8550 | kbuild `qcs8550-ayn-odin2.dtb` |
| 3 | AYN Odin 2 Mini | SM8550 | **reference** `slot-03.dtb` (Odin 2 Mini reference; kbuild deferred — black-screen reports) |
| 4 | AYN Thor | SM8550 | kbuild `qcs8550-ayn-thor.dtb` |
| 5–6 | Retroid Pocket 6 | SM8550 | kbuild `qcs8550-retroidpocket-rp6.dtb` |
| 7 | KONKR Pocket FIT | SM8650 | reference blob (wrong SoC) |
| 8 | AYANEO Pocket S2 | SM8650 | reference blob (wrong SoC) |
| 9 | AYANEO Pocket ACE | SM8550 | kbuild `qcs8550-ayaneo-pocketace.dtb` |
| 10 | AYANEO Pocket DMG | SM8550 | kbuild `qcs8550-ayaneo-pocketdmg.dtb` |
| 11 | AYANEO Pocket DS | SM8550 | kbuild `qcs8550-ayaneo-pocketds.dtb` |
| 12 | AYANEO Pocket EVO | SM8550 | kbuild `qcs8550-ayaneo-pocketevo.dtb` |
| 13 | AYANEO Pocket S 2K | SM8550 | kbuild `qcs8550-ayaneo-pockets1.dtb` |

## AYANEO SM8550 bring-up notes

- DTS/common: `patches/masi/ayaneo/` (ported from Armbian `sm8550-6.18` + MaSi Pocket S 2K).
- Panel drivers: ACE (`DRM_PANEL_AR06_4INCH` from Armbian 7.0), DMG (`1020` AR02), DS lower (`1021` AR11), EVO (`ICNA3512`), S 2K (`1022` R63419 / `ayaneo,wt0600-2k`).
- ADSP firmware: staged as `qcom/sm8550/ayaneo` → `ayn/odin2` (Armbian firmware has no separate ayaneo tree yet).

Config: `config/dtb-chain.map`, `config/devices.conf`.

See [DTB-ABL.md](DTB-ABL.md), [DTB-INVENTORY.md](DTB-INVENTORY.md).
