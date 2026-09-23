#!/usr/bin/env bash
# linux-7.2.x bridges — Armbian sm8550-7.0 patches + MaSi overlays on kernel.org 7.2.
set -euo pipefail

_kernel_is_72_series() {
    local ver="${1:-${KERNEL_VER:-}}"
    [[ "$(kernel_major_minor "${ver}")" == "7.2" ]]
}

_ensure_makefile_panel_obj() {
    local mk="$1" config="$2" obj="$3"
    grep -q "${obj}" "${mk}" && return 0
    echo "obj-\$(CONFIG_${config}) += ${obj}" >> "${mk}"
}

_try_apply_armbian_patch_loose() {
    local src_dir="$1" patch_file="$2"
    [[ -f "${patch_file}" ]] || return 1
    patch -p1 -l -d "${src_dir}" -f < "${patch_file}" >/dev/null 2>&1
}

_armbian_patch_bridge_72() {
    local base="$1" src_dir="$2" patch_dir="$3"
    local patch="${patch_dir}/${base}"

    case "${base}" in
    0007-mmc-sdhci-msm-Toggle-the-FIFO-write-clock-after-unga.patch)
        bridge_72_sdhci_msm_fifo_toggle "${src_dir}" && return 0
        _try_apply_armbian_patch_loose "${src_dir}" "${patch}" && return 0
        ;;
    0008-ASoC-codecs-aw88166-AYN-Products-Specific-modificati.patch)
        bridge_72_aw88166_ayn "${src_dir}" && return 0
        ;;
    0016-drm-panel-Add-panel-driver-for-Xm-Plus-XM91080G-base.patch)
        _try_apply_armbian_patch_loose "${src_dir}" "${patch}" || true
        _ensure_makefile_panel_obj \
            "${src_dir}/drivers/gpu/drm/panel/Makefile" \
            "DRM_PANEL_BOE_XM91080G" "panel-boe-xm91080g.o"
        [[ -f "${src_dir}/drivers/gpu/drm/panel/panel-boe-xm91080g.c" ]] && return 0
        ;;
    0017-drm-panel-Add-panel-driver-for-Chipone-ICNA35XX-base.patch)
        _try_apply_armbian_patch_loose "${src_dir}" "${patch}" || true
        _ensure_makefile_panel_obj \
            "${src_dir}/drivers/gpu/drm/panel/Makefile" \
            "DRM_PANEL_CHIPONE_ICNA35XX" "panel-chipone-icna35xx.o"
        [[ -f "${src_dir}/drivers/gpu/drm/panel/panel-chipone-icna35xx.c" ]] && return 0
        ;;
    0018-drm-panel-Add-panel-driver-for-DDIC-CH13726A-based-p.patch)
        [[ -f "${src_dir}/drivers/gpu/drm/panel/panel-chipwealth-ch13726a.c" ]] && return 0
        _try_apply_armbian_patch_loose "${src_dir}" "${patch}" && return 0
        ;;
    0022-regulator-add-sgm3804-i2c-regulator-for-panel-power-.patch)
        [[ -f "${src_dir}/drivers/regulator/sgm3804-regulator.c" ]] && return 0
        ;;
    0026-SM8550-Fix-L2-cache-for-CPU2-and-add-cache-sizes.patch)
        bridge_72_sm8550_cache_sizes "${src_dir}" && return 0
        _try_apply_armbian_patch_loose "${src_dir}" "${patch}" && return 0
        ;;
    0027-SM8550-Add-DDR-LLCC-L3-CPU-bandwidth-scaling.patch)
        grep -q 'operating-points-v2 = <&cpu0_opp_table>' \
            "${src_dir}/arch/arm64/boot/dts/qcom/sm8550.dtsi" 2>/dev/null && return 0
        ;;
    0028-arm64-dts-qcom-sm8550-Update-EAS-properties.patch)
        grep -q 'capacity-dmips-mhz = <326>' \
            "${src_dir}/arch/arm64/boot/dts/qcom/sm8550.dtsi" 2>/dev/null && return 0
        ;;
    0029-arm64-dts-qcom-sm8550-add-UART15.patch)
        grep -q 'uart15: serial@89c000' \
            "${src_dir}/arch/arm64/boot/dts/qcom/sm8550.dtsi" 2>/dev/null && return 0
        ;;
    0009-arm64-dts-qcom-Added-pmk8550_pwm.patch)
        grep -q 'pmk8550_pwm: pwm' \
            "${src_dir}/arch/arm64/boot/dts/qcom/pmk8550.dtsi" 2>/dev/null && return 0
        ;;
    esac
    return 1
}

bridge_72_sdhci_msm_fifo_toggle() {
    local src_dir="$1" f="${src_dir}/drivers/mmc/host/sdhci-msm.c"
    [[ -f "${f}" ]] || return 1
    grep -q 'bool toggle_fifo_clk' "${f}" && return 0
    grep -q 'sdhci_msm_toggle_fifo_write_clk' "${f}" && {
        python3 - "${f}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
if "bool toggle_fifo_clk" in text:
    sys.exit(0)
text, n = re.subn(
    r"(bool vqmmc_enabled;\n)(\tbool non_cqe_ice_init_done;\n\};)",
    r"\1\tbool toggle_fifo_clk;\n\2",
    text,
    count=1,
)
if n != 1:
    sys.exit(1)
path.write_text(text)
PY
        grep -q 'bool toggle_fifo_clk' "${f}" && return 0
    }
    grep -q 'toggle_fifo_clk' "${f}" && return 0

    python3 - "${f}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

if "toggle_fifo_clk" in text:
    sys.exit(0)

if "RCLK_TOGGLE" not in text:
    text = text.replace(
        "#define CQHCI_VENDOR_DIS_RST_ON_CQ_EN\t(0x3 << 13)\n",
        "#define CQHCI_VENDOR_DIS_RST_ON_CQ_EN\t(0x3 << 13)\n#define RCLK_TOGGLE BIT(1)\n",
        1,
    )

text, n = re.subn(
    r"(bool vqmmc_enabled;\n)(\tbool non_cqe_ice_init_done;\n\};)",
    r"\1\tbool toggle_fifo_clk;\n\2",
    text,
    count=1,
)
if n != 1:
    text, n = re.subn(
        r"(struct sdhci_msm_host \{.*?bool vqmmc_enabled;\n)(\};)",
        r"\1\tbool toggle_fifo_clk;\n\2",
        text,
        count=1,
        flags=re.S,
    )
if n != 1:
    sys.exit(1)

fn = '''
/*
 * After MCLK ugating, toggle the FIFO write clock to get
 * the FIFO pointers and flags to valid state.
 */
static void sdhci_msm_toggle_fifo_write_clk(struct sdhci_host *host)
{
\tu32 config;
\tstruct mmc_ios ios = host->mmc->ios;
\tstruct sdhci_pltfm_host *pltfm_host = sdhci_priv(host);
\tstruct sdhci_msm_host *msm_host = sdhci_pltfm_priv(pltfm_host);
\tconst struct sdhci_msm_offset *msm_offset = msm_host->offset;

\tif ((msm_host->tuning_done || ios.enhanced_strobe) &&
\t    host->mmc->ios.timing == MMC_TIMING_MMC_HS400) {
\t\tconfig = readl_relaxed(host->ioaddr + msm_offset->core_dll_config_3);
\t\tconfig |= RCLK_TOGGLE;
\t\twritel_relaxed(config, host->ioaddr + msm_offset->core_dll_config_3);
\t\twmb();
\t\tudelay(2);
\t\tconfig &= ~RCLK_TOGGLE;
\t\twritel_relaxed(config, host->ioaddr + msm_offset->core_dll_config_3);
\t}
}

'''
anchor = "static int sdhci_msm_restore_sdr_dll_config(struct sdhci_host *host)"
if anchor not in text or "sdhci_msm_toggle_fifo_write_clk" in text:
    sys.exit(1)
text = text.replace(anchor, fn + anchor, 1)

text, n = re.subn(
    r"(if \(core_major == 1 && core_minor >= 0x71\)\n\t\tmsm_host->uses_tassadar_dll = true;\n)",
    r"\1\n\tif (core_major == 1 && core_minor >= 0x6B)\n\t\tmsm_host->toggle_fifo_clk = true;\n",
    text,
    count=1,
)
if n != 1:
    sys.exit(1)

text, n = re.subn(
    r"(static int sdhci_msm_runtime_resume\(struct device \*dev\)\n\{.*?if \(ret\)\n\t\treturn ret;\n)",
    r"\1\n\tif (msm_host->toggle_fifo_clk)\n\t\tsdhci_msm_toggle_fifo_write_clk(host);\n",
    text,
    count=1,
    flags=re.S,
)
if n != 1:
    sys.exit(1)

path.write_text(text)
PY
}

bridge_72_aw88166_ayn() {
    local src_dir="$1" f="${src_dir}/sound/soc/codecs/aw88166.c"
    [[ -f "${f}" ]] || return 1
    grep -q 'aw88166_of_match' "${f}" && grep -q 'aw88166_dai_ops' "${f}" && return 0

    python3 - "${f}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
changed = False

if "#include <linux/of.h>" not in text:
    text = text.replace(
        "#include <linux/i2c.h>\n",
        "#include <linux/i2c.h>\n#include <linux/of.h>\n#include <linux/of_device.h>\n",
        1,
    )
    changed = True

if "AW88166_DSP_I2C_WRITES" not in text and "#else" not in text.split("aw_dev_dsp_update_container", 1)[-1][:800]:
    old = """\tfor (i = 0; i < len; i += AW88166_MAX_RAM_WRITE_BYTE_SIZE) {
\t\ttmp_len = min(len - i, AW88166_MAX_RAM_WRITE_BYTE_SIZE);
\t\tret = regmap_raw_write(aw_dev->regmap, AW88166_DSPMDAT_REG,
\t\t\t\t\tdata + i, tmp_len);
\t\tif (ret)
\t\t\treturn ret;
\t}"""
    new = """#ifdef AW88166_DSP_I2C_WRITES
\tu32 tmp_len;
\tfor (i = 0; i < len; i += AW88166_MAX_RAM_WRITE_BYTE_SIZE) {
\t\ttmp_len = min(len - i, AW88166_MAX_RAM_WRITE_BYTE_SIZE);
\t\tret = regmap_raw_write(aw_dev->regmap, AW88166_DSPMDAT_REG,
\t\t\t\t\tdata + i, tmp_len);
\t\tif (ret)
\t\t\treturn ret;
\t}
#else
\t__be16 reg_val;
\tfor (i = 0; i < len; i += 2) {
\t\treg_val = cpu_to_be16p((u16 *)(data + i));
\t\tret = regmap_write(aw_dev->regmap, AW88166_DSPMDAT_REG, (u16)reg_val);
\t\tif (ret)
\t\t\treturn ret;
\t}
#endif"""
    if old in text:
        text = text.replace(old, new, 1)
        changed = True

if "aw88166_dai_ops" not in text:
    block = """
static int aw88166_startup(struct snd_pcm_substream *substream, struct snd_soc_dai *dai)
{
\treturn 0;
}

static int aw88166_set_fmt(struct snd_soc_dai *dai, unsigned int fmt)
{
\treturn 0;
}

static int aw88166_set_dai_sysclk(struct snd_soc_dai *dai, int clk_id,
\t\t\t\t  unsigned int freq, int dir)
{
\treturn 0;
}

static int aw88166_hw_params(struct snd_pcm_substream *substream,
\t\t\t     struct snd_pcm_hw_params *params, struct snd_soc_dai *dai)
{
\treturn 0;
}

static int aw88166_mute(struct snd_soc_dai *dai, int mute, int stream)
{
\treturn 0;
}

static void aw88166_shutdown(struct snd_pcm_substream *substream, struct snd_soc_dai *dai)
{
}

static const struct snd_soc_dai_ops aw88166_dai_ops = {
\t.startup = aw88166_startup,
\t.set_fmt = aw88166_set_fmt,
\t.set_sysclk = aw88166_set_dai_sysclk,
\t.hw_params = aw88166_hw_params,
\t.mute_stream = aw88166_mute,
\t.shutdown = aw88166_shutdown,
};

"""
    anchor = "static struct snd_soc_dai_driver aw88166_dai[] = {"
    if anchor in text:
        text = text.replace(anchor, block + anchor, 1)
        text = text.replace(
            "\t\t.formats = AW88166_FORMATS,\n\t\t},\n\t},\n};",
            "\t\t.formats = AW88166_FORMATS,\n\t\t},\n\t\t.ops = &aw88166_dai_ops,\n\t},\n};",
            1,
        )
        changed = True

if "firmware-name" not in text and "aw88166_request_firmware_file" in text:
    text = text.replace(
        "\tconst struct firmware *cont = NULL;\n\tint ret;\n",
        "\tconst struct firmware *cont = NULL;\n\tconst char *fw_name;\n\tint ret;\n",
        1,
    )
    text = text.replace(
        "\taw88166->aw_pa->fw_status = AW88166_DEV_FW_FAILED;\n\n\tret = request_firmware(&cont, AW88166_ACF_FILE, aw88166->aw_pa->dev);",
        "\taw88166->aw_pa->fw_status = AW88166_DEV_FW_FAILED;\n\n\tif (device_property_read_string(aw88166->aw_pa->dev, \"firmware-name\", &fw_name))\n\t\tfw_name = AW88166_ACF_FILE;\n\n\tret = request_firmware(&cont, fw_name, aw88166->aw_pa->dev);",
        1,
    )
    text = text.replace("AW88166_ACF_FILE", "fw_name", 3)
    changed = True

if "aw88166_of_match" not in text:
    text = text.replace(
        "MODULE_DEVICE_TABLE(i2c, aw88166_i2c_id);\n\nstatic struct i2c_driver aw88166_i2c_driver = {",
        "MODULE_DEVICE_TABLE(i2c, aw88166_i2c_id);\n\nstatic const struct of_device_id aw88166_of_match[] = {\n\t{ .compatible = \"awinic,aw88166\" },\n\t{ /* sentinel */ }\n};\nMODULE_DEVICE_TABLE(of, aw88166_of_match);\n\nstatic struct i2c_driver aw88166_i2c_driver = {",
        1,
    )
    text = text.replace(
        "\t.driver = {\n\t\t.name = AW88166_I2C_NAME,\n\t},",
        "\t.driver = {\n\t\t.name = AW88166_I2C_NAME,\n\t\t.of_match_table = aw88166_of_match,\n\t},",
        1,
    )
    changed = True

if not changed:
    sys.exit(1)
path.write_text(text)
PY
}

bridge_72_sm8550_cache_sizes() {
    local src_dir="$1" dtsi="${src_dir}/arch/arm64/boot/dts/qcom/sm8550.dtsi"
    [[ -f "${dtsi}" ]] || return 1
    grep -q 'd-cache-size = <0x8000>' "${dtsi}" && return 0

    python3 - "${dtsi}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
changed = False

cache = (
    "\t\t\td-cache-size = <0x8000>;\n"
    "\t\t\td-cache-line-size = <64>;\n"
    "\t\t\td-cache-sets = <128>;\n"
    "\t\t\ti-cache-size = <0x8000>;\n"
    "\t\t\ti-cache-line-size = <64>;\n"
    "\t\t\ti-cache-sets = <128>;\n"
)

for cpu in ("cpu0: cpu@0", "cpu1: cpu@100", "cpu2: cpu@200"):
    marker = f"\t\t{cpu} {{\n"
    if marker not in text:
        continue
    start = text.index(marker)
    end = text.index("\t\t};", start)
    block = text[start:end]
    if "d-cache-size" in block:
        continue
    insert_at = block.find('\t\t\tenable-method = "psci";\n')
    if insert_at < 0:
        continue
    insert_at += len('\t\t\tenable-method = "psci";\n')
    block = block[:insert_at] + cache + block[insert_at:]
    text = text[:start] + block + text[end:]
    changed = True

if "cpu2: cpu@200" in text:
    old = "\t\t\tnext-level-cache = <&l2_200>;\n"
    new = "\t\t\tnext-level-cache = <&l2_100>;\n"
    if old in text:
        text = text.replace(old, new, 1)
        changed = True

if not changed and "d-cache-size" not in text:
    sys.exit(1)
path.write_text(text)
PY
}

bridge_72_ufshcd_1006_intr() {
    local src_dir="$1" f="${src_dir}/drivers/ufs/core/ufshcd.c"
    local patch="${ROOT}/patches/masi/1006-scsi-ufs-drain-relink-completions-out-of-band-pm.patch"
    [[ -f "${f}" ]] || return 1

    if ! grep -q 'ufshcd_pm_drain_completions' "${f}" && [[ -f "${patch}" ]]; then
        patch -p1 -l -d "${src_dir}" -f < "${patch}" >/dev/null 2>&1 || true
    fi

    grep -q 'ufshcd_pm_drain_completions' "${f}" || return 1
    grep -q 'ufshcd_relinking(hba)' "${f}" && grep -A20 'ufshcd_intr(int irq' "${f}" | grep -q 'ufshcd_pm_drain_completions' && return 0

    python3 - "${f}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

hook = """
\tif (!hba->mcq_enabled && ufshcd_relinking(hba)) {
\t\tufshcd_pm_drain_completions(hba);
\t\treturn IRQ_HANDLED;
\t}

"""
fn = "static irqreturn_t ufshcd_intr(int irq, void *__hba)"
start = text.find(fn)
if start < 0:
    sys.exit(1)
anchor = "struct ufs_hba *hba = __hba;"
idx = text.find(anchor, start)
if idx < 0:
    sys.exit(1)
insert_at = idx + len(anchor)
if insert_at < len(text) and text[insert_at] == "\n":
    insert_at += 1
window = text[start:insert_at + 200]
if "ufshcd_pm_drain_completions(hba)" in window:
    sys.exit(0)
text = text[:insert_at] + hook + text[insert_at:]
path.write_text(text)
PY
}

bridge_72_tsens_1013() {
    local src_dir="$1" f="${src_dir}/drivers/thermal/qcom/tsens.c"
    [[ -f "${f}" ]] || return 1
    grep -q 'tsens_irq_wake_enabled' "${f}" && return 0

    python3 - "${f}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

helper = """
static bool tsens_irq_wake_enabled(const char *irqname)
{
\tif (!of_machine_is_compatible("qcom,sm8550"))
\t\treturn true;

\treturn strcmp(irqname, "uplow") != 0;
}

"""

anchor = "static int tsens_register_irq(struct tsens_priv *priv, char *irqname,"
if helper.strip() in text:
    sys.exit(0)
if anchor not in text:
    sys.exit(1)
text = text.replace(anchor, helper + anchor, 1)

old = """\tif (priv->feat->combo_int)
\t\tenable_irq_wake(priv->combined_irq);
\telse {
\t\tenable_irq_wake(priv->uplow_irq);
\t\tif (priv->feat->crit_int)
\t\t\tenable_irq_wake(priv->crit_irq);
\t}"""
new = """\tif (priv->feat->combo_int) {
\t\tif (tsens_irq_wake_enabled("combined"))
\t\t\tenable_irq_wake(priv->combined_irq);
\t} else {
\t\tif (tsens_irq_wake_enabled("uplow"))
\t\t\tenable_irq_wake(priv->uplow_irq);
\t\tif (priv->feat->crit_int && tsens_irq_wake_enabled("critical"))
\t\t\tenable_irq_wake(priv->crit_irq);
\t}"""
if old not in text:
    sys.exit(1)
text = text.replace(old, new, 1)
path.write_text(text)
PY
}

_masi_patch_bridge_72() {
    local base="$1" src_dir="$2"
    case "${base}" in
    1006-scsi-ufs-drain-relink-completions-out-of-band-pm.patch)
        bridge_72_ufshcd_1006_intr "${src_dir}" && return 0
        ;;
    1013-thermal-qcom-tsens-skip-ayn-thor-uplow-wake-irq.patch)
        bridge_72_tsens_1013 "${src_dir}" && return 0
        ;;
    1005-thor-ch13726a-reset-polarity-fix.patch)
        [[ -f "${src_dir}/drivers/gpu/drm/panel/panel-chipwealth-ch13726a.c" ]] \
            && grep -q 'GPIOD_OUT_HIGH' \
                "${src_dir}/drivers/gpu/drm/panel/panel-chipwealth-ch13726a.c" && return 0
        ;;
    1015-q6apm-dp-graph-start-on-trigger.patch)
        grep -q 'q6apm_lpass_dai_trigger' \
            "${src_dir}/sound/soc/qcom/qdsp6/q6apm-lpass-dais.c" 2>/dev/null && return 0
        ;;
    1025-misc-fastrpc-adsp-sensor-pd-and-legacy-ioctl.patch)
        grep -q 'FASTRPC_IOCTL_INIT_ATTACH_SNS' "${src_dir}/drivers/misc/fastrpc.c" 2>/dev/null \
            && grep -q 'SENSORS_PD' "${src_dir}/drivers/misc/fastrpc.c" 2>/dev/null && return 0
        ;;
    1035-cpufeatures-sm8550-heterogeneous-quiet.patch)
        grep -q 'of_machine_is_compatible("qcom,sm8550")' \
            "${src_dir}/arch/arm64/kernel/cpufeature.c" 2>/dev/null && return 0
        bridge_72_cpufeature_sm8550_quiet "${src_dir}" && return 0
        ;;
    1034-ufs-quiet-unsupported-timestamp.patch)
        grep -q 'timestamp attr not supported' \
            "${src_dir}/drivers/ufs/core/ufshcd.c" 2>/dev/null && return 0
        bridge_72_ufs_quiet_timestamp "${src_dir}" && return 0
        ;;
    1036-sound-aw88166-quiet-local-pll-iis.patch)
        grep -q 'dev_dbg(aw_dev->dev, "check pll lock fail, reg_val:0x%04x"' \
            "${src_dir}/sound/soc/codecs/aw88166.c" 2>/dev/null && return 0
        bridge_72_aw88166_quiet_pll_iis "${src_dir}" && return 0
        ;;
    1037-sound-soc-quiet-einval-probe.patch)
        grep -q 'case -EINVAL:' "${src_dir}/sound/soc/soc-utils.c" 2>/dev/null \
            && grep -A6 'case -EINVAL:' "${src_dir}/sound/soc/soc-utils.c" 2>/dev/null \
            | grep -q 'dev_dbg(dev, "ASoC error' && return 0
        bridge_72_asoc_quiet_einval "${src_dir}" && return 0
        ;;
    1038-soundwire-qcom-quiet-port-mismatch.patch)
        grep -q 'dev_dbg(ctrl->dev, "dout-ports (%d) mismatch with controller (%d)"' \
            "${src_dir}/drivers/soundwire/qcom.c" 2>/dev/null && return 0
        bridge_72_soundwire_quiet_port_mismatch "${src_dir}" && return 0
        ;;
    esac
    return 1
}

bridge_72_ufs_quiet_timestamp() {
    local src_dir="$1" f="${src_dir}/drivers/ufs/core/ufshcd.c"
    [[ -f "${f}" ]] || return 1
    grep -q 'timestamp attr not supported' "${f}" && return 0

    python3 - "${f}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

qword_old = """\terr = ufshcd_exec_dev_cmd(hba, DEV_CMD_TYPE_QUERY, dev_cmd_timeout);
\tif (err) {
\t\tdev_err(hba->dev, "%s: opcode 0x%.2x for idn %d failed, index %d, selector %d, err = %d\\n",
\t\t\t__func__, opcode, idn, index, sel, err);
\t\tgoto out_unlock;
\t}"""

qword_new = """\terr = ufshcd_exec_dev_cmd(hba, DEV_CMD_TYPE_QUERY, dev_cmd_timeout);
\tif (err) {
\t\tif (idn == QUERY_ATTR_IDN_TIMESTAMP && err == -EINVAL) {
\t\t\thba->dev_quirks |= UFS_DEVICE_QUIRK_NO_TIMESTAMP_SUPPORT;
\t\t\tdev_dbg(hba->dev,
\t\t\t\t"%s: timestamp attr not supported (opcode 0x%.2x, err %d)\\n",
\t\t\t\t__func__, opcode, err);
\t\t\tgoto out_unlock;
\t\t}
\t\tdev_err(hba->dev, "%s: opcode 0x%.2x for idn %d failed, index %d, selector %d, err = %d\\n",
\t\t\t__func__, opcode, idn, index, sel, err);
\t\tgoto out_unlock;
\t}"""

ts_old = """\tif (err)
\t\tdev_err(hba->dev, "%s: failed to set timestamp %d\\n",
\t\t\t__func__, err);
}"""

ts_new = """\tif (err) {
\t\tif (err == -EINVAL) {
\t\t\thba->dev_quirks |= UFS_DEVICE_QUIRK_NO_TIMESTAMP_SUPPORT;
\t\t\tdev_dbg(hba->dev, "%s: timestamp not supported (%d)\\n",
\t\t\t\t__func__, err);
\t\t} else {
\t\t\tdev_err(hba->dev, "%s: failed to set timestamp %d\\n",
\t\t\t\t__func__, err);
\t\t}
\t}
}"""

if qword_old not in text or ts_old not in text:
    sys.exit(1)
text = text.replace(qword_old, qword_new, 1)
text = text.replace(ts_old, ts_new, 1)
path.write_text(text)
PY
    grep -q 'timestamp attr not supported' "${f}"
}

bridge_72_cpufeature_sm8550_quiet() {
    local src_dir="$1" f="${src_dir}/arch/arm64/kernel/cpufeature.c"
    [[ -f "${f}" ]] || return 1
    grep -q 'of_machine_is_compatible("qcom,sm8550")' "${f}" && return 0

    python3 - "${f}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

if 'of_machine_is_compatible("qcom,sm8550")' in text:
    sys.exit(0)

block = """
\tif (of_machine_is_compatible("qcom,sm8550") &&
\t    (sys_id == SYS_ID_AA64MMFR1_EL1 ||
\t     sys_id == SYS_ID_MMFR4_EL1)) {
\t\tpr_debug("heterogeneous %s on CPU%d (boot %#016llx, cpu %#016llx)\\n",
\t\t\t regp->name, cpu, boot, val);
\t\treturn 0;
\t}

"""

needle = "\tif ((boot & regp->strict_mask) == (val & regp->strict_mask))\n\t\treturn 0;\n\tpr_warn(\"SANITY CHECK:"
if needle not in text:
    sys.exit(1)
text = text.replace(
    "\tif ((boot & regp->strict_mask) == (val & regp->strict_mask))\n\t\treturn 0;\n\tpr_warn(\"SANITY CHECK:",
    "\tif ((boot & regp->strict_mask) == (val & regp->strict_mask))\n\t\treturn 0;\n" + block + "\tpr_warn(\"SANITY CHECK:",
    1,
)
if '#include <linux/of.h>' not in text:
    text = text.replace('#include <linux/cpuhotplug.h>\n',
                        '#include <linux/cpuhotplug.h>\n#include <linux/of.h>\n', 1)
path.write_text(text)
PY
    grep -q 'of_machine_is_compatible("qcom,sm8550")' "${f}"
}

bridge_72_aw88166_quiet_pll_iis() {
    local src_dir="$1" f="${src_dir}/sound/soc/codecs/aw88166.c"
    [[ -f "${f}" ]] || return 1
    grep -q 'dev_dbg(aw_dev->dev, "check pll lock fail, reg_val:0x%04x"' "${f}" && return 0

    python3 - "${f}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

replacements = [
    (
        '\t\tdev_err(aw_dev->dev, "check pll lock fail, reg_val:0x%04x", reg_val);',
        '\t\tdev_dbg(aw_dev->dev, "check pll lock fail, reg_val:0x%04x", reg_val);',
    ),
    (
        '\t\t\tdev_err(aw_dev->dev, "mode1 iis signal check error");',
        '\t\t\tdev_dbg(aw_dev->dev, "mode1 iis signal check error");',
    ),
    (
        '\t\t\tdev_err(aw_dev->dev, "mode2 iis signal check error");',
        '\t\t\tdev_dbg(aw_dev->dev, "mode2 iis signal check error");',
    ),
    (
        '\t\t\t\tdev_err(aw_dev->dev, "mode2 switch to mode1, iis signal check error");',
        '\t\t\t\tdev_dbg(aw_dev->dev, "mode2 switch to mode1, iis signal check error");',
    ),
    (
        '\t\t\tdev_err(aw_dev->dev, "mode2 check iis failed");',
        '\t\t\tdev_dbg(aw_dev->dev, "mode2 check iis failed");',
    ),
]

for old, new in replacements:
    if old not in text:
        sys.exit(1)
    text = text.replace(old, new, 1)

path.write_text(text)
PY
    grep -q 'dev_dbg(aw_dev->dev, "check pll lock fail, reg_val:0x%04x"' "${f}"
}

bridge_72_asoc_quiet_einval() {
    local src_dir="$1" f="${src_dir}/sound/soc/soc-utils.c"
    [[ -f "${f}" ]] || return 1
    if grep -q 'case -EINVAL:' "${f}" \
        && grep -A6 'case -EINVAL:' "${f}" | grep -q 'dev_dbg(dev, "ASoC error'; then
        return 0
    fi

    python3 - "${f}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

needle = (
    "\tcase -EOPNOTSUPP:\n"
    "\t\tbreak;\n"
    "\tdefault:"
)
insert = (
    "\tcase -EOPNOTSUPP:\n"
    "\t\tbreak;\n"
    "\tcase -EINVAL:\n"
    "\t\tva_start(args, fmt);\n"
    "\t\tvaf.fmt = fmt;\n"
    "\t\tvaf.va = &args;\n"
    "\n"
    "\t\tdev_dbg(dev, \"ASoC error (%d): %pV\", ret, &vaf);\n"
    "\t\tva_end(args);\n"
    "\t\tbreak;\n"
    "\tdefault:"
)
if needle not in text:
    sys.exit(1)
path.write_text(text.replace(needle, insert, 1))
PY
    grep -q 'case -EINVAL:' "${f}" \
        && grep -A6 'case -EINVAL:' "${f}" | grep -q 'dev_dbg(dev, "ASoC error'
}

bridge_72_soundwire_quiet_port_mismatch() {
    local src_dir="$1" f="${src_dir}/drivers/soundwire/qcom.c"
    [[ -f "${f}" ]] || return 1
    grep -q 'dev_dbg(ctrl->dev, "dout-ports (%d) mismatch with controller (%d)"' "${f}" && return 0

    python3 - "${f}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

replacements = [
    (
        '\t\t\tdev_err(ctrl->dev, "din-ports (%d) mismatch with controller (%d)",',
        '\t\t\tdev_dbg(ctrl->dev, "din-ports (%d) mismatch with controller (%d)",',
    ),
    (
        '\t\t\tdev_err(ctrl->dev, "dout-ports (%d) mismatch with controller (%d)",',
        '\t\t\tdev_dbg(ctrl->dev, "dout-ports (%d) mismatch with controller (%d)",',
    ),
]

for old, new in replacements:
    if old not in text:
        sys.exit(1)
    text = text.replace(old, new, 1)

path.write_text(text)
PY
    grep -q 'dev_dbg(ctrl->dev, "dout-ports (%d) mismatch with controller (%d)"' "${f}"
}

apply_sm8550_72_patch_bridges() {
    local src_dir="$1" patch_dir="$2" kernel_ver="${3:-${KERNEL_VER:-}}"
    _kernel_is_72_series "${kernel_ver}" || return 0
    echo "==> linux-${kernel_ver}: SM8550 7.2 compatibility bridges" >&2
    bridge_72_sdhci_msm_fifo_toggle "${src_dir}" || true
    bridge_72_aw88166_ayn "${src_dir}" || true
    bridge_72_sm8550_cache_sizes "${src_dir}" || true
    bridge_72_ufshcd_1006_intr "${src_dir}" || true
    bridge_72_tsens_1013 "${src_dir}" || true
    bridge_72_fixup_dts_duplicates "${src_dir}" || true
    return 0
}

bridge_72_fixup_drm_panel_file() {
    local f="$1"
    [[ -f "${f}" ]] || return 0
    grep -qE 'drm_panel_init|devm_drm_panel_alloc' "${f}" || return 0

    python3 - "${f}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
original = text

ALLOC_TYPED = re.compile(
    r"\t(\w+) = devm_drm_panel_alloc\(dev, __typeof\(\*\1\), (\w+),\n"
    r"\t\t\t\t   &(\w+),\n"
    r"\t\t\t\t   DRM_MODE_CONNECTOR_DSI\);\n"
    r"\tif \(IS_ERR\(\1\)\)\n"
    r"\t\treturn PTR_ERR\(\1\);\n\n?"
)

INIT_RE = re.compile(
    r"drm_panel_init\(&(\w+)->(\w+),\s*dev,\s*&(\w+),\s*(?:\n\s*)?DRM_MODE_CONNECTOR_DSI\);"
)


def find_function_range(src, start):
    depth = 0
    i = start
    while i < len(src):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(src)


def find_probe_range(src):
    m = re.search(r"static int \w+_probe\(struct mipi_dsi_device \*dsi\)\s*\{", src)
    if not m:
        return None
    return m.start(), find_function_range(src, m.end() - 1)


def strip_prepare_allocs(src):
    out = []
    pos = 0
    saved = None
    for m in re.finditer(
        r"static int (\w+)_prepare\(struct drm_panel \*panel\)\s*\{", src
    ):
        out.append(src[pos : m.start()])
        fn_start = m.start()
        fn_end = find_function_range(src, m.end() - 1)
        body = src[fn_start:fn_end]
        while True:
            am = ALLOC_TYPED.search(body)
            if not am:
                break
            saved = (am.group(1), am.group(2), am.group(3))
            body = body[: am.start()] + body[am.end() :]
        out.append(body)
        pos = fn_end
    out.append(src[pos:])
    return "".join(out), saved


text, saved_alloc = strip_prepare_allocs(text)

init_m = INIT_RE.search(text)
if init_m:
    var, member, funcs = init_m.group(1), init_m.group(2), init_m.group(3)
    saved_alloc = (var, member, funcs)
    text = re.sub(
        rf"\t{re.escape(var)} = devm_kzalloc\(dev, sizeof\(\*{re.escape(var)}\), GFP_KERNEL\);\n"
        rf"\tif \(!{re.escape(var)}\)\n"
        rf"\t\treturn -ENOMEM;\n\n?",
        "",
        text,
        count=1,
    )
    text = re.sub(
        rf"\tdrm_panel_init\(&{re.escape(var)}->{re.escape(member)},\s*dev,\s*&{re.escape(funcs)},\s*(?:\n\s*)?DRM_MODE_CONNECTOR_DSI\);\n",
        "",
        text,
        count=1,
    )

probe = find_probe_range(text)
if probe and saved_alloc and "devm_drm_panel_alloc" not in text[probe[0] : probe[1]]:
    var, member, funcs = saved_alloc
    alloc = (
        f"\t{var} = devm_drm_panel_alloc(dev, __typeof(*{var}), {member},\n"
        f"\t\t\t\t   &{funcs},\n"
        f"\t\t\t\t   DRM_MODE_CONNECTOR_DSI);\n"
        f"\tif (IS_ERR({var}))\n"
        f"\t\treturn PTR_ERR({var});\n\n"
    )
    inserted = False
    for pat in (
        rf"(static int \w+_probe\(struct mipi_dsi_device \*dsi\)\s*\{{\n"
        rf"\tstruct device \*dev = &dsi->dev;\n"
        rf"\tstruct \w+ \*{re.escape(var)};\n"
        rf"\tint ret;\n\n)",
        rf"(static int \w+_probe\(struct mipi_dsi_device \*dsi\)\s*\{{\n"
        rf"\tstruct device \*dev = &dsi->dev;\n"
        rf"\tstruct \w+ \*{re.escape(var)};\n"
        rf"\tint ret;\n)",
    ):
        new_text, n = re.subn(pat, r"\1" + alloc, text, count=1)
        if n:
            text = new_text
            inserted = True
            break
    if not inserted:
        sys.exit(1)

if INIT_RE.search(text) or "drm_panel_init" in text:
    sys.exit(1)

if text == original:
    sys.exit(0)

path.write_text(text)
print(f"  OK   drm_panel API: {path.name}", file=sys.stderr)
PY
}

bridge_72_fixup_qcom_serial_strncpy() {
    local f="$1"
    [[ -f "${f}" ]] || return 0
    grep -q 'strncpy(last6, serial + serial_len - 6, 6)' "${f}" || return 0

    python3 - "${f}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
new_text, n = re.subn(
    r"^([ \t]+)strncpy\(last6, serial \+ serial_len - 6, 6\);",
    r"\1memcpy(last6, serial + serial_len - 6, 6);",
    text,
    count=1,
    flags=re.M,
)
if n != 1:
    sys.exit(1)
path.write_text(new_text)
PY
    echo "  OK   $(basename "${f}"): strncpy → memcpy" >&2
}

bridge_72_fixup_ath12k_serial() {
    local src_dir="$1"
    bridge_72_fixup_qcom_serial_strncpy "${src_dir}/drivers/net/wireless/ath/ath12k/mac.c"
}

bridge_72_fixup_btqca_serial() {
    local src_dir="$1"
    bridge_72_fixup_qcom_serial_strncpy "${src_dir}/drivers/bluetooth/btqca.c"
}

bridge_72_fixup_hynitron_gpio() {
    local c="${1}/drivers/input/touchscreen/hynitron/hyn_core.c"
    local h="${1}/drivers/input/touchscreen/hynitron/hyn_core.h"
    [[ -f "${c}" ]] || return 0

    if [[ -f "${h}" ]] && grep -q 'linux/of_gpio.h' "${h}"; then
        sed -i 's|#include <linux/of_gpio.h>|#include <linux/gpio/consumer.h>|' "${h}"
        echo "  OK   hynitron: of_gpio.h → gpio/consumer.h" >&2
    fi

    if grep -q 'hyn_gpio_from_dt' "${c}" && ! grep -q 'of_get_named_gpio' "${c}"; then
        return 0
    fi

    python3 - "${c}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

helper = """
static int hyn_gpio_from_dt(struct device *dev, const char *con_id, int index)
{
\tstruct gpio_desc *desc;
\tint gpio;

\tdesc = gpiod_get_index(dev, con_id, index, GPIOD_ASIS);
\tif (IS_ERR(desc))
\t\treturn PTR_ERR(desc);
\tgpio = desc_to_gpio(desc);
\tgpiod_put(desc);
\treturn gpio;
}

"""

if "hyn_gpio_from_dt" not in text:
    anchor = "static int hyn_parse_dt(struct hyn_ts_data *ts_data)"
    if anchor not in text:
        sys.exit(1)
    text = text.replace(anchor, helper + anchor, 1)

text, n = re.subn(
    r"^([ \t]+)dt->reset_gpio = of_get_named_gpio\(np, \"reset-gpio\", 0\);\n"
    r"\1dt->irq_gpio = of_get_named_gpio\(np, \"irq-gpio\", 0\);",
    r'\1dt->reset_gpio = hyn_gpio_from_dt(dev, "reset", 0);\n'
    r'\1dt->irq_gpio = hyn_gpio_from_dt(dev, "irq", 0);',
    text,
    count=1,
    flags=re.M,
)
if n != 1 and "of_get_named_gpio" in text:
    sys.exit(1)

if "of_get_named_gpio" in text:
    sys.exit(1)

path.write_text(text)
PY
    echo "  OK   hynitron: of_get_named_gpio → gpiod compat" >&2
}

bridge_72_fixup_dts_duplicates() {
    local src_dir="$1"
    python3 - "${src_dir}" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
changed = False

sm8550 = root / "arch/arm64/boot/dts/qcom/sm8550.dtsi"
if sm8550.exists():
    text = sm8550.read_text()
    orig = text
    while text.count("uart15: serial@89c000") > 1:
        text = re.sub(
            r"\n\t\t\tuart15: serial@89c000 \{.*?\n\t\t\t\};",
            "",
            text,
            count=1,
            flags=re.S,
        )
    while text.count("qup_uart15_default: qup-uart15-default-state") > 1:
        text = re.sub(
            r"\n\t\t\tqup_uart15_default: qup-uart15-default-state \{.*?\n\t\t\t\};",
            "",
            text,
            count=1,
            flags=re.S,
        )
    if text != orig:
        sm8550.write_text(text)
        changed = True
        print("  OK   sm8550.dtsi: drop duplicate UART15 nodes", file=sys.stderr)

pmk = root / "arch/arm64/boot/dts/qcom/pmk8550.dtsi"
if pmk.exists():
    text = pmk.read_text()
    orig = text
    while text.count("pmk8550_pwm: pwm") > 1:
        text = re.sub(
            r"\n\t\tpmk8550_pwm: pwm \{.*?\n\t\t\};",
            "",
            text,
            count=1,
            flags=re.S,
        )
    if text != orig:
        pmk.write_text(text)
        changed = True
        print("  OK   pmk8550.dtsi: drop duplicate pwm node", file=sys.stderr)

old_glink = (
    "&remoteproc_adsp_glink {\n"
    "\tfastrpc {"
)
new_glink = (
    "&remoteproc_adsp {\n"
    "\tglink-edge {\n"
    "\t\tfastrpc {"
)
close_old = "\t};\n};"
close_new = "\t\t};\n\t};\n};"

for path in (
    root / "arch/arm64/boot/dts/qcom/qcs8550-ayn-common.dtsi",
    root / "arch/arm64/boot/dts/qcom/qcs8550-ayn-thor.dts",
):
    if not path.exists():
        continue
    text = path.read_text()
    if old_glink not in text:
        continue
    text = text.replace(old_glink, new_glink, 1)
    # Replace the fastrpc block's closing only for this overlay section.
    idx = text.find(new_glink)
    if idx >= 0:
        end = text.find(close_old, idx)
        if end >= 0:
            text = text[:end] + close_new + text[end + len(close_old) :]
    path.write_text(text)
    changed = True
    print(f"  OK   {path.name}: remoteproc_adsp_glink → remoteproc_adsp", file=sys.stderr)

sys.exit(0)
PY
}

bridge_72_fixup_ufs_qcom_post_change() {
    local f="$1/drivers/ufs/host/ufs-qcom.c"
    [[ -f "${f}" ]] || return 0
    grep -q 'ufs_qcom_link_startup_post_change' "${f}" || return 0
    grep -q 'qcom_qmp_ufs_ctrl_rx_linecfg' "${f}" || return 0
    [[ "$(grep -c 'case POST_CHANGE:' "${f}")" -le 1 ]] && return 0

    python3 - "${f}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

merged = re.sub(
    r"case POST_CHANGE:\n"
    r"\t\tufs_qcom_link_startup_post_change\(hba\);\n"
    r"\t\tbreak;\n"
    r"case POST_CHANGE:\n"
    r"(\t\tlinecfg_err = qcom_qmp_ufs_ctrl_rx_linecfg\(host->generic_phy, false\);\n"
    r"\t\tif \(linecfg_err && linecfg_err != -EOPNOTSUPP\)\n"
    r"\t\t\tdev_warn\(hba->dev, \"failed to disable RX LineCfg: %d\\n\",\n"
    r"\t\t\t\t linecfg_err\);\n)"
    r"\t\tbreak;",
    r"case POST_CHANGE:\n"
    r"\t\tufs_qcom_link_startup_post_change(hba);\n"
    r"\1"
    r"\t\tbreak;",
    text,
    count=1,
)
if merged == text or merged.count("case POST_CHANGE:") != 1:
    sys.exit(1)
path.write_text(merged)
PY
    echo "  OK   ufs-qcom: merge duplicate POST_CHANGE cases" >&2
}

bridge_72_fixup_compile_apis() {
    local src_dir="$1" panel f fixed=0 failed=0

    echo "==> linux-7.2.x: driver API fixups (compile)" >&2
    shopt -s nullglob
    for panel in "${src_dir}"/drivers/gpu/drm/panel/*.c; do
        if bridge_72_fixup_drm_panel_file "${panel}"; then
            fixed=$((fixed + 1))
        else
            if grep -qE 'drm_panel_init|devm_drm_panel_alloc' "${panel}" 2>/dev/null \
                && grep -q 'drm_panel_init' "${panel}" 2>/dev/null; then
                echo "  FAIL drm_panel API: $(basename "${panel}")" >&2
                failed=$((failed + 1))
            fi
        fi
    done
    shopt -u nullglob

    bridge_72_fixup_ath12k_serial "${src_dir}" || failed=$((failed + 1))
    bridge_72_fixup_btqca_serial "${src_dir}" || failed=$((failed + 1))
    bridge_72_fixup_hynitron_gpio "${src_dir}" || failed=$((failed + 1))
    bridge_72_fixup_ufs_qcom_post_change "${src_dir}" || true
    bridge_72_fixup_dts_duplicates "${src_dir}" || true

    [[ "${failed}" -eq 0 ]]
}

verify_sm8550_72_compile() {
    local src_dir="$1" ok=1 f

    echo "==> Verify linux-7.2.x compile fixups" >&2

    shopt -s nullglob
    for f in "${src_dir}"/drivers/gpu/drm/panel/panel-ar0*.c \
             "${src_dir}"/drivers/gpu/drm/panel/panel-boe-xm91080g.c \
             "${src_dir}"/drivers/gpu/drm/panel/panel-chipone-icna35xx.c \
             "${src_dir}"/drivers/gpu/drm/panel/panel-synaptics-td4328.c; do
        [[ -f "${f}" ]] || continue
        if grep -q 'drm_panel_init' "${f}"; then
            echo "  FAIL $(basename "${f}"): still uses drm_panel_init" >&2
            ok=0
        fi
    done
    shopt -u nullglob

    if grep -q 'strncpy(last6, serial + serial_len - 6, 6)' \
        "${src_dir}/drivers/net/wireless/ath/ath12k/mac.c" 2>/dev/null \
        "${src_dir}/drivers/bluetooth/btqca.c" 2>/dev/null; then
        echo "  FAIL qcom serial MAC/BT: strncpy still present" >&2
        ok=0
    fi

    if grep -q 'linux/of_gpio.h' \
        "${src_dir}/drivers/input/touchscreen/hynitron/hyn_core.h" 2>/dev/null; then
        echo "  FAIL hyn_core.h: still includes of_gpio.h" >&2
        ok=0
    fi
    if grep -q 'of_get_named_gpio\|\\"reset\\"' \
        "${src_dir}/drivers/input/touchscreen/hynitron/hyn_core.c" 2>/dev/null; then
        echo "  FAIL hyn_core.c: hynitron GPIO fixup incomplete" >&2
        ok=0
    fi

    [[ "${ok}" -eq 1 ]] && echo "  OK   ath12k + panels + hynitron 7.2 APIs" >&2

    if grep -q 'remoteproc_adsp_glink' \
        "${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-ayn-common.dtsi" 2>/dev/null \
        "${src_dir}/arch/arm64/boot/dts/qcom/qcs8550-ayn-thor.dts" 2>/dev/null; then
        echo "  FAIL DTS: obsolete remoteproc_adsp_glink reference" >&2
        ok=0
    fi
    if [[ "$(grep -c 'uart15: serial@89c000' "${src_dir}/arch/arm64/boot/dts/qcom/sm8550.dtsi" 2>/dev/null || echo 0)" -gt 1 ]]; then
        echo "  FAIL sm8550.dtsi: duplicate uart15 node" >&2
        ok=0
    fi

    [[ "${ok}" -eq 1 ]]
}

verify_sm8550_72_required() {
    local src_dir="$1" ok=1

    grep -q 'bool toggle_fifo_clk' "${src_dir}/drivers/mmc/host/sdhci-msm.c" 2>/dev/null || ok=0
    grep -q 'aw88166_of_match' "${src_dir}/sound/soc/codecs/aw88166.c" 2>/dev/null || ok=0
    grep -q 'ufshcd_relinking' "${src_dir}/drivers/ufs/core/ufshcd.c" 2>/dev/null || ok=0
    grep -q 'ufshcd_pm_drain_completions' "${src_dir}/drivers/ufs/core/ufshcd.c" 2>/dev/null || ok=0
    grep -q 'tsens_irq_wake_enabled' "${src_dir}/drivers/thermal/qcom/tsens.c" 2>/dev/null || ok=0
    [[ "${ok}" -eq 1 ]]
}
