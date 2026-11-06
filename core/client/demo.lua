-- A scripted start for screenshots and quick looks (LÖVE --demo): three holes laid out on open ground near the clubhouse,
-- a snack bar and a ball washer, through the same course commands the tools use.

return function(Game)
	local L = Game.require("land")

	return function(App)
		local c = App.course
		local land = c.land
		local N = 50

		-- a w x h block of open, owned ground with nothing on it
		local function open(a0, b0, w, h)
			for a = a0, a0 + w - 1 do
				for b = b0, b0 + h - 1 do
					if a < 1 or b < 1 or a >= N - 1 or b >= N - 1 or not land:inPlay(a, b) then return false end
					local i = a * N + b
					local ty = land.ty[i]
					if bit.band(land.flags[i], 0x8400) ~= 0 or ty == 17 or ty == 22 or ty == 21 then return false end
				end
			end
			return true
		end

		-- the block nearest the clubhouse
		local function near(w, h, avoid)
			local ca, cb = land.clubhouse[1] + 2, land.clubhouse[2] + 2
			local best, bd
			for a = 1, N - w - 1 do
				for b = 1, N - h - 1 do
					local clash = false
					for _, r in ipairs(avoid) do
						if a < r[1] + r[3] + 1 and r[1] < a + w + 1 and b < r[2] + r[4] + 1 and r[2] < b + h + 1 then clash = true break end
					end
					if not clash and open(a, b, w, h) then
						local d = (a + w / 2 - ca) ^ 2 + (b + h / 2 - cb) ^ 2
						if not bd or d < bd then best, bd = { a, b, w, h }, d end
					end
				end
			end
			return best
		end

		local used = { { land.clubhouse[1], land.clubhouse[2], 4, 4 } }
		for hole = 1, 3 do
			local len = ({ 7, 10, 8 })[hole]
			local r = near(3, len, used)
			if not r then break end
			used[#used + 1] = r
			local a, b = r[1], r[2]
			local fair = {}
			for y = b + 1, b + len - 2 do
				for x = a, a + 2 do fair[#fair + 1] = { x, y } end
			end
			c:paint(fair, 2, 0)
			c:paint({ { a + 1, b } }, 0, 0)
			local green = {}
			for x = a, a + 2 do
				for y = b + len - 2, b + len - 1 do green[#green + 1] = { x, y } end
			end
			c:paint(green, 1, 0)
			c:paint({ { a + 2, b + len - 4 } }, 7, 13)
			c:openHole()
		end
		for _, kind in ipairs({ 7, 3 }) do
			local size = L.kinds()[kind].size
			local r = near(size, size, used)
			if r then
				used[#used + 1] = r
				c:build(kind, r[1], r[2], 0)
			end
		end
		local hill = near(5, 5, used)
		if hill then c:elevate(2, hill[1] + 2, hill[2] + 2, true) c:elevate(2, hill[1] + 2, hill[2] + 2, true) end
		App:takeEvents()
	end
end
