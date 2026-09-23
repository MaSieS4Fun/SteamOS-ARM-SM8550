from __future__ import annotations

import os
import re
import shutil
import tarfile
import zipfile
from pathlib import Path
from typing import Callable, Optional

from .constants import CACHE_DIR, DEFAULT_INSTALL_DIR
from .github_api import download_file, ensure_cache_dir
from .models import Release, archive_extension


ProgressCallback = Callable[[str, float], None]
CancelCheck = Callable[[], bool]


def get_install_dir() -> Path:
    env = os.environ.get("PROTON_ARM_INSTALL_DIR")
    if env:
        return Path(env).expanduser()
    return DEFAULT_INSTALL_DIR


def list_installed(install_dir: Path | None = None) -> list[Path]:
    root = install_dir or get_install_dir()
    if not root.is_dir():
        return []
    installed: list[Path] = []
    for entry in sorted(root.iterdir(), key=lambda p: p.name.lower()):
        if entry.name.startswith("."):
            continue
        # Real Proton installs are directories (or symlinks to directories) with a proton script.
        target = entry.resolve() if entry.is_symlink() else entry
        if target.is_dir() and (target / "proton").exists():
            installed.append(entry)
    return installed


def is_release_installed(release: Release, install_dir: Path | None = None) -> bool:
    root = install_dir or get_install_dir()
    candidates = {
        release.install_dir_name,
        release.tag,
        release.asset_name,
    }
    ext = archive_extension(release.asset_name)
    if ext:
        candidates.add(release.asset_name[: -len(ext)])
    for name in candidates:
        path = root / name
        if path.exists():
            return True
    # Fuzzy: directory containing tag name
    if not root.is_dir():
        return False
    tag = release.tag.lower()
    for entry in root.iterdir():
        if tag and tag in entry.name.lower() and (entry.resolve() / "proton").exists():
            return True
    return False


def find_install_path(release: Release, install_dir: Path | None = None) -> Optional[Path]:
    root = install_dir or get_install_dir()
    if not root.is_dir():
        return None
    preferred = [
        release.install_dir_name,
        release.tag,
    ]
    ext = archive_extension(release.asset_name)
    if ext:
        preferred.append(release.asset_name[: -len(ext)])
    for name in preferred:
        path = root / name
        if path.exists():
            return path
    tag = release.tag.lower()
    for entry in root.iterdir():
        if tag and tag in entry.name.lower() and (entry.resolve() / "proton").exists():
            return entry
    return None


REQUIRE_TOOL_APPID_RE = re.compile(
    r'^[ \t]*"require_tool_appid"[ \t]+"[^"]*"[ \t]*\r?\n?',
    re.MULTILINE | re.IGNORECASE,
)


def patch_toolmanifest(proton_dir: Path) -> bool:
    """Remove require_tool_appid from toolmanifest.vdf. Returns True if changed."""
    path = proton_dir / "toolmanifest.vdf"
    if not path.is_file():
        return False
    original = path.read_text(encoding="utf-8", errors="replace")
    patched = REQUIRE_TOOL_APPID_RE.sub("", original)
    if patched == original:
        return False
    backup = path.with_suffix(path.suffix + ".bak-paem")
    if not backup.exists():
        backup.write_text(original, encoding="utf-8")
    path.write_text(patched, encoding="utf-8")
    return True


def ensure_bin_symlink(proton_dir: Path) -> bool:
    """Create files/bin -> bin-arm64 when needed. Returns True if created/updated."""
    files_dir = proton_dir / "files"
    if not files_dir.is_dir():
        return False
    arm_bin = files_dir / "bin-arm64"
    bin_path = files_dir / "bin"
    if not arm_bin.is_dir():
        return False
    if bin_path.is_symlink():
        if os.readlink(bin_path) == "bin-arm64":
            return False
        bin_path.unlink()
    elif bin_path.exists():
        # Real directory/file already named bin — leave it alone.
        return False
    bin_path.symlink_to("bin-arm64")
    return True


def apply_arm_fixes(proton_dir: Path) -> dict[str, bool]:
    """Apply both post-install Proton ARM fixes."""
    return {
        "toolmanifest_patched": patch_toolmanifest(proton_dir),
        "bin_symlink_created": ensure_bin_symlink(proton_dir),
    }


def _extract_archive(archive: Path, destination: Path) -> Path:
    """Extract archive into destination and return the top-level Proton directory."""
    destination.mkdir(parents=True, exist_ok=True)
    before = {p.name for p in destination.iterdir()}

    name = archive.name.lower()
    if name.endswith(".zip"):
        with zipfile.ZipFile(archive, "r") as zf:
            zf.extractall(destination)
    else:
        # tar.gz / tar.xz / tar.zst / tar
        mode = "r:*"
        with tarfile.open(archive, mode) as tf:
            # Python 3.12+ has filter=; use it when available for safety.
            try:
                tf.extractall(destination, filter="data")
            except TypeError:
                tf.extractall(destination)

    after = [p for p in destination.iterdir() if p.name not in before]
    if len(after) == 1 and after[0].is_dir():
        return after[0]
    # Some archives extract files flat — wrap unexpected layouts.
    if after:
        # Prefer directory containing proton script.
        for path in after:
            if path.is_dir() and (path / "proton").exists():
                return path
        if len(after) == 1:
            return after[0]
    raise RuntimeError(f"Could not determine extracted Proton directory from {archive.name}")


def install_release(
    release: Release,
    install_dir: Path | None = None,
    progress: ProgressCallback | None = None,
    cancel_check: CancelCheck | None = None,
) -> Path:
    """Download, extract, install, and apply ARM fixes for a release."""
    root = install_dir or get_install_dir()
    root.mkdir(parents=True, exist_ok=True)
    cache = ensure_cache_dir()

    ext = archive_extension(release.asset_name) or ".tar.gz"
    archive_path = cache / release.asset_name
    if not archive_path.exists():
        if progress:
            progress("Downloading", 0.0)

        def dl_progress(done: int, total: int | None) -> None:
            if not progress:
                return
            if total and total > 0:
                progress("Downloading", min(done / total, 0.99))
            else:
                progress("Downloading", -1.0)

        download_file(
            release.download_url,
            archive_path,
            progress=dl_progress,
            cancel_check=cancel_check,
        )

    if cancel_check and cancel_check():
        raise RuntimeError("Install canceled")

    if progress:
        progress("Extracting", 0.0)

    extract_root = cache / f"extract-{release.source_id}-{release.tag}".replace("/", "_")
    if extract_root.exists():
        shutil.rmtree(extract_root)
    extract_root.mkdir(parents=True, exist_ok=True)

    extracted = _extract_archive(archive_path, extract_root)
    release.install_dir_name = extracted.name

    if progress:
        progress("Installing", 0.5)

    target = root / extracted.name
    if target.exists():
        if target.is_symlink() or target.is_file():
            target.unlink()
        else:
            shutil.rmtree(target)

    shutil.move(str(extracted), str(target))
    shutil.rmtree(extract_root, ignore_errors=True)

    if progress:
        progress("Patching", 0.9)

    apply_arm_fixes(target.resolve() if target.is_symlink() else target)

    if progress:
        progress("Done", 1.0)

    return target


def remove_install(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)
    else:
        raise FileNotFoundError(path)


def repair_installed(install_dir: Path | None = None) -> list[tuple[str, dict[str, bool]]]:
    """Re-apply ARM fixes to every installed Proton under compatibilitytools.d."""
    results: list[tuple[str, dict[str, bool]]] = []
    for path in list_installed(install_dir):
        target = path.resolve() if path.is_symlink() else path
        results.append((path.name, apply_arm_fixes(target)))
    return results
