-- A Platform implementation for running the core without GMod or LÖVE (tests, tools).
-- Packs are read from the repository's packs/ folder. Drawing calls are counted, not drawn.

return function(root)
	local P = { name = "headless", logs = {}, draws = { rects = 0, images = 0, meshes = 0, texts = 0 } }

	function P.isServer() return true end
	function P.isClient() return true end
	function P.time() return os.clock() end
	function P.log(m) P.logs[#P.logs + 1] = tostring(m) end

	local saves = {}
	function P.readFile(path) return saves[path] end
	function P.writeFile(path, data) saves[path] = data; return true end
	function P.fileExists(path) return saves[path] ~= nil end

	local function exists(path)
		local f = io.open(path, "rb")
		if f then f:close() return true end
		return false
	end

	local function listDir(dir)
		local windows = package.config:sub(1, 1) == "\\"
		local cmd = windows and ('dir /b "' .. dir:gsub("/", "\\") .. '" 2>nul') or ('ls -1 "' .. dir .. '" 2>/dev/null')
		local out = {}
		local p = io.popen(cmd)
		if p then
			for line in p:lines() do out[#out + 1] = line end
			p:close()
		end
		table.sort(out)
		return out
	end
	P.listDir = listDir

	local function manifestDir(pack) return root .. "packs/" .. pack .. "/lua/simgolf/packs/" .. pack .. "/" end

	function P.listPacks()
		local out = {}
		for _, name in ipairs(listDir(root .. "packs")) do
			if exists(manifestDir(name) .. "info.lua") then out[#out + 1] = name end
		end
		return out
	end

	function P.findPackFiles(pack, sub)
		local out = {}
		for _, name in ipairs(listDir(manifestDir(pack) .. sub)) do
			if name:sub(-4) == ".lua" then out[#out + 1] = name end
		end
		return out
	end

	function P.loadPackFile(pack, path)
		local f = loadfile(manifestDir(pack) .. path)
		return f and f() or nil
	end

	-- the file a pack image path names (for tests that check the pictures)
	function P.imageFile(path)
		local pack = path:match("^([^/]+)/")
		return root .. "packs/" .. pack .. "/materials/simgolf/" .. path
	end

	function P.screenSize() return 1280, 720 end
	function P.loadImage(path) return { path = path } end
	function P.imageSize() return 0, 0 end
	function P.drawImage() P.draws.images = P.draws.images + 1 end
	function P.drawImageUV() P.draws.images = P.draws.images + 1 end
	function P.drawRect() P.draws.rects = P.draws.rects + 1 end
	function P.drawText() P.draws.texts = P.draws.texts + 1 end
	function P.newMesh(img, verts) return { img = img, n = #verts / 8 } end
	function P.drawMesh() P.draws.meshes = P.draws.meshes + 1 end
	function P.freeMesh() end
	function P.pushTransform() end
	function P.popTransform() end
	P.keysDown = {}
	function P.isKeyDown(k) return P.keysDown[k] == true end
	function P.playSound() end

	local handlers = {}
	function P.send(name, data) if handlers[name] then handlers[name](data or {}, nil) end end
	function P.onReceive(name, fn) handlers[name] = fn end

	return P
end
