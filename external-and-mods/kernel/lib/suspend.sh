#!/usr/bin/env bash
# Userspace hooks for SM8550 deep suspend (systemd). Replaces fake-suspend / keepalive.
set -euo pipefail

# Devices validated for deep suspend in ROCKNIX PR #2954
_suspend_device_allowed() {
    local model compat=""
    if [[ "${SUSPEND_DEEP_ALL:-0}" == "1" ]]; then
        return 0
    fi
    if [[ -r /proc/device-tree/compatible ]]; then
        compat="$(tr '\0' ' ' </proc/device-tree/compatible 2>/dev/null || true)"
    fi
    model="$(cat /sys/firmware/devicetree/base/model 2>/dev/null || true)"
    case "${compat} ${model}" in
        *odin2*|*Odin*2*|*ayn,odin2*|*ayn,odin2mini*|*ayn,odin2portal*|*ayn,thor*|*Thor*|*retroidpocket,rp6*|*RP6*|*Retroid*Pocket*6*)
            return 0
            ;;
    esac
    return 1
}

disable_fake_suspend_and_keepalive() {
    local u
    for u in \
        masi-ufs-gaming-keepalive.service \
        rocknix-fake-suspend.service \
        fake-suspend.service
    do
        if systemctl list-unit-files "${u}" &>/dev/null; then
            systemctl disable --now "${u}" 2>/dev/null || true
            systemctl mask "${u}" 2>/dev/null || true
            echo "  disabled/masked ${u}" >&2
        fi
    done
    rm -f /usr/bin/masi-ufs-gaming-keepalive \
          /usr/lib/systemd/system/masi-ufs-gaming-keepalive.service \
          /etc/systemd/system/masi-ufs-gaming-keepalive.service \
          /etc/systemd/system/masi-ufs-gaming-keepalive.service 2>/dev/null || true
}

install_deep_suspend_config() {
    disable_fake_suspend_and_keepalive

    [[ "${SUSPEND_DEEP:-0}" == "1" ]] || {
        echo "  deep-suspend: SUSPEND_DEEP=0 — userspace not installed" >&2
        return 0
    }

    if ! _suspend_device_allowed; then
        echo "  deep-suspend: device not in PR#2954 validated set (Odin2/Mini/Portal/Thor/RP6)" >&2
        echo "  deep-suspend: kernel patches still applied; set SUSPEND_DEEP_ALL=1 to force userspace" >&2
        return 0
    fi

    [[ -d /etc/systemd ]] || {
        echo "  deep-suspend: no systemd — skip sleep.conf.d" >&2
        return 0
    }

    mkdir -p /etc/systemd/sleep.conf.d /etc/systemd/logind.conf.d

    install -m644 "${ROOT}/config/sleep/masi-deep-suspend.conf" \
        /etc/systemd/sleep.conf.d/masi-deep-suspend.conf
    install -m644 "${ROOT}/config/sleep/masi-logind-suspend.conf" \
        /etc/systemd/logind.conf.d/masi-suspend.conf

    systemctl daemon-reload 2>/dev/null || true
    echo "  deep-suspend: systemd sleep + logind (mem / power key)" >&2
}
