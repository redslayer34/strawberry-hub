#!/usr/bin/env python3
"""Compare two trees ignoring comments, to prove a rewrite touched only prose.

Translating thousands of comment lines by hand risks silently altering code.
This strips Lua comments and blank lines from both sides and reports any file
whose executable content changed, so a slip shows up immediately instead of at
load time in the game.

    python3 tools/codediff.py <before-dir> <after-dir>

String literals are NOT stripped: user-facing text is intentionally
translated, so changes there are reported and reviewed rather than hidden.
"""

import pathlib
import sys


def strip_comments(source: str) -> str:
    """Remove Lua comments, preserving anything inside string literals."""
    out = []
    i, n = 0, len(source)
    quote = None          # active string delimiter, if any
    long_bracket = None   # active [[ ]] level, if any

    while i < n:
        char = source[i]
        nxt = source[i + 1] if i + 1 < n else ""

        if long_bracket is not None:
            if source.startswith("]" + "=" * long_bracket + "]", i):
                out.append(source[i:i + long_bracket + 2])
                i += long_bracket + 2
                long_bracket = None
                continue
            out.append(char)
            i += 1
            continue

        if quote:
            out.append(char)
            if char == "\\":
                if i + 1 < n:
                    out.append(nxt)
                    i += 2
                    continue
            elif char == quote:
                quote = None
            i += 1
            continue

        if char in "\"'":
            quote = char
            out.append(char)
            i += 1
            continue

        # Long string literal [[ ... ]] / [=[ ... ]=]
        if char == "[":
            level = 0
            j = i + 1
            while j < n and source[j] == "=":
                level += 1
                j += 1
            if j < n and source[j] == "[":
                long_bracket = level
                out.append(source[i:j + 1])
                i = j + 1
                continue

        if char == "-" and nxt == "-":
            # Long comment --[[ ... ]] shares the bracket syntax.
            j = i + 2
            if j < n and source[j] == "[":
                level = 0
                k = j + 1
                while k < n and source[k] == "=":
                    level += 1
                    k += 1
                if k < n and source[k] == "[":
                    closing = "]" + "=" * level + "]"
                    end = source.find(closing, k + 1)
                    i = n if end == -1 else end + len(closing)
                    continue
            # Line comment.
            end = source.find("\n", i)
            i = n if end == -1 else end
            continue

        out.append(char)
        i += 1

    # Collapse whitespace so re-indentation is not reported as a change.
    lines = [line.strip() for line in "".join(out).split("\n")]
    return "\n".join(line for line in lines if line)


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)

    before, after = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    changed, missing, checked = [], [], 0

    for path in sorted(after.rglob("*.lua")):
        relative = path.relative_to(after)
        counterpart = before / relative
        if not counterpart.exists():
            missing.append(str(relative))
            continue
        checked += 1
        if strip_comments(counterpart.read_text(encoding="utf-8")) != \
           strip_comments(path.read_text(encoding="utf-8")):
            changed.append(str(relative))

    print(f"{checked} file(s) compared")
    if missing:
        print(f"\nnew file(s), not compared:\n  " + "\n  ".join(missing))
    if changed:
        print(f"\ncode changed in {len(changed)} file(s):\n  " + "\n  ".join(changed))
        return 1
    print("\ncode identical everywhere -- only comments differ")
    return 0


if __name__ == "__main__":
    sys.exit(main())
