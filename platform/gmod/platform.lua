-- Garry's Mod implementation of the Platform interface (core/platform.lua).
-- Loaded on both server and client. Returns a function that builds the implementation for a game id.

return function(id, gamemodeRoot)
	local P = { name = "gmod" }

	function P.isServer() return SERVER == true end
	function P.isClient() return CLIENT == true end

	function P.time() return SysTime() end

	-- every core event is also run as a GMod hook named "<id>.<Event>", so plain GMod addons can listen too
	function P.hookForward(event, ...)
		return hook.Run(id .. "." .. event, ...)
	end

	function P.log(message)
		MsgC(Color(79, 194, 122), "[" .. id .. "] ", color_white, tostring(message), "\n")
	end

	-- files: garrysmod/data/<id>/...
	-- file.Write only allows some extensions (.txt, .json, .dat, ...); save files must use one of them.
	local function dataPath(path) return id .. "/" .. path end

	function P.readFile(path)
		return file.Read(dataPath(path), "DATA")
	end

	function P.writeFile(path, data)
		local full = dataPath(path)
		local dir = string.GetPathFromFilename(full)
		if dir ~= "" then file.CreateDir(dir) end
		file.Write(full, data)
		return file.Exists(full, "DATA")
	end

	function P.fileExists(path)
		return file.Exists(dataPath(path), "DATA")
	end

	------------------------------------------------------------------------------------------------ packs

	-- The free pack's manifest ships in the gamemode (<gamemode>/gamemode/packs/free/); other packs are addons with
	-- lua/<id>/packs/<pack>/. Their pictures and sounds are under materials/<id>/<pack>/ and sound/<id>/<pack>/.
	local function manifestDir(pack)
		local inGamemode = gamemodeRoot .. "packs/" .. pack .. "/"
		if file.Exists(inGamemode .. "info.lua", "LUA") then return inGamemode end
		return id .. "/packs/" .. pack .. "/"
	end

	function P.listPacks()
		local seen, out = {}, {}
		for _, base in ipairs({ gamemodeRoot .. "packs/", id .. "/packs/" }) do
			local _, dirs = file.Find(base .. "*", "LUA")
			for _, d in ipairs(dirs or {}) do
				if not seen[d] and file.Exists(base .. d .. "/info.lua", "LUA") then
					seen[d] = true
					out[#out + 1] = d
				end
			end
		end
		table.sort(out)
		return out
	end

	function P.findPackFiles(pack, sub)
		local files = file.Find(manifestDir(pack) .. sub .. "/*.lua", "LUA")
		table.sort(files)
		return files
	end

	function P.loadPackFile(pack, path)
		local full = manifestDir(pack) .. path
		if not file.Exists(full, "LUA") then return nil end
		return include(full)
	end

	------------------------------------------------------------------------------------------------ networking

	-- one net message carries every core message as compressed JSON
	local NET = id .. ".msg"
	local handlers = {}

	if SERVER then util.AddNetworkString(NET) end

	function P.send(msgName, data, target)
		local raw = util.Compress(util.TableToJSON({ n = msgName, d = data or {} }))
		net.Start(NET)
		net.WriteUInt(#raw, 32)
		net.WriteData(raw, #raw)
		if SERVER then
			if target then net.Send(target) else net.Broadcast() end
		else
			net.SendToServer()
		end
	end

	function P.onReceive(msgName, fn)
		handlers[msgName] = fn
	end

	net.Receive(NET, function(_, ply)
		local raw = net.ReadData(net.ReadUInt(32))
		local json = raw and util.Decompress(raw)
		local msg = json and util.JSONToTable(json)
		if not msg or not handlers[msg.n] then return end
		handlers[msg.n](msg.d, SERVER and ply or nil)
	end)

	if SERVER then return P end

	------------------------------------------------------------------------------------------------ drawing (client)

	function P.screenSize() return ScrW(), ScrH() end

	-- images: materials/<id>/<pack>/... , e.g. loadImage("free/terrain/parkland.png")
	local images = {}
	function P.loadImage(path)
		local img = images[path]
		if not img then
			img = Material(id .. "/" .. path, "smooth mips noclamp")
			images[path] = img
		end
		return img
	end

	function P.imageSize(img)
		return img:Width(), img:Height()
	end

	function P.drawImage(img, x, y, w, h, r, g, b, a)
		surface.SetDrawColor(r or 255, g or 255, b or 255, a or 255)
		surface.SetMaterial(img)
		surface.DrawTexturedRect(x, y, w, h)
	end

	-- texture coordinates, not pixels: GMod resizes pictures whose sides are not powers of two, so a material's size
	-- can differ from its file's (the packs' sheets are powers of two, so nothing is resized)
	function P.drawImageUV(img, u0, v0, u1, v1, x, y, w, h, r, g, b, a)
		surface.SetDrawColor(r or 255, g or 255, b or 255, a or 255)
		surface.SetMaterial(img)
		surface.DrawTexturedRectUV(x, y, w, h, u0, v0, u1, v1)
	end

	function P.drawRect(x, y, w, h, r, g, b, a)
		surface.SetDrawColor(r, g, b, a or 255)
		surface.DrawRect(x, y, w, h)
	end

	local fonts = {}
	local function font(size)
		size = math.floor(size or 16)
		local name = fonts[size]
		if not name then
			name = id .. ".font" .. size
			surface.CreateFont(name, { font = "Roboto", size = size, weight = 500, extended = true })
			fonts[size] = name
		end
		return name
	end

	local ALIGN = { [0] = TEXT_ALIGN_LEFT, [1] = TEXT_ALIGN_CENTER, [2] = TEXT_ALIGN_RIGHT }
	function P.drawText(text, size, x, y, r, g, b, a, alignX)
		draw.SimpleText(tostring(text), font(size), x, y, Color(r, g, b, a or 255), ALIGN[alignX or 0], TEXT_ALIGN_TOP)
	end

	-- static meshes: vertices x, y, u, v, r, g, b, a; drawn under the current model matrix
	function P.newMesh(img, verts)
		local obj = Mesh()
		local count = #verts / 8
		mesh.Begin(obj, MATERIAL_TRIANGLES, count / 3)
		for i = 1, #verts, 8 do
			mesh.Position(Vector(verts[i], verts[i + 1], 0))
			mesh.TexCoord(0, verts[i + 2], verts[i + 3])
			mesh.Color(verts[i + 4], verts[i + 5], verts[i + 6], verts[i + 7])
			mesh.AdvanceVertex()
		end
		mesh.End()
		return { mesh = obj, mat = img }
	end

	function P.drawMesh(m)
		render.SetMaterial(m.mat)
		if MATERIAL_CULLMODE_NONE then render.CullMode(MATERIAL_CULLMODE_NONE) end
		m.mesh:Draw()
		if MATERIAL_CULLMODE_CCW then render.CullMode(MATERIAL_CULLMODE_CCW) end
	end

	function P.freeMesh(m)
		if IsValid(m.mesh) then m.mesh:Destroy() end
	end

	function P.pushTransform(tx, ty, s)
		local m = Matrix()
		m:Translate(Vector(tx, ty, 0))
		m:Scale(Vector(s, s, 1))
		cam.PushModelMatrix(m, true)
	end

	function P.popTransform()
		cam.PopModelMatrix()
	end

	-- sounds: sound/<id>/<pack>/... , e.g. playSound("free/sounds/interface/click.ogg")
	function P.playSound(path)
		surface.PlaySound(id .. "/" .. path)
	end

	------------------------------------------------------------------------------------------------ input (client)

	-- core key names ("w", "up", "space") <-> GMod KEY_ codes
	local NAME_TO_CODE = { up = KEY_UP, down = KEY_DOWN, left = KEY_LEFT, right = KEY_RIGHT, space = KEY_SPACE,
		escape = KEY_ESCAPE, ["return"] = KEY_ENTER, tab = KEY_TAB, lshift = KEY_LSHIFT, rshift = KEY_RSHIFT,
		lctrl = KEY_LCONTROL, rctrl = KEY_RCONTROL, backspace = KEY_BACKSPACE, delete = KEY_DELETE }

	local CODE_TO_NAME = {}
	for name, code in pairs(NAME_TO_CODE) do CODE_TO_NAME[code] = name end

	function P.keyCode(name)
		return NAME_TO_CODE[name] or _G["KEY_" .. name:upper()]
	end

	function P.keyName(code)
		if CODE_TO_NAME[code] then return CODE_TO_NAME[code] end
		local n = input.GetKeyName(code)
		return n and n:lower() or tostring(code)
	end

	function P.isKeyDown(name)
		local code = P.keyCode(name)
		return code ~= nil and input.IsKeyDown(code)
	end

	P.MOUSE_NAMES = { [MOUSE_LEFT] = "left", [MOUSE_RIGHT] = "right", [MOUSE_MIDDLE] = "middle" }

	return P
end
