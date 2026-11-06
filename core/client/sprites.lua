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
	-- (OpenSGolf render.rs prop_view): eight views turn two a quarter; four and two views add the prop's own facing; a
	-- fixed view (a flag, a tee marker) stays
	function Sprites.viewFor(entry, rot, facing, fixed)
		local views = entry.views
		if fixed then return fixed % math.max(1, views) end
		if views >= 8 then return (2 * rot) % 8 end
		if views >= 4 then return (rot + (facing or 0)) % views end
		if views == 2 then return (rot + (facing or 0)) % 2 end
		return 0
	end

	local function drawFrame(entry, path, frame, sx, sy, zoom, r, g, b, a)
		local f = floor(frame) % entry.frames
		local px, py = (f % entry.cols) * entry.w, floor(f / entry.cols) * entry.h
		-- the sheet's size from the manifest, not the loaded picture's (GMod may report another size)
		local sw, sh = entry.sheetW, entry.sheetH
		P.drawImageUV(image(path), px / sw, py / sh, (px + entry.w) / sw, (py + entry.h) / sh,
			sx - entry.ax * zoom, sy - entry.ay * zoom, entry.w * zoom, entry.h * zoom, r, g, b, a)
	end

	-- Draw sprite `key` with its ground point at screen (sx, sy). `frame` counts within the view (0 .. fpv - 1).
	-- opts (optional): noShadow, noBody, r, g, b, a (the body's colour, e.g. a see-through or red preview)
	function Sprites.draw(key, frame, view, sx, sy, zoom, opts)
		local path, entry = Packs.spriteImage(key)
		if not entry then return false end
		local index = (view % entry.views) * entry.fpv + (frame % entry.fpv)
		if opts then
			if entry.shadow and not opts.noShadow then
				local spath, sentry = Packs.spriteImage(entry.shadow)
				if sentry then
					drawFrame(sentry, spath, (view % sentry.views) * sentry.fpv + (frame % sentry.fpv), sx, sy, zoom, 0, 0, 0,
						opts.a or 255)
				end
			end
			if not opts.noBody then
				drawFrame(entry, path, index, sx, sy, zoom, opts.r or 255, opts.g or 255, opts.b or 255, opts.a or 255)
			end
			return true
		end
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
