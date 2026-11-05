-- Garry's Mod implementation of the Platform interface (core/platform.lua).
-- Loaded on both server and client. Returns a function that builds the implementation for a game id.

return function(id)
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

	-- networking: one net message carries every core message as compressed JSON
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

	if CLIENT then
		function P.screenSize() return ScrW(), ScrH() end

		-- images: materials/<id>/<pack>/... , e.g. loadImage("free/terrain/fairway.png")
		local images = {}
		function P.loadImage(path)
			local img = images[path]
			if not img then
				img = Material(id .. "/" .. path, "smooth noclamp")
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

		-- sounds: sound/<id>/<pack>/... , e.g. playSound("free/sounds/click.wav")
		function P.playSound(path)
			surface.PlaySound(id .. "/" .. path)
		end
	end

	return P
end
