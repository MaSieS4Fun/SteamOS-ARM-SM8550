#!/usr/bin/env bash
# Build MESA Easy Manager AppImage for the current architecture.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING="${ROOT}/packaging"
DIST="${ROOT}/dist"
APPDIR="${DIST}/MESA_Easy_Manager.AppDir"
ARCH="$(uname -m)"
VERSION="$(python3 -c "from pathlib import Path; import re; t=Path('${ROOT}/mesa_easy_manager/constants.py').read_text(); print(re.search(r'APP_VERSION = \"([^\"]+)\"', t).group(1))")"
APPIMAGE_NAME="MESA_Easy_Manager-${VERSION}-${ARCH}.AppImage"
APPIMAGETOOL="${DIST}/appimagetool-${ARCH}.AppImage"

case "${ARCH}" in
  aarch64|arm64) TOOL_ARCH="aarch64" ;;
  x86_64|amd64) TOOL_ARCH="x86_64" ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

echo "==> Building AppDir (${APPIMAGE_NAME})"
rm -rf "${APPDIR}"
mkdir -p \
  "${APPDIR}/usr/bin" \
  "${APPDIR}/usr/share/mesa-easy-manager" \
  "${APPDIR}/usr/share/applications" \
  "${APPDIR}/usr/share/icons/hicolor/scalable/apps"

# Application payload
cp -a "${ROOT}/mesa_easy_manager" "${APPDIR}/usr/share/mesa-easy-manager/"
mkdir -p "${APPDIR}/usr/share/mesa-easy-manager/scripts"
cp -a "${ROOT}/scripts/mesa_easy_privileged.py" "${APPDIR}/usr/share/mesa-easy-manager/scripts/"
chmod 755 "${APPDIR}/usr/share/mesa-easy-manager/scripts/mesa_easy_privileged.py"
cp -a "${ROOT}/run.py" "${APPDIR}/usr/share/mesa-easy-manager/"
find "${APPDIR}/usr/share/mesa-easy-manager" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
find "${APPDIR}/usr/share/mesa-easy-manager" -type f -name '*.pyc' -delete 2>/dev/null || true

# Launcher symlink expected by some desktop integrations
cat > "${APPDIR}/usr/bin/mesa-easy-manager" <<'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")/../.."
exec "${HERE}/AppRun" "$@"
EOF
chmod 755 "${APPDIR}/usr/bin/mesa-easy-manager"

# Desktop entry + icon at AppDir root (required by appimagetool)
cp "${PACKAGING}/mesa-easy-manager.desktop" "${APPDIR}/mesa-easy-manager.desktop"
cp "${PACKAGING}/mesa-easy-manager.desktop" "${APPDIR}/usr/share/applications/mesa-easy-manager.desktop"
cp "${PACKAGING}/mesa-easy-manager.svg" "${APPDIR}/mesa-easy-manager.svg"
cp "${PACKAGING}/mesa-easy-manager.svg" "${APPDIR}/usr/share/icons/hicolor/scalable/apps/mesa-easy-manager.svg"
cp "${PACKAGING}/AppRun" "${APPDIR}/AppRun"
chmod 755 "${APPDIR}/AppRun"

# Stamp version into desktop file
sed -i "s/^X-AppImage-Version=.*/X-AppImage-Version=${VERSION}/" \
  "${APPDIR}/mesa-easy-manager.desktop" \
  "${APPDIR}/usr/share/applications/mesa-easy-manager.desktop"

# Fetch appimagetool if needed
if [[ ! -x "${APPIMAGETOOL}" ]]; then
  echo "==> Downloading appimagetool (${TOOL_ARCH})"
  URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${TOOL_ARCH}.AppImage"
  curl -fsSL -o "${APPIMAGETOOL}" "${URL}" || \
    curl -fsSL -o "${APPIMAGETOOL}" \
      "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${TOOL_ARCH}.AppImage"
  chmod +x "${APPIMAGETOOL}"
fi

echo "==> Preparing appimagetool"
TMPTOOL="${DIST}/appimagetool-extracted"
if [[ ! -x "${TMPTOOL}/AppRun" ]]; then
  echo "==> Extracting appimagetool with unsquashfs (no FUSE required)"
  rm -rf "${TMPTOOL}"
  OFFSET="$(python3 -c "print(open('${APPIMAGETOOL}','rb').read().find(b'hsqs'))")"
  if [[ -z "${OFFSET}" || "${OFFSET}" -lt 0 ]]; then
    echo "Could not locate squashfs payload in appimagetool" >&2
    exit 1
  fi
  unsquashfs -o "${OFFSET}" -d "${TMPTOOL}" "${APPIMAGETOOL}" >/dev/null
fi

echo "==> Running appimagetool"
ARCH="${TOOL_ARCH}" VERSION="${VERSION}" \
  "${TMPTOOL}/AppRun" --no-appstream "${APPDIR}" "${DIST}/${APPIMAGE_NAME}"

chmod +x "${DIST}/${APPIMAGE_NAME}"
echo "==> Built: ${DIST}/${APPIMAGE_NAME}"
ls -lh "${DIST}/${APPIMAGE_NAME}"
