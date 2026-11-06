-- Client entry point: a fullscreen panel that shows the course view and forwards input to the core's App.

include("shared.lua")

local P = SimGolf.Platform
local App

-- the course view replaces the HUD
function GM:HUDShouldDraw() return false end
function GM:HUDDrawTargetID() end

-- input and updates report errors once each instead of every frame
local reported = {}
local function safe(what, fn, ...)
	local ok, err = pcall(fn, App, ...)
	if not ok and not reported[tostring(err)] then
		reported[tostring(err)] = true
		ErrorNoHalt("[simgolf] " .. what .. ": " .. tostring(err) .. "\n")
	end
end

local function openView()
	if IsValid(SimGolf.panel) then SimGolf.panel:Remove() end

	App = SimGolf.require("client/app")
	App:init({ seed = os.time() })

	local panel = vgui.Create("Panel")
	SimGolf.panel = panel
	panel:SetPos(0, 0)
	panel:SetSize(ScrW(), ScrH())
	panel:MakePopup()
	panel:SetKeyboardInputEnabled(true)
	panel:SetMouseInputEnabled(true)

	function panel:Paint(w, h)
		-- Draw with no depth test or depth writes: everything is drawn far to near at z = 0, and with the depth buffer on
		-- a sprite's see-through corners hide parts of the sprites drawn after it.
		cam.IgnoreZ(true)
		render.OverrideDepthEnable(true, false)
		local ok, err = pcall(App.draw, App, w, h)
		render.OverrideDepthEnable(false, false)
		cam.IgnoreZ(false)
		if not ok then ErrorNoHalt("[simgolf] draw: " .. tostring(err) .. "\n") end
		return true
	end

	function panel:Think()
		if self:GetWide() ~= ScrW() or self:GetTall() ~= ScrH() then self:SetSize(ScrW(), ScrH()) end
		safe("update", App.update, FrameTime())
	end

	function panel:OnMousePressed(code)
		self:MouseCapture(true)
		safe("mouse", App.mousePressed, gui.MouseX(), gui.MouseY(), P.MOUSE_NAMES[code] or tostring(code))
	end

	function panel:OnMouseReleased(code)
		self:MouseCapture(false)
		safe("mouse", App.mouseReleased, gui.MouseX(), gui.MouseY(), P.MOUSE_NAMES[code] or tostring(code))
	end

	function panel:OnCursorMoved(x, y)
		safe("mouse", App.mouseMoved, x, y)
	end

	function panel:OnMouseWheeled(delta)
		safe("wheel", App.wheel, delta, self:GetWide(), self:GetTall())
		return true
	end

	function panel:OnKeyCodePressed(code)
		safe("key", App.keyPressed, P.keyName(code))
	end
end

hook.Add("InitPostEntity", "simgolf.view", openView)

-- `simgolf_view` reopens the view (e.g. after closing it with the console open)
concommand.Add("simgolf_view", openView)
