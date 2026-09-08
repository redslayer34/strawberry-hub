#!/usr/bin/env python3
"""Bundle src/ into a single Lua chunk, then pack it into StrawberryHub.lua.

The distributed file is a build artifact. The source of truth is src/.

Bundling
--------
Every .lua file under src/ becomes a module addressed by its dotted path
relative to src/ (``src/AutomationCore/Log.lua`` -> ``AutomationCore.Log``).
A directory's ``init.lua`` takes the directory's own name
(``src/AutomationCore/init.lua`` -> ``AutomationCore``), matching the way
``require`` resolves packages elsewhere.

Modules are emitted as thunks in a registry and resolved lazily by a small
``require`` shim, so load order follows the dependency graph rather than
file order, and each module runs at most once.

Packing
-------
base64 over an XOR-with-repeating-key stream, mirrored by the loader stub.
This is obfuscation for casual reading, not security: the key ships with the
file. It exists only to keep the distributed script from being trivially
copy-pasted, and it is why the source has to live in src/ to stay editable.
"""

import argparse
import base64
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
DIST = ROOT / "StrawberryHub.lua"
KEY = "str4wb3rry_hub_k3y_2026"
ENTRY = "main"

B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

# The runtime shim. `require` is a plain local, so every module thunk closes
# over it; a module that is never required is never executed.
PREAMBLE = """local __modules = {}
local __loaded = {}
local function require(name)
    local cached = __loaded[name]
    if cached ~= nil then return cached end
    local factory = __modules[name]
    if not factory then
        error("[Strawberry Hub] module introuvable : " .. tostring(name), 2)
    end
    -- Marked before the body runs so a dependency cycle surfaces as a nil
    -- field instead of an unbounded recursion.
    __loaded[name] = true
    local value = factory()
    if value == nil then value = true end
    __loaded[name] = value
    return value
end
"""


def module_name(path: pathlib.Path) -> str:
    rel = path.relative_to(SRC).with_suffix("")
    parts = list(rel.parts)
    if parts[-1] == "init":
        parts.pop()
        if not parts:
            raise SystemExit("src/init.lua is not a valid module name; use src/main.lua")
    return ".".join(parts)


def collect() -> list[tuple[str, pathlib.Path]]:
    files = sorted(SRC.rglob("*.lua"))
    if not files:
        raise SystemExit(f"no .lua sources found under {SRC}")
    modules = [(module_name(p), p) for p in files]
    seen: dict[str, pathlib.Path] = {}
    for name, path in modules:
        if name in seen:
            raise SystemExit(f"duplicate module {name}: {seen[name]} and {path}")
        seen[name] = path
    if ENTRY not in seen:
        raise SystemExit(f"missing entry module src/{ENTRY}.lua")
    return modules


def bundle(modules: list[tuple[str, pathlib.Path]]) -> str:
    out = ["-- Strawberry Hub — bundle genere par tools/pack.py. Ne pas editer.", PREAMBLE]
    for name, path in modules:
        # Module names come from filesystem paths made of identifier chars and
        # dots, so they need no escaping inside a Lua string literal.
        assert '"' not in name and "\\" not in name, name
        body = path.read_text(encoding="utf-8").rstrip("\n")
        out.append(f'__modules["{name}"] = function()\n{body}\nend\n')
    out.append(f'return require("{ENTRY}")\n')
    return "\n".join(out)


def pack(source: str) -> str:
    payload = bytes(
        b ^ ord(KEY[i % len(KEY)]) for i, b in enumerate(source.encode("utf-8"))
    )
    encoded = base64.b64encode(payload).decode("ascii")
    return f"""-- Strawberry Hub
-- Distribution packee. Ne pas editer : editer la source puis re-packer.
--   python3 tools/pack.py
local K="{KEY}"
local D="{encoded}"
local b="{B64_ALPHABET}"
local t={{}}
for i=1,#b do t[b:sub(i,i)]=i-1 end
local function b64(data)
    local out={{}}
    local i,n=1,#data
    while i<=n do
        local c1=t[data:sub(i,i)] or 0
        local c2=t[data:sub(i+1,i+1)] or 0
        local d3=data:sub(i+2,i+2)
        local d4=data:sub(i+3,i+3)
        local c3=t[d3] or 0
        local c4=t[d4] or 0
        out[#out+1]=string.char(c1*4+math.floor(c2/16))
        if d3~="=" and d3~="" then out[#out+1]=string.char((c2%16)*16+math.floor(c3/4)) end
        if d4~="=" and d4~="" then out[#out+1]=string.char((c3%4)*64+c4) end
        i=i+4
    end
    return table.concat(out)
end
local raw=b64(D)
local xor=bit32 and bit32.bxor or function(a,c)
    local r,p=0,1
    for _=1,8 do
        local x,y=a%2,c%2
        if x~=y then r=r+p end
        a,c,p=math.floor(a/2),math.floor(c/2),p*2
    end
    return r
end
local o={{}}
for i=1,#raw do
    o[i]=string.char(xor(raw:byte(i),K:byte((i-1)%#K+1)))
end
local src=table.concat(o)
local fn,err=(loadstring or load)(src)
if not fn then return warn("[Strawberry Hub] load error: "..tostring(err)) end
return fn()
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--bundle-only",
        metavar="PATH",
        help="write the readable bundle here and skip packing (for syntax checks)",
    )
    args = ap.parse_args()

    modules = collect()
    bundled = bundle(modules)

    if args.bundle_only:
        pathlib.Path(args.bundle_only).write_text(bundled, encoding="utf-8")
        print(f"bundle -> {args.bundle_only} ({len(modules)} modules, {len(bundled)} bytes)")
        return 0

    DIST.write_text(pack(bundled), encoding="utf-8")
    print(
        f"packed {len(modules)} modules -> {DIST.relative_to(ROOT)} "
        f"({len(bundled)} bytes source, {DIST.stat().st_size} bytes dist)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
