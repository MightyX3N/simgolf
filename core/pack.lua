-- Asset packs: finds installed packs, reads their manifests (written by tools/export-pack) and answers lookups with a
-- per-file fallback: whatever the active pack lacks comes from the free pack.
--
-- Platform functions used: listPacks(), findPackFiles(id, subfolder), loadPackFile(id, relative path).

return function(Game)
	local T = Game.require("terrain")
	local P = Game.Platform
	local floor = math.floor

	local Packs = { loaded = {}, activeId = "free", baseId = "free" }

	local function loadManifest(id)
		local info = P.loadPackFile(id, "info.lua")
		if type(info) ~= "table" then return nil end
		local pack = { id = id, info = info, sprites = {}, sounds = {}, themes = {} }

		local layout = P.loadPackFile(id, "terrain.lua")
		if type(layout) == "table" then
			pack.terrain = layout
			for _, file in ipairs(P.findPackFiles(id, "terrain")) do
				local theme = file:match("^(.-)%.lua$")
				local t = theme and P.loadPackFile(id, "terrain/" .. file)
				if type(t) == "table" then pack.themes[theme] = t end
			end
		end

		for _, file in ipairs(P.findPackFiles(id, "sprites")) do
			local part = P.loadPackFile(id, "sprites/" .. file)
			if type(part) == "table" then
				for key, s in pairs(part) do pack.sprites[key] = s end
			end
		end

		local sounds = P.loadPackFile(id, "sounds.lua")
		if type(sounds) == "table" then pack.sounds = sounds end
		return pack
	end

	function Packs.get(id)
		local pack = Packs.loaded[id]
		if pack == nil then
			pack = loadManifest(id) or false
			Packs.loaded[id] = pack
			if pack then
				P.log(("pack %s: %s"):format(id, tostring(pack.info.name)))
			else
				P.log("pack " .. id .. " not found or has no info.lua")
			end
		end
		return pack or nil
	end

	function Packs.list()
		return P.listPacks()
	end

	function Packs.setActive(id)
		if Packs.get(id) then Packs.activeId = id end
		Packs.catalogs = {}
	end

	-- the packs to search, active first, then the free base pack
	local function chain()
		local a, b = Packs.get(Packs.activeId), Packs.get(Packs.baseId)
		if a and b and a ~= b then return { a, b } end
		return { a or b }
	end

	------------------------------------------------------------------------------------------------ sprites

	-- sprite entry for a key such as "trees/treemaplelarge", plus the pack it comes from
	function Packs.sprite(key)
		for _, pack in ipairs(chain()) do
			local s = pack.sprites[key]
			if s then return s, pack end
		end
	end

	-- image path of a sprite sheet, for Platform.loadImage
	function Packs.spriteImage(key)
		local s, pack = Packs.sprite(key)
		if s then return pack.id .. "/" .. s.file, s end
	end

	------------------------------------------------------------------------------------------------ terrain

	-- A theme's texture catalog: files[type][set][variation] = atlas cell, built from the manifest's texture names
	-- ("<typename><set letter><0001..0009>"; tees: "teea0001".."teea0025" are 25 sets of one picture).
	local function buildCatalog(pack, theme)
		local th = pack.themes[theme]
		if not (th and pack.terrain) then return nil end
		local cellOf = {}
		for i, name in ipairs(th.names) do cellOf[name] = i - 1 end

		local files = {}
		for ty = 0, T.TYPE_COUNT - 1 do
			local name = T.NAMES[ty]
			local sets = {}
			if name then
				local lower = name:lower()
				if ty == T.TEE then
					for v = 1, 25 do
						local c = cellOf[("%sa%04d"):format(lower, v)]
						if not c then break end
						sets[#sets + 1] = { [0] = c }
					end
				else
					for letter in ("abcde"):gmatch(".") do
						local vars, have = {}, false
						for v = 1, 9 do
							local c = cellOf[("%s%s%04d"):format(lower, letter, v)]
							if c then vars[v - 1], have = c, true end
						end
						if have then sets[#sets + 1] = vars end
					end
				end
			end
			files[ty] = sets
		end

		local L = pack.terrain
		return {
			pack = pack,
			image = pack.id .. "/" .. th.atlas,
			lighting = th.lighting,
			files = files,
			atlasSize = L.atlasSize, cell = L.cell, cols = L.cols, tex = L.tex,
		}
	end

	-- missing types fall back to something that looks close (OpenSGolf's TextureCatalog::pick)
	local FALLBACK = {
		[T.OVERGROWTH2] = T.OVERGROWTH, [T.WATER_SHALLOW_DESERT] = T.WATER_SHALLOW, [T.TEE] = T.FAIRWAY,
		[T.TRICKY_GREEN] = T.PUTTING_GREEN, [T.FIRM_FAIRWAY] = T.FAIRWAY, [T.GRASSY_SAND] = T.ROUGH, [T.MARSH] = T.ROUGH,
		[T.BUILDING] = T.ROCK, [T.OVERGROWTH] = T.BRUSH, [T.BRUSH] = T.ROUGH, [T.WOODS] = T.BRUSH,
		[T.POT_SAND_BUNKER] = T.GRASSY_SAND, [T.SAND_BUNKER1] = T.POT_SAND_BUNKER, [T.ROUGH] = T.FAIRWAY,
	}

	-- atlas cell for a texture type, set and variation, or nil
	local function pick(cat, ty, set, variation)
		for _ = 1, 6 do
			local sets = cat.files[ty]
			if sets and #sets > 0 then
				local vars = sets[(set % #sets) + 1]
				local c = vars[variation % 9]
				if c then return c end
				for v = 0, 8 do
					if vars[v] then return vars[v] end -- variation missing: the first that exists
				end
			end
			ty = FALLBACK[ty]
			if not ty then break end
		end
	end

	-- Terrain texture lookup for a theme ("parkland", "desert", "tropical", "links"): returns an object with
	--   image                       atlas image path for Platform.loadImage
	--   lighting                    { ambient, diffuse, specular } 0..255 or nil
	--   uv(ty, set, variation, u, v) -> atlas u, v (0..1) for texture coordinates u, v (0..1, top-down) in that texture
	function Packs.terrain(theme)
		Packs.catalogs = Packs.catalogs or {}
		local cat = Packs.catalogs[theme]
		if cat == nil then
			cat = false
			for _, pack in ipairs(chain()) do
				local c = buildCatalog(pack, theme)
				if c then cat = c break end
			end
			Packs.catalogs[theme] = cat
		end
		if not cat then return nil end

		local cache = {}
		local size, cell, cols, tex = cat.atlasSize, cat.cell, cat.cols, cat.tex
		cat.cellFor = function(ty, set, variation)
			local key = ty * 4096 + set * 16 + variation
			local c = cache[key]
			if c == nil then
				c = pick(cat, ty, set, variation) or false
				cache[key] = c
			end
			return c or nil
		end
		cat.uv = function(c, u, v)
			local x0 = (c % cols) * cell + 1
			local y0 = floor(c / cols) * cell + 1
			return (x0 + u * tex) / size, (y0 + v * tex) / size
		end
		return cat
	end

	return Packs
end
