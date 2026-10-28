class_name BlockTex
extends RefCounted
## Tekstury bloków generowane w kodzie (16x16 pikseli, jeden atlas 128x64).

const TS := 16
const COLS := 8
const ROWS := 4

enum { GRASS_TOP, GRASS_SIDE, DIRT, STONE, SAND, LOG_SIDE, LOG_TOP, LEAVES, OBSIDIAN, SNOW, PLANKS, WATER, LAVA, BED_TOP, BED_SIDE, WOOL, FURNACE_TOP, FURNACE_SIDE, CHEST_TOP, CHEST_SIDE, COUNT }

static var _tex: ImageTexture = null
static var _icons: ImageTexture = null
const ICON_SCALE := 4


## Która kafelka dla danego bloku i ściany (0 góra, 1 dół, 2..5 boki).
static func tile_for(b: int, f: int) -> int:
	match b:
		1:
			return GRASS_TOP if f == 0 else (DIRT if f == 1 else GRASS_SIDE)
		2:
			return DIRT
		3:
			return STONE
		4:
			return SAND
		5:
			return LOG_TOP if f < 2 else LOG_SIDE
		6:
			return LEAVES
		7:
			return OBSIDIAN
		8:
			return SNOW
		9:
			return PLANKS
		10:
			return BED_TOP if f == 0 else (PLANKS if f == 1 else BED_SIDE)
		11:
			return WOOL
		12:
			return FURNACE_TOP if f < 2 else FURNACE_SIDE
		13:
			return CHEST_TOP if f < 2 else CHEST_SIDE
	return STONE


## Prostokąt kafelki w atlasie (0..1) - do rysowania ikon w interfejsie.
static func tile_rect(t: int) -> Rect2:
	return Rect2(float(t % COLS) / COLS, float(t / COLS) / ROWS, 1.0 / COLS, 1.0 / ROWS)


static func atlas() -> ImageTexture:
	if _tex != null:
		return _tex
	var img := Image.create(TS * COLS, TS * ROWS, false, Image.FORMAT_RGBA8)
	for t in range(COUNT):
		var ox := (t % COLS) * TS
		var oy := (t / COLS) * TS
		for y in range(TS):
			for x in range(TS):
				img.set_pixel(ox + x, oy + y, _px(t, x, y))
	_tex = ImageTexture.create_from_image(img)
	var big := img.duplicate() as Image
	big.resize(img.get_width() * ICON_SCALE, img.get_height() * ICON_SCALE, Image.INTERPOLATE_NEAREST)
	_icons = ImageTexture.create_from_image(big)
	return _tex


## Powiększony (4x, bez wygładzania) atlas do ikon w interfejsie.
static func icon_atlas() -> ImageTexture:
	atlas()
	return _icons


static func _h(x: int, y: int, t: int) -> float:
	var h: int = ((x + 11) * 374761393 + (y + 7) * 668265263 + (t + 3) * 1274126177) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1103515245) & 0x7fffffff
	return float(h % 1000) / 1000.0


static func _px(t: int, x: int, y: int) -> Color:
	var n := _h(x, y, t)
	match t:
		GRASS_TOP:
			return Color(0.36, 0.66, 0.22) * (0.8 + 0.4 * n) + Color(0, 0, 0, 1)
		GRASS_SIDE:
			var d := 3 + int(_h(x, 0, 99) * 3.0)
			if y < d:
				return _px(GRASS_TOP, x, y)
			return _px(DIRT, x, y)
		DIRT:
			var c := Color(0.47, 0.33, 0.21) * (0.78 + 0.4 * n)
			if n > 0.93:
				c = Color(0.55, 0.52, 0.5) * (0.8 + 0.3 * _h(y, x, 5))
			c.a = 1.0
			return c
		STONE:
			var blot := _h(x / 2, y / 2, 31)
			var v := 0.46 + 0.14 * blot + 0.07 * n
			if n > 0.96:
				v -= 0.16
			return Color(v, v, v + 0.01, 1.0)
		SAND:
			var c2 := Color(0.87, 0.81, 0.55) * (0.92 + 0.12 * n)
			c2.a = 1.0
			return c2
		LOG_SIDE:
			var s := _h(x, 0, 41)
			var c3 := Color(0.40, 0.28, 0.15) * (0.72 + 0.45 * s + 0.1 * n)
			c3.a = 1.0
			return c3
		LOG_TOP:
			var ring := int(maxf(absf(float(x) - 7.5), absf(float(y) - 7.5)))
			if ring >= 7:
				return _px(LOG_SIDE, x, y)
			var base := Color(0.72, 0.55, 0.32) if ring % 2 == 0 else Color(0.6, 0.44, 0.25)
			base = base * (0.94 + 0.1 * n)
			base.a = 1.0
			return base
		LEAVES:
			var c4 := Color(0.16, 0.46, 0.13) * (0.6 + 0.7 * n)
			if n > 0.86:
				c4 = Color(0.08, 0.28, 0.08)
			c4.a = 1.0
			return c4
		OBSIDIAN:
			var c5 := Color(0.12, 0.07, 0.2) * (0.7 + 0.6 * n)
			if n > 0.92:
				c5 = Color(0.34, 0.2, 0.52)
			c5.a = 1.0
			return c5
		SNOW:
			var v2 := 0.94 + 0.06 * n
			return Color(v2 * 0.97, v2 * 0.99, v2, 1.0)
		PLANKS:
			var row := y / 4
			var shade := 0.88 + 0.2 * _h(0, row, 61)
			var c6 := Color(0.72, 0.55, 0.3) * (shade + 0.06 * n)
			if y % 4 == 3:
				c6 = c6 * 0.7
			if x == (row % 2) * 8:
				c6 = c6 * 0.78
			c6.a = 1.0
			return c6
		WATER:
			var w := 0.86 + 0.14 * _h(x / 2, y, 71)
			return Color(w, w, w, 1.0)
		LAVA:
			var b2 := _h(x / 2, y / 2, 81)
			var c7 := Color(1.0, 0.35 + 0.35 * b2, 0.05, 1.0)
			if n > 0.82:
				c7 = Color(1.0, 0.88, 0.25, 1.0)
			elif n < 0.1:
				c7 = Color(0.55, 0.12, 0.02, 1.0)
			return c7
		BED_TOP:
			if y < 5:
				var p := 0.93 + 0.05 * n
				return Color(p, p, p * 0.97, 1.0)
			var c8 := Color(0.72, 0.1, 0.1) * (0.92 + 0.12 * n)
			if y == 5:
				c8 = c8 * 0.8
			c8.a = 1.0
			return c8
		BED_SIDE:
			if y < 8:
				var c9 := Color(0.72, 0.1, 0.1) * (0.92 + 0.12 * n)
				if y == 7:
					c9 = Color(0.9, 0.88, 0.86)
				c9.a = 1.0
				return c9
			return _px(PLANKS, x, y)
		WOOL:
			var wv := 0.96 if y % 2 == 0 else 0.9
			if (x + (y / 2) * 3) % 5 == 0:
				wv -= 0.05
			wv *= 0.97 + 0.04 * n
			return Color(wv, wv, wv, 1.0)
		FURNACE_TOP:
			var fv := 0.34 + 0.1 * _h(x / 2, y / 2, 91) + 0.05 * n
			if x == 0 or y == 0 or x == 15 or y == 15:
				fv -= 0.1
			return Color(fv, fv, fv + 0.01, 1.0)
		FURNACE_SIDE:
			var sv := 0.42 + 0.1 * _h(x / 2, y / 2, 92) + 0.05 * n
			var c10 := Color(sv, sv, sv + 0.01, 1.0)
			if x >= 3 and x <= 12 and y >= 7 and y <= 13:
				c10 = Color(0.07, 0.06, 0.06, 1.0)
				if y >= 10 and n > 0.45:
					c10 = Color(1.0, 0.45 + 0.4 * _h(x, y, 93), 0.08, 1.0)
			elif x >= 5 and x <= 10 and y >= 3 and y <= 4:
				c10 = Color(0.12, 0.12, 0.13, 1.0)
			return c10
		CHEST_TOP:
			var c11 := Color(0.58, 0.4, 0.17) * (0.9 + 0.15 * n)
			if x == 0 or y == 0 or x == 15 or y == 15:
				c11 = Color(0.32, 0.2, 0.08)
			c11.a = 1.0
			return c11
		CHEST_SIDE:
			var c12 := Color(0.58, 0.4, 0.17) * (0.88 + 0.15 * n)
			if x == 0 or x == 15 or y == 0 or y == 15:
				c12 = Color(0.32, 0.2, 0.08)
			elif y == 6 or y == 7:
				c12 = Color(0.36, 0.23, 0.1)
			if x >= 7 and x <= 8 and y >= 5 and y <= 9:
				c12 = Color(0.85, 0.8, 0.35)
			c12.a = 1.0
			return c12
	return Color(1, 0, 1, 1)
