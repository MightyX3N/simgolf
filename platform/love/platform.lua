-- LÖVE implementation of the Platform interface (core/platform.lua).
-- Returns a function that builds the implementation for a game id.
-- Networking is a local loopback for now (server and client in one process); lua-enet comes in Phase 7.

return function(id)
	local P = { name = "love" }
	local lg = love.graphics

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

	------------------------------------------------------------------------------------------------ packs

	-- Packs keep their GMod addon layout inside packs/<pack>/: manifests in lua/<id>/packs/<pack>/, pictures in
	-- materials/<id>/<pack>/, sounds in sound/<id>/<pack>/. A path such as "free/terrain/parkland.png" names
	-- packs/free/materials/<id>/free/terrain/parkland.png.
	local function packFile(kind, path)
		local pack = path:match("^([^/]+)/") or path
		return "packs/" .. pack .. "/" .. kind .. "/" .. id .. "/" .. path
	end

	local function manifestDir(pack)
		return "packs/" .. pack .. "/lua/" .. id .. "/packs/" .. pack
	end

	function P.listPacks()
		local out = {}
		for _, name in ipairs(love.filesystem.getDirectoryItems("packs")) do
			if love.filesystem.getInfo(manifestDir(name) .. "/info.lua", "file") then out[#out + 1] = name end
		end
		table.sort(out)
		return out
	end

	function P.findPackFiles(pack, sub)
		local out = {}
		for _, name in ipairs(love.filesystem.getDirectoryItems(manifestDir(pack) .. "/" .. sub)) do
			if name:sub(-4) == ".lua" then out[#out + 1] = name end
		end
		table.sort(out)
		return out
	end

	function P.loadPackFile(pack, path)
		local file = manifestDir(pack) .. "/" .. path
		if not love.filesystem.getInfo(file, "file") then return nil end
		return love.filesystem.load(file)()
	end

	------------------------------------------------------------------------------------------------ drawing

	function P.screenSize()
		return lg.getDimensions()
	end

	local images = {}
	function P.loadImage(path)
		local img = images[path]
		if not img then
			img = lg.newImage(packFile("materials", path), { mipmaps = true })
			img:setFilter("linear", "linear")
			img:setMipmapFilter("linear")
			images[path] = img
		end
		return img
	end

	function P.imageSize(img)
		return img:getDimensions()
	end

	local function setColor(r, g, b, a)
		lg.setColor((r or 255) / 255, (g or 255) / 255, (b or 255) / 255, (a or 255) / 255)
	end

	function P.drawImage(img, x, y, w, h, r, g, b, a)
		local iw, ih = img:getDimensions()
		setColor(r, g, b, a)
		lg.draw(img, x, y, 0, w / iw, h / ih)
	end

	local quad = nil
	function P.drawImageUV(img, u0, v0, u1, v1, x, y, w, h, r, g, b, a)
		local iw, ih = img:getDimensions()
		local sx, sy, sw, sh = u0 * iw, v0 * ih, (u1 - u0) * iw, (v1 - v0) * ih
		if quad then quad:setViewport(sx, sy, sw, sh, iw, ih) else quad = lg.newQuad(sx, sy, sw, sh, iw, ih) end
		setColor(r, g, b, a)
		lg.draw(img, quad, x, y, 0, w / sw, h / sh)
	end

	function P.drawRect(x, y, w, h, r, g, b, a)
		setColor(r, g, b, a)
		lg.rectangle("fill", x, y, w, h)
	end

	local fonts = {}
	function P.drawText(text, size, x, y, r, g, b, a, alignX)
		size = math.floor(size or 16)
		local f = fonts[size]
		if not f then
			f = lg.newFont(size)
			fonts[size] = f
		end
		text = tostring(text)
		local w = f:getWidth(text)
		if alignX == 1 then x = x - w / 2 elseif alignX == 2 then x = x - w end
		lg.setFont(f)
		setColor(r, g, b, a)
		lg.print(text, math.floor(x), math.floor(y))
	end

	local FORMAT = { { "VertexPosition", "float", 2 }, { "VertexTexCoord", "float", 2 }, { "VertexColor", "byte", 4 } }
	function P.newMesh(img, verts)
		local list = {}
		for i = 1, #verts, 8 do
			list[#list + 1] = { verts[i], verts[i + 1], verts[i + 2], verts[i + 3],
				verts[i + 4] / 255, verts[i + 5] / 255, verts[i + 6] / 255, verts[i + 7] / 255 }
		end
		local mesh = lg.newMesh(FORMAT, list, "triangles", "static")
		mesh:setTexture(img)
		return mesh
	end

	function P.drawMesh(mesh)
		lg.setColor(1, 1, 1, 1)
		lg.draw(mesh)
	end

	function P.freeMesh(mesh)
		mesh:release()
	end

	function P.pushTransform(tx, ty, s)
		lg.push()
		lg.translate(tx, ty)
		lg.scale(s, s)
	end

	function P.popTransform()
		lg.pop()
	end

	------------------------------------------------------------------------------------------------ input, sound, net

	function P.isKeyDown(key)
		local ok, down = pcall(love.keyboard.isDown, key)
		return ok and down
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
