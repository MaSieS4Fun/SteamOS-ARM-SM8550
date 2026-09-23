"""Download / extract / install kernel builds (GUI helper)."""

from __future__ import annotations

import os
import shutil
import subprocess
import tarfile
import zipfile
from pathlib import Path
from typing import Callable
from urllib.request import Request, urlopen

from .constants import BUILDS_DIR, DOWNLOAD_DIR, KERNEL_TREE, USER_AGENT
from .versions import KernelCandidate

ProgressCb = Callable[[str, float], None]


def tree_has_update_sh(tree: Path | None = None) -> bool:
    root = tree or KERNEL_TREE
    return (root / "update.sh").is_file()


def tree_has_make_sh(tree: Path | None = None) -> bool:
    root = tree or KERNEL_TREE
    return (root / "make.sh").is_file()


def _progress(cb: ProgressCb | None, stage: str, fraction: float) -> None:
    if cb:
        cb(stage, fraction)


def download_asset(url: str, dest: Path, progress: ProgressCb | None = None) -> Path:
    DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(req, timeout=600) as resp, open(dest, "wb") as out:
        total = int(resp.headers.get("Content-Length") or 0)
        done = 0
        while True:
            chunk = resp.read(1024 * 256)
            if not chunk:
                break
            out.write(chunk)
            done += len(chunk)
            if total > 0:
                _progress(progress, "Downloading", min(done / total, 0.99))
            else:
                _progress(progress, f"Downloading ({done // (1024 * 1024)} MiB)", -1.0)
    _progress(progress, "Download complete", 1.0)
    return dest


def _find_kbase_dir(root: Path) -> Path | None:
    if (root / "boot" / "KERNEL").is_file():
        return root
    for child in root.rglob("KERNEL"):
        if child.name == "KERNEL" and child.parent.name == "boot":
            return child.parent.parent
    return None


def extract_build_archive(archive: Path, progress: ProgressCb | None = None) -> Path:
    BUILDS_DIR.mkdir(parents=True, exist_ok=True)
    staging = BUILDS_DIR / f".extract-{os.getpid()}"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)

    _progress(progress, "Extracting", 0.1)
    name = archive.name.lower()
    if name.endswith(".zip"):
        with zipfile.ZipFile(archive) as zf:
            zf.extractall(staging)
    else:
        # tar.gz / tar.xz / tar.zst / tgz
        mode = "r:*"
        if name.endswith(".tar.zst") or name.endswith(".tzst"):
            # Python 3.14+ may support zstd; fall back to tar CLI
            try:
                with tarfile.open(archive, mode="r:zst") as tf:
                    tf.extractall(staging)
            except (tarfile.ReadError, ValueError):
                subprocess.run(
                    ["tar", "-C", str(staging), "-xf", str(archive)],
                    check=True,
                )
        else:
            with tarfile.open(archive, mode=mode) as tf:
                tf.extractall(staging)

    found = _find_kbase_dir(staging)
    if found is None:
        shutil.rmtree(staging, ignore_errors=True)
        raise RuntimeError(f"No boot/KERNEL inside archive: {archive.name}")

    # Move to stable name under builds/
    target_name = found.name if "kbase" in found.name else f"{found.name}-kbase"
    target = BUILDS_DIR / target_name
    if target.exists():
        shutil.rmtree(target)
    if found == staging:
        staging.rename(target)
    else:
        shutil.move(str(found), str(target))
        shutil.rmtree(staging, ignore_errors=True)

    _progress(progress, "Extracted", 1.0)
    return target


def prepare_candidate(candidate: KernelCandidate, progress: ProgressCb | None = None) -> Path:
    """Return a local build directory ready for update.sh."""
    if candidate.path and (candidate.path / "boot" / "KERNEL").is_file():
        return candidate.path
    if not candidate.download_url or not candidate.asset_name:
        raise RuntimeError(
            f"{candidate.version} has no local build and no downloadable package. "
            "Build with KERNEL_VER=… ./make.sh first, or publish a GitHub release asset."
        )
    archive = DOWNLOAD_DIR / candidate.asset_name
    if not archive.is_file():
        download_asset(candidate.download_url, archive, progress=progress)
    return extract_build_archive(archive, progress=progress)


def _pkexec_or_sudo(argv: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    run_env = os.environ.copy()
    if env:
        run_env.update(env)
    if os.geteuid() == 0:
        return subprocess.run(argv, check=False, text=True, capture_output=True, env=run_env)
    if shutil.which("pkexec"):
        return subprocess.run(["pkexec", *argv], check=False, text=True, capture_output=True, env=run_env)
    return subprocess.run(["sudo", "--", *argv], check=False, text=True, capture_output=True, env=run_env)


def install_build(build_dir: Path, progress: ProgressCb | None = None) -> None:
    build_dir = build_dir.resolve()
    if not (build_dir / "boot" / "KERNEL").is_file():
        raise RuntimeError(f"Incomplete build: {build_dir}")

    helper = Path(__file__).resolve().parent / "privileged_install.py"
    for candidate in (
        Path("/usr/share/easy-kernel-updater/easy_kernel_updater/privileged_install.py"),
        Path("/usr/share/masi-kernel-manager/masi_kernel_manager/privileged_install.py"),
    ):
        if candidate.is_file():
            helper = candidate
            break

    _progress(progress, "Installing (root)", 0.2)
    proc = _pkexec_or_sudo(
        ["python3", str(helper), "install", str(build_dir)],
        env={
            "EASY_KERNEL_TREE": str(KERNEL_TREE),
            "MASI_KERNEL_TREE": str(KERNEL_TREE),
            "SKIP_REBOOT": "1",
            "UPDATE_YES": "1",
        },
    )
    if proc.returncode != 0:
        msg = (proc.stderr or proc.stdout or "").strip() or f"exit {proc.returncode}"
        raise RuntimeError(msg)
    _progress(progress, "Install complete — reboot required", 1.0)


def build_from_source(version: str, progress: ProgressCb | None = None) -> Path:
    if not tree_has_make_sh():
        raise RuntimeError(
            "Kernel source tree with make.sh not found. "
            "Run this GUI from the kernel updater checkout (vendor/kernel) "
            "or install a release package."
        )
    _progress(progress, f"Building linux-{version} (long)", 0.05)
    proc = subprocess.run(
        [str(KERNEL_TREE / "make.sh")],
        cwd=str(KERNEL_TREE),
        check=False,
        text=True,
        capture_output=True,
        env={**os.environ, "KERNEL_VER": version},
    )
    if proc.returncode != 0:
        tail = (proc.stderr or proc.stdout or "")[-4000:]
        raise RuntimeError(f"make.sh failed:\n{tail}")
    # Pick newest matching output
    matches = sorted(
        KERNEL_TREE.joinpath("output").glob(f"{version}-*-kbase"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    if not matches or not (matches[0] / "boot" / "KERNEL").is_file():
        raise RuntimeError(f"Build finished but no output/{version}-*-kbase found")
    _progress(progress, "Build complete", 1.0)
    return matches[0]
