"""Download and compile Freedreno Vulkan libraries from official Mesa sources."""

from __future__ import annotations

import shutil
import subprocess
import tarfile
import urllib.request
from collections.abc import Callable
from pathlib import Path

from .constants import (
    ARCHIVE_BASE_URL,
    BUILD_ROOT,
    DEVEL_VERSION,
    LIBRARY_NAME,
    MESA_GIT_URL,
    USER_AGENT,
)
from .local_store import store_compiled_library
from .rocknix import RocknixPatch, download_patches
from .versions import is_devel

LogFn = Callable[[str], None]


class CompileError(RuntimeError):
    pass


def _log(log: LogFn | None, message: str) -> None:
    if log:
        log(message)


def archive_url(version: str) -> str:
    return f"{ARCHIVE_BASE_URL}/mesa-{version}.tar.xz"


def download_source(version: str, destination: Path, log: LogFn | None = None) -> Path:
    url = archive_url(version)
    _log(log, f"Downloading {url}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response, destination.open("wb") as out:
        shutil.copyfileobj(response, out)
    _log(log, f"Downloaded archive to {destination}")
    return destination


def clone_devel_source(destination: Path, log: LogFn | None = None) -> Path:
    """Shallow-clone Mesa main for the rolling devel build."""
    if destination.exists():
        shutil.rmtree(destination, ignore_errors=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    _log(log, f"Cloning Mesa devel (shallow): {MESA_GIT_URL}")
    _run(
        [
            "git",
            "clone",
            "--depth",
            "1",
            "--single-branch",
            MESA_GIT_URL,
            str(destination),
        ],
        cwd=None,
        log=log,
    )
    return destination


def _run(cmd: list[str], cwd: Path | None, log: LogFn | None) -> None:
    _log(log, "$ " + " ".join(cmd))
    process = subprocess.Popen(
        cmd,
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert process.stdout is not None
    for line in process.stdout:
        _log(log, line.rstrip())
    code = process.wait()
    if code != 0:
        raise CompileError(f"Command failed ({code}): {' '.join(cmd)}")


def _find_built_library(build_dir: Path) -> Path:
    candidates = list(build_dir.rglob(LIBRARY_NAME))
    if not candidates:
        raise CompileError(f"Built library {LIBRARY_NAME} was not found under {build_dir}")
    for path in candidates:
        if "freedreno" in str(path):
            return path
    return candidates[0]


def _apply_patch_file(source_dir: Path, patch_file: Path, log: LogFn | None) -> None:
    _log(log, f"Applying patch: {patch_file.name}")
    _run(
        [
            "patch",
            "-p1",
            "--forward",
            "--batch",
            "-i",
            str(patch_file),
        ],
        cwd=source_dir,
        log=log,
    )
    _log(log, f"Applied {patch_file.name}")


def _download_community_patches(
    patches: list[RocknixPatch],
    work_patches_dir: Path,
    log: LogFn | None,
) -> list[Path]:
    if not patches:
        return []
    _log(log, f"Downloading {len(patches)} community patch(es)…")
    return download_patches(patches, work_patches_dir)


def _meson_setup(source_dir: Path, build_dir: Path, log: LogFn | None) -> None:
    options = [
        "meson",
        "setup",
        str(build_dir),
        str(source_dir),
        "--buildtype=release",
        "-Dprefix=/usr",
        "-Dgallium-drivers=",
        "-Dvulkan-drivers=freedreno",
        "-Dfreedreno-kmds=msm",
        "-Dglx=disabled",
        "-Degl=disabled",
        "-Dgles1=disabled",
        "-Dgles2=disabled",
        "-Dgbm=disabled",
        "-Dllvm=disabled",
        "-Dshared-glapi=disabled",
        "-Dmicrosoft-clc=disabled",
        "-Dvalgrind=disabled",
        "-Dlibunwind=disabled",
        "-Dlmsensors=disabled",
        "-Dbuild-tests=false",
    ]

    try:
        _run(options + ["-Dopengl=disabled"], cwd=None, log=log)
        return
    except CompileError:
        _log(log, "Retrying meson setup without -Dopengl=disabled")
        if build_dir.exists():
            shutil.rmtree(build_dir, ignore_errors=True)
        _run(options, cwd=None, log=log)


def compile_version(
    version: str,
    *,
    apply_patches: bool = False,
    rocknix_patches: list[RocknixPatch] | None = None,
    log: LogFn | None = None,
) -> Path:
    """
    Compile libvulkan_freedreno.so for a Mesa release or rolling devel tip.

    Stable versions are fetched from archive.mesa3d.org.
    devel is cloned from gitlab.freedesktop.org/mesa/mesa.git (shallow).
    """
    store_name = DEVEL_VERSION if is_devel(version) else version
    work_root = BUILD_ROOT / store_name
    if work_root.exists():
        shutil.rmtree(work_root, ignore_errors=True)
    work_root.mkdir(parents=True, exist_ok=True)

    extract_dir = work_root / "src"
    build_dir = work_root / "build"
    work_patches_dir = work_root / "patches"

    try:
        if is_devel(version):
            source_dir = clone_devel_source(extract_dir / "mesa", log=log)
        else:
            archive_path = work_root / f"mesa-{version}.tar.xz"
            download_source(version, archive_path, log=log)
            _log(log, "Extracting source archive...")
            extract_dir.mkdir(parents=True, exist_ok=True)
            with tarfile.open(archive_path, "r:xz") as archive:
                archive.extractall(path=extract_dir)
            source_candidates = [p for p in extract_dir.iterdir() if p.is_dir()]
            if not source_candidates:
                raise CompileError("Extracted Mesa source directory was not found")
            source_dir = source_candidates[0]

        if apply_patches:
            patches = _download_community_patches(
                rocknix_patches or [],
                work_patches_dir,
                log=log,
            )
            if not patches:
                _log(log, "apply_patches=True but no community patch files were available")
            for patch_file in patches:
                _apply_patch_file(source_dir, patch_file, log=log)
        else:
            _log(log, "Compiling without community patches (user choice)")

        _meson_setup(source_dir, build_dir, log=log)

        targets = [
            "src/freedreno/vulkan/libvulkan_freedreno.so",
            LIBRARY_NAME,
        ]
        built: Path | None = None
        last_error: Exception | None = None
        for target in targets:
            try:
                _run(["ninja", "-C", str(build_dir), target], cwd=None, log=log)
                built = _find_built_library(build_dir)
                break
            except CompileError as exc:
                last_error = exc
                _log(log, f"Target {target} failed, trying next option…")
        if built is None:
            raise CompileError(str(last_error) if last_error else "Build produced no library")

        _log(log, f"Built library: {built}")
        stored = store_compiled_library(store_name, built)
        _log(log, f"Stored library at {stored}")
        return stored
    finally:
        _log(log, f"Cleaning compile directory {work_root}")
        shutil.rmtree(work_root, ignore_errors=True)
        try:
            if BUILD_ROOT.exists() and not any(BUILD_ROOT.iterdir()):
                BUILD_ROOT.rmdir()
        except OSError:
            pass
