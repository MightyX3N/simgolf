-- data/properties.toml: the sixteen properties of the world map (OpenSGolf built-in values).
--   id          the entry's id (fixed for built-in entries)
--   index       place in the list, 0..15 (fixed): 0..9 on the map's left arc, 10..15 on the right
--   name        the place, as the map shows it
--   course      the course's own name
--   bonus       the property's bonus, as the map shows it
--   map_x/map_y the marker on the world map art
--   theme       parkland | desert | tropical | links
--   coast       inland (a square of land) | coast (the sea along one side) | island (water all round)
--   relief      gentle | rolling | hilly
-- Converted from OpenSGolf's properties.toml by tools/convert_data.py; edit the values here.

return {
	property = {
		{ id = "monterey", index = 0, name = "Monterey", course = "Ocean's Edge", bonus = "Scenic Cypress", map_x = 53, map_y = 226, theme = "parkland", coast = "coast", relief = "rolling" },
		{ id = "san-diego", index = 1, name = "San Diego", course = "Dolphin Coast", bonus = "Dolphins", map_x = 53, map_y = 244, theme = "parkland", coast = "coast", relief = "gentle" },
		{ id = "rocky-mtns", index = 2, name = "Rocky Mtns.", course = "Jurassic Springs", bonus = "Free Hotel", map_x = 92, map_y = 226, theme = "parkland", coast = "inland", relief = "hilly" },
		{ id = "las-vegas", index = 3, name = "Las Vegas", course = "Ace in the Hole", bonus = "Fun, Fun, Fun", map_x = 73, map_y = 241, theme = "desert", coast = "inland", relief = "gentle" },
		{ id = "phoenix", index = 4, name = "Phoenix", course = "Coyote Flats", bonus = "Free Spa", map_x = 70, map_y = 262, theme = "desert", coast = "inland", relief = "gentle" },
		{ id = "hawaii", index = 5, name = "Hawaii", course = "Flamingo Shores", bonus = "Scenic Waterfall", map_x = 26, map_y = 327, theme = "tropical", coast = "coast", relief = "rolling" },
		{ id = "oahu", index = 6, name = "Oahu", course = "Island Palms", bonus = "Japanese Garden", map_x = 23, map_y = 311, theme = "tropical", coast = "island", relief = "gentle" },
		{ id = "nova-scotia", index = 7, name = "Nova Scotia", course = "Windy Point", bonus = "Scenic Lighthouse", map_x = 158, map_y = 250, theme = "links", coast = "coast", relief = "rolling" },
		{ id = "northeast", index = 8, name = "Northeast", course = "Ravenwood Farms", bonus = "Civil War Battlefield", map_x = 138, map_y = 254, theme = "parkland", coast = "inland", relief = "rolling" },
		{ id = "carolina", index = 9, name = "Carolina", course = "Christmas Pines", bonus = "Free Putting Green", map_x = 133, map_y = 272, theme = "parkland", coast = "inland", relief = "gentle" },
		{ id = "ireland", index = 10, name = "Ireland", course = "County Kincaide", bonus = "Leprechauns", map_x = 262, map_y = 232, theme = "links", coast = "inland", relief = "hilly" },
		{ id = "scotland", index = 11, name = "Scotland", course = "Harold's Keep", bonus = "Free Castle", map_x = 266, map_y = 222, theme = "links", coast = "coast", relief = "gentle" },
		{ id = "wales", index = 12, name = "Wales", course = "Thistle Runes", bonus = "Stonehenge", map_x = 272, map_y = 239, theme = "links", coast = "island", relief = "rolling" },
		{ id = "spain", index = 13, name = "Spain", course = "Sangria Bay", bonus = "Scenic Vineyards", map_x = 275, map_y = 270, theme = "desert", coast = "coast", relief = "rolling" },
		{ id = "florida", index = 14, name = "Florida", course = "Ocean Grove", bonus = "Free Pro Shop", map_x = 125, map_y = 298, theme = "tropical", coast = "coast", relief = "gentle" },
		{ id = "jamaica", index = 15, name = "Jamaica", course = "Scorpion Cove", bonus = "Scenic Statues", map_x = 129, map_y = 342, theme = "tropical", coast = "inland", relief = "rolling" },
	},
}
