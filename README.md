# SimGolf (working title)

A Garry's Mod gamemode that rebuilds Sid Meier's SimGolf (2002), ported to Lua from
[OpenSGolf](https://github.com/crspytopgn/opensgolf). The same code is written to run later as a standalone
[LÖVE](https://love2d.org) game.

- Plays like SimGolf by default; runs without the original game files (free asset set)
- Asset packs (free, converted original, community) switchable by the server admin
- Gameplay addons that change rules and add content, with a vanilla mode
- Modern UI; multiplayer with the server running the simulation

Status: **Phase 1, foundation.** The course view works: OpenSGolf's demo course drawn from the free asset pack with
the original's camera, terrain blending and lighting, trees, and pan / zoom / rotate. Nothing playable yet. The full
plan is in [docs/PLAN.md](docs/PLAN.md).

## Layout

```
core/               shared game code; never touches GMod or LÖVE directly
core/data/          rule tables (prices, terrain, golfers...) converted from OpenSGolf
core/client/        camera, terrain renderer, sprites, the course view
platform/gmod/      GMod implementation of the Platform interface (core/platform.lua)
platform/love/      LÖVE implementation
gmod/               gamemode entry files
love/               LÖVE entry files
packs/free/         the free asset pack (generated from OpenSGolf's free set, GPL-2.0-or-later)
tests/              core tests (LuaJIT) and a GMod smoke test
tools/build.py      assembles dist/gmod/simgolf/ and dist/love/
tools/export-pack/  turns OpenSGolf's free set or an original SimGolf install into an asset pack (Rust)
site/               project website (GitHub Pages)
docs/               plan and notes
```

## Building

Needs Python 3.8+.

```
python tools/build.py          # both
python tools/build.py gmod     # dist/gmod/simgolf/  -> copy to garrysmod/addons/simgolf/ (also what gets uploaded)
python tools/build.py love     # dist/love/ and dist/simgolf.love -> run with LÖVE 11.4+
```

In Garry's Mod, start a game with the SimGolf gamemode; the course view opens on its own (`simgolf_view` reopens it).
Controls: WASD, the arrow keys or dragging move the view, the wheel zooms, Q and E rotate.

## Tests

```
luajit tests/run.lua                             # core tests, including parity with OpenSGolf's demo course
luajit tests/gmod_smoke.lua dist/gmod/simgolf/ client   # the built addon against stand-ins for GMod's API (also: server)
```

More for developers in [CLAUDE.md](CLAUDE.md).

## Licence

GPL-2.0-or-later, the same as OpenSGolf. See [LICENSE](LICENSE).

Not affiliated with Electronic Arts, Maxis or Firaxis. SimGolf is a trademark of its owner; the original game's
files are not included and are never needed.
