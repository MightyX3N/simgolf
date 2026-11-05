-- data/buildings.toml and data/amenities.toml: objects the player places (OpenSGolf built-in values).
-- Merge rules: an entry with the id of an earlier one replaces the fields it gives; `remove = true` deletes it.
--   id          the entry's id (fixed for built-in entries)
--   kind        the exe's object kind 0..19 (fixed)
--   name        the name the build panel shows
--   footprint   edge of the square footprint, in tiles (1..8)
--   price       price in the game's money, a multiple of 100 (an upgrade costs price x (level + 2) / 2)
-- Converted from OpenSGolf's buildings.toml by tools/convert_data.py; edit the values here.

return {
	building = {
		{ id = "home-site", kind = 5, name = "Home Site", footprint = 2, price = 1000 },
		{ id = "putting-green", kind = 6, name = "Putting Green", footprint = 3, price = 10000 },
		{ id = "snack-bar", kind = 7, name = "Snack Bar", footprint = 2, price = 15000 },
		{ id = "pro-shop", kind = 8, name = "Pro Shop", footprint = 2, price = 20000 },
		{ id = "swim-club", kind = 9, name = "Swim Club", footprint = 3, price = 30000 },
		{ id = "driving-range", kind = 10, name = "Driving Range", footprint = 5, price = 25000 },
		{ id = "cart-garage", kind = 11, name = "Cart Garage", footprint = 2, price = 40000 },
		{ id = "marina", kind = 12, name = "Marina", footprint = 2, price = 100000 },
		{ id = "resort-hotel", kind = 13, name = "Resort Hotel", footprint = 4, price = 250000 },
		{ id = "airstrip", kind = 14, name = "Airstrip", footprint = 6, price = 500000 },
		{ id = "clubhouse", kind = 15, name = "Clubhouse", footprint = 4, price = 20000 },
	},
}
