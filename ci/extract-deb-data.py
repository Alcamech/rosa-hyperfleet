#!/usr/bin/env python3
"""Extract data.tar.* from a .deb (ar archive). Stdlib only for CI pods without ar."""
from __future__ import annotations

import io
import os
import sys
import tarfile


def _read_ar_member(f: io.BufferedReader) -> tuple[str, bytes] | None:
    hdr = f.read(60)
    if len(hdr) < 60:
        return None
    name = hdr[:16].decode("ascii", errors="replace").strip()
    size = int(hdr[48:58].decode("ascii").strip())
    payload = f.read(size)
    if size % 2:
        f.read(1)
    return name, payload


def extract_deb(deb_path: str, dest_dir: str) -> None:
    os.makedirs(dest_dir, exist_ok=True)
    with open(deb_path, "rb") as f:
        magic = f.read(8)
        if magic != b"!<arch>\n":
            raise ValueError(f"not an ar archive: {deb_path}")
        data_payload: bytes | None = None
        while True:
            member = _read_ar_member(f)
            if member is None:
                break
            name, payload = member
            if name.startswith("data.tar"):
                data_payload = payload
                break
        if data_payload is None:
            raise ValueError("data.tar member not found in deb")

    with tarfile.open(fileobj=io.BytesIO(data_payload), mode="r:*") as tf:
        for member in tf.getmembers():
            if member.name.startswith("/") or ".." in member.name.split("/"):
                continue
            tf.extract(member, path=dest_dir)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <deb> <dest-dir>", file=sys.stderr)
        return 2
    extract_deb(sys.argv[1], sys.argv[2])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
