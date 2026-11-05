-- The Platform interface: the only way core code may touch the engine it runs on.
-- platform/gmod/platform.lua and platform/love/platform.lua each implement these functions.
-- Core code calls Game.Platform.<name>(...) and never uses GMod or LÖVE globals directly.
--
-- Colours are r, g, b, a numbers from 0 to 255. Positions and sizes are in screen pixels.
-- File paths are relative to the game's own save area (GMod: garrysmod/data/<id>/, LÖVE: the save folder).

local Platform = {}

Platform.spec = {
	-- identity
	{ "name",        "string: 'gmod' or 'love'" },
	{ "isServer",    "() -> bool: this process runs the simulation" },
	{ "isClient",    "() -> bool: this process draws and takes input" },

	-- time and logging
	{ "time",        "() -> number: seconds, monotonic" },
	{ "log",         "(message)" },

	-- files in the save area
	{ "readFile",    "(path) -> string or nil" },
	{ "writeFile",   "(path, data) -> bool" },
	{ "fileExists",  "(path) -> bool" },

	-- drawing (entries marked "client" only exist on clients)
	{ "screenSize",  "() -> width, height", "client" },
	{ "loadImage",   "(path) -> image handle; path inside the active pack, e.g. 'free/terrain/fairway.png'", "client" },
	{ "imageSize",   "(image) -> width, height", "client" },
	{ "drawImage",   "(image, x, y, w, h, r, g, b, a)", "client" },
	{ "drawRect",    "(x, y, w, h, r, g, b, a)", "client" },
	{ "drawText",    "(text, size, x, y, r, g, b, a, alignX) alignX: 0 left, 1 centre, 2 right", "client" },
	{ "drawImageUV", "(image, u0, v0, u1, v1, x, y, w, h, r, g, b, a) part of an image, texture coordinates 0..1", "client" },
	{ "newMesh",     "(image, vertices) -> mesh; vertices: flat x, y, u, v, r, g, b, a per vertex, 3 per triangle", "client" },
	{ "drawMesh",    "(mesh) drawn under the current transform", "client" },
	{ "freeMesh",    "(mesh)", "client" },
	{ "pushTransform", "(tx, ty, scale) until popTransform: screen = position * scale + (tx, ty)", "client" },
	{ "popTransform", "()", "client" },

	-- input (client only)
	{ "isKeyDown",   "(key) -> bool; key names as App:keyPressed gets them ('w', 'left', 'space', ...)", "client" },

	-- sound (client only)
	{ "playSound",   "(path) path inside the active pack, e.g. 'free/sounds/click.wav'", "client" },

	-- asset packs: manifests written by tools/export-pack (lua/simgolf/packs/<id>/ in a pack)
	{ "listPacks",   "() -> array of installed pack ids" },
	{ "findPackFiles", "(id, subfolder) -> array of .lua file names in that folder of the pack's manifest" },
	{ "loadPackFile", "(id, path) -> what the manifest file at path returns, or nil" },

	-- networking: messages are plain Lua tables
	{ "send",        "(msgName, data, target) server: target = player or nil for everyone; client: to the server" },
	{ "onReceive",   "(msgName, fn) fn(data, sender) ; sender is nil on clients" },
}

-- Checks an implementation against the spec. Missing functions are replaced with stubs that raise a clear
-- error when called, so a half-finished platform layer still boots and points at what is missing.
function Platform.bind(impl)
	assert(type(impl) == "table", "Platform.bind: implementation table required")

	-- On a server-only process (a GMod dedicated server or the server realm) client functions don't exist;
	-- they get stubs but are not reported as missing.
	local serverOnly = type(impl.isClient) == "function" and not impl.isClient()

	local missing = {}
	for _, entry in ipairs(Platform.spec) do
		local key, clientOnly = entry[1], entry[3] == "client"
		if impl[key] == nil then
			if clientOnly and serverOnly then
				impl[key] = function()
					error(("%s is client-only and was called on the server"):format(key), 2)
				end
			else
				missing[#missing + 1] = key
				impl[key] = function()
					error(("Platform '%s' does not implement %s %s"):format(tostring(impl.name), key, entry[2]), 2)
				end
			end
		end
	end

	impl.missing = missing
	return impl
end

return Platform
