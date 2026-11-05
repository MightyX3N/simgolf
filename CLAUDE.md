# Working on this repo

SimGolf remake for Garry's Mod, written so the same Lua also runs as a standalone LÖVE game. The plan is in
docs/PLAN.md. Rules and numbers come from OpenSGolf (https://github.com/crspytopgn/opensgolf, tag v0.6.10); when
porting a rule, read its Rust source and port it faithfully, then add a parity test.

## Layout rules

- `core/` never touches GMod or LÖVE globals. It reaches the engine only through `Game.Platform` (core/platform.lua
  lists every function). Modules other than info/hook/platform return `function(Game)` and load with
  `Game.require("name")`.
- `platform/gmod/` and `platform/love/` implement the Platform interface. A new Platform function goes into
  core/platform.lua's spec, both platforms and tests/headless.lua.
- No `.md` files inside anything that ends up in the GMod build (the Workshop refuses them); tools/build.py skips them.
- `packs/free/` is generated (see below); don't edit it by hand.

## Commands (run from the repo root)

```
luajit tests/run.lua                      core tests (headless platform, real packs/); filter: luajit tests/run.lua terrain
python3 tools/build.py                    dist/gmod/simgolf/ and dist/love/ + dist/simgolf.love
luajit tests/gmod_smoke.lua dist/gmod/ client   built gamemode against stand-ins for GMod's API (also: server)
python3 tools/screenshot.py out.png --view X,Z,ZOOM,ROT   LÖVE screenshot (uses xvfb-run on a headless Linux box)
```

Tools needed: LuaJIT, Python 3.11+, LÖVE 11.4+, xvfb (Linux, headless). On Ubuntu: `apt-get install luajit love xvfb`.
Garry's Mod itself can't run here; tests/gmod_smoke.lua only proves the files load and every call exists, so say so
when a change has only been checked that way.

## Regenerating the free pack and the rule tables

```
git clone --depth 1 --branch v0.6.10 https://github.com/crspytopgn/opensgolf
cd opensgolf && cargo build --release -p sgtool
./target/release/sgtool freeset /tmp/free && ./target/release/sgtool dump-data /tmp/data
cd <this repo>
cargo build --release --manifest-path tools/export-pack/Cargo.toml
tools/export-pack/target/release/export-pack /tmp/free packs/free --id free --name "Free (OpenSGolf)" --water-one-look
python3 tools/convert_data.py /tmp/data
```

Delete `packs/free` before exporting into it again. The same exporter turns an original SimGolf install into a pack
(no `--water-one-look` there).

## Comparing with OpenSGolf

Its app renders the same demo course: build `cargo build --release -p opensgolf`, then
`SG_PICK_FOLDER=free xvfb-run -a opensgolf --size 1280x720 --seed 7 --mute --png out.png --time 0.2`
(needs libudev-dev, libasound2-dev, libgl1-mesa-dev, libx11-dev, libxi-dev).
