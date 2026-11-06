-- New-game land, as the publisher's golf.exe builds it. Ported from OpenSGolf's sg-core/src/land.rs (v0.6.10), which documents
-- every rule; this follows it line by line on the original's 50 x 50 map.
--
-- A new game deals the sixteen properties out to sixteen offer slots; the slot decides acreage and price, the property the
-- theme, coast and relief. Picking one runs the generator: tree streaks, a creek, the coast, ponds and rock patches, wildlife
-- spots, the clubhouse, the property's own feature, obstacles by difficulty, and the land outside the purchase.
--
-- Layout as the exe: tile (a, b), index a * 50 + b (0-based tables); corner heights on a 51 x 51 grid, index a * 51 + b,
-- sea level 3. Land:toTerrain() gives the renderer's Terrain (x = a, y = b).

return function(Game)
	local T = Game.require("terrain")
	local Rng = Game.require("rng")
	local floor, abs, max, min = math.floor, math.abs, math.max, math.min

	local L = {}

	local N = 50          -- map edge in tiles (the original's)
	local NN = N * N      -- tiles
	local HP = N + 1      -- corner row pitch
	local HN = HP * HP    -- corners
	L.N = N

	-- integer division truncating toward zero, as Rust's i32 /
	local function idiv(a, b)
		local q = a / b
		return q >= 0 and floor(q) or -floor(-q)
	end

	-- tile types (the exe's 23)
	L.T_TEE, L.T_GREEN, L.T_FAIRWAY, L.T_ROUGH, L.T_DEEP_ROUGH = 0, 1, 2, 4, 5
	L.T_SAND, L.T_WASTE, L.T_POT, L.T_RAVINE, L.T_BRUSH, L.T_ROCKS = 7, 8, 9, 10, 11, 12
	L.T_TREE, L.T_PINE, L.T_PALM, L.T_ELM, L.T_WATER, L.T_WETLANDS = 13, 14, 15, 16, 17, 18
	L.T_MARSH, L.T_OUT, L.T_HOME_SITE, L.T_BUILDING = 19, 20, 21, 22
	local T_GREEN, T_ROUGH, T_DEEP_ROUGH, T_WASTE, T_RAVINE, T_BRUSH, T_ROCKS = 1, 4, 5, 8, 10, 11, 12
	local T_TREE, T_PINE, T_PALM, T_ELM, T_WATER, T_WETLANDS, T_MARSH = 13, 14, 15, 16, 17, 18, 19
	local T_OUT, T_HOME_SITE, T_BUILDING = 20, 21, 22

	-- object kinds
	L.K_PATH, L.K_BENCH, L.K_FLOWERS, L.K_WASHER, L.K_LANDMARK, L.K_HOME_SITE = 0, 1, 2, 3, 4, 5
	L.K_PUTTING_GREEN, L.K_SNACK_BAR, L.K_DRIVING_RANGE, L.K_MARINA, L.K_CLUBHOUSE = 6, 7, 10, 12, 15
	local K_LANDMARK, K_HOME_SITE, K_PUTTING_GREEN, K_SNACK_BAR = 4, 5, 6, 7
	local K_DRIVING_RANGE, K_MARINA, K_CLUBHOUSE = 10, 12, 15

	-- tile flag bits
	local F_PATH, F_JOINED, F_SPOT, F_PATH_ALT, F_FOOTPRINT = 0x20, 0x40, 0x100, 0x200, 0x400
	local F_CREEK, F_STREAK_48, F_OBSTACLE = 0x1000, 0x2000, 0x8000
	L.FLAG = { PATH = F_PATH, JOINED = F_JOINED, SPOT = F_SPOT, PATH_ALT = F_PATH_ALT, FOOTPRINT = F_FOOTPRINT,
		CREEK = F_CREEK, STREAK_48 = F_STREAK_48, OBSTACLE = F_OBSTACLE }

	local DX = { [0] = 0, 1, 1, 1, 0, -1, -1, -1 }
	local DY = { [0] = -1, -1, 0, 1, 1, 1, 0, -1 }

	local TRIES = 100000

	local bit = bit or require("bit")
	local band, bor, bnot = bit.band, bit.bor, bit.bnot

	------------------------------------------------------------------------------------------------ the exe's RNG

	-- 32-bit LCG (x * 1103515245 + 12345), seeded with the millisecond clock times 37; a draw scales bits 16..30
	local ExeRng = {}
	ExeRng.__index = ExeRng
	L.ExeRng = ExeRng

	-- (a * b) mod 2^32 exactly, for 0 <= a, b < 2^32
	local function mul32(a, b)
		local ah, al = floor(a / 65536), a % 65536
		return (((ah * b) % 65536) * 65536 + al * b) % 4294967296
	end

	function ExeRng.new(state) return setmetatable({ state = state % 4294967296 }, ExeRng) end
	function ExeRng.fromClock(ms) return ExeRng.new(mul32(ms % 4294967296, 37)) end

	function ExeRng:below(n)
		self.state = (mul32(self.state, 0x41c64e6d) + 0x3039) % 4294967296
		local r = floor(self.state / 65536) % 32768
		local range = (n % 4294967296) % 65536
		local v = (r / 32768) * range
		return v >= 0 and floor(v) or -floor(-v)
	end

	------------------------------------------------------------------------------------------------ height noise

	local Noise = {}
	Noise.__index = Noise
	L.Noise = Noise

	-- a 16 x 16 grid of 0..15 that wraps (drawn as 18 x 18, of which the 16 x 16 corner is used)
	function Noise.new(rng)
		local src = {}
		for r = 0, 17 do
			src[r] = {}
			for c = 0, 17 do src[r][c] = rng:below(16) end
		end
		local g = {}
		for r = 0, 15 do
			g[r] = {}
			for c = 0, 15 do g[r][c] = src[r][c] end
			g[r][16] = g[r][0]
		end
		g[16] = g[0]
		return setmetatable({ g = g }, Noise)
	end

	function Noise:sample(x, y)
		local i = floor((x - 0x80) / 256) % 16
		local j = floor((y - 0x80) / 256) % 16
		local fx = floor((x - 0x80) / 8) % 32
		local fy = floor((y - 0x80) / 8) % 32
		local g = self.g
		local s = g[i][j + 1] * (32 - fx) * fy + g[i + 1][j] * (32 - fy) * fx + g[i][j] * (32 - fx) * (32 - fy)
			+ g[i + 1][j + 1] * fy * fx
		return idiv(s, 32)
	end

	local function clampExe(v, lo, hi)
		v = max(v, lo)
		if v > hi and lo <= hi then return hi end
		return v
	end

	-- two octaves mixed 6:4, scaled to 0..512
	function Noise:field(a, b)
		local n1 = self:sample(floor(a / 4), floor(b / 4))
		local n2 = self:sample(floor(a / 4) * 2, floor(b / 4) * 2)
		local v = (n1 * 6 + n2 * 4) * 7
		return clampExe(floor(idiv(v, 64) / 2), 0, 0x200)
	end

	------------------------------------------------------------------------------------------------ tables

	local THEME_NAMES = { [0] = "parkland", "desert", "tropical", "links" }
	L.THEME_NAMES = THEME_NAMES
	local COAST = { inland = 0, coast = 1, island = 2 }
	local RELIEF = { gentle = 0, rolling = 1, hilly = 2 }
	local THEME = { parkland = 0, desert = 1, tropical = 2, links = 3 }

	-- the sixteen property records (core/data/properties), with the exe's theme, coast and relief numbers
	local records
	function L.records()
		if not records then
			records = {}
			for _, p in ipairs(Game.Data.properties.property) do
				records[p.index] = { name = p.name, course = p.course, bonus = p.bonus, theme = THEME[p.theme],
					coast = COAST[p.coast], relief = RELIEF[p.relief], mapX = p.map_x, mapY = p.map_y }
			end
		end
		return records
	end

	-- per tile type: layer (walking cost), class, clearing cost in money units
	local landTypes
	local function landType(t)
		if not landTypes then
			landTypes = {}
			for _, row in ipairs(Game.Data.terrain.terrain) do
				if row.tile <= 22 then
					landTypes[row.tile] = { layer = row.walk, class = row.class, clear = floor(row.clear_cost / 100), hazard = row.hazard }
				end
			end
		end
		return landTypes[max(0, min(22, t))]
	end
	L.landType = landType

	-- building and object kinds 0..19: name, footprint edge, price (money)
	local kinds
	function L.kinds()
		if not kinds then
			kinds = {}
			for _, set in ipairs({ Game.Data.amenities.amenity, Game.Data.buildings.building }) do
				for _, k in ipairs(set) do
					kinds[k.kind] = { id = k.id, name = k.name, size = k.footprint, price = k.price }
				end
			end
		end
		return kinds
	end
	local function kindSize(k) return L.kinds()[k].size end

	L.SLOT_PRICE_UNITS = { [0] = 500, 600, 700, 800, 1200, 1500, 2000, 2500, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000 }

	function L.slotAcres(i, p, sandbox)
		if sandbox then return 250 end
		local bonus = i > 3 and 20 or 10
		local base = (i + 4) * 10
		local coast = L.records()[p].coast
		if coast == 0 then return base + bonus elseif coast == 2 then return base - bonus end
		return base
	end

	-- the properties dealt to the sixteen slots: 12..15 get four different themes, slot 0 a Parkland property
	function L.dealOffer(rng, sandbox)
		local recs = L.records()
		local slot, out = {}, {}
		local i = 12
		while i < 16 do
			local p = rng:below(16)
			local clash = false
			for j = 12, i - 1 do
				if recs[slot[j]].theme == recs[p].theme then clash = true break end
			end
			if not clash then
				slot[i] = p
				out[i] = { property = p, acres = L.slotAcres(i, p, sandbox) }
				i = i + 1
			end
		end
		i = 0
		while i < 12 do
			local p = rng:below(16)
			local taken = false
			for j = 0, 15 do if slot[j] == p then taken = true end end
			if not (taken or (i == 0 and recs[p].theme ~= 0)) then
				slot[i] = p
				out[i] = { property = p, acres = L.slotAcres(i, p, sandbox) }
				i = i + 1
			end
		end
		return out
	end

	------------------------------------------------------------------------------------------------ Land

	local Land = {}
	Land.__index = Land
	L.Land = Land

	local function idx(a, b) return a * N + b end
	local function inMap(v) return v >= 0 and v < N end

	function Land:record() return L.records()[self.slot.property] end
	function Land:tile(a, b) return self.ty[idx(a, b)] end

	function Land:tyAt(i)
		if i >= 0 and i < NN then return self.ty[i] end
		return 0xff
	end

	function Land:setTy(i, t)
		if i >= 0 and i < NN then
			self.ty[i] = t
			self.layer[i] = landType(t).layer
		end
	end

	function Land:h(i)
		if i >= 0 and i < HN then return self.height[i] end
		return 0
	end

	function Land:setH(i, v)
		if i >= 0 and i < HN then self.height[i] = v % 256 end
	end

	function Land:flagsOr(i, f)
		if i >= 0 and i < NN then self.flags[i] = bor(self.flags[i], f) end
	end

	function Land:blocked(a, b)
		return not inMap(a) or not inMap(b) or self:tile(a, b) == T_OUT
	end

	function Land:noiseHeight(noise, a, b)
		if not inMap(a) or not inMap(b) then return 3 end
		local here = self:tile(a, b)
		local nxt = self:tyAt(idx(a, b) + N)
		if here == T_WATER or nxt == T_WATER or here == T_WETLANDS or here == T_MARSH then return 3 end
		local rec = self:record()
		local shift = rec.relief == 2 and 128 or 64
		local n = noise:field(a * shift, b * shift)
		if rec.theme == 1 and b < 16 then n = n - idiv((16 - b) * self.hill, 6) end
		return clampExe(idiv(n, self.hill) + 1, 3 + (self.difficulty ~= 0 and 1 or 0), 15)
	end

	-- corner height in play: sea level off the map and deep in the unowned land, else the stored height
	function Land:corner(a, b)
		if not inMap(a) or not inMap(b) then return 3 end
		if self:tile(a, b) == T_OUT and self:blocked(a - 1, b) and self:blocked(a, b + 1) then return 3 end
		return self.height[a * HP + b]
	end

	function Land:objectAt(i)
		local v = self.var[i]
		return self.objects[v + 1]
	end

	function Land:objectsFull()
		if #self.objects < 0xff then return false end
		for _, o in ipairs(self.objects) do if o.kind == -1 then return false end end
		return true
	end

	-- footprint test with a one-tile ring: the clearing cost (money units), or nil when not allowed
	function Land:fits(a, b, size, kind, theme)
		if kind >= 4 and kind < 20 and self:objectsFull() then return nil end
		local cost, dryRing = 0, false
		if size >= -1 then
			for r = -1, size do
				for c = -1, size do
					local ta, tb = a + r, b + c
					local i = ta * N + tb
					local ring = r == -1 or c == -1 or r == size or c == size
					if ring then
						if self:tyAt(i) ~= T_WATER then dryRing = true end
					else
						if self:blocked(ta, tb) then return nil end
						local t = self:tyAt(i)
						local f = self.flags[i]
						if kind == K_MARINA and (theme == 0 or theme == 2) and t ~= T_WATER then return nil end
						if kind ~= 0 then
							if t == T_HOME_SITE or t == 0 or band(f, 0x8080) ~= 0 then return nil end
							if t == T_BUILDING or band(f, F_FOOTPRINT) ~= 0 then
								local o = self:objectAt(i)
								if not o or o.kind ~= kind then return nil end
							end
						end
						if landType(t).class == 13 or t == T_ROCKS or (t == T_WATER and kind ~= K_MARINA) or t == T_WETLANDS
							or t == T_MARSH then
							cost = cost + landType(t).clear
						end
						if band(f, 0x8000) ~= 0 then return nil end
					end
				end
			end
			if dryRing then return cost end
		end
		if kind ~= 0 and kind ~= 4 then return nil end
		return cost
	end

	function Land:footprintSize(o)
		local k = L.kinds()[o.kind]
		local edge = k and k.size or 1
		if o.kind > 5 and o.kind ~= K_SNACK_BAR then return edge + max(0, min(1, o.sub)) end
		return edge
	end

	function Land:place(rng, a, b, kind, fl, theme)
		return self:placeSized(rng, a, b, kind, fl, theme, fl == -2 and 1 or 0)
	end

	-- puts down an object: corners flattened to the anchor's height, tiles made building tiles (a putting green keeps green,
	-- a driving range rough, a marina water), recorded. Returns the object's index (0-based).
	function Land:placeSized(rng, a, b, kind, fl, theme, extra)
		local size = kindSize(kind) + extra
		local anchorH = self:h(a * HP + b)
		for c = 0, size - 1 do
			for k = 0, size - 1 do
				if k < size - 1 or c ~= 0 then self:setH((c + a) * HP + b + k, anchorH) end
				local i = (b + k) + (c + a) * N
				local t = kind ~= K_HOME_SITE and T_BUILDING or T_HOME_SITE
				local edge = c ~= 0 or k ~= 0
				if kind == K_PUTTING_GREEN and edge then
					t = T_GREEN
				elseif kind == K_DRIVING_RANGE and edge then
					t = c == size - 1 and T_DEEP_ROUGH or T_ROUGH
				elseif kind == K_MARINA and (theme == 0 or theme == 2) and edge then
					t = T_WATER
				end
				if i >= 0 and i < NN then
					self.ty[i] = t
					self.layer[i] = landType(T_BUILDING).layer
					local f = band(self.flags[i], 0xecff)
					self.flags[i] = fl > 0 and bor(f, fl) or f
					self.var[i] = 0xff
				end
			end
		end
		if kind == K_DRIVING_RANGE then
			local span = size - 2
			for _, mark in ipairs({ T_GREEN, T_GREEN, T_GREEN, 7 }) do
				local r1 = rng:below(span)
				local r2 = rng:below(span)
				local i = b + r1 + (r2 + a) * N + N + 1
				if i >= 0 and i < NN then self.ty[i] = mark end
			end
		elseif kind == K_CLUBHOUSE then
			self.staffStart = { a + 1, b + 1 }
		end
		if fl < 0 then return 0 end
		self:flagsOr(a * N + b, kind + 1)
		local n
		for i, o in ipairs(self.objects) do
			if o.kind == -1 then n = i - 1 break end
		end
		local rec = { kind = kind, a = a, b = b, dir = 0, flags = 0, sub = 0, val = 0 }
		if n then self.objects[n + 1] = rec else self.objects[#self.objects + 1] = rec; n = #self.objects - 1 end
		local s = kindSize(kind)
		for r = 0, s - 1 do
			for c = 0, s - 1 do
				local i = (a + r) * N + b + c
				if i >= 0 and i < NN then
					self.var[i] = n
					self.flags[i] = bor(band(self.flags[i], 0xfeff), F_FOOTPRINT)
				end
			end
		end
		return n
	end

	-- every water tile starts deep (2); next to land shallow (0); next to shallow water middling (1)
	function Land:waterDepth()
		for i = 0, NN - 1 do
			if landType(self.ty[i]).class == 17 then self.var[i] = 2 end
		end
		repeat
			local changed = false
			for a = 0, N - 1 do
				for b = 0, N - 1 do
					local i = idx(a, b)
					if landType(self.ty[i]).class == 17 then
						local v = self.var[i]
						for k = 0, 7 do
							local na, nb = a + DX[k], b + DY[k]
							if not self:blocked(na, nb) then
								local j = idx(na, nb)
								if landType(self.ty[j]).class ~= 17 then v = 0 end
								if self.var[j] == 0 and v ~= 0 then v = 1 end
							end
						end
						if v ~= self.var[i] then
							self.var[i] = v
							changed = true
						end
					end
				end
			end
		until not changed
	end

	function Land:removeObject(i)
		local o = self.objects[i + 1]
		if not o or o.kind < 0 then return end
		local size = self:footprintSize(o)
		local theme = self:record().theme
		local kind = o.kind
		o.kind = -1
		local ai = idx(o.a, o.b)
		self.flags[ai] = band(self.flags[ai], 0xfde0)
		for r = 0, size - 1 do
			for c = 0, size - 1 do
				local t = (o.a + r) * N + o.b + c
				if t >= 0 and t < NN then
					local ty
					if kind == K_MARINA and (theme == 0 or theme == 2) then ty = T_WATER
					elseif self.slotIndex > 11 then ty = T_DEEP_ROUGH
					else ty = T_ROUGH end
					self.flags[t] = band(self.flags[t], 0xfbdf)
					self.ty[t] = ty
					self.layer[t] = landType(ty).layer
					self.var[t] = 0
				end
			end
		end
	end

	-- "Fix original bugs": what was put down on land the owned area then cut off goes, and cut tiles are out of bounds
	-- (sea round an island) again (OpenSGolf issue #144)
	function Land:clearCut(cut)
		for i, o in ipairs(self.objects) do
			if o.kind >= 0 and o.kind ~= K_CLUBHOUSE then
				local s = max(1, self:footprintSize(o))
				local off = false
				for r = 0, s - 1 do
					for c = 0, s - 1 do
						if not inMap(o.a + r) or not inMap(o.b + c) or cut[idx(o.a + r, o.b + c)] then off = true end
					end
				end
				if off then
					local oa, ob = o.a, o.b
					self:removeObject(i - 1)
					local function ring(a, b) return a >= 0 and a <= N and b >= 0 and b <= N end
					local count = {}
					for r = -1, s + 1 do
						for c = -1, s + 1 do
							local edge = r == -1 or c == -1 or r == s + 1 or c == s + 1
							if edge and ring(oa + r, ob + c) then
								local v = self:h((oa + r) * HP + ob + c)
								count[v] = (count[v] or 0) + 1
							end
						end
					end
					-- the commonest height on the ring; ties go to the lower
					local level, best = nil, -1
					for v = 0, 255 do
						if count[v] and count[v] > best then level, best = v, count[v] end
					end
					if level then
						for r = 0, s do
							for c = 0, s do
								if ring(oa + r, ob + c) then self:setH((oa + r) * HP + ob + c, level) end
							end
						end
					end
				end
			end
		end
		local island = self:record().coast == 2
		local clear = bnot(bor(0x1f, F_PATH, F_JOINED, F_SPOT, F_PATH_ALT, F_FOOTPRINT, F_CREEK, F_OBSTACLE))
		for i = 0, NN - 1 do
			if cut[i] then
				local t = island and T_WATER or T_OUT
				if self.ty[i] ~= t then
					self.ty[i] = t
					self.layer[i] = landType(t).layer
				end
				self.flags[i] = band(self.flags[i], clear) % 65536
			end
		end
	end

	function Land:unown(a, b)
		local i = idx(a, b)
		if self:record().coast ~= 2 then
			self.ty[i] = T_OUT
		else
			self.ty[i] = T_WATER
			self.flags[i] = band(self.flags[i], 0xfcdf)
		end
	end

	function Land:inPlay(a, b)
		return inMap(a) and inMap(b) and self.ty[idx(a, b)] ~= T_OUT
	end

	-- width of the unowned border round the owned square: a square of side 2r with 4r^2 tiles about acres x 10
	local function ownedMargin(slot, size)
		local acres = slot.acres % 256
		local r, m = floor(size / 2), 0
		repeat
			m = m + 1
			r = r - 1
		until acres * 10 >= r * r * 4
		return m
	end

	------------------------------------------------------------------------------------------------ the generator

	-- a property landmark, placed (8 - difficulty) times for Hawaii, Oahu, Northeast, Wales, Spain and Jamaica
	local function landmark(land, rng, prop, n, a, b, theme)
		if prop == 5 then
			-- waterfall: a small pool stepped into the hillside
			local i = idx(a, b)
			land.ty[i] = T_WATER
			land:setH(b + a * HP + HP - 1, 6)
			rng:below(4)
			for k = 0, 7 do
				local ka, kb = DX[k] + a, DY[k] + b
				local ti = ka * N + kb
				local corner = kb + ka * HP
				if k == 0 or k == 6 then
					land.ty[ti] = T_WATER
					land:setH(corner + HP - 1, 6)
				elseif k == 1 or k == 7 then
					land.ty[ti] = T_DEEP_ROUGH
					land:setH(corner + HP - 1, 6)
				elseif k == 2 then
					land.ty[ti] = T_WATER
					land:setH(corner + HP - 1, 3)
				else
					if rng:below(2) ~= 0 then land.ty[ti] = T_WATER end
					land:setH(corner - 1, 3)
				end
			end
			return
		end
		if prop == 15 or prop == 12 or prop == 8 then
			local o = land.objects[land:place(rng, a, b, K_LANDMARK, 0, theme) + 1]
			o.sub = 0xb
			if prop == 8 then
				o.sub = rng:below(2) ~= 0 and 6 or 2
			elseif prop == 12 then
				o.sub = 3
			end
			o.dir = rng:below(4)
			for k = 0, 7 do
				local i = DY[k] + (DX[k] + a) * N + b
				local t = land:tyAt(i)
				if t ~= T_BUILDING and t ~= T_WATER then
					if n % 2 == 0 then
						land.ty[i] = T_DEEP_ROUGH
						land.flags[i] = bor(land.flags[i], (k % 2) * 512, F_PATH)
					else
						land.ty[i] = prop == 12 and T_ROCKS or T_ROUGH
						if prop == 15 then
							land.ty[i] = T_WATER
						elseif k == 0 then
							local v = b + a * HP
							for _, d in ipairs({ 0, HP, -1, HP - 1 }) do
								land:setH(v + d, land:h(v + d) + 2)
							end
						end
					end
				end
			end
		end
		if prop == 13 then
			local o = land.objects[land:place(rng, a, b, K_LANDMARK, 0, theme) + 1]
			o.sub = 1
			o.dir = rng:below(4)
			for k = 0, 7 do
				local t = land:tyAt(b + DY[k] + (DX[k] + a) * N)
				if t ~= 0xff and landType(t).class == 13 then o.sub = 10 end
				if t == T_WATER then
					o.sub = 9
					break
				end
			end
			for k = 0, 7 do
				local s = o.sub
				local i = DY[k] + (DX[k] + a) * N + b
				if i >= 0 and i < NN then
					if s == 1 then
						land.flags[i] = bor(land.flags[i], F_SPOT)
						land.ty[i] = T_BRUSH
					end
					if s == 3 and land.ty[i] == T_ROUGH then land.ty[i] = T_RAVINE end
					if s == 9 and land.ty[i] == T_ROUGH and rng:below(3) == 0 then
						land.flags[i] = bor(land.flags[i], F_SPOT)
					end
				end
			end
		elseif prop == 6 then
			local o = land.objects[land:place(rng, a, b, K_LANDMARK, 0, theme) + 1]
			o.sub = n % 2 == 0 and 8 or 12
			o.dir = rng:below(4)
			for k = 0, 7 do
				local i = DY[k] + (DX[k] + a) * N + b
				if i >= 0 and i < NN then
					if n % 2 == 0 then
						if land.ty[i] ~= T_WATER then
							land.flags[i] = bor(land.flags[i], (k % 2) * 512, F_PATH)
						end
					else
						land.flags[i] = bor(land.flags[i], F_CREEK)
					end
				end
			end
		end
	end

	-- Builds the land for an offer slot, as the exe does when a property is bought.
	-- opts.fixes: "Fix original bugs" (OpenSGolf's default on; off reproduces the exe exactly)
	function L.generate(slotIndex, slot, difficulty, sandbox, rng, noise, opts)
		local fixes = not (opts and opts.fixes == false)
		local rec = L.records()[slot.property]
		local theme = rec.theme
		local prop = slot.property
		local desert = theme == 1
		local si = slotIndex
		local size = N

		local hill = ({ [0] = 48, 32, 16 })[min(2, rec.relief)]
		local q = floor(si / 4)
		if q == 0 then hill = hill + floor(hill / 2)
		elseif q == 1 then hill = hill + floor(hill / 4)
		elseif q == 3 then hill = hill - floor(hill / 4) end
		if sandbox then hill = hill + 16 end

		local base = T_ROUGH
		if not sandbox then
			if si > 7 then base = desert and T_ROCKS or T_DEEP_ROUGH end
			if si > 11 then base = desert and T_ROCKS or T_BRUSH end
		end

		local land = setmetatable({
			slotIndex = slotIndex, slot = slot, difficulty = difficulty,
			ty = {}, flags = {}, layer = {}, var = {}, height = {}, objects = {},
			clubhouse = { -1, -1 }, staffStart = { -1, -1 }, view = { -1, -1 }, margin = 0, hill = hill,
		}, Land)
		for i = 0, NN - 1 do
			land.ty[i], land.flags[i], land.layer[i], land.var[i] = base, 0, landType(base).layer, 0
		end
		for i = 0, HN - 1 do land.height[i] = 0 end

		-- streaks of trees (rocks, brush or deep rough by theme), random walks, up to 1250 tiles in all
		do
			local limit, total, n = 5000, 0, 0
			while true do
				local a = rng:below(size)
				local b = rng:below(size)
				local odd = n % 2 == 1
				local t
				if theme == 0 then
					t = (prop == 9 or b >= size / 2) and T_PINE or T_TREE
				elseif theme == 1 then
					t = odd and T_ROCKS or T_PINE
				elseif theme == 2 then
					if not odd then t = T_PINE elseif band(n, 2) ~= 0 then t = T_TREE else t = T_ROCKS end
				else
					t = odd and T_BRUSH or T_DEEP_ROUGH
				end
				local len = 0
				while true do
					if a < 0 or b < 0 or a >= size or b >= size or len >= idiv(limit, 128) then break end
					local i = idx(a, b)
					len = len + 1
					land.ty[i] = t
					if len == 48 then land.flags[i] = bor(land.flags[i], F_STREAK_48) end
					land.layer[i] = landType(t).layer
					if rng:below(64) == 0 then
						land.flags[i] = bor(land.flags[i], F_SPOT)
					else
						land.flags[i] = band(land.flags[i], bnot(F_SPOT)) % 65536
					end
					a = a + rng:below(3) - 1
					b = b + rng:below(3) - 1
					if a < 0 then break end
				end
				total = total + len
				if total > 1250 then break end
				limit = limit + 2500
				n = n + 1
				if limit >= 45000 then break end
			end
		end

		-- a creek from the far edge that runs downhill, with banks of waste bunker or rocks (ravine in the desert)
		if rec.coast ~= 2 then
			local share = size
			local creekT = desert and T_BRUSH or T_WATER
			local a = share / 3
			a = floor(a) + rng:below(16)
			local b = size - 1
			local prevDir, dir = 0, 0
			while inMap(a) do
				local i = a * N + b
				land:setTy(i, creekT)
				land.flags[i] = bor(band(land.flags[i], 0xfeff), F_CREEK)
				if rng:below(64) == 0 then land:flagsOr(i, F_SPOT) end
				local nb = b + 1
				local best = 999
				local side = a + (rng:below(2) ~= 0 and 1 or -1)
				local bank = side * N + b + 1
				local na = side
				if land:tyAt(bank) ~= T_WATER and land:noiseHeight(noise, side, b + 1) == 3 then
					local v
					if desert then v = T_RAVINE else v = bor(band(bnot((side + b + 1) * 2), 4), 8) end
					land:setTy(bank, v)
				end
				local d = -2
				while d < 3 do
					local k = d % 8
					local ca, cb = DX[k] + a, DY[k] + b
					local hgt = noise:field(ca * 0x80, cb * 0x80)
					if hgt < best then
						dir, na, best, nb = d, ca, hgt, cb
					end
					d = d + 2
				end
				if dir == -prevDir then
					nb, na = b - 1, a
				end
				prevDir = dir
				if land:tyAt(na * N + nb) == T_WATER or nb < 0 then break end
				a, b = na, nb
			end
		end

		-- the sea along the b = 0 side of a coastal property, 2..12 tiles wide; each row's first tile out of bounds
		if rec.coast == 1 then
			local w = 5
			for a = 0, N - 1 do
				for b = 0, w - 1 do
					local i = idx(a, b)
					if land.ty[i] ~= T_WATER then
						land.ty[i] = T_WATER
						land.layer[i] = landType(T_WATER).layer
						land.flags[i] = band(land.flags[i], bnot(F_SPOT)) % 65536
						if b == w - 1 and rng:below(16) == 0 then land.flags[i] = bor(land.flags[i], F_SPOT) end
					end
					if b == 0 then land.ty[idx(a, 0)] = T_OUT end
				end
				w = w + rng:below(5) - 2
				if w < 2 then w = 2 elseif w > 12 then w = w - 1 end
			end
		end

		for i = 0, NN - 1 do land.flags[i] = band(land.flags[i], bnot(F_CREEK)) % 65536 end
		for a = 0, HP - 1 do
			for b = 0, HP - 1 do land.height[a * HP + b] = land:noiseHeight(noise, a, b) end
		end

		-- 24 patches on a 4 x 6 grid: ponds low, rocks (or sand, by theme) high; the first a wetland, more on harder games
		local cols = 4
		for n = 0, cols * cols * 3 / 2 - 1 do
			local a = rng:below(4) + 4 + (n % cols) * size / cols
			local b = rng:below(4) + 4 + floor(floor(n / cols) * size / cols)
			a = floor(a)
			local high = land:h(b + a * HP) > 3
			local t
			if theme == 0 then t = high and T_ROCKS or T_WATER
			elseif theme == 1 then t = high and T_ROCKS or T_PALM
			elseif theme == 2 then t = high and T_PALM or T_WATER
			else t = high and T_PALM or T_ROCKS end
			if (difficulty > 1 and rng:below(idiv(8, difficulty - 1)) == 0) or n == 0 then t = T_WETLANDS end
			if prop == 2 and (t == T_WASTE or t == T_WETLANDS) then t = T_ROCKS end
			local count = 0
			while true do
				local i = b + a * N
				local protected = i >= 0 and i < NN and band(land.flags[i], F_CREEK) ~= 0
				if not protected then
					if i >= 0 and i < NN then land.ty[i] = t end
					if rng:below(8) == 0 and t == T_WETLANDS then land:flagsOr(i, F_SPOT) end
					if i >= 0 and i < NN then land.layer[i] = landType(land.ty[i]).layer end
					if t == T_WATER then land:setH(b + a * HP, 3) end
				end
				if rng:below(2) == 0 then
					b = b + (rng:below(2) ~= 0 and 1 or -1)
				else
					a = a + (rng:below(2) ~= 0 and 1 or -1)
				end
				if not (inMap(a) and inMap(b)) then break end
				count = count + 1
				if count >= 5 and rng:below(16) == 0 then break end
			end
		end

		-- sixteen spots the next step clears again (the draws still happen), then elms become plain trees
		for _ = 1, 16 do
			local r1 = rng:below(size - 8)
			local r2 = rng:below(size - 8)
			land:flagsOr(r1 + r2 * size + 4 * size + 4, F_SPOT)
		end
		for i = 0, NN - 1 do
			land.flags[i] = band(land.flags[i], bnot(F_SPOT)) % 65536
			if land.ty[i] == T_ELM then land.ty[i] = T_TREE end
		end

		-- wildlife spots: (4 - difficulty) x 9
		local skip = desert and T_BRUSH or T_RAVINE
		local placed, tries = 0, 0
		while placed < (4 - difficulty) * 9 and tries < TRIES do
			tries = tries + 1
			local a = rng:below(size - 4) + 2
			local b = rng:below(size - 4) + 2
			if not land:blocked(a, b) then
				local i = idx(a, b)
				local t = land.ty[i]
				if t ~= T_HOME_SITE and t ~= T_BUILDING and t ~= T_ROUGH and t ~= T_WETLANDS and t ~= skip
					and (t ~= T_WATER or b > 6) then
					land.flags[i] = bor(land.flags[i], F_SPOT)
					placed = placed + 1
				end
			end
		end

		-- around water and wetlands, an edge whose two corners are both above sea level is pulled down (from 4) or nudged
		local RA = { [0] = 0, 1, 1, 0, 0 }
		local RB = { [0] = -1, -1, 0, 0, -1 }
		for a = 0, HP - 1 do
			for b = 0, HP - 1 do
				local t = land:tyAt(a * N + b)
				if t == T_WATER or t == T_WETLANDS then
					for k = 0, 3 do
						local va, vb = RA[k] + a, RB[k] + b
						if inMap(va) and inMap(vb) then
							local nbr = land:tyAt(b + DY[2 * k] + (DX[2 * k] + a) * N)
							if nbr ~= T_WATER then
								local vi = va * HP + vb
								local v = land:h(vi)
								local w = land:h((RA[k + 1] + a) * HP + RB[k + 1] + b)
								if v > 3 and v == w then
									if v == 4 then
										land:setH(vi, 3)
									else
										local up = rng:below(2) ~= 0
										land:setH(vi, up and v + 1 or v - 1)
									end
								end
							end
						end
					end
				end
			end
		end

		-- the clubhouse: a random spot in the middle on plain ground where its 4 x 4 footprint fits
		local csize = kindSize(K_CLUBHOUSE)
		local ca, cb
		tries = 0
		while true do
			while true do
				ca = rng:below(17) + 15
				cb = rng:below(17) + 15
				tries = tries + 1
				if land.ty[idx(ca, cb)] == base or tries > TRIES then break end
			end
			if land:fits(ca, cb, csize, K_CLUBHOUSE, theme) or tries > TRIES then break end
		end
		local club = land:place(rng, ca, cb, K_CLUBHOUSE, 0x60, theme)
		land.objects[club + 1].flags = bor(land.objects[club + 1].flags, 0x40)
		land.view = { ca + 6, cb - 4 }
		land.clubhouse = { ca, cb }
		local ci = idx(ca, cb)
		land.flags[ci] = band(land.flags[ci], bnot(F_PATH)) % 65536

		-- the property's own feature
		local freeBuilding = ({ [2] = 0xd, [4] = 9, [9] = 6, [11] = 0xe, [14] = 8 })[prop]
		if prop == 0 or prop == 10 then
			local count
			count, tries = 0, 0
			while count < 16 and tries < TRIES do
				tries = tries + 1
				local a = rng:below(size - 4) + 2
				local b = rng:below(size - 4) + 2
				if not land:blocked(a, b) then
					local i = idx(a, b)
					local t = land.ty[i]
					if t ~= T_HOME_SITE and t ~= T_BUILDING and t ~= T_WATER and band(land.flags[i], F_FOOTPRINT) == 0 then
						land.flags[i] = bor(land.flags[i], F_SPOT)
						land.ty[i] = prop == 0 and T_BRUSH or T_ROUGH
						count = count + 1
					end
				end
			end
		elseif prop == 1 then
			for _ = 1, max(0, 8 - difficulty) do
				local i
				tries = 0
				repeat
					local r1 = rng:below(30)
					local r2 = rng:below(30)
					i = r2 + (r1 + 10) * size
					tries = tries + 1
				until land.ty[i] == T_WATER or tries > TRIES
				land.flags[i] = bor(land.flags[i], F_SPOT)
			end
		elseif prop == 5 or prop == 6 or prop == 8 or prop == 12 or prop == 13 or prop == 15 then
			tries = 0
			repeat
				local r1 = rng:below(size - 10)
				local r2 = rng:below(size - 10)
				tries = tries + 1
			until land:fits(r1 + 3, r2 + 3, 5, K_CLUBHOUSE, theme) or tries > TRIES
			for n = 0, max(0, 8 - difficulty) - 1 do
				rng:below(7)
				rng:below(7)
				local r1 = rng:below(size - 10)
				local a = r1 + 5
				local r2 = rng:below(size - 10)
				local b = r2 + 5
				if land:fits(r1 + 4, r2 + 4, 3, 7, theme) and land.ty[idx(a, b)] ~= T_WATER then
					landmark(land, rng, prop, n, a, b, theme)
				end
			end
		elseif prop == 7 then
			for n = 0, 1 do
				local r = rng:below(10)
				local a = n == 0 and size / 2 - r or size / 2 + r
				local b = 0
				while (land.ty[idx(a, b)] == T_WATER or land.ty[idx(a, b)] == T_OUT) and b < size - 2 do b = b + 1 end
				local o = land.objects[land:place(rng, a, b, K_LANDMARK, 0, theme) + 1]
				o.sub = rng:below(2) ~= 0 and 7 or 13
				local hi = b + a * HP
				land.height[hi] = (land.height[hi] + 2) % 256
			end
		end
		if freeBuilding then
			-- beside the clubhouse, with a short path to it; fixed, on the side whose lot is all on the owned land (#125)
			local past
			if fixes and rec.coast ~= 2 then
				local m = ownedMargin(slot, size)
				local lo = rec.coast == 0 and m or 0
				local function owned(a, b) return a >= m and a < size - m and b >= lo and b < size - m end
				local function fitsAt(b0)
					for r = 0, 3 do for c = 0, 3 do if not owned(ca - 1 + r, b0 + c) then return false end end end
					return true
				end
				past = not fitsAt(cb + 4) and fitsAt(cb - 5)
			else
				past = land:blocked(ca, cb + 5)
			end
			if not past then
				land:place(rng, ca - 1, cb + 4, freeBuilding, 0, theme)
				for k = 2, 4 do land:flagsOr(ci + k, F_PATH) end
			else
				land:place(rng, ca - 1, cb - 5, freeBuilding, 0, theme)
				for k = 1, 3 do land:flagsOr(ci - k, F_PATH) end
			end
			if prop == 4 or prop == 3 then
				local a, b
				tries = 0
				repeat
					a = rng:below(size - 10) + 5
					b = rng:below(size - 10) + 5
					tries = tries + 1
				until land:fits(a, b, 2, 4, theme) or tries > TRIES
				local o = land.objects[land:place(rng, a, b, K_LANDMARK, 0, theme) + 1]
				o.sub = 0xe
			end
		end

		-- obstacles, one per difficulty step, on plain ground; ringed with brush in the desert
		for _ = 1, max(0, difficulty) do
			local a, b, i
			tries = 0
			repeat
				a = rng:below(size - 11) + 5
				b = rng:below(size - 11) + 5
				i = idx(a, b)
				tries = tries + 1
			until land.ty[i] == base or tries > TRIES
			local o = land.objects[land:place(rng, a, b, K_LANDMARK, 0, theme) + 1]
			o.sub = theme == 0 and 0x10 or (theme == 1 and 0x12 or 0x11)
			local dir = rng:below(4)
			land.flags[i] = bor(land.flags[i], F_OBSTACLE)
			o.dir = dir
			if desert then
				for k = 0, 7 do
					local j = b + DY[k] + (DX[k] + a) * N
					if j >= 0 and j < NN then land.ty[j] = T_BRUSH end
				end
			end
		end

		-- the owned land; the rest is out of bounds (or sea round an island)
		local m = ownedMargin(slot, size)
		land.margin = m
		land.original = {}
		for i = 0, NN - 1 do land.original[i] = land.ty[i] end
		local cut = {}
		local function unown(a, b)
			land:unown(a, b)
			cut[idx(a, b)] = true
		end
		if rec.coast ~= 2 then
			for i = 0, m - 1 do
				for j = 0, N - 1 do
					unown(i, j)
					if rec.coast == 0 then unown(j, i) end
					unown(j, size - 1 - i)
					unown(size - 1 - i, j)
				end
			end
		else
			for row = 0, N - 1 do
				local s = rng:below(3)
				local w = clampExe(abs(row - size / 2), 8, size) + (m - 1) - 11 + s
				for j = 0, max(0, w) - 1 do
					if j >= N then break end
					unown(j, row)
					unown(row, j)
					unown(row, size - 1 - j)
					unown(size - 1 - j, row)
				end
			end
		end
		if fixes then
			if rec.coast == 1 then
				for a = 0, N - 1 do
					cut[idx(a, 0)] = true
					land.original[idx(a, 0)] = T_OUT
				end
			end
			land:clearCut(cut)
		end
		land:waterDepth()
		return land
	end

	------------------------------------------------------------------------------------------------ to the renderer

	function L.themeName(land) return THEME_NAMES[land:record().theme] end

	-- the renderer's Terrain: tiles (x = a, y = b), corner levels above sea level (our corner (cx, cy) is the exe's vertex
	-- (cx, cy - 1)), water depth and a green's tricky bit in the variation byte, random looks A..E
	function Land:toTerrain()
		local t = T.new(N, N, T_ROUGH)
		t.desert = self:record().theme == 1
		t.land = self
		local seed = Rng.new(bit.bxor(0x9e3779b9, self.slot.property) % 4294967296)
		t.pathKind = {}
		for a = 0, N - 1 do
			for b = 0, N - 1 do
				local i = idx(a, b)
				local o = t:index(a, b)
				t.ty[o] = self.ty[i]
				t.set[o] = seed:range(5)
				if self.ty[i] == T_WATER or self.ty[i] == T_GREEN then t.variation[o] = self.var[i] else t.variation[o] = 0 end
				local building = self.ty[i] == T_BUILDING or self.ty[i] == T_HOME_SITE
				t.pathKind[o] = (band(self.flags[i], F_PATH) ~= 0 and not building) and 1 or 0
			end
		end
		for cy = 0, N do
			for cx = 0, N do
				local v = self:corner(cx, cy - 1) - 3
				t.corner[cy * (N + 1) + cx + 1] = max(0, min(24, v))
			end
		end
		self:lotsTo(t)
		t.clubhouseX, t.clubhouseY = self.clubhouse[1] + 2, self.clubhouse[2] + 2
		return t
	end

	-- the lots that keep open ground (putting greens, driving ranges), so they keep their border against the same ground
	function Land:lotsTo(t)
		t.lot = {}
		for _, o in ipairs(self.objects) do
			if o.kind == K_PUTTING_GREEN or o.kind == K_DRIVING_RANGE then
				local s = self:footprintSize(o)
				for a = o.a, o.a + s - 1 do
					for b = o.b, o.b + s - 1 do
						if t:inside(a, b) then t.lot[t:index(a, b)] = o.kind end
					end
				end
			end
		end
	end

	-- writes the land's tiles and corners inside a rectangle back to the terrain (after an edit)
	function Land:writeArea(t, a0, b0, a1, b1)
		for a = max(0, a0), min(N - 1, a1) do
			for b = max(0, b0), min(N - 1, b1) do
				local o = t:index(a, b)
				t.ty[o] = self.ty[idx(a, b)]
				if t.ty[o] == T_WATER then t.variation[o] = self.var[idx(a, b)] end
				local building = t.ty[o] == T_BUILDING or t.ty[o] == T_HOME_SITE
				t.pathKind[o] = (band(self.flags[idx(a, b)], F_PATH) ~= 0 and not building) and 1 or 0
			end
		end
		for cx = max(0, a0), min(N, a1 + 1) do
			for cy = max(0, b0), min(N, b1 + 1) do
				local v = self:corner(cx, cy - 1) - 3
				t.corner[cy * (N + 1) + cx + 1] = max(0, min(24, v))
			end
		end
		self:lotsTo(t)
		t:dirty()
	end

	-- a whole new game's land: the clock seeds the RNG, the noise is drawn first, then the offer, then the chosen slot's land
	function L.newGame(opts)
		opts = opts or {}
		local rng = ExeRng.fromClock(opts.clock or 1)
		local noise = Noise.new(rng)
		local offer = L.dealOffer(rng, opts.sandbox)
		local slotIndex = opts.slot or 0
		local land = L.generate(slotIndex, offer[slotIndex], opts.difficulty or 1, opts.sandbox, rng, noise, opts)
		land.noise = noise
		return land, offer, rng
	end

	return L
end
