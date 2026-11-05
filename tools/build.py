#!/usr/bin/env python3
"""Assemble the Garry's Mod gamemode and the LÖVE game from the shared source.

    python tools/build.py          build both
    python tools/build.py gmod     dist/gmod/simgolf/   (the Workshop addon; copy into garrysmod/addons/)
    python tools/build.py love     dist/love/  and  dist/simgolf.love

Works on Windows and Linux with Python 3.8+. No dependencies.
"""

import json
import re
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


# gmad's upload whitelist (github.com/garrynewman/gmad, include/AddonWhiteList.h), in order: a "!" entry cancels
# earlier matches. "*" matches any characters, "/" included. Every file in the GMod build must pass it.
GMAD_WHITELIST = [
    "lua/*.lua", "scenes/*.vcd", "particles/*.pcf", "resource/fonts/*.ttf", "scripts/vehicles/*.txt",
    "resource/localization/*/*.properties", "maps/*.bsp", "maps/*.lmp", "maps/*.nav", "maps/*.ain", "maps/thumb/*.png",
    "sound/*.wav", "sound/*.mp3", "sound/*.ogg", "materials/*.vmt", "materials/*.vtf", "materials/*.png",
    "materials/*.jpg", "materials/*.jpeg", "materials/colorcorrection/*.raw", "models/*.mdl", "models/*.phy",
    "models/*.ani", "models/*.vvd", "models/*.vtx", "!models/*.sw.vtx", "!models/*.360.vtx", "!models/*.xbox.vtx",
    "gamemodes/*/*.txt", "!gamemodes/*/*/*.txt", "gamemodes/*/*.fgd", "!gamemodes/*/*/*.fgd", "gamemodes/*/logo.png",
    "gamemodes/*/icon24.png", "gamemodes/*/gamemode/*.lua", "gamemodes/*/entities/effects/*.lua",
    "gamemodes/*/entities/weapons/*.lua", "gamemodes/*/entities/entities/*.lua", "gamemodes/*/backgrounds/*.png",
    "gamemodes/*/backgrounds/*.jpg", "gamemodes/*/backgrounds/*.jpeg", "data_static/*.txt", "data_static/*.dat",
    "data_static/*.json", "data_static/*.xml", "data_static/*.csv", "shaders/fxc/*.vcs",
]


def gmad_allows(rel: str) -> bool:
    ok = False
    for pattern in GMAD_WHITELIST:
        neg = pattern.startswith("!")
        regex = "^" + re.escape(pattern.lstrip("!")).replace(r"\*", ".*") + "$"
        if re.match(regex, rel.lower()):
            ok = not neg
    return ok


def build_gmod() -> None:
    """The Workshop addon: the gamemode's code under gamemodes/<id>/, the free pack's pictures and sounds at the addon
    root (materials/, sound/), as gmpublish takes it. Install by copying dist/gmod/<id>/ to garrysmod/addons/<id>/."""
    out = fresh(DIST / "gmod" / GAME_ID)
    gm = out / "gamemodes" / GAME_ID
    n = copy_tree(ROOT / "gmod", gm)
    n += copy_tree(ROOT / "core", gm / "gamemode" / "core")
    n += copy_tree(ROOT / "platform" / "gmod", gm / "gamemode" / "platform" / "gmod")
    free = ROOT / "packs" / "free"
    n += copy_tree(free / "materials", out / "materials")
    n += copy_tree(free / "sound", out / "sound")
    n += copy_tree(free / "lua" / GAME_ID / "packs" / "free", gm / "gamemode" / "packs" / "free")
    (out / "addon.json").write_text(json.dumps({
        "title": "SimGolf (working title)",
        "type": "gamemode",
        "tags": ["fun", "build"],
        "ignore": [],
    }, indent="\t") + "\n", encoding="utf-8")

    bad = [r for r in (p.relative_to(out).as_posix() for p in out.rglob("*") if p.is_file())
           if r != "addon.json" and not gmad_allows(r)]
    if bad:
        raise SystemExit("files gmad would refuse:\n  " + "\n  ".join(bad[:50]))
    print(f"gmod: {n + 1} files -> {out.relative_to(ROOT)} (all pass gmad's whitelist)")


def build_love() -> None:
    out = fresh(DIST / "love")
    n = copy_tree(ROOT / "love", out)
    n += copy_tree(ROOT / "core", out / "core")
    n += copy_tree(ROOT / "platform" / "love", out / "platform" / "love")
    n += copy_tree(ROOT / "packs", out / "packs")

    packed = DIST / f"{GAME_ID}.love"
    with zipfile.ZipFile(packed, "w", zipfile.ZIP_DEFLATED) as z:
        for path in sorted(out.rglob("*")):
            if path.is_file():
                # pictures and sounds are already compressed
                kind = zipfile.ZIP_STORED if path.suffix.lower() in {".png", ".jpg", ".ogg", ".mp3"} else zipfile.ZIP_DEFLATED
                z.write(path, path.relative_to(out).as_posix(), compress_type=kind)
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
