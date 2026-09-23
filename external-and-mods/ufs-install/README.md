# SteamOS SM8550 UFS install

Install **this project's SteamOS ARM userspace** on **internal UFS** alongside **Android**, using **ROCKNIX ABL 1.1.8** (or compatible) and the same **three Linux partitions** as the microSD image: boot + root + home.

> **⚠️ RISK WARNING**
>
> This **repartitions internal storage** and **wipes Android userdata**. You can **lose all data** on internal UFS. **Android, Linux, or both** may fail to boot. **Use at your own risk.** See [DISCLAIMER.md](DISCLAIMER.md).

This folder is **only for steamos-oficial**. It does **not** change the MaSi-OS kernel tree installer (`external-and-mods/kernel/scripts/ufs-linux`).

## Supported devices

- Qualcomm **SM8550** with **ROCKNIX ABL** installed (tested with **1.1.8**)
- AYN **Odin 2** (and similar SM8550 handhelds using the same ABL)

## What you need before starting

| Requirement | Notes |
|-------------|--------|
| ROCKNIX ABL | Installed on the device (1.1.8 or compatible) |
| SteamOS on **microSD** | Run the installer from SD, not from UFS |
| `/boot/KERNEL` | Dual-boot image (`root=UUID=` + `masi.ufsroot=PARTLABEL=STORAGE`) |
| User password | `pkexec` / `sudo` (SteamOS has none until you set one) |

The kernel already supports UFS boot. The installer only **repacks** `KERNEL` onto `ROCKNIX` with `root=PARTLABEL=STORAGE` so internal boot does not depend on the SD UUID.

## Partition layout (after install)

```
userdata   →  Android (size you choose; all data erased)
ROCKNIX    →  2 GiB FAT32 — KERNEL + KERNEL.md5   (ABL reads this)
STORAGE    →  16 GiB ext4 — SteamOS root (/)
HOME       →  remaining ext4 — /home (Steam, games, user data)
```

ABL only needs the **ROCKNIX** partition for `KERNEL`. `STORAGE` and `HOME` are Linux filesystems.

If you previously installed the **two-partition** ROCKNIX + STORAGE layout, use ABL **Uninstall ROCKNIX** and run a fresh install. `--resume` only works when **all three** Linux partitions already exist.

ABL Uninstall may leave a leftover **HOME** partition. Delete it if a later Android-only restore looks wrong.

## Quick start

From SteamOS on microSD:

```bash
sudo ufs-diagnose.sh
sudo install-masios-to-internal.sh
# or:
sudo install-masios-to-internal.sh --android-gb 64
```

Or open **Easy UFS Installer** from ARM-Manager.

### After a failed install (partitions already exist)

```bash
sudo install-masios-to-internal.sh --deploy-only
```

### Repair KERNEL / fstab only

```bash
sudo ufs-fix-internal-boot.sh
```

## Scripts

| Script | Purpose |
|--------|---------|
| `install-masios-to-internal.sh` | Repartition UFS + install KERNEL + root + home |
| `ufs-diagnose.sh` | Show UFS layout, SD vs ROCKNIX KERNEL cmdline |
| `ufs-fix-internal-boot.sh` | Rewrite ROCKNIX KERNEL to `root=PARTLABEL=STORAGE`; fix fstab |
| `ufs-bootimg.sh` | Shared helpers (pack UFS KERNEL from SD KERNEL) |
| `easy-ufs-installer.py` | GUI |

## How boot works

| Location | KERNEL cmdline |
|----------|----------------|
| microSD `/boot/KERNEL` | `root=UUID=<SD>` + `masi.ufsroot=PARTLABEL=STORAGE` |
| UFS `ROCKNIX/KERNEL` | **`root=PARTLABEL=STORAGE` only** (packed at install time) |

`/etc/fstab` on STORAGE (and the SteamOS `/etc` overlay upper) mounts:

- `PARTLABEL=STORAGE` → `/`
- `PARTLABEL=ROCKNIX` → `/boot`
- `PARTLABEL=HOME` → `/home`

Internal Linux boot does **not** depend on the microSD being present.

## Options (`install-masios-to-internal.sh`)

```
--android-gb N    Android userdata size (GB)
--dry-run         Simulate without writing
--resume          Use existing ROCKNIX/STORAGE/HOME (no repartition)
--deploy-only     Same as --resume
--force           Skip final confirmation (still shows risk banner)
-h, --help        Help
```

Root size is **16 GiB** (same as the published image). `/home` gets the rest of the Linux space.

## Typical flow after install

1. **Remove microSD**, reboot → ABL Linux mode → SteamOS from UFS.
2. Boot **Android recovery** → **Factory data reset** (userdata was wiped).
3. Keep a working microSD as recovery until UFS Linux is verified.

### Already installed but black screen on UFS?

Boot from microSD and run:

```bash
sudo ufs-fix-internal-boot.sh
```

Then remove the SD and test UFS boot again.

## Recovery if something goes wrong

| Problem | Action |
|---------|--------|
| Linux black screen | `sudo ufs-diagnose.sh` then `sudo ufs-fix-internal-boot.sh` |
| Partial install | `sudo install-masios-to-internal.sh --deploy-only` |
| Old 2-partition install | ABL **Uninstall ROCKNIX**, then fresh install |
| Remove internal Linux | ROCKNIX ABL → **Uninstall ROCKNIX** (delete leftover HOME if needed) |
| Android broken | Recovery → factory reset; worst case reflash firmware |

## Legal

- [DISCLAIMER.md](DISCLAIMER.md) — **read before use**
- [LICENSE](LICENSE) — GPL-2.0-or-later

**You assume all risk.** Authors provide no warranty and no guarantee of support.

---

## Aviso en español

Esta herramienta **borra los datos de la partición Android `userdata`** en la memoria interna (UFS) y **reparticiona el disco**. Puedes **perder todos los datos** guardados en Android y en UFS. **Android, Linux o ambos sistemas pueden dejar de arrancar**.

Instala **SteamOS de este proyecto** con **tres particiones Linux**: `ROCKNIX` (arranque ABL), `STORAGE` (sistema) y `HOME` (`/home`). El ABL 1.1.8 solo necesita `ROCKNIX` con el `KERNEL`.

**Haz copias de seguridad** antes de continuar. **Úsalo bajo tu cuenta y riesgo.** Lee [DISCLAIMER.md](DISCLAIMER.md).
