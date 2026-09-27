#!/usr/bin/env bash
# Install Arch/SteamOS Holo packages into an extracted rootfs without running
# rootfs pacman on the build host (glibc mismatch). Mirrors install-plasma-extras.
#
# Usage (source):
#   source scripts/lib/holo-pkg-install.sh
#   holo_pkg_init /path/to/rootfs
#   holo_pkg_index_repos
#   holo_pkg_install_tree lutris
#   holo_pkg_cleanup
set -euo pipefail

HOLO_PKG_R=""
HOLO_PKG_DB=""
HOLO_PKG_CONF=""
HOLO_PKG_WORKDIR=""
declare -A HOLO_PKG_URL HOLO_PKG_FILE HOLO_PKG_REPO
declare -A HOLO_PKG_DEPENDS
HOLO_PKG_INSTALLING=""

holo_pkg_log() { printf '==> [holo-pkg] %s\n' "$*"; }
holo_pkg_warn() { printf 'WARN [holo-pkg] %s\n' "$*" >&2; }
holo_pkg_die() { printf 'ERROR [holo-pkg] %s\n' "$*" >&2; exit 1; }

holo_pkg_init() {
  local r="$1"
  HOLO_PKG_R="$(cd "$r" && pwd)"
  HOLO_PKG_DB="${HOLO_PKG_R}/usr/lib/holo/pacmandb"
  HOLO_PKG_CONF="${HOLO_PKG_R}/etc/pacman.conf"
  [[ -d "${HOLO_PKG_R}/usr" && -f "$HOLO_PKG_CONF" ]] \
    || holo_pkg_die "bad rootfs ${HOLO_PKG_R}"
  mkdir -p "${HOLO_PKG_DB}/local"
  HOLO_PKG_WORKDIR="$(mktemp -d /tmp/holo-pkg.XXXXXX)"
}

holo_pkg_cleanup() {
  [[ -n "${HOLO_PKG_WORKDIR:-}" ]] && rm -rf "$HOLO_PKG_WORKDIR"
}

holo_pkg_repo_url() {
  local section="$1"
  awk -v sec="[$section]" '
    $0 == sec { insec=1; next }
    /^\[/ { insec=0 }
    insec && $1 == "Server" {
      sub(/^Server[[:space:]]*=[[:space:]]*/, "")
      print
      exit
    }
  ' "$HOLO_PKG_CONF"
}

holo_pkg_download_db() {
  local url="$1" dest="$2"
  curl -k -fsSL --max-time 60 "$url" -o "$dest"
}

holo_pkg_index_db() {
  local dbfile="$1" baseurl="$2" repolabel="$3"
  python3 - "$dbfile" "$baseurl" "$repolabel" "$HOLO_PKG_WORKDIR/index.pyout" <<'PY'
import sys, tarfile
db, base, repolabel, out = sys.argv[1], sys.argv[2].rstrip("/"), sys.argv[3], sys.argv[4]
rows = []
with tarfile.open(db, "r:*") as tf:
    for m in tf.getmembers():
        n = m.name.replace("\\", "/").lstrip("./")
        if not n.endswith("/desc"):
            continue
        pkgdir = n.rsplit("/", 1)[0].split("/")[-1]
        if "debug" in pkgdir:
            continue
        text = tf.extractfile(m).read().decode("utf-8", "replace")
        lines = text.splitlines()
        name = fn = ""
        depends = []
        in_dep = False
        for i, line in enumerate(lines):
            s = line.strip()
            if s == "%NAME%" and i + 1 < len(lines):
                name = lines[i + 1].strip()
            elif s == "%FILENAME%" and i + 1 < len(lines):
                fn = lines[i + 1].strip()
            elif s == "%DEPENDS%":
                in_dep = True
                continue
            elif s.startswith("%") and in_dep:
                in_dep = False
            elif in_dep and s:
                depends.append(s.split()[0])
        if name and fn:
            rows.append("\t".join([name, f"{base}/{fn}", fn, repolabel, ",".join(depends)]))
with open(out, "w", encoding="utf-8") as fh:
    fh.write("\n".join(rows) + ("\n" if rows else ""))
PY
  while IFS=$'\t' read -r name url file repolabel deps; do
    [[ -n "$name" ]] || continue
    [[ -n "${HOLO_PKG_URL[$name]:-}" ]] && continue
    HOLO_PKG_URL["$name"]="$url"
    HOLO_PKG_FILE["$name"]="$file"
    HOLO_PKG_REPO["$name"]="$repolabel"
    HOLO_PKG_DEPENDS["$name"]="${deps//,/$' '}"
  done <"$HOLO_PKG_WORKDIR/index.pyout"
}

holo_pkg_index_repos() {
  local extra_server hf_server

  extra_server="$(holo_pkg_repo_url extra)"
  extra_server="${extra_server//\$repo/extra}"
  extra_server="${extra_server//\$arch/aarch64}"
  if holo_pkg_download_db "${extra_server}/extra.db" "$HOLO_PKG_WORKDIR/extra.db"; then
    holo_pkg_index_db "$HOLO_PKG_WORKDIR/extra.db" "$extra_server" "holo-extra"
  fi

  hf_server="$(holo_pkg_repo_url deckard-arch-hotfixes)"
  if [[ -n "$hf_server" ]] \
    && holo_pkg_download_db "${hf_server}/deckard-arch-hotfixes.db" "$HOLO_PKG_WORKDIR/hf.db"; then
    holo_pkg_index_db "$HOLO_PKG_WORKDIR/hf.db" "$hf_server" "holo-hotfixes"
  fi

  if holo_pkg_download_db "http://mirror.archlinuxarm.org/aarch64/extra/extra.db" \
      "$HOLO_PKG_WORKDIR/alarm.db"; then
    holo_pkg_index_db "$HOLO_PKG_WORKDIR/alarm.db" \
      "http://mirror.archlinuxarm.org/aarch64/extra" "alarm-extra"
  fi
}

holo_pkg_local_installed() {
  local name="$1"
  compgen -G "${HOLO_PKG_DB}/local/${name}-[0-9]*" >/dev/null 2>&1
}

holo_pkg_satisfies() {
  local name="$1"

  # Base system / soname-only entries from .PKGINFO (not pacman package names).
  # HOLO_PKG_ALLOW_PLATFORM_REPLACE=1 is a diagnostic-only escape hatch. Normal
  # image builds never set it and therefore always preserve the SM8550 stack.
  case "$name" in
    glibc|zlib|gcc-libs|filesystem)
      return 0
      ;;
    # Never replace the image's platform stack while adding applications.
    # SM8550 uses a verified Mesa/Turnip + Wayland combination; generic ALARM
    # packages make gamescope/Steam flicker and repeatedly restart.
    mesa)
      [[ "${HOLO_PKG_ALLOW_PLATFORM_REPLACE:-0}" == "1" ]] \
        || { [[ -e "${HOLO_PKG_R}/usr/lib/libvulkan_freedreno.so" ]] && return 0; }
      ;;
    wayland)
      [[ "${HOLO_PKG_ALLOW_PLATFORM_REPLACE:-0}" == "1" ]] \
        || { [[ -e "${HOLO_PKG_R}/usr/lib/libwayland-client.so.0" ]] && return 0; }
      ;;
    systemd)
      [[ "${HOLO_PKG_ALLOW_PLATFORM_REPLACE:-0}" == "1" ]] \
        || { [[ -x "${HOLO_PKG_R}/usr/lib/systemd/systemd" ]] && return 0; }
      ;;
    systemd-libs)
      [[ "${HOLO_PKG_ALLOW_PLATFORM_REPLACE:-0}" == "1" ]] \
        || { [[ -e "${HOLO_PKG_R}/usr/lib/libsystemd.so.0" ]] && return 0; }
      ;;
    libglvnd)
      [[ "${HOLO_PKG_ALLOW_PLATFORM_REPLACE:-0}" == "1" ]] \
        || { [[ -e "${HOLO_PKG_R}/usr/lib/libGL.so.1" ]] && return 0; }
      ;;
    vulkan-icd-loader)
      [[ "${HOLO_PKG_ALLOW_PLATFORM_REPLACE:-0}" == "1" ]] \
        || { [[ -e "${HOLO_PKG_R}/usr/lib/libvulkan.so.1" ]] && return 0; }
      ;;
    llvm-libs)
      [[ "${HOLO_PKG_ALLOW_PLATFORM_REPLACE:-0}" == "1" ]] \
        || { compgen -G "${HOLO_PKG_R}/usr/lib/libLLVM*.so*" >/dev/null 2>&1 && return 0; }
      ;;
    *.so|*.so.*)
      return 0
      ;;
  esac
  if [[ "$name" == lib* ]]; then
    compgen -G "${HOLO_PKG_R}/usr/lib/${name}.so" >/dev/null 2>&1 && return 0
    compgen -G "${HOLO_PKG_R}/usr/lib/${name}.so.*" >/dev/null 2>&1 && return 0
  fi

  # Do not trust pacmandb/local alone — a failed cp can leave a stale desc.
  if holo_pkg_local_installed "$name"; then
    case "$name" in
      webkit2gtk*|glib2|gtk3|pango|gdk-pixbuf2|gobject-introspection-runtime|hicolor-icon-theme)
        return 0
        ;;
      *)
        [[ -x "${HOLO_PKG_R}/usr/bin/$name" ]] && return 0
        ;;
    esac
  fi

  case "$name" in
    p7zip)
      holo_pkg_local_installed 7zip && return 0
      [[ -x "${HOLO_PKG_R}/usr/bin/7z" ]] && return 0
      ;;
    gnome-desktop)
      holo_pkg_local_installed gnome-desktop-4 && return 0
      [[ -e "${HOLO_PKG_R}/usr/lib/libgnome-desktop-4.so.2" ]] && return 0
      ;;
    python)
      [[ -x "${HOLO_PKG_R}/usr/bin/python" || -x "${HOLO_PKG_R}/usr/bin/python3" ]] && return 0
      ;;
    python-*)
      local mod="${name#python-}"
      mod="${mod//-/_}"
      find "${HOLO_PKG_R}/usr/lib/python"* -path '*/site-packages/*' \
        -maxdepth 2 -type d -name "$mod" 2>/dev/null | grep -q . && return 0
      ;;
    webkit2gtk-4.1)
      compgen -G "${HOLO_PKG_R}/usr/lib/libwebkit2gtk-4.1.so*" >/dev/null 2>&1 && return 0
      ;;
    cabextract|unzip|curl|psmisc|hicolor-icon-theme|mesa-utils)
      [[ -x "${HOLO_PKG_R}/usr/bin/$name" ]] && return 0
      ;;
    gdk-pixbuf2|glib2|gtk3|pango)
      compgen -G "${HOLO_PKG_R}/usr/lib/lib${name}*.so*" >/dev/null 2>&1 && return 0
      ;;
    gobject-introspection-runtime)
      [[ -d "${HOLO_PKG_R}/usr/lib/girepository-1.0" ]] && return 0
      ;;
  esac

  [[ -x "${HOLO_PKG_R}/usr/bin/$name" ]]
}

holo_pkg_qt11_reject() {
  local dest="$1"
  if find "$dest" -type f \( -name '*.so*' -o -perm -111 \) 2>/dev/null \
      | head -40 | xargs -r strings 2>/dev/null | grep -q 'Qt_6\.11'; then
    return 0
  fi
  return 1
}

holo_pkg_fetch_extract() {
  local name="$1"
  local url="${HOLO_PKG_URL[$name]:-}"
  local file="${HOLO_PKG_FILE[$name]:-}"
  local dest="$2"

  if [[ -z "$url" || -z "$file" ]]; then
    holo_pkg_warn "package not in indexed repos: $name"
    return 1
  fi

  case "$name" in
    kscreen|plasma-nm|bluedevil|spectacle|plasma-pa|plasma-desktop|plasma-workspace)
      if [[ "${HOLO_PKG_REPO[$name]:-}" == "alarm-extra" ]]; then
        holo_pkg_warn "skip $name (Plasma 6.7 applets break Frame 6.2.5)"
        return 1
      fi
      ;;
  esac

  holo_pkg_log "get $name ($file) from ${HOLO_PKG_REPO[$name]}"
  if ! curl -k -fsSL --max-time 180 "$url" -o "$HOLO_PKG_WORKDIR/$file"; then
    holo_pkg_warn "download failed: $name"
    return 1
  fi

  rm -rf "$dest"
  mkdir -p "$dest"
  # A stale host bsdtar may exist but fail at startup after an OpenSSL update.
  # Fall back to GNU tar instead of silently leaving the package uninstalled.
  if command -v bsdtar >/dev/null 2>&1 && bsdtar --version >/dev/null 2>&1; then
    bsdtar -C "$dest" -xf "$HOLO_PKG_WORKDIR/$file"
  else
    tar -C "$dest" -xf "$HOLO_PKG_WORKDIR/$file"
  fi

  if holo_pkg_qt11_reject "$dest"; then
    holo_pkg_warn "skip $name ($file needs Qt_6.11; this image has Qt 6.8)"
    return 1
  fi
  return 0
}

holo_pkg_depends_from_pkginfo() {
  local pkginfo="$1"
  [[ -f "$pkginfo" ]] || return 0
  awk -F' = ' '/^depend / {print $2}' "$pkginfo"
}

holo_pkg_merge_tree() {
  local dest="$1"
  for d in usr etc opt; do
    [[ -d "$dest/$d" ]] || continue
    mkdir -p "${HOLO_PKG_R}/$d"
    cp -a "$dest/$d/." "${HOLO_PKG_R}/$d/" || return 1
  done

  if [[ -f "$dest/.PKGINFO" ]]; then
    local pkgver
    pkgver="$(awk -F' = ' '/^pkgname /{n=$2} /^pkgver /{v=$2} END{print n"-"v}' "$dest/.PKGINFO")"
    if [[ -n "$pkgver" ]]; then
      mkdir -p "${HOLO_PKG_DB}/local/${pkgver}"
      {
        echo "%NAME%"
        awk -F' = ' '/^pkgname /{print $2}' "$dest/.PKGINFO"
        echo
        echo "%VERSION%"
        awk -F' = ' '/^pkgver /{print $2}' "$dest/.PKGINFO"
        echo
      } >"${HOLO_PKG_DB}/local/${pkgver}/desc"
    fi
  fi
  return 0
}

holo_pkg_install_tree() {
  local name="$1"
  holo_pkg_satisfies "$name" && return 0
  case " ${HOLO_PKG_INSTALLING} " in
    *" ${name} "*) holo_pkg_warn "dependency cycle on $name"; return 1 ;;
  esac
  HOLO_PKG_INSTALLING+=" ${name}"

  local dest="$HOLO_PKG_WORKDIR/tree-${name}"
  if ! holo_pkg_fetch_extract "$name" "$dest"; then
    return 1
  fi

  local dep
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    holo_pkg_install_tree "$dep" || holo_pkg_warn "dependency $dep missing for $name"
  done < <(holo_pkg_depends_from_pkginfo "$dest/.PKGINFO")

  for dep in ${HOLO_PKG_DEPENDS[$name]:-}; do
    [[ -n "$dep" ]] || continue
    holo_pkg_install_tree "$dep" || holo_pkg_warn "indexed dependency $dep missing for $name"
  done

  holo_pkg_merge_tree "$dest"
}
