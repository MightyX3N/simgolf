-- The sprites that stand on the course: the land's objects (buildings, the clubhouse, landmarks), the trees of tree tiles,
-- and the holes' flags and tee markers. Rebuilt from the course when it changes (OpenSGolf app.rs add_land_objects,
-- add_trees, update_decor_props); sorted far to near per view rotation.

return function(Game)
	local O = Game.require("objects")
	local Course = Game.require("course")
	local Packs = Game.require("pack")
	local Sprites = Game.require("client/sprites")
	local T = Game.require("terrain")
	local L = Game.require("land")
	local floor, min, max = math.floor, math.min, math.max

	local Props = {}
	Props.__index = Props

	Props.FPS = 10 -- animation frames a second

	function Props.new(course)
		return setmetatable({ course = course, list = {}, builtFor = -1, sortedFor = -1 }, Props)
	end

	local function push(list, t, key, x, z, o)
		local _, entry = Packs.spriteImage(key)
		if not entry then return end
		o = o or {}
		list[#list + 1] = {
			key = key, x = x, z = z, y = t:heightAt(x, z), entry = entry,
			facing = o.facing or 0, view = o.view, flat = o.flat or false, animated = o.animated or false,
			phase = o.phase or 0, frame = o.frame,
		}
	end

	function Props:rebuild()
		local c = self.course
		local land, t = c.land, c.terrain
		local theme = c.theme
		local S = T.TILE_SIZE
		local list = {}
		local N = 50

		-- objects
		local bigCourse = c:openHoles() > 10
		for _, o in ipairs(land.objects) do
			if o.kind >= 0 and t:typeAt(o.a, o.b) ~= 20 then
				local level = o.kind == Course.K_SNACK_BAR and (bigCourse and 1 or 0) or max(0, min(1, o.sub))
				if o.kind == Course.K_DRIVING_RANGE then
					local green = function(i, j)
						local ta, tb = o.a + i, o.b + j
						return ta >= 0 and tb >= 0 and ta < N and tb < N and land.ty[ta * N + tb] == 1
					end
					for _, pc in ipairs(O.drivingRange(level, theme, green)) do
						local x = (o.a * 1024 + pc.ua) * S / 1024 - t.w * S * 0.5
						local z = (o.b * 1024 + pc.ub) * S / 1024 - t.h * S * 0.5
						push(list, t, pc.key, x, z, { flat = pc.flat, animated = pc.animated, phase = pc.phase, view = pc.view })
					end
				else
					local k = L.kinds()[o.kind]
					local size = k and k.size or 1
					local cx, cz = t:tileCentre(o.a, o.b)
					local off = (size - 1) * S * 0.5
					local x, z = cx + off, cz + off
					local layers
					if o.kind == Course.K_WASHER then
						layers = { { key = "bldgs/upgrade bwasher" } }
					elseif o.kind == Course.K_LANDMARK then
						local f = O.landmark(o.sub)
						layers = f and { { key = f, animated = true } } or {}
					elseif o.kind == Course.K_HOME_SITE then
						layers = {}
					else
						layers = O.layers(o.kind, level, theme)
					end
					for _, l in ipairs(layers) do
						push(list, t, l.key, x, z, { flat = l.flat, animated = l.animated, facing = o.dir })
					end
				end
			end
		end

		-- trees
		local function tyAt(a, b)
			if a >= 0 and b >= 0 and a < N and b < N then return land.ty[a * N + b] end
			return 0x1f
		end
		local noise = c.noise
		local field = function(x, y) return noise and noise:field(x, y) or 0 end
		for a = 0, N - 1 do
			for b = 0, N - 1 do
				local i = a * N + b
				local ty = land.ty[i]
				if ty >= 13 and ty <= 15 then
					local scenic = bit.band(land.flags[i], 0x100) ~= 0
					local cx, cz = t:tileCentre(a, b)
					for _, d in ipairs(O.trees(tyAt, Course.row, land.var[i], scenic, a, b, theme, true, field)) do
						local key = O.decorFile(d.id, theme)
						if key then push(list, t, key, cx + d.da * S, cz + d.db * S, { facing = d.view, frame = d.frame }) end
					end
				end
			end
		end

		-- the holes: a flag on each cup green, tee markers on the open holes' tees
		for h = 1, 18 do
			local r = c.holes[h]
			if r.pin[1] ~= 0 then
				local cx, cz = t:tileCentre(r.pin[1], r.pin[2])
				push(list, t, O.decorFile(0x189, theme), cx, cz, { view = r.par ~= 0 and 0 or 1, animated = true, phase = h * 3 })
			end
			if r.par ~= 0 and r.back[1] ~= 0 then
				local cx, cz = t:tileCentre(r.back[1], r.back[2])
				for _, d in ipairs(O.teeMarkers(r.par, r.teeFacing)) do
					push(list, t, O.decorFile(d.id, theme), cx + d.da * S, cz + d.db * S, { view = 0 })
				end
			end
		end

		self.list = list
		self.builtFor = c.objectsVersion
		self.sortedFor = -1
	end

	function Props:sort(camera)
		for _, p in ipairs(self.list) do
			p.bx, p.by, p.depth = camera:project(p.x, p.y, p.z)
		end
		table.sort(self.list, function(a, b)
			if a.flat ~= b.flat then return a.flat end
			return a.depth < b.depth
		end)
		self.sortedFor = camera.rot
	end

	function Props:draw(camera, sw, sh, now)
		if self.builtFor ~= self.course.objectsVersion then self:rebuild() end
		if self.sortedFor ~= camera.rot then self:sort(camera) end
		local tx, ty, s = camera:transform(sw, sh)
		local rot = camera.rot
		local tick = floor((now or 0) * Props.FPS)
		for _, p in ipairs(self.list) do
			local x, y = p.bx * s + tx, p.by * s + ty
			local e = p.entry
			if x > -(e.w) * s and x < sw + e.w * s and y > -20 * s and y < sh + e.h * s then
				local frame = p.frame
				if not frame then
					frame = p.animated and ((tick + p.phase) % e.fpv) or (e.fpv - 1)
				end
				local view = Sprites.viewFor(e, rot, p.facing, p.view)
				if p.flat then
					Sprites.draw(p.key, frame, view, x, y, s, { noShadow = true })
				else
					Sprites.draw(p.key, frame, view, x, y, s)
				end
			end
		end
	end

	return Props
end
