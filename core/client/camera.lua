-- The view: SimGolf's orthographic camera, turned 45 degrees plus a quarter turn per rotation step and tilted down by the
-- original's pitch, so the ground lines up with the pre-rendered sprites.
--
-- "Base" coordinates are screen pixels at zoom 1 (one sprite pixel = one screen pixel = 1767 / 800 world units) with the
-- world origin at 0, 0. Screen = (base - base of the view centre) * zoom + screen centre.

return function(Game)
	local sin, cos, rad = math.sin, math.cos, math.rad

	local Camera = {}
	Camera.__index = Camera

	Camera.PITCH = 38.682186         -- degrees, the original at 800 x 600 (Terrain::initSystem)
	Camera.UNITS_PER_PIXEL = 1767 / 800
	Camera.MIN_ZOOM, Camera.MAX_ZOOM = 0.25, 2

	function Camera.new()
		local c = setmetatable({ x = 0, z = 0, zoom = 0.5, rot = 0 }, Camera)
		c:setRotation(0)
		return c
	end

	-- quarter turns 0..3
	function Camera:setRotation(q)
		self.rot = q % 4
		local yaw = rad(45 + 90 * self.rot)
		local pitch = rad(Camera.PITCH)
		self.cy, self.sy = cos(yaw), sin(yaw)
		self.cp, self.sp = cos(pitch), sin(pitch)
		self.k = 1 / Camera.UNITS_PER_PIXEL
	end

	-- world (x, y up, z) -> base x, base y (down), depth (larger is nearer the viewer)
	function Camera:project(x, y, z)
		local xr = x * self.cy + z * self.sy
		local zr = -x * self.sy + z * self.cy
		local k = self.k
		return xr * k, (zr * self.sp - y * self.cp) * k, self.sp * y + self.cp * zr
	end

	-- a world normal in eye space (for lighting)
	function Camera:eyeNormal(nx, ny, nz)
		local xr = nx * self.cy + nz * self.sy
		local zr = -nx * self.sy + nz * self.cy
		return xr, self.cp * ny - self.sp * zr, self.sp * ny + self.cp * zr
	end

	-- the transform from base to screen: screen = base * scale + (tx, ty)
	function Camera:transform(screenW, screenH)
		local bx, by = self:project(self.x, self.ground and self.ground(self.x, self.z) or 0, self.z)
		local s = self.zoom
		return screenW * 0.5 - bx * s, screenH * 0.5 - by * s, s
	end

	function Camera:toScreen(x, y, z, screenW, screenH)
		local tx, ty, s = self:transform(screenW, screenH)
		local bx, by, depth = self:project(x, y, z)
		return bx * s + tx, by * s + ty, depth
	end

	-- move the view centre by a screen-pixel offset (on the ground plane)
	function Camera:panScreen(dx, dy)
		local a = dx / self.zoom / self.k
		local b = dy / self.zoom / self.k / self.sp
		self.x = self.x + a * self.cy - b * self.sy
		self.z = self.z + a * self.sy + b * self.cy
	end

	-- the world point (x, z) at height y under base point (bx, by)
	function Camera:baseToWorld(bx, by, y)
		local xr = bx / self.k
		local zr = (by / self.k + y * self.cp) / self.sp
		return xr * self.cy - zr * self.sy, xr * self.sy + zr * self.cy
	end

	-- the ground point under screen point (sx, sy): the view ray marched down from `top` until it meets the ground
	-- (ground(x, z) -> height). Returns x, y, z.
	function Camera:pick(sx, sy, screenW, screenH, ground, top)
		local tx, ty, s = self:transform(screenW, screenH)
		local bx, by = (sx - tx) / s, (sy - ty) / s
		local step = 4
		local y = top or 400
		local px, pz = self:baseToWorld(bx, by, y)
		while y > -50 do
			local x, z = self:baseToWorld(bx, by, y)
			local g = ground(x, z)
			if g >= y then
				-- refine between the last point above the ground and this one
				local lo, hi = y, y + step
				for _ = 1, 6 do
					local mid = (lo + hi) * 0.5
					local mx, mz = self:baseToWorld(bx, by, mid)
					if ground(mx, mz) >= mid then lo = mid else hi = mid end
				end
				local fx, fz = self:baseToWorld(bx, by, lo)
				return fx, lo, fz
			end
			px, pz = x, z
			y = y - step
		end
		return px, 0, pz
	end

	function Camera:setZoom(z)
		self.zoom = math.max(Camera.MIN_ZOOM, math.min(Camera.MAX_ZOOM, z))
	end

	return Camera
end
