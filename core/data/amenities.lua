-- data/buildings.toml and data/amenities.toml: objects the player places (OpenSGolf built-in values).
-- Merge rules: an entry with the id of an earlier one replaces the fields it gives; `remove = true` deletes it.
--   id          the entry's id (fixed for built-in entries)
--   kind        the exe's object kind 0..19 (fixed)
--   name        the name the build panel shows
--   footprint   edge of the square footprint, in tiles (1..8)
--   price       price in the game's money, a multiple of 100 (an upgrade costs price x (level + 2) / 2)
-- Converted from OpenSGolf's amenities.toml by tools/convert_data.py; edit the values here.

return {
	amenity = {
		{ id = "pathway", kind = 0, name = "Pathway", footprint = 1, price = 100 },
		{ id = "benches", kind = 1, name = "Benches", footprint = 1, price = 200 },
		{ id = "flower-bed", kind = 2, name = "Flower Bed", footprint = 1, price = 500 },
		{ id = "ball-washer", kind = 3, name = "Ball Washer", footprint = 1, price = 5000 },
		{ id = "landmark", kind = 4, name = "Landmark", footprint = 1, price = 1500 },
		{ id = "willow-tree", kind = 16, name = "Willow Tree", footprint = 1, price = 2500 },
		{ id = "tv-tower", kind = 17, name = "TV Tower", footprint = 1, price = 1000 },
		{ id = "tv-booth", kind = 18, name = "TV Booth", footprint = 1, price = 1000 },
		{ id = "scenic-bridge", kind = 19, name = "Scenic Bridge", footprint = 1, price = 10000 },
	},
}
