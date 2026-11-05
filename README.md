# SimGolf (working title)

A Garry's Mod gamemode that rebuilds Sid Meier's SimGolf (2002), ported to Lua from
[OpenSGolf](https://github.com/crspytopgn/opensgolf). The same code is written to run later as a standalone
[LÖVE](https://love2d.org) game.

- Plays like SimGolf by default; runs without the original game files (free asset set)
- Asset packs (free, converted original, community) switchable by the server admin
- Gameplay addons that change rules and add content, with a vanilla mode
- Modern UI; multiplayer with the server running the simulation

Status: **Phase 1, foundation.** Nothing playable yet. The full plan is in [docs/PLAN.md](docs/PLAN.md).

## Layout

```
core/            shared game code; never touches GMod or LÖVE directly
platform/gmod/   GMod implementation of the Platform interface (core/platform.lua)
platform/love/   LÖVE implementation
gmod/            gamemode entry files
love/            LÖVE entry files
tools/build.py   assembles dist/gmod/simgolf/ and dist/love/
site/            project website (GitHub Pages)
docs/            plan and notes
```

## Building

Needs Python 3.8+.

```
python tools/build.py          # both
python tools/build.py gmod     # dist/gmod/simgolf/  -> copy to garrysmod/gamemodes/simgolf/
python tools/build.py love     # dist/love/ and dist/simgolf.love -> run with LÖVE 11.4+
```

## Licence

GPL-2.0-or-later, the same as OpenSGolf. See [LICENSE](LICENSE).

Not affiliated with Electronic Arts, Maxis or Firaxis. SimGolf is a trademark of its owner; the original game's
files are not included and are never needed.
