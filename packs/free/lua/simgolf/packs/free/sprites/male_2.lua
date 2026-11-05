-- Sprites from Flics/male. Sheet: frame f (0-based, view-major: f = view * fpv + frame) is at
-- column f % cols, row floor(f / cols), w x h each. ax, ay: the ground point inside a frame. ms: frame time.
-- mask: bit set per stored view. shadow: key of the matching shadow sprite (drawn first, black with alpha).
return {
	["male/malesss_sitsqshadow"] = { file = "sprites/male/malesss_sitsqshadow.png", w = 25, h = 28, views = 4, fpv = 11, frames = 44, cols = 11, ax = 10, ay = 21, ms = 83, mask = 15 },
	["male/malesss_sitting"] = { file = "sprites/male/malesss_sitting.png", w = 45, h = 41, views = 4, fpv = 21, frames = 84, cols = 21, ax = 18, ay = 31, ms = 83, mask = 15, shadow = "male/malesss_sittingshadow" },
	["male/malesss_sittingshadow"] = { file = "sprites/male/malesss_sittingshadow.png", w = 45, h = 41, views = 4, fpv = 21, frames = 84, cols = 21, ax = 18, ay = 31, ms = 83, mask = 15 },
	["male/malesss_sq"] = { file = "sprites/male/malesss_sq.png", w = 28, h = 32, views = 8, fpv = 18, frames = 144, cols = 18, ax = 8, ay = 28, ms = 83, mask = 255, shadow = "male/malesss_sqshadow" },
	["male/malesss_sqshadow"] = { file = "sprites/male/malesss_sqshadow.png", w = 28, h = 32, views = 8, fpv = 18, frames = 144, cols = 18, ax = 8, ay = 28, ms = 83, mask = 255 },
	["male/malesss_successa"] = { file = "sprites/male/malesss_successa.png", w = 51, h = 50, views = 8, fpv = 21, frames = 168, cols = 21, ax = 20, ay = 40, ms = 83, mask = 255, shadow = "male/malesss_successashadow" },
	["male/malesss_successashadow"] = { file = "sprites/male/malesss_successashadow.png", w = 51, h = 50, views = 8, fpv = 21, frames = 168, cols = 21, ax = 20, ay = 40, ms = 83, mask = 255 },
	["male/malesss_tiredwalk"] = { file = "sprites/male/malesss_tiredwalk.png", w = 43, h = 34, views = 8, fpv = 18, frames = 144, cols = 18, ax = 17, ay = 26, ms = 83, mask = 255, shadow = "male/malesss_tiredwalkshadow" },
	["male/malesss_tiredwalkshadow"] = { file = "sprites/male/malesss_tiredwalkshadow.png", w = 43, h = 34, views = 8, fpv = 18, frames = 144, cols = 18, ax = 17, ay = 26, ms = 83, mask = 255 },
}
