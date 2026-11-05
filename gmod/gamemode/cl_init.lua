-- Client entry point.

include("shared.lua")

-- Phase 1 check that the core and platform layer run: a status line drawn through the Platform interface.
-- Replaced by the fullscreen course view in the next step.
hook.Add("HUDPaint", "simgolf.status", function()
	local P, info = SimGolf.Platform, SimGolf.Info
	P.drawRect(16, 16, 330, 34, 12, 20, 16, 220)
	P.drawText(("%s %s · API %d · %s"):format(info.name, info.version, info.apiVersion, P.name), 16, 28, 25, 238, 245, 240, 255, 0)
end)
