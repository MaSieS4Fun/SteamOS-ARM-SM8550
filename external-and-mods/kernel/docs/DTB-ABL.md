# ABL multidevice boot — DTB selection

## How ABL works

The **ABL** reads `boot/KERNEL`, decompresses `gzip(Image)` + **concatenated DTB chain**, and picks **`chain[device_index]`** using the model stored in ROCKNIX-ABL (“Set the Device”).

Do **not** use `devicetree=` / `dtb=` in cmdline.

## Reference Slot Order

Extracted from `reference-boot-partition/KERNEL` (works on all SM8550 units):

| Slot | Device |
|------|--------|
| 0 | (Odin 3 / other SoC — index padding) |
| **1** | **Odin 2 Portal** |
| **2** | **Odin 2** |
| **3** | **Odin 2 Mini** (reference DTB — not kbuild) |
| **4** | **Thor** |
| **5 / 6** | **Retroid Pocket 6** |
| 7–8 | SM8650 refs (Pocket FIT, Pocket S2 — **wrong SoC** for this kernel) |
| 9–13 | AYANEO Pocket ACE / DMG / DS / EVO / S 2K (SM8550 kbuild) |

MaSi previously used `0=Odin2, 1=Mini, 2=Portal…` — **wrong index map**. ABL index 2 (Odin 2) received Portal’s DTB, index 3 (Mini) received Thor’s DTB, etc.

Editable map: `config/dtb-chain.map` (14 slots, reference-aligned).

```bash
./scripts/extract-reference-dtb-chain.sh   # refresh reference/dtb-chain/
```

## ABL: set the correct device

1. Hold **Volume Down** at power-on → ABL menu  
2. **Set the Device** → exact model  
3. **Boot Mode** = Linux → **START**

## Verification

```bash
./make.sh
# log should show slot-01=portal, slot-02=odin2, slot-03=mini …

tr -d '\0' < /proc/device-tree/model   # after boot
```

See also [MULTI-DEVICE-DIST.md](MULTI-DEVICE-DIST.md) (UUID / initrd).
