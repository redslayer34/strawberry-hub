#!/usr/bin/env python3
"""Reverse tools/pack.py: recover the bundled Lua source from a packed build.

Kept in the repo because the packed distribution was, for a while, the only
copy of the source that existed. It stays useful for inspecting an older
tagged build without checking it out.

    python3 tools/unpack.py [StrawberryHub.lua] [-o out.lua]
"""

import argparse
import base64
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def unpack(text: str) -> str:
    key = re.search(r'local K="([^"]+)"', text)
    data = re.search(r'local D="([^"]+)"', text)
    if not key or not data:
        raise SystemExit("not a packed Strawberry Hub build (missing K/D)")
    k = key.group(1)
    raw = base64.b64decode(data.group(1) + "=" * (-len(data.group(1)) % 4))
    return bytes(b ^ ord(k[i % len(k)]) for i, b in enumerate(raw)).decode("utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("path", nargs="?", default=str(ROOT / "StrawberryHub.lua"))
    ap.add_argument("-o", "--out", help="write here instead of stdout")
    args = ap.parse_args()

    source = unpack(pathlib.Path(args.path).read_text(encoding="utf-8"))
    if args.out:
        pathlib.Path(args.out).write_text(source, encoding="utf-8")
        print(f"unpacked -> {args.out} ({len(source)} bytes)")
    else:
        sys.stdout.write(source)
    return 0


if __name__ == "__main__":
    sys.exit(main())
