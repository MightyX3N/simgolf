-- Smoke test of the built GMod gamemode against stand-ins for GMod's API, for checking without Garry's Mod:
--
--   python tools/build.py gmod
--   luajit tests/gmod_smoke.lua dist/gmod/simgolf/ client
--   luajit tests/gmod_smoke.lua dist/gmod/simgolf/ server
--
-- The argument is the built addon (gamemodes/, materials/, sound/ inside it).
--
-- The stand-ins only record calls; this proves the files load, every Platform function exists and a frame draws.
-- It does not prove GMod draws it right: that needs the game.
local ADDON = arg[1]
local ROOT = ADDON .. "gamemodes/" -- Lua paths are relative to gamemodes/ for a gamemode
local REALM = arg[2] or "client"
local calls = {}
local function count(name) return function(...) calls[name] = (calls[name] or 0) + 1 end end
CLIENT, SERVER = REALM == "client", REALM == "server"
GM = { FolderName = "simgolf" }
local hooks = {}
hook = { Add = function(ev, id, fn) hooks[ev .. "/" .. id] = fn end, Run = function() end }
concommand = { Add = function() end }
local function exists(p) local f = io.open(p) if f then f:close() return true end return false end
function include(p)
  local full = p:find("^simgolf/") and p or "simgolf/gamemode/" .. p
  return assert(loadfile(ROOT .. full))()
end
MsgC = function(...) local t = {...}; print("log: " .. tostring(t[#t-1])) end
Color = function(r,g,b,a) return {r,g,b,a} end; color_white = Color(255,255,255)
SysTime = os.clock; FrameTime = function() return 0.016 end
local function ls(dir) local out = {} local p = io.popen('ls -1 "' .. dir .. '" 2>/dev/null') for l in p:lines() do out[#out+1] = l end p:close() return out end
file = {
  Read = function() end, Write = function() end, CreateDir = function() end,
  Exists = function(p, where) if where == "LUA" then return exists(ROOT .. p) end return false end,
  Find = function(pattern, where)
    local dir, glob = pattern:match("^(.*/)([^/]*)$")
    local files, dirs = {}, {}
    for _, n in ipairs(ls(ROOT .. dir)) do
      local isdir = os.execute('test -d "' .. ROOT .. dir .. n .. '"') == 0
      if isdir then dirs[#dirs+1] = n elseif glob == "*" or (glob == "*.lua" and n:sub(-4) == ".lua") then files[#files+1] = n end
    end
    return files, dirs
  end,
}
string.GetPathFromFilename = function(p) return p:match("^(.*/)") or "" end
util = { Compress = function(s) return s end, Decompress = function(s) return s end, TableToJSON = function() return "{}" end, JSONToTable = function() return {} end }
net = { Receive = function() end }
ScrW = function() return 1920 end; ScrH = function() return 1080 end
Material = function(p) assert(exists(ADDON .. "materials/" .. p), "material missing: " .. p) return { Width = function() return 2048 end, Height = function() return 2048 end } end
surface = { SetDrawColor = count("SetDrawColor"), DrawRect = count("DrawRect"), CreateFont = count("CreateFont"), SetMaterial = count("SetMaterial"), DrawTexturedRect = count("DrawTexturedRect"), DrawTexturedRectUV = function(x, y, w, h, u0, v0, u1, v1) calls.DrawTexturedRectUV = (calls.DrawTexturedRectUV or 0) + 1; assert(u0 >= 0 and v0 >= 0 and u1 <= 1 and v1 <= 1 and u0 < u1 and v0 < v1, "texture coordinates out of range") end, PlaySound = count("PlaySound"), DrawPoly = function(poly) calls.DrawPoly = (calls.DrawPoly or 0) + 1; assert(#poly >= 3 and poly[1].x and poly[1].y, "polygon points") end, SetFont = count("SetFont"), GetTextSize = function(t) return #t * 8, 16 end }
draw = { SimpleText = count("SimpleText"), NoTexture = count("NoTexture") }
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP = 0, 1, 2, 3
KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_ESCAPE, KEY_ENTER, KEY_TAB = 88, 90, 89, 91, 65, 70, 64, 67
KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E = 33, 11, 29, 14, 27, 15
MOUSE_LEFT, MOUSE_RIGHT, MOUSE_MIDDLE = 107, 108, 109
MATERIAL_TRIANGLES, MATERIAL_CULLMODE_CCW, MATERIAL_CULLMODE_NONE = 2, 0, 2
local down = {}
input = { IsKeyDown = function(c) return down[c] end, GetKeyName = function(c) return ({ [KEY_Q] = "q", [3] = "2", [4] = "3", [5] = "4" })[c] or "x" end }
gui = { MouseX = function() return 960 end, MouseY = function() return 540 end }
function Vector(x, y, z) return { x, y, z } end
function Matrix() return { Translate = function() end, Scale = function() end } end
cam = { PushModelMatrix = count("PushModelMatrix"), PopModelMatrix = count("PopModelMatrix"), IgnoreZ = count("IgnoreZ") }
ErrorNoHalt = function(m) error(m) end
render = { SetMaterial = count("SetMaterial3D"), CullMode = count("CullMode"), OverrideDepthEnable = count("OverrideDepthEnable") }
local verts = 0
function Mesh() return { Draw = count("MeshDraw"), Destroy = function() end } end
mesh = { Begin = function(_, kind, prims) assert(kind == MATERIAL_TRIANGLES and prims == math.floor(prims) and prims <= 8000, "prims " .. prims) end,
  Position = function() verts = verts + 1 end, TexCoord = function() end, Color = function() end, AdvanceVertex = function() end, End = function() end }
function IsValid(x) return x ~= nil end
local panel
vgui = { Create = function() panel = { SetPos = function() end, SetSize = function() end, MakePopup = function() end,
  SetKeyboardInputEnabled = function() end, SetMouseInputEnabled = function() end, GetWide = function() return 1920 end,
  GetTall = function() return 1080 end, MouseCapture = function() end, Remove = function() end } return panel end }

if REALM == "client" then
	include("simgolf/gamemode/cl_init.lua")
	assert(#SimGolf.Platform.missing == 0, table.concat(SimGolf.Platform.missing, ","))
	hooks["InitPostEntity/simgolf.view"]()
	panel:Paint(1920, 1080)
	down[KEY_D] = true; panel:Think(); down[KEY_D] = nil
	panel:OnKeyCodePressed(KEY_Q)
	panel:OnMousePressed(MOUSE_LEFT); panel:OnCursorMoved(900, 500); panel:OnMouseReleased(MOUSE_LEFT)
	panel:OnMouseWheeled(1)
	panel:Paint(1920, 1080)
	-- the course tools: terrain (2), height (3), build (4), each used once at the screen's centre
	for _, key in ipairs({ 3, 4, 5 }) do
		panel:OnKeyCodePressed(key)
		panel:Paint(1920, 1080)
		panel:OnCursorMoved(960, 540)
		panel:OnMousePressed(MOUSE_LEFT); panel:OnCursorMoved(970, 545); panel:OnMouseReleased(MOUSE_LEFT)
		panel:OnMousePressed(MOUSE_RIGHT); panel:OnMouseReleased(MOUSE_RIGHT)
		panel:Paint(1920, 1080)
	end
	assert((calls.DrawPoly or 0) > 0, "cursor and icons drawn")
	assert(GM.HUDShouldDraw() == false, "HUD hidden")
	print(("vertices %d, meshes drawn %d, trees drawn %d, model matrix pushes %d"):format(verts, calls.MeshDraw or 0, calls.DrawTexturedRectUV or 0, calls.PushModelMatrix or 0))
	print("gmod client ok")
else
	local sent = 0
	function AddCSLuaFile() sent = sent + 1 end
	util.AddNetworkString = function() end
	OBS_MODE_ROAMING = 6
	include("simgolf/gamemode/init.lua")
	assert(#SimGolf.Platform.missing == 0, table.concat(SimGolf.Platform.missing, ","))
	assert(not pcall(SimGolf.Platform.drawRect))
	local packs = SimGolf.Platform.listPacks()
	assert(packs[1] == "free", "packs: " .. table.concat(packs, ","))
	local spawned = {}
	GM.PlayerSpawn(GM, { Spectate = function(_, m) spawned.mode = m end, StripWeapons = function() spawned.strip = true end })
	assert(spawned.mode == 6 and spawned.strip)
	print("gmod server ok, files sent to clients: " .. sent)
end
