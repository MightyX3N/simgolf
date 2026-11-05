-- The client application: the course view with camera controls. Phase 1 shows OpenSGolf's demo course with trees on its
-- woods; game state and building tools come in Phase 2.
--
-- The platform layer calls:
--   App:init(screenW, screenH)        once, after the core has booted
--   App:update(dt)                    every frame, dt in seconds
--   App:draw(screenW, screenH)        every frame
--   App:keyPressed(key)               key names: "a".."z", "0".."9", "up", "down", "left", "right", "escape", "space", ...
--   App:mousePressed(x, y, button)    buttons: "left", "right", "middle"
--   App:mouseReleased(x, y, button)
--   App:mouseMoved(x, y)
--   App:wheel(dy)                     positive: away from the user (zoom in)

return function(Game)
	local T = Game.require("terrain")
	local Rng = Game.require("rng")
	local Packs = Game.require("pack")
	local Camera = Game.require("client/camera")
	local TerrainView = Game.require("client/terrain_view")
	local Sprites = Game.require("client/sprites")
	local P = Game.Platform

	local App = {}

	App.MAP_SIZE = 50 -- the original's course size
	App.PAN_SPEED = 900 -- screen pixels a second

	-- trees the demo course scatters on woods, per theme (sprite keys in the pack, full-grown frame)
	App.TREES = {
		parkland = {
			"trees/treemaplelarge", "trees/treemaplemedium", "trees/treepinelarge", "trees/treepinemedium",
			"trees/treepinesprucelg", "trees/treepinesprucemed", "trees/treepinefirlg", "trees/treepinefirmed",
		},
	}

	function App:init(opts)
		opts = opts or {}
		self.theme = opts.theme or "parkland"
		Packs.setActive(opts.pack or "free")

		local base = Packs.get(Packs.baseId)
		self.terrain = T.demoCourse(opts.size or App.MAP_SIZE, opts.size or App.MAP_SIZE, opts.seed or 7)
		-- the free set draws all water in one look (OpenSGolf's water_one)
		self.terrain.waterOne = Packs.activeId == Packs.baseId and base and base.info.waterOneLook or false

		self.camera = Camera.new()
		self.camera.ground = function(x, z) return self.terrain:heightAt(x, z) end
		self.view = TerrainView.new(self.terrain, self.theme, self.camera)
		self:scatterScenery(opts.seed or 7)
		self.keys = {}
		self.drag = nil
	end

	function App:scatterScenery(seed)
		local t, rng = self.terrain, Rng.new(seed * 7919 + 1)
		local trees = App.TREES[self.theme] or App.TREES.parkland
		self.scenery = {}
		for y = 0, t.h - 1 do
			for x = 0, t.w - 1 do
				if t:typeAt(x, y) == T.WOODS then
					local cx, cz = t:tileCentre(x, y)
					for _ = 1, 2 do
						local px, pz = cx + (rng:unit() - 0.5) * 70, cz + (rng:unit() - 0.5) * 70
						local key = trees[rng:range(#trees) + 1]
						local _, entry = Packs.spriteImage(key)
						if entry then
							self.scenery[#self.scenery + 1] = { key = key, x = px, y = t:heightAt(px, pz), z = pz, frame = entry.fpv - 1 }
						end
					end
				end
			end
		end
		self.sceneryRot = nil
	end

	-- far to near for the current rotation
	function App:sortScenery()
		local cam = self.camera
		for _, s in ipairs(self.scenery) do
			s.bx, s.by, s.depth = cam:project(s.x, s.y, s.z)
		end
		table.sort(self.scenery, function(a, b) return a.depth < b.depth end)
		self.sceneryRot = cam.rot
	end

	------------------------------------------------------------------------------------------------ frame

	function App:update(dt)
		local dx, dy = 0, 0
		if P.isKeyDown("w") or P.isKeyDown("up") then dy = dy - 1 end
		if P.isKeyDown("s") or P.isKeyDown("down") then dy = dy + 1 end
		if P.isKeyDown("a") or P.isKeyDown("left") then dx = dx - 1 end
		if P.isKeyDown("d") or P.isKeyDown("right") then dx = dx + 1 end
		if dx ~= 0 or dy ~= 0 then
			self.camera:panScreen(dx * App.PAN_SPEED * dt, dy * App.PAN_SPEED * dt)
			self:clampCamera()
		end
	end

	function App:clampCamera()
		local t, cam = self.terrain, self.camera
		local x0, z0 = t:tileCentre(0, 0)
		local x1, z1 = t:tileCentre(t.w - 1, t.h - 1)
		cam.x = math.max(x0, math.min(x1, cam.x))
		cam.z = math.max(z0, math.min(z1, cam.z))
	end

	function App:draw(sw, sh)
		P.drawRect(0, 0, sw, sh, 12, 20, 16, 255)
		self.view:draw(sw, sh)

		if self.sceneryRot ~= self.camera.rot then self:sortScenery() end
		local tx, ty, s = self.camera:transform(sw, sh)
		local rot = self.camera.rot
		for _, item in ipairs(self.scenery) do
			local x, y = item.bx * s + tx, item.by * s + ty
			if x > -200 * s and x < sw + 200 * s and y > -20 * s and y < sh + 300 * s then
				local _, entry = Packs.spriteImage(item.key)
				Sprites.draw(item.key, item.frame, Sprites.viewFor(entry, rot), x, y, s)
			end
		end

		local info = Game.Info
		P.drawRect(12, 12, 620, 30, 12, 20, 16, 220)
		P.drawText(("%s %s  ·  WASD or drag: move  ·  wheel: zoom  ·  Q / E: rotate"):format(info.name, info.version), 15, 22, 19, 238, 245, 240, 255, 0)
	end

	------------------------------------------------------------------------------------------------ input

	function App:keyPressed(key)
		if key == "q" then
			self.camera:setRotation(self.camera.rot + 1)
		elseif key == "e" then
			self.camera:setRotation(self.camera.rot - 1)
		end
	end

	function App:mousePressed(x, y, button)
		self.drag = { x = x, y = y }
	end

	function App:mouseReleased(x, y, button)
		self.drag = nil
	end

	function App:mouseMoved(x, y)
		local d = self.drag
		if d then
			self.camera:panScreen(d.x - x, d.y - y)
			self:clampCamera()
			d.x, d.y = x, y
		end
		self.mouseX, self.mouseY = x, y
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
	end

	return App
end
