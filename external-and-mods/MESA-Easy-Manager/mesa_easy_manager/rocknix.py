"""Load bundled Mesa patches per SoC profile (no network at compile time).

All patches ship under mesa_easy_manager/patches/. Upstream attribution
URLs are documentation-only; the original Batocera repo was removed and
preserved at https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from enum import Enum
from pathlib import Path

PATCHES_ROOT = Path(__file__).resolve().parent / "patches"

# Attribution / docs only (not fetched at runtime).
BATOCERA_FORK = "https://github.com/MaSieS4Fun/Batocera-Custom-Qualcomm-Builds"
ROCKNIX_TREE = (
    "https://github.com/ROCKNIX/distribution/tree/next/"
    "projects/ROCKNIX/packages/graphics/mesa/patches"
)

DEFAULT_PLATFORM = "SM8550"

# Ordered list of patch files relative to PATCHES_ROOT.
PLATFORM_PATCH_FILES: dict[str, tuple[str, ...]] = {
    "SM8550": (
        "SM8550/001-fix-freedreno-vulkan.patch",
        "SM8550/0001-freedreno-ir3-vulkan-disable-bindless-ubo-const-lowering.patch",
    ),
    "SM8750": (
        "SM8550/001-fix-freedreno-vulkan.patch",
        "SM8550/0001-freedreno-ir3-vulkan-disable-bindless-ubo-const-lowering.patch",
        "SM8750/0001-add-a830-chip-id.patch",
    ),
}


class CompileProfile(Enum):
    GENERIC = "generic"
    SM8550 = "SM8550"
    SM8750 = "SM8750"


PROFILE_LABELS = {
    CompileProfile.GENERIC: "Generic (no device patches)",
    CompileProfile.SM8550: "SM8550 (Odin 2, Thor, R-Pocket 6)",
    CompileProfile.SM8750: "SM8750 (Odin 3)",
}


@dataclass(frozen=True)
class PlatformSources:
    platform: str
    rocknix_url: str
    batocera_url: str
    batocera_root: str
    devices: str
    local_note: str = ""


def platform_sources(platform: str) -> PlatformSources:
    if platform == "SM8750":
        devices = "Odin 3 (SM8750 / Adreno 830)"
        batocera_root = "board/batocera/qualcomm/sm8750/patches/mesa3d"
    else:
        devices = "Odin 2, Thor, R-Pocket 6 (SM8550 / Adreno 740)"
        batocera_root = "board/batocera/patches/mesa3d"
    return PlatformSources(
        platform=platform,
        rocknix_url=f"{ROCKNIX_TREE}/{platform}",
        batocera_url=f"{BATOCERA_FORK}/tree/main/{batocera_root}",
        batocera_root=batocera_root,
        devices=devices,
        local_note=(
            f"Bundled under mesa_easy_manager/patches/ "
            f"({len(PLATFORM_PATCH_FILES.get(platform, ()))} files, offline)"
        ),
    )


# Backwards-compatible module-level names.
_default = platform_sources(DEFAULT_PLATFORM)
ROCKNIX_PATCHES_URL = _default.rocknix_url
BATOCERA_PATCHES_URL = _default.batocera_url
BATOCERA_PATCHES_ROOT = _default.batocera_root
PATCH_SOURCES_SUMMARY = (
    f"Local bundle: mesa_easy_manager/patches/\n"
    f"Attribution Batocera fork: {BATOCERA_FORK}\n"
    f"Attribution ROCKNIX tree:  {ROCKNIX_TREE}"
)


def patch_sources_summary(platform: str) -> str:
    src = platform_sources(platform)
    return (
        f"Local:    {src.local_note}\n"
        f"Attrib.:  Batocera fork {BATOCERA_FORK}\n"
        f"          ROCKNIX {src.rocknix_url}"
    )


@dataclass(frozen=True)
class MesaPatch:
    """A bundled Mesa `.patch` file."""

    name: str
    path: str
    download_url: str
    sha: str
    size: int
    source: str  # "local"
    content_sha256: str = ""
    local_path: str = ""

    @property
    def html_url(self) -> str:
        return f"bundled:{self.path}"

    @property
    def label(self) -> str:
        return f"[local] {self.name}"


RocknixPatch = MesaPatch


class PatchFetchError(RuntimeError):
    pass


RocknixError = PatchFetchError


def _load_bundled_file(rel: str) -> MesaPatch:
    path = PATCHES_ROOT / rel
    if not path.is_file():
        raise PatchFetchError(f"Bundled patch missing: {path}")
    blob = path.read_bytes()
    digest = hashlib.sha256(blob).hexdigest()
    return MesaPatch(
        name=path.name,
        path=rel,
        download_url="",
        sha=digest[:12],
        size=len(blob),
        source="local",
        content_sha256=digest,
        local_path=str(path),
    )


def fetch_patches(platform: str = DEFAULT_PLATFORM) -> list[MesaPatch]:
    """
    Return bundled patches for SM8550 or SM8750.

    No network access — files must exist under mesa_easy_manager/patches/.
    """
    files = PLATFORM_PATCH_FILES.get(platform)
    if not files:
        raise PatchFetchError(f"Unsupported patch platform: {platform}")

    patches = [_load_bundled_file(rel) for rel in files]
    # Deduplicate by content (defensive).
    unique: list[MesaPatch] = []
    seen: set[str] = set()
    for patch in patches:
        if patch.content_sha256 in seen:
            continue
        seen.add(patch.content_sha256)
        unique.append(patch)
    if not unique:
        raise PatchFetchError(f"No bundled patches for {platform}")
    return unique


def download_patches(
    patches: list[MesaPatch],
    destination: Path,
) -> list[Path]:
    """Copy bundled patches into the build work directory (apply order)."""
    destination.mkdir(parents=True, exist_ok=True)
    saved: list[Path] = []
    for index, patch in enumerate(patches, start=1):
        target = destination / f"{index:02d}-{patch.source}-{patch.name}"
        target.write_bytes(Path(patch.local_path).read_bytes())
        saved.append(target)
    return saved


def summarize_patches(patches: list[MesaPatch]) -> str:
    if not patches:
        return "(none)"
    lines = ["  Local (bundled):"]
    for patch in patches:
        lines.append(f"    • {patch.name}")
    return "\n".join(lines)


# Stubs kept so older imports do not break; always empty / error offline.
def fetch_rocknix_patches(platform: str = DEFAULT_PLATFORM) -> list[MesaPatch]:
    return []


def fetch_batocera_patches(platform: str = DEFAULT_PLATFORM) -> list[MesaPatch]:
    return []


def fetch_local_wsi_patches() -> list[MesaPatch]:
    """Deprecated — local WSI/RPCS3 experiment patches were removed."""
    return []
