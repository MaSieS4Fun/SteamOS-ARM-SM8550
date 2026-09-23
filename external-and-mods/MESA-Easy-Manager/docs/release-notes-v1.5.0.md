## MESA Easy Manager v1.5.0

### Highlights

- **Compile profiles** — choose **Generic**, **SM8550** (Odin 2 / Thor / R-Pocket 6), or **SM8750** (Odin 3) before each build
- **devel** — rolling Mesa git tip, always listed first, with instability warnings
- **SM8750 patches** — Batocera + ROCKNIX a830 chip-id support for Odin 3

### Install (AppImage)

1. Download `MESA_Easy_Manager-1.5.0-aarch64.AppImage` below
2. `chmod +x MESA_Easy_Manager-1.5.0-aarch64.AppImage`
3. Run it

**Host packages still required:**

```bash
sudo apt install python3-gi gir1.2-gtk-3.0 policykit-1
```

For **devel** compiles, also install `git` and Mesa build dependencies (see README).

### Full changelog

https://github.com/MaSieS4Fun/MESA-Easy-Manager/blob/main/CHANGELOG.md
