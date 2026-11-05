-- data/terrain.toml: tile types (OpenSGolf built-in values, written by `sgtool dump-data`).
-- Merge rules: an entry with the id of an earlier one replaces the fields it gives; `remove = true` deletes it.
-- Money is the game's money as shown (a multiple of 100).
--   id          the entry's id (fixed for built-in entries)
--   tile        tile id 0..27 (fixed); 0..22 are the exe's types, 23..27 paint-only ids with a price only
--   name        the type's name in the exe's table (tract descriptions)
--   cost        price of painting one tile
--   clear_cost  price of clearing one tile of it before painting or building over it
--   view        what one such tile next to a home site adds to the lot's view
--   bounce      0..15, how high a ball bounces on it
--   roll        0..15, how far a ball rolls on it
--   hazard      the lie, -1 (green) .. 8: how hard a shot from it is
--   walk        walking cost for golfers and staff (also the draw layer)
--   class       blend class (0 tee, 1 green, 2 fairway, 4 rough, 7 sand, 8 waste, 13 trees, 17 water, 18 out of bounds)
--   group       scenery group: which trees, rocks or grasses are drawn on it
--   flags       shape flags: 1 level table, 2 flat at the lowest corner, 4 flat at the highest, 8 height 0
-- Converted from OpenSGolf's terrain.toml by tools/convert_data.py; edit the values here.

return {
	terrain = {
		{ id = "tee", tile = 0, name = "tees", cost = 500, clear_cost = 0, view = 5, bounce = 4, roll = 3, hazard = 0, walk = 2, class = 0, group = 0, flags = 4 },
		{ id = "green", tile = 1, name = "green", cost = 1000, clear_cost = 0, view = 10, bounce = 3, roll = 3, hazard = -1, walk = 1, class = 1, group = 1, flags = 0 },
		{ id = "fairway", tile = 2, name = "fairway", cost = 300, clear_cost = 0, view = 3, bounce = 4, roll = 3, hazard = 0, walk = 1, class = 2, group = 2, flags = 0 },
		{ id = "firm-fairway", tile = 3, name = "firm fairway", cost = 300, clear_cost = 0, view = 3, bounce = 5, roll = 4, hazard = 0, walk = 1, class = 2, group = 15, flags = 0 },
		{ id = "rough", tile = 4, name = "rough", cost = 100, clear_cost = 0, view = 1, bounce = 2, roll = 2, hazard = 1, walk = 2, class = 4, group = 3, flags = 0 },
		{ id = "deep-rough", tile = 5, name = "deep rough", cost = 200, clear_cost = 0, view = 2, bounce = 1, roll = 2, hazard = 2, walk = 3, class = 4, group = 17, flags = 0 },
		{ id = "mounds", tile = 6, name = "mound", cost = 400, clear_cost = 0, view = 4, bounce = 2, roll = 2, hazard = 2, walk = 3, class = 4, group = 4, flags = 0 },
		{ id = "sand-trap", tile = 7, name = "sand trap", cost = 600, clear_cost = 0, view = 6, bounce = 1, roll = 1, hazard = 3, walk = 4, class = 7, group = 5, flags = 0 },
		{ id = "waste-bunker", tile = 8, name = "waste bunker", cost = 400, clear_cost = 0, view = 4, bounce = 2, roll = 2, hazard = 2, walk = 3, class = 8, group = 5, flags = 0 },
		{ id = "pot-bunker", tile = 9, name = "pot bunker", cost = 800, clear_cost = 0, view = 8, bounce = 1, roll = 1, hazard = 5, walk = 5, class = 7, group = 5, flags = 2 },
		{ id = "ravine", tile = 10, name = "ravine", cost = 1000, clear_cost = 0, view = 10, bounce = 2, roll = 2, hazard = 5, walk = 3, class = 4, group = 6, flags = 0 },
		{ id = "brush", tile = 11, name = "brush", cost = 400, clear_cost = 0, view = 4, bounce = 1, roll = 1, hazard = 3, walk = 3, class = 4, group = 6, flags = 0 },
		{ id = "rocks", tile = 12, name = "rocks", cost = 400, clear_cost = 500, view = 4, bounce = 5, roll = 1, hazard = 3, walk = 4, class = 4, group = 9, flags = 256 },
		{ id = "tree", tile = 13, name = "tree", cost = 1000, clear_cost = 500, view = 10, bounce = 2, roll = 2, hazard = 4, walk = 4, class = 13, group = 7, flags = 1024 },
		{ id = "pine-tree", tile = 14, name = "pine tree", cost = 1000, clear_cost = 500, view = 10, bounce = 2, roll = 2, hazard = 4, walk = 4, class = 13, group = 7, flags = 512 },
		{ id = "palm-tree", tile = 15, name = "palm tree", cost = 1000, clear_cost = 500, view = 10, bounce = 2, roll = 2, hazard = 4, walk = 4, class = 13, group = 6, flags = 512 },
		{ id = "elm-tree", tile = 16, name = "elm tree", cost = 2500, clear_cost = 1000, view = 25, bounce = 2, roll = 2, hazard = 4, walk = 4, class = 13, group = 7, flags = 1024 },
		{ id = "water", tile = 17, name = "water", cost = 5000, clear_cost = 1000, view = 50, bounce = 0, roll = 0, hazard = 8, walk = 16, class = 17, group = 8, flags = 2 },
		{ id = "wetlands", tile = 18, name = "wetlands", cost = 200, clear_cost = 5000, view = 2, bounce = 2, roll = 1, hazard = 3, walk = 4, class = 4, group = 14, flags = 8 },
		{ id = "marsh", tile = 19, name = "marsh", cost = 600, clear_cost = 10000, view = 6, bounce = 2, roll = 1, hazard = 3, walk = 4, class = 4, group = 14, flags = 8 },
		{ id = "out-of-bounds", tile = 20, name = "out of bounds", cost = 0, clear_cost = 0, view = 10, bounce = 2, roll = 2, hazard = 8, walk = 12, class = 18, group = 6, flags = 0 },
		{ id = "home-site", tile = 21, name = "building", cost = 0, clear_cost = 0, view = 0, bounce = 2, roll = 2, hazard = 4, walk = 4, class = 18, group = 16, flags = 5 },
		{ id = "building", tile = 22, name = "building", cost = 0, clear_cost = 0, view = 0, bounce = 2, roll = 2, hazard = 4, walk = 4, class = 18, group = 16, flags = 5 },
		{ id = "water-middle", tile = 23, name = "water", cost = 5000, clear_cost = 1000 },
		{ id = "water-deep", tile = 24, name = "deep water", cost = 5000, clear_cost = 1000 },
		{ id = "water-shallow-desert", tile = 25, name = "desert water", cost = 5000, clear_cost = 1000 },
		{ id = "tricky-green", tile = 26, name = "tricky green", cost = 1000, clear_cost = 0 },
		{ id = "sand-bunker", tile = 27, name = "sand trap", cost = 600, clear_cost = 0 },
	},
}
