-- Loads the shared core on both server and client.
-- Built layout: gamemodes/simgolf/gamemode/{core,platform/gmod}/ (tools/build.py copies them in).

local root = GM.FolderName .. "/gamemode/"
local function loadFile(path)
	return include(root .. path)
end

local info = loadFile("core/info.lua")

GM.Name = info.name
GM.Author = info.author
GM.Website = info.repo

local impl = loadFile("platform/gmod/platform.lua")(info.id)
local boot = loadFile("core/init.lua")

-- Global entry point for addons: SimGolf.Hook.Add(...), SimGolf.Platform, SimGolf.Info, ...
SimGolf = boot(loadFile, impl)
