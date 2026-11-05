-- LÖVE implementation of the Platform interface (core/platform.lua).
-- Returns a function that builds the implementation for a game id.
-- Networking is a local loopback for now (server and client in one process); lua-enet comes in Phase 7.

return function(id)
	local P = { name = "love" }

	function P.isServer() return true end
	function P.isClient() return true end

	function P.time() return love.timer.getTime() end

	function P.log(message)
		print("[" .. id .. "] " .. tostring(message))
	end

	-- files: LÖVE's save folder (t.identity in conf.lua)
	function P.readFile(path)
		if not love.filesystem.getInfo(path, "file") then return nil end
		return (love.filesystem.read(path))
	end

	function P.writeFile(path, data)
		local dir = path:match("^(.*)/[^/]*$")
		if dir then love.filesystem.createDirectory(dir) end
		return (love.filesystem.write(path, data))
	end

	function P.fileExists(path)
		return love.filesystem.getInfo(path) ~= nil
	end

	function P.screenSize()
		return love.graphics.getDimensions()
	end

	-- Packs keep their GMod addon layout inside packs/<pack>/, so a path such as "free/terrain/fairway.png"
	-- is read from packs/free/materials/<id>/free/terrain/fairway.png (sounds: packs/free/sound/<id>/...).
	local function packFile(kind, path)
		local pack = path:match("^([^/]+)/") or path
		return "packs/" .. pack .. "/" .. kind .. "/" .. id .. "/" .. path
	end

	local images = {}
	function P.loadImage(path)
		local img = images[path]
		if not img then
			img = love.graphics.newImage(packFile("materials", path))
			images[path] = img
		end
		return img
	end

	function P.imageSize(img)
		return img:getDimensions()
	end

	local function setColor(r, g, b, a)
		love.graphics.setColor((r or 255) / 255, (g or 255) / 255, (b or 255) / 255, (a or 255) / 255)
	end

	function P.drawImage(img, x, y, w, h, r, g, b, a)
		local iw, ih = img:getDimensions()
		setColor(r, g, b, a)
		love.graphics.draw(img, x, y, 0, w / iw, h / ih)
	end

	function P.drawRect(x, y, w, h, r, g, b, a)
		setColor(r, g, b, a)
		love.graphics.rectangle("fill", x, y, w, h)
	end

	local fonts = {}
	function P.drawText(text, size, x, y, r, g, b, a, alignX)
		size = math.floor(size or 16)
		local f = fonts[size]
		if not f then
			f = love.graphics.newFont(size)
			fonts[size] = f
		end
		text = tostring(text)
		local w = f:getWidth(text)
		if alignX == 1 then x = x - w / 2 elseif alignX == 2 then x = x - w end
		love.graphics.setFont(f)
		setColor(r, g, b, a)
		love.graphics.print(text, math.floor(x), math.floor(y))
	end

	local sounds = {}
	function P.playSound(path)
		local s = sounds[path]
		if not s then
			s = love.audio.newSource(packFile("sound", path), "static")
			sounds[path] = s
		end
		s:stop()
		s:play()
	end

	-- loopback networking: send() delivers straight to the handler in this process
	local handlers = {}
	function P.send(msgName, data)
		local fn = handlers[msgName]
		if fn then fn(data or {}, nil) end
	end

	function P.onReceive(msgName, fn)
		handlers[msgName] = fn
	end

	return P
end
