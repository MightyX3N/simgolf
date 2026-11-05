-- Event bus shared by the game and its addons. Works the same on every platform.
--
--   Hook.Add("ShotResult", "my_addon", function(golfer, shot) ... end)
--   Hook.Remove("ShotResult", "my_addon")
--   local result = Hook.Run("ShotResult", golfer, shot)
--
-- Run calls handlers in the order they were added. The first handler that returns a non-nil value
-- stops the run and that value is returned (same rule as GMod's hook.Run).
-- A platform may set Hook.forward to also pass every event on (GMod forwards to hook.Run).

local Hook = {}

local events = {} -- event name -> { list = { {id, fn}, ... }, index = { id -> position } }

function Hook.Add(event, id, fn)
	assert(type(event) == "string", "Hook.Add: event must be a string")
	assert(id ~= nil, "Hook.Add: id is required")
	assert(type(fn) == "function", "Hook.Add: fn must be a function")

	local e = events[event]
	if not e then
		e = { list = {}, index = {} }
		events[event] = e
	end

	local pos = e.index[id]
	if pos then
		e.list[pos].fn = fn -- re-adding an id replaces its handler and keeps its place
	else
		e.list[#e.list + 1] = { id = id, fn = fn }
		e.index[id] = #e.list
	end
end

function Hook.Remove(event, id)
	local e = events[event]
	if not e or not e.index[id] then return end

	table.remove(e.list, e.index[id])
	e.index = {}
	for i, h in ipairs(e.list) do
		e.index[h.id] = i
	end
end

function Hook.Run(event, ...)
	local e = events[event]
	if e then
		-- copy so handlers may add or remove hooks while running
		local list = {}
		for i, h in ipairs(e.list) do list[i] = h end

		for _, h in ipairs(list) do
			local a, b, c, d, f = h.fn(...)
			if a ~= nil then return a, b, c, d, f end
		end
	end

	if Hook.forward then
		return Hook.forward(event, ...)
	end
end

function Hook.GetTable()
	local out = {}
	for name, e in pairs(events) do
		out[name] = {}
		for _, h in ipairs(e.list) do out[name][h.id] = h.fn end
	end
	return out
end

return Hook
