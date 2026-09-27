#!/usr/bin/env bash
# Build Heroic Games Launcher (linux arm64) and install under /opt/Heroic.
# Adapted from SteamOS-Ubuntu/scripts/install-heroic-into-rootfs.sh — upstream
# has no official Linux ARM build; electron-builder --linux dir --arm64 works.
#
# Usage:
#   sudo ./scripts/install-heroic-into-rootfs.sh [rootfs]
#
# Host (aarch64): git, Node 22, pnpm 10 (scripts/lib/ensure-build-node.sh).
#
# Env:
#   SKIP_HEROIC=1           — no-op
#   HEROIC_GIT_REF=v2.x.y   — tag/branch (default: upstream HEAD)
#   HEROIC_FRESH_CLONE=1    — discard cached clone
#   HEROIC_WORK_DIR=...     — build dir (default vendor/.cache/heroic-build)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${1:-${ROOT}/rootfs}"
R="$(cd "$R" && pwd)"
WORK_DIR="${HEROIC_WORK_DIR:-${ROOT}/vendor/.cache/heroic-build}"
REPO="https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher.git"

log() { printf '==> [heroic] %s\n' "$*" >&2; }
die() { printf 'ERROR: [heroic] %s\n' "$*" >&2; exit 1; }

[[ "${SKIP_HEROIC:-0}" == "1" ]] && { log "SKIP_HEROIC=1"; exit 0; }

# shellcheck source=lib/ensure-build-node.sh
source "${SCRIPT_DIR}/lib/ensure-build-node.sh"

[[ -d "${R}/usr" ]] || die "missing rootfs ${R}"
[[ "${EUID}" -eq 0 ]] || die "run as root (sudo) — heroic installs into ${R}/opt"
[[ "$(uname -m)" == "aarch64" ]] || die "build on aarch64"

command -v git >/dev/null || die "git required"

ensure_build_node "$ROOT" || die \
  "Node 22 + pnpm 10 required; ensure network or install Node locally before sudo"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

heroic_src="${WORK_DIR}/HeroicGamesLauncher"

if [[ "${HEROIC_FRESH_CLONE:-0}" == "1" ]]; then
  log "HEROIC_FRESH_CLONE=1 — removing previous clone"
  rm -rf "$heroic_src"
fi

if [[ ! -d "${heroic_src}/.git" ]]; then
  log "cloning Heroic (shallow, submodules)…"
  git clone --depth 1 --recurse-submodules "$REPO" "$heroic_src"
else
  log "refreshing existing Heroic clone…"
  git -C "$heroic_src" fetch --depth 1 origin || true
fi

cd "$heroic_src"

if [[ -n "${HEROIC_GIT_REF:-}" ]]; then
  log "checkout ${HEROIC_GIT_REF}"
  git fetch --depth 1 origin "${HEROIC_GIT_REF}" 2>/dev/null || true
  git checkout -f "${HEROIC_GIT_REF}"
else
  default_branch="$(git remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}')"
  default_branch="${default_branch:-main}"
  log "checkout origin/${default_branch} (latest upstream)"
  git fetch --depth 1 origin "${default_branch}" || true
  git checkout -f "origin/${default_branch}" 2>/dev/null \
    || git checkout -f "${default_branch}" 2>/dev/null \
    || git pull --ff-only || true
fi

git submodule update --init --recursive --depth 1 || true

log "Heroic $(git rev-parse --short HEAD) — pnpm $(pnpm -v), node $(node -v)"

heroic_pnpm_install() {
  log "pnpm install…"
  pnpm install --reporter=append-only
}

if [[ -d node_modules ]]; then
  log "node_modules present — trying incremental install…"
  if ! heroic_pnpm_install; then
    log "incremental install failed — clean node_modules and retry…"
    rm -rf node_modules
    heroic_pnpm_install
  fi
else
  heroic_pnpm_install
fi

log "downloading helper binaries (legendary, gogdl, nile)…"
pnpm run download-helper-binaries || true

log "building frontend (electron-vite)…"
export CSC_IDENTITY_AUTO_DISCOVERY=false
pnpm exec electron-vite build

log "packaging linux arm64 (directory, not AppImage)…"
set +e
pnpm exec electron-builder --linux dir --arm64 \
  -c.linux.icon=build/icon.png \
  -c.npmRebuild=true
eb_rc=$?
set -e

unpacked="$(find dist -type d -name 'linux*-unpacked' 2>/dev/null | head -1 || true)"
[[ -n "$unpacked" && -x "${unpacked}/heroic" ]] \
  || die "electron-builder failed (rc=${eb_rc}); no linux*-unpacked/heroic"
[[ "${eb_rc}" -ne 0 ]] && log "electron-builder rc=${eb_rc} but tree exists — continuing"

log "installing into ${R}/opt/Heroic"
rm -rf "${R}/opt/Heroic"
mkdir -p \
  "${R}/opt/Heroic" \
  "${R}/usr/bin" \
  "${R}/usr/share/applications" \
  "${R}/usr/share/icons/hicolor/256x256/apps"
cp -a "${unpacked}/." "${R}/opt/Heroic/"
chmod 0755 "${R}/opt/Heroic/heroic"
[[ -f "${R}/opt/Heroic/chrome-sandbox" ]] && \
  chmod 4755 "${R}/opt/Heroic/chrome-sandbox" 2>/dev/null || true

cat > "${R}/usr/bin/heroic" <<'EOF'
#!/bin/bash
# Heroic on Wayland (Plasma / gamescope desktop)
mkdir -p /tmp/.X11-unix 2>/dev/null || true
export LD_LIBRARY_PATH="/opt/Heroic${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec /opt/Heroic/heroic \
  --ozone-platform-hint=auto \
  --enable-features=UseOzonePlatform,WaylandWindowDecorations \
  "$@"
EOF
chmod 0755 "${R}/usr/bin/heroic"

if [[ -f build/icon.png ]]; then
  install -d "${R}/usr/share/icons/hicolor/256x256/apps"
  install -m 0644 build/icon.png \
    "${R}/usr/share/icons/hicolor/256x256/apps/heroic.png"
fi

cat > "${R}/usr/share/applications/heroic.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Heroic Games Launcher
Comment=Launcher for Epic, GOG and Amazon Games
Exec=heroic %U
Icon=heroic
Terminal=false
Categories=Game;
Keywords=epic;gog;amazon;games;heroic;
StartupNotify=true
MimeType=x-scheme-handler/heroic;
EOF

log "done: /opt/Heroic + ${R}/usr/bin/heroic"
