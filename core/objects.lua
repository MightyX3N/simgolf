-- What the course draws for objects and trees: the exe's sprite ids and the files each theme loads for them, the layers of
-- every building, the driving range's pieces and the trees of tree tiles. Ported from OpenSGolf's sg-core objects.rs and
-- decor.rs (v0.6.10). Sprite keys are the pack's (lower-case paths without ".flc"). Themes are the exe's: 0 Parkland,
-- 1 Desert, 2 Tropical, 3 Links. Palettes (the exe's recolouring of trees and landmarks) are not drawn yet.

return function(Game)
	local bit = bit or require("bit")
	local band, rshift, lshift = bit.band, bit.rshift, bit.lshift
	local floor = math.floor

	local O = {}

	-- building sprites 0x1b6..0x1fb and the TV art, by exe theme (false where a theme loads nothing)
	O.SPRITES = {
		[0x246] = { "tees/tvtowerstatic", "tees/tvtowerstatic", "tees/tvtowerstatic", "tees/tvtowerstatic" },
		[0x247] = { "tees/tvtoweranim", "tees/tvtoweranim", "tees/tvtoweranim", "tees/tvtoweranim" },
		[0x248] = { "tees/tvcommentstatic", "tees/tvcommentstatic", "tees/tvcommentstatic", "tees/tvcommentstatic" },
		[0x249] = { "tees/tvcommentanim", "tees/tvcommentanim", "tees/tvcommentanim", "tees/tvcommentanim" },
		[0x1b6] = { "bldgs/park/builddrl1", "bldgs/desert/dbuilddrl1", "bldgs/tropical/tropdrivingrshopl1", "bldgs/links/dr_shop" },
		[0x1b7] = { "bldgs/park/builddrl2", "bldgs/desert/desdrl2house", "bldgs/tropical/tropdrivingrshopl2", "bldgs/links/drl2_shop" },
		[0x1b8] = { "bldgs/park/plat_topdrl1", "bldgs/desert/dplatdrl1", "bldgs/tropical/tropdrivingrl1plattop", "bldgs/links/dr_platform" },
		[0x1b9] = { "bldgs/park/plat_basedrl1", "bldgs/desert/dplatdrl1base", "bldgs/tropical/tropdrivingrl1platbase", "bldgs/links/dr_platform_dirt" },
		[0x1ba] = { "bldgs/park/100drl1", "bldgs/desert/d100drl1", "bldgs/tropical/tropdrivingr100l1", "bldgs/links/dr_100sign" },
		[0x1bb] = { "bldgs/park/200drl1", "bldgs/desert/d200drl1", "bldgs/tropical/tropdrivingr200l1", "bldgs/links/dr_200sign" },
		[0x1bc] = { "bldgs/park/300drl1", "bldgs/desert/d300drl1", "bldgs/tropical/tropdrivingr300l1", "bldgs/links/dr_300sign" },
		[0x1bd] = { "bldgs/park/flag_drl1", "bldgs/desert/dflagdrl1", "bldgs/tropical/tropdrivingrflagl1", "bldgs/links/dr_flag" },
		[0x1be] = { "bldgs/park/wall_drl1", "bldgs/desert/dwalldrl1", "bldgs/tropical/tropdrivingrfencel1", "bldgs/links/rockwall01" },
		[0x1bf] = { "bldgs/park/builddrl2_anim", false, "bldgs/tropical/tropdrivingrshopl2_anim", "bldgs/links/drl2_shop_anim" },
		[0x1c0] = { "bldgs/park/plat_topdrl2", "bldgs/desert/desdrl2plattop", "bldgs/tropical/tropdrivingrl2plattop", "bldgs/links/drl2_platform" },
		[0x1c1] = { "bldgs/park/plat_basedrl2", "bldgs/desert/desdrl2plat", "bldgs/tropical/tropdrivingrl2platbase", "bldgs/links/drl2_platform_base" },
		[0x1c2] = { "bldgs/park/cartl1", "bldgs/desert/descartl1", "bldgs/tropical/tropcartl1", "bldgs/links/cart_garagel1" },
		[0x1c3] = { "bldgs/park/cartl2", "bldgs/desert/descartl2", "bldgs/tropical/tropcartl2", "bldgs/links/cart_garagel2" },
		[0x1c4] = { "bldgs/park/cartl1_anim", false, false, false },
		[0x1c5] = { "bldgs/park/cartl1_base", "bldgs/desert/descartl1base", "bldgs/tropical/tropcartl1base", "bldgs/links/cart_garagel1_dirt" },
		[0x1c6] = { "bldgs/park/cartl2_base", "bldgs/desert/descartl2base", "bldgs/tropical/tropcartl2_base", "bldgs/links/cart_garagel2_dirt" },
		[0x1c7] = { "bldgs/park/cartl2_anim", "bldgs/desert/descartl2anim", false, false },
		[0x1ca] = { "homes/regular/parkland/a/parkhousea", "homes/regular/desert/a/deshousea", "homes/regular/tropical/b/trophouseb", "homes/regular/links/b/linkshouseb" },
		[0x1c8] = { "bldgs/park/sign", "bldgs/desert/dessign", "bldgs/tropical/tropsign", "bldgs/links/sign_links" },
		[0x1c9] = { "bldgs/park/houseconst", "bldgs/desert/deshouseconst", "bldgs/tropical/trophouseconst", "bldgs/links/houseconst_links" },
		[0x1ce] = { "bldgs/park/marl1", "bldgs/desert/helil1", "bldgs/tropical/tropmarl1", "bldgs/links/churchl1" },
		[0x1cf] = { "bldgs/park/marl2", "bldgs/desert/hell2", "bldgs/tropical/tropmarinal2", "bldgs/links/churchl2" },
		[0x1d0] = { "bldgs/park/parksnackl2_anim", "bldgs/desert/helanimlites", false, false },
		[0x1d1] = { "bldgs/park/marl1_wateranim", "bldgs/desert/helil1_base", "bldgs/tropical/tropmarl1_underwater", "bldgs/links/churchl1_dirt" },
		[0x1d2] = { "bldgs/park/marl2_wateranim", "bldgs/desert/hell2base", "bldgs/tropical/tropmarinal2_underwater", "bldgs/links/churchl2_dirt" },
		[0x1d3] = { "bldgs/park/parksnackl1_anim", "bldgs/desert/helanimelev", false, false },
		[0x1d4] = { "bldgs/park/tenl1", "bldgs/desert/spal1", "bldgs/tropical/tropswiml1", "bldgs/links/stablel1" },
		[0x1d5] = { "bldgs/park/tenl2", "bldgs/desert/spal2", "bldgs/tropical/tropswiml2", "bldgs/links/stablel2" },
		[0x1d7] = { false, "bldgs/desert/spal1_base", "bldgs/tropical/tropswiml1anim", "bldgs/links/stablel1_dirt" },
		[0x1d8] = { false, false, "bldgs/tropical/tropswiml2_anim", "bldgs/links/stablel2_dirt" },
		[0x1d9] = { false, "bldgs/desert/descasl2wheel", false, "bldgs/links/stablel2_anim" },
		[0x1da] = { "bldgs/park/airl1", "bldgs/desert/descasl1", "bldgs/tropical/tropthemel1", "bldgs/links/castlel1" },
		[0x1db] = { "bldgs/park/airl2", "bldgs/desert/descasl2", "bldgs/tropical/tropthemel2", "bldgs/links/castlel2" },
		[0x1dc] = { "bldgs/park/airl1_anim", "bldgs/desert/descasl1anim", "bldgs/tropical/tropthemel1_boatanim", "bldgs/links/castlel2_anim" },
		[0x1dd] = { "bldgs/park/airl1_base", "bldgs/desert/descasl1base", "bldgs/tropical/tropthemel2_loopanim", "bldgs/links/castlel1_dirt" },
		[0x1de] = { "bldgs/park/airl2_base", "bldgs/desert/descasl2base", "bldgs/tropical/tropthemel1_cannonanim", "bldgs/links/castlel2_dirt" },
		[0x1df] = { "bldgs/park/airl2_anim", "bldgs/desert/descasl2status", "bldgs/tropical/tropthemel2_sprayanim", false },
		[0x1e0] = { "bldgs/park/prosl1", "bldgs/desert/dprol1", "bldgs/tropical/tropproshopl1", "bldgs/links/pro_shop" },
		[0x1e1] = { "bldgs/park/prosl2", "bldgs/desert/desprol2", "bldgs/tropical/tropproshopl2", "bldgs/links/links_proshopl2" },
		[0x1e2] = { "bldgs/park/prosl2_anim01", false, false, "bldgs/links/pro_shop_anim" },
		[0x1e3] = { "bldgs/park/prosl1_base", "bldgs/desert/dprol1base", "bldgs/tropical/tropproshopl1_base", "bldgs/links/pro_shop_dirt" },
		[0x1e4] = { false, "bldgs/desert/desprol2anim", "bldgs/tropical/tropproshopl1_anim", "bldgs/links/links_proshopl2_dirt" },
		[0x1e5] = { "bldgs/park/prosl2_anim02", false, false, "bldgs/links/links_proshopl2_anim" },
		[0x1e6] = { "bldgs/park/hotell1", "bldgs/desert/deshotell1", "bldgs/tropical/trophotell1", "bldgs/links/hotell1" },
		[0x1e7] = { "bldgs/park/hotell2", "bldgs/desert/deshol2", "bldgs/tropical/trophotell2", "bldgs/links/hotell2" },
		[0x1e8] = { "bldgs/park/hotell1_anim", "bldgs/desert/deshotell1anim", false, "bldgs/links/hotell1_anim" },
		[0x1e9] = { "bldgs/park/hotell1_base", "bldgs/desert/deshotell1base", "bldgs/tropical/trophotell1base", "bldgs/links/hotell1_dirt" },
		[0x1ea] = { "bldgs/park/hotell2_base", "bldgs/desert/deshol2status", "bldgs/tropical/trophotell2_base", "bldgs/links/hotell2_dirt" },
		[0x1eb] = { "bldgs/park/hotell2_anim", "bldgs/desert/deshol2elev", "bldgs/tropical/trophotell2_anim", "bldgs/links/hotell2_anim" },
		[0x1ec] = { "bldgs/park/parksnackl1", "bldgs/desert/dessnack", "bldgs/tropical/tropsnackl1", "bldgs/links/pub_sq" },
		[0x1ed] = { "bldgs/park/parksnackl1_base", "bldgs/desert/dessnackbase", false, "bldgs/links/pub_sq_dirt" },
		[0x1ee] = { "bldgs/park/parksnackl2", "bldgs/desert/dessnackl2", "bldgs/tropical/tropsnackl2", "bldgs/links/publ2" },
		[0x1ef] = { "bldgs/park/parksnackl2_base", false, "bldgs/tropical/tropsnackl2_anim", "bldgs/links/publ2_dirt" },
		[0x1f0] = { "bldgs/park/puttl1", "bldgs/desert/dputtl1", "bldgs/tropical/tropputtinggl1", "bldgs/links/pg_hutl1" },
		[0x1f1] = { "bldgs/park/puttl1", "bldgs/desert/dputtl1base", "bldgs/tropical/tropputtinggl1", "bldgs/links/pg_hutl1_dirt" },
		[0x1f2] = { "bldgs/park/shortflagl1", "bldgs/desert/dshortflagl1", "bldgs/tropical/tropputtinggflagl1", "bldgs/links/pg_pflag" },
		[0x1f3] = { "bldgs/park/puttl2", "bldgs/desert/desputtl2", "bldgs/tropical/tropputtinggl2", "bldgs/links/pg_hutl2" },
		[0x1f4] = { "bldgs/park/puttl2_anim", "bldgs/desert/desputtl2", "bldgs/tropical/tropputtinggl2_anim", "bldgs/links/pg_hutl2_dirt" },
		[0x1f5] = { "bldgs/park/puttscenic", "bldgs/desert/desputtl2scenic", "bldgs/tropical/tropputtinggl2_scenic", "bldgs/links/pg_scenicl2" },
		[0x1f6] = { "bldgs/park/clubl1", "bldgs/desert/desclubl1", "bldgs/tropical/tropclubl1", "bldgs/links/clubl1" },
		[0x1f7] = { "bldgs/park/clubl2", "bldgs/desert/desclubl2", "bldgs/tropical/tropclubl2", "bldgs/links/clubl2" },
		[0x1f8] = { "bldgs/park/clubl2_base", false, "bldgs/tropical/tropclubl2_base", "bldgs/links/clubl2_dirt" },
		[0x1f9] = { "bldgs/park/clubl1_base", "bldgs/desert/desclubl1base", false, "bldgs/links/clubl1_dirt" },
		[0x1fa] = { "bldgs/park/clubl1_anim", false, "bldgs/tropical/tropclubl1anim", "bldgs/links/clubl1_anim" },
		[0x1fb] = { "bldgs/park/clubl2_anim", false, "bldgs/tropical/tropclubl2_anim", "bldgs/links/clubl2_anim" },
	}

	function O.sprite(id, theme)
		local s = O.SPRITES[id]
		if not s then return nil end
		return s[math.min(theme, 3) + 1] or nil
	end

	O.LANDMARKS = {
		"landmarks/sundial", "landmarks/barn", "landmarks/civilwarcannon", "landmarks/stone two", "landmarks/wmilla",
		"landmarks/parklandrock", "landmarks/civilwarstatue", "landmarks/lighthousec", "landmarks/buddha", "landmarks/windmill",
		"landmarks/equestrian", "landmarks/easter", "landmarks/pagoda", "landmarks/lighthouseb", "landmarks/chinesehouse",
		"landmarks/tarpit", "landmarks/wtow2", "landmarks/radio tower", "landmarks/red oil pump",
	}

	function O.landmark(t)
		return O.LANDMARKS[t + 1]
	end

	-- the layers of a building of kind `kind` at upgrade `level` (building_layers): { key, flat, animated }
	function O.layers(kind, level, theme)
		local v = {}
		local l = math.min(level, 1)
		local function add(id, flat, animated)
			local f = O.sprite(id, theme)
			if f then v[#v + 1] = { key = f, flat = flat, animated = animated } end
		end
		if kind == 6 then
			local k = l == 1 and 3 or 0
			add(0x1f1 + k, theme == 1 or theme == 3, true)
			add(0x1f0 + k, false, false)
			if l == 1 then add(0x1f5, false, true) end
		elseif kind == 7 then
			if l == 0 then
				if theme ~= 2 then add(0x1ed, true, false) end
				add(0x1ec, false, true)
				if theme == 0 then add(0x1d3, false, true) end
			else
				if theme ~= 2 and theme ~= 1 then add(0x1ef, true, false) end
				add(0x1ee, false, true)
				if theme == 2 then add(0x1ef, false, true) end
				if theme == 0 then add(0x1d0, false, true) end
			end
		elseif kind == 8 then
			if theme ~= 2 or l == 0 then add(0x1e3 + l, not (theme == 2 and l ~= 0), true) end
			add(0x1e0 + l, false, true)
		elseif kind == 9 then
			if theme ~= 0 and theme ~= 1 then add(0x1d7 + l, theme ~= 2, true) end
			add(0x1d4 + l, false, true)
		elseif kind == 11 then
			add(0x1c5 + l, true, false); add(0x1c2 + l, false, false)
		elseif kind == 12 then
			add(0x1d1 + l, true, true); add(0x1ce + l, false, false)
		elseif kind == 13 then
			add(0x1e9 + l, true, false); add(0x1e6 + l, false, false)
		elseif kind == 14 then
			add(0x1dd + l, true, false); add(0x1da + l, false, false)
		elseif kind == 15 then
			local skipBase = (theme == 2 and l == 0) or (theme == 1 and l == 1)
			if not skipBase then add(0x1f9 - l, true, false) end
			add(0x1f6 + l, false, false)
			if theme ~= 1 then add(0x1fa + l, false, true) end
		elseif kind == 17 then
			add(0x246, false, false); add(0x247, false, true)
		elseif kind == 18 then
			add(0x248, false, false); add(0x249, false, true)
		end
		return v
	end

	-- the driving range's pieces (driving_range): { key, ua, ub (position in 1/1024 tiles from the range's corner), flat,
	-- animated, phase, view }; green(i, j) says whether the range's tile i, j is a target green
	function O.drivingRange(level, theme, green)
		local l = math.min(level, 1)
		local n = 5 + l
		local v = {}
		local function put(id, ua, ub, flat, animated, phase, view)
			local f = O.sprite(id, theme)
			if f then v[#v + 1] = { key = f, ua = ua, ub = ub, flat = flat, animated = animated, phase = phase or 0, view = view } end
		end
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				local ua, ub = i * 1024 + 512, j * 1024 + 512
				local skip = false
				if i == 0 then
					if j == 0 then
						put(0x1b6 + l, ua, ub, false, false)
						if l ~= 0 and theme ~= 1 then put(0x1bf, ua, ub, false, true) end
					else
						local k = l ~= 0 and 8 or 0
						put(0x1b8 + k, ua, ub, false, false)
						put(0x1b9 + k, ua, ub, true, false)
					end
				elseif j == 0 or j == l + 4 then
					local y = j == 0 and 0 or (5 + l) * 1024
					put(0x1be, i * 1024 + 512, y, false, false)
					ua, ub = i * 1024, y
					put(0x1be, ua, ub, false, false)
				end
				if green(i, j) then
					put(0x1bd, ua, ub, false, true, i + j, 0)
				elseif j * 2 - 2 == i then
					local sign = (i == 2 and 0x1ba) or (i == 4 and 0x1bb) or (i == 6 and 0x1bc)
					if sign then put(sign, ua, ub, false, false) end
				end
			end
		end
		return v
	end

	------------------------------------------------------------------------------------------------ trees (decor.rs)

	local TREE_FILES = {
		[0x192] = { "trees/treepinesprucesm", "trees/desert/cactusa_sm", "trees/tropic/tree_cerc/cerc_small", "trees/links/linkspine_small" },
		[0x193] = { "trees/treepinesprucemed", "trees/desert/cactusa_md", "trees/tropic/tree_cerc/cerc_med", "trees/links/linkspine_med" },
		[0x194] = { "trees/treepinesprucelg", "trees/desert/cactusa_lg", "trees/tropic/tree_cerc/cerc_large", "trees/links/linkspine_tall" },
		[0x198] = { "trees/treepinefirsm", "trees/desert/cactusc_sm", "trees/tropic/tree_drac/drac_small", "trees/links/linkspine_small" },
		[0x199] = { "trees/treepinefirmed", "trees/desert/cactusc_md", "trees/tropic/tree_drac/drac_med", "trees/links/linkspine_med" },
		[0x19a] = { "trees/treepinefirlg", "trees/desert/cactusc_lg", "trees/tropic/tree_drac/drac_large", "trees/links/linkspine_tall" },
		[0x195] = { "trees/treepalmsm", "trees/desert/tallpalm_small", "trees/desert/tallpalm_small", "trees/links/scotspine_small" },
		[0x196] = { "trees/treepalmmed", "trees/desert/tallpalm_med", "trees/desert/tallpalm_med", "trees/links/scotspine_med" },
		[0x197] = { "trees/treepalmlg", "trees/desert/tallpalm_large", "trees/desert/tallpalm_large", "trees/links/scotspine_lg" },
		[0x19b] = { "trees/treemaplesmall", "trees/desert/joshuatree_sm", "trees/tropic/tropicalbrush_sm", "trees/treemaplesmall" },
		[0x19c] = { "trees/treemaplemedium", "trees/desert/joshuatree_md", "trees/tropic/tropicalbrush_med", "trees/treemaplemedium" },
		[0x19d] = { "trees/treemaplelarge", "trees/desert/joshuatree_lg", "trees/tropic/tropicalbrush_lg", "trees/treemaplelarge" },
		[0x131] = { "scenic/scenicelm", "scenic/scenicelm", "scenic/scenicelm", "scenic/scenicelm" },
		[0xf9] = { "trees/willowtree", "trees/willowtree", "trees/willowtree", "trees/willowtree" },
		[0x18d] = { "tees/teemarkerred_pop", "tees/teemarkerred_pop", "tees/teemarkerred_pop", "tees/teemarkerred_pop" },
		[0x18e] = { "tees/teemarkerwhite_pop", "tees/teemarkerwhite_pop", "tees/teemarkerwhite_pop", "tees/teemarkerwhite_pop" },
		[0x18f] = { "tees/teemarkerblue_pop", "tees/teemarkerblue_pop", "tees/teemarkerblue_pop", "tees/teemarkerblue_pop" },
		[0x185] = { "tees/flagpark_pop", "tees/flagdesert_pop", "tees/flagtrop_pop", "tees/flaglinks_pop" },
		[0x189] = { "tees/flagpark_open", "tees/flagdesert_open", "tees/flagtrop_open", "tees/flaglinks_open" },
	}

	function O.decorFile(id, theme)
		local f = TREE_FILES[id]
		return f and f[math.min(theme, 3) + 1]
	end

	local DX = { [0] = 0, 1, 1, 1, 0, -1, -1, -1 }
	local DY = { [0] = -1, -1, 0, 1, 1, 1, 0, -1 }
	O.DX, O.DY = DX, DY

	-- a screen offset in zoom units as tile offsets along a and b
	local function screen(dx, dy)
		return (dx / 8 - dy / 5) / 2, (dx / 8 + dy / 5) / 2
	end
	O.screenOffset = screen

	-- Rust's % on i32 (sign of the dividend)
	local function rem(a, b)
		local r = math.fmod(a, b)
		return r
	end

	-- the trees of a tile of type 13, 14 or 15 (decor::trees). tyAt(a, b) is the land's type (0x1f off the map), row(t)
	-- the terrain rule row, field(x, y) the land's height noise. Returns { id, frame (nil: grown), view, da, db }.
	function O.trees(tyAt, row, var, scenic, a, b, theme, grown, field)
		local own = tyAt(a, b)
		if row(own).class ~= 13 or own == 16 or scenic then return {} end
		local mask = 0
		for d = 0, 7 do mask = bit.bor(mask, lshift(1, band(tyAt(a + DX[d], b + DY[d]), 0x1f))) end
		local g0 = row(own).group
		local axes = 0
		for d = 0, 3 do
			local g1 = row(tyAt(a + DX[d], b + DY[d])).group
			local g2 = row(tyAt(a + DX[d + 4], b + DY[d + 4])).group
			if (g1 == g0) == (g2 == g0) then axes = axes + 1 end
		end
		local size = axes == 0 and 0 or (axes <= 2 and 1 or 2)
		local v = var
		local view = band(a - 2 * b, 3)
		local frame = (not grown) and 0 or nil
		local function single(id)
			local da, db = screen(rem(a + 3 * b, 5) - 2, 0)
			return { { id = id, frame = frame, view = view, da = da, db = db } }
		end
		local function pair(id)
			local z = 8
			local a1, b1 = screen(z / (band(a, 1) ~= 0 and 3 or 5), 0)
			local a2, b2 = screen(-z / (band(b, 1) ~= 0 and 3 or 5), -z / (band(a, 2) ~= 0 and 4 or -6))
			return { { id = id, frame = frame, view = view, da = a1, db = b1 }, { id = id, frame = frame, view = view, da = a2, db = b2 } }
		end
		if own == 13 then
			local id = 0x19b + size
			if v ~= 0 then id = 0x19b + v % 3 end
			if grown and band(mask, lshift(1, 13)) == 0 and (theme == 0 or theme == 3) then
				return { { id = 0x131, view = view, da = 0, db = 0 } }
			end
			return single(id)
		elseif own == 14 then
			local id = 0x192 + size
			local n = field(lshift(a, 8), lshift(b, 8))
			local q = n / 13
			q = q < 0 and math.ceil(q) or floor(q)
			if band(q, 4) ~= 0 then id = id + 6 end
			if v ~= 0 then
				id = 0x192 + v % 3
				if band(floor(v / 3), 1) ~= 0 then id = id + 6 end
			end
			if id == 0x192 then return pair(id) end
			return single(id)
		else
			local id = 0x195 + size
			if v ~= 0 then id = 0x195 + v % 3 end
			if id == 0x195 then return pair(id) end
			return single(id)
		end
	end

	-- the two tee markers of an open hole's tee (decor::tee_markers): red for par 3, white for 4, blue above
	function O.teeMarkers(par, facing)
		local id = 0x18d + math.max(0, math.min(2, par - 3))
		local e = band(facing + 1, 7)
		local dx, dy = DX[e], DY[e]
		local sx, sy = 5, 3
		if band(e, 1) ~= 0 then sx, sy = 4, 2 end
		local a1, b1 = screen(sx * dx, sy * dy)
		local a2, b2 = screen(-sx * dx, -sy * dy)
		return { { id = id, view = 0, da = a1, db = b1 }, { id = id, view = 0, da = a2, db = b2 } }
	end

	return O
end
