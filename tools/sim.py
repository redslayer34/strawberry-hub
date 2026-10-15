#!/usr/bin/env python3
"""Run game simulations: replay a real case against a fake Blox Fruits.

Each scenario is assembled like a test suite and run in its own process:

    tools/stubs.lua          minimal Roblox environment
    the bundle               every module, minus its entry line
    tools/sim/lib.lua        the SIM library (fake server, clock, report)
    tools/sim/scenarios/X    the scenario

    python3 tools/sim.py --list
    python3 tools/sim.py guitar_puzzle      # one scenario (report also in build/sim-NAME.txt)
    python3 tools/sim.py all                # every scenario
"""

import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import pack  # noqa: E402
from test import ENTRY_LINE, lua_binary  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
SCENARIOS = TOOLS / "sim" / "scenarios"


def scenarios() -> list[str]:
    return sorted(path.stem for path in SCENARIOS.glob("*.lua"))


def run(name: str, bundle: str, binary: str) -> int:
    path = SCENARIOS / f"{name}.lua"
    if not path.exists():
        raise SystemExit(f"unknown scenario {name!r} (have: {', '.join(scenarios())})")
    parts = [
        (TOOLS / "stubs.lua").read_text(encoding="utf-8"),
        bundle.replace(ENTRY_LINE, "-- entry skipped for the simulator"),
        (TOOLS / "sim" / "lib.lua").read_text(encoding="utf-8"),
        path.read_text(encoding="utf-8"),
    ]
    out = ROOT / "build" / f"sim-{name}.lua"
    out.parent.mkdir(exist_ok=True)
    out.write_text("\n".join(parts), encoding="utf-8")
    result = subprocess.run([binary, str(out)], capture_output=True, text=True)
    report = result.stdout + (("\n-- lua stderr\n" + result.stderr) if result.stderr else "")
    (ROOT / "build" / f"sim-{name}.txt").write_text(report, encoding="utf-8")
    print(report)
    return result.returncode


def main() -> int:
    args = sys.argv[1:]
    if not args or args == ["--list"]:
        print("\n".join(scenarios()))
        return 0
    wanted = scenarios() if args == ["all"] else args
    bundle = pack.bundle(pack.collect())
    binary = lua_binary()
    failed = [name for name in wanted if run(name, bundle, binary) != 0]
    print(f"\n{len(wanted) - len(failed)}/{len(wanted)} scenario(s) passed"
          + (f"; failed: {', '.join(failed)}" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
