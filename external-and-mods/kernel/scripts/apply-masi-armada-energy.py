#!/usr/bin/env python3
"""Idempotent Armada SM8550 energy/suspend helpers on linux-7.2.x.

Ports the subset that is compatible with MaSi deep (S2RAM) sleep:
PCIe L23 skip + suspend OPP, RPMH regulator-state-mem, TSENS lower-IRQ
mask, GENI UART IRQ mask, rsinput MCU quiesce + VDD drop,
dwc3 skip-phy (0522), sdhci-msm IRQ mask in runtime suspend (0521).

Does not enable interconnect QoS, fake-suspend, or s2idle-as-default.
"""
from __future__ import annotations

import sys
from pathlib import Path

CHANGED = 0


def patch_file(path: Path, mutator) -> bool:
    global CHANGED
    if not path.is_file():
        print(f"  MISS {path}", file=sys.stderr)
        return False
    orig = path.read_text()
    text, ok = mutator(orig)
    if not ok:
        print(f"  FAIL {path.name}", file=sys.stderr)
        return False
    if text != orig:
        path.write_text(text)
        CHANGED += 1
        print(f"  PATCH {path.name}", file=sys.stderr)
    else:
        print(f"  SKIP {path.name} (present)", file=sys.stderr)
    return True


def pcie_qcom(text: str) -> tuple[str, bool]:
    if "pp->skip_l23_ready = true" not in text:
        needle = "\tpp->ops = &qcom_pcie_dw_ops;\n\n"
        insert = (
            "\tpp->ops = &qcom_pcie_dw_ops;\n\n"
            "\t/* PARF_LTSSM is inaccessible after PME_Turn_Off on SM8550. */\n"
            "\tif (of_device_is_compatible(dev->of_node, \"qcom,pcie-sm8550\"))\n"
            "\t\tpp->skip_l23_ready = true;\n\n"
        )
        if needle not in text:
            return text, False
        text = text.replace(needle, insert, 1)

    if "qcom_pcie_set_suspend_opp" not in text:
        helper = '''
/*
 * Use the DT suspend OPP to retain the PCIe DDR/LLCC sleep-set votes
 * during s2idle. Suspend-to-RAM tears the link down and keeps dropping
 * the OPP.
 */
static int qcom_pcie_set_suspend_opp(struct qcom_pcie *pcie)
{
	struct device *dev = pcie->pci->dev;
	struct dev_pm_opp *opp;
	unsigned long freq;
	int ret;

	if (pm_suspend_target_state == PM_SUSPEND_MEM)
		return dev_pm_opp_set_opp(dev, NULL);

	freq = dev_pm_opp_get_suspend_opp_freq(dev);
	if (!freq)
		return dev_pm_opp_set_opp(dev, NULL);

	opp = dev_pm_opp_find_freq_exact(dev, freq, true);
	if (IS_ERR(opp))
		return PTR_ERR(opp);

	ret = dev_pm_opp_set_opp(dev, opp);
	dev_pm_opp_put(opp);

	return ret;
}

'''
        needle = "static int qcom_pcie_suspend_noirq(struct device *dev)\n"
        if needle not in text:
            return text, False
        text = text.replace(needle, helper + needle, 1)

        old1 = (
            "\t\tif (pcie->use_pm_opp)\n"
            "\t\t\tdev_pm_opp_set_opp(pcie->pci->dev, NULL);\n"
            "\t} else {\n"
        )
        new1 = (
            "\t\tif (pcie->use_pm_opp) {\n"
            "\t\t\tret = qcom_pcie_set_suspend_opp(pcie);\n"
            "\t\t\tif (ret)\n"
            "\t\t\t\tdev_err(dev, \"Failed to set suspend OPP: %d\\n\", ret);\n"
            "\t\t}\n"
            "\t} else {\n"
        )
        old2 = (
            "\t\t\tif (pcie->use_pm_opp)\n"
            "\t\t\t\tdev_pm_opp_set_opp(pcie->pci->dev, NULL);\n"
        )
        new2 = (
            "\t\t\tif (pcie->use_pm_opp) {\n"
            "\t\t\t\tret = qcom_pcie_set_suspend_opp(pcie);\n"
            "\t\t\t\tif (ret)\n"
            "\t\t\t\t\tdev_err(dev, \"Failed to set suspend OPP: %d\\n\",\n"
            "\t\t\t\t\t\tret);\n"
            "\t\t\t}\n"
        )
        if old1 not in text or old2 not in text:
            return text, False
        text = text.replace(old1, new1, 1)
        text = text.replace(old2, new2, 1)

    # 1056 caused a black-screen hang (deinit without PME while the
    # link was still up after userspace PCI remove). Strip it.
    if "masi_s2ram_force_pcie_teardown" in text:
        old_1056 = """	ret = dw_pcie_suspend_noirq(pcie->pci);
	if (ret)
		return ret;

	/*
	 * dw_pcie_suspend_noirq() returns success without deinit when
	 * d3cold is not possible (root port still D0, or ath12k skipped
	 * power_down). That leaves WCN WLAN_EN high and the SM8550 PCIe
	 * PHY up — local heat on the upper-right that is *not* there
	 * while the radio is in use. Force host + pwrseq teardown on
	 * S2RAM (1056).
	 */
	if (!pcie->pci->suspended && pm_suspend_target_state == PM_SUSPEND_MEM) {
		/* 1056 masi_s2ram_force_pcie_teardown */
		pcie->pci->pp.skip_pwrctrl_off = false;
		if (pcie->pci->pp.ops && pcie->pci->pp.ops->deinit)
			pcie->pci->pp.ops->deinit(&pcie->pci->pp);
		pcie->pci->suspended = true;
	}

	if (pcie->pci->suspended) {
"""
        new_1056 = """	ret = dw_pcie_suspend_noirq(pcie->pci);
	if (ret)
		return ret;

	if (pcie->pci->suspended) {
"""
        if old_1056 not in text:
            return text, False
        text = text.replace(old_1056, new_1056, 1)

    return text, (
        "pp->skip_l23_ready = true" in text
        and "qcom_pcie_set_suspend_opp" in text
        and "masi_s2ram_force_pcie_teardown" not in text
    )


def sm8550_dtsi(text: str) -> tuple[str, bool]:
    if "opp-suspend-1" in text and "opp-suspend;" in text:
        return text, True
    needle = (
        "\t\t\t\topp-16000000-3 {\n"
        "\t\t\t\t\topp-hz = /bits/ 64 <16000000>;\n"
        "\t\t\t\t\trequired-opps = <&rpmhpd_opp_nom>;\n"
        "\t\t\t\t\topp-peak-kBps = <1969000 1>;\n"
        "\t\t\t\t\topp-level = <3>;\n"
        "\t\t\t\t};\n"
        "\t\t\t};\n"
    )
    insert = (
        "\t\t\t\topp-16000000-3 {\n"
        "\t\t\t\t\topp-hz = /bits/ 64 <16000000>;\n"
        "\t\t\t\t\trequired-opps = <&rpmhpd_opp_nom>;\n"
        "\t\t\t\t\topp-peak-kBps = <1969000 1>;\n"
        "\t\t\t\t\topp-level = <3>;\n"
        "\t\t\t\t};\n"
        "\n"
        "\t\t\t\t/*\n"
        "\t\t\t\t * Suspend-only DDR/LLCC floor for the RPMh sleep\n"
        "\t\t\t\t * set. opp-hz is synthetic and opp-level is\n"
        "\t\t\t\t * absent, so link-speed matching cannot select it.\n"
        "\t\t\t\t */\n"
        "\t\t\t\topp-suspend-1 {\n"
        "\t\t\t\t\topp-hz = /bits/ 64 <1>;\n"
        "\t\t\t\t\trequired-opps = <&rpmhpd_opp_min_svs>;\n"
        "\t\t\t\t\topp-peak-kBps = <1000 1>;\n"
        "\t\t\t\t\topp-suspend;\n"
        "\t\t\t\t};\n"
        "\t\t\t};\n"
    )
    # First opp-16000000-3 is pcie0; pcie1 has a similar table later.
    if needle not in text:
        return text, False
    text = text.replace(needle, insert, 1)
    return text, "opp-suspend-1" in text


def rpmh_regulator(text: str) -> tuple[str, bool]:
    if "rpmh_regulator_set_suspend_enable" in text:
        return text, True

    old_send = """	else
		ret = rpmh_write_async(vreg->dev, RPMH_ACTIVE_ONLY_STATE, cmd,
					1);

	return ret;
}"""
    new_send = """	else
		ret = rpmh_write_async(vreg->dev, RPMH_ACTIVE_ONLY_STATE, cmd,
					1);
	if (ret < 0)
		return ret;

	/*
	 * Mirror every active-set request into the SLEEP set cache.  rpmh
	 * prunes cache entries whose sleep and wake values are equal, so this
	 * changes nothing in the sleep/wake TCSes by itself until a suspend
	 * vote is armed.
	 */
	return rpmh_write(vreg->dev, RPMH_SLEEP_STATE, cmd, 1);
}"""
    if old_send not in text:
        return text, False
    text = text.replace(old_send, new_send, 1)

    helpers = r'''
/**
 * rpmh_regulator_send_sleep_wake_request() - cache a SLEEP set vote together
 *		with the matching WAKE set restore value for one register of
 *		an RPMh regulator resource
 */
static int rpmh_regulator_send_sleep_wake_request(struct rpmh_vreg *vreg,
				u32 reg_offset, u32 sleep_val, u32 wake_val)
{
	struct tcs_cmd cmd = {
		.addr = vreg->addr + reg_offset,
		.data = sleep_val,
	};
	int ret;

	ret = rpmh_write(vreg->dev, RPMH_SLEEP_STATE, &cmd, 1);
	if (ret < 0)
		return ret;

	cmd.data = wake_val;

	return rpmh_write(vreg->dev, RPMH_WAKE_ONLY_STATE, &cmd, 1);
}

static int rpmh_regulator_set_suspend_enable(struct regulator_dev *rdev)
{
	struct rpmh_vreg *vreg = rdev_get_drvdata(rdev);

	return rpmh_regulator_send_sleep_wake_request(vreg,
			RPMH_REGULATOR_REG_ENABLE, 1, vreg->enabled == 1);
}

static int rpmh_regulator_set_suspend_disable(struct regulator_dev *rdev)
{
	struct rpmh_vreg *vreg = rdev_get_drvdata(rdev);

	return rpmh_regulator_send_sleep_wake_request(vreg,
			RPMH_REGULATOR_REG_ENABLE, 0, vreg->enabled == 1);
}

static int rpmh_regulator_vrm_active_pmic_mode(struct rpmh_vreg *vreg)
{
	if (vreg->bypassed)
		return vreg->hw_data->pmic_bypass_mode;

	if (vreg->mode == REGULATOR_MODE_INVALID)
		return -EINVAL;

	return vreg->hw_data->pmic_mode_map[vreg->mode];
}

static int rpmh_regulator_vrm_set_suspend_mode(struct regulator_dev *rdev,
					unsigned int mode)
{
	struct rpmh_vreg *vreg = rdev_get_drvdata(rdev);
	int sleep_mode, wake_mode;

	if (mode > REGULATOR_MODE_STANDBY)
		return -EINVAL;

	sleep_mode = vreg->hw_data->pmic_mode_map[mode];
	if (sleep_mode < 0)
		return sleep_mode;

	wake_mode = rpmh_regulator_vrm_active_pmic_mode(vreg);
	if (wake_mode < 0)
		wake_mode = sleep_mode;

	if (vreg->bypassed)
		sleep_mode = wake_mode;

	return rpmh_regulator_send_sleep_wake_request(vreg,
			RPMH_REGULATOR_REG_VRM_MODE, sleep_mode, wake_mode);
}

static int rpmh_regulator_resume(struct regulator_dev *rdev)
{
	struct rpmh_vreg *vreg = rdev_get_drvdata(rdev);
	int mode;
	int ret;

	ret = rpmh_regulator_send_sleep_wake_request(vreg,
			RPMH_REGULATOR_REG_ENABLE,
			vreg->enabled == 1, vreg->enabled == 1);
	if (ret < 0)
		return ret;

	if (vreg->hw_data->regulator_type != VRM)
		return 0;

	mode = rpmh_regulator_vrm_active_pmic_mode(vreg);
	if (mode < 0)
		return 0;

	return rpmh_regulator_send_sleep_wake_request(vreg,
			RPMH_REGULATOR_REG_VRM_MODE, mode, mode);
}

'''
    anchor = (
        "/**\n"
        " * rpmh_regulator_vrm_get_optimum_mode() - get the mode based on the  load\n"
    )
    if anchor not in text:
        return text, False
    text = text.replace(anchor, helpers + anchor, 1)

    ops_extra = (
        "\t.set_suspend_enable	= rpmh_regulator_set_suspend_enable,\n"
        "\t.set_suspend_disable	= rpmh_regulator_set_suspend_disable,\n"
        "\t.set_suspend_mode	= rpmh_regulator_vrm_set_suspend_mode,\n"
        "\t.resume			= rpmh_regulator_resume,\n"
    )
    xob_extra = (
        "\t.set_suspend_enable	= rpmh_regulator_set_suspend_enable,\n"
        "\t.set_suspend_disable	= rpmh_regulator_set_suspend_disable,\n"
        "\t.resume			= rpmh_regulator_resume,\n"
    )

    def add_ops(block_start: str, extra: str, before_close: str = "};") -> bool:
        nonlocal text
        idx = text.find(block_start)
        if idx < 0:
            return False
        end = text.find("\n};", idx)
        if end < 0:
            return False
        chunk = text[idx:end]
        if "set_suspend_enable" in chunk:
            return True
        text = text[:end] + "\n" + extra.rstrip("\n") + text[end:]
        return True

    if not add_ops("static const struct regulator_ops rpmh_regulator_vrm_ops = {", ops_extra):
        return text, False
    if not add_ops("static const struct regulator_ops rpmh_regulator_vrm_drms_ops = {", ops_extra):
        return text, False
    if not add_ops("static const struct regulator_ops rpmh_regulator_vrm_bypass_ops = {", ops_extra):
        return text, False
    if not add_ops("static const struct regulator_ops rpmh_regulator_xob_ops = {", xob_extra):
        return text, False

    return text, "rpmh_regulator_set_suspend_enable" in text


def tsens(text: str) -> tuple[str, bool]:
    if "static int __maybe_unused tsens_prepare(" in text:
        return text, True
    prepare = '''
static int __maybe_unused tsens_prepare(struct device *dev)
{
	struct tsens_priv *priv = dev_get_drvdata(dev);
	unsigned int i;

	if (tsens_version(priv) < VER_0_1)
		return 0;

	/*
	 * Thermal zones are already suspended here. Falling temperatures
	 * cross lower trips and the level IRQ cannot be cleared, aborting
	 * suspend. Mask LOWER; UPPER stays armed. The first post-resume
	 * tsens_set_trips() re-enables it.
	 */
	for (i = 0; i < priv->num_sensors; i++)
		tsens_set_interrupt(priv, priv->sensor[i].hw_id, LOWER, false);

	return 0;
}

'''
    needle = "static int  __maybe_unused tsens_suspend(struct device *dev)\n"
    alt = "static int __maybe_unused tsens_suspend(struct device *dev)\n"
    if needle in text:
        text = text.replace(needle, prepare + needle, 1)
    elif alt in text:
        text = text.replace(alt, prepare + alt, 1)
    else:
        return text, False

    old_pm = "static SIMPLE_DEV_PM_OPS(tsens_pm_ops, tsens_suspend, tsens_resume);"
    new_pm = (
        "static const struct dev_pm_ops tsens_pm_ops = {\n"
        "\t.prepare = pm_sleep_ptr(tsens_prepare),\n"
        "\tSET_SYSTEM_SLEEP_PM_OPS(tsens_suspend, tsens_resume)\n"
        "};"
    )
    if old_pm not in text:
        return text, False
    text = text.replace(old_pm, new_pm, 1)
    return text, "tsens_prepare" in text


def geni_serial(text: str) -> tuple[str, bool]:
    if "Balance the disable_irq() taken in qcom_geni_serial_suspend" in text:
        return text, True
    old_susp = '''static int qcom_geni_serial_suspend(struct device *dev)
{
	struct qcom_geni_serial_port *port = dev_get_drvdata(dev);
	struct uart_port *uport = &port->uport;
	struct qcom_geni_private_data *private_data = uport->private_data;

	/*
	 * This is done so we can hit the lowest possible state in suspend
	 * even with no_console_suspend
	 */
'''
    new_susp = '''static int qcom_geni_serial_suspend(struct device *dev)
{
	struct qcom_geni_serial_port *port = dev_get_drvdata(dev);
	struct uart_port *uport = &port->uport;
	struct qcom_geni_private_data *private_data = uport->private_data;

	/*
	 * A peer that keeps streaming into a non-console geni UART (gamepad
	 * MCU) storms the RX IRQ once uart_suspend_port() sets
	 * uport->suspended. Mask it here while the ISR still acks the line.
	 */
	if (!uart_console(uport))
		disable_irq(uport->irq);

	/*
	 * This is done so we can hit the lowest possible state in suspend
	 * even with no_console_suspend
	 */
'''
    if old_susp not in text:
        return text, False
    text = text.replace(old_susp, new_susp, 1)

    old_res = (
        "\tret = uart_resume_port(private_data->drv, uport);\n"
        "\tif (uart_console(uport)) {\n"
    )
    new_res = (
        "\tret = uart_resume_port(private_data->drv, uport);\n"
        "\t/* Balance the disable_irq() taken in qcom_geni_serial_suspend(). */\n"
        "\tif (!uart_console(uport))\n"
        "\t\tenable_irq(uport->irq);\n"
        "\tif (uart_console(uport)) {\n"
    )
    if old_res not in text:
        return text, False
    text = text.replace(old_res, new_res, 1)
    return text, True


def rsinput(text: str) -> tuple[str, bool]:
    if "bool vdd_off;" in text and "drv->vdd_off = true" in text:
        return text, True

    if "bool vdd_off;" not in text:
        old = "\tstruct regulator *vdd;\n    struct gpio_desc *boot_gpio;"
        new = "\tstruct regulator *vdd;\n    bool vdd_off;\n    struct gpio_desc *boot_gpio;"
        if old not in text:
            old = "    struct regulator *vdd;\n    struct gpio_desc *boot_gpio;"
            new = "    struct regulator *vdd;\n    bool vdd_off;\n    struct gpio_desc *boot_gpio;"
        if old not in text:
            return text, False
        text = text.replace(old, new, 1)

    old_rm = "    regulator_disable(drv->vdd);\n}"
    new_rm = "    if (!drv->vdd_off)\n        regulator_disable(drv->vdd);\n}"
    if "if (!drv->vdd_off)" not in text:
        if old_rm not in text:
            old_rm = "\tregulator_disable(drv->vdd);\n}"
            new_rm = "\tif (!drv->vdd_off)\n\t\tregulator_disable(drv->vdd);\n}"
        if old_rm not in text:
            return text, False
        text = text.replace(old_rm, new_rm, 1)

    old_susp = '''static int rsinput_suspend(struct device *dev)
{
	struct rsinput_driver *drv = dev_get_drvdata(dev);

	rsinput_rumble_cancel(NULL);
	rsinput_report_sticks_centered(drv);
	return 0;
}
'''
    new_susp = '''static int rsinput_suspend(struct device *dev)
{
	struct rsinput_driver *drv = dev_get_drvdata(dev);
	int error;

	rsinput_rumble_cancel(NULL);
	rsinput_report_sticks_centered(drv);

	/*
	 * Stop continuous MCU reports before the UART suspends; otherwise the
	 * UART IRQ can be disabled as spurious. rsinput_resume() powers the
	 * MCU back on through rsinput_init_commands().
	 */
	if (drv->enable_gpio)
		gpiod_set_value_cansleep(drv->enable_gpio, 0);

	if (drv->reset_gpio)
		gpiod_set_value_cansleep(drv->reset_gpio, 0);

	if (!drv->vdd_off) {
		error = regulator_disable(drv->vdd);
		if (error) {
			dev_err(dev, "Failed to disable MCU supply: %d\\n", error);
			rsinput_init_commands(drv);
			return error;
		}
		drv->vdd_off = true;
	}

	return 0;
}
'''
    if old_susp not in text:
        return text, False
    text = text.replace(old_susp, new_susp, 1)

    old_res = '''static int rsinput_resume(struct device *dev)
{
	struct rsinput_driver *drv = dev_get_drvdata(dev);
	int error;

	if (!drv)
		return 0;

	/* MCU often needs a beat after rails return before UART commands stick. */
	msleep(80);
'''
    new_res = '''static int rsinput_resume(struct device *dev)
{
	struct rsinput_driver *drv = dev_get_drvdata(dev);
	int error;

	if (!drv)
		return 0;

	if (drv->vdd_off) {
		error = regulator_enable(drv->vdd);
		if (error) {
			dev_err(dev, "Failed to enable MCU supply: %d\\n", error);
			return error;
		}
		drv->vdd_off = false;
	}

	/* MCU often needs a beat after rails return before UART commands stick. */
	msleep(80);
'''
    if old_res not in text:
        return text, False
    text = text.replace(old_res, new_res, 1)
    return text, "drv->vdd_off = true" in text


def dwc3_qcom(text: str) -> tuple[str, bool]:
    """Armada 0522 / lore 20260723: HCD core extra phy_init pins CX (right-side heat)."""
    if "dwc3_qcom_set_swnode" in text and "xhci-skip-phy-init-quirk" in text:
        return text, True

    if "#include <linux/property.h>" not in text:
        needle = "#include <linux/usb.h>\n"
        if needle not in text:
            return text, False
        text = text.replace(needle, needle + "#include <linux/property.h>\n", 1)

    helper = '''
static int dwc3_qcom_set_swnode(struct device *dev)
{
	const struct property_entry props[] = {
		PROPERTY_ENTRY_BOOL("xhci-skip-phy-init-quirk"),
		{}
	};

	return device_create_managed_software_node(dev, props, NULL);
}

'''
    anchor = "static void dwc3_qcom_select_utmi_clk(struct dwc3_qcom *qcom)\n"
    if helper.strip() not in text:
        if anchor not in text:
            return text, False
        text = text.replace(anchor, helper + anchor, 1)

    call = '''	if (ignore_pipe_clk)
		dwc3_qcom_select_utmi_clk(qcom);

	ret = dwc3_qcom_set_swnode(dev);
	if (ret)
		goto clk_disable;

	qcom->mode = usb_get_dr_mode(dev);
'''
    old_call = '''	if (ignore_pipe_clk)
		dwc3_qcom_select_utmi_clk(qcom);

	qcom->mode = usb_get_dr_mode(dev);
'''
    if "dwc3_qcom_set_swnode(dev)" not in text:
        if old_call not in text:
            return text, False
        text = text.replace(old_call, call, 1)

    return text, "xhci-skip-phy-init-quirk" in text and "dwc3_qcom_set_swnode(dev)" in text


def sdhci_msm(text: str) -> tuple[str, bool]:
    """Armada 0521: mask SDHCI IRQs while runtime suspended (mmc0 storm / CX)."""
    if "host->ier & SDHCI_INT_CARD_INT" in text and "synchronize_hardirq(host->irq)" in text:
        return text, True

    old_susp = '''	spin_lock_irqsave(&host->lock, flags);
	host->runtime_suspended = true;
	spin_unlock_irqrestore(&host->lock, flags);

	/* Drop the performance vote */
'''
    new_susp = '''	spin_lock_irqsave(&host->lock, flags);
	host->runtime_suspended = true;
	/*
	 * SDCC apps clk parks on always-on bi_tcxo, so the controller
	 * keeps asserting status IRQs while runtime suspended (Odin 2:
	 * 15-50 irq/s, armada#274). sdhci_irq() returns IRQ_NONE and
	 * never acks. Mask enables; keep SDHCI_INT_CARD_INT for SDIO.
	 */
	sdhci_writel(host, host->ier & SDHCI_INT_CARD_INT, SDHCI_SIGNAL_ENABLE);
	sdhci_writel(host, host->ier & SDHCI_INT_CARD_INT, SDHCI_INT_ENABLE);
	spin_unlock_irqrestore(&host->lock, flags);

	synchronize_hardirq(host->irq);

	/* Drop the performance vote */
'''
    if old_susp not in text:
        return text, False
    text = text.replace(old_susp, new_susp, 1)

    old_res = '''	spin_lock_irqsave(&host->lock, flags);
	host->runtime_suspended = false;
	spin_unlock_irqrestore(&host->lock, flags);
'''
    new_res = '''	spin_lock_irqsave(&host->lock, flags);
	sdhci_writel(host, host->ier, SDHCI_SIGNAL_ENABLE);
	sdhci_writel(host, host->ier, SDHCI_INT_ENABLE);
	host->runtime_suspended = false;
	spin_unlock_irqrestore(&host->lock, flags);
'''
    # Only the runtime_resume copy: last occurrence is the runtime path.
    if old_res not in text:
        return text, False
    idx = text.rfind(old_res)
    text = text[:idx] + new_res + text[idx + len(old_res):]
    return text, "host->ier & SDHCI_INT_CARD_INT" in text


def present(src: Path) -> bool:
    checks = [
        (src / "drivers/pci/controller/dwc/pcie-qcom.c", "pp->skip_l23_ready = true"),
        (src / "drivers/pci/controller/dwc/pcie-qcom.c", "qcom_pcie_set_suspend_opp"),
        (src / "arch/arm64/boot/dts/qcom/sm8550.dtsi", "opp-suspend-1"),
        (src / "drivers/regulator/qcom-rpmh-regulator.c", "rpmh_regulator_set_suspend_enable"),
        (src / "drivers/thermal/qcom/tsens.c", "tsens_prepare"),
        (src / "drivers/tty/serial/qcom_geni_serial.c",
         "Balance the disable_irq() taken in qcom_geni_serial_suspend"),
        (src / "drivers/input/joystick/rsinput.c", "drv->vdd_off = true"),
        (src / "drivers/usb/dwc3/dwc3-qcom.c", "xhci-skip-phy-init-quirk"),
        (src / "drivers/mmc/host/sdhci-msm.c", "host->ier & SDHCI_INT_CARD_INT"),
    ]
    return all(p.is_file() and marker in p.read_text() for p, marker in checks)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: apply-masi-armada-energy.py SRC_DIR", file=sys.stderr)
        return 2
    src = Path(sys.argv[1])
    jobs = [
        (src / "drivers/pci/controller/dwc/pcie-qcom.c", pcie_qcom),
        (src / "arch/arm64/boot/dts/qcom/sm8550.dtsi", sm8550_dtsi),
        (src / "drivers/regulator/qcom-rpmh-regulator.c", rpmh_regulator),
        (src / "drivers/thermal/qcom/tsens.c", tsens),
        (src / "drivers/tty/serial/qcom_geni_serial.c", geni_serial),
        (src / "drivers/input/joystick/rsinput.c", rsinput),
        (src / "drivers/usb/dwc3/dwc3-qcom.c", dwc3_qcom),
        (src / "drivers/mmc/host/sdhci-msm.c", sdhci_msm),
    ]
    ok = True
    for path, fn in jobs:
        if not patch_file(path, fn):
            ok = False
    if not ok:
        return 1
    if not present(src):
        print("  FAIL energy stack verify", file=sys.stderr)
        return 1
    print("  OK   Armada SM8550 energy stack", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
