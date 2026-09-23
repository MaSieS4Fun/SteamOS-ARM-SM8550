#!/usr/bin/env bash
# Install UFS/GPU keep-awake for gaming (userspace; safe with or without deep-suspend patches).
set -euo pipefail

install_ufs_gaming_keepalive() {
    local unit_src="${ROOT}/config/gaming/masi-ufs-gaming-keepalive.service"
    local bin_src="${ROOT}/packaging/bin/masi-ufs-gaming-keepalive"

    [[ -f "${bin_src}" && -f "${unit_src}" ]] || {
        echo "  ufs-gaming: missing packaging files — skip" >&2
        return 0
    }

    install -d /usr/bin /usr/lib/systemd/system
    install -m 0755 "${bin_src}" /usr/bin/masi-ufs-gaming-keepalive
    install -m 0644 "${unit_src}" /usr/lib/systemd/system/masi-ufs-gaming-keepalive.service

    systemctl daemon-reload 2>/dev/null || true
    systemctl enable --now masi-ufs-gaming-keepalive.service 2>/dev/null || {
        # enable may fail in chroot; still run once if sysfs present
        /usr/bin/masi-ufs-gaming-keepalive 2>/dev/null || true
        echo "  ufs-gaming: script installed (enable service after reboot if needed)" >&2
        return 0
    }
    echo "  ufs-gaming: masi-ufs-gaming-keepalive enabled" >&2
}
