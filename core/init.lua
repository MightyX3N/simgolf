-- Boots the shared core. A platform entry point runs this file and calls the function it returns:
--
--   local Game = boot(loadFile, impl)
--
--   loadFile(path) returns what the Lua file at `path` returns. Paths are relative to the game root,
--                  e.g. "core/hook.lua" (GMod: <gamemode>/gamemode/core/hook.lua, LÖVE: core/hook.lua).
--   impl           the platform implementation table (see core/platform.lua).

return function(loadFile, impl)
	local Game = {}

	Game.loadFile = loadFile
	Game.Info = loadFile("core/info.lua")
	Game.Hook = loadFile("core/hook.lua")
	Game.Hook.forward = impl.hookForward -- optional: lets the platform see every core event
	Game.Platform = loadFile("core/platform.lua").bind(impl)

	local P = Game.Platform
	P.log(("%s %s (API %d) on %s"):format(Game.Info.name, Game.Info.version, Game.Info.apiVersion, P.name))
	if #P.missing > 0 then
		P.log("Platform functions not implemented yet: " .. table.concat(P.missing, ", "))
	end

	Game.Hook.Run("CoreLoaded", Game)
	return Game
end
