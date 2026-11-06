-- Standalone LÖVE entry point. Built layout: main.lua, conf.lua, core/, platform/love/, packs/ (tools/build.py).
--
-- Options (after the game folder or .love file):
--   --screenshot FILE   draw a few frames, save the window to FILE (PNG, absolute path) and quit
--   --view X,Z,ZOOM,ROT start the camera at world X, Z with ZOOM and ROT quarter turns
--   --seed N            the deal's seed (default: the clock)
--   --slot N            which of the sixteen offered properties (0..15, default 0)
--   --sandbox           a sandbox game
--   --demo              build a hole and some buildings first (for screenshots)
--   --tool NAME         start with a tool picked: paint, elevation, build

local function loadFile(path)
	return love.filesystem.load(path)()
end

local opts = {}

local function parseArgs(args)
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "--screenshot" then opts.screenshot, i = args[i + 1], i + 1
		elseif a == "--view" then opts.view, i = args[i + 1], i + 1
		elseif a == "--seed" then opts.seed, i = tonumber(args[i + 1]), i + 1
		elseif a == "--slot" then opts.slot, i = tonumber(args[i + 1]), i + 1
		elseif a == "--sandbox" then opts.sandbox = true
		elseif a == "--demo" then opts.demo = true
		elseif a == "--tool" then opts.tool, i = args[i + 1], i + 1
		end
		i = i + 1
	end
end

local App
local frames = 0

function love.load(args)
	parseArgs(args or {})
	local info = loadFile("core/info.lua")
	local impl = loadFile("platform/love/platform.lua")(info.id)
	local boot = loadFile("core/init.lua")

	-- Global entry point for addons, same name as in GMod.
	SimGolf = boot(loadFile, impl)
	love.window.setTitle(info.name)

	App = SimGolf.require("client/app")
	App:init({ seed = opts.seed or os.time(), slot = opts.slot, sandbox = opts.sandbox })
	if opts.demo then SimGolf.require("client/demo")(App) end
	if opts.tool then App:setTool(opts.tool) end
	if opts.view then
		local x, z, zoom, rot = opts.view:match("^([-%d.]+),([-%d.]+),([%d.]+),(%d+)$")
		if x then
			App.camera.x, App.camera.z = tonumber(x), tonumber(z)
			App.camera:setZoom(tonumber(zoom))
			App.camera:setRotation(tonumber(rot))
		end
	end
end

function love.update(dt)
	App:update(dt)
end

function love.draw()
	local w, h = love.graphics.getDimensions()
	App:draw(w, h)

	frames = frames + 1
	if opts.screenshot and frames == 3 then
		love.graphics.captureScreenshot(function(img)
			local data = img:encode("png"):getString()
			local f = assert(io.open(opts.screenshot, "wb"))
			f:write(data)
			f:close()
			print("screenshot: " .. opts.screenshot)
			love.event.quit()
		end)
	end
end

-- LÖVE key and button names already match the core's ("w", "left", "space"; buttons 1 left, 2 right, 3 middle)
local BUTTONS = { "left", "right", "middle" }

function love.keypressed(key) App:keyPressed(key) end
function love.mousepressed(x, y, b) App:mousePressed(x, y, BUTTONS[b] or tostring(b)) end
function love.mousereleased(x, y, b) App:mouseReleased(x, y, BUTTONS[b] or tostring(b)) end
function love.mousemoved(x, y) App:mouseMoved(x, y) end
function love.wheelmoved(_, dy)
	local w, h = love.graphics.getDimensions()
	App:wheel(dy, w, h)
end
