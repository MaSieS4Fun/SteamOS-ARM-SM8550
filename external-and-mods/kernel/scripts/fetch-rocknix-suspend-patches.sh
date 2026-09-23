#!/usr/bin/env bash
# One-time helper: fetch deep-suspend patches from ROCKNIX PR #2952 into patches/masi/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="https://raw.githubusercontent.com/ROCKNIX/distribution/abcc2bc87ea41416e88ba2c15557842c460193f9/projects/ROCKNIX/devices/SM8550/patches/linux"
DEST="${ROOT}/patches/masi"
FORCE=0

[[ "${1:-}" == "--force" ]] && FORCE=1

mkdir -p "${DEST}"

fetch() {
    local src="$1" dst="$2"
    if [[ "${FORCE}" -eq 0 && -f "${DEST}/${dst}" ]]; then
        echo "  SKIP ${dst} (already vendored; pass --force to replace)" >&2
        return 0
    fi
    echo "==> ${dst}" >&2
    curl -fsSL "${BASE}/${src}" -o "${DEST}/${dst}"
    if [[ "${dst}" == 1011-ufs-qcom-qmp-rx-linecfg-link-startup.patch ]]; then
        sed -i \
            -e 's/qmp_ufs_init(struct qmp_ufs \*qmp, const struct qmp_phy_cfg \*cfg)/qmp_ufs_init_registers(struct qmp_ufs *qmp, const struct qmp_phy_cfg *cfg)/g' \
            -e 's/@@ -738,10 +738,17 @@ static int ufs_qcom_link_startup_notify/@@ -716,10 +717,17 @@ static int ufs_qcom_cfg_timers(struct ufs_hba *hba, bool is_pre_scale_up, unsign/' \
            "${DEST}/${dst}"
        echo "  port linux-7.0 anchors for 1011" >&2
    fi
}

fetch 0201-scsi-ufs-drain-relink-completions-out-of-band-pm.patch \
    1006-scsi-ufs-drain-relink-completions-out-of-band-pm.patch
fetch 0207-scsi-ufs-qcom-balance-irq-on-host-reset-error.patch \
    1007-scsi-ufs-qcom-balance-irq-on-host-reset-error.patch
fetch 1007-scsi-ufs-qcom-propagate-hibern8-exit-failure-clk-scale.patch \
    1008-scsi-ufs-qcom-propagate-hibern8-exit-failure-clk-scale.patch
fetch 1008-scsi-ufs-qcom-auto-hibern8-clk-gating-collision.patch \
    1009-scsi-ufs-qcom-auto-hibern8-clk-gating-collision.patch
fetch 1010-scsi-ufs-qcom-keep-mphy-powered-on-hibern8-park.patch \
    1010-scsi-ufs-qcom-keep-mphy-powered-on-hibern8-park.patch
fetch 1015-ufs-qcom-disable-rx-linecfg-after-link-startup.patch \
    1011-ufs-qcom-qmp-rx-linecfg-link-startup.patch
fetch 0502-wakeup-qcom-ipcc-remove-IRQF-NO-SUSPEND.patch \
    1012-mailbox-qcom-ipcc-remove-irqf-no-suspend.patch
fetch 0203-thermal-qcom-tsens-skip-ayn-thor-uplow-wake-irq.patch \
    1013-thermal-qcom-tsens-skip-ayn-thor-uplow-wake-irq.patch

echo "Done: ${DEST}/1006-1013 suspend patches"
