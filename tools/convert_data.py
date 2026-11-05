#!/usr/bin/env python3
"""Convert OpenSGolf's rule tables (`sgtool dump-data <dir>` writes <dir>/data/*.toml) into core/data/*.lua.

    python tools/convert_data.py <dump-dir>

Each TOML file becomes a Lua module returning the same structure; its header comment (field meanings) is kept.
Needs Python 3.11+ (tomllib).
"""

import pathlib
import re
import sys
import tomllib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "core" / "data"
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_key(k: str) -> str:
    return k if IDENT.match(k) and k not in LUA_KEYWORDS else f"[{lua_str(k)}]"


def lua_value(v, indent: int) -> str:
    pad = "\t" * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        if all(isinstance(x, (int, float, str, bool)) for x in v):
            return "{ " + ", ".join(lua_value(x, 0) for x in v) + " }"
        inner = "".join(f"{pad}\t{lua_value(x, indent + 1)},\n" for x in v)
        return "{\n" + inner + pad + "}"
    if isinstance(v, dict):
        if all(not isinstance(x, (list, dict)) for x in v.values()) and len(v) <= 16:
            return "{ " + ", ".join(f"{lua_key(k)} = {lua_value(x, 0)}" for k, x in v.items()) + " }"
        inner = "".join(f"{pad}\t{lua_key(k)} = {lua_value(x, indent + 1)},\n" for k, x in v.items())
        return "{\n" + inner + pad + "}"
    raise TypeError(f"unsupported value {v!r}")


def convert(src: pathlib.Path) -> pathlib.Path:
    text = src.read_text(encoding="utf-8")
    header = []
    for line in text.splitlines():
        if not line.startswith("#"):
            break
        header.append("--" + line[1:])
    data = tomllib.loads(text)
    out = OUT / (src.stem + ".lua")
    body = "\n".join(header)
    body += f"\n-- Converted from OpenSGolf's {src.name} by tools/convert_data.py; edit the values here.\n\n"
    body += "return " + lua_value(data, 0) + "\n"
    out.write_text(body, encoding="utf-8")
    return out


def main(argv) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    src = pathlib.Path(argv[1])
    folder = src / "data" if (src / "data").is_dir() else src
    files = sorted(folder.glob("*.toml"))
    if not files:
        print(f"no .toml files in {folder}", file=sys.stderr)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    for f in files:
        print(f"{f.name} -> {convert(f).relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
