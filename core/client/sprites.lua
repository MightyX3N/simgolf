-- Pre-rendered sprites (trees, buildings, people) from the active pack, drawn at their ground point.
-- A sprite's frames are view-major (view * fpv + frame); its shadow, when it has one, is drawn first.

return function(Game)
	local Packs = Game.require("pack")
	local P = Game.Platform
	local floor = math.floor

	local Sprites = {}

	local images = {}
	local function image(path)
		local img = images[path]
		if not img then
			img = P.loadImage(path)
			images[path] = img
		end
		return img
	end

	-- the view to draw for a quarter-turn camera rotation: 4-view sprites turn with the camera, 1-view sprites never do
	function Sprites.viewFor(entry, rot)
		if entry.views <= 1 then return 0 end
		if entry.views == 4 then return rot % 4 end
		return (2 * rot) % entry.views
	end

	local function drawFrame(entry, path, frame, sx, sy, zoom, r, g, b, a)
		local f = floor(frame) % entry.frames
		local col, row = f % entry.cols, floor(f / entry.cols)
		P.drawImageRect(image(path), col * entry.w, row * entry.h, entry.w, entry.h,
			sx - entry.ax * zoom, sy - entry.ay * zoom, entry.w * zoom, entry.h * zoom, r, g, b, a)
	end

	-- Draw sprite `key` with its ground point at screen (sx, sy). `frame` counts within the view (0 .. fpv - 1).
	function Sprites.draw(key, frame, view, sx, sy, zoom)
		local path, entry = Packs.spriteImage(key)
		if not entry then return false end
		local index = (view % entry.views) * entry.fpv + (frame % entry.fpv)
		if entry.shadow then
			local spath, sentry = Packs.spriteImage(entry.shadow)
			if sentry then
				drawFrame(sentry, spath, (view % sentry.views) * sentry.fpv + (frame % sentry.fpv), sx, sy, zoom, 0, 0, 0, 255)
			end
		end
		drawFrame(entry, path, index, sx, sy, zoom, 255, 255, 255, 255)
		return true
	end

	-- screen size of a sprite at zoom (for culling): left, top, right, bottom offsets from its ground point
	function Sprites.bounds(key, zoom)
		local _, entry = Packs.spriteImage(key)
		if not entry then return 0, 0, 0, 0 end
		return -entry.ax * zoom, -entry.ay * zoom, (entry.w - entry.ax) * zoom, (entry.h - entry.ay) * zoom
	end

	return Sprites
end
