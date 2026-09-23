from __future__ import annotations

import threading
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, Pango  # noqa: E402

from ..constants import APP_NAME, APP_VERSION, CACHE_DIR, DISCLAIMER, ICON_PATH
from ..cover_fetch import CoverCandidate, download_cover, search_covers
from ..shortcuts_vdf import add_shortcut, install_grid_art
from ..steam_paths import find_userdata_dir, shortcuts_path


CSS = b"""
window { background-color: #1a1d23; }
.card {
  background-color: #222833;
  border-radius: 12px;
  padding: 16px;
}
.title { font-size: 18px; font-weight: 700; color: #e8eef7; }
.muted { color: #8b98a8; font-size: 12px; }
.disclaimer {
  background-color: #2a2418;
  border: 1px solid #5c4a1f;
  border-radius: 8px;
  padding: 10px 12px;
  color: #f0dca8;
  font-size: 12px;
}
.cover-row {
  background-color: #2a3140;
  border-radius: 8px;
  padding: 8px;
  margin: 4px 0;
}
button.suggested-action {
  background-image: linear-gradient(to bottom, #3d8bfd, #2b6fd6);
  color: white;
  border: none;
  border-radius: 8px;
  padding: 8px 18px;
  font-weight: 600;
}
"""


class MainWindow(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application) -> None:
        super().__init__(application=app, title=APP_NAME, default_width=760, default_height=620)
        self._cover_path: Path | None = None
        self._cover_candidates: list[CoverCandidate] = []

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        outer.set_margin_start(16)
        outer.set_margin_end(16)
        outer.set_margin_top(16)
        outer.set_margin_bottom(16)
        self.add(outer)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        if ICON_PATH.is_file():
            img = Gtk.Image.new_from_pixbuf(
                GdkPixbuf.Pixbuf.new_from_file_at_scale(str(ICON_PATH), 48, 48, True)
            )
            header.pack_start(img, False, False, 0)
        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title = Gtk.Label(label=APP_NAME, xalign=0)
        title.get_style_context().add_class("title")
        sub = Gtk.Label(label=f"v{APP_VERSION} — add DRM-free games to Steam", xalign=0)
        sub.get_style_context().add_class("muted")
        title_box.pack_start(title, False, False, 0)
        title_box.pack_start(sub, False, False, 0)
        header.pack_start(title_box, True, True, 0)
        outer.pack_start(header, False, False, 0)

        disc = Gtk.Label(label=DISCLAIMER, wrap=True, xalign=0, max_width_chars=80)
        disc.get_style_context().add_class("disclaimer")
        outer.pack_start(disc, False, False, 0)

        card = Gtk.Grid()
        card.set_column_spacing(12)
        card.set_row_spacing(10)
        card.get_style_context().add_class("card")

        row = 0
        card.attach(Gtk.Label(label="Game name", halign=Gtk.Align.START), 0, row, 1, 1)
        self.entry_name = Gtk.Entry()
        self.entry_name.set_placeholder_text("e.g. Celeste (GOG)")
        self.entry_name.connect("changed", self._on_name_changed)
        card.attach(self.entry_name, 1, row, 1, 1)
        row += 1

        card.attach(Gtk.Label(label="Executable", halign=Gtk.Align.START), 0, row, 1, 1)
        exe_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.entry_exe = Gtk.Entry()
        self.entry_exe.set_placeholder_text("/path/to/game.exe or native Linux ARM binary")
        self.entry_exe.connect("changed", self._on_exe_changed)
        exe_box.pack_start(self.entry_exe, True, True, 0)
        btn_browse = Gtk.Button(label="Browse…")
        btn_browse.connect("clicked", self._on_browse_exe)
        exe_box.pack_start(btn_browse, False, False, 0)
        card.attach(exe_box, 1, row, 1, 1)
        row += 1

        self.launch_hint = Gtk.Label(label="", xalign=0, wrap=True)
        self.launch_hint.get_style_context().add_class("muted")
        card.attach(self.launch_hint, 1, row, 1, 1)
        row += 1

        card.attach(Gtk.Label(label="Cover art", halign=Gtk.Align.START), 0, row, 1, 1)
        cover_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self.cover_image = Gtk.Image.new_from_icon_name("applications-games", Gtk.IconSize.DIALOG)
        self.cover_image.set_size_request(120, 160)
        cover_box.pack_start(self.cover_image, False, False, 0)
        cover_actions = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        btn_search = Gtk.Button(label="Search online (Lutris)")
        btn_search.connect("clicked", self._on_search_covers)
        cover_actions.pack_start(btn_search, False, False, 0)
        btn_manual = Gtk.Button(label="Browse image…")
        btn_manual.connect("clicked", self._on_browse_cover)
        cover_actions.pack_start(btn_manual, False, False, 0)
        btn_clear = Gtk.Button(label="Clear cover")
        btn_clear.connect("clicked", self._on_clear_cover)
        cover_actions.pack_start(btn_clear, False, False, 0)
        cover_box.pack_start(cover_actions, True, True, 0)
        card.attach(cover_box, 1, row, 1, 1)
        row += 1

        self.cover_results = Gtk.ListBox()
        self.cover_results.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.cover_results.connect("row-activated", self._on_cover_selected)
        self.cover_results.set_no_show_all(True)
        card.attach(self.cover_results, 1, row, 1, 1)
        row += 1

        outer.pack_start(card, True, True, 0)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        actions.set_halign(Gtk.Align.END)
        btn_add = Gtk.Button(label="Add to Steam library")
        btn_add.get_style_context().add_class("suggested-action")
        btn_add.connect("clicked", self._on_add)
        actions.pack_start(btn_add, False, False, 0)
        outer.pack_start(actions, False, False, 0)

        self.status = Gtk.Label(label="", xalign=0)
        self.status.get_style_context().add_class("muted")
        outer.pack_start(self.status, False, False, 0)

        steam_cfg = shortcuts_path()
        if steam_cfg:
            self._set_status(f"Steam userdata: {steam_cfg.parent.parent}")
        else:
            self._set_status("Warning: Steam userdata not found — log into Steam once first.")
        self.launch_hint.set_text(self._launch_hint_for(""))

    def _set_status(self, text: str) -> None:
        self.status.set_text(text)

    def _on_name_changed(self, *_args) -> None:
        pass

    def _launch_hint_for(self, exe: str) -> str:
        path = Path(exe)
        if not exe:
            return "Windows .exe → assign Proton in Steam after add. Native Linux ARM binary → direct launch."
        if path.suffix.lower() == ".exe":
            return "Windows game: after restart, open the game in Steam → Properties → Compatibility → force Proton."
        return "Native Linux binary: Steam launches it directly — do not enable Proton unless you know you need it."

    def _on_exe_changed(self, *_args) -> None:
        self.launch_hint.set_text(self._launch_hint_for(self.entry_exe.get_text().strip()))

    def _on_browse_exe(self, _btn) -> None:
        dialog = Gtk.FileChooserDialog(
            title="Select game executable",
            parent=self,
            action=Gtk.FileChooserAction.OPEN,
        )
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
        filter_all = Gtk.FileFilter()
        filter_all.set_name("Executables")
        for pattern in ("*.exe", "*.sh", "*.run", "*.AppImage"):
            filter_all.add_pattern(pattern)
        filter_all.add_pattern("*")
        dialog.add_filter(filter_all)
        if dialog.run() == Gtk.ResponseType.OK:
            path = dialog.get_filename()
            if path:
                self.entry_exe.set_text(path)
                self.launch_hint.set_text(self._launch_hint_for(path))
                if not self.entry_name.get_text().strip():
                    self.entry_name.set_text(Path(path).stem.replace("_", " "))
        dialog.destroy()

    def _on_browse_cover(self, _btn) -> None:
        dialog = Gtk.FileChooserDialog(
            title="Select cover image",
            parent=self,
            action=Gtk.FileChooserAction.OPEN,
        )
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
        filt = Gtk.FileFilter()
        filt.set_name("Images")
        for pattern in ("*.png", "*.jpg", "*.jpeg", "*.webp"):
            filt.add_pattern(pattern)
        dialog.add_filter(filt)
        if dialog.run() == Gtk.ResponseType.OK:
            path = dialog.get_filename()
            if path:
                self._apply_cover_path(Path(path))
        dialog.destroy()

    def _on_clear_cover(self, _btn) -> None:
        self._cover_path = None
        self.cover_image.set_from_icon_name("applications-games", Gtk.IconSize.DIALOG)

    def _apply_cover_path(self, path: Path) -> None:
        self._cover_path = path
        try:
            pix = GdkPixbuf.Pixbuf.new_from_file_at_scale(str(path), 120, 160, True)
            self.cover_image.set_from_pixbuf(pix)
        except GLib.GError:
            self._set_status(f"Could not load image: {path}")

    def _on_search_covers(self, _btn) -> None:
        query = self.entry_name.get_text().strip()
        if not query:
            self._set_status("Enter a game name first to search covers.")
            return
        self._set_status(f"Searching covers for “{query}”…")
        for child in self.cover_results.get_children():
            self.cover_results.remove(child)

        def work() -> None:
            results = search_covers(query)

            def finish() -> None:
                self._cover_candidates = results
                for child in self.cover_results.get_children():
                    self.cover_results.remove(child)
                if not results:
                    self._set_status("No covers found — use Browse image.")
                    self.cover_results.hide()
                    return
                for item in results:
                    row = Gtk.ListBoxRow()
                    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
                    box.set_margin_top(6)
                    box.set_margin_bottom(6)
                    if item.icon_url:
                        try:
                            cache = CACHE_DIR / "covers"
                            cache.mkdir(parents=True, exist_ok=True)
                            local = download_cover(item.icon_url, cache / f"{item.slug or item.title}.jpg")
                            pix = GdkPixbuf.Pixbuf.new_from_file_at_scale(str(local), 48, 48, True)
                            box.pack_start(Gtk.Image.new_from_pixbuf(pix), False, False, 0)
                        except Exception:
                            pass
                    lbl = Gtk.Label(label=item.title, xalign=0)
                    lbl.set_ellipsize(Pango.EllipsizeMode.END)
                    box.pack_start(lbl, True, True, 0)
                    row.add(box)
                    row.candidate = item  # type: ignore[attr-defined]
                    self.cover_results.add(row)
                self.cover_results.show_all()
                self._set_status(f"Found {len(results)} cover(s) — click one to use it.")

            GLib.idle_add(finish)

        threading.Thread(target=work, daemon=True).start()

    def _on_cover_selected(self, _box, row) -> None:
        candidate: CoverCandidate = row.candidate  # type: ignore[attr-defined]
        self._set_status(f"Downloading cover: {candidate.title}…")

        def work() -> None:
            try:
                cache = CACHE_DIR / "covers"
                cache.mkdir(parents=True, exist_ok=True)
                url = candidate.banner_url or candidate.icon_url
                local = download_cover(url, cache / f"{candidate.slug or candidate.title}-banner.jpg")

                def finish() -> None:
                    self._apply_cover_path(local)
                    self._set_status(f"Cover set: {candidate.title}")

                GLib.idle_add(finish)
            except Exception as exc:
                GLib.idle_add(lambda: self._set_status(f"Cover download failed: {exc}"))

        threading.Thread(target=work, daemon=True).start()

    def _on_add(self, _btn) -> None:
        name = self.entry_name.get_text().strip()
        exe = self.entry_exe.get_text().strip()
        if not name:
            self._set_status("Enter a game name.")
            return
        if not exe or not Path(exe).is_file():
            self._set_status("Select a valid executable file.")
            return

        sc_path = shortcuts_path()
        if not sc_path:
            self._set_status("Steam userdata not found. Launch Steam and log in first.")
            return

        try:
            app_id = add_shortcut(sc_path, name, exe)
        except Exception as exc:
            self._set_status(f"Failed to write shortcuts.vdf: {exc}")
            return

        userdata = find_userdata_dir()
        if userdata and self._cover_path and self._cover_path.is_file():
            try:
                install_grid_art(userdata, app_id, self._cover_path)
            except Exception as exc:
                self._set_status(f"Shortcut added but cover failed: {exc}")
                return

        hint = (
            " Restart Steam, then force Proton in game Properties (Compatibility)."
            if Path(exe).suffix.lower() == ".exe"
            else " Restart Steam — native ARM binary, no Proton needed."
        )
        self._set_status(f"Added “{name}” (appid {app_id}).{hint}")


def run_gui() -> None:
    app = Gtk.Application(application_id="io.steamosubuntu.nosteamgames")

    def on_activate(application: Gtk.Application) -> None:
        win = MainWindow(application)
        win.show_all()

    app.connect("activate", on_activate)
    app.run(None)
