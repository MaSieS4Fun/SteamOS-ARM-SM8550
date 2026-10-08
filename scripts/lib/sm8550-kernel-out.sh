#!/usr/bin/env bash
# Resolve the SM8550 kernel pack directory (boot/KERNEL + modules/<uname -r>/).
# Override: KERNEL_OUT=/path/to/pack
#
# Preferred: kernel/output/current → latest *-kbase build.

sm8550_kernel_output_root() {
  echo "${1}/kernel/output"
}

sm8550_resolve_kout() {
  local mod="${1}"
  local out src d best=""

  out="$(sm8550_kernel_output_root "${mod}")"

  if [[ -n "${KERNEL_OUT:-}" ]]; then
    [[ -f "${KERNEL_OUT}/boot/KERNEL" ]] || return 1
    echo "${KERNEL_OUT}"
    return 0
  fi

  if [[ -e "${out}/current/boot/KERNEL" ]]; then
    src="$(readlink -f "${out}/current" 2>/dev/null || true)"
    echo "${src:-${out}/current}"
    return 0
  fi

  shopt -s nullglob
  for d in "${out}"/*-kbase "${out}"/*-edge-sm8550; do
    [[ -f "${d}/boot/KERNEL" ]] || continue
    if [[ -z "${best}" || "${d}" -nt "${best}" ]]; then
      best="${d}"
    fi
  done
  shopt -u nullglob

  [[ -n "${best}" ]] || return 1
  echo "${best}"
}

sm8550_kernel_release() {
  local kout="$1"
  local -a mods=()
  shopt -s nullglob
  mods=("${kout}/modules/"*-edge-sm8550)
  shopt -u nullglob
  [[ ${#mods[@]} -gt 0 ]] || return 1
  basename "${mods[0]}"
}

sm8550_link_current_kout() {
  local mod="${1}" kout="${2:-}"
  local out
  out="$(sm8550_kernel_output_root "${mod}")"
  [[ -d "${out}" ]] || return 1
  if [[ -z "${kout}" ]]; then
    kout="$(sm8550_resolve_kout "${mod}")" || return 1
  fi
  ln -sfn "$(basename "${kout}")" "${out}/current"
}
