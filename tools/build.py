#!/usr/bin/env python3
"""Assemble the Garry's Mod gamemode and the LÖVE game from the shared source.

    python tools/build.py          build both
    python tools/build.py gmod     dist/gmod/simgolf/   (copy into garrysmod/gamemodes/)
    python tools/build.py love     dist/love/  and  dist/simgolf.love

Works on Windows and Linux with Python 3.8+. No dependencies.
"""

import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
GAME_ID = "simgolf"  # must match core/info.lua id

# The Workshop refuses .md files, and nothing else here belongs in a build.
SKIP_SUFFIXES = {".md"}
SKIP_NAMES = {".DS_Store", "Thumbs.db"}


def copy_tree(src: Path, dst: Path) -> int:
    count = 0
    for path in sorted(src.rglob("*")):
        if not path.is_file() or path.suffix.lower() in SKIP_SUFFIXES or path.name in SKIP_NAMES:
            continue
        target = dst / path.relative_to(src)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        count += 1
    return count


def fresh(path: Path) -> Path:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)
    return path


def build_gmod() -> None:
    out = fresh(DIST / "gmod" / GAME_ID)
    n = copy_tree(ROOT / "gmod", out)
    n += copy_tree(ROOT / "core", out / "gamemode" / "core")
    n += copy_tree(ROOT / "platform" / "gmod", out / "gamemode" / "platform" / "gmod")
    print(f"gmod: {n} files -> {out.relative_to(ROOT)}")


def build_love() -> None:
    out = fresh(DIST / "love")
    n = copy_tree(ROOT / "love", out)
    n += copy_tree(ROOT / "core", out / "core")
    n += copy_tree(ROOT / "platform" / "love", out / "platform" / "love")

    packed = DIST / f"{GAME_ID}.love"
    with zipfile.ZipFile(packed, "w", zipfile.ZIP_DEFLATED) as z:
        for path in sorted(out.rglob("*")):
            if path.is_file():
                z.write(path, path.relative_to(out).as_posix())
    print(f"love: {n} files -> {out.relative_to(ROOT)} and {packed.relative_to(ROOT)}")


def main(argv) -> int:
    targets = argv[1:] or ["gmod", "love"]
    builders = {"gmod": build_gmod, "love": build_love}
    unknown = [t for t in targets if t not in builders]
    if unknown:
        print(f"unknown target(s): {', '.join(unknown)}; use gmod and/or love", file=sys.stderr)
        return 2
    for t in targets:
        builders[t]()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
