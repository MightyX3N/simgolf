-- The course ground: tile types, corner heights and the rules Terrain.dll uses to turn them into textured triangles.
-- Ported from OpenSGolf's sg-core/src/terrain.rs (docs/TERRAIN.md there explains the original's rules).
--
-- Coordinates: tile (x, y) with 0 <= x < w, 0 <= y < h. World units: a tile is 100 wide; world x runs with tile x and world z
-- with tile y, centred on the map (x = tx * 100 - w * 50). Heights are corner levels, 15 world units each.

return function(Game)
	local Rng = Game.require("rng")
	local sqrt, floor, sin, cos, max, min = math.sqrt, math.floor, math.sin, math.cos, math.max, math.min

	local T = {}

	T.TILE_SIZE = 100
	T.HEIGHT_STEP = 15

	-- tile type ids (Terrain.dll's constructor; 27..35 are the port's paint-only ids)
	T.TEE, T.PUTTING_GREEN, T.FAIRWAY, T.FIRM_FAIRWAY, T.ROUGH, T.DEEP_ROUGH = 0, 1, 2, 3, 4, 5
	T.SAND, T.GRASSY_SAND, T.POT_SAND_BUNKER, T.OVERGROWTH, T.BRUSH, T.ROCK, T.WOODS = 7, 8, 9, 10, 11, 12, 13
	T.WATER_SHALLOW, T.MARSH, T.OVERGROWTH2, T.OUT_OF_BOUNDS, T.BUILDING = 17, 18, 19, 20, 22
	T.WATER_MIDDLE, T.WATER_DEEP, T.WATER_SHALLOW_DESERT, T.TRICKY_GREEN, T.SAND_BUNKER1 = 23, 24, 25, 26, 27

	-- texture file prefix per type id (nil: unnamed)
	T.NAMES = {
		[0] = "Tee", "PuttingGreen", "Fairway", "FirmFairway", "Rough", "DeepRough", nil, nil, "GrassySand", "PotSandBunker",
		"Overgrowth", "Brush", "Rock", "Woods", nil, nil, nil, "WaterShallow", "Marsh", "Overgrowth", nil, nil, "Building",
		"WaterMiddle", "WaterDeep", "WaterShallowDesert", "TrickyGreen", "SandBunker1", "SandBunker2", "SandBunker3",
		"SandBunker4", "Cliff", "Ravine", "FlowerBed", "ZenSand", "GrassBunker",
	}
	T.TYPE_COUNT = 36

	------------------------------------------------------------------------------------------------ the grid

	local Terrain = {}
	Terrain.__index = Terrain
	T.Terrain = Terrain

	-- A flat course of one type. Arrays are 1-based: tile (x, y) is index y * w + x + 1, corner (cx, cy) is cy * (w + 1) + cx + 1.
	function T.new(w, h, fill)
		local t = setmetatable({ w = w, h = h, ty = {}, variation = {}, set = {}, corner = {}, desert = false, waterOne = false }, Terrain)
		for i = 1, w * h do
			t.ty[i], t.variation[i], t.set[i] = fill or T.ROUGH, 0, 0
		end
		for i = 1, (w + 1) * (h + 1) do t.corner[i] = 0 end
		return t
	end

	function Terrain:inside(x, y) return x >= 0 and y >= 0 and x < self.w and y < self.h end
	function Terrain:index(x, y) return y * self.w + x + 1 end
	function Terrain:typeAt(x, y)
		if not self:inside(x, y) then return -1 end
		return self.ty[y * self.w + x + 1]
	end
	function Terrain:cornerAt(cx, cy)
		cx = max(0, min(self.w, cx)); cy = max(0, min(self.h, cy))
		return self.corner[cy * (self.w + 1) + cx + 1]
	end

	-- corner levels of a tile: north-west, north-east, south-west, south-east
	function Terrain:tileLevels(x, y)
		return self:cornerAt(x, y), self:cornerAt(x + 1, y), self:cornerAt(x, y + 1), self:cornerAt(x + 1, y + 1)
	end

	-- heights of a tile's 3 x 3 vertex patch, [row j along z][column k along x] (1-based), sand (type 7) dished 13 units
	function Terrain:patchHeights(tx, ty)
		local a, b, c, d = self:tileLevels(tx, ty)
		local S = T.HEIGHT_STEP
		a, b, c, d = a * S, b * S, c * S, d * S
		local hgt = {}
		for j = 0, 2 do
			local row = {}
			local fy = j * 0.5
			for k = 0, 2 do
				local fx = k * 0.5
				row[k + 1] = (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
			end
			hgt[j + 1] = row
		end
		if self:typeAt(tx, ty) == T.SAND then
			local dish = 13
			local function sand(dx, dy) return self:typeAt(tx + dx, ty + dy) == T.SAND end
			hgt[2][2] = hgt[2][2] - dish
			if sand(0, -1) then hgt[1][2] = hgt[1][2] - dish end
			if sand(0, 1) then hgt[3][2] = hgt[3][2] - dish end
			if sand(-1, 0) then hgt[2][1] = hgt[2][1] - dish end
			if sand(1, 0) then hgt[2][3] = hgt[2][3] - dish end
			if sand(0, -1) and sand(-1, 0) and sand(-1, -1) then hgt[1][1] = hgt[1][1] - dish end
			if sand(0, -1) and sand(1, 0) and sand(1, -1) then hgt[1][3] = hgt[1][3] - dish end
			if sand(0, 1) and sand(-1, 0) and sand(-1, 1) then hgt[3][1] = hgt[3][1] - dish end
			if sand(0, 1) and sand(1, 0) and sand(1, 1) then hgt[3][3] = hgt[3][3] - dish end
		end
		return hgt
	end

	function Terrain:tileCentre(tx, ty)
		local S = T.TILE_SIZE
		return tx * S - self.w * S * 0.5 + S * 0.5, ty * S - self.h * S * 0.5 + S * 0.5
	end

	-- ground height at a world position (bilinear between corners; ignores sand dishing)
	function Terrain:heightAt(wx, wz)
		local S = T.TILE_SIZE
		local fx = max(0, min(self.w - 0.001, (wx + self.w * S * 0.5) / S))
		local fz = max(0, min(self.h - 0.001, (wz + self.h * S * 0.5) / S))
		local x, y = floor(fx), floor(fz)
		local u, v = fx - x, fz - y
		local a, b, c, d = self:tileLevels(x, y)
		local top, bottom = a * (1 - u) + b * u, c * (1 - u) + d * u
		return (top * (1 - v) + bottom * v) * T.HEIGHT_STEP
	end

	------------------------------------------------------------------------------------------------ blending

	-- terrain "class" for borders: tiles of the same class blend without a border. 0..22 from the rule table (data/terrain).
	local classOf
	function T.typeClass(ty, desert)
		if not classOf then
			classOf = {}
			for _, row in ipairs(Game.Data.terrain.terrain) do
				classOf[row.tile] = { class = row.class, desertGroup = row.hazard }
			end
		end
		if ty >= 0 and ty <= 22 then
			local r = classOf[ty]
			if not r then return ty end
			if desert and ty == T.DEEP_ROUGH then return 5 end
			if desert and r.desertGroup > 0 and ty ~= T.SAND then return 4 end
			return r.class
		elseif ty >= 23 and ty <= 25 then
			return T.typeClass(T.WATER_SHALLOW, desert)
		elseif ty == 26 then
			return 1
		elseif (ty >= 27 and ty <= 30) or ty == 34 or ty == 35 then
			return 7
		end
		return 100 + ty
	end

	-- relation of a tile to a neighbour: 0 same, 1 different class, 2 same class but different type (0 off the map).
	-- Water depth (the variation byte 0/1/2) takes part.
	function T.tileRelation(t, x, y, nx, ny)
		if not t:inside(nx, ny) then return 0 end
		local me, nb = t:index(x, y), t:index(nx, ny)
		local mt, nt = t.ty[me], t.ty[nb]
		if t.waterOne and mt == T.WATER_SHALLOW then
			return nt == T.WATER_SHALLOW and 0 or 1
		end
		if mt == T.WATER_SHALLOW then
			local level = t.variation[me]
			local nl = nt == T.WATER_SHALLOW and t.variation[nb] or 0
			if level == 0 and nt ~= T.WATER_SHALLOW then return 1 end
			if nl == level then return 0 end
			return (level == 0 or (level == 1 and nl == 2)) and 2 or 1
		end
		if T.typeClass(mt, t.desert) ~= T.typeClass(nt, t.desert) then return 1 end
		return mt ~= nt and 2 or 0
	end

	-- texture variation 0..8 from the relations (a, b, c) of a triangle's two edge neighbours and its diagonal one
	-- (the original's lookup, Tile::m1028 + m1262)
	local RAW = {
		[0] = 0, 0, 0, 1, 2, 3, 4, 3, 9, 9, 0, 9, 0, 9, 2, 9, 4, 9, 9, 9, 0, 0, 9, 9, 2, 3, 9, 9, 9, 9, 5, 9, 9, 9, 2, 9, 9, 9, 9,
		9, 6, 6, 6, 1, 9, 9, 9, 9, 9, 9, 7, 9, 7, 9, 9, 9, 9, 9, 9, 9, 8, 6, 9, 9, 9, 9, 9, 9, 9, 9, 7,
	}
	local MAP = { [0] = 0, 2, 4, 3, 1, 6, 8, 7, 5, 0 }
	local function r(v, one, two) return v == 1 and one or (v == 2 and two or 0) end
	function T.blendVariation(a, b, c)
		return MAP[RAW[r(a, 4, 40) + r(b, 1, 10) + r(c, 2, 20)]]
	end

	-- the texture type the original draws for a tile type (Tile::m116d)
	function T.textureTypeFor(tileType, vbyte, param, phase)
		if tileType == 1 then
			return (vbyte >= 128) and T.TRICKY_GREEN or param
		elseif tileType == 6 or tileType == 21 then
			return T.ROUGH
		elseif tileType == 7 then
			return T.SAND_BUNKER1 + ((vbyte % 4) - phase) % 4
		elseif tileType >= 13 and tileType <= 16 then
			return T.WOODS
		elseif tileType == 17 then
			if vbyte == 1 then return T.WATER_MIDDLE elseif vbyte == 2 then return T.WATER_DEEP end
			return param
		elseif tileType == 22 then
			return (vbyte >= 0x40 and vbyte < 0x48) and T.ROUGH or param
		end
		return param
	end

	-- texture coordinates (top-down) turned a quarter per view phase, as Terrain.dll's table has them
	function T.viewUV(u, v, phase)
		phase = phase % 4
		if phase == 1 then return v, 1 - u
		elseif phase == 2 then return 1 - u, 1 - v
		elseif phase == 3 then return 1 - v, u end
		return u, v
	end

	-- the 8 triangles of a tile as {row, column} points of its 3 x 3 patch (0-based), in Terrain.dll's record order:
	-- a fan round the centre, each triangle holding half of one tile edge
	T.TILE_TRIS = {
		{ { 0, 0 }, { 1, 0 }, { 1, 1 } },
		{ { 0, 0 }, { 1, 1 }, { 0, 1 } },
		{ { 0, 1 }, { 1, 1 }, { 0, 2 } },
		{ { 1, 1 }, { 1, 2 }, { 0, 2 } },
		{ { 1, 0 }, { 2, 0 }, { 1, 1 } },
		{ { 2, 0 }, { 2, 1 }, { 1, 1 } },
		{ { 1, 1 }, { 2, 1 }, { 2, 2 } },
		{ { 1, 1 }, { 2, 2 }, { 1, 2 } },
	}
	local TILE_TRIS = T.TILE_TRIS
	-- the edge (0 north, 1 east, 2 south, 3 west) each triangle record holds half of
	local EDGE_OF_REC = { 3, 0, 0, 1, 3, 2, 2, 1 }
	local DX4, DY4 = { [0] = 0, 1, 0, -1 }, { [0] = -1, 0, 1, 0 }

	-- desert water: which edges meet a tee, green, fairway or sand (those triangles take WaterShallowDesert, the grass shore)
	local function desertGrassEdges(t, tx, ty)
		local out = { [0] = false, false, false, false }
		if not t.desert or t.waterOne or t.ty[t:index(tx, ty)] ~= T.WATER_SHALLOW then return out end
		for d = 0, 3 do
			local nx, ny = tx + DX4[d], ty + DY4[d]
			if t:inside(nx, ny) then
				local n = t.ty[t:index(nx, ny)]
				out[d] = n == 0 or n == 1 or n == 2 or n == 3 or n == 7 or n == 8 or n == 9
			end
		end
		return out
	end

	local function waterOneType(t, tileType)
		if t.waterOne and tileType == T.WATER_SHALLOW then
			return t.desert and T.WATER_SHALLOW_DESERT or T.WATER_SHALLOW
		end
	end

	------------------------------------------------------------------------------------------------ normals

	local function normalize(x, y, z)
		local l = sqrt(x * x + y * y + z * z)
		if l > 0 then return x / l, y / l, z / l end
		return 0, 1, 0
	end

	-- unit face normals of a tile's 8 triangles, facing up; cached per tile (cleared by Terrain:dirty())
	function Terrain:faceNormals(tx, ty)
		self._faces = self._faces or {}
		local i = self:index(tx, ty)
		local cached = self._faces[i]
		if cached then return cached end
		local hgt = self:patchHeights(tx, ty)
		local half = T.TILE_SIZE * 0.5
		local out = {}
		for r = 1, 8 do
			local p = TILE_TRIS[r]
			local ax, ay, az = p[1][2] * half, hgt[p[1][1] + 1][p[1][2] + 1], p[1][1] * half
			local bx, by, bz = p[2][2] * half, hgt[p[2][1] + 1][p[2][2] + 1], p[2][1] * half
			local cx, cy, cz = p[3][2] * half, hgt[p[3][1] + 1][p[3][2] + 1], p[3][1] * half
			local ux, uy, uz = bx - ax, by - ay, bz - az
			local vx, vy, vz = cx - ax, cy - ay, cz - az
			local nx, ny, nz = normalize(uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
			if ny < 0 then nx, ny, nz = -nx, -ny, -nz end
			out[r] = { nx, ny, nz }
		end
		self._faces[i] = out
		return out
	end

	function Terrain:dirty()
		self._faces = nil
	end

	-- normals of the 3 x 3 patch: per point the normalised sum of the unit face normals of every triangle on the map that
	-- meets it (this tile's and the neighbours'), as Terrain.dll's calcNormals does, so slopes shade smoothly across tiles
	function Terrain:vertexNormals(tx, ty)
		local sum = {}
		for j = 1, 3 do sum[j] = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } } end
		for dy = -1, 1 do
			for dx = -1, 1 do
				local nx, ny = tx + dx, ty + dy
				if self:inside(nx, ny) then
					local faces = self:faceNormals(nx, ny)
					for r = 1, 8 do
						local n = faces[r]
						for _, p in ipairs(TILE_TRIS[r]) do
							local pj, pk = p[1] + 2 * dy, p[2] + 2 * dx
							if pj >= 0 and pj <= 2 and pk >= 0 and pk <= 2 then
								local s = sum[pj + 1][pk + 1]
								s[1], s[2], s[3] = s[1] + n[1], s[2] + n[2], s[3] + n[3]
							end
						end
					end
				end
			end
		end
		for j = 1, 3 do
			for k = 1, 3 do
				local s = sum[j][k]
				s[1], s[2], s[3] = normalize(s[1], s[2], s[3])
			end
		end
		return sum
	end

	------------------------------------------------------------------------------------------------ triangles

	-- The 8 triangles of tile (tx, ty), appended to `out` as
	--   { texType, set, variation, x1, y1, z1, u1, v1, nx1, ny1, nz1, ... (3 vertices) }
	-- world coordinates, texture coordinates 0..1 within the texture (top-down).
	function T.buildTileTriangles(t, tx, ty, out)
		local me = t:index(tx, ty)
		local ttype, vbyte, set = t.ty[me], t.variation[me], t.set[me]
		local hgt = t:patchHeights(tx, ty)
		local S = T.TILE_SIZE
		local ox = tx * S - t.w * S * 0.5
		local oz = ty * S - t.h * S * 0.5
		local phase = ttype == T.TEE and (t.sandPhase or 0) or 0

		local var = {}
		if ttype == T.TEE or ttype == T.POT_SAND_BUNKER then
			for i = 1, 8 do var[i] = ttype == T.TEE and 0 or 3 end
		else
			local function rel(dx, dy) return T.tileRelation(t, tx, ty, tx + dx, ty + dy) end
			local n, s, w, e = rel(0, -1), rel(0, 1), rel(-1, 0), rel(1, 0)
			local nw, ne, sw, se = rel(-1, -1), rel(1, -1), rel(-1, 1), rel(1, 1)
			local abc = { { n, e, ne }, { e, n, ne }, { e, s, se }, { s, e, se }, { s, w, sw }, { w, s, sw }, { w, n, nw }, { n, w, nw } }
			local REC_OF = { 3, 4, 8, 7, 6, 5, 1, 2 } -- original triangle index -> record (1-based)
			local texType = waterOneType(t, ttype) or T.textureTypeFor(ttype, vbyte, ttype, t.sandPhase or 0)
			for i = 1, 8 do
				local v = T.blendVariation(abc[i][1], abc[i][2], abc[i][3])
				if (texType == T.ROUGH or ttype == T.SAND or texType == T.FAIRWAY) and v > 4 then v = 0 end
				var[REC_OF[i]] = v
			end
		end

		local texType
		if ttype == T.TEE or ttype == T.POT_SAND_BUNKER then
			texType = ttype
		else
			texType = waterOneType(t, ttype) or T.textureTypeFor(ttype, vbyte, ttype, t.sandPhase or 0)
		end
		local useSet = ttype == T.TEE and vbyte or set
		local grassEdge = desertGrassEdges(t, tx, ty)
		local normals = t:vertexNormals(tx, ty)

		for r = 1, 8 do
			local tt = texType
			if grassEdge[EDGE_OF_REC[r]] then tt = T.textureTypeFor(ttype, vbyte, T.WATER_SHALLOW_DESERT, 0) end
			local tri = { tt, useSet, var[r] }
			for _, p in ipairs(TILE_TRIS[r]) do
				local j, k = p[1], p[2]
				local u, v = T.viewUV(k * 0.5, j * 0.5, phase)
				local n = normals[j + 1][k + 1]
				local o = #tri
				tri[o + 1], tri[o + 2], tri[o + 3] = ox + k * S * 0.5, hgt[j + 1][k + 1], oz + j * S * 0.5
				tri[o + 4], tri[o + 5] = u, v
				tri[o + 6], tri[o + 7], tri[o + 8] = n[1], n[2], n[3]
			end
			out[#out + 1] = tri
		end
	end

	------------------------------------------------------------------------------------------------ demo course

	-- OpenSGolf's made-up demonstration course (tee, winding fairway, green, bunkers, pond, woods, hills), same seed same course
	function T.demoCourse(w, h, seed)
		local t = T.new(w, h, T.ROUGH)
		t.clubhouseX, t.clubhouseY = -1, -1
		local rng = Rng.new(seed ~= 0 and seed or 1)
		local wf, hf = w, h

		local function disc(cx, cy, rx, ry, ty, onlyRough)
			for y = 0, h - 1 do
				for x = 0, w - 1 do
					local dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
					local i = y * w + x + 1
					if dx * dx + dy * dy <= 1 and (not onlyRough or t.ty[i] == T.ROUGH or t.ty[i] == T.DEEP_ROUGH) then
						t.ty[i] = ty
					end
				end
			end
		end

		-- outer deep rough, then scattered woods, brush and rock
		for y = 0, h - 1 do
			for x = 0, w - 1 do
				if min(x, y, w - 1 - x, h - 1 - y) < 2 then t.ty[y * w + x + 1] = T.DEEP_ROUGH end
			end
		end
		for _ = 1, floor(w * h / 14) do
			local cx, cy = rng:range(w), rng:range(h)
			local radius = 1 + rng:unit() * 2.2
			local ty
			if rng:range(3) == 0 then ty = T.BRUSH
			elseif rng:range(3) == 0 then ty = T.ROCK
			else ty = T.WOODS end
			disc(cx, cy, radius, radius, ty, true)
		end

		-- fairway along a curve from the tee (bottom-left) to the green (top-right)
		local sx, sy, ex, ey = 5, h - 6, w - 7, 6
		local PI = 3.14159
		local function curve(s) return sx + (ex - sx) * s + sin(s * PI * 1.4) * hf * 0.14, sy + (ey - sy) * s end
		for step = 0, 200 do
			local cx, cy = curve(step / 200)
			disc(cx, cy, 3.4, 3.4, T.ROUGH, false)
		end
		t.path = {}
		for step = 0, 200 do
			local cx, cy = curve(step / 200)
			disc(cx, cy, 2.3, 2.3, T.FAIRWAY, false)
			if step % 5 == 0 then
				t.path[#t.path + 1] = cx * T.TILE_SIZE - wf * T.TILE_SIZE * 0.5
				t.path[#t.path + 1] = cy * T.TILE_SIZE - hf * T.TILE_SIZE * 0.5
			end
			if step % 4 == 0 then disc(cx, cy, 1, 1, T.FIRM_FAIRWAY, false) end
		end
		local gcx, gcy = ex + sin(PI * 1.4) * hf * 0.14, ey
		disc(gcx, gcy, 4.6, 4.6, T.FIRM_FAIRWAY, false)
		disc(gcx, gcy, 3.2, 3.2, T.PUTTING_GREEN, false)
		disc(sx, sy, 2.2, 1.6, T.TEE, false)

		-- clubhouse lot beside the tee: a 5 x 5 block of Building tiles
		t.clubhouseX, t.clubhouseY = floor(sx) + 6, floor(sy) - 3
		for y = t.clubhouseY - 2, t.clubhouseY + 2 do
			for x = t.clubhouseX - 2, t.clubhouseX + 2 do
				if t:inside(x, y) then t.ty[t:index(x, y)] = T.BUILDING end
			end
		end

		-- bunkers beside the green and mid fairway, a pond to one side
		disc(gcx - 4.5, gcy + 2.5, 1.9, 1.3, T.POT_SAND_BUNKER, false)
		disc(gcx + 3.2, gcy + 3.6, 1.6, 1.6, T.POT_SAND_BUNKER, false)
		disc(wf * 0.5 + 3, hf * 0.5 - 1, 1.7, 1.2, T.POT_SAND_BUNKER, false)
		disc(wf * 0.5 - 2, hf * 0.5 + 6, 2.3, 1.5, T.SAND, true)
		local pcx, pcy = wf * 0.30, hf * 0.38
		disc(pcx, pcy, 5.5, 4.2, T.WATER_SHALLOW, false)
		disc(pcx, pcy, 4.2, 3.0, T.WATER_MIDDLE, false)
		disc(pcx, pcy, 2.4, 1.6, T.WATER_DEEP, false)

		for i = 1, w * h do
			-- sets A..E are alternative looks of the same ground, chosen at random per tile
			t.set[i] = rng:range(5)
			t.variation[i] = 0
			if t.ty[i] == T.TEE then t.variation[i] = rng:range(5) end -- tees use this byte as their set
			-- water is one type; its depth is the variation byte (1 middle, 2 deep)
			if t.ty[i] == T.WATER_MIDDLE then
				t.ty[i], t.variation[i] = T.WATER_SHALLOW, 1
			elseif t.ty[i] == T.WATER_DEEP then
				t.ty[i], t.variation[i] = T.WATER_SHALLOW, 2
			end
		end

		-- gentle hills, flattened under water, greens, tees and the clubhouse
		local p1, p2 = rng:unit() * 6.28, rng:unit() * 6.28
		for y = 0, h do
			for x = 0, w do
				local v = 3.2 * sin(x * 0.17 + p1) + 2.6 * cos(y * 0.13 + p2) + 2.0 * sin((x + y) * 0.09)
				t.corner[y * (w + 1) + x + 1] = max(0, min(12, floor(v + 5 + 0.5)))
			end
		end
		for y = 0, h - 1 do
			for x = 0, w - 1 do
				local ty = t.ty[y * w + x + 1]
				local level
				if ty == T.PUTTING_GREEN or ty == T.TEE then level = 6
				elseif ty == T.BUILDING then level = 5
				elseif ty == T.WATER_SHALLOW or ty == T.WATER_MIDDLE or ty == T.WATER_DEEP then level = 1 end
				if level then
					for dy = 0, 1 do
						for dx = 0, 1 do t.corner[(y + dy) * (w + 1) + (x + dx) + 1] = level end
					end
				end
			end
		end
		return t
	end

	return T
end
