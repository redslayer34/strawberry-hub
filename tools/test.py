#!/usr/bin/env python3
"""Run the AutomationCore test suite outside Roblox.

Assembles three pieces into one Lua chunk and runs it:

    tools/stubs.lua   minimal Roblox environment
    the bundle        every module, minus its ``return require("main")`` line
    tools/tests.lua   the assertions

Dropping the entry line is what keeps the runtime monolith out of the run:
modules are registered but only those the tests require actually execute, so
``Runtime.Legacy`` (which needs a real game) is never touched.

    python3 tools/test.py
"""

import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import pack  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
ENTRY_LINE = f'return require("{pack.ENTRY}")'


def main() -> int:
    bundle = pack.bundle(pack.collect())
    if ENTRY_LINE not in bundle:
        raise SystemExit("bundle layout changed: entry line not found")
    bundle = bundle.replace(ENTRY_LINE, "-- entry skipped for tests")

    chunk = "\n".join([
        (TOOLS / "stubs.lua").read_text(encoding="utf-8"),
        bundle,
        (TOOLS / "tests.lua").read_text(encoding="utf-8"),
    ])

    out = ROOT / "build" / "test-chunk.lua"
    out.parent.mkdir(exist_ok=True)
    out.write_text(chunk, encoding="utf-8")

    for binary in ("lua5.4", "lua5.3", "lua"):
        try:
            return subprocess.call([binary, str(out)])
        except FileNotFoundError:
            continue
    raise SystemExit("no lua interpreter found (tried lua5.4, lua5.3, lua)")


if __name__ == "__main__":
    sys.exit(main())
