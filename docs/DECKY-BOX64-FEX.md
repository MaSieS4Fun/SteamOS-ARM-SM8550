# Decky, Box64 and Valve FEX-Emu

## Policy (SM8550 image)

| Component | Scope | Used for |
|-----------|-------|----------|
| **Box64** | System-wide (`/etc/binfmt.d/box64.conf`) | Decky PluginLoader, x86_64 CLI tools |
| **Valve FEX-Emu** | Steam/Proton only | Games when forcing x86_64 Proton compatibility |

FEX must **never** register global binfmt. Steam downloads FEX-Emu into
`~/.local/share/Steam/steamapps/common/FEX-Emu/`; Proton uses it via
`fex-compat-tool` in `RUNSTEAM.sh`, not via systemd binfmt.

## PluginLoader service model

Decky must run as part of the Game Mode user session:

```text
gamescope-session.target
  -> sm8550-plugin-loader.service (user)
  -> /usr/lib/steamos/sm8550-plugin-loader
  -> /usr/local/bin/box64
  -> ~/homebrew/services/PluginLoader
```

`gamescope-onready` also restarts the user service after Gamescope is ready.
`install-decky` adds the target link only after PluginLoader has been
installed. A clean image therefore contains the wrapper and unit but does not
start an empty Decky service.

Never create a root-level `/usr/lib/systemd/system/plugin_loader.service`.
The legacy service outlived Game Mode, left LSFG children behind during
session changes, and was sometimes generated with a missing `/usr/bin/box64`
or an invalid `home.mount` ordering dependency.

## Why Decky broke (root cause chain)

1. **Decky worked** when PluginLoader was launched explicitly through Box64.

2. **Overlay experiment** switched Decky to FEX (`sm8550-plugin-loader` → `sm8550-fex`).
   FEX-Emu from Valve is built for Proton/pressure-vessel, not as a root systemd
   daemon running PluginLoader.

3. **`sm8550-fex-binfmt.path`** watched for FEX-Emu install. When Steam downloaded
   FEX (e.g. after forcing Proton x86_64), the path unit fired and
   `sm8550-fex-binfmt` registered **global FEX binfmt** and **deleted `box64.conf`**.

4. **FEX + PluginLoader as root → segfault (exit 139)**. Logs:
   `plugin_loader-fex.log` / `~/.local/share/sm8550-fex.log`.

5. **Removing Box64 manually did not fix it** — `sm8550-plugin-loader` still called
   FEX explicitly; `install-decky` accepted FEX if the wrapper existed.

6. **Disabling global FEX alone did not fix it** — same wrapper, no Box64 left.

## Image build (prevention)

- `scripts/build-box64-sm8550.sh` — bake Box64 into rootfs at apply time
- `make-steamos-sm8550.sh` — no longer strips Box64
- `sm8550-plugin-loader` — always Box64
- `sm8550-plugin-loader.service` — user service, stopped with Game Mode
- `sm8550-fex-binfmt.service` — one-shot **cleanup** only (remove global FEX)
- **`sm8550-fex-binfmt.path` — not shipped**
- `install-decky` — ensures Box64, deploys the user service, removes any
  legacy system service, and cleans FEX binfmt on every install/verify

Decky enables CEF remote debugging. If `gamescope-session.target` also starts
the stock `steam.service` while `gamescope-onready` launches Steam, two clients
start a few seconds apart. Typical symptoms are a black screen with a cursor
in the top-left corner and duplicated/stuck controller input. The production
target must not contain `Wants=steam.service`.

## On-device repair

```bash
pkexec /usr/lib/steamos/sm8550-restore-decky-box64
# or
pkexec install-decky verify
```

After repair, verify:

```bash
systemctl --user status sm8550-plugin-loader.service
systemctl status plugin_loader.service
```

The user service should be active in Game Mode. The system service should not
exist.
