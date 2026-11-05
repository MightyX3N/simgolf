-- The xorshift32 generator OpenSGolf uses (sg-core/src/rng.rs), so seeded results match the port.
-- Not the original game's generator, which is not decoded.

return function(Game)
	local bit = bit or require("bit") -- LuaJIT's bit library (GMod and LÖVE both run LuaJIT)
	local bxor, lshift, rshift = bit.bxor, bit.lshift, bit.rshift

	local Rng = {}
	Rng.__index = Rng

	function Rng.new(seed)
		return setmetatable({ s = (seed or 1) % 4294967296 }, Rng)
	end

	-- next 32-bit value, 0 .. 2^32 - 1
	function Rng:next()
		local s = self.s
		s = bxor(s, lshift(s, 13))
		s = bxor(s, rshift(s, 17))
		s = bxor(s, lshift(s, 5))
		s = s % 4294967296 -- bit ops give signed 32-bit results
		self.s = s
		return s
	end

	-- 0 .. 1 with 24 bits of precision
	function Rng:unit()
		return (self:next() % 16777216) / 16777216
	end

	-- 0 .. n - 1
	function Rng:range(n)
		return self:next() % n
	end

	return Rng
end
