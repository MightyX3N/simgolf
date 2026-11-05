-- data/economy.toml: the money rules (OpenSGolf built-in values). Money is the game's money, multiples of 100.
--   start_funds            what a normal game starts with, before the property's price
--   sandbox_funds          what a sandbox game starts with
--   offer_prices           the sixteen offer slots of the world map, cheapest first
--   firing_cost            what firing an employee costs
--   hole_maintenance       maintenance per active hole, charged with the wages every 1024 / (difficulty + 2) ticks
--   debt_interest_percent  interest on debt at each month start
--   rank_holes             holes for Daily Fee, Country Club, Championship (fewer than the first: Municipal)
-- The port's extras (all off by default; docs/PLAYING.md, OpenSGolf extras):
--   staff_limit                   most employees (the original's 20)
--   staff_limit_high              most employees with Higher staff limits (at most 63)
--   hardcore_staff_limit          most employees with Hardcore economy (Higher staff limits wins over it)
--   hardcore_wage_percent         wages under Hardcore, in percent of the normal wage
--   hardcore_maintenance_percent  hole maintenance under Hardcore, in percent
--   hardcore_land_percent         prices of properties and tracts under Hardcore, in percent
--   hardcore_interest_percent     interest on debt at each month start under Hardcore
--   hardcore_fee_cap              the most a golfer pays for a hole under Hardcore
--   hardcore_mood_penalty         what every bad moment costs a golfer's mood on top under Hardcore
-- [economy.weather]: Weather that matters (sg_core::weather; any field may be left out):
--   rain_drag, snow_drag, heat_drag  a rolling ball's extra drag on tee, fairway and green, per mille of its speed a tick
--                                    (wet ground at full wetness, snow lying, a full heat wave; negative: it runs on)
--   lush_bounce_percent              how high balls bounce on the soft ground the day after rain
--   rain/snow/heat_turnout_percent   the share of the time new golfers keep coming (heat: at midday)
--   rain/snow/heat_mood_percent      golfers in a hundred teeing off in it who start a point less happy
--   snow_lover_percent               golfers in a hundred who start a point happier in the snow
--   heat_thirst_percent              hunger and thirst grow this often in a heat wave, in percent of the usual interval
--   heat_percent                     heat-wave days in a hundred desert summer days
--   storm_percent                    thunderstorm days in a hundred heavy-rain days
--   storm_ticks                      how long a storm holds play, in game ticks (about 11 a second)
--   storm_spend                      what each golfer sheltering from it spends on food and drink
-- Converted from OpenSGolf's economy.toml by tools/convert_data.py; edit the values here.

return {
	economy = {
		start_funds = 100000,
		sandbox_funds = 1000000,
		offer_prices = { 50000, 60000, 70000, 80000, 120000, 150000, 200000, 250000, 300000, 400000, 500000, 600000, 700000, 800000, 900000, 1000000 },
		firing_cost = 2500,
		hole_maintenance = 100,
		debt_interest_percent = 2,
		rank_holes = { 6, 10, 18 },
		staff_limit = 20,
		staff_limit_high = 40,
		hardcore_staff_limit = 12,
		hardcore_wage_percent = 150,
		hardcore_maintenance_percent = 200,
		hardcore_land_percent = 150,
		hardcore_interest_percent = 5,
		hardcore_fee_cap = 600,
		hardcore_mood_penalty = 1,
		weather = { rain_drag = 12, snow_drag = 30, heat_drag = -6, lush_bounce_percent = 70, rain_turnout_percent = 90, snow_turnout_percent = 75, heat_turnout_percent = 85, rain_mood_percent = 30, snow_mood_percent = 50, snow_lover_percent = 15, heat_mood_percent = 25, heat_thirst_percent = 75, heat_percent = 45, storm_percent = 40, storm_ticks = 240, storm_spend = 100 },
	},
}
