#!/usr/bin/env python3
"""Fetch ROCKNIX PR #2952 deep-suspend kernel patches into patches/masi/."""
from __future__ import annotations

import argparse
import sys
import urllib.request
from pathlib import Path

BASE = (
    "https://raw.githubusercontent.com/ROCKNIX/distribution/"
    "abcc2bc87ea41416e88ba2c15557842c460193f9/"
    "projects/ROCKNIX/devices/SM8550/patches/linux"
)

MAP = {
    "0201-scsi-ufs-drain-relink-completions-out-of-band-pm.patch":
        "1006-scsi-ufs-drain-relink-completions-out-of-band-pm.patch",
    "0207-scsi-ufs-qcom-balance-irq-on-host-reset-error.patch":
        "1007-scsi-ufs-qcom-balance-irq-on-host-reset-error.patch",
    "1007-scsi-ufs-qcom-propagate-hibern8-exit-failure-clk-scale.patch":
        "1008-scsi-ufs-qcom-propagate-hibern8-exit-failure-clk-scale.patch",
    "1008-scsi-ufs-qcom-auto-hibern8-clk-gating-collision.patch":
        "1009-scsi-ufs-qcom-auto-hibern8-clk-gating-collision.patch",
    "1010-scsi-ufs-qcom-keep-mphy-powered-on-hibern8-park.patch":
        "1010-scsi-ufs-qcom-keep-mphy-powered-on-hibern8-park.patch",
    "1015-ufs-qcom-disable-rx-linecfg-after-link-startup.patch":
        "1011-ufs-qcom-qmp-rx-linecfg-link-startup.patch",
    "0502-wakeup-qcom-ipcc-remove-IRQF-NO-SUSPEND.patch":
        "1012-mailbox-qcom-ipcc-remove-irqf-no-suspend.patch",
    "0203-thermal-qcom-tsens-skip-ayn-thor-uplow-wake-irq.patch":
        "1013-thermal-qcom-tsens-skip-ayn-thor-uplow-wake-irq.patch",
}

# linux-7.0 uses qmp_ufs_init_registers(), not the downstream qmp_ufs_init() name.
PORT_1011 = (
    ("qmp_ufs_init(struct qmp_ufs *qmp, const struct qmp_phy_cfg *cfg)",
     "qmp_ufs_init_registers(struct qmp_ufs *qmp, const struct qmp_phy_cfg *cfg)"),
    ("@@ -738,10 +738,17 @@ static int ufs_qcom_link_startup_notify",
     "@@ -716,10 +717,17 @@ static int ufs_qcom_cfg_timers(struct ufs_hba *hba, bool is_pre_scale_up, unsign"),
)


def port_1011_for_linux_7(data: bytes) -> bytes:
    text = data.decode("utf-8")
    for old, new in PORT_1011:
        text = text.replace(old, new)
    return text.encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-download even when patches/masi/ already has vendored copies",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    dest = root / "patches" / "masi"
    dest.mkdir(parents=True, exist_ok=True)

    for src, dst in MAP.items():
        out = dest / dst
        if out.exists() and not args.force:
            print(f"  SKIP {dst} (already vendored; use --force to replace)", file=sys.stderr)
            continue
        url = f"{BASE}/{src}"
        print(f"==> {dst}", file=sys.stderr)
        with urllib.request.urlopen(url, timeout=120) as resp:
            data = resp.read()
        if dst.startswith("1011-"):
            data = port_1011_for_linux_7(data)
            print("  port linux-7.0 anchors for 1011", file=sys.stderr)
        out.write_bytes(data)
        print(f"  {len(data)} bytes", file=sys.stderr)

    print(f"Done: {dest}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
