# Internal UFS boot (ROCKNIX ABL dual-boot)

**One `KERNEL` file** — same bootimg on microSD `/boot` and on the UFS `ROCKNIX` partition (like ROCKNIX `installtointernal`: `cp -a /flash/.` with no cmdline patch).

## How it works

| Piece | Role |
|-------|------|
| `boot/KERNEL` cmdline | `root=UUID=<SD>` + `masi.ufsroot=PARTLABEL=STORAGE` (after `update.sh`) |
| initramfs `masi-dual-root` | Runs in **init-premount** (before root wait): SD → UUID; UFS → STORAGE |
| `install-masios-to-internal.sh` | `cp /boot/KERNEL` → `ROCKNIX/KERNEL` (no `abootimg`) |
| `update.sh` | Repacks KERNEL with this device's `masi.sdroot`, syncs to ROCKNIX if present |

## Build and install

```bash
cd ~/Projects/Kernel_MaSi-OS
./make.sh
sudo ./update.sh          # embeds masi.sdroot=UUID= for this microSD
sudo masi-install-to-ufs  # copies same KERNEL to ROCKNIX
```

Kernel updates on an existing UFS install:

```bash
sudo ./update.sh            # updates /boot/KERNEL and ROCKNIX/KERNEL
```

## Scripts (installed by `update.sh`)

```bash
sudo masi-install-to-ufs
sudo masi-install-to-ufs --deploy-only   # partitions exist, copy only
sudo masi-ufs-diagnose
sudo /usr/lib/masi/ufs-linux/ufs-fix-internal-boot.sh   # rescue only
```

**Do not** use an old `~/Desktop/ufs-Linux` copy — run `sudo ./update.sh` to install matching scripts.

## Internal boot with microSD inserted

If both SD and UFS MaSi layouts exist, prefer **removing the SD card** for the first internal Linux boot test (same as ROCKNIX docs).

If the SD must stay in: add `masi.root=ufs` to the kernel cmdline (advanced) or remove SD when booting internal Linux.

## Troubleshooting

**`bad config entry` / `Failed to patch KERNEL`?**  
You are on an **old installer** that patched cmdline at install time. Fix:

```bash
cd ~/Projects/Kernel_MaSi-OS && ./make.sh && sudo ./update.sh
sudo masi-install-to-ufs --deploy-only
```

**Black screen booting internal Linux?**  
Old KERNEL still had `root=UUID=<SD>` only. Rebuild + `update.sh`, then `--deploy-only` or `ufs-fix-internal-boot.sh`.
