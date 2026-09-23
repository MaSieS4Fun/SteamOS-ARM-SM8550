#!/usr/bin/env python3
"""Easy UFS Installer — GUI for installing Linux to internal UFS."""

from __future__ import annotations

import os
import shutil
import subprocess
import threading
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk, Pango

APP_NAME = "Easy UFS Installer"
APP_VERSION = "2.0.0"

SHARE = Path(os.environ.get("EASY_UFS_INSTALL_ROOT", "/usr/share/easy-ufs-install"))
INSTALL_SH = SHARE / "install-masios-to-internal.sh"
PROBE_SH = SHARE / "ufs-probe-sizes.sh"
DIAGNOSE_SH = SHARE / "ufs-diagnose.sh"

WARNING_TEXT = (
    "WARNING — THIS WILL MODIFY THE INTERNAL STORAGE OF YOUR DEVICE\n\n"
    "This tool repartitions internal UFS and installs SteamOS alongside Android "
    "(ROCKNIX ABL 3-partition layout: boot + root + home).\n\n"
    "• Android userdata will be ERASED (factory-reset style).\n"
    "• Incorrect use MAY cause data loss or make Android/Linux unbootable.\n"
    "• Run this from microSD Linux, not from an already-installed UFS root.\n"
    "• Keep ROCKNIX ABL installed and a working /boot/KERNEL on the SD.\n\n"
    "Nothing should go wrong if you follow the steps, but DATA LOSS IS POSSIBLE.\n"
    "Proceed only if you understand the risk."
)


def _pkexec(argv: list[str]) -> subprocess.CompletedProcess[str]:
    if os.geteuid() == 0:
        return subprocess.run(argv, check=False, text=True, capture_output=True)
    if shutil.which("pkexec"):
        return subprocess.run(["pkexec", *argv], check=False, text=True, capture_output=True)
    return subprocess.run(["sudo", "--", *argv], check=False, text=True, capture_output=True)


def probe_sizes() -> dict[str, str]:
    script = PROBE_SH if PROBE_SH.is_file() else Path(__file__).resolve().parent / "ufs-probe-sizes.sh"
    if not script.is_file():
        raise RuntimeError(f"Missing probe script: {script}")
    # Probe may need root for parted on some devices
    proc = _pkexec(["bash", str(script)])
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip() or f"exit {proc.returncode}"
        raise RuntimeError(err)
    out: dict[str, str] = {}
    for line in (proc.stdout or "").splitlines():
        if "=" in line and not line.startswith("ERROR="):
            k, v = line.split("=", 1)
            out[k] = v
        elif line.startswith("ERROR="):
            raise RuntimeError(line.split("=", 1)[1])
    if "MAX_ANDROID_GIB" not in out:
        raise RuntimeError("Probe did not return sizing info")
    return out


class MainWindow(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(title=APP_NAME)
        self.set_default_size(640, 720)
        self.set_border_width(14)
        self._busy = False
        self._info: dict[str, str] = {}

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(root)

        title = Gtk.Label()
        title.set_markup(f"<span size='x-large'><b>{APP_NAME}</b></span>")
        title.set_xalign(0)
        root.pack_start(title, False, False, 0)

        warn = Gtk.Label(label=WARNING_TEXT)
        warn.set_xalign(0)
        warn.set_line_wrap(True)
        warn.set_selectable(True)
        warn.override_color(Gtk.StateFlags.NORMAL, None)
        frame = Gtk.Frame(label="Read carefully")
        frame.set_shadow_type(Gtk.ShadowType.ETCHED_IN)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_border_width(10)
        # Red-ish emphasis via markup
        warn_m = Gtk.Label()
        warn_m.set_markup(
            "<span foreground='#b00020'><b>WARNING — THIS WILL MODIFY THE INTERNAL "
            "STORAGE OF YOUR DEVICE</b></span>\n\n"
            + GLib.markup_escape_text(
                "This tool repartitions internal UFS and installs SteamOS alongside Android "
                "(ROCKNIX ABL: ROCKNIX boot + STORAGE root + HOME).\n\n"
                "• Android userdata will be ERASED (factory-reset style).\n"
                "• Incorrect use MAY cause data loss or make Android/Linux unbootable.\n"
                "• Run this from microSD Linux, not from an already-installed UFS root.\n"
                "• Keep ROCKNIX ABL installed and a working /boot/KERNEL on the SD.\n\n"
                "STEAMOS PASSWORD: official SteamOS ships with no user password. "
                "Create one later (passwd in Konsole, or Users in System Settings). "
                "This installer asks for that password (pkexec/sudo). "
                "Without it the internal UFS install cannot run.\n\n"
                "Nothing should go wrong if you follow the steps, but DATA LOSS IS POSSIBLE.\n"
                "Proceed only if you understand the risk."
            )
        )
        warn_m.set_xalign(0)
        warn_m.set_line_wrap(True)
        warn_m.set_selectable(True)
        box.pack_start(warn_m, False, False, 0)
        frame.add(box)
        root.pack_start(frame, False, False, 0)

        self.status = Gtk.Label(label="Click Refresh to probe internal UFS…")
        self.status.set_xalign(0)
        self.status.set_line_wrap(True)
        root.pack_start(self.status, False, False, 0)

        grid = Gtk.Grid(column_spacing=12, row_spacing=8)
        grid.attach(Gtk.Label(label="Android partition size (GB):", xalign=0), 0, 0, 1, 1)
        adj = Gtk.Adjustment(value=64, lower=16, upper=512, step_increment=1, page_increment=8)
        self.size_spin = Gtk.SpinButton(adjustment=adj, climb_rate=1, digits=0)
        self.size_spin.set_numeric(True)
        grid.attach(self.size_spin, 1, 0, 1, 1)
        self.linux_label = Gtk.Label(label="SteamOS partitions: —", xalign=0)
        self.linux_label.set_line_wrap(True)
        grid.attach(self.linux_label, 0, 1, 2, 1)
        root.pack_start(grid, False, False, 0)
        self.size_spin.connect("value-changed", lambda *_: self._update_linux_label())

        self.ack = Gtk.CheckButton(
            label="I understand this modifies internal UFS and may erase Android data"
        )
        root.pack_start(self.ack, False, False, 0)

        buttons = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.refresh_btn = Gtk.Button(label="Refresh UFS info")
        self.refresh_btn.connect("clicked", lambda *_: self.refresh_async())
        self.install_btn = Gtk.Button(label="Install to internal UFS")
        self.install_btn.connect("clicked", self._on_install)
        buttons.pack_start(self.refresh_btn, False, False, 0)
        buttons.pack_start(self.install_btn, False, False, 0)
        buttons.pack_end(Gtk.Label(label=f"v{APP_VERSION}"), False, False, 0)
        root.pack_start(buttons, False, False, 0)

        self.log = Gtk.TextView()
        self.log.set_editable(False)
        self.log.set_monospace(True)
        self.log.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        scroll = Gtk.ScrolledWindow()
        scroll.set_min_content_height(180)
        scroll.add(self.log)
        root.pack_start(scroll, True, True, 0)

        self.connect("destroy", Gtk.main_quit)
        self.refresh_async()

    def _append(self, text: str) -> None:
        buf = self.log.get_buffer()
        buf.insert(buf.get_end_iter(), text.rstrip() + "\n")

    def _update_linux_label(self) -> None:
        if not self._info:
            return
        try:
            android = int(self.size_spin.get_value())
            boot = int(self._info.get("BOOT_PART_GIB", "2"))
            root = int(self._info.get("ROOT_PART_GIB", "16"))
            total = int(self._info.get("ORIG_ANDROID_GIB", "0"))
            home = total - android - boot - root
            self.linux_label.set_text(
                f"ROCKNIX boot {boot} GB  |  STORAGE root {root} GB  |  HOME ~{home} GB"
            )
        except ValueError:
            pass

    def refresh_async(self) -> None:
        if self._busy:
            return
        self._busy = True
        self.refresh_btn.set_sensitive(False)
        self.status.set_text("Probing internal UFS…")

        def worker() -> None:
            err = ""
            info: dict[str, str] = {}
            try:
                info = probe_sizes()
            except Exception as exc:  # noqa: BLE001
                err = str(exc)

            def done() -> None:
                self._busy = False
                self.refresh_btn.set_sensitive(True)
                if err:
                    self.status.set_text(f"Probe failed: {err}")
                    self._append(err)
                    return
                self._info = info
                mn = int(info["MIN_ANDROID_GIB"])
                mx = int(info["MAX_ANDROID_GIB"])
                rec = int(info["RECOMMENDED_ANDROID_GIB"])
                self.size_spin.set_range(mn, mx)
                self.size_spin.set_value(rec)
                existing = info.get("EXISTING_INSTALL", "0") == "1"
                old_two = info.get("OLD_TWOPART_INSTALL", "0") == "1"
                extra = ""
                if existing:
                    extra = " (ROCKNIX+STORAGE+HOME already present — use --resume / repair tools)"
                elif old_two:
                    extra = " (old 2-partition ROCKNIX+STORAGE — Uninstall ROCKNIX before a fresh SteamOS install)"
                self.status.set_text(
                    f"UFS {info.get('DEVICE')} · total ~{info.get('DISK_TOTAL_GIB')} GB · "
                    f"userdata now ~{info.get('ORIG_ANDROID_GIB')} GB · "
                    f"Android size {mn}–{mx} GB (recommended {rec}){extra}"
                )
                self._update_linux_label()
                self._append(f"Probe OK: {info}")

            GLib.idle_add(done)

        threading.Thread(target=worker, daemon=True).start()

    def _on_install(self, *_args) -> None:
        if self._busy:
            return
        if not self.ack.get_active():
            self._append("Tick the confirmation checkbox first.")
            return
        script = INSTALL_SH if INSTALL_SH.is_file() else Path(__file__).resolve().parent / "install-masios-to-internal.sh"
        if not script.is_file():
            self._append(f"Missing installer: {script}")
            return
        android_gb = int(self.size_spin.get_value())
        root_gb = int(self._info.get("ROOT_PART_GIB", "16")) if self._info else 16
        boot_gb = int(self._info.get("BOOT_PART_GIB", "2")) if self._info else 2
        dialog = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text="Confirm internal UFS install",
        )
        dialog.format_secondary_text(
            f"Android userdata will be set to {android_gb} GB and ERASED.\n"
            f"Creates ROCKNIX ({boot_gb} GB boot) + STORAGE ({root_gb} GB root) + HOME (remaining).\n"
            "Internal partitions will be rewritten. Continue?"
        )
        response = dialog.run()
        dialog.destroy()
        if response != Gtk.ResponseType.OK:
            return

        self._busy = True
        self.install_btn.set_sensitive(False)
        self.status.set_text(f"Installing with --android-gb {android_gb} (this takes a while)…")

        def worker() -> None:
            proc = _pkexec(["bash", str(script), "--force", "--android-gb", str(android_gb)])
            out = ((proc.stdout or "") + (proc.stderr or "")).strip()

            def done() -> None:
                self._busy = False
                self.install_btn.set_sensitive(True)
                if out:
                    self._append(out[-8000:])
                if proc.returncode == 0:
                    self.status.set_text("Install finished. Reboot and select Linux in ABL.")
                else:
                    self.status.set_text(f"Install failed (exit {proc.returncode}). See log.")

            GLib.idle_add(done)

        threading.Thread(target=worker, daemon=True).start()


def main() -> int:
    win = MainWindow()
    win.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
