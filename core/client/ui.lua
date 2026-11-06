-- A small immediate-mode UI drawn through the Platform: panels, buttons, labels, toasts. Widgets are declared while
-- drawing; the clickable ones are remembered for the next mouse press, so a click lands on what was on screen.
-- The look follows the design previews: dark translucent panels, a green accent, light text.

return function(Game)
	local P = Game.Platform
	local floor = math.floor

	local UI = {}
	UI.__index = UI

	UI.COLORS = {
		panel = { 16, 22, 20, 228 },
		panelLight = { 30, 40, 36, 236 },
		line = { 255, 255, 255, 22 },
		text = { 236, 242, 238, 255 },
		dim = { 160, 176, 168, 255 },
		accent = { 92, 196, 124, 255 },
		accentDim = { 92, 196, 124, 60 },
		hover = { 255, 255, 255, 18 },
		warn = { 236, 112, 96, 255 },
		gold = { 236, 200, 110, 255 },
	}
	local C = UI.COLORS

	function UI.new()
		return setmetatable({ widgets = {}, next = {}, mx = -1, my = -1, toasts = {}, cards = {} }, UI)
	end

	function UI:beginFrame(mx, my)
		self.widgets, self.next = self.next, {}
		self.mx, self.my = mx or -1, my or -1
	end

	local function inRect(x, y, r) return x >= r[1] and y >= r[2] and x < r[1] + r[3] and y < r[2] + r[4] end

	function UI:hovered(x, y, w, h)
		return inRect(self.mx, self.my, { x, y, w, h })
	end

	-- an area that takes the mouse (so clicks on it never reach the course)
	function UI:block(x, y, w, h)
		self.next[#self.next + 1] = { x, y, w, h }
	end

	function UI:panel(x, y, w, h, col)
		col = col or C.panel
		P.drawRect(x, y, w, h, col[1], col[2], col[3], col[4])
		P.drawRect(x, y, w, 1, C.line[1], C.line[2], C.line[3], C.line[4])
		self:block(x, y, w, h)
	end

	function UI:text(s, size, x, y, col, align)
		col = col or C.text
		P.drawText(s, size, x, y, col[1], col[2], col[3], col[4], align or 0)
	end

	function UI:textWidth(s, size) return P.textWidth(s, size) end

	-- a button: o.label, o.sub (second line), o.active, o.disabled, o.icon(x, y, w, h), o.onClick, o.tip, o.size
	function UI:button(x, y, w, h, o)
		local hot = self:hovered(x, y, w, h)
		local bg = o.active and C.accentDim or (hot and not o.disabled) and C.hover or nil
		if o.bg then bg = o.bg end
		if bg then P.drawRect(x, y, w, h, bg[1], bg[2], bg[3], bg[4]) end
		if o.active then P.drawRect(x, y + h - 2, w, 2, C.accent[1], C.accent[2], C.accent[3], 255) end
		local col = o.disabled and C.dim or (o.color or C.text)
		local size = o.size or 15
		if o.icon then
			local ih = o.label and h - size - 10 or h - 8
			o.icon(x + 4, y + 4, w - 8, ih, o.disabled)
			if o.label then self:text(o.label, size, x + w / 2, y + h - size - 5, col, 1) end
		elseif o.label then
			local ty = o.sub and (y + h / 2 - size - 1) or (y + (h - size) / 2 - 1)
			self:text(o.label, size, x + w / 2, ty, col, 1)
			if o.sub then self:text(o.sub, size - 3, x + w / 2, y + h / 2 + 1, o.subColor or C.dim, 1) end
		end
		if hot and o.tip then self.tip = o.tip end
		self.next[#self.next + 1] = { x, y, w, h, onClick = (not o.disabled) and o.onClick or nil, onRight = o.onRight }
		return hot
	end

	-- the tooltip of the button under the mouse, drawn last
	function UI:drawTip(sw, sh)
		local tip = self.tip
		self.tip = nil
		if not tip then return end
		local w = self:textWidth(tip, 14) + 16
		local x = math.min(sw - w - 4, self.mx + 14)
		local y = math.max(4, self.my - 30)
		P.drawRect(x, y, w, 24, 8, 12, 10, 240)
		self:text(tip, 14, x + 8, y + 4, C.text)
	end

	-- whether the mouse is over any widget of the last frame
	function UI:over(x, y)
		for i = #self.widgets, 1, -1 do
			if inRect(x, y, self.widgets[i]) then return true end
		end
		return false
	end

	-- a press: the top-most widget under the mouse gets it; returns whether the UI took it
	function UI:press(x, y, button)
		for i = #self.widgets, 1, -1 do
			local wd = self.widgets[i]
			if inRect(x, y, wd) then
				if button == "left" and wd.onClick then wd.onClick() end
				if button == "right" and wd.onRight then wd.onRight() end
				return true
			end
		end
		return false
	end

	------------------------------------------------------------------------------------------------ toasts and cards

	function UI:toast(text, now, col)
		self.toasts[#self.toasts + 1] = { text = text, until_ = now + 3.5, col = col }
	end

	-- a message card (a hole opened, a building unlocked)
	function UI:card(text, now)
		self.cards[#self.cards + 1] = { text = text, until_ = now + 8 }
		while #self.cards > 3 do table.remove(self.cards, 1) end
	end

	-- word wrap for drawText
	function UI:wrap(text, size, width)
		local lines, line = {}, ""
		for word in tostring(text):gmatch("%S+") do
			local try = line == "" and word or (line .. " " .. word)
			if line ~= "" and self:textWidth(try, size) > width then
				lines[#lines + 1] = line
				line = word
			else
				line = try
			end
		end
		if line ~= "" then lines[#lines + 1] = line end
		return lines
	end

	function UI:drawNotices(sw, sh, now, top, bottom)
		-- cards: top centre under the bar
		local y = top
		local keep = {}
		for _, c in ipairs(self.cards) do
			if c.until_ > now then
				keep[#keep + 1] = c
				local lines = self:wrap(c.text, 16, 520)
				local h = #lines * 21 + 20
				local x = floor(sw / 2 - 280)
				P.drawRect(x, y, 560, h, C.panel[1], C.panel[2], C.panel[3], C.panel[4])
				P.drawRect(x, y, 4, h, C.gold[1], C.gold[2], C.gold[3], 255)
				for i, l in ipairs(lines) do self:text(l, 16, x + 20, y + 10 + (i - 1) * 21, C.text) end
				self:block(x, y, 560, h)
				local cc = c
				self.next[#self.next].onClick = function() cc.until_ = 0 end
				y = y + h + 8
			end
		end
		self.cards = keep
		-- toasts: bottom centre over the drawer
		keep = {}
		y = bottom
		for i = #self.toasts, 1, -1 do
			local t = self.toasts[i]
			if t.until_ > now then
				table.insert(keep, 1, t)
				local w = self:textWidth(t.text, 16) + 32
				y = y - 40
				local x = floor(sw / 2 - w / 2)
				P.drawRect(x, y, w, 34, 10, 14, 12, 235)
				local col = t.col or C.warn
				P.drawRect(x, y + 32, w, 2, col[1], col[2], col[3], 255)
				self:text(t.text, 16, sw / 2, y + 8, C.text, 1)
			end
		end
		self.toasts = keep
	end

	return UI
end
