#!/usr/bin/env bash
# Node 22 + pnpm 10 for image-bake steps (Heroic, Decky plugin builds).
# Safe under sudo: uses vendor/.cache bootstrap (no global npm under /usr).
#
# Usage (source, do not exec):
#   source scripts/lib/ensure-build-node.sh
#   ensure_build_node /path/to/steamos-oficial || exit 1
set -euo pipefail

_ensure_build_node_log() { printf '==> [build-node] %s\n' "$*"; }

# Corepack prompts when a repo declares a different packageManager than PATH pnpm.
_ensure_corepack_noninteractive() {
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  export CI=1
  command -v corepack >/dev/null 2>&1 && corepack enable 2>/dev/null || true
}

# Activate packageManager from package.json when possible; never abort the bake.
ensure_project_package_manager() {
  local pkg_json="${1:-package.json}"
  [[ -f "$pkg_json" ]] || return 0
  local pm
  pm="$(node -e "const p=require(process.argv[1]); process.stdout.write(p.packageManager||'')" "$pkg_json" 2>/dev/null || true)"
  [[ -n "$pm" ]] || return 0
  _ensure_corepack_noninteractive
  _ensure_build_node_log "Corepack prepare ${pm} (best-effort)..."
  corepack prepare "$pm" --activate 2>/dev/null \
    || _ensure_build_node_log "WARN: corepack ${pm} skipped — using PATH pnpm"
  return 0
}

_ensure_node_tarball() {
  local root_dir="$1"
  local node_ver="${BUILD_NODE_VERSION:-22.14.0}"
  local cache="${root_dir}/vendor/.cache/node-v${node_ver}-linux-arm64"

  if [[ -x "${cache}/bin/node" ]]; then
    printf '%s\n' "${cache}/bin"
    return 0
  fi

  local tarball="node-v${node_ver}-linux-arm64.tar.xz"
  local url="https://nodejs.org/dist/v${node_ver}/${tarball}"
  mkdir -p "${root_dir}/vendor/.cache"
  _ensure_build_node_log "Downloading ${url}"
  curl -fsSL "$url" -o "/tmp/${tarball}"
  tar -xJf "/tmp/${tarball}" -C "${root_dir}/vendor/.cache"
  rm -f "/tmp/${tarball}"
  [[ -x "${cache}/bin/node" ]] || return 1
  printf '%s\n' "${cache}/bin"
}

_prepend_path() {
  local dir="$1"
  [[ -n "$dir" && -d "$dir" ]] || return 0
  case ":${PATH}:" in
    *":${dir}:"*) ;;
    *) export PATH="${dir}:${PATH}" ;;
  esac
}

_ensure_pnpm() {
  local root_dir="${1:-}"

  if command -v pnpm >/dev/null 2>&1; then
    return 0
  fi

  _ensure_corepack_noninteractive
  if command -v corepack >/dev/null 2>&1; then
    _ensure_build_node_log "Corepack prepare pnpm@10 --activate"
    if corepack prepare pnpm@10 --activate; then
      command -v pnpm >/dev/null 2>&1 && return 0
    fi
  fi

  local npm_prefix="${root_dir}/vendor/.cache/npm-global"
  [[ -n "$root_dir" ]] || npm_prefix="${TMPDIR:-/tmp}/steamos-npm-global"
  mkdir -p "$npm_prefix"
  _ensure_build_node_log "Installing pnpm@10 → ${npm_prefix} (local prefix, sudo-safe)"
  npm install -g pnpm@10 --prefix "$npm_prefix"
  _prepend_path "${npm_prefix}/bin"
  command -v pnpm >/dev/null 2>&1
}

ensure_build_node() {
  local root_dir="${1:-}"
  local home d node_bin

  if command -v node >/dev/null 2>&1 && command -v pnpm >/dev/null 2>&1; then
    _ensure_build_node_log "OK: node $(node -v), pnpm $(pnpm -v)"
    return 0
  fi

  # 1) Repo vendor cache (preferred under sudo — same tree as the bake)
  if [[ -n "$root_dir" ]]; then
    if node_bin="$(_ensure_node_tarball "$root_dir")"; then
      _prepend_path "$node_bin"
      _ensure_build_node_log "Using bootstrapped Node from ${node_bin}"
    fi
  fi

  # 2) User-local Node installs (steam / SUDO_USER)
  if ! command -v node >/dev/null 2>&1; then
    local -a homes=()
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
      home="$(getent passwd "${SUDO_USER}" 2>/dev/null | cut -d: -f6 || true)"
      [[ -n "$home" ]] && homes+=("$home")
    fi
    [[ -n "${HOME:-}" ]] && homes+=("${HOME}")
    homes+=("/home/steam")

    for home in "${homes[@]}"; do
      [[ -n "$home" && -d "$home" ]] || continue
      for d in "${home}/.local"/node-v*-linux-arm64/bin; do
        [[ -x "${d}/node" ]] || continue
        _prepend_path "$d"
        _ensure_build_node_log "Using Node from ${d}"
        break 2
      done
    done
  fi

  command -v node >/dev/null 2>&1 || return 1
  _ensure_pnpm "$root_dir" || return 1

  _ensure_build_node_log "OK: node $(node -v), pnpm $(pnpm -v)"
  return 0
}
