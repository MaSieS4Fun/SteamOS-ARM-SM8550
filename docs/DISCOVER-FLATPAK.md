# Discover, Flatpak and SteamOS updates (SM8550)

## Flatpak / Flathub install fails (revokefs-fuse)

Typical error in Discover:

```
Could not unmount revokefs-fuse filesystem at /var/tmp/flatpak-cache-... exit 1
```

**Cause (two parts):**

1. **`fusermount3` lost setuid** (`4755`) when the rootfs was copied into the
   image — revokefs unmount then fails with exit 1 (*Operation not permitted*).
2. The **user** `flatpak` process (Discover) must call `/usr/bin/fusermount3`,
   not a shim from homebrew/podman on `$PATH`.

**Image fix:** restore setuid in `sm8550-restore-privs`, wrappers on
`/usr/bin/flatpak` + helpers, `sm8550-flatpak-env`, Plasma env, `1777` on
`/var/tmp`.

**On device (pkexec):**

```bash
pkexec /usr/bin/sm8550-fix-discover
```

The script must report `fusermount3` with **setuid** (`-rwsr-xr-x`). If an older
`sm8550-restore-privs` is on the device (without fusermount lines), the fix
script now restores setuid explicitly anyway.

Verify:

```bash
ls -la /usr/bin/fusermount3   # must show root root and 's' in permissions
flatpak remotes
```

Then log out of Plasma completely and retry Discover.

Writable flatpak data lives on the **home** partition via bind mounts:

`/home/.steamos/offload/var/lib/flatpak` → `/var/lib/flatpak`

First boot creates offload dirs via `sm8550-setup-steamos-offload.service`.

## Ghost “SteamOS” update in Discover

Discover’s `steamos-backend.so` talks to **atomupd** (Valve RAUC OTA). SM8550
images use ext4 root+home and **no atomupd payload** — the update row never
completes.

**Image fix:**

- Remove `steamos-backend.so` from Discover plugins
- Mask `atomupd.service`
- `discoverrc` excludes SteamOS backend

Game Mode “Software Updates” still uses the `steamos-update` stub (always up
to date). Kernel updates: **MaSi-OS Kernel Updater** in ARM-Manager.
