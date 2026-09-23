# Multi-device distribution — stop shipping one broken KERNEL

## What went wrong

Two separate bugs caused **the same symptoms on every tester** while your Odin 2 worked:

### 1. Poisoned initrd (`conf/conf.d/root`)

The build reused a “gold” initrd from `reference/` or `/boot/KERNEL`. That cpio contained:

```text
ROOT=/home/odin2/Desktop/ayn-sm8550-kernel/output/.../.initramfs-root
```

That path is from **mkinitramfs on the build PC**. On Portal (and other SDs) the initramfs ignores `root=UUID=` from the kernel cmdline and fails with **cannot find UUID / root**.

Your machine worked because you likely installed with `update.sh` or had a matching environment — testers got the raw `output/.../boot/KERNEL` file.

**Fix (in tree):** every initrd is scrubbed — `conf/conf.d/root` is removed before packing.

### 2. One `root=UUID=` baked into KERNEL

`make.sh` embeds **your** root UUID from `/boot/LinuxLoader.cfg`. Each SD card has its **own** UUID unless everyone cloned the same image byte-for-byte.

**Fix:** each device must run:

```bash
sudo ./update.sh
```

before reboot (`INSTALL_REPACK_KERNEL=1` by default). That repacks `KERNEL` with **that** machine’s UUID.

Do **not** copy only `boot/KERNEL` from `output/` to testers’ SD cards.

### 3. DTB chain experiment (reverted)

Putting Mini DTB at slot 0 broke Odin 2 units whose ABL picks index 0 → black screen. Standard ROCKNIX slot order is restored in `config/dtb-chain.map`.

---

## Workflow for testers (copy-paste)

On **each** handheld, with the MaSi repo and a completed build (or install bundle):

```bash
cd Kernel_MaSi-OS
sudo ./update.sh
sudo reboot
```

ABL: **Set the Device** → exact model → Linux → START.

---

## Workflow for you (one build, many devices)

```bash
./make.sh
# Copy the whole output/<ver>-masi/ folder to each device (or git pull on device)
# On EACH device:
sudo ./update.sh
```

---

## Verify initrd before sending anything

```bash
work=$(mktemp -d)
(cd "$work" && abootimg -x output/*/boot/KERNEL)
tmpdir=$(mktemp -d)
gzip -dc "$work/initrd.img" | (cd "$tmpdir" && cpio -idm conf/conf.d/root 2>/dev/null)
test ! -f "$tmpdir/conf/conf.d/root" && echo "OK: no poisoned ROOT="
```

---

## If screen stays black

Temporarily drop `quiet` from cmdline to see kernel/initrd messages:

```bash
KERNEL_CMDLINE_EXTRA="loglevel=7" ./make.sh
sudo ./update.sh
```
