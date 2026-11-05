-- Server entry point.

local root = GM.FolderName .. "/gamemode/"

-- Send every client-side and shared Lua file to clients.
local function addCSDir(dir)
	local files, dirs = file.Find(dir .. "*", "LUA")
	for _, f in ipairs(files) do
		if f:sub(-4) == ".lua" then AddCSLuaFile(dir .. f) end
	end
	for _, d in ipairs(dirs) do
		addCSDir(dir .. d .. "/")
	end
end

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
addCSDir(root .. "core/")
addCSDir(root .. "platform/gmod/")

include("shared.lua")
