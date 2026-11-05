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
		eq(w, s.cols * s.w, key .. " width")
		eq(h, math.ceil(s.frames / s.cols) * s.h, key .. " height")
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
	App:init({ size = 24 })
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
