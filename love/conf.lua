function love.conf(t)
	t.identity = "simgolf" -- save folder name; matches core/info.lua id
	t.version = "11.4"     -- runs on LÖVE 11.4+ and 12
	t.window.title = "SimGolf (working title)"
	t.window.width = 1280
	t.window.height = 720
	t.window.resizable = true
	t.window.minwidth = 960
	t.window.minheight = 540
end
