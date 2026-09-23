#!/usr/bin/env python3
"""Rebuild the official SteamOS Deckard/VR aarch64 rootfs.img from a RAUC+casync store."""

from __future__ import annotations

import argparse
import hashlib
import os
import struct
import sys
import threading
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests
import zstandard

CA_FORMAT_INDEX = 0x96824D9C7B129FF9
CA_FORMAT_TABLE = 0xE75B9E112F17417D
CA_FORMAT_TABLE_TAIL_MARKER = 0x4B4F050E5549ECD1
INDEX_HEADER_LEN = 48
TABLE_HEADER_LEN = 16
TABLE_ENTRY_LEN = 40

DEFAULT_STORE = (
    "https://steamdeck-images.steamos.cloud/vr/"
    "20260921.6090922/deckard-20260921.6090922-0.5.0.castr"
)
FALLBACK_STORE = "https://steamdeck-images.steamos.cloud/vr/chunks.castr"
EXPECTED_SHA256 = "5c53ff2ed7dc78f313a19fc9224aa07e7fb63271b811a4ada295441a0361e6a8"


def parse_caibx(path: str) -> tuple[int, list[tuple[int, int, bytes]]]:
    data = open(path, "rb").read()
    size, magic, flags, min_sz, avg_sz, max_sz = struct.unpack_from("<6Q", data, 0)
    if magic != CA_FORMAT_INDEX:
        raise SystemExit(f"not a casync index: magic={magic:#x}")
    if size != INDEX_HEADER_LEN:
        raise SystemExit(f"unexpected index header size {size}")

    tsize, tmagic = struct.unpack_from("<2Q", data, INDEX_HEADER_LEN)
    if tmagic != CA_FORMAT_TABLE:
        raise SystemExit(f"missing casync table: magic={tmagic:#x}")

    body = data[INDEX_HEADER_LEN + TABLE_HEADER_LEN :]
    if len(body) % TABLE_ENTRY_LEN:
        raise SystemExit("truncated casync table")
    n_items = len(body) // TABLE_ENTRY_LEN - 1
    tail = body[n_items * TABLE_ENTRY_LEN :]
    marker = struct.unpack_from("<Q", tail, 32)[0]
    if marker != CA_FORMAT_TABLE_TAIL_MARKER:
        raise SystemExit(f"bad table tail marker {marker:#x}")

    chunks: list[tuple[int, int, bytes]] = []
    prev = 0
    for i in range(n_items):
        rec = body[i * TABLE_ENTRY_LEN : (i + 1) * TABLE_ENTRY_LEN]
        new_off = struct.unpack_from("<Q", rec, 0)[0]
        digest = rec[8:40]
        length = new_off - prev
        if length <= 0 or length > max_sz:
            raise SystemExit(f"bad chunk length {length} at {i}")
        chunks.append((prev, length, digest))
        prev = new_off
    return prev, chunks


def chunk_url(store: str, digest_hex: str) -> str:
    return f"{store.rstrip('/')}/{digest_hex[:4]}/{digest_hex}.cacnk"


def download_chunk(session: requests.Session, stores: list[str], digest_hex: str) -> bytes:
    last_err: Exception | None = None
    for store in stores:
        url = chunk_url(store, digest_hex)
        for attempt in range(6):
            try:
                r = session.get(url, timeout=20)
                if r.status_code == 404:
                    break
                r.raise_for_status()
                return r.content
            except Exception as exc:  # noqa: BLE001
                last_err = exc
                time.sleep(min(8, 0.4 * (2**attempt)))
    raise RuntimeError(f"failed to download {digest_hex}: {last_err}")


def read_local_chunk(chunks_dir: str, digest_hex: str) -> bytes:
    path = os.path.join(chunks_dir, digest_hex[:4], f"{digest_hex}.cacnk")
    with open(path, "rb") as f:
        return f.read()


def assemble(
    caibx: str,
    output: str,
    stores: list[str],
    workers: int,
    expected_sha256: str | None,
    chunks_dir: str | None = None,
) -> None:
    image_size, chunks = parse_caibx(caibx)
    by_hash: dict[bytes, list[tuple[int, int]]] = defaultdict(list)
    for offset, length, digest in chunks:
        by_hash[digest].append((offset, length))

    print(f"image size : {image_size} bytes ({image_size / (1024**3):.2f} GiB)")
    print(f"chunks     : {len(chunks)} total, {len(by_hash)} unique")
    print(f"output     : {output}")
    print(f"stores     : {', '.join(stores)}")
    sys.stdout.flush()

    os.makedirs(os.path.dirname(os.path.abspath(output)) or ".", exist_ok=True)
    fd = os.open(output, os.O_RDWR | os.O_CREAT)
    try:
        os.ftruncate(fd, image_size)
        done = 0
        downloaded = 0
        written = 0
        skipped_zero = 0
        lock = threading.Lock()
        t0 = time.time()

        def worker(digest: bytes, locs: list[tuple[int, int]]) -> tuple[int, int, int]:
            thread = threading.current_thread()
            dctx = getattr(thread, "dctx", None)
            if dctx is None:
                dctx = zstandard.ZstdDecompressor()
                thread.dctx = dctx
            session = getattr(thread, "http", None)
            if session is None and not chunks_dir:
                session = requests.Session()
                adapter = requests.adapters.HTTPAdapter(
                    pool_connections=4,
                    pool_maxsize=4,
                    max_retries=0,
                )
                session.mount("https://", adapter)
                session.headers["User-Agent"] = "steamos-oficial-rootfs-extract/1.0"
                thread.http = session

            if chunks_dir:
                blob = read_local_chunk(chunks_dir, digest.hex())
            else:
                blob = download_chunk(session, stores, digest.hex())
            try:
                raw = dctx.decompress(blob)
            except zstandard.ZstdError:
                raw = dctx.decompress(blob, max_output_size=max(length for _, length in locs))
            expected_len = locs[0][1]
            if any(length != expected_len for _, length in locs):
                raise RuntimeError(f"inconsistent lengths for {digest.hex()}")
            if len(raw) != expected_len:
                # zstd frame size should match, but allow streaming fallback
                raw = dctx.decompress(blob, max_output_size=expected_len)
            if len(raw) != expected_len:
                raise RuntimeError(
                    f"chunk {digest.hex()} decompressed to {len(raw)}, expected {expected_len}"
                )

            is_zero = not any(raw)
            if not is_zero:
                for offset, length in locs:
                    wrote = os.pwrite(fd, raw, offset)
                    if wrote != length:
                        raise RuntimeError(f"short pwrite at {offset}")
            return len(blob), expected_len * len(locs), int(is_zero)

        total_unique = len(by_hash)
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futs = [pool.submit(worker, digest, locs) for digest, locs in by_hash.items()]
            for fut in as_completed(futs):
                n_down, n_write, zero = fut.result()
                with lock:
                    done += 1
                    downloaded += n_down
                    written += n_write
                    skipped_zero += zero
                    if done % 200 == 0 or done == total_unique:
                        dt = max(time.time() - t0, 1e-6)
                        print(
                            f"[{done}/{total_unique}] "
                            f"net={downloaded / (1024**2):.1f} MiB "
                            f"placed={written / (1024**3):.2f} GiB "
                            f"zero_chunks={skipped_zero} "
                            f"{done / dt:.1f} chunk/s",
                            flush=True,
                        )
    finally:
        os.close(fd)

    if expected_sha256:
        print("hashing rootfs.img ...", flush=True)
        h = hashlib.sha256()
        with open(output, "rb") as f:
            while True:
                buf = f.read(1024 * 1024 * 8)
                if not buf:
                    break
                h.update(buf)
        digest = h.hexdigest()
        print(f"sha256     : {digest}")
        if digest != expected_sha256:
            raise SystemExit(f"SHA256 mismatch, expected {expected_sha256}")
        print("sha256 matches RAUC manifest")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--caibx", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--store", action="append", default=[])
    ap.add_argument("--workers", type=int, default=16)
    ap.add_argument("--expected-sha256", default=EXPECTED_SHA256)
    ap.add_argument("--chunks-dir", default=None, help="Local castr directory of .cacnk files")
    args = ap.parse_args()
    stores = args.store or [DEFAULT_STORE, FALLBACK_STORE]
    assemble(
        args.caibx,
        args.output,
        stores,
        args.workers,
        args.expected_sha256 or None,
        chunks_dir=args.chunks_dir,
    )


if __name__ == "__main__":
    main()
