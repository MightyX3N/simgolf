-- Standalone LÖVE entry point. Built layout: main.lua, conf.lua, core/, platform/love/ (tools/build.py).

local function loadFile(path)
	return love.filesystem.load(path)()
end

function love.load()
	local info = loadFile("core/info.lua")
	local impl = loadFile("platform/love/platform.lua")(info.id)
	local boot = loadFile("core/init.lua")

	-- Global entry point for addons, same name as in GMod.
	SimGolf = boot(loadFile, impl)
	love.window.setTitle(info.name)
end

function love.draw()
	local P, info = SimGolf.Platform, SimGolf.Info
	love.graphics.clear(76 / 255, 138 / 255, 63 / 255)

	-- Phase 1 check that the core and platform layer run; replaced by the course view.
	P.drawRect(16, 16, 330, 34, 12, 20, 16, 220)
	P.drawText(("%s %s · API %d · %s"):format(info.name, info.version, info.apiVersion, P.name), 16, 28, 25, 238, 245, 240, 255, 0)
end
