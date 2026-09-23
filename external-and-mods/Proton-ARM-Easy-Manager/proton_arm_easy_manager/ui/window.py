from __future__ import annotations

import threading
from typing import Callable, Optional

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, Pango  # noqa: E402

from .. import __app_name__, __version__
from ..constants import ICON_PATH
from ..github_api import load_source_definitions, probe_sources
from ..installer import (
    find_install_path,
    get_install_dir,
    install_release,
    is_release_installed,
    list_installed,
    remove_install,
    repair_installed,
)
from ..models import Release, Source


CSS = b"""
window {
  background-color: #1a1d23;
}
.sidebar {
  background-color: #12151a;
  border-right: 1px solid #2a303a;
}
.sidebar list {
  background-color: transparent;
}
.brand-logo {
  margin-bottom: 4px;
}
.brand-title {
  font-size: 18px;
  font-weight: 700;
  color: #e8eef7;
}
.brand-sub {
  font-size: 11px;
  color: #8b98a8;
}
.section-title {
  font-size: 16px;
  font-weight: 600;
  color: #e8eef7;
}
.muted {
  color: #8b98a8;
}
.release-row {
  background-color: #222833;
  border-radius: 10px;
  padding: 10px 12px;
  margin: 4px 0;
}
.release-row:hover {
  background-color: #2a3140;
}
.badge-arm {
  background-color: #1f6f4a;
  color: #d8ffe9;
  border-radius: 6px;
  padding: 2px 8px;
  font-size: 11px;
  font-weight: 600;
}
.badge-installed {
  background-color: #2f5d9f;
  color: #dceaff;
  border-radius: 6px;
  padding: 2px 8px;
  font-size: 11px;
  font-weight: 600;
}
.status-bar {
  background-color: #12151a;
  border-top: 1px solid #2a303a;
  padding: 8px 12px;
  color: #a9b4c2;
}
button.suggested-action {
  background-image: linear-gradient(to bottom, #3d8bfd, #2b6fd6);
  color: white;
  border: none;
  border-radius: 8px;
  padding: 6px 14px;
}
button.destructive-action {
  background-image: linear-gradient(to bottom, #d9534f, #b83b37);
  color: white;
  border: none;
  border-radius: 8px;
  padding: 6px 14px;
}
"""


class ReleaseRow(Gtk.ListBoxRow):
    def __init__(self, release: Release, on_install: Callable, on_remove: Callable) -> None:
        super().__init__()
        self.release = release
        self.get_style_context().add_class("release-row")

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        box.set_margin_start(8)
        box.set_margin_end(8)
        box.set_margin_top(6)
        box.set_margin_bottom(6)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text.set_hexpand(True)

        title = Gtk.Label(label=release.title, xalign=0)
        title.get_style_context().add_class("section-title")
        title.set_ellipsize(Pango.EllipsizeMode.END)
        text.pack_start(title, False, False, 0)

        meta = Gtk.Label(label=release.asset_name, xalign=0)
        meta.get_style_context().add_class("muted")
        meta.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        text.pack_start(meta, False, False, 0)

        size_mb = release.size / (1024 * 1024) if release.size else 0
        size_lbl = Gtk.Label(
            label=f"{size_mb:.0f} MB · {release.published_at[:10] if release.published_at else 'unknown date'}",
            xalign=0,
        )
        size_lbl.get_style_context().add_class("muted")
        text.pack_start(size_lbl, False, False, 0)

        badges = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        badges.set_valign(Gtk.Align.CENTER)

        arm = Gtk.Label(label="ARM64")
        arm.get_style_context().add_class("badge-arm")
        badges.pack_start(arm, False, False, 0)

        self.installed_badge = Gtk.Label(label="Installed")
        self.installed_badge.get_style_context().add_class("badge-installed")
        badges.pack_start(self.installed_badge, False, False, 0)

        actions = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        actions.set_valign(Gtk.Align.CENTER)

        self.install_btn = Gtk.Button(label="Install")
        self.install_btn.get_style_context().add_class("suggested-action")
        self.install_btn.connect("clicked", lambda *_: on_install(release))
        actions.pack_start(self.install_btn, False, False, 0)

        self.remove_btn = Gtk.Button(label="Remove")
        self.remove_btn.get_style_context().add_class("destructive-action")
        self.remove_btn.connect("clicked", lambda *_: on_remove(release))
        actions.pack_start(self.remove_btn, False, False, 0)

        box.pack_start(text, True, True, 0)
        box.pack_start(badges, False, False, 0)
        box.pack_start(actions, False, False, 0)
        self.add(box)
        self.refresh_state()

    def refresh_state(self) -> None:
        installed = is_release_installed(self.release)
        self.installed_badge.set_visible(installed)
        self.install_btn.set_sensitive(not installed)
        self.install_btn.set_label("Installed" if installed else "Install")
        self.remove_btn.set_sensitive(installed)


class MainWindow(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(title=__app_name__)
        self.set_default_size(1100, 700)
        self.set_border_width(0)
        self._apply_window_icon()

        self.sources: list[Source] = []
        self.current_source: Optional[Source] = None
        self._busy = False
        self._cancel = False

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        screen = Gdk.Screen.get_default()
        Gtk.StyleContext.add_provider_for_screen(
            screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(root)

        paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        paned.set_wide_handle(True)
        root.pack_start(paned, True, True, 0)

        # Sidebar
        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        sidebar.get_style_context().add_class("sidebar")
        sidebar.set_size_request(280, -1)
        sidebar.set_margin_top(16)
        sidebar.set_margin_bottom(16)
        sidebar.set_margin_start(16)
        sidebar.set_margin_end(8)

        logo = self._make_logo_image(128)
        if logo is not None:
            logo.get_style_context().add_class("brand-logo")
            logo.set_halign(Gtk.Align.CENTER)
            sidebar.pack_start(logo, False, False, 0)

        brand = Gtk.Label(label=__app_name__, xalign=0)
        brand.get_style_context().add_class("brand-title")
        brand.set_line_wrap(True)
        brand.set_justify(Gtk.Justification.CENTER)
        brand.set_halign(Gtk.Align.CENTER)
        brand.set_xalign(0.5)
        sidebar.pack_start(brand, False, False, 0)

        sub = Gtk.Label(label=f"v{__version__} · ARM64 Proton only", xalign=0)
        sub.get_style_context().add_class("brand-sub")
        sub.set_halign(Gtk.Align.CENTER)
        sub.set_xalign(0.5)
        sidebar.pack_start(sub, False, False, 0)

        install_hint = Gtk.Label(
            label=f"Installs to\n{get_install_dir()}",
            xalign=0,
        )
        install_hint.get_style_context().add_class("muted")
        install_hint.set_line_wrap(True)
        sidebar.pack_start(install_hint, False, False, 8)

        self.source_list = Gtk.ListBox()
        self.source_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.source_list.connect("row-selected", self._on_source_selected)
        scroll_side = Gtk.ScrolledWindow()
        scroll_side.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll_side.add(self.source_list)
        sidebar.pack_start(scroll_side, True, True, 0)

        btn_row = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        refresh_btn = Gtk.Button(label="Refresh sources")
        refresh_btn.connect("clicked", lambda *_: self.reload_sources())
        repair_btn = Gtk.Button(label="Repair installed (ARM fixes)")
        repair_btn.connect("clicked", lambda *_: self.repair_all())
        btn_row.pack_start(refresh_btn, False, False, 0)
        btn_row.pack_start(repair_btn, False, False, 0)
        sidebar.pack_start(btn_row, False, False, 0)

        paned.pack1(sidebar, False, False)

        # Main
        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        main.set_margin_top(16)
        main.set_margin_bottom(8)
        main.set_margin_start(8)
        main.set_margin_end(16)

        self.header = Gtk.Label(label="Loading ARM Proton sources…", xalign=0)
        self.header.get_style_context().add_class("section-title")
        main.pack_start(self.header, False, False, 0)

        self.description = Gtk.Label(label="", xalign=0)
        self.description.get_style_context().add_class("muted")
        self.description.set_line_wrap(True)
        main.pack_start(self.description, False, False, 0)

        self.release_list = Gtk.ListBox()
        self.release_list.set_selection_mode(Gtk.SelectionMode.NONE)
        self.release_list.set_header_func(lambda *_: None)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(self.release_list)
        main.pack_start(scroll, True, True, 0)

        installed_title = Gtk.Label(label="Installed in compatibilitytools.d", xalign=0)
        installed_title.get_style_context().add_class("section-title")
        main.pack_start(installed_title, False, False, 0)

        self.installed_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        main.pack_start(self.installed_box, False, False, 0)

        paned.pack2(main, True, False)

        self.status = Gtk.Label(label="Ready", xalign=0)
        self.status.get_style_context().add_class("status-bar")
        root.pack_start(self.status, False, False, 0)

        self.progress = Gtk.ProgressBar()
        self.progress.set_show_text(True)
        self.progress.set_fraction(0)
        self.progress.set_no_show_all(True)
        root.pack_start(self.progress, False, False, 0)

        self.connect("destroy", Gtk.main_quit)
        self.reload_sources()
        self.refresh_installed()

    def _apply_window_icon(self) -> None:
        if not ICON_PATH.is_file():
            return
        try:
            icon = GdkPixbuf.Pixbuf.new_from_file(str(ICON_PATH))
            self.set_icon(icon)
            # Also register common sizes for taskbars / alt-tab.
            icons_dir = ICON_PATH.parent
            list_icons = []
            for size in (16, 24, 32, 48, 64, 128, 256):
                sized = icons_dir / f"eparm-{size}.png"
                path = sized if sized.is_file() else ICON_PATH
                list_icons.append(GdkPixbuf.Pixbuf.new_from_file_at_size(str(path), size, size))
            if list_icons:
                self.set_icon_list(list_icons)
        except Exception:
            pass

    @staticmethod
    def _make_logo_image(pixel_size: int = 128) -> Optional[Gtk.Image]:
        if not ICON_PATH.is_file():
            return None
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_size(str(ICON_PATH), pixel_size, pixel_size)
            image = Gtk.Image.new_from_pixbuf(pixbuf)
            return image
        except Exception:
            return None

    def set_status(self, text: str) -> None:
        self.status.set_text(text)

    def reload_sources(self) -> None:
        if self._busy:
            return
        self._busy = True
        self.set_status("Probing Proton sources for ARM builds…")
        self.header.set_text("Checking sources…")
        self._clear_list(self.source_list)
        self._clear_list(self.release_list)

        def worker() -> None:
            try:
                defs = load_source_definitions()
                # Probe all; UI only shows ones with ARM.
                available = probe_sources(defs)
                discarded = [s for s in defs if not s.has_arm]
                GLib.idle_add(self._on_sources_loaded, available, discarded)
            except Exception as exc:  # noqa: BLE001
                GLib.idle_add(self._on_sources_failed, str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def _on_sources_failed(self, error: str) -> bool:
        self._busy = False
        self.set_status(f"Failed to load sources: {error}")
        self.header.set_text("Could not load sources")
        return False

    def _on_sources_loaded(self, available: list[Source], discarded: list[Source]) -> bool:
        self._busy = False
        self.sources = available
        self._clear_list(self.source_list)

        for source in available:
            row = Gtk.ListBoxRow()
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            box.set_margin_top(8)
            box.set_margin_bottom(8)
            box.set_margin_start(8)
            box.set_margin_end(8)
            title = Gtk.Label(label=source.title, xalign=0)
            title.get_style_context().add_class("section-title")
            count = Gtk.Label(label=f"{len(source.releases)} ARM release(s)", xalign=0)
            count.get_style_context().add_class("muted")
            box.pack_start(title, False, False, 0)
            box.pack_start(count, False, False, 0)
            row.add(box)
            row.source = source  # type: ignore[attr-defined]
            self.source_list.add(row)

        self.source_list.show_all()

        discarded_names = ", ".join(s.title for s in discarded) or "none"
        self.set_status(
            f"Showing {len(available)} ARM source(s). Discarded (no ARM): {discarded_names}"
        )

        if available:
            first = self.source_list.get_row_at_index(0)
            self.source_list.select_row(first)
        else:
            self.header.set_text("No Proton ARM sources found")
            self.description.set_text(
                "None of the configured Proton download sources currently publish ARM builds."
            )
        return False

    def _on_source_selected(self, _list: Gtk.ListBox, row: Optional[Gtk.ListBoxRow]) -> None:
        if row is None:
            return
        source: Source = row.source  # type: ignore[attr-defined]
        self.current_source = source
        self.header.set_text(source.title)
        self.description.set_text(source.description)
        self._populate_releases(source)

    def _populate_releases(self, source: Source) -> None:
        self._clear_list(self.release_list)
        for release in source.releases:
            row = ReleaseRow(release, self.start_install, self.start_remove)
            self.release_list.add(row)
        self.release_list.show_all()

    def refresh_installed(self) -> None:
        for child in self.installed_box.get_children():
            self.installed_box.remove(child)
        installed = list_installed()
        if not installed:
            lbl = Gtk.Label(label="(none)", xalign=0)
            lbl.get_style_context().add_class("muted")
            self.installed_box.pack_start(lbl, False, False, 0)
        else:
            for path in installed:
                lbl = Gtk.Label(label=str(path), xalign=0)
                lbl.get_style_context().add_class("muted")
                lbl.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
                self.installed_box.pack_start(lbl, False, False, 0)
        self.installed_box.show_all()

        for row in self.release_list.get_children():
            if isinstance(row, ReleaseRow):
                row.refresh_state()

    def start_install(self, release: Release) -> None:
        if self._busy:
            return
        self._busy = True
        self._cancel = False
        self.progress.show()
        self.progress.set_fraction(0)
        self.progress.set_text("Starting…")
        self.set_status(f"Installing {release.title} ({release.asset_name})…")

        def worker() -> None:
            try:
                def prog(stage: str, fraction: float) -> None:
                    GLib.idle_add(self._update_progress, stage, fraction)

                path = install_release(
                    release,
                    progress=prog,
                    cancel_check=lambda: self._cancel,
                )
                GLib.idle_add(self._install_done, release, str(path), None)
            except Exception as exc:  # noqa: BLE001
                GLib.idle_add(self._install_done, release, None, str(exc))

        threading.Thread(target=worker, daemon=True).start()

    def _update_progress(self, stage: str, fraction: float) -> bool:
        if fraction < 0:
            self.progress.pulse()
            self.progress.set_text(stage)
        else:
            self.progress.set_fraction(max(0.0, min(fraction, 1.0)))
            self.progress.set_text(f"{stage} ({int(max(0, fraction) * 100)}%)")
        return False

    def _install_done(self, release: Release, path: Optional[str], error: Optional[str]) -> bool:
        self._busy = False
        self.progress.hide()
        if error:
            self.set_status(f"Install failed: {error}")
            self._alert("Install failed", error)
        else:
            self.set_status(
                f"Installed {release.title} → {path} (toolmanifest cleaned, bin→bin-arm64)"
            )
            self.refresh_installed()
        return False

    def start_remove(self, release: Release) -> None:
        if self._busy:
            return
        path = find_install_path(release)
        if not path:
            self.set_status(f"{release.title} is not installed")
            return
        dialog = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text=f"Remove {path.name}?",
        )
        dialog.format_secondary_text(str(path))
        response = dialog.run()
        dialog.destroy()
        if response != Gtk.ResponseType.OK:
            return
        try:
            remove_install(path)
            self.set_status(f"Removed {path.name}")
            self.refresh_installed()
        except Exception as exc:  # noqa: BLE001
            self.set_status(f"Remove failed: {exc}")
            self._alert("Remove failed", str(exc))

    def repair_all(self) -> None:
        if self._busy:
            return
        results = repair_installed()
        if not results:
            self.set_status("No installed Proton tools to repair")
            return
        changed = []
        for name, flags in results:
            parts = []
            if flags.get("toolmanifest_patched"):
                parts.append("toolmanifest")
            if flags.get("bin_symlink_created"):
                parts.append("bin symlink")
            if parts:
                changed.append(f"{name}: {', '.join(parts)}")
        if changed:
            self.set_status("Repaired: " + "; ".join(changed))
        else:
            self.set_status("All installed tools already have ARM fixes applied")

    def _alert(self, title: str, message: str) -> None:
        dialog = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.CLOSE,
            text=title,
        )
        dialog.format_secondary_text(message)
        dialog.run()
        dialog.destroy()

    @staticmethod
    def _clear_list(listbox: Gtk.ListBox) -> None:
        for child in listbox.get_children():
            listbox.remove(child)


def run_gui() -> None:
    if not Gtk.init_check(None)[0]:
        raise SystemExit(
            "GTK could not be initialized. Run from a graphical session, or use CLI commands "
            "(sources / install / installed / repair)."
        )
    win = MainWindow()
    win.show_all()
    win.progress.hide()
    Gtk.main()
