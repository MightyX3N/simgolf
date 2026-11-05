-- Server entry point.

local root = GM.FolderName .. "/gamemode/"

-- Send every client-side and shared Lua file to clients.
local function addCSDir(dir)
	local files, dirs = file.Find(dir .. "*", "LUA")
	for _, f in ipairs(files or {}) do
		if f:sub(-4) == ".lua" then AddCSLuaFile(dir .. f) end
	end
	for _, d in ipairs(dirs or {}) do
		addCSDir(dir .. d .. "/")
	end
end

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
addCSDir(root .. "core/")
addCSDir(root .. "platform/gmod/")
addCSDir(root .. "packs/")    -- the free pack's manifest
addCSDir("simgolf/packs/")    -- manifests of asset packs installed as addons

include("shared.lua")

-- Players only watch the course view for now: no body, no weapons.
function GM:PlayerSpawn(ply)
	ply:Spectate(OBS_MODE_ROAMING)
	ply:StripWeapons()
end
