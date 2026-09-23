"""GTK 3 main window for Easy Kernel Updater."""

from __future__ import annotations

import threading
import traceback

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk, Pango

from . import __app_name__, __version__
from .constants import GITHUB_REPO, KERNEL_TREE
from .installer import build_from_source, install_build, prepare_candidate, tree_has_make_sh, tree_has_update_sh
from .versions import (
    KernelCandidate,
    list_github_releases,
    list_kernel_org_candidates,
    list_local_builds,
    merge_candidates,
    running_release,
    running_version,
)


class MainWindow(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(title=__app_name__)
        self.set_default_size(720, 640)
        self.set_border_width(14)
        self._busy = False
        self._rows: list[KernelCandidate] = []

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(root)

        title = Gtk.Label()
        title.set_markup(f"<span size='x-large'><b>{__app_name__}</b></span>")
        title.set_xalign(0)
        sub = Gtk.Label(
            label="SM8550 ABL kernel — show the running release and install newer builds when available."
        )
        sub.set_xalign(0)
        sub.set_line_wrap(True)
        root.pack_start(title, False, False, 0)
        root.pack_start(sub, False, False, 0)

        self.status_running = Gtk.Label(label="Running: …")
        self.status_running.set_xalign(0)
        self.status_running.set_selectable(True)
        self.status_tree = Gtk.Label(label=f"Tree: {KERNEL_TREE}")
        self.status_tree.set_xalign(0)
        self.status_tree.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        self.status_tree.set_selectable(True)
        root.pack_start(self.status_running, False, False, 0)
        root.pack_start(self.status_tree, False, False, 0)

        self.info = Gtk.Label(label="")
        self.info.set_xalign(0)
        self.info.set_line_wrap(True)
        root.pack_start(self.info, False, False, 0)

        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.refresh_btn = Gtk.Button(label="Refresh")
        self.refresh_btn.connect("clicked", lambda *_: self.refresh_async())
        toolbar.pack_start(self.refresh_btn, False, False, 0)
        toolbar.pack_end(Gtk.Label(label=f"v{__version__}"), False, False, 0)
        root.pack_start(toolbar, False, False, 0)

        self.progress = Gtk.ProgressBar()
        self.progress.set_show_text(True)
        self.progress.set_no_show_all(True)
        self.progress.hide()
        root.pack_start(self.progress, False, False, 0)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_vexpand(True)
        root.pack_start(scrolled, True, True, 0)

        self.list_box = Gtk.ListBox()
        self.list_box.set_selection_mode(Gtk.SelectionMode.NONE)
        scrolled.add(self.list_box)

        self.log_view = Gtk.TextView()
        self.log_view.set_editable(False)
        self.log_view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.log_view.set_monospace(True)
        log_scroll = Gtk.ScrolledWindow()
        log_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        log_scroll.set_min_content_height(120)
        log_scroll.add(self.log_view)
        root.pack_start(log_scroll, False, False, 0)

        self.connect("destroy", Gtk.main_quit)
        self._refresh_status_labels()
        self.refresh_async()

    def _set_busy(self, busy: bool) -> None:
        self._busy = busy
        self.refresh_btn.set_sensitive(not busy)

    def _append_log(self, text: str) -> None:
        buf = self.log_view.get_buffer()
        end = buf.get_end_iter()
        buf.insert(end, text.rstrip() + "\n")

    def _refresh_status_labels(self) -> None:
        self.status_running.set_markup(
            f"<b>Running kernel:</b> {GLib.markup_escape_text(running_release())} "
            f"(base {GLib.markup_escape_text(running_version())})"
        )
        update_ok = "yes" if tree_has_update_sh() else "missing update.sh"
        make_ok = "yes" if tree_has_make_sh() else "no"
        self.status_tree.set_text(f"Tree: {KERNEL_TREE}  ·  update.sh: {update_ok}  ·  make.sh: {make_ok}")

    def refresh_async(self) -> None:
        if self._busy:
            return
        self._set_busy(True)
        self.info.set_text("Checking local builds, GitHub releases, and kernel.org…")

        def worker() -> None:
            err = ""
            try:
                local = list_local_builds()
                github = list_github_releases()
                org = list_kernel_org_candidates()
                rows = merge_candidates(local, github, org)
            except Exception as exc:  # noqa: BLE001
                rows = []
                err = f"{exc}\n{traceback.format_exc()}"

            def done() -> None:
                self._set_busy(False)
                self._refresh_status_labels()
                if err:
                    self.info.set_text("Refresh failed — see log.")
                    self._append_log(err)
                    return
                self._rows = rows
                self._rebuild_list()
                newer = sum(1 for r in rows if r.newer and r.source in {"local", "github"})
                buildable = sum(1 for r in rows if r.newer and r.source == "kernel.org")
                if newer:
                    self.info.set_text(
                        f"Found {newer} newer installable build(s). "
                        f"GitHub: https://github.com/{GITHUB_REPO}/releases"
                    )
                elif buildable and tree_has_make_sh():
                    self.info.set_text(
                        f"No prebuilt packages yet — {buildable} newer kernel.org version(s) "
                        "can be built with make.sh."
                    )
                elif buildable:
                    self.info.set_text(
                        "Newer kernel.org versions exist, but this device has no make.sh tree. "
                        f"Publish a release asset on {GITHUB_REPO} or run the GUI from the kernel updater checkout."
                    )
                else:
                    self.info.set_text("You are on the latest known SM8550-compatible kernel (or no newer packages found).")

            GLib.idle_add(done)

        threading.Thread(target=worker, daemon=True).start()

    def _rebuild_list(self) -> None:
        for child in list(self.list_box.get_children()):
            self.list_box.remove(child)

        if not self._rows:
            row = Gtk.ListBoxRow()
            lab = Gtk.Label(label="No candidates found.")
            lab.set_xalign(0)
            lab.set_margin_top(8)
            lab.set_margin_bottom(8)
            row.add(lab)
            self.list_box.add(row)
            self.list_box.show_all()
            return

        for cand in self._rows:
            self.list_box.add(self._make_row(cand))
        self.list_box.show_all()

    def _make_row(self, cand: KernelCandidate) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(6)
        box.set_margin_end(6)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title = Gtk.Label()
        badges = []
        if cand.current:
            badges.append("current")
        if cand.newer:
            badges.append("newer")
        badge = f"  [{', '.join(badges)}]" if badges else ""
        title.set_markup(
            f"<b>{GLib.markup_escape_text(cand.version)}</b>"
            f"<span foreground='#666'> · {GLib.markup_escape_text(cand.source)}{badge}</span>"
        )
        title.set_xalign(0)
        detail = Gtk.Label(label=cand.label)
        detail.set_xalign(0)
        detail.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        text.pack_start(title, False, False, 0)
        text.pack_start(detail, False, False, 0)
        box.pack_start(text, True, True, 0)

        if cand.source in {"local", "github"}:
            btn = Gtk.Button(label="Install")
            btn.set_sensitive(not cand.current and not self._busy)
            btn.connect("clicked", lambda _b, c=cand: self._on_install(c))
            box.pack_end(btn, False, False, 0)
        elif cand.source == "kernel.org" and tree_has_make_sh():
            btn = Gtk.Button(label="Build & install")
            btn.set_sensitive(not self._busy)
            btn.connect("clicked", lambda _b, c=cand: self._on_build_install(c))
            box.pack_end(btn, False, False, 0)
        else:
            lab = Gtk.Label(label="(no package)")
            lab.set_sensitive(False)
            box.pack_end(lab, False, False, 0)

        row.add(box)
        return row

    def _show_progress(self, show: bool) -> None:
        if show:
            self.progress.show()
        else:
            self.progress.hide()

    def _on_progress(self, stage: str, fraction: float) -> None:
        def ui() -> None:
            self.progress.set_text(stage)
            if fraction < 0:
                self.progress.pulse()
            else:
                self.progress.set_fraction(max(0.0, min(fraction, 1.0)))

        GLib.idle_add(ui)

    def _confirm(self, message: str) -> bool:
        dialog = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text=message,
        )
        response = dialog.run()
        dialog.destroy()
        return response == Gtk.ResponseType.OK

    def _on_install(self, cand: KernelCandidate) -> None:
        if self._busy:
            return
        if not tree_has_update_sh():
            self._append_log("update.sh missing — cannot install on this system.")
            self.info.set_text("Install runtime missing (update.sh).")
            return
        if not self._confirm(
            f"Install kernel {cand.version}?\n\n"
            "This backs up the current /boot KERNEL, firmware and modules, "
            "then installs the selected build. A reboot is required afterwards."
        ):
            return

        self._set_busy(True)
        self._show_progress(True)
        self.info.set_text(f"Installing {cand.version}…")

        def worker() -> None:
            err = ""
            try:
                build = prepare_candidate(cand, progress=self._on_progress)
                install_build(build, progress=self._on_progress)
            except Exception as exc:  # noqa: BLE001
                err = str(exc)

            def done() -> None:
                self._set_busy(False)
                self._show_progress(False)
                self._rebuild_list()
                if err:
                    self.info.set_text("Install failed — see log.")
                    self._append_log(err)
                else:
                    self.info.set_text(
                        f"Installed {cand.version}. Reboot to activate the new kernel "
                        "(ABL: Vol Down → set device → Linux → START)."
                    )
                    self._append_log(f"OK: installed {cand.version}")

            GLib.idle_add(done)

        threading.Thread(target=worker, daemon=True).start()

    def _on_build_install(self, cand: KernelCandidate) -> None:
        if self._busy:
            return
        if not self._confirm(
            f"Build linux-{cand.version} from source and install?\n\n"
            "This can take a long time on-device. Prefer publishing a GitHub "
            "release package when possible."
        ):
            return

        self._set_busy(True)
        self._show_progress(True)
        self.info.set_text(f"Building {cand.version}…")

        def worker() -> None:
            err = ""
            try:
                build = build_from_source(cand.version, progress=self._on_progress)
                install_build(build, progress=self._on_progress)
            except Exception as exc:  # noqa: BLE001
                err = str(exc)

            def done() -> None:
                self._set_busy(False)
                self._show_progress(False)
                self.refresh_async()
                if err:
                    self.info.set_text("Build/install failed — see log.")
                    self._append_log(err)
                else:
                    self.info.set_text(f"Built and installed {cand.version}. Reboot to activate.")
                    self._append_log(f"OK: built+installed {cand.version}")

            GLib.idle_add(done)

        threading.Thread(target=worker, daemon=True).start()


def run_gui() -> None:
    win = MainWindow()
    win.show_all()
    win.progress.hide()
    Gtk.main()
