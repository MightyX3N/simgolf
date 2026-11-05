-- data/staff.toml: kinds of employee (OpenSGolf built-in values).
--   id                the entry's id (fixed for built-in entries)
--   kind              0 Club Pro, 1 Ranger, 2 Groundskeeper, 3 Soda Vendor (fixed)
--   name              the kind's name
--   wage              wage per pay interval (the hire panel shows it per week), a multiple of 100
--   wage_experienced  the same for an experienced employee
-- Converted from OpenSGolf's staff.toml by tools/convert_data.py; edit the values here.

return {
	staff = {
		{ id = "club-pro", kind = 0, name = "Club Pro", wage = 300, wage_experienced = 700 },
		{ id = "ranger", kind = 1, name = "Ranger", wage = 200, wage_experienced = 300 },
		{ id = "groundskeeper", kind = 2, name = "Groundskeeper", wage = 200, wage_experienced = 400 },
		{ id = "soda-vendor", kind = 3, name = "Soda Vendor", wage = 200, wage_experienced = 500 },
	},
}
