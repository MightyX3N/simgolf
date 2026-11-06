-- The client application: a new game on a generated property, the course view and the course tools (terrain painting,
-- elevation, buildings, holes) with the top bar, the tool rail and the build drawer.
--
-- The platform layer calls:
--   App:init(opts)                    once, after the core has booted; opts: seed, slot, sandbox, difficulty, pack
--   App:update(dt)                    every frame, dt in seconds
--   App:draw(screenW, screenH)        every frame
--   App:keyPressed(key)               key names: "a".."z", "0".."9", "up", "down", "left", "right", "escape", "space", ...
--   App:mousePressed(x, y, button)    buttons: "left", "right", "middle"
--   App:mouseReleased(x, y, button)
--   App:mouseMoved(x, y)
--   App:wheel(dy, sw, sh)             positive: away from the user (zoom in)

return function(Game)
	local T = Game.require("terrain")
	local L = Game.require("land")
	local Course = Game.require("course")
	local O = Game.require("objects")
	local Packs = Game.require("pack")
	local Camera = Game.require("client/camera")
	local TerrainView = Game.require("client/terrain_view")
	local Sprites = Game.require("client/sprites")
	local Props = Game.require("client/props")
	local UI = Game.require("client/ui")
	local P = Game.Platform
	local floor, min, max, abs = math.floor, math.min, math.max, math.abs
	local COL = UI.COLORS

	local App = {}

	App.PAN_SPEED = 900 -- screen pixels a second
	App.TOP = 52        -- the top bar's height
	App.RAIL = 76       -- the tool rail's width
	App.DRAWER = 118    -- the build drawer's height

	App.TOOLS = {
		{ id = "look", label = "Look", key = "1", tip = "Look around (drag to move)" },
		{ id = "paint", label = "Terrain", key = "2", tip = "Paint terrain: tees, greens, fairways, hazards, trees" },
		{ id = "elevation", label = "Height", key = "3", tip = "Raise (left click) and lower (right click) the ground" },
		{ id = "build", label = "Build", key = "4", tip = "Put down buildings" },
	}

	App.ELEV_TOOLS = { { label = "Point", tip = "One corner" }, { label = "Square", tip = "A 2 x 2 block" },
		{ label = "Hill", tip = "A corner and its slopes" } }

	App.SOUNDS = {
		refused = "sounds/interface/unavailable", build = "sounds/interface/building", raise = "sounds/interface/bass up 2",
		lower = "sounds/interface/bass down 2", opened = "sounds/effects/tada", button = "sounds/interface/button2",
		green = "sounds/interface/place greentee", sand = "sounds/interface/place bunker", water = "sounds/interface/place water",
		rough = "sounds/interface/place rough", fairway = "sounds/interface/place fairway", rocks = "sounds/interface/place rocks",
	}

	function App:init(opts)
		opts = opts or {}
		Packs.setActive(opts.pack or "free")
		self.course = Course.new({ clock = opts.seed or 7, slot = opts.slot or 0, sandbox = opts.sandbox,
			difficulty = opts.difficulty, fixes = opts.fixes })
		local c = self.course
		self.terrain = c.terrain
		self.theme = L.THEME_NAMES[c.theme] or "parkland"
		local base = Packs.get(Packs.baseId)
		-- the free set draws all water in one look (OpenSGolf's water_one)
		self.terrain.waterOne = Packs.activeId == Packs.baseId and base and base.info.waterOneLook or false

		self.camera = Camera.new()
		self.camera.ground = function(x, z) return self.terrain:heightAt(x, z) end
		local cx, cz = self.terrain:tileCentre(c.land.clubhouse[1] + 2, c.land.clubhouse[2] + 2)
		self.camera.x, self.camera.z = cx, cz
		self.view = TerrainView.new(self.terrain, self.theme, self.camera)
		self.props = Props.new(c)
		self.ui = UI.new()
		self.keys = {}
		self.drag = nil
		self.tool = "look"
		self.paintTile = 2
		self.elevTool = 0
		self.buildKind = 6
		self.buildDir = 0
		self.brushVariant = 0
		self.seenVersion = -1
		self.seenRot = -1
		self.now = 0
		self.sw, self.sh = 1280, 720
		self.ui:card(("Welcome to %s in %s. Paint a tee, then a green, to build your first hole.")
			:format(c.land:record().course or "your course", c.land:record().name or ""), 0)
	end

	------------------------------------------------------------------------------------------------ frame

	function App:update(dt)
		self.now = self.now + dt
		local dx, dy = 0, 0
		if P.isKeyDown("w") or P.isKeyDown("up") then dy = dy - 1 end
		if P.isKeyDown("s") or P.isKeyDown("down") then dy = dy + 1 end
		if P.isKeyDown("a") or P.isKeyDown("left") then dx = dx - 1 end
		if P.isKeyDown("d") or P.isKeyDown("right") then dx = dx + 1 end
		if dx ~= 0 or dy ~= 0 then
			self.camera:panScreen(dx * App.PAN_SPEED * dt, dy * App.PAN_SPEED * dt)
			self:clampCamera()
			self:updateHover()
		end
		self:takeEvents()
	end

	function App:takeEvents()
		for _, e in ipairs(self.course:takeEvents()) do
			if e.type == "toast" then
				self.ui:toast(e.text, self.now)
			elseif e.type == "message" then
				self.ui:card(e.text, self.now)
			elseif e.type == "sound" then
				self:playSound(e.name)
			end
		end
	end

	function App:playSound(name)
		local path = Packs.sound(App.SOUNDS[name] or name)
		if path then pcall(P.playSound, path) end
	end

	function App:clampCamera()
		local t, cam = self.terrain, self.camera
		local x0, z0 = t:tileCentre(0, 0)
		local x1, z1 = t:tileCentre(t.w - 1, t.h - 1)
		cam.x = max(x0, min(x1, cam.x))
		cam.z = max(z0, min(z1, cam.z))
	end

	-- the ground changed or the view turned: tee arrows, then the terrain meshes
	function App:refreshGround()
		local c, rot = self.course, self.camera.rot
		if self.seenVersion ~= c.version or self.seenRot ~= rot then
			c:teeArrows(rot)
			self.view.builtFor = nil
			self.seenVersion, self.seenRot = c.version, rot
		end
	end

	function App:draw(sw, sh)
		self.sw, self.sh = sw, sh
		P.drawRect(0, 0, sw, sh, 12, 20, 16, 255)
		self:refreshGround()
		self.view:draw(sw, sh)
		self:drawCursor(sw, sh)
		self.props:draw(self.camera, sw, sh, self.now)
		self:drawPreview(sw, sh)
		self:drawHoleFigures(sw, sh)

		self.ui:beginFrame(self.mouseX, self.mouseY)
		self:drawTopBar(sw, sh)
		self:drawRail(sw, sh)
		self:drawDrawer(sw, sh)
		local bottom = self:drawerShown() and (sh - App.DRAWER - 8) or (sh - 12)
		self.ui:drawNotices(sw, sh, self.now, App.TOP + 10, bottom)
		self:drawCursorInfo(sw, sh)
		self.ui:drawTip(sw, sh)
	end

	------------------------------------------------------------------------------------------------ the tile under the mouse

	function App:updateHover()
		self.hover = nil
		if not self.mouseX or self.ui:over(self.mouseX, self.mouseY) then return end
		local t = self.terrain
		local x, _, z = self.camera:pick(self.mouseX, self.mouseY, self.sw, self.sh, function(px, pz) return t:heightAt(px, pz) end, 400)
		local S = T.TILE_SIZE
		local fx, fz = (x + t.w * S * 0.5) / S, (z + t.h * S * 0.5) / S
		local a, b = floor(fx), floor(fz)
		if a < 0 or b < 0 or a >= t.w or b >= t.h then return end
		self.hover = { a = a, b = b, cx = floor(fx + 0.5), cy = floor(fz + 0.5), x = x, z = z }
	end

	-- screen points of a tile rectangle's outline (tiles a0..a1, b0..b1), following the ground
	function App:tilePoly(a0, b0, a1, b1)
		local t, cam = self.terrain, self.camera
		local S = T.TILE_SIZE
		local pts = {}
		local function corner(cx, cy)
			local x, z = cx * S - t.w * S * 0.5, cy * S - t.h * S * 0.5
			local h = t:heightAt(min(x, (t.w * 0.5 - 0.01) * S), min(z, (t.h * 0.5 - 0.01) * S))
			local sx, sy = cam:toScreen(x, h + 1, z, self.sw, self.sh)
			pts[#pts + 1] = sx
			pts[#pts + 1] = sy
		end
		corner(a0, b0); corner(a1 + 1, b0); corner(a1 + 1, b1 + 1); corner(a0, b1 + 1)
		return pts
	end

	function App:drawTileHighlight(a0, b0, a1, b1, r, g, b, a)
		if a1 - a0 <= 0 and b1 - b0 <= 0 then
			P.drawPoly(self:tilePoly(a0, b0, a1, b1), r, g, b, a)
			return
		end
		-- larger areas tile by tile, so the outline follows hills
		for x = a0, a1 do
			for y = b0, b1 do P.drawPoly(self:tilePoly(x, y, x, y), r, g, b, a) end
		end
	end

	function App:drawCursor(sw, sh)
		local h = self.hover
		if not h then return end
		if self.tool == "paint" then
			if self.rect then
				local r = self.rect
				local a0, a1 = min(r.a, h.a), max(r.a, h.a)
				local b0, b1 = min(r.b, h.b), max(r.b, h.b)
				self:drawTileHighlight(a0, b0, a1, b1, 255, 255, 255, 50)
			else
				self:drawTileHighlight(h.a, h.b, h.a, h.b, 255, 255, 255, 70)
			end
		elseif self.tool == "elevation" then
			local cx, cy = h.cx, h.cy
			if self.elevTool == 1 then
				self:drawTileHighlight(cx - 1, cy - 1, cx, cy, 255, 230, 120, 50)
			elseif self.elevTool == 2 then
				self:drawTileHighlight(cx - 2, cy - 2, cx + 1, cy + 1, 255, 230, 120, 36)
			end
			-- the corner itself
			local t, S = self.terrain, T.TILE_SIZE
			local x, z = cx * S - t.w * S * 0.5, cy * S - t.h * S * 0.5
			local sx, sy = self.camera:toScreen(x, t:heightAt(x, z), z, sw, sh)
			local d = 7
			P.drawPoly({ sx, sy - d, sx + d, sy, sx, sy + d, sx - d, sy }, 255, 230, 120, 230)
		elseif self.tool == "look" then
			self:drawTileHighlight(h.a, h.b, h.a, h.b, 255, 255, 255, 30)
		end
	end

	-- the building tool's see-through picture of what would go down, red where it can't
	function App:buildAnchor()
		local h = self.hover
		if not h then return nil end
		local k = L.kinds()[self.buildKind]
		local size = k and k.size or 1
		-- the footprint centred on the mouse
		local off = floor((size - 1) / 2)
		return h.a - off, h.b - off, size
	end

	function App:drawPreview(sw, sh)
		if self.tool ~= "build" or not self.hover then return end
		local c = self.course
		local a, b, size = self:buildAnchor()
		local ex = c:existing(self.buildKind)
		local cost = c:buildQuote(self.buildKind, a, b)
		local fsize = size + (ex and 1 or 0)
		local okCol = cost and { 120, 230, 140, 70 } or { 240, 90, 80, 80 }
		self:drawTileHighlight(a, b, a + fsize - 1, b + fsize - 1, okCol[1], okCol[2], okCol[3], okCol[4])
		local level = ex and 1 or 0
		local t, S = self.terrain, T.TILE_SIZE
		local cx, cz = t:tileCentre(a, b)
		local off = (size - 1) * S * 0.5
		local x, z = cx + off, cz + off
		local sx, sy = self.camera:toScreen(x, t:heightAt(x, z), z, sw, sh)
		local opts = cost and { a = 150 } or { r = 255, g = 90, b = 80, a = 150 }
		for _, l in ipairs(self:buildingLayers(self.buildKind, level)) do
			local _, e = Packs.spriteImage(l.key)
			if e then
				local view = Sprites.viewFor(e, self.camera.rot, self.buildDir, nil)
				Sprites.draw(l.key, e.fpv - 1, view, sx, sy, self.camera.zoom, { a = opts.a, r = opts.r, g = opts.g, b = opts.b, noShadow = true })
			end
		end
	end

	function App:buildingLayers(kind, level)
		local theme = self.course.theme
		if kind == Course.K_WASHER then return { { key = "bldgs/upgrade bwasher" } } end
		if kind == Course.K_DRIVING_RANGE then
			local f = O.sprite(0x1b6 + level, theme)
			return f and { { key = f } } or {}
		end
		return O.layers(kind, level, theme)
	end

	-- the hole being built: its number, length and par over its green (building_figures)
	function App:drawHoleFigures(sw, sh)
		local c = self.course
		local h, len, par = c:buildingFigures()
		if not h then return end
		local hr = c.holes[h]
		local t = self.terrain
		local x, z = t:tileCentre(hr.pin[1], hr.pin[2])
		local sx, sy = self.camera:toScreen(x, t:heightAt(x, z), z, sw, sh)
		local text = ("Hole %d  ·  %d yds  ·  par %d"):format(h, len, par)
		local w = self.ui:textWidth(text, 15) + 20
		P.drawRect(sx - w / 2, sy - 64, w, 26, 16, 22, 20, 230)
		P.drawRect(sx - w / 2, sy - 40, w, 2, COL.gold[1], COL.gold[2], COL.gold[3], 255)
		self.ui:text(text, 15, sx, sy - 60, COL.text, 1)
	end

	-- the cost next to the mouse while painting or building
	function App:drawCursorInfo(sw, sh)
		local h = self.hover
		if not h or not self.mouseX then return end
		local text, col
		local c = self.course
		if self.tool == "paint" then
			local tiles = self.rect and self:rectTiles(self.rect.a, self.rect.b, h.a, h.b) or { { h.a, h.b } }
			local cost, n = c:paintCost(tiles, self.paintTile)
			if n > 0 then
				text = Course.money(cost)
				col = c:affordable(cost) and COL.text or COL.warn
			end
		elseif self.tool == "build" then
			local a, b = self:buildAnchor()
			local cost, why = c:buildQuote(self.buildKind, a, b)
			if cost then
				text = Course.money(cost)
				col = c:affordable(cost) and COL.text or COL.warn
			else
				text, col = why, COL.warn
			end
		end
		if text then
			local w = self.ui:textWidth(text, 14) + 14
			P.drawRect(self.mouseX + 16, self.mouseY + 14, w, 22, 10, 14, 12, 220)
			self.ui:text(text, 14, self.mouseX + 23, self.mouseY + 17, col)
		end
	end

	------------------------------------------------------------------------------------------------ the top bar

	function App:drawTopBar(sw, sh)
		local ui, c = self.ui, self.course
		ui:panel(0, 0, sw, App.TOP)
		local rec = c.land:record()
		ui:text(rec.course or "Course", 19, 18, 8, COL.text)
		local theme = self.theme:gsub("^%l", string.upper)
		ui:text(("%s  ·  %s  ·  %s"):format(rec.name or "", theme, c.sandbox and "Sandbox" or "Career"), 13, 18, 31, COL.dim)

		-- money
		local cash = Course.money(c.cash)
		local mx = sw / 2
		ui:text("FUNDS", 11, mx, 7, COL.dim, 1)
		ui:text(cash, 22, mx, 21, c.cash < 0 and COL.warn or COL.gold, 1)

		-- holes and rank
		local holes = c:openHoles()
		local ranks = { [0] = "Municipal", "Daily Fee", "Country Club", "Championship" }
		local rx = sw - 20
		ui:text(("%d / 18 holes"):format(holes), 17, rx, 9, COL.text, 2)
		ui:text(ranks[Course.rank(holes)], 13, rx, 31, COL.dim, 2)

		-- the open-hole button once the hole being built has a tee and a green
		if c:canOpenHole() then
			local label = ("Open hole %d"):format(c.nextHole)
			local w = ui:textWidth(label, 16) + 36
			ui:button(rx - 170 - w, 9, w, 34, { label = label, size = 16, bg = { 92, 196, 124, 220 }, color = { 10, 24, 14, 255 },
				tip = "Open the hole for play (H)", onClick = function() self:openHole() end })
		else
			local hr = c.holes[c.nextHole] or {}
			local hint
			if c.nextHole < 19 then
				if not hr.back or hr.back[1] == 0 then hint = ("Hole %d: paint a tee"):format(c.nextHole)
				elseif hr.pin[1] == 0 then hint = ("Hole %d: paint a green"):format(c.nextHole) end
			end
			if hint then ui:text(hint, 14, rx - 170, 18, COL.dim, 2) end
		end
	end

	function App:openHole()
		self.course:openHole()
		self:takeEvents()
	end

	------------------------------------------------------------------------------------------------ the tool rail

	function App:drawRail(sw, sh)
		local ui = self.ui
		local x, y = 10, App.TOP + 12
		local h = #App.TOOLS * 60 + 8
		ui:panel(x, y, App.RAIL - 20 + 10, h, COL.panel)
		for i, tool in ipairs(App.TOOLS) do
			ui:button(x + 4, y + 4 + (i - 1) * 60, App.RAIL - 20 + 2, 56, {
				label = tool.label, size = 13, active = self.tool == tool.id, tip = tool.tip .. " [" .. tool.key .. "]",
				icon = function(ix, iy, iw, ih) self:toolIcon(tool.id, ix, iy, iw, ih) end,
				onClick = function() self:setTool(tool.id) end,
			})
		end
		-- rotation
		local ry = y + h + 8
		ui:panel(x, ry, App.RAIL - 10, 40, COL.panel)
		local function arrow(dir)
			return function(ix, iy, iw, ih)
				local cx, cy = ix + iw / 2, iy + ih / 2
				P.drawPoly({ cx - 6 * dir, cy - 7, cx + 6 * dir, cy, cx - 6 * dir, cy + 7 }, COL.text[1], COL.text[2], COL.text[3], 220)
			end
		end
		ui:button(x + 4, ry + 4, 26, 32, { icon = arrow(-1), tip = "Turn the view [Q]", onClick = function() self:rotate(1) end })
		ui:button(x + 32, ry + 4, 26, 32, { icon = arrow(1), tip = "Turn the view [E]", onClick = function() self:rotate(-1) end })
	end

	-- simple drawn icons for the rail
	function App:toolIcon(id, x, y, w, h)
		local cx, cy = x + w / 2, y + h / 2
		local c = self.tool == id and COL.accent or COL.text
		if id == "look" then
			P.drawPoly({ cx - 11, cy, cx, cy - 7, cx + 11, cy, cx, cy + 7 }, c[1], c[2], c[3], 200)
			P.drawPoly({ cx - 4, cy, cx, cy - 4, cx + 4, cy, cx, cy + 4 }, 16, 22, 20, 255)
		elseif id == "paint" then
			local cat = Packs.terrain(self.theme)
			if cat then
				local cell = cat.cellFor(T.FAIRWAY, 0, 0)
				if cell then
					local u0, v0 = cat.uv(cell, 0, 0)
					local u1, v1 = cat.uv(cell, 1, 1)
					P.drawImageUV(P.loadImage(cat.image), u0, v0, u1, v1, cx - 12, cy - 9, 24, 18, 255, 255, 255, 255)
				end
			end
		elseif id == "elevation" then
			P.drawPoly({ cx - 13, cy + 8, cx - 3, cy - 8, cx + 3, cy + 1, cx + 6, cy - 3, cx + 13, cy + 8 }, c[1], c[2], c[3], 220)
		elseif id == "build" then
			P.drawPoly({ cx - 10, cy - 1, cx, cy - 10, cx + 10, cy - 1 }, c[1], c[2], c[3], 220)
			P.drawRect(cx - 8, cy - 1, 16, 10, c[1], c[2], c[3], 220)
		end
	end

	function App:setTool(id)
		if self.tool ~= id then self:playSound("button") end
		self.tool = id
		self.stroke, self.rect = nil, nil
	end

	function App:rotate(d)
		self.camera:setRotation(self.camera.rot + d)
		self:updateHover()
	end

	------------------------------------------------------------------------------------------------ the build drawer

	function App:drawerShown()
		return self.tool == "paint" or self.tool == "elevation" or self.tool == "build"
	end

	function App:terrainIcon(id, x, y, w, h, disabled)
		local cat = Packs.terrain(self.theme)
		if not cat then return end
		local tt = T.textureTypeFor(id, id == 7 and 12 or 0, id, 0)
		if id == 0 then tt = T.TEE end
		local cell = cat.cellFor(tt, 0, 0)
		if not cell then return end
		local u0, v0 = cat.uv(cell, 0, 0)
		local u1, v1 = cat.uv(cell, 1, 1)
		local s = min(w, h)
		local a = disabled and 120 or 255
		P.drawImageUV(P.loadImage(cat.image), u0, v0, u1, v1, x + (w - s) / 2, y + (h - s) / 2, s, s, a, a, a, 255)
		-- trees: the tree on its woods
		if id >= 13 and id <= 15 then
			local tid = ({ [13] = 0x19c, [14] = 0x193, [15] = 0x196 })[id]
			local key = O.decorFile(tid, self.course.theme)
			local e
			if key then _, e = Packs.spriteImage(key) end
			if e then
				local z = min(s / e.w, s / e.h) * 0.95
				Sprites.draw(key, e.fpv - 1, 0, x + w / 2 - (e.w / 2 - e.ax) * z, y + (h + s) / 2 - (e.h - e.ay) * z - 2, z, { noShadow = true })
			end
		end
	end

	function App:buildingIcon(kind, x, y, w, h, disabled)
		local layers = self:buildingLayers(kind, 0)
		-- the biggest picture decides the scale; flat layers first, as on the course
		local big
		for _, l in ipairs(layers) do
			local _, e = Packs.spriteImage(l.key)
			if e and (not big or e.w * e.h > big.w * big.h) then big = e end
		end
		if not big then return end
		local z = min(w / big.w, h / big.h)
		local gx, gy = x + w / 2 - (big.w / 2 - big.ax) * z, y + h - (big.h - big.ay) * z
		local col = disabled and { r = 110, g = 110, b = 110, a = 255, noShadow = true } or { noShadow = true }
		for _, flat in ipairs({ true, false }) do
			for _, l in ipairs(layers) do
				if (l.flat or false) == flat then
					local _, e = Packs.spriteImage(l.key)
					if e then Sprites.draw(l.key, e.fpv - 1, Sprites.viewFor(e, 0, 0), gx, gy, z, col) end
				end
			end
		end
	end

	function App:drawDrawer(sw, sh)
		if not self:drawerShown() then return end
		local ui, c = self.ui, self.course
		local x0 = App.RAIL + 10
		local y0 = sh - App.DRAWER - 10
		local w0 = sw - x0 - 10
		ui:panel(x0, y0, w0, App.DRAWER, COL.panel)
		if self.tool == "paint" then
			ui:text("TERRAIN", 12, x0 + 14, y0 + 8, COL.dim)
			local bw, bh = 74, 86
			local n = #Course.PAINT_TILES
			bw = min(bw, floor((w0 - 24) / n) - 4)
			for i, id in ipairs(Course.PAINT_TILES) do
				local bx = x0 + 12 + (i - 1) * (bw + 4)
				local cost = Course.paintUnits(id) * 100
				ui:button(bx, y0 + 24, bw, bh, {
					label = Course.tileName(id, c.theme), size = 12, active = self.paintTile == id,
					tip = ("%s  ·  %s a tile"):format(Course.tileName(id, c.theme), Course.money(cost)),
					icon = function(ix, iy, iw, ih, dis) self:terrainIcon(id, ix, iy, iw, ih, dis) end,
					onClick = function() self:pickBrush(id) end,
				})
			end
		elseif self.tool == "elevation" then
			ui:text("HEIGHT  ·  left click raises, right click lowers", 12, x0 + 14, y0 + 8, COL.dim)
			for i, t in ipairs(App.ELEV_TOOLS) do
				ui:button(x0 + 12 + (i - 1) * 164, y0 + 30, 160, 70, {
					label = t.label, sub = t.tip, size = 16, active = self.elevTool == i - 1,
					onClick = function() self.elevTool = i - 1 self:playSound("button") end,
				})
			end
		elseif self.tool == "build" then
			ui:text("BUILDINGS  ·  R turns", 12, x0 + 14, y0 + 8, COL.dim)
			local bw, bh = 104, 86
			for i, kind in ipairs(Course.BUILD_KINDS) do
				local k = L.kinds()[kind]
				local avail = c:buildAvailable(kind)
				local ex = c:existing(kind)
				local level = ex and c.land.objects[ex + 1].sub + 1 or 0
				local price = floor(floor(k.price / 100) * (level + 2) / 2) * 100
				local bx = x0 + 12 + (i - 1) * (bw + 4)
				local sub = avail and (ex and ("Upgrade " .. Course.money(price)) or Course.money(price)) or "Locked"
				ui:button(bx, y0 + 24, bw, bh, {
					label = k.name, size = 12, active = self.buildKind == kind, disabled = not avail,
					tip = avail and ("%s  ·  %s"):format(k.name, sub) or (k.name .. "  ·  build more holes to unlock"),
					icon = function(ix, iy, iw, ih, dis) self:buildingIcon(kind, ix, iy, iw, ih - 12, dis) end,
					onClick = function() self.buildKind = kind self:playSound("button") end,
				})
				ui:text(sub, 11, bx + bw / 2, y0 + 24 + bh - 30, avail and COL.gold or COL.dim, 1)
			end
		end
	end

	-- picking a brush rolls its variant (App::pick_brush): the green starts plain, Tab steps it
	function App:pickBrush(id)
		self.paintTile = id
		self.brushVariant = id == 1 and 0 or self.course.rng:below(3)
		self:playSound("button")
	end

	-- the byte the brush gives a tile: the green's (tricky on odd variants), the sand trap's shape
	function App:brushByte()
		local v = self.brushVariant
		if self.paintTile == 1 then return v % 2 == 1 and 0xff or 0 end
		if self.paintTile == 7 then return v % 12 + 12 end
		return 0
	end

	------------------------------------------------------------------------------------------------ painting

	function App:rectTiles(a0, b0, a1, b1)
		local tiles = {}
		for a = min(a0, a1), max(a0, a1) do
			for b = min(b0, b1), max(b0, b1) do tiles[#tiles + 1] = { a, b } end
		end
		return tiles
	end

	function App:paintSound(id)
		if id <= 1 then self:playSound("green")
		elseif id == 2 or id == 3 then self:playSound("fairway")
		elseif id >= 7 and id <= 9 then self:playSound("sand")
		elseif id == 17 then self:playSound("water")
		elseif id == 12 then self:playSound("rocks")
		else self:playSound("rough") end
	end

	function App:paintAt(a, b)
		local s = self.stroke
		local key = a * 1000 + b
		if s[key] then return end
		s[key] = true
		local spent = self.course:paint({ { a, b } }, self.paintTile, self:brushByte())
		if spent > 0 and not s.sounded then
			s.sounded = true
			self:paintSound(self.paintTile)
		end
		self:takeEvents()
	end

	------------------------------------------------------------------------------------------------ input

	function App:keyPressed(key)
		if key == "q" then
			self:rotate(1)
		elseif key == "e" then
			self:rotate(-1)
		elseif key == "h" then
			self:openHole()
		elseif key == "r" then
			self.buildDir = (self.buildDir + 1) % 4
		elseif key == "tab" then
			self.brushVariant = self.brushVariant + 1
		elseif key == "escape" then
			self:setTool("look")
		else
			for _, t in ipairs(App.TOOLS) do
				if key == t.key then self:setTool(t.id) end
			end
		end
	end

	function App:mousePressed(x, y, button)
		self.mouseX, self.mouseY = x, y
		if self.ui:press(x, y, button) then return end
		self:updateHover()
		local h = self.hover
		local tool = self.tool
		local c = self.course
		-- a click on the cup green of the hole being built opens it, as in the exe
		if h and button == "left" and tool == "look" and c:isCup(h.a, h.b) then
			local k = c:holeAt(h.a, h.b)
			if k and c.holes[k].par == 0 and k == c.nextHole and c:canOpenHole() then return self:openHole() end
		end
		if button == "middle" or (button == "right" and tool ~= "elevation") or (button == "left" and tool == "look") then
			self.drag = { x = x, y = y, button = button }
			return
		end
		if not h then return end
		if tool == "paint" and button == "left" then
			if P.isKeyDown("lshift") or P.isKeyDown("rshift") then
				self.rect = { a = h.a, b = h.b }
			else
				self.stroke = {}
				self:paintAt(h.a, h.b)
			end
		elseif tool == "elevation" then
			c:elevate(self.elevTool, h.cx, h.cy, button == "left")
			self:takeEvents()
		elseif tool == "build" and button == "left" then
			local a, b = self:buildAnchor()
			c:build(self.buildKind, a, b, self.buildDir)
			self:takeEvents()
		end
	end

	function App:mouseReleased(x, y, button)
		if self.rect and button == "left" then
			self:updateHover()
			local h = self.hover
			if h then
				local spent = self.course:paint(self:rectTiles(self.rect.a, self.rect.b, h.a, h.b), self.paintTile, self:brushByte())
				if spent > 0 then self:paintSound(self.paintTile) end
				self:takeEvents()
			end
		end
		self.rect = nil
		self.stroke = nil
		self.drag = nil
	end

	function App:mouseMoved(x, y)
		local d = self.drag
		self.mouseX, self.mouseY = x, y
		if d then
			self.camera:panScreen(d.x - x, d.y - y)
			self:clampCamera()
			d.x, d.y = x, y
		end
		self:updateHover()
		if self.stroke and self.hover then self:paintAt(self.hover.a, self.hover.b) end
	end

	function App:wheel(dy, sw, sh)
		local cam = self.camera
		local factor = dy > 0 and 1.25 or 0.8
		-- keep the ground under the cursor where it is
		local ox, oy = 0, 0
		if self.mouseX and sw then ox, oy = self.mouseX - sw * 0.5, self.mouseY - sh * 0.5 end
		cam:panScreen(ox, oy)
		cam:setZoom(cam.zoom * factor)
		cam:panScreen(-ox, -oy)
		self:clampCamera()
		self:updateHover()
	end

	return App
end
