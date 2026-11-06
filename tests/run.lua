-- Core tests, run from the repository root with LuaJIT (the Lua that GMod and LÖVE use):
--
--   luajit tests/run.lua            all tests
--   luajit tests/run.lua terrain    tests whose name contains "terrain"
--
-- They boot the core on a headless platform (tests/headless.lua) with the repository's own packs/.

local ROOT = (arg and arg[0] and arg[0]:match("^(.*)tests[/\\]run%.lua$")) or "./"
local filter = arg and arg[1]

local function loadFile(path)
	return assert(loadfile(ROOT .. path))()
end

local impl = loadFile("tests/headless.lua")(ROOT)
local Game = loadFile("core/init.lua")(loadFile, impl)

local tests, failed, ran = {}, 0, 0
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local function eq(a, b, what)
	if a ~= b then error(("%s: expected %s, got %s"):format(what or "value", tostring(b), tostring(a)), 2) end
end

------------------------------------------------------------------------------------------------ core

test("hook: order, replace, remove, first return wins", function()
	local H = Game.Hook
	local seen = {}
	H.Add("T1", "a", function() seen[#seen + 1] = "a" end)
	H.Add("T1", "b", function(x) seen[#seen + 1] = "b"; return x * 2 end)
	H.Add("T1", "c", function() seen[#seen + 1] = "c" end)
	eq(H.Run("T1", 21), 42, "result")
	eq(table.concat(seen), "ab", "order")
	H.Add("T1", "a", function() seen[#seen + 1] = "A" end)
	seen = {}; H.Run("T1", 1); eq(table.concat(seen), "Ab", "replaced in place")
	H.Remove("T1", "b")
	seen = {}; H.Run("T1", 1); eq(table.concat(seen), "Ac", "removed")
end)

test("platform: every function implemented by the headless platform", function()
	eq(#Game.Platform.missing, 0, "missing")
end)

test("rng: same sequence as OpenSGolf's xorshift32", function()
	local r = Game.require("rng").new(7)
	local want = { 1892583, 470389255, 3882205507, 3069989445, 2854842367 }
	for i, w in ipairs(want) do eq(r:next(), w, "value " .. i) end
end)

test("data: rule tables load", function()
	eq(#Game.Data.terrain.terrain > 20, true, "terrain rows")
	eq(Game.Data.terrain.terrain[1].id, "tee", "first row")
	eq(type(Game.Data.economy.economy), "table", "economy")
end)

------------------------------------------------------------------------------------------------ terrain

local T = Game.require("terrain")

test("terrain: blend lookup matches the original table", function()
	eq(T.blendVariation(0, 0, 0), 0)
	eq(T.blendVariation(1, 0, 0), 4)
	eq(T.blendVariation(0, 1, 0), 0)
	eq(T.blendVariation(1, 1, 1), 3)
	eq(T.blendVariation(2, 2, 2), 7)
end)

test("terrain: view phases turn texture coordinates a quarter", function()
	local u, v = T.viewUV(0, 0, 1); eq(u, 0); eq(v, 1)
	u, v = T.viewUV(0, 0, 2); eq(u, 1); eq(v, 1)
	u, v = T.viewUV(0, 0, 3); eq(u, 1); eq(v, 0)
end)

test("terrain: a slope's patch heights are the corner averages", function()
	local t = T.new(3, 3, T.ROUGH)
	-- tile (1, 1): corners NW 0, NE 2, SW 0, SE 2
	t.corner[1 * 4 + 2 + 1] = 2
	t.corner[2 * 4 + 2 + 1] = 2
	local h = t:patchHeights(1, 1)
	eq(h[2][1], 0); eq(h[2][2], T.HEIGHT_STEP); eq(h[2][3], 2 * T.HEIGHT_STEP)
end)

test("terrain: flat ground normals point straight up", function()
	local t = T.new(5, 5, T.ROUGH)
	local n = t:vertexNormals(2, 2)
	for j = 1, 3 do for k = 1, 3 do
		eq(n[j][k][1], 0); eq(n[j][k][2], 1); eq(n[j][k][3], 0)
	end end
end)

test("terrain: demo course matches OpenSGolf's (50 x 50, seed 7)", function()
	local t = T.demoCourse(50, 50, 7)
	local csum, ssum, tsum = 0, 0, 0
	for i, c in ipairs(t.corner) do csum = csum + i * c end
	for i, s in ipairs(t.set) do ssum = ssum + i * s end
	for i, ty in ipairs(t.ty) do tsum = tsum + i * ty end
	-- printed by OpenSGolf v0.6.10's Terrain::demo_course(50, 50, 7)
	eq(csum, 19071167, "corner checksum")
	eq(ssum, 6270265, "set checksum")
	eq(tsum, 27460642, "type checksum")
	eq(t.clubhouseX, 11); eq(t.clubhouseY, 41)

	-- and every triangle's texture type, set and blend variation (build_tile_triangles, water_one off)
	local sum, n = 0, 0
	for y = 0, 49 do for x = 0, 49 do
		local out = {}
		T.buildTileTriangles(t, x, y, out)
		for _, tri in ipairs(out) do
			n = n + 1
			sum = sum + n * (tri[1] * 1000 + tri[2] * 10 + tri[3])
		end
	end end
	eq(n, 20000, "triangles")
	eq(sum, 1778219915634, "triangle checksum")
end)

------------------------------------------------------------------------------------------------ land

local L = Game.require("land")

test("land: the generator matches OpenSGolf's (7 deals, fixes on and off)", function()
	local cases = {
	{ clock = 1, slot = 0, diff = 1, fixes = false, prop = 9, acres = 50, ty = 56066347, h = 12908696, flags = 157724715, var = 10196, margin = 14, club = { 18, 18 }, rng = 463229680, objs = "15:18,18:0:0 6:17,22:0:0 4:18,39:0:16", tcorner = 606818, tset = 6274922 },
	{ clock = 12345, slot = 5, diff = 2, fixes = false, prop = 4, acres = 110, ty = 47323676, h = 13245748, flags = 208874248, var = 18663, margin = 9, club = { 19, 17 }, rng = 3119281714, objs = "15:19,17:0:0 9:18,21:0:0 4:18,12:0:14 4:35,37:3:18 4:13,28:1:18", tcorner = 1412587, tset = 6347622 },
	{ clock = 777, slot = 12, diff = 3, fixes = false, prop = 2, acres = 180, ty = 44717013, h = 40795786, flags = 231663412, var = 25408, margin = 4, club = { 18, 24 }, rng = 143230916, objs = "15:18,24:0:0 13:17,28:0:0 4:40,15:1:16 4:18,14:0:16 4:8,38:0:16", tcorner = 21880217, tset = 6110430 },
	{ clock = 999, slot = 15, diff = 0, fixes = false, prop = 6, acres = 170, ty = 43512735, h = 13458000, flags = 378943919, var = 1408777, margin = 5, club = { 25, 30 }, rng = 3937447039, objs = "15:25,30:0:0 4:13,44:2:8 4:44,26:2:12 4:27,10:1:8 4:43,13:3:12 4:10,34:3:12 4:19,15:1:8 4:38,26:1:12", tcorner = 2054702, tset = 6450337 },
	{ clock = 4242, slot = 9, diff = 1, fixes = true, prop = 0, acres = 130, ty = 43051165, h = 15492626, flags = 181424171, var = 234560, margin = 7, club = { 29, 15 }, rng = 14212597, objs = "15:29,15:0:0 4:18,10:0:16", tcorner = 3580071, tset = 6257480 },
	{ clock = 31337, slot = 14, diff = 2, fixes = true, prop = 6, acres = 160, ty = 43466598, h = 14873417, flags = 354061150, var = 1478603, margin = 5, club = { 28, 26 }, rng = 1385014965, objs = "15:28,26:0:0 -1:40,9:2:8 -1:39,5:3:12 -1:6,44:0:8 4:39,34:2:12 4:31,17:0:8 4:38,40:0:12 4:7,15:1:17 4:42,29:3:17", tcorner = 4889893, tset = 6450337 },
	{ clock = 5, slot = 3, diff = 1, fixes = true, prop = 3, acres = 80, ty = 50791613, h = 13334549, flags = 147201950, var = 870, margin = 11, club = { 26, 17 }, rng = 282639512, objs = "15:26,17:0:0 4:17,19:0:18", tcorner = 1093540, tset = 6280667 },
	}
	local function sum(t, from, to) local s = 0 for i = from, to do s = s + (i + 1) * (t[i] or 0) end return s end
	local function sum1(t, n) local s = 0 for i = 1, n do s = s + i * (t[i] or 0) end return s end
	for _, c in ipairs(cases) do
		local land, offer, rng = L.newGame({ clock = c.clock, slot = c.slot, difficulty = c.diff, fixes = c.fixes })
		local objs = {}
		for _, o in ipairs(land.objects) do objs[#objs + 1] = ("%d:%d,%d:%d:%d"):format(o.kind, o.a, o.b, o.dir, o.sub) end
		local t = land:toTerrain()
		local got = { prop = offer[c.slot].property, acres = offer[c.slot].acres, ty = sum(land.ty, 0, 2499),
			h = sum(land.height, 0, 2600), flags = sum(land.flags, 0, 2499), var = sum(land.var, 0, 2499), margin = land.margin,
			rng = rng.state, objs = table.concat(objs, " "), tcorner = sum1(t.corner, 51 * 51), tset = sum1(t.set, 2500) }
		for _, k in ipairs({ "prop", "acres", "ty", "h", "flags", "var", "margin", "rng", "objs", "tcorner", "tset" }) do
			eq(got[k], c[k], ("clock %d %s"):format(c.clock, k))
		end
	end
end)

test("land: the offer follows the exe's rules", function()
	for seed = 0, 30 do
		local offer = L.dealOffer(L.ExeRng.fromClock(seed * 7919), false)
		local seen, themes = {}, {}
		for i = 0, 15 do
			assert(not seen[offer[i].property], "dealt twice")
			seen[offer[i].property] = true
		end
		eq(L.records()[offer[0].property].theme, 0, "slot 0 is Parkland")
		for i = 12, 15 do themes[L.records()[offer[i].property].theme] = true end
		eq(#({ themes[0], themes[1], themes[2], themes[3] }), 4, "four themes in the dear slots")
	end
end)

------------------------------------------------------------------------------------------------ packs

local Packs = Game.require("pack")

local function pngSize(file)
	local f = io.open(file, "rb")
	if not f then return nil end
	local d = f:read(24)
	f:close()
	if not d or d:sub(2, 4) ~= "PNG" then return nil end
	local function u32(s, i) local a, b, c, e = s:byte(i, i + 3); return ((a * 256 + b) * 256 + c) * 256 + e end
	return u32(d, 17), u32(d, 21)
end

test("pack: the free pack is installed and loads", function()
	local found = false
	for _, id in ipairs(Packs.list()) do if id == "free" then found = true end end
	eq(found, true, "free pack listed")
	local p = Packs.get("free")
	eq(p.info.waterOneLook, true, "water one look")
	local n = 0
	for _ in pairs(p.sprites) do n = n + 1 end
	eq(n, 1893, "sprites")
end)

test("pack: every theme has a catalog with fairway, green and water", function()
	for _, theme in ipairs({ "parkland", "desert", "tropical", "links" }) do
		local cat = Packs.terrain(theme)
		assert(cat, theme)
		for _, ty in ipairs({ T.FAIRWAY, T.PUTTING_GREEN, T.WATER_SHALLOW, T.TEE }) do
			assert(cat.cellFor(ty, 0, 0), theme .. " type " .. ty)
		end
		local w, h = pngSize(impl.imageFile(cat.image))
		eq(w, 2048, theme .. " atlas width"); eq(h, 2048, theme .. " atlas height")
	end
end)

test("pack: sprite sheets have the size their manifest says", function()
	local checked = 0
	for key, s in pairs(Packs.get("free").sprites) do
		local w, h = pngSize(impl.imageFile("free/" .. s.file))
		assert(w, "missing sheet for " .. key)
		eq(w, s.sheetW, key .. " width"); eq(h, s.sheetH, key .. " height")
		-- powers of two (GMod resizes anything else), big enough for every frame
		local function pow2(n) return n > 0 and 2 ^ math.floor(math.log(n) / math.log(2) + 0.5) == n end
		assert(pow2(w) and pow2(h), key .. " sheet " .. w .. " x " .. h .. " is not a power of two")
		assert(w >= s.cols * s.w and h >= math.ceil(s.frames / s.cols) * s.h, key .. " frames fit")
		eq(s.frames, s.views * s.fpv, key .. " frames")
		checked = checked + 1
	end
	eq(checked, 1893, "sheets checked")
end)

------------------------------------------------------------------------------------------------ view

local Camera = Game.require("client/camera")
local TerrainView = Game.require("client/terrain_view")

test("camera: panning by a screen offset moves the ground under it by that offset", function()
	local c = Camera.new()
	c.zoom = 0.7
	for rot = 0, 3 do
		c:setRotation(rot)
		c.x, c.z = 120, -340
		local ax, ay = c:project(c.x, 0, c.z)
		c:panScreen(35, -12)
		local bx, by = c:project(c.x, 0, c.z)
		assert(near((bx - ax) * c.zoom, 35, 1e-6) and near((by - ay) * c.zoom, -12, 1e-6), "rotation " .. rot)
	end
end)

test("camera: view 0 shows world -X down and to the left", function()
	local c = Camera.new()
	local x, y = c:project(-100, 0, 0)
	assert(x < 0 and y > 0)
end)

test("light: Terrain.dll's direction and flat ground shading", function()
	local L = TerrainView.LIGHT
	assert(near(L[1], -0.7570, 1e-3) and near(L[2], 0.6409, 1e-3) and near(L[3], -0.1271, 1e-3))
end)

test("terrain view: 8 clockwise triangles per tile, texture coordinates inside their atlas cell", function()
	local t = T.demoCourse(20, 20, 3)
	local cam = Camera.new()
	for rot = 0, 3 do
		cam:setRotation(rot)
		local view = TerrainView.new(t, "parkland", cam)
		local verts, count = view:buildVertices()
		eq(count, 20 * 20 * 8, "triangles")
		eq(#verts, count * 24, "vertex values")
		for i = 1, #verts, 24 do
			local ax, ay, bx, by, cx, cy = verts[i], verts[i + 1], verts[i + 8], verts[i + 9], verts[i + 16], verts[i + 17]
			assert((bx - ax) * (cy - ay) - (by - ay) * (cx - ax) >= 0, "clockwise")
			for k = 0, 2 do
				local u, v = verts[i + k * 8 + 2], verts[i + k * 8 + 3]
				assert(u >= 0 and u <= 1 and v >= 0 and v <= 1, "uv in atlas")
			end
		end
	end
end)

test("app: boots, draws a frame and reacts to input", function()
	local App = Game.require("client/app")
	App:init({ seed = 7 })
	App:draw(1280, 720)
	assert(impl.draws.meshes > 0, "terrain drawn")
	assert(impl.draws.images > 0, "trees drawn")
	local rot = App.camera.rot
	App:keyPressed("q")
	eq(App.camera.rot, (rot + 1) % 4, "rotated")
	local x = App.camera.x
	impl.keysDown.d = true
	App:update(0.1)
	impl.keysDown.d = nil
	assert(App.camera.x ~= x, "panned")
	local z = App.camera.zoom
	App:wheel(1, 1280, 720)
	assert(App.camera.zoom > z, "zoomed in")
end)

------------------------------------------------------------------------------------------------ course

local Course = Game.require("course")

test("course: the exe's angle and heading match OpenSGolf's", function()
	local s = 0
	for dx = -7, 7 do
		for dy = -7, 7 do
			local a = Course.angle(dx, dy)
			s = s + math.floor(a / 65536) * ((dx + 8) * 17 + dy + 8) + Course.dir8(a)
		end
	end
	eq(s, 795607848, "angle checksum")
end)

test("course: a new game starts with the property's price paid", function()
	local c = Course.new({ clock = 7, slot = 0 })
	eq(c.cash, 100000 - 50000, "cash")
	eq(c.nextHole, 1, "next hole")
	eq(c:openHoles(), 0, "holes")
	local s = Course.new({ clock = 7, slot = 0, sandbox = true })
	eq(s.cash, 1000000, "sandbox cash")
end)

test("course: elevation edits match OpenSGolf's (clock 7, slot 0)", function()
	local c = Course.new({ clock = 7, slot = 0 })
	local edits = { { 0, 20, 20, true }, { 0, 20, 20, true }, { 1, 21, 21, true }, { 2, 25, 25, true }, { 2, 25, 25, true },
		{ 2, 25, 25, true }, { 0, 30, 12, false }, { 2, 30, 12, false }, { 1, 12, 30, false }, { 2, 26, 24, false },
		{ 0, 0, 0, true }, { 1, 50, 50, true } }
	for _, e in ipairs(edits) do c:elevate(e[1], e[2], e[3], e[4]) end
	local sum = 0
	for i, v in ipairs(c.terrain.corner) do sum = sum + i * v end
	eq(sum, 593970, "corner checksum")
	-- the land follows: our corner (cx, cy) is the land's vertex (cx, cy - 1)
	eq(c.land:corner(25, 24), c.terrain.corner[25 * 51 + 25 + 1] + 3, "land height")
end)

test("course: tees, greens and opening holes follow OpenSGolf's hole tool", function()
	local c = Course.new({ clock = 7, slot = 0 })
	local tys = {}
	for i = 0, 2499 do tys[i] = 4 end
	-- a, b, new type, then what OpenSGolf gives: paint goes ahead, next hole, hole opened, its par and length, tile flags
	local steps = {
		{ 10, 10, 0, true, 1, nil, 0, 0, 1 }, { 10, 22, 1, true, 2, 1, 4, 312, 129 }, { 11, 22, 1, true, 2, nil, 0, 0, 0 },
		{ 10, 11, 0, true, 2, nil, 0, 0, 2 }, { 30, 30, 1, true, 3, 2, 6, 798, 130 }, { 14, 5, 0, true, 3, nil, 0, 0, 3 },
		{ 14, 40, 1, true, 4, 3, 6, 1031, 131 }, { 10, 10, 4, true, 1, nil, 0, 0, 16384 }, { 10, 9, 0, true, 4, 1, 4, 312, 16385 },
	}
	for n, s in ipairs(steps) do
		local a, b, new = s[1], s[2], s[3]
		local i = a * 50 + b
		local old = tys[i]
		local function g(x, y) return x >= 0 and y >= 0 and x < 50 and y < 50 and tys[x * 50 + y] == 1 end
		local ok = c:paintHoleTile(a, b, old, new, g(a + 1, b) or g(a - 1, b) or g(a, b + 1) or g(a, b - 1))
		if ok then tys[i] = new end
		local opened = c:canOpenHole() and c:openHole() or nil
		eq(ok, s[4], "step " .. n .. " ok")
		eq(c.nextHole, s[5], "step " .. n .. " next hole")
		eq(opened, s[6], "step " .. n .. " opened")
		eq(c.holes[opened or 0].par, s[7], "step " .. n .. " par")
		eq(c.holes[opened or 0].length, s[8], "step " .. n .. " length")
		eq(c.flags[i], s[9], "step " .. n .. " flags")
	end
end)

test("course: painting charges the rule tables' costs and refuses what it must", function()
	local c = Course.new({ clock = 7, slot = 0 })
	local land, t = c.land, c.terrain
	-- an owned rough tile with nothing on it
	local a, b
	for x = 5, 44 do
		for y = 5, 44 do
			if not a and land:inPlay(x, y) and t:typeAt(x, y) == 4 and bit.band(land.flags[x * 50 + y], 0x8400) == 0 then a, b = x, y end
		end
	end
	assert(a, "a rough tile")
	local cash = c.cash
	local spent = c:paint({ { a, b } }, 2, 0)
	eq(spent, 300, "fairway over rough costs the fairway")
	eq(c.cash, cash - 300, "cash")
	eq(t:typeAt(a, b), 2, "painted")
	eq(land.ty[a * 50 + b], 2, "land follows")
	eq(c:paint({ { a, b } }, 2, 0), 0, "same type is free")
	-- trees cost their clearing too
	c:paint({ { a, b } }, 13, 0)
	eq(c:paint({ { a, b } }, 4, 0), 100 + 500, "rough over a tree: rough plus clearing")
	-- not enough money: refused after three holes, allowed before
	c.cash = 0
	eq(c:paint({ { a, b } }, 17, 0), 5000, "under three holes the bank lends")
	for h = 1, 3 do c.holes[h].par = 3 end
	eq(c:paint({ { a, b } }, 4, 0), 0, "now refused")
	local ev = c:takeEvents()
	local toast
	for _, e in ipairs(ev) do if e.type == "toast" then toast = e.text end end
	eq(toast, "You don't have enough money.", "toast")
	-- the clubhouse is never painted over
	local ca, cb = land.clubhouse[1], land.clubhouse[2]
	c.cash = 1e6
	eq(c:paint({ { ca, cb } }, 2, 0), 0, "clubhouse refused")
end)

test("course: buildings go down with their price and unlock with holes", function()
	local c = Course.new({ clock = 7, slot = 0 })
	eq(c:buildAvailable(7), false, "snack bar locked at first")
	eq(Course.unlockedFor(2), 7, "two holes unlock the putting green")
	eq(Course.unlockedFor(3), 8, "three the snack bar")
	c.unlocked = 8
	c.cash = 1e6
	local land = c.land
	local spot
	for a = 3, 44 do
		for b = 3, 44 do
			if not spot and c:buildQuote(7, a, b) then spot = { a, b } end
		end
	end
	assert(spot, "room for a snack bar")
	local cost = c:buildQuote(7, spot[1], spot[2])
	assert(cost >= 15000, "snack bar price")
	assert(c:build(7, spot[1], spot[2], 1), "built")
	eq(c.cash, 1e6 - cost, "paid")
	local o = land.objects[#land.objects]
	eq(o.kind, 7, "object")
	eq(o.dir, 1, "facing")
	eq(c.terrain:typeAt(spot[1], spot[2]), 22, "building tile")
	assert(not c:buildQuote(7, spot[1], spot[2]), "no room on top of it")
	-- the property's own putting green: a second one is an upgrade, which needs a Country Club course
	local _, why = c:buildQuote(6, 10, 10)
	eq(why, "Upgrades need a Country Club course", "no upgrade yet")
end)

test("course: the app paints, builds and opens a hole through its tools", function()
	local App = Game.require("client/app")
	App:init({ seed = 7 })
	Game.require("client/demo")(App)
	assert(App.course:openHoles() >= 2, "demo holes open")
	App:draw(1280, 720)
	assert(impl.draws.polys and impl.draws.polys > 0, "ui drawn")
	-- the paint tool through the mouse
	App.course.cash = 1e6
	local land = App.course.land
	local a, b
	for x = 5, 44 do
		for y = 5, 44 do
			if not a and land:inPlay(x, y) and App.terrain:typeAt(x, y) == 4 and bit.band(land.flags[x * 50 + y], 0x8400) == 0 then a, b = x, y end
		end
	end
	App.camera.x, App.camera.z = App.terrain:tileCentre(a, b)
	App:setTool("paint")
	App:pickBrush(5)
	App:mouseMoved(640, 360)
	assert(App.hover and App.hover.a == a and App.hover.b == b, "the tile at the view centre is under the mouse")
	App:mousePressed(640, 360, "left")
	App:mouseReleased(640, 360, "left")
	eq(App.terrain:typeAt(a, b), 5, "painted deep rough under the mouse")
	-- the building tool shows its price and puts down a ball washer
	App:setTool("build")
	App.buildKind = 3
	App:draw(1280, 720)
	local n = #land.objects
	App:mousePressed(640, 360, "left")
	App:mouseReleased(640, 360, "left")
	eq(#land.objects, n + 1, "ball washer built")
	App:draw(1280, 720)
end)

------------------------------------------------------------------------------------------------ run

for _, t in ipairs(tests) do
	if not filter or t.name:find(filter, 1, true) then
		ran = ran + 1
		local ok, err = pcall(t.fn)
		if ok then
			print("ok    " .. t.name)
		else
			failed = failed + 1
			print("FAIL  " .. t.name .. "\n      " .. tostring(err))
		end
	end
end
print(("%d tests, %d failed"):format(ran, failed))
os.exit(failed == 0 and 0 or 1)
