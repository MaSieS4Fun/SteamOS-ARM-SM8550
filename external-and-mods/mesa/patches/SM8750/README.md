# Mesa SM8750 patches (Odin 3 / Adreno 830)

Source: `/home/masies/Desktop/SteamOS-Ubuntu/vendor/mesa/patches/SM8750/`

Do **not** apply the SM8550 Freedreno patches here. Odin 3 only needs:

| File | Effect |
| --- | --- |
| `0001-add-a830-chip-id.patch` | Extra A830 chip ids (`0xffff44050001`, `0x44050000`) |

`scripts/build-mesa-sm8750.sh` applies this patch only.
`scripts/install-mesa-sm8750.sh` installs `external-and-mods/mesa-sm8750/`.
