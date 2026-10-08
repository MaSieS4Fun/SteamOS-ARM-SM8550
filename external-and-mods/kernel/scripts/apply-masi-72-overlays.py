#!/usr/bin/env python3
"""linux-7.2.x overlays that GNU patch cannot apply on live Armbian sm8550-7.2.

Covers:
  rsinput 1032/1052  — Armbian 7.2 abs-params / rumble layout
  haptics global_stop — Armbian 1005 uses chip->global_ff_lock, not MaSi mutex
  ath12k 1040 + MHI 1041–1043 — malformed hunk counts / empty 1043
  ath12k 1055 — force WCN7850 power_down on S2RAM (skip only when HW OFF)
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def _write_if_changed(path: Path, orig: str, text: str) -> bool:
    if text == orig:
        return True
    path.write_text(text)
    return True


def apply_rsinput(src: Path) -> bool:
    path = src / "drivers/input/joystick/rsinput.c"
    if not path.is_file():
        print("  MISS rsinput.c", file=sys.stderr)
        return False
    text = orig = path.read_text()

    if '#include <linux/delay.h>' not in text:
        text = text.replace("#include <linux/module.h>\n",
                            "#include <linux/module.h>\n#include <linux/delay.h>\n#include <linux/pm.h>\n",
                            1)
    elif '#include <linux/pm.h>' not in text:
        text = text.replace("#include <linux/delay.h>\n",
                            "#include <linux/delay.h>\n#include <linux/pm.h>\n",
                            1)

    if "bool vdd_off;" not in text:
        for old, new in (
            ("\tstruct regulator *vdd;\n    struct gpio_desc *boot_gpio;",
             "\tstruct regulator *vdd;\n    bool vdd_off;\n    struct gpio_desc *boot_gpio;"),
            ("    struct regulator *vdd;\n    struct gpio_desc *boot_gpio;",
             "    struct regulator *vdd;\n    bool vdd_off;\n    struct gpio_desc *boot_gpio;"),
            ("\tstruct regulator *vdd;\n\tstruct gpio_desc *boot_gpio;",
             "\tstruct regulator *vdd;\n\tbool vdd_off;\n\tstruct gpio_desc *boot_gpio;"),
        ):
            if old in text:
                text = text.replace(old, new, 1)
                break
        else:
            print("  FAIL rsinput: no vdd field to attach vdd_off", file=sys.stderr)
            return False

    if "if (!drv->vdd_off)" not in text:
        for old, new in (
            ("    regulator_disable(drv->vdd);\n}",
             "    if (!drv->vdd_off)\n        regulator_disable(drv->vdd);\n}"),
            ("\tregulator_disable(drv->vdd);\n}",
             "\tif (!drv->vdd_off)\n\t\tregulator_disable(drv->vdd);\n}"),
        ):
            if old in text:
                text = text.replace(old, new, 1)
                break

    # Stick rest deadzone (Armbian 7.2: per-axis INT_SIGN in probe + update_params).
    text = re.sub(
        r'(input_set_abs_params\(drv->input, ABS_(?:X|Y|RX|RY),[\s\S]*?),\s*0,\s*0\);',
        r'\1, 24, 96);',
        text,
    )

    if "rsinput_rumble_cancel(" not in text:
        stub = """
static void rsinput_rumble_cancel(void *unused)
{
	(void)unused;
"""
        if "rumble_work" in text:
            stub += "\tcancel_work_sync(&rumble_work);\n"
        stub += "}\n\n"
        marker = "static const struct of_device_id rsinput_of_match[]"
        if marker not in text:
            print("  FAIL rsinput: no of_match to hang rumble_cancel", file=sys.stderr)
            return False
        text = text.replace(marker, stub + marker, 1)

    if "rsinput_report_sticks_centered" not in text:
        block = r'''
static void rsinput_report_sticks_centered(struct rsinput_driver *drv)
{
	if (!drv || !drv->input)
		return;
	input_report_abs(drv->input, ABS_X, 0);
	input_report_abs(drv->input, ABS_Y, 0);
	input_report_abs(drv->input, ABS_RX, 0);
	input_report_abs(drv->input, ABS_RY, 0);
	input_report_abs(drv->input, ABS_Z, 0);
	input_report_abs(drv->input, ABS_RZ, 0);
	input_sync(drv->input);
}

static int rsinput_suspend(struct device *dev)
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
			dev_err(dev, "Failed to disable MCU supply: %d\n", error);
			rsinput_init_commands(drv);
			return error;
		}
		drv->vdd_off = true;
	}

	return 0;
}

static int rsinput_resume(struct device *dev)
{
	struct rsinput_driver *drv = dev_get_drvdata(dev);
	int error;

	if (!drv)
		return 0;

	if (drv->vdd_off) {
		error = regulator_enable(drv->vdd);
		if (error) {
			dev_err(dev, "Failed to enable MCU supply: %d\n", error);
			return error;
		}
		drv->vdd_off = false;
	}

	/* MCU often needs a beat after rails return before UART commands stick. */
	msleep(80);
	error = rsinput_init_commands(drv);
	if (error)
		dev_warn(dev, "rsinput resume init failed: %d\n", error);

	rsinput_report_sticks_centered(drv);
	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(rsinput_pm_ops, rsinput_suspend, rsinput_resume);

'''
        marker = "static const struct of_device_id rsinput_of_match[]"
        text = text.replace(marker, block + marker, 1)
    elif "drv->vdd_off = true" not in text:
        old = """static int rsinput_suspend(struct device *dev)
{
	struct rsinput_driver *drv = dev_get_drvdata(dev);

	rsinput_rumble_cancel(NULL);
	rsinput_report_sticks_centered(drv);
	return 0;
}
"""
        new = """static int rsinput_suspend(struct device *dev)
{
	struct rsinput_driver *drv = dev_get_drvdata(dev);
	int error;

	rsinput_rumble_cancel(NULL);
	rsinput_report_sticks_centered(drv);

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
"""
        if old not in text:
            print("  FAIL rsinput: suspend present but cannot add MCU quiesce", file=sys.stderr)
            return False
        text = text.replace(old, new, 1)
        old_res = """	if (!drv)
		return 0;

	/* MCU often needs a beat after rails return before UART commands stick. */
	msleep(80);
"""
        new_res = """	if (!drv)
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
"""
        if old_res not in text:
            print("  FAIL rsinput: resume cannot enable VDD", file=sys.stderr)
            return False
        text = text.replace(old_res, new_res, 1)

    if "pm_ptr(&rsinput_pm_ops)" not in text:
        old = """        .name = "rsinput",
        .of_match_table = rsinput_of_match,"""
        new = """        .name = "rsinput",
        .pm = pm_ptr(&rsinput_pm_ops),
        .of_match_table = rsinput_of_match,"""
        if old not in text:
            old = """\t\t.name = "rsinput",
\t\t.of_match_table = rsinput_of_match,"""
            new = """\t\t.name = "rsinput",
\t\t.pm = pm_ptr(&rsinput_pm_ops),
\t\t.of_match_table = rsinput_of_match,"""
        if old not in text:
            print("  FAIL rsinput: cannot attach pm_ops", file=sys.stderr)
            return False
        text = text.replace(old, new, 1)

    ok = (
        "rsinput_report_sticks_centered" in text
        and "DEFINE_SIMPLE_DEV_PM_OPS(rsinput_pm_ops" in text
        and "pm_ptr(&rsinput_pm_ops)" in text
        and "drv->vdd_off = true" in text
    )
    if not ok:
        print("  FAIL rsinput: overlay incomplete", file=sys.stderr)
        return False
    if text == orig:
        print("  OK   rsinput suspend/resume + MCU VDD drop (present)", file=sys.stderr)
        return True
    _write_if_changed(path, orig, text)
    print("  OK   rsinput suspend/resume + MCU VDD drop (1032/1052)", file=sys.stderr)
    return True


def apply_haptics_stop(src: Path) -> bool:
    path = src / "drivers/input/misc/qcom-hv-haptics.c"
    if not path.is_file():
        return True
    text = orig = path.read_text()
    if "EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_stop)" in text:
        print("  OK   haptics global_stop (present)", file=sys.stderr)
        return True

    if "MODULE_DESCRIPTION(" not in text:
        print("  FAIL haptics: no MODULE_DESCRIPTION", file=sys.stderr)
        return False

    if "global_playback_work" in text and "global_ff_lock" in text:
        stop = '''
int qcom_spmi_haptics_global_stop(void)
{
	struct haptics_chip *chip = READ_ONCE(global_haptics);

	if (!chip)
		return -ENODEV;

	cancel_work_sync(&chip->global_playback_work);
	cancel_delayed_work_sync(&chip->stop_work);
	mutex_lock(&chip->global_ff_lock);
	if (chip->chip_is_playing)
		haptics_enable_play(chip, false);
	chip->chip_effect_loaded = false;
	mutex_unlock(&chip->global_ff_lock);
	return 0;
}
EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_stop);

'''
    else:
        if "static DEFINE_MUTEX(global_ff_mutex);" not in text:
            text = text.replace(
                "static struct haptics_chip *global_haptics;",
                "static struct haptics_chip *global_haptics;\nstatic DEFINE_MUTEX(global_ff_mutex);",
                1,
            )
        stop = '''
int qcom_spmi_haptics_global_stop(void)
{
	struct haptics_play_info *play;

	if (!global_haptics)
		return -ENODEV;

	play = &global_haptics->play;
	mutex_lock(&global_ff_mutex);
	if (!global_haptics->chip_is_playing) {
		global_haptics->chip_effect_loaded = false;
		mutex_unlock(&global_ff_mutex);
		return 0;
	}
	mutex_lock(&play->lock);
	cancel_delayed_work_sync(&global_haptics->stop_work);
	haptics_enable_play(global_haptics, false);
	global_haptics->chip_effect_loaded = false;
	mutex_unlock(&play->lock);
	mutex_unlock(&global_ff_mutex);
	return 0;
}
EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_stop);

'''

    idx = text.rfind("MODULE_DESCRIPTION(")
    text = text[:idx] + stop + text[idx:]
    if "EXPORT_SYMBOL_GPL(qcom_spmi_haptics_global_stop)" not in text:
        return False
    _write_if_changed(path, orig, text)
    print("  OK   haptics global_stop export", file=sys.stderr)
    return True


def apply_ath12k_aspm(src: Path) -> bool:
    pci = src / "drivers/net/wireless/ath/ath12k/pci.c"
    wifi7 = src / "drivers/net/wireless/ath/ath12k/wifi7/mhi.c"
    if not pci.is_file():
        return True
    text = orig = pci.read_text()
    if "pci_upstream_bridge(ab_pci->pdev)" not in text:
        old = """	/* disable L0s and L1 */
	pcie_capability_clear_word(ab_pci->pdev, PCI_EXP_LNKCTL,
				   PCI_EXP_LNKCTL_ASPMC);

	set_bit(ATH12K_PCI_ASPM_RESTORE, &ab_pci->flags);
"""
        new = """	/* disable L0s and L1 */
	pcie_capability_clear_word(ab_pci->pdev, PCI_EXP_LNKCTL,
				   PCI_EXP_LNKCTL_ASPMC);

	/* Endpoint-only ASPM off is not enough on SM8550: the QCOM root
	 * port can still enter L1 and WCN7850 hangs after
	 * "mhi Power on setup success" (no wlan).
	 */
	{
		struct pci_dev *bridge = pci_upstream_bridge(ab_pci->pdev);

		if (bridge) {
			pcie_capability_clear_word(bridge, PCI_EXP_LNKCTL,
						   PCI_EXP_LNKCTL_ASPMC);
			ath12k_info(ab, "PCI ASPM L0s/L1 cleared on %s and bridge %s\\n",
				    pci_name(ab_pci->pdev), pci_name(bridge));
		}
	}

	set_bit(ATH12K_PCI_ASPM_RESTORE, &ab_pci->flags);
"""
        if old not in text:
            print("  FAIL ath12k pci ASPM parent-port", file=sys.stderr)
            return False
        text = text.replace(old, new, 1)
        _write_if_changed(pci, orig, text)

    if wifi7.is_file():
        w = orig_w = wifi7.read_text()
        w2 = w.replace(".timeout_ms = 2000,", ".timeout_ms = 20000,", 1)
        if w2 == w and ".timeout_ms = 20000," not in w:
            print("  FAIL ath12k wifi7 WCN7850 timeout", file=sys.stderr)
            return False
        _write_if_changed(wifi7, orig_w, w2)

    mhi = src / "drivers/net/wireless/ath/ath12k/mhi.c"
    if mhi.is_file():
        mt = orig_m = mhi.read_text()
        if "IRQF_NO_AUTOEN" not in mt:
            if "#include <linux/interrupt.h>" not in mt:
                mt = mt.replace("#include <linux/msi.h>\n",
                                "#include <linux/interrupt.h>\n#include <linux/msi.h>\n", 1)
            old = """	if (!test_bit(ATH12K_PCI_FLAG_MULTI_MSI_VECTORS, &ab_pci->flags))
		mhi_ctrl->irq_flags = IRQF_SHARED | IRQF_NOBALANCING;
"""
            new = """	if (!test_bit(ATH12K_PCI_FLAG_MULTI_MSI_VECTORS, &ab_pci->flags))
		mhi_ctrl->irq_flags = IRQF_SHARED | IRQF_NOBALANCING |
				      IRQF_NO_SUSPEND | IRQF_NO_AUTOEN;
	else
		mhi_ctrl->irq_flags = IRQF_NO_SUSPEND | IRQF_NO_AUTOEN;
"""
            if old not in mt:
                print("  FAIL ath12k mhi irq_flags", file=sys.stderr)
                return False
            mt = mt.replace(old, new, 1)
            _write_if_changed(mhi, orig_m, mt)

    print("  OK   ath12k parent ASPM + WCN7850 MHI timeout/IRQ flags (1040/1042)", file=sys.stderr)
    return True


def apply_ath12k_s2ram(src: Path) -> bool:
    """Force ath12k power_down on PM_SUSPEND_MEM even if HW is not OFF.

    WCN7850 advertises supports_suspend, but continue_suspend_resume
    returns 0 unless ATH12K_HW_STATE_OFF. wlan0 down does not reach that
    state, so system suspend succeeds without MHI power-down: chip stays
    M0, ASPM stays off, upper-right heat, hang, force-off.
    """
    core = src / "drivers/net/wireless/ath/ath12k/core.c"
    if not core.is_file():
        return True
    text = orig = core.read_text()
    if "ath12k_masi_s2ram_force" in text:
        print("  OK   ath12k S2RAM force power-down (1055, already)", file=sys.stderr)
        return True

    if "#include <linux/suspend.h>" not in text:
        if "#include <linux/export.h>\n" not in text:
            print("  FAIL ath12k s2ram: no export.h include", file=sys.stderr)
            return False
        text = text.replace(
            "#include <linux/export.h>\n",
            "#include <linux/export.h>\n#include <linux/suspend.h>\n",
            1,
        )

    old = """static int ath12k_core_continue_suspend_resume(struct ath12k_base *ab)
{
	struct ath12k *ar;

	if (!ab->hw_params->supports_suspend)
		return -EOPNOTSUPP;

	/* so far single_pdev_only chips have supports_suspend as true
	 * so pass 0 as a dummy pdev_id here.
	 */
	ar = ab->pdevs[0].ar;
	if (!ar || !ar->ah || ar->ah->state != ATH12K_HW_STATE_OFF)
		return 0;

	return 1;
}
"""
    new = """static bool ath12k_masi_s2ram_force;

static int ath12k_core_continue_suspend_resume(struct ath12k_base *ab)
{
	struct ath12k *ar;

	if (!ab->hw_params->supports_suspend)
		return -EOPNOTSUPP;

	/* so far single_pdev_only chips have supports_suspend as true
	 * so pass 0 as a dummy pdev_id here.
	 */
	ar = ab->pdevs[0].ar;
	if (!ar || !ar->ah)
		return 0;

	/* WCN7850 stays ATH12K_HW_STATE_ON after wlan0 down. Skipping
	 * power_down leaves MHI in M0 / ASPM off and the SoC hot, then
	 * the machine never reaches PSCI (hang + force-off).
	 */
	if (ar->ah->state != ATH12K_HW_STATE_OFF) {
#ifdef CONFIG_SUSPEND
		if (pm_suspend_target_state == PM_SUSPEND_MEM) {
			ath12k_masi_s2ram_force = true;
			ath12k_info(ab, "S2RAM: power down WCN while hw state %d\\n",
				    ar->ah->state);
			return 1;
		}
		if (ath12k_masi_s2ram_force)
			return 1;
#endif
		return 0;
	}

	ath12k_masi_s2ram_force = false;
	return 1;
}
"""
    if old not in text:
        print("  FAIL ath12k s2ram: continue_suspend_resume marker", file=sys.stderr)
        return False
    text = text.replace(old, new, 1)
    _write_if_changed(core, orig, text)
    print("  OK   ath12k S2RAM force power-down (1055)", file=sys.stderr)
    return True


def apply_mhi_host(src: Path) -> bool:
    boot = src / "drivers/bus/mhi/host/boot.c"
    init = src / "drivers/bus/mhi/host/init.c"
    main = src / "drivers/bus/mhi/host/main.c"
    pm = src / "drivers/bus/mhi/host/pm.c"
    internal = src / "drivers/bus/mhi/host/internal.h"
    for p in (boot, init, main, pm, internal):
        if not p.is_file():
            print(f"  MISS {p.name}", file=sys.stderr)
            return False

    # --- drain ---
    mt = orig_m = main.read_text()
    if "void mhi_drain_events(" not in mt:
        insert = '''
void mhi_drain_events(struct mhi_controller *mhi_cntrl)
{
	struct mhi_event *mhi_event = mhi_cntrl->mhi_event;
	int i;

	if (!mhi_cntrl->mhi_ctxt || !mhi_event)
		return;

	for (i = 0; i < mhi_cntrl->total_ev_rings; i++, mhi_event++) {
		if (mhi_event->offload_ev || !mhi_event->process_event)
			continue;
		mhi_event->process_event(mhi_cntrl, mhi_event, U32_MAX);
	}
}

'''
        if "void mhi_ev_task(unsigned long data)" not in mt:
            print("  FAIL mhi drain: no mhi_ev_task", file=sys.stderr)
            return False
        mt = mt.replace("void mhi_ev_task(unsigned long data)",
                        insert + "void mhi_ev_task(unsigned long data)", 1)
        _write_if_changed(main, orig_m, mt)

    mt = orig_m = main.read_text()
    if "#include <linux/jiffies.h>" not in mt:
        mt = mt.replace("#include <linux/interrupt.h>\n",
                        "#include <linux/interrupt.h>\n#include <linux/jiffies.h>\n"
                        "#include <linux/workqueue.h>\n", 1)

    if "mhi_event_poll_worker" not in mt:
        poller = '''
static struct mhi_controller *mhi_event_poll_cntrl;
static void mhi_event_poll_worker(struct work_struct *work);
static DECLARE_DELAYED_WORK(mhi_event_poll_work, mhi_event_poll_worker);

static void mhi_event_poll_worker(struct work_struct *work)
{
	struct mhi_controller *mhi_cntrl = READ_ONCE(mhi_event_poll_cntrl);

	if (!mhi_cntrl)
		return;
	mhi_drain_events(mhi_cntrl);
	if (!MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state))
		schedule_delayed_work(&mhi_event_poll_work, msecs_to_jiffies(2));
}

void mhi_start_event_poll(struct mhi_controller *mhi_cntrl)
{
	WRITE_ONCE(mhi_event_poll_cntrl, mhi_cntrl);
	mod_delayed_work(system_wq, &mhi_event_poll_work, 0);
}

void mhi_stop_event_poll(struct mhi_controller *mhi_cntrl)
{
	if (READ_ONCE(mhi_event_poll_cntrl) != mhi_cntrl)
		return;
	WRITE_ONCE(mhi_event_poll_cntrl, NULL);
	cancel_delayed_work_sync(&mhi_event_poll_work);
}

'''
        if "void mhi_ev_task(unsigned long data)" not in mt:
            print("  FAIL mhi poller: no mhi_ev_task", file=sys.stderr)
            return False
        mt = mt.replace("void mhi_ev_task(unsigned long data)",
                        poller + "void mhi_ev_task(unsigned long data)", 1)

    if "drain channel command" not in mt:
        old_cmd = """	ret = wait_for_completion_timeout(&mhi_chan->completion,
				       msecs_to_jiffies(mhi_cntrl->timeout_ms));
	if (!ret || mhi_chan->ccs != MHI_EV_CC_SUCCESS) {
		dev_err(dev,
			"%d: Failed to receive %s channel command completion\\n",
			mhi_chan->chan, TO_CH_STATE_TYPE_STR(to_state));
"""
        new_cmd = """	{
		unsigned long cmd_deadline =
			jiffies + msecs_to_jiffies(mhi_cntrl->timeout_ms);

		/*
		 * START/RESET completion is an event-ring TRE. On SM8550
		 * 7.2.8 qcom-pcie MSI never wakes wait_for_completion, so
		 * QRTR IPCR sits ~90s then probe fails -EIO and no wlan.
		 */
		dev_info(dev, "drain channel command %s ch %d\\n",
			 TO_CH_STATE_TYPE_STR(to_state), mhi_chan->chan);
		ret = 0;
		do {
			mhi_drain_events(mhi_cntrl);
			if (try_wait_for_completion(&mhi_chan->completion)) {
				ret = 1;
				break;
			}
			usleep_range(1000, 2000);
		} while (time_before(jiffies, cmd_deadline));
	}
	if (!ret || mhi_chan->ccs != MHI_EV_CC_SUCCESS) {
		dev_err(dev,
			"%d: Failed to receive %s channel command completion\\n",
			mhi_chan->chan, TO_CH_STATE_TYPE_STR(to_state));
"""
        if old_cmd not in mt:
            print("  FAIL mhi main: channel command wait", file=sys.stderr)
            return False
        mt = mt.replace(old_cmd, new_cmd, 1)
    _write_if_changed(main, orig_m, mt)

    it = orig_i = internal.read_text()
    if "void mhi_drain_events(" not in it:
        if "int mhi_process_ctrl_ev_ring(" not in it:
            print("  FAIL mhi internal.h: no process_ctrl proto", file=sys.stderr)
            return False
        it = it.replace(
            "int mhi_process_ctrl_ev_ring(",
            "void mhi_drain_events(struct mhi_controller *mhi_cntrl);\n"
            "int mhi_process_ctrl_ev_ring(",
            1,
        )
    if "void mhi_start_event_poll(" not in it:
        it = it.replace(
            "void mhi_drain_events(struct mhi_controller *mhi_cntrl);\n",
            "void mhi_drain_events(struct mhi_controller *mhi_cntrl);\n"
            "void mhi_start_event_poll(struct mhi_controller *mhi_cntrl);\n"
            "void mhi_stop_event_poll(struct mhi_controller *mhi_cntrl);\n",
            1,
        )
    _write_if_changed(internal, orig_i, it)

    # --- init IRQF_NO_AUTOEN ---
    xt = orig_x = init.read_text()
    if "IRQF_NO_AUTOEN" not in xt:
        xt = xt.replace(
            "unsigned long irq_flags = IRQF_SHARED | IRQF_NO_SUSPEND;",
            "unsigned long irq_flags = IRQF_SHARED | IRQF_NO_SUSPEND | IRQF_NO_AUTOEN;",
            1,
        )
        old_dis = """	/*
	 * IRQs should be enabled during mhi_async_power_up(), so disable them explicitly here.
	 * Due to the use of IRQF_SHARED flag as default while requesting IRQs, we assume that
	 * IRQ_NOAUTOEN is not applicable.
	 */
	disable_irq(mhi_cntrl->irq[0]);
"""
        new_dis = """	/*
	 * Do not disable_irq() after request. On SM8550 qcom-pcie MSI,
	 * disable_irq()+enable_irq() leaves the WCN7850 vectors masked.
	 * IRQF_NO_AUTOEN keeps them off until mhi_async_power_up().
	 */
	if (!(irq_flags & IRQF_NO_AUTOEN))
		disable_irq(mhi_cntrl->irq[0]);
"""
        if old_dis not in xt:
            print("  FAIL mhi init: disable_irq(0) block", file=sys.stderr)
            return False
        xt = xt.replace(old_dis, new_dis, 1)
        xt = xt.replace(
            "\t\tdisable_irq(mhi_cntrl->irq[mhi_event->irq]);",
            "\t\tif (!(irq_flags & IRQF_NO_AUTOEN))\n"
            "\t\t\tdisable_irq(mhi_cntrl->irq[mhi_event->irq]);",
            1,
        )
        _write_if_changed(init, orig_x, xt)

    # --- boot poll ---
    bt = orig_b = boot.read_text()
    if "#include <linux/jiffies.h>" not in bt:
        bt = bt.replace("#include <linux/interrupt.h>\n",
                        "#include <linux/interrupt.h>\n#include <linux/jiffies.h>\n", 1)
    if "static int mhi_fw_poll_status(" not in bt:
        helper = r'''
/*
 * BHI/BHIE completion is advertised in MMIO. wait_event_timeout only
 * rechecks that MMIO when an IRQ wakes the queue. On SM8550 7.2.8 the
 * qcom-pcie MSI for WCN7850 never wakes this wait after mhi_init_irq_setup
 * disable_irq()/enable_irq(), so firmware load sits on
 * "Power on setup success" and no wlan appears. Poll the status bit.
 */
static int mhi_fw_poll_status(struct mhi_controller *mhi_cntrl,
			      void __iomem *base, u32 offset, u32 mask,
			      u32 *status)
{
	unsigned long timeout = jiffies + msecs_to_jiffies(mhi_cntrl->timeout_ms);
	int ret;

	*status = 0;
	do {
		if (MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state))
			return -EIO;

		mhi_drain_events(mhi_cntrl);
		ret = mhi_read_reg_field(mhi_cntrl, base, offset, mask, status);
		if (ret)
			return ret;
		if (*status)
			return 0;

		usleep_range(5000, 10000);
	} while (time_before(jiffies, timeout));

	return -ETIMEDOUT;
}

'''
        if "/* Setup RDDM vector table" not in bt:
            print("  FAIL mhi boot: RDDM marker", file=sys.stderr)
            return False
        bt = bt.replace("/* Setup RDDM vector table", helper + "/* Setup RDDM vector table", 1)

    old_bhie = """	/* Wait for the image download to complete */
	ret = wait_event_timeout(mhi_cntrl->state_event,
				 MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state) ||
				 mhi_read_reg_field(mhi_cntrl, base,
						   BHIE_TXVECSTATUS_OFFS,
						   BHIE_TXVECSTATUS_STATUS_BMSK,
						   &tx_status) || tx_status,
				 msecs_to_jiffies(mhi_cntrl->timeout_ms));
	if (MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state) ||
	    tx_status != BHIE_TXVECSTATUS_STATUS_XFER_COMPL)
		return -EIO;

	return (!ret) ? -ETIMEDOUT : 0;
"""
    new_bhie = """	ret = mhi_fw_poll_status(mhi_cntrl, base, BHIE_TXVECSTATUS_OFFS,
				 BHIE_TXVECSTATUS_STATUS_BMSK, &tx_status);
	if (ret)
		return ret;
	if (MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state) ||
	    tx_status != BHIE_TXVECSTATUS_STATUS_XFER_COMPL)
		return -EIO;

	return 0;
"""
    if "mhi_fw_poll_status(mhi_cntrl, base, BHIE_TXVECSTATUS_OFFS" not in bt:
        if old_bhie not in bt:
            print("  FAIL mhi boot: BHIE wait_event", file=sys.stderr)
            return False
        bt = bt.replace(old_bhie, new_bhie, 1)

    old_bhi = """	/* Wait for the image download to complete */
	ret = wait_event_timeout(mhi_cntrl->state_event,
			   MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state) ||
			   mhi_read_reg_field(mhi_cntrl, base, BHI_STATUS,
					      BHI_STATUS_MASK, &tx_status) || tx_status,
			   msecs_to_jiffies(mhi_cntrl->timeout_ms));
	if (MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state))
		goto invalid_pm_state;
"""
    new_bhi = """	dev_info(dev, "BHI image download %zu bytes\\n", mhi_buf->len);
	ret = mhi_fw_poll_status(mhi_cntrl, base, BHI_STATUS,
				 BHI_STATUS_MASK, &tx_status);
	if (ret) {
		dev_err(dev, "BHI image download timed out, ret: %d\\n", ret);
		goto invalid_pm_state;
	}
	if (MHI_PM_IN_ERROR_STATE(mhi_cntrl->pm_state))
		goto invalid_pm_state;
"""
    if "BHI image download %zu bytes" not in bt:
        if old_bhi not in bt:
            print("  FAIL mhi boot: BHI wait_event", file=sys.stderr)
            return False
        bt = bt.replace(old_bhi, new_bhi, 1)
        bt = bt.replace(
            "	return (!ret) ? -ETIMEDOUT : 0;\n\ninvalid_pm_state:",
            "	dev_info(dev, \"BHI image download complete, status %u\\n\", tx_status);\n"
            "	return 0;\n\ninvalid_pm_state:",
            1,
        )

    if "loading AMSS inline" not in bt:
        queued = """			if (ee == MHI_EE_SBL) {
				dev_info(dev, "Polled EE SBL, queueing AMSS download\\n");
				mhi_queue_state_transition(mhi_cntrl,
							   DEV_ST_TRANSITION_SBL);
				break;
			}"""
        inline = """			if (ee == MHI_EE_SBL) {
				/*
				 * Do not only queue DEV_ST_TRANSITION_SBL:
				 * st_worker is already running this READY/PBL
				 * item on hiprio_wq, so AMSS never started and
				 * ath12k sat in POWER_ON until -ETIMEDOUT (~90s).
				 */
				dev_info(dev, "Polled EE SBL, loading AMSS inline\\n");
				write_lock_irq(&mhi_cntrl->pm_lock);
				mhi_cntrl->ee = MHI_EE_SBL;
				write_unlock_irq(&mhi_cntrl->pm_lock);
				mhi_create_devices(mhi_cntrl);
				mhi_uevent_notify(mhi_cntrl, MHI_EE_SBL);
				if (mhi_cntrl->fbc_download) {
					amss_ret = mhi_download_amss_image(mhi_cntrl);
					dev_info(dev, "AMSS BHIe ret=%d\\n", amss_ret);
					if (!amss_ret)
						mhi_cntrl->fbc_download = false;
				}
				break;
			}"""
        if queued in bt:
            if "int amss_ret;" not in bt:
                bt = bt.replace(
                    "\t\tenum mhi_ee_type ee = MHI_EE_MAX;\n",
                    "\t\tenum mhi_ee_type ee = MHI_EE_MAX;\n"
                    "\t\tint amss_ret;\n",
                    1,
                )
            bt = bt.replace(queued, inline, 1)
            if "Polled EE %s after AMSS" not in bt:
                after = """		if (ee != MHI_EE_SBL && !MHI_IN_MISSION_MODE(ee))
			dev_info(dev, "EE still %s after poll (waiting for MSI)\\n",
				 TO_MHI_EXEC_STR(ee));
"""
                after_new = """		if (ee == MHI_EE_SBL) {
			timeout = jiffies + msecs_to_jiffies(mhi_cntrl->timeout_ms);
			do {
				mhi_drain_events(mhi_cntrl);
				ee = mhi_get_exec_env(mhi_cntrl);
				if (MHI_IN_MISSION_MODE(ee)) {
					dev_info(dev, "Polled EE %s after AMSS\\n",
						 TO_MHI_EXEC_STR(ee));
					mhi_queue_state_transition(mhi_cntrl,
								   DEV_ST_TRANSITION_MISSION_MODE);
					break;
				}
				usleep_range(2000, 4000);
			} while (time_before(jiffies, timeout));
		}

		if (ee != MHI_EE_SBL && !MHI_IN_MISSION_MODE(ee))
			dev_info(dev, "EE still %s after poll (waiting for MSI)\\n",
				 TO_MHI_EXEC_STR(ee));
"""
                if after in bt:
                    bt = bt.replace(after, after_new, 1)

    if "loading AMSS inline" not in bt:
        old_wait = """	dev_info(dev, "Wait for device to enter SBL or Mission mode\\n");
	return;
"""
        new_wait = """	dev_info(dev, "Wait for device to enter SBL or Mission mode\\n");
	{
		unsigned long timeout = jiffies + msecs_to_jiffies(3000);
		enum mhi_ee_type ee = MHI_EE_MAX;
		int amss_ret;

		do {
			mhi_drain_events(mhi_cntrl);
			ee = mhi_get_exec_env(mhi_cntrl);
			if (ee == MHI_EE_SBL) {
				/*
				 * Do not only queue DEV_ST_TRANSITION_SBL:
				 * st_worker is already running this READY/PBL
				 * item on hiprio_wq, so AMSS never started and
				 * ath12k sat in POWER_ON until -ETIMEDOUT (~90s).
				 */
				dev_info(dev, "Polled EE SBL, loading AMSS inline\\n");
				write_lock_irq(&mhi_cntrl->pm_lock);
				mhi_cntrl->ee = MHI_EE_SBL;
				write_unlock_irq(&mhi_cntrl->pm_lock);
				mhi_create_devices(mhi_cntrl);
				mhi_uevent_notify(mhi_cntrl, MHI_EE_SBL);
				if (mhi_cntrl->fbc_download) {
					amss_ret = mhi_download_amss_image(mhi_cntrl);
					dev_info(dev, "AMSS BHIe ret=%d\\n", amss_ret);
					if (!amss_ret)
						mhi_cntrl->fbc_download = false;
				}
				break;
			}
			if (MHI_IN_MISSION_MODE(ee)) {
				dev_info(dev, "Polled EE %s\\n",
					 TO_MHI_EXEC_STR(ee));
				mhi_queue_state_transition(mhi_cntrl,
							   DEV_ST_TRANSITION_MISSION_MODE);
				break;
			}
			usleep_range(2000, 4000);
		} while (time_before(jiffies, timeout));

		if (ee == MHI_EE_SBL) {
			timeout = jiffies + msecs_to_jiffies(mhi_cntrl->timeout_ms);
			do {
				mhi_drain_events(mhi_cntrl);
				ee = mhi_get_exec_env(mhi_cntrl);
				if (MHI_IN_MISSION_MODE(ee)) {
					dev_info(dev, "Polled EE %s after AMSS\\n",
						 TO_MHI_EXEC_STR(ee));
					mhi_queue_state_transition(mhi_cntrl,
								   DEV_ST_TRANSITION_MISSION_MODE);
					break;
				}
				usleep_range(2000, 4000);
			} while (time_before(jiffies, timeout));
		}

		if (ee != MHI_EE_SBL && !MHI_IN_MISSION_MODE(ee))
			dev_info(dev, "EE still %s after poll (waiting for MSI)\\n",
				 TO_MHI_EXEC_STR(ee));
	}
	return;
"""
        if old_wait in bt:
            bt = bt.replace(old_wait, new_wait, 1)
        elif "queueing AMSS download" in bt:
            print("  FAIL mhi boot: SBL queueing block mismatch", file=sys.stderr)
            return False
        else:
            print("  FAIL mhi boot: SBL wait marker", file=sys.stderr)
            return False

    if "BHIe AMSS download" not in bt and "Starting image download via BHIe" in bt:
        bt = bt.replace(
            "	dev_dbg(dev, \"Starting image download via BHIe. Sequence ID: %u\\n\",\n"
            "		sequence_id);\n",
            "	dev_info(dev, \"BHIe AMSS download %zu bytes seq %u\\n\",\n"
            "		 mhi_buf->len, sequence_id);\n",
            1,
        )
    _write_if_changed(boot, orig_b, bt)

    pt = orig_p = pm.read_text()
    if "Mission mode M0 already" not in pt:
        old_dup = """	dev_dbg(dev, "Processing Mission Mode transition\\n");

	write_lock_irq(&mhi_cntrl->pm_lock);
"""
        new_dup = """	dev_dbg(dev, "Processing Mission Mode transition\\n");

	if (MHI_IN_MISSION_MODE(current_ee)) {
		dev_info(dev, "Mission mode M0 already, skip duplicate\\n");
		return 0;
	}

	write_lock_irq(&mhi_cntrl->pm_lock);
"""
        if old_dup not in pt:
            print("  FAIL mhi pm: mission-mode duplicate skip", file=sys.stderr)
            return False
        pt = pt.replace(old_dup, new_dup, 1)

    if "Mission mode M0, creating devices" not in pt:
        old = """	 * Execution Environment (EE) to either SBL or AMSS states
	 */
	mhi_create_devices(mhi_cntrl);
"""
        new = """	 * Execution Environment (EE) to either SBL or AMSS states
	 */
	dev_info(dev, "Mission mode M0, creating devices\\n");
	mhi_create_devices(mhi_cntrl);
	mhi_start_event_poll(mhi_cntrl);
"""
        if old not in pt:
            print("  FAIL mhi pm: create_devices marker", file=sys.stderr)
            return False
        pt = pt.replace(old, new, 1)
    elif "mhi_start_event_poll" not in pt:
        pt = pt.replace(
            "	dev_info(dev, \"Mission mode M0, creating devices\\n\");\n"
            "	mhi_create_devices(mhi_cntrl);\n",
            "	dev_info(dev, \"Mission mode M0, creating devices\\n\");\n"
            "	mhi_create_devices(mhi_cntrl);\n"
            "	mhi_start_event_poll(mhi_cntrl);\n",
            1,
        )

    if "mhi_stop_event_poll" not in pt:
        old_dis = """	dev_dbg(dev, "Processing disable transition with PM state: %s\\n",
		to_mhi_pm_state_str(mhi_cntrl->pm_state));
"""
        new_dis = """	dev_dbg(dev, "Processing disable transition with PM state: %s\\n",
		to_mhi_pm_state_str(mhi_cntrl->pm_state));
	mhi_stop_event_poll(mhi_cntrl);
"""
        if old_dis not in pt:
            print("  FAIL mhi pm: disable transition marker", file=sys.stderr)
            return False
        pt = pt.replace(old_dis, new_dis, 1)

    _write_if_changed(pm, orig_p, pt)

    print("  OK   MHI MMIO poll + drain + SBL/AMSS (1041–1043)", file=sys.stderr)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("src")
    parser.add_argument("--rsinput", action="store_true")
    parser.add_argument("--haptics", action="store_true")
    parser.add_argument("--mhi", action="store_true")
    args = parser.parse_args()
    src = Path(args.src)
    want_all = not (args.rsinput or args.haptics or args.mhi)
    ok = True
    if want_all or args.rsinput:
        ok &= apply_rsinput(src)
    if want_all or args.haptics:
        ok &= apply_haptics_stop(src)
    if want_all or args.mhi:
        ok &= apply_ath12k_aspm(src)
        ok &= apply_ath12k_s2ram(src)
        ok &= apply_mhi_host(src)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
