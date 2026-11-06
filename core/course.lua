-- A game in progress: the generated land, the terrain drawn from it, the money, and the holes. Every change to the course
-- goes through here (painting, elevation, buildings, opening holes) with OpenSGolf's rules and costs, so the server can own
-- this state and clients only send commands.
--
-- Ported from OpenSGolf v0.6.10: App::paint_tiles (simgolf/src/app.rs), Terrain::paint and Terrain::edit_elevation
-- (sg-core/src/terrain.rs), the building tool (app.rs), Club::paint_hole_tile and Club::open_hole (sg-core/src/holetool.rs),
-- Economy::affordable and rank (sg-core/src/economy.rs).
--
-- Not yet: the layout pass that measures a hole by playing it (holes are measured straight from tee to pin, as OpenSGolf
-- does for a hole the pass has not measured), undo, paths, benches, flower beds, landmarks and home sites, tournaments.
--
-- Tiles are (a, b) = (x, y) on the 50 x 50 map; land and course arrays are 0-based (a * 50 + b), the terrain's 1-based.
-- Money is in the game's money (the exe's units are 100 money).

return function(Game)
	local T = Game.require("terrain")
	local L = Game.require("land")
	local bit = bit or require("bit")
	local band, bor, bnot, arshift = bit.band, bit.bor, bit.bnot, bit.arshift
	local max, min, floor, sqrt = math.max, math.min, math.floor, math.sqrt

	local C = {}
	C.__index = C

	local N = 50
	local UNIT = 100
	local T_TEE, T_GREEN, T_SAND, T_WATER = 0, 1, 7, 17
	local F_OBSTACLE, F_FOOTPRINT, F_PATH = 0x8000, 0x400, 0x20
	-- course tile flags (sg-core course.rs f::): the hole number, the cup
	local CF_LOW, CF_CUP = 0x1f, 0x80
	local EXE_SEA, EXE_LOW, EXE_HIGH, EXE_LOW_CAP = 3, 3, 13, 10
	local AREA_KERNEL = { { 6, 4, 3, 4, 6 }, { 4, 2, 1, 2, 4 }, { 3, 1, 0, 1, 3 }, { 4, 2, 1, 2, 3 }, { 6, 4, 3, 4, 6 } }

	C.K_WASHER, C.K_LANDMARK, C.K_HOME_SITE, C.K_PUTTING_GREEN, C.K_SNACK_BAR = 3, 4, 5, 6, 7
	C.K_DRIVING_RANGE, C.K_CLUBHOUSE = 10, 15

	-- the Build Course panel's terrain buttons: tile ids in the panel's order (panels_ui.rs TERRAIN_SLOTS, then the trees)
	C.PAINT_TILES = { 0, 1, 7, 4, 9, 10, 17, 2, 3, 5, 8, 11, 12, 13, 14, 15 }
	-- the buildings the Add Buildings panel offers that the port can place so far (app.rs OFFERED_KINDS, minus the tile items,
	-- landmarks and home sites)
	C.BUILD_KINDS = { 3, 6, 7, 8, 9, 10, 11, 12, 13, 14 }

	-- tile names per exe theme (panels_ui.rs tile_key)
	local TILE_NAMES = {
		[0] = "Tees", "Green", "Fairway", "Firm fairway", "Rough", "Deep rough", "Mound", "Sand trap", "Waste bunker",
		"Pot bunker", "Stream", "Brush", "Rocks", "Tree", "Pine tree", "Palm tree", "Elm tree", "Water",
	}
	local THEME_TILE_NAMES = {
		[1] = { [4] = "Desert", [5] = "Rough", [10] = "Brush", [11] = "Ravine", [13] = "Joshua tree", [14] = "Cactus" },
		[2] = { [13] = "Tropical bush", [14] = "Tropical tree" },
		[3] = { [10] = "Burn", [11] = "Gorse", [13] = "Maple tree", [14] = "Pine", [15] = "Scots pine" },
	}
	function C.tileName(id, theme)
		local t = THEME_TILE_NAMES[theme]
		return (t and t[id]) or TILE_NAMES[id] or "?"
	end

	------------------------------------------------------------------------------------------------ rule tables

	local rows
	local function row(ty)
		if not rows then
			rows = {}
			for _, r in ipairs(Game.Data.terrain.terrain) do rows[r.tile] = r end
		end
		return rows[ty] or rows[4]
	end
	C.row = row

	-- what laying a type costs and what clearing it costs, per tile in units (data/terrain: money / 100)
	function C.paintUnits(ty) local r = rows and rows[ty] or row(ty) return r and floor(r.cost / UNIT) or 0 end
	function C.clearUnits(ty) local r = rows and rows[ty] or row(ty) return r and floor(r.clear_cost / UNIT) or 0 end

	local function economy() return Game.Data.economy.economy end

	-- course rank 0..3 (Municipal, Daily Fee, Country Club, Championship) by open holes
	function C.rank(holes)
		local k = 0
		for _, n in ipairs(economy().rank_holes) do if holes >= n then k = k + 1 end end
		return k
	end

	-- Rust's integer division (towards zero)
	local function idiv(a, b)
		local q = a / b
		return q < 0 and math.ceil(q) or floor(q)
	end

	-- the exe's angle of a vector (staff.rs angle): 0 up, a full turn is 2^32
	local function angle(x, y)
		local ny = -y
		if x == 0 then return ny < 1 and 0x80000000 or 0 end
		if ny == 0 then return x < 1 and 0xc0000000 or 0x40000000 end
		local ax, ay = math.abs(x), math.abs(ny)
		local swap = ay < ax
		local hi, lo = ay, ax
		if swap then hi, lo = ax, ay end
		local r = idiv(lo * 0x4000, hi)
		local k = 0x1333 - r
		local a = bit.rshift(bit.tobit((0x2800 - bit.rshift(math.abs(k) * 0xb00, 0xe)) * r), 0xe)
		local v
		if x < 1 then
			if ny < 1 then
				v = (not swap) and (a + 0x8000) or (0xc000 - a)
			else
				v = swap and (a + 0xc000) or -a
			end
		elseif ny < 1 then
			v = (not swap) and (0x8000 - a) or (a + 0x4000)
		else
			v = swap and (0x4000 - a) or a
		end
		return bit.lshift(v, 16) % 4294967296
	end
	C.angle = angle

	-- heading 0..7 nearest an angle (geom.rs dir8)
	local function dir8(a)
		return band(arshift(arshift(bit.tobit(a), 28) + 1, 1), 7)
	end
	C.dir8 = dir8

	------------------------------------------------------------------------------------------------ a new game

	-- opts: clock (the deal's seed), slot (0..15), difficulty (0..2), sandbox, fixes ("Fix original bugs", default on)
	function C.new(opts)
		opts = opts or {}
		if opts.fixes == nil then opts.fixes = true end
		local land, offer, rng = L.newGame(opts)
		local c = setmetatable({}, C)
		c.land, c.offer, c.rng = land, offer, rng
		c.noise = land.noise
		c.sandbox = opts.sandbox and true or false
		c.difficulty = opts.difficulty or 1
		c.fixes = opts.fixes
		c.theme = land:record().theme
		c.terrain = land:toTerrain()
		local price = economy().offer_prices[(opts.slot or 0) + 1]
		c.cash = c.sandbox and economy().sandbox_funds or (economy().start_funds - price)
		c.holes = {}
		for h = 0, 19 do c.holes[h] = C.newHole() end
		c.holes[19].back = { land.clubhouse[1], land.clubhouse[2] }
		c.nextHole = 1
		c.unlocked = c.sandbox and 17 or 6
		c.flags = {}
		for i = 0, N * N - 1 do c.flags[i] = 0 end
		c.events = {}
		c.version = 0       -- bumped on every change to the ground
		c.objectsVersion = 0 -- bumped when objects, trees or hole markers change
		return c
	end

	function C.newHole()
		return { back = { 0, 0 }, fwd = { 0, 0 }, pin = { 0, 0 }, par = 0, length = 0, flags = 0, teeFacing = 0, fwdFacing = 0 }
	end

	local function closeHole(h) h.par = 0 end

	function C:emit(e) self.events[#self.events + 1] = e end
	function C:toast(text) self:emit({ type = "toast", text = text }) end
	function C:message(text) self:emit({ type = "message", text = text }) end
	function C:sound(name) self:emit({ type = "sound", name = name }) end

	-- takes the events since the last call (toasts, messages, sounds) for the client to show
	function C:takeEvents()
		local e = self.events
		self.events = {}
		return e
	end

	function C:openHoles()
		local n = 0
		for h = 1, 18 do if self.holes[h].par ~= 0 then n = n + 1 end end
		return n
	end

	function C:affordable(amount)
		return amount < UNIT or amount <= self.cash or self.sandbox or self:openHoles() < 3
	end

	function C:spend(amount)
		self.cash = self.cash - amount
	end

	local function money(v)
		local s = tostring(floor(math.abs(v)))
		s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
		return (v < 0 and "-$" or "$") .. s
	end
	C.money = money

	------------------------------------------------------------------------------------------------ sync between land and terrain

	local function inside(a, b) return a >= 0 and b >= 0 and a < N and b < N end
	local function idx(a, b) return a * N + b end
	C.inside, C.idx = inside, idx

	-- the land's view of a painted tile (Land::sync_from_terrain for one tile)
	function C:syncTile(a, b)
		local land, t = self.land, self.terrain
		local i = idx(a, b)
		local o = t:index(a, b)
		if band(land.flags[i], F_FOOTPRINT) == 0 then land:setTy(i, t.ty[o]) end
	end

	-- the land's corner heights from the terrain's (Land::sync_from_terrain's second half)
	function C:syncHeights(a0, b0, a1, b1)
		local land, t = self.land, self.terrain
		for a = max(0, a0), min(N, a1) do
			for b = max(0, b0), min(N - 1, b1) do
				local v = t.corner[(b + 1) * (t.w + 1) + a + 1] + EXE_SEA
				land:setH(a * (N + 1) + b, max(0, min(255, v)))
			end
		end
	end

	-- Terrain::paint: type, byte, and a stable random look
	local function terrainPaint(t, x, y, ty, vbyte)
		local o = t:index(x, y)
		t.ty[o] = ty
		t.variation[o] = vbyte
		local h = bit.bxor(bit.tobit(x * 73856093 % 4294967296), bit.tobit(y * 19349663 % 4294967296),
			bit.tobit(ty * 83492791 % 4294967296))
		t.set[o] = (bit.rshift(h, 7) % 4294967296) % 5
	end

	function C:changed(objects)
		self.terrain:dirty()
		self.version = self.version + 1
		if objects then self.objectsVersion = self.objectsVersion + 1 end
	end

	------------------------------------------------------------------------------------------------ painting

	-- the object whose footprint covers (a, b) (Land::object_on), 0-based index
	function C:objectOn(a, b)
		local land = self.land
		if not inside(a, b) or band(land.flags[idx(a, b)], F_FOOTPRINT) == 0 then return nil end
		for i, o in ipairs(land.objects) do
			local s = land:footprintSize(o)
			if o.kind >= 0 and a >= o.a and a < o.a + s and b >= o.b and b < o.b + s then return i - 1 end
		end
		return nil
	end

	-- a green next to (x, y) that a green painted there joins (App::green_joins); with the fixes a putting green's lot does not
	-- count (OpenSGolf issue #128)
	function C:greenJoins(x, y)
		local t = self.terrain
		if not t:inside(x, y) or t.ty[t:index(x, y)] ~= T_GREEN then return false end
		return not (self.fixes and t.lot and t.lot[t:index(x, y)] == C.K_PUTTING_GREEN)
	end

	-- Club::paint_hole_tile: the hole bookkeeping of painting (a, b) from `old` to `new`; returns whether the paint goes ahead
	function C:paintHoleTile(a, b, old, new, greenNext)
		if not inside(a, b) then return false end
		local i = idx(a, b)
		local h = self.nextHole
		local holes, flags = self.holes, self.flags
		if h >= 19 and (new == T_TEE or (new == T_GREEN and not greenNext)) then return false end
		local oldFlags = flags[i]
		local cup = old == T_GREEN and band(oldFlags, CF_CUP) ~= 0
		local hu = max(0, min(19, h))
		local hr = holes[hu]
		local go = true
		if new == T_TEE then
			if hr.back[1] == 0 then
				if old == T_TEE then
					go = false
				elseif cup then
					local k = band(oldFlags, CF_LOW)
					closeHole(holes[k])
					holes[k].pin[1] = 0
				end
				hr.back = { a, b }
				flags[i] = h
				hr.fwd = { a, b }
			else
				go = false
				self:message(("Hole %d already has its tee; open it before starting the next hole."):format(h))
			end
		elseif new == T_GREEN then
			if hr.pin[1] == 0 and a ~= 0 and (not greenNext or hr.back[1] ~= 0) then
				if old == T_TEE then
					local k = band(flags[i], CF_LOW)
					closeHole(holes[k])
					holes[k].back[1] = 0
				elseif cup then
					return false
				end
				if h < 19 then
					hr.pin = { a, b }
					flags[i] = bor(h, CF_CUP)
				end
			elseif old ~= T_GREEN then
				flags[i] = band(flags[i], bnot(CF_LOW))
			end
		end
		if not go then return false end
		if new == old then return true end
		-- painting over a hole's tee or cup green takes the hole out of play until it is rebuilt
		local k = band(oldFlags, CF_LOW)
		if k ~= 0 then
			local kr = holes[k]
			if old == T_TEE then
				self.nextHole = min(self.nextHole, k)
				if not (a == kr.fwd[1] and b == kr.fwd[2]) then
					kr.back[1] = 0
				else
					kr.fwd[1] = 0
					kr.back[1] = 0
				end
				closeHole(kr)
				if not (new == T_GREEN and band(flags[i], CF_CUP) ~= 0) then flags[i] = band(flags[i], bnot(CF_LOW)) end
			elseif old == T_GREEN then
				self.nextHole = min(self.nextHole, k)
				closeHole(kr)
				kr.pin[1] = 0
				if new ~= T_TEE then flags[i] = band(flags[i], bnot(CF_LOW)) end
			end
		end
		return true
	end

	-- what painting these tiles with `ty` would cost, and how many tiles would change (for the cursor's preview)
	function C:paintCost(tiles, ty)
		local t, land = self.terrain, self.land
		local cost, n = 0, 0
		for _, p in ipairs(tiles) do
			local x, y = p[1], p[2]
			if t:inside(x, y) and land:inPlay(x, y) and band(land.flags[idx(x, y)], F_OBSTACLE) == 0 then
				local old = t.ty[t:index(x, y)]
				if old ~= ty then
					cost = cost + (C.clearUnits(old) + C.paintUnits(ty)) * UNIT
					n = n + 1
				end
			end
		end
		return cost, n
	end

	-- App::paint_tiles. `want` is the brush's byte: a green's (0, or 0xff tricky), a sand trap's shape (12..23), else 0.
	-- Returns the money spent.
	function C:paint(tiles, ty, want)
		want = want or 0
		local t, land = self.terrain, self.land
		local refused, broke, scenery, any = false, false, false, false
		local spentTotal = 0
		for _, p in ipairs(tiles) do
			local x, y = p[1], p[2]
			if t:inside(x, y) then
				local o = t:index(x, y)
				local old, new = t.ty[o], ty
				local li = idx(x, y)
				local clear = C.clearUnits(old)
				local cost = clear + C.paintUnits(ty)
				local byteOnly = new == T_GREEN or new == T_SAND
				repeat
					if not land:inPlay(x, y) or band(land.flags[li], F_OBSTACLE) ~= 0 then
						refused = true
						break
					end
					-- a flower bed or garden border on the tile goes, even under the same type
					if band(land.flags[li], 0x1000) ~= 0 then
						land.flags[li] = band(land.flags[li], bnot(0x1000))
						scenery = true
					end
					if old == new and (not byteOnly or want == t.variation[o]) then break end
					if not self:affordable(cost * UNIT) then
						broke = true
						break
					end
					local on = self:objectOn(x, y)
					if on then
						local obj = land.objects[on + 1]
						local k = L.kinds()[obj.kind]
						local edge = k and k.size or 1
						if (obj.kind == C.K_LANDMARK and obj.sub <= 16) or obj.kind == C.K_CLUBHOUSE or edge > 1 then
							refused = true
							break
						end
						scenery = true
						local size = land:footprintSize(obj)
						land:removeObject(on)
						land:writeArea(t, obj.a, obj.b, obj.a + size - 1, obj.b + size - 1)
					end
					if old <= 1 or new <= 1 then
						local gn = self:greenJoins(x + 1, y) or self:greenJoins(x - 1, y) or self:greenJoins(x, y + 1)
							or self:greenJoins(x, y - 1)
						if not self:paintHoleTile(x, y, old, new, gn) then
							scenery = true
							break
						end
						scenery = true
					end
					local keep = new == T_SAND and band(land.flags[li], 0x200) ~= 0
					if old == new and (new == T_GREEN or new == T_SAND) then
						if not keep then
							t.variation[o] = want
							land.var[li] = want
							any = true
						end
						break
					end
					local vb = want
					if ty == T_TEE then vb = 0 elseif keep then vb = land.var[li] end
					self:spend(cost * UNIT)
					spentTotal = spentTotal + cost * UNIT
					terrainPaint(t, x, y, ty, vb)
					land.var[li] = vb
					self:syncTile(x, y)
					any = true
					if row(old).class == 13 or row(new).class == 13 then scenery = true end
				until true
			end
		end
		if broke then
			self:sound("refused")
			self:toast("You don't have enough money.")
		elseif refused then
			self:sound("refused")
		end
		if any or scenery then self:changed(scenery or any) end
		return spentTotal
	end

	------------------------------------------------------------------------------------------------ elevation

	-- Terrain::edit_elevation on corner (cx, cy): tool 0 the corner, 1 the 2 x 2 block (cx..cx+1, cy-1..cy), 2 the area.
	-- No money is charged (none is in the exe's edit routines).
	function C:elevate(tool, cx, cy, raise)
		local t = self.terrain
		local w, h = t.w, t.h
		local hilly = self.land:record().relief == 2
		local function ok(x, y) return x >= 0 and y >= 0 and x <= w and y <= h end
		local function at(x, y) return t.corner[y * (w + 1) + x + 1] + EXE_SEA end
		local function set(x, y, v) t.corner[y * (w + 1) + x + 1] = v - EXE_SEA end
		if tool == 1 then
			local block = {}
			for _, p in ipairs({ { cx, cy - 1 }, { cx + 1, cy - 1 }, { cx, cy }, { cx + 1, cy } }) do
				if ok(p[1], p[2]) then block[#block + 1] = p end
			end
			if raise then
				local m = 99
				for _, p in ipairs(block) do m = min(m, at(p[1], p[2])) end
				for _, p in ipairs(block) do
					if at(p[1], p[2]) == m and m < EXE_HIGH then set(p[1], p[2], m + 1) end
				end
			else
				local m = 0
				for _, p in ipairs(block) do m = max(m, at(p[1], p[2])) end
				for _, p in ipairs(block) do
					if at(p[1], p[2]) == m and m > EXE_LOW then set(p[1], p[2], m - 1) end
				end
			end
		else
			if not ok(cx, cy) then return end
			local v = at(cx, cy)
			local top = (raise or hilly) and EXE_HIGH or EXE_LOW_CAP
			local c = max(EXE_LOW, min(top, v + (raise and 1 or -1)))
			set(cx, cy, c)
			if tool == 2 then
				for i = 1, 5 do
					for j = 1, 5 do
						local k = AREA_KERNEL[i][j]
						local x, y = cx + i - 3, cy + j - 3
						if ok(x, y) then
							local hh = at(x, y)
							if raise and hh < c - k then set(x, y, hh + 1)
							elseif not raise and hh > c + k then set(x, y, hh - 1) end
						end
					end
				end
			end
		end
		self:syncHeights(cx - 3, cy - 4, cx + 3, cy + 3)
		self:sound(raise and "raise" or "lower")
		self:changed(true)
	end

	------------------------------------------------------------------------------------------------ buildings

	function C:unlockedKinds()
		if self.sandbox then return 17 end
		return max(self.unlocked, C.unlockedFor(self:openHoles()))
	end

	-- land.rs unlocked_kinds: kinds 0..5 from the start, then one more per completed hole (not 6, 10 or 18's rank holes)
	function C.unlockedFor(holes)
		local u = 6
		for n = 1, holes do
			if n ~= 6 and n ~= 10 and n > u - 5 and u <= 14 then u = u + 1 end
		end
		return u
	end

	function C:buildAvailable(kind)
		return kind <= 5 or kind == 16 or kind == 19 or kind < self:unlockedKinds()
	end

	local function hasLevels(kind) return kind >= C.K_PUTTING_GREEN and kind ~= C.K_SNACK_BAR end

	function C:existing(kind)
		if not hasLevels(kind) then return nil end
		for i, o in ipairs(self.land.objects) do if o.kind == kind then return i - 1 end end
		return nil
	end

	-- Land::covers_object: the footprint covers a tile of an object already standing
	function C:coversObject(a, b, size)
		local land = self.land
		for r = 0, size - 1 do
			for c = 0, size - 1 do
				local ta, tb = a + r, b + c
				if inside(ta, tb) then
					local i = idx(ta, tb)
					if land.ty[i] == 22 or band(land.flags[i], F_FOOTPRINT) ~= 0 then
						local o = land:objectAt(i)
						if o and o.kind >= 0 then return true end
					end
				end
			end
		end
		return false
	end

	-- what building `kind` at (a, b) would cost, or nil and why not
	function C:buildQuote(kind, a, b)
		local land = self.land
		if not self:buildAvailable(kind) then return nil, "Build more holes to unlock this building" end
		local ex = self:existing(kind)
		if ex and C.rank(self:openHoles()) < 2 then return nil, "Upgrades need a Country Club course" end
		if ex and land.objects[ex + 1].sub >= 1 then return nil, "That building can't be upgraded further" end
		local k = L.kinds()[kind]
		local size = k.size + (ex and 1 or 0)
		local clear = land:fits(a, b, size, kind, self.theme)
		if not clear then return nil, "There is no room for that building there" end
		-- "Fix original bugs": a lot may overlap its own kind only to upgrade it (OpenSGolf FIXES.md 2)
		if not ex and self.fixes and self:coversObject(a, b, size) then return nil, "There is no room for that building there" end
		if kind == 0 then clear = idiv(clear, 2) end
		local level = ex and land.objects[ex + 1].sub + 1 or 0
		local units = idiv(floor(k.price / UNIT) * (level + 2), 2) + clear
		return units * UNIT, nil, size, level, ex
	end

	-- the building tool: puts down (or upgrades) building `kind` with its corner at (a, b), facing dir 0..3
	function C:build(kind, a, b, dir)
		local land, t = self.land, self.terrain
		local cost, why, size, level, ex = self:buildQuote(kind, a, b)
		if not cost then
			self:sound("refused")
			self:toast(why)
			return false
		end
		if not self:affordable(cost) then
			self:sound("refused")
			self:toast(("This change costs %s. You have only %s."):format(money(cost), money(self.cash)))
			return false
		end
		if ex then
			local o = land.objects[ex + 1]
			local s = land:footprintSize(o)
			land:removeObject(ex)
			land:writeArea(t, o.a, o.b, o.a + s - 1, o.b + s - 1)
		end
		local n = land:placeSized(self.rng, a, b, kind, 0, self.theme, ex and 1 or 0)
		local o = land.objects[n + 1]
		o.sub = level
		o.dir = (dir or 0) % 4
		land:writeArea(t, a, b, a + size - 1, b + size - 1)
		self:spend(cost)
		self:sound("build")
		self:changed(true)
		return true
	end

	------------------------------------------------------------------------------------------------ holes

	function C:canOpenHole()
		local h = self.nextHole
		if h < 1 or h >= 19 then return false end
		local hr = self.holes[h]
		return hr.back[1] ~= 0 and hr.pin[1] ~= 0
	end

	-- the highest driving range level + 1 (Course::level[10]), which shortens the par of long holes
	function C:rangeLevel()
		local lv = 0
		for _, o in ipairs(self.land.objects) do
			if o.kind == C.K_DRIVING_RANGE then lv = max(lv, o.sub + 1) end
		end
		return lv
	end

	-- the straight length in yards from tee to pin, 25 a tile, plus a quarter over `over`
	local function straightLength(hr, over)
		local dx, dy = hr.back[1] - hr.pin[1], hr.back[2] - hr.pin[2]
		local l = floor(sqrt((dx * dx + dy * dy) * 625))
		if l > over then l = l + idiv(l - over, 4) end
		return l
	end

	-- the figures shown over the hole being built: its number, length and the par it would open with (building_figures)
	function C:buildingFigures()
		local h = self.nextHole
		if h < 1 or h >= 19 then return nil end
		local hr = self.holes[h]
		if hr.back[1] == 0 or hr.pin[1] == 0 then return nil end
		local len = hr.length ~= 0 and hr.length or straightLength(hr, 200)
		return h, len, C.parFor(len, hr.flags, self:rangeLevel(), true)
	end

	function C.parFor(len, flags, level10, anyDogleg)
		local eff = len
		if band(flags, 0x60) ~= 0 and (anyDogleg or eff > 250) then eff = eff + 25 end
		if eff > 300 then eff = eff - 25 * level10 end
		local par
		if eff > 625 then par = 6 elseif eff > 474 then par = 5 elseif eff > 249 then par = 4 elseif eff < 51 then par = 2 else par = 3 end
		return par, eff
	end

	local function openingText(h, par, len, eff, flags)
		local size = "scenic "
		if par == 3 then size = eff < 125 and "short " or (eff > 200 and "long " or size)
		elseif par == 4 then size = eff < 350 and "short " or (eff > 425 and "long " or size)
		elseif par == 5 then size = eff < 500 and "short " or (eff > 575 and "long " or size) end
		local s = ("Hole #%d, a %s%d yard "):format(h, size, len)
		if band(flags, 0x1000) ~= 0 then s = s .. "uphill " end
		if band(flags, 0x2000) ~= 0 then s = s .. "downhill " end
		s = s .. ("par %d"):format(par)
		if band(flags, 0x20) ~= 0 then s = s .. " with a dogleg to the left" end
		if band(flags, 0x40) ~= 0 then s = s .. " with a dogleg to the right" end
		return s .. ", is now open for play."
	end

	local UNLOCK_NAMES = { [6] = "Putting Green", [7] = "Snack Bar", [8] = "Pro Shop", [9] = "Swim Club", [10] = "Driving Range",
		[11] = "Cart Garage", [12] = "Marina", [13] = "Resort Hotel", [14] = "Airstrip" }
	local RANK_NAMES = { [0] = "Municipal", "Daily Fee", "Country Club", "Championship" }

	-- Club::open_hole: the hole being built needs a tee and a green; its par comes from its length
	function C:openHole()
		if not self:canOpenHole() then
			self:sound("refused")
			return nil
		end
		local h = self.nextHole
		local hr = self.holes[h]
		local land = self.land
		-- what the layout pass would set (holetool.rs layout): the tee's facing and the up- or downhill flag; the pass's
		-- dogleg and measured length need the golfers' trial shots, so the hole is measured straight
		hr.teeFacing = dir8(angle(hr.pin[1] - hr.back[1], hr.pin[2] - hr.back[2]))
		hr.flags = band(hr.flags, bnot(0x3000))
		local hb, hp = land:corner(hr.back[1], hr.back[2]), land:corner(hr.pin[1], hr.pin[2])
		if hp > hb + 1 then hr.flags = bor(hr.flags, 0x1000) end
		if hp < hb - 1 then hr.flags = bor(hr.flags, 0x2000) end
		if hr.length == 0 then hr.length = straightLength(hr, 250) end
		local par, eff = C.parFor(hr.length, hr.flags, self:rangeLevel(), false)
		hr.par = par
		hr.fwdFacing = dir8(angle(hr.pin[1] - hr.fwd[1], hr.pin[2] - hr.fwd[2]))
		-- the new tee grows in (f::GROWING)
		if inside(hr.back[1], hr.back[2]) then
			local i = idx(hr.back[1], hr.back[2])
			self.flags[i] = bor(self.flags[i], 0x4000)
		end
		self.nextHole = 1
		while self.nextHole < 19 and self.holes[self.nextHole].par ~= 0 do self.nextHole = self.nextHole + 1 end
		local msg = openingText(h, par, hr.length, eff, hr.flags)
		-- holetool.rs unlock_text
		if h == 6 or h == 10 or h == 18 then
			msg = msg .. (" Your course is now a %s course!"):format(RANK_NAMES[C.rank(self:openHoles())])
		elseif h > self.unlocked - 5 and self.unlocked <= 14 and not self.sandbox then
			local name = UNLOCK_NAMES[self.unlocked]
			if name then msg = msg .. (" You can now build a %s."):format(name) end
			self.unlocked = self.unlocked + 1
		end
		self:message(msg)
		self:sound("opened")
		self:changed(true)
		return h
	end

	-- the hole a tile belongs to (its tee or cup green), or nil
	function C:holeAt(a, b)
		if not inside(a, b) then return nil end
		local k = band(self.flags[idx(a, b)], CF_LOW)
		return k ~= 0 and k or nil
	end

	function C:isCup(a, b)
		return inside(a, b) and band(self.flags[idx(a, b)], CF_CUP) ~= 0
	end

	-- the tee tiles' arrows (decor::tee_arrow) for camera rotation `rot` (0..3); returns whether a byte changed
	function C:teeArrows(rot)
		local t = self.terrain
		local camera = 2 * (rot % 4)
		local changed = false
		for a = 0, N - 1 do
			for b = 0, N - 1 do
				local i = idx(a, b)
				local h = band(self.flags[i], CF_LOW)
				local o = t:index(a, b)
				if h ~= 0 and h < 19 and t.ty[o] == T_TEE then
					local r = self.holes[h]
					local v = 0
					if r.par ~= 0 then
						v = band(camera - r.teeFacing - 2, 7) * 3 + 1
						if band(r.flags, 0x20) ~= 0 then v = v + 1 end
						if band(r.flags, 0x40) ~= 0 then v = v + 2 end
					end
					if t.variation[o] ~= v then
						t.variation[o] = v
						changed = true
					end
				end
			end
		end
		if changed then t:dirty() end
		return changed
	end

	return C
end
