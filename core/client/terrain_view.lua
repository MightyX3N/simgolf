-- Draws the ground. The terrain's triangles are projected once per view rotation into base coordinates (see camera.lua),
-- lit per vertex the way the original's fixed-function OpenGL lit them, sorted far to near, and kept as static meshes on
-- the theme's texture atlas. Panning and zooming then only change one transform.

return function(Game)
	local T = Game.require("terrain")
	local Packs = Game.require("pack")
	local P = Game.Platform
	local sqrt, max, min, floor = math.sqrt, math.max, math.min, math.floor

	local View = {}
	View.__index = View

	local TRIS_PER_MESH = 8000 -- GMod meshes are kept well under their vertex limit

	-- light 0 of Terrain.dll: (-0.5, 0.1, -1) turned 40 degrees about x, then 45 about y, normalised; fixed in eye space
	local LX, LY, LZ
	do
		local s, c = math.sin(math.rad(40)), math.cos(math.rad(40))
		local x, y, z = -0.5, 0.1, -1.0
		y, z = c * y - s * z, s * y + c * z
		s, c = math.sin(math.rad(45)), math.cos(math.rad(45))
		x, z = c * x + s * z, -s * x + c * z
		local l = sqrt(x * x + y * y + z * z)
		LX, LY, LZ = x / l, y / l, z / l
	end
	View.LIGHT = { LX, LY, LZ }

	local DEFAULT_LIGHT = { ambient = { 199, 199, 199 }, diffuse = { 240, 240, 240 }, specular = { 255, 255, 255 } }

	-- The decoded light leaves flat ground at about 58% of its texture, but the original's own terrain icons show about 95%,
	-- so OpenSGolf scales ambient and diffuse by 1.74 to match (CALIBRATED in its render.rs); so do we.
	local BRIGHTNESS = 1.74

	-- OpenGL's default material under one directional light: 0.2 global ambient x 0.2, light ambient x 0.2, diffuse x 0.8 x n.l,
	-- specular (n.h)^13 with the viewer at infinity; the texture is modulated by the result
	local function shade(light, nx, ny, nz)
		local d = nx * LX + ny * LY + nz * LZ
		local hx, hy, hz = LX, LY, LZ + 1
		local hl = sqrt(hx * hx + hy * hy + hz * hz)
		local nh = max(0, (nx * hx + ny * hy + nz * hz) / hl)
		local spec = nh ^ 13
		local a, di, sp = light.ambient, light.diffuse, light.specular
		local out = {}
		for i = 1, 3 do
			local c = 0.04 + 0.2 * a[i] / 255 * BRIGHTNESS
			if d > 0 then c = c + 0.8 * di[i] / 255 * BRIGHTNESS * d + sp[i] / 255 * spec end
			out[i] = floor(min(1, c) * 255 + 0.5)
		end
		return out[1], out[2], out[3]
	end
	View.shade = shade

	function View.new(terrain, theme, camera)
		local v = setmetatable({ terrain = terrain, theme = theme, camera = camera, meshes = {}, builtFor = nil }, View)
		return v
	end

	function View:free()
		for _, m in ipairs(self.meshes) do P.freeMesh(m) end
		self.meshes = {}
		self.builtFor = nil
	end

	-- Build the vertex list for the current rotation. Returns the flat vertex array (x, y, u, v, r, g, b, a per vertex,
	-- three vertices per triangle) in drawing order, and the triangle count. Separate from the platform so tests can check it.
	function View:buildVertices()
		local t, cam = self.terrain, self.camera
		local cat = Packs.terrain(self.theme)
		assert(cat, "no terrain textures for theme " .. tostring(self.theme))
		local light = cat.lighting or DEFAULT_LIGHT
		self.atlas = cat.image

		-- tiles far to near, by the depth of their centre
		local order = {}
		for y = 0, t.h - 1 do
			for x = 0, t.w - 1 do
				if t.ty[t:index(x, y)] ~= T.OUT_OF_BOUNDS then
					local cx, cz = t:tileCentre(x, y)
					local _, _, depth = cam:project(cx, t:heightAt(cx, cz), cz)
					order[#order + 1] = { x, y, depth }
				end
			end
		end
		table.sort(order, function(a, b) return a[3] < b[3] end)

		local verts, n = {}, 0
		local tris = {}
		local count = 0
		for _, tile in ipairs(order) do
			for i = #tris, 1, -1 do tris[i] = nil end
			T.buildTileTriangles(t, tile[1], tile[2], tris)
			for _, tri in ipairs(tris) do
				local cell = cat.cellFor(tri[1], tri[2], tri[3])
				if cell then
					local p = {}
					for k = 0, 2 do
						local o = 3 + k * 8
						local x, y, z = tri[o + 1], tri[o + 2], tri[o + 3]
						local sx, sy = cam:project(x, y, z)
						local au, av = cat.uv(cell, tri[o + 4], tri[o + 5])
						local ex, ey, ez = cam:eyeNormal(tri[o + 6], tri[o + 7], tri[o + 8])
						local r, g, b = shade(light, ex, ey, ez)
						p[k + 1] = { sx, sy, au, av, r, g, b }
					end
					-- clockwise on screen (y down) for every triangle, so back-face culling never drops one
					local a, b, c = p[1], p[2], p[3]
					if (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]) < 0 then b, c = c, b end
					for _, q in ipairs({ a, b, c }) do
						verts[n + 1], verts[n + 2], verts[n + 3], verts[n + 4] = q[1], q[2], q[3], q[4]
						verts[n + 5], verts[n + 6], verts[n + 7], verts[n + 8] = q[5], q[6], q[7], 255
						n = n + 8
					end
					count = count + 1
				end
			end
		end
		return verts, count
	end

	function View:rebuild()
		self:free()
		local verts, count = self:buildVertices()
		local image = P.loadImage(self.atlas)
		local per = TRIS_PER_MESH * 24
		for first = 1, #verts, per do
			local chunk = {}
			local last = min(#verts, first + per - 1)
			for i = first, last do chunk[#chunk + 1] = verts[i] end
			self.meshes[#self.meshes + 1] = P.newMesh(image, chunk)
		end
		self.builtFor = self.camera.rot
		self.triangles = count
	end

	function View:draw(screenW, screenH)
		if self.builtFor ~= self.camera.rot then self:rebuild() end
		local tx, ty, s = self.camera:transform(screenW, screenH)
		P.pushTransform(tx, ty, s)
		for _, m in ipairs(self.meshes) do P.drawMesh(m) end
		P.popTransform()
	end

	return View
end
