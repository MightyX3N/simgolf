-- Terrain atlas layout. Each theme's atlas (terrain/<theme>.lua) is 2048 x 2048 with 66 x 66 cells, 31 to a row;
-- cell i holds a 64 x 64 texture at x = (i % 31) * 66 + 1, y = floor(i / 31) * 66 + 1.
return { atlasSize = 2048, cell = 66, cols = 31, tex = 64 }
