-- Boots the shared core. A platform entry point runs this file and calls the function it returns:
--
--   local Game = boot(loadFile, impl)
--
--   loadFile(path) returns what the Lua file at `path` returns. Paths are relative to the game root,
--                  e.g. "core/hook.lua" (GMod: <gamemode>/gamemode/core/hook.lua, LÖVE: core/hook.lua).
--   impl           the platform implementation table (see core/platform.lua).
--
-- Core modules other than info, hook and platform return function(Game) and are loaded once with Game.require("name"),
-- e.g. Game.require("terrain") or Game.require("client/camera").
-- Rule tables load on first use: Game.Data.terrain is core/data/terrain.lua.

return function(loadFile, impl)
	local Game = {}

	Game.loadFile = loadFile
	Game.Info = loadFile("core/info.lua")
	Game.Hook = loadFile("core/hook.lua")
	Game.Hook.forward = impl.hookForward -- optional: lets the platform see every core event
	Game.Platform = loadFile("core/platform.lua").bind(impl)

	local modules, loading = {}, {}
	function Game.require(name)
		local m = modules[name]
		if m ~= nil then return m end
		assert(not loading[name], "circular Game.require of " .. name)
		loading[name] = true
		m = loadFile("core/" .. name .. ".lua")(Game)
		loading[name] = nil
		modules[name] = m
		return m
	end

	Game.Data = setmetatable({}, {
		__index = function(t, name)
			local d = loadFile("core/data/" .. name .. ".lua")
			rawset(t, name, d)
			return d
		end,
	})

	local P = Game.Platform
	P.log(("%s %s (API %d) on %s"):format(Game.Info.name, Game.Info.version, Game.Info.apiVersion, P.name))
	if #P.missing > 0 then
		P.log("Platform functions not implemented yet: " .. table.concat(P.missing, ", "))
	end

	Game.Hook.Run("CoreLoaded", Game)
	return Game
end
