#!/usr/bin/env python3
"""Run the test suites outside Roblox.

Each suite is assembled into its own Lua chunk and run in its own process, so
a global left behind by one suite cannot mask a bug in another:

    tools/stubs.lua     minimal Roblox environment (both suites)
    tools/uistubs.lua   UI types and services (UI suite only)
    the bundle          every module, minus its ``return require(...)`` line
    the suite file      the assertions

Dropping the entry line is what keeps the runtime monolith out of the run:
modules are registered but only those a suite requires actually execute, so
``Runtime.Legacy`` (which needs a real game) is never touched.

    python3 tools/test.py            # every suite
    python3 tools/test.py ui         # one suite
"""

import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import pack  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
ENTRY_LINE = f'return require("{pack.ENTRY}")'

SUITES = {
    "core": {"file": "tests.lua", "stubs": ["stubs.lua"]},
    "ui": {"file": "uitests.lua", "stubs": ["stubs.lua", "uistubs.lua"]},
}


def lua_binary() -> str:
    for binary in ("lua5.4", "lua5.3", "lua"):
        try:
            subprocess.run([binary, "-v"], capture_output=True, check=False)
            return binary
        except FileNotFoundError:
            continue
    raise SystemExit("no lua interpreter found (tried lua5.4, lua5.3, lua)")


def run(name: str, spec: dict, bundle: str, binary: str) -> int:
    parts = [(TOOLS / stub).read_text(encoding="utf-8") for stub in spec["stubs"]]
    parts.append(bundle)
    parts.append((TOOLS / spec["file"]).read_text(encoding="utf-8"))

    out = ROOT / "build" / f"test-{name}.lua"
    out.parent.mkdir(exist_ok=True)
    out.write_text("\n".join(parts), encoding="utf-8")

    print(f"\n=== suite {name} ===")
    return subprocess.call([binary, str(out)])


def main() -> int:
    wanted = sys.argv[1:] or list(SUITES)
    for name in wanted:
        if name not in SUITES:
            raise SystemExit(f"unknown suite {name!r} (have: {', '.join(SUITES)})")

    bundle = pack.bundle(pack.collect())
    if ENTRY_LINE not in bundle:
        raise SystemExit("bundle layout changed: entry line not found")
    bundle = bundle.replace(ENTRY_LINE, "-- entry skipped for tests")

    binary = lua_binary()
    failed = 0
    for name in wanted:
        if run(name, SUITES[name], bundle, binary) != 0:
            failed += 1

    if failed:
        print(f"\n{failed} suite(s) en echec")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
