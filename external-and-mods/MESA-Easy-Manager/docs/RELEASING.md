# Releasing on GitHub

Checklist for publishing a new **MESA Easy Manager** version.

## 1. Bump version

Update `APP_VERSION` in:

```text
mesa_easy_manager/constants.py
```

The AppImage build script reads this value automatically. The desktop file
`X-AppImage-Version` is stamped during `./packaging/build-appimage.sh`.

## 2. Update changelog

Add a section to [CHANGELOG.md](../CHANGELOG.md) and, if needed, the **Releases**
table in [README.md](../README.md).

## 3. Build AppImage

```bash
./packaging/build-appimage.sh
```

Output:

```text
dist/MESA_Easy_Manager-<version>-aarch64.AppImage
```

Smoke-test on aarch64:

```bash
./dist/MESA_Easy_Manager-*-aarch64.AppImage
```

## 4. Commit and tag

```bash
git add -A
git commit -m "Release v1.5.0"
git tag -a v1.5.0 -m "MESA Easy Manager 1.5.0"
git push origin main
git push origin v1.5.0
```

## 5. Create GitHub Release

```bash
gh release create v1.5.0 \
  dist/MESA_Easy_Manager-1.5.0-aarch64.AppImage \
  --title "v1.5.0" \
  --notes-file - <<'EOF'
## Highlights

- Compile profiles: Generic / SM8550 / SM8750
- Rolling **devel** Mesa tip (unstable)
- SM8750 (Odin 3) patch support

## Install

1. Download `MESA_Easy_Manager-1.5.0-aarch64.AppImage`
2. `chmod +x MESA_Easy_Manager-1.5.0-aarch64.AppImage`
3. Run it — host still needs `python3-gi`, `gir1.2-gtk-3.0`, `policykit-1`

Full notes: [CHANGELOG.md](https://github.com/MaSieS4Fun/MESA-Easy-Manager/blob/main/CHANGELOG.md)
EOF
```

Adjust version strings and notes as needed.

## Notes

- AppImages are **not** committed to git (see `.gitignore`).
- Only **aarch64** is built and tested for this project.
- Patch upstream URLs and commit pins live in `mesa_easy_manager/rocknix.py` and
  [PATCH_SOURCES.md](PATCH_SOURCES.md).
