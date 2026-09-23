"""GTK 3 main window for MESA Easy Manager."""

from __future__ import annotations

import threading
import traceback
from dataclasses import dataclass
from enum import Enum

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk, Pango

from mesa_easy_manager import __version__
from mesa_easy_manager.compiler import compile_version
from mesa_easy_manager.constants import (
    APP_NAME,
    DEVEL_VERSION,
    DRIVERS_DIR,
    MESA_GIT_URL,
    MESA_NEWS_URL,
    RELNOTES_URL,
    SYSTEM_LIBRARY,
    is_steamos,
)
from mesa_easy_manager.installer import install_version, restore_system_default
from mesa_easy_manager.local_store import (
    detect_active_source,
    has_original_backup,
    list_local_versions,
    local_version_set,
)
from mesa_easy_manager.rocknix import (
    PROFILE_LABELS,
    CompileProfile,
    RocknixPatch,
    fetch_patches,
    patch_sources_summary,
    platform_sources,
    summarize_patches,
)
from mesa_easy_manager.versions import (
    RemoteVersion,
    fetch_remote_versions,
    filter_missing,
    is_devel,
    version_sort_key,
)


class PatchChoice(Enum):
    APPLY = "apply"
    SKIP = "skip"
    CANCEL = "cancel"


@dataclass
class VersionRow:
    version: str
    local: bool
    active: bool


class MainWindow(Gtk.Window):
    def __init__(self) -> None:
        super().__init__(title=APP_NAME)
        self.set_default_size(960, 680)
        self.set_border_width(12)

        self._remote: list[RemoteVersion] = []
        self._busy = False

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.add(root)

        header = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        title = Gtk.Label()
        title.set_markup(f"<span size='x-large'><b>{APP_NAME}</b></span>")
        title.set_xalign(0)
        subtitle = Gtk.Label(
            label="Replace only libvulkan_freedreno.so — leave the rest of system Mesa untouched."
        )
        subtitle.set_xalign(0)
        subtitle.set_line_wrap(True)
        header.pack_start(title, False, False, 0)
        header.pack_start(subtitle, False, False, 0)
        root.pack_start(header, False, False, 0)

        if is_steamos():
            pw = Gtk.InfoBar()
            pw.set_message_type(Gtk.MessageType.WARNING)
            pw.set_show_close_button(False)
            pw_label = Gtk.Label()
            pw_label.set_line_wrap(True)
            pw_label.set_xalign(0)
            pw_label.set_markup(
                "<b>SteamOS password required</b>\n"
                "Official SteamOS ships the desktop user with no password. "
                "Set one later with <tt>passwd</tt> in Konsole or Users in System Settings.\n"
                "Installing or restoring drivers asks for that password (pkexec). "
                "Without it the Vulkan library will not be installed."
            )
            pw.get_content_area().add(pw_label)
            root.pack_start(pw, False, False, 0)

        self.alert_box = Gtk.InfoBar()
        self.alert_box.set_message_type(Gtk.MessageType.WARNING)
        self.alert_box.set_show_close_button(False)
        self.alert_label = Gtk.Label(label="")
        self.alert_label.set_line_wrap(True)
        self.alert_label.set_xalign(0)
        content = self.alert_box.get_content_area()
        content.add(self.alert_label)
        compile_latest = self.alert_box.add_button("Compile latest missing", Gtk.ResponseType.ACCEPT)
        compile_latest.connect("clicked", self._on_compile_latest_missing)
        self.alert_box.connect("response", self._on_alert_response)
        self.alert_box.set_no_show_all(True)
        self.alert_box.hide()
        root.pack_start(self.alert_box, False, False, 0)

        status_grid = Gtk.Grid(column_spacing=12, row_spacing=4)
        self.status_active = Gtk.Label(label="Active: …")
        self.status_active.set_xalign(0)
        self.status_system = Gtk.Label(label=f"System library: {SYSTEM_LIBRARY}")
        self.status_system.set_xalign(0)
        self.status_system.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        self.status_store = Gtk.Label(label=f"Local store: {DRIVERS_DIR}")
        self.status_store.set_xalign(0)
        self.status_backup = Gtk.Label(label="Original backup: …")
        self.status_backup.set_xalign(0)
        status_grid.attach(self.status_active, 0, 0, 1, 1)
        status_grid.attach(self.status_backup, 1, 0, 1, 1)
        status_grid.attach(self.status_system, 0, 1, 2, 1)
        status_grid.attach(self.status_store, 0, 2, 2, 1)
        root.pack_start(status_grid, False, False, 0)

        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.refresh_btn = Gtk.Button(label="Refresh versions")
        self.refresh_btn.connect("clicked", lambda *_: self.refresh_async())
        self.restore_btn = Gtk.Button(label="Restore MESA system default")
        self.restore_btn.connect("clicked", self._on_restore)
        toolbar.pack_start(self.refresh_btn, False, False, 0)
        toolbar.pack_start(self.restore_btn, False, False, 0)
        toolbar.pack_end(Gtk.Label(label=f"v{__version__}"), False, False, 0)
        root.pack_start(toolbar, False, False, 0)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_vexpand(True)
        root.pack_start(scrolled, True, True, 0)

        self.list_box = Gtk.ListBox()
        self.list_box.set_selection_mode(Gtk.SelectionMode.NONE)
        scrolled.add(self.list_box)

        log_frame = Gtk.Frame(label="Activity log")
        self.log_view = Gtk.TextView()
        self.log_view.set_editable(False)
        self.log_view.set_cursor_visible(False)
        self.log_view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.log_buffer = self.log_view.get_buffer()
        log_scroll = Gtk.ScrolledWindow()
        log_scroll.set_min_content_height(140)
        log_scroll.add(self.log_view)
        log_frame.add(log_scroll)
        root.pack_start(log_frame, False, False, 0)

        self.connect("destroy", Gtk.main_quit)
        self.append_log(f"Welcome to {APP_NAME}. Sources: {MESA_NEWS_URL} / {RELNOTES_URL}")
        self.append_log(f"Devel tip: {MESA_GIT_URL}")
        self.append_log("Compile profiles: Generic | SM8550 (Odin 2/Thor/R-Pocket 6) | SM8750 (Odin 3)")
        self.refresh_async()

    # --- UI helpers -----------------------------------------------------

    def append_log(self, message: str) -> None:
        end = self.log_buffer.get_end_iter()
        self.log_buffer.insert(end, message.rstrip() + "\n")
        mark = self.log_buffer.create_mark(None, self.log_buffer.get_end_iter(), False)
        self.log_view.scroll_to_mark(mark, 0.0, True, 0.0, 1.0)

    def set_busy(self, busy: bool) -> None:
        self._busy = busy
        self.refresh_btn.set_sensitive(not busy)
        self.restore_btn.set_sensitive(not busy)
        self.list_box.set_sensitive(not busy)

    def show_error(self, title: str, message: str) -> None:
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text=title,
        )
        dialog.format_secondary_text(message)
        dialog.run()
        dialog.destroy()

    def confirm(self, title: str, message: str) -> bool:
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text=title,
        )
        dialog.format_secondary_text(message)
        response = dialog.run()
        dialog.destroy()
        return response == Gtk.ResponseType.OK

    def ask_compile_profile(self, version: str) -> CompileProfile | None:
        """Choose Generic / SM8550 / SM8750 before compile."""
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.NONE,
            text=f"Compile profile for Mesa {version}",
        )
        dialog.format_secondary_text(
            "Choose how to build this library:\n\n"
            "• Generic — stock Mesa, no device patches (other devices may work).\n"
            "• SM8550 — Odin 2 / Thor / R-Pocket 6 "
            "(bundled offline patches: Batocera sync + ROCKNIX UBO).\n"
            "• SM8750 — Odin 3 "
            "(bundled offline patches: A830 + Batocera sync + ROCKNIX UBO).\n\n"
            "For SM8550 / SM8750 you will next choose whether to apply patches.\n"
            "Patches are shipped inside the app — nothing is downloaded from GitHub."
        )
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("Generic", 100)
        dialog.add_button("SM8550", 101)
        dialog.add_button("SM8750", 102)
        dialog.set_default_response(101)
        response = dialog.run()
        dialog.destroy()
        if response == 100:
            return CompileProfile.GENERIC
        if response == 101:
            return CompileProfile.SM8550
        if response == 102:
            return CompileProfile.SM8750
        return None

    def ask_patch_choice(
        self,
        version: str,
        platform: str,
        patches: list[RocknixPatch],
        *,
        recompile: bool,
    ) -> PatchChoice:
        action = "Recompile" if recompile else "Compile"
        src = platform_sources(platform)
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.NONE,
            text=f"{platform} patches for Mesa {version}",
        )
        lines = [
            f"Devices: {src.devices}",
            "",
            "Patches are bundled offline under mesa_easy_manager/patches/",
            "(no GitHub download at compile time).",
            "",
            "Attribution (original authors / mirrors):",
            f"  Batocera fork: {src.batocera_url}",
            f"  ROCKNIX:       {src.rocknix_url}",
            "",
            "Patches that will be applied:",
            summarize_patches(patches),
            "",
            "If you skip patches, Vulkan may fail or show graphical glitches",
            "(on SM8550, vkcube often aborts without the Batocera sync fix).",
            "If you apply patches, some games may still break — you can Recompile later.",
            "",
            "Note: this app installs libvulkan_freedreno.so only. For best Plasma",
            "Wayland results, prefer a full Mesa stack (EGL/GBM matching Turnip).",
            "",
            f"Choose how to {action.lower()} Mesa {version}:",
        ]
        dialog.format_secondary_text("\n".join(lines))
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("Compile without patches", Gtk.ResponseType.REJECT)
        dialog.add_button("Apply patches & compile", Gtk.ResponseType.ACCEPT)
        dialog.set_default_response(Gtk.ResponseType.ACCEPT)

        response = dialog.run()
        dialog.destroy()
        if response == Gtk.ResponseType.ACCEPT:
            return PatchChoice.APPLY
        if response == Gtk.ResponseType.REJECT:
            return PatchChoice.SKIP
        return PatchChoice.CANCEL

    # --- data refresh ---------------------------------------------------

    def refresh_async(self) -> None:
        if self._busy:
            return
        self.set_busy(True)
        self.append_log("Refreshing Mesa release list…")

        def worker() -> None:
            error: Exception | None = None
            remote: list[RemoteVersion] = []
            try:
                remote = fetch_remote_versions()
            except Exception as exc:  # noqa: BLE001
                error = exc
            GLib.idle_add(self._on_refresh_done, remote, error)

        threading.Thread(target=worker, daemon=True).start()

    def _on_refresh_done(self, remote: list[RemoteVersion], error: Exception | None) -> bool:
        self.set_busy(False)
        if error:
            self.append_log(f"Failed to fetch releases: {error}")
            self.show_error("Could not fetch Mesa versions", str(error))
            self._remote = [RemoteVersion(version=DEVEL_VERSION)]
        else:
            self._remote = remote
            numeric = [r for r in remote if not r.is_devel]
            self.append_log(
                f"Found {len(numeric)} Mesa versions >= 25.0.0 (+ devel tip)"
            )
        self.rebuild_list()
        return False

    def rebuild_list(self) -> None:
        for child in self.list_box.get_children():
            self.list_box.remove(child)

        local = local_version_set()
        active = detect_active_source()

        if active == "original-system-lib":
            active_text = "system default (original backup)"
        elif active:
            active_text = f"Mesa {active}"
        else:
            active_text = "unknown / not matching a stored library"

        self.status_active.set_text(f"Active: {active_text}")
        self.status_backup.set_text(
            "Original backup: present" if has_original_backup() else "Original backup: not created yet"
        )

        missing = [
            item
            for item in filter_missing(self._remote, local)
            if not is_devel(item.version)
        ]
        if missing:
            newest = missing[0].version
            extra = f" (+{len(missing) - 1} more)" if len(missing) > 1 else ""
            self.alert_label.set_text(
                f"New Mesa version available and not stored locally: {newest}{extra}. "
                f"You can compile it into {DRIVERS_DIR}."
            )
            self.alert_box.show_all()
            self.alert_box.show()
        else:
            self.alert_box.hide()

        versions: dict[str, VersionRow] = {}
        for item in self._remote:
            versions[item.version] = VersionRow(
                version=item.version,
                local=item.version in local,
                active=active == item.version,
            )
        for item in list_local_versions():
            versions[item.version] = VersionRow(
                version=item.version,
                local=True,
                active=active == item.version,
            )

        ordered = sorted(
            versions.values(),
            key=lambda row: version_sort_key(row.version),
            reverse=True,
        )
        if not ordered:
            placeholder = Gtk.Label(label="No versions to show yet. Click Refresh versions.")
            placeholder.set_margin_top(24)
            placeholder.set_margin_bottom(24)
            self.list_box.add(placeholder)
        else:
            for row in ordered:
                self.list_box.add(self._make_row(row))

        self.list_box.show_all()

    def _make_row(self, row: VersionRow) -> Gtk.ListBoxRow:
        widget = Gtk.ListBoxRow()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.set_margin_top(6)
        box.set_margin_bottom(6)
        box.set_margin_start(8)
        box.set_margin_end(8)

        labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title = Gtk.Label()
        mark = "  • active" if row.active else ""
        if is_devel(row.version):
            title.set_markup(f"<b>Mesa devel</b> (git tip){mark}")
        else:
            title.set_markup(f"<b>Mesa {row.version}</b>{mark}")
        title.set_xalign(0)
        if is_devel(row.version):
            if row.local:
                state = "Development build — may be unstable · Install or Recompile"
            else:
                state = "Development tip — may be unstable · compile required"
        elif row.local:
            state = "Stored locally — Install or Recompile"
        else:
            state = "Not stored — compile required"
        detail = Gtk.Label(label=state)
        detail.set_xalign(0)
        detail.get_style_context().add_class("dim-label")
        labels.pack_start(title, False, False, 0)
        labels.pack_start(detail, False, False, 0)
        box.pack_start(labels, True, True, 0)

        if row.local:
            recompile_btn = Gtk.Button(label="Recompile")
            recompile_btn.set_tooltip_text(
                "Rebuild and choose profile / patches again"
            )
            recompile_btn.connect("clicked", self._on_recompile, row.version)
            box.pack_end(recompile_btn, False, False, 0)

            install_btn = Gtk.Button(label="Install")
            install_btn.connect("clicked", self._on_install, row.version)
            if row.active:
                install_btn.set_sensitive(False)
                install_btn.set_tooltip_text("This version is already active")
            box.pack_end(install_btn, False, False, 0)
        else:
            compile_btn = Gtk.Button(label="Compile")
            compile_btn.connect("clicked", self._on_compile, row.version)
            box.pack_end(compile_btn, False, False, 0)

        widget.add(box)
        return widget

    # --- actions --------------------------------------------------------

    def _on_alert_response(self, _bar: Gtk.InfoBar, response: int) -> None:
        if response == Gtk.ResponseType.ACCEPT:
            self._on_compile_latest_missing()

    def _on_compile_latest_missing(self, *_args) -> None:
        local = local_version_set()
        missing = [
            item
            for item in filter_missing(self._remote, local)
            if not is_devel(item.version)
        ]
        if not missing:
            return
        self._start_compile(missing[0].version, recompile=False)

    def _on_compile(self, _button: Gtk.Button, version: str) -> None:
        self._start_compile(version, recompile=False)

    def _on_recompile(self, _button: Gtk.Button, version: str) -> None:
        self._start_compile(version, recompile=True)

    def _start_compile(self, version: str, *, recompile: bool) -> None:
        if self._busy:
            return

        action = "Recompile" if recompile else "Compile"
        if is_devel(version):
            intro = (
                "WARNING: Mesa devel is a rolling development tip from git.\n"
                "It may crash, glitch, or break Vulkan apps.\n\n"
                f"Source: {MESA_GIT_URL}\n"
                f"Stored as: ~/MESA-Drivers/{DEVEL_VERSION}/\n\n"
                "Only use this if you want to test the latest upstream code."
            )
            if not self.confirm(f"{action} Mesa devel (unstable)?", intro):
                return
        else:
            intro = (
                f"This will rebuild Mesa {version} and replace the copy under ~/MESA-Drivers/."
                if recompile
                else (
                    "This downloads the official Mesa source, builds only "
                    "libvulkan_freedreno.so, stores it under ~/MESA-Drivers/, "
                    "then deletes the temporary build directory."
                )
            )
            if not self.confirm(
                f"{action} Mesa {version}?",
                intro
                + "\n\nNext you will choose a compile profile "
                "(Generic / SM8550 / SM8750).\n"
                "The build may take a long time and needs build dependencies installed.",
            ):
                return

        profile = self.ask_compile_profile(version)
        if profile is None:
            self.append_log("Compile cancelled (no profile selected)")
            return

        self.append_log(f"Compile profile: {PROFILE_LABELS[profile]}")

        if profile == CompileProfile.GENERIC:
            self.set_busy(True)
            self._run_compile(version, apply_patches=False, rocknix_patches=[])
            return

        platform = profile.value
        self.set_busy(True)
        self.append_log(f"Loading bundled {platform} patches (offline)…")

        def worker() -> None:
            patches: list[RocknixPatch] = []
            error: Exception | None = None
            try:
                patches = fetch_patches(platform)
            except Exception as exc:  # noqa: BLE001
                error = exc
            GLib.idle_add(
                self._on_patches_checked,
                version,
                recompile,
                platform,
                patches,
                error,
            )

        threading.Thread(target=worker, daemon=True).start()

    def _on_patches_checked(
        self,
        version: str,
        recompile: bool,
        platform: str,
        patches: list[RocknixPatch],
        error: Exception | None,
    ) -> bool:
        if error:
            self.append_log(f"Could not fetch {platform} patches: {error}")
            if not self.confirm(
                f"Could not check {platform} patches",
                f"{error}\n\nContinue compiling without patches?",
            ):
                self.set_busy(False)
                return False
            self.append_log("Continuing without community patches")
            self._run_compile(version, apply_patches=False, rocknix_patches=[])
            return False

        if patches:
            self.append_log(
                f"{platform} patches: {len(patches)} — "
                + ", ".join(p.label for p in patches)
            )
            for line in patch_sources_summary(platform).splitlines():
                self.append_log(f"  {line}")
            choice = self.ask_patch_choice(
                version, platform, patches, recompile=recompile
            )
            if choice == PatchChoice.CANCEL:
                self.append_log("Compile cancelled by user")
                self.set_busy(False)
                return False
            apply_patches = choice == PatchChoice.APPLY
        else:
            self.append_log(f"No {platform} patch files listed")
            if recompile and not self.confirm(
                f"Recompile Mesa {version}?",
                f"No {platform} patches are listed right now.\n"
                "Continue and compile without patches?",
            ):
                self.set_busy(False)
                return False
            apply_patches = False

        self._run_compile(
            version,
            apply_patches=apply_patches,
            rocknix_patches=patches,
        )
        return False

    def _run_compile(
        self,
        version: str,
        *,
        apply_patches: bool,
        rocknix_patches: list[RocknixPatch],
    ) -> None:
        mode = "with patches" if apply_patches else "without patches"
        label = "devel" if is_devel(version) else version
        self.append_log(f"Starting compile for Mesa {label} ({mode})…")

        def worker() -> None:
            error: Exception | None = None
            try:
                compile_version(
                    version,
                    apply_patches=apply_patches,
                    rocknix_patches=rocknix_patches if apply_patches else None,
                    log=lambda msg: GLib.idle_add(self.append_log, msg),
                )
            except Exception as exc:  # noqa: BLE001
                error = exc
                GLib.idle_add(self.append_log, traceback.format_exc())
            GLib.idle_add(self._on_compile_done, version, error)

        threading.Thread(target=worker, daemon=True).start()

    def _on_compile_done(self, version: str, error: Exception | None) -> bool:
        self.set_busy(False)
        label = "devel" if is_devel(version) else version
        if error:
            self.append_log(f"Compile failed for {label}: {error}")
            self.show_error("Compile failed", str(error))
        else:
            self.append_log(f"Compile finished for {label}")
        self.rebuild_list()
        return False

    def _on_install(self, _button: Gtk.Button, version: str) -> None:
        if self._busy:
            return
        warning = ""
        if is_devel(version):
            warning = (
                "\n\nWARNING: This is a development build and may be unstable."
            )
        if not self.confirm(
            f"Install Mesa {version}?",
            f"This will replace:\n{SYSTEM_LIBRARY}\n\n"
            "Your system password will be requested.\n"
            "Official SteamOS has no password until you create one "
            "(passwd / System Settings → Users). "
            "Without that password the driver will not be installed.\n"
            "On the first change, the current system library is backed up to "
            f"{DRIVERS_DIR}/original-system-lib/."
            + warning,
        ):
            return

        self.set_busy(True)
        self.append_log(f"Installing Mesa {version} (authentication required)…")

        def worker() -> None:
            error: Exception | None = None
            try:
                install_version(version)
            except Exception as exc:  # noqa: BLE001
                error = exc
            GLib.idle_add(self._on_install_done, version, error)

        threading.Thread(target=worker, daemon=True).start()

    def _on_install_done(self, version: str, error: Exception | None) -> bool:
        self.set_busy(False)
        if error:
            self.append_log(f"Install failed: {error}")
            self.show_error("Install failed", str(error))
        else:
            self.append_log(f"Installed Mesa {version}. Restart Vulkan apps to pick it up.")
        self.rebuild_list()
        return False

    def _on_restore(self, *_args) -> None:
        if self._busy:
            return
        if not has_original_backup():
            self.show_error(
                "No backup available",
                "The original system library has not been backed up yet. "
                "It is created automatically the first time you install a custom version.",
            )
            return
        if not self.confirm(
            "Restore MESA system default?",
            f"This restores the original library to:\n{SYSTEM_LIBRARY}\n\n"
            "Your system password will be requested.",
        ):
            return

        self.set_busy(True)
        self.append_log("Restoring original system library (authentication required)…")

        def worker() -> None:
            error: Exception | None = None
            try:
                restore_system_default()
            except Exception as exc:  # noqa: BLE001
                error = exc
            GLib.idle_add(self._on_restore_done, error)

        threading.Thread(target=worker, daemon=True).start()

    def _on_restore_done(self, error: Exception | None) -> bool:
        self.set_busy(False)
        if error:
            self.append_log(f"Restore failed: {error}")
            self.show_error("Restore failed", str(error))
        else:
            self.append_log("System default Freedreno Vulkan library restored.")
        self.rebuild_list()
        return False


def run_app() -> None:
    win = MainWindow()
    win.show_all()
    win.alert_box.hide()
    Gtk.main()
