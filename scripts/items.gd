class_name Items
extends RefCounted
## Przedmioty, narzędzia, jedzenie i przepisy. Bloki mają id < 100, przedmioty >= 100.

const STICK := 100
const WOOD_PICK := 101
const STONE_PICK := 102
const WOOD_SWORD := 103
const STONE_SWORD := 104
const WOOD_AXE := 105
const RAW_MEAT := 106
const COOKED_MEAT := 107
const CHARCOAL := 108

const CREATIVE_BLOCKS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 24, 40]

const NAMES := {
	1: "Trawa", 2: "Ziemia", 3: "Kamień", 4: "Piasek", 5: "Drewno", 6: "Liście",
	7: "Obsydian", 8: "Śnieg", 9: "Deski", 10: "Łóżko", 11: "Wełna", 12: "Piecyk", 13: "Skrzynia", 24: "Woda", 40: "Lawa",
	100: "Patyk", 101: "Drewniany kilof", 102: "Kamienny kilof",
	103: "Drewniany miecz", 104: "Kamienny miecz", 105: "Drewniana siekiera",
	106: "Surowe mięso", 107: "Pieczone mięso", 108: "Węgiel drzewny",
}
const LABELS := {
	100: "PAT", 101: "D.KIL", 102: "K.KIL", 103: "D.MIE", 104: "K.MIE",
	105: "D.SIE", 106: "MIĘ", 107: "PIE", 108: "WĘG",
}
const COLORS := {
	100: Color(0.6, 0.45, 0.25), 101: Color(0.75, 0.55, 0.3), 102: Color(0.6, 0.62, 0.68),
	103: Color(0.75, 0.55, 0.3), 104: Color(0.65, 0.67, 0.72), 105: Color(0.75, 0.55, 0.3),
	106: Color(0.9, 0.45, 0.5), 107: Color(0.65, 0.38, 0.2), 108: Color(0.12, 0.12, 0.14),
}
const TOOLS := {
	101: {"kind": "pick", "speed": 2.5, "dmg": 2.0},
	102: {"kind": "pick", "speed": 4.0, "dmg": 3.0},
	103: {"kind": "sword", "speed": 1.0, "dmg": 5.0},
	104: {"kind": "sword", "speed": 1.0, "dmg": 7.0},
	105: {"kind": "axe", "speed": 3.0, "dmg": 3.0},
}
const FOOD := {106: 3.0, 107: 8.0}      # ile HP leczy (20 HP = 10 serc)
const HARDNESS := {1: 0.6, 2: 0.5, 3: 2.0, 4: 0.5, 5: 1.2, 6: 0.2, 7: 12.0, 8: 0.3, 9: 1.0, 10: 0.3, 11: 0.4, 12: 2.0, 13: 1.0}
const RECIPES := [
	{"out": 9, "n": 4, "in": {5: 1}},
	{"out": 100, "n": 4, "in": {9: 2}},
	{"out": 101, "n": 1, "in": {9: 3, 100: 2}},
	{"out": 102, "n": 1, "in": {3: 3, 100: 2}},
	{"out": 103, "n": 1, "in": {9: 2, 100: 1}},
	{"out": 104, "n": 1, "in": {3: 2, 100: 1}},
	{"out": 105, "n": 1, "in": {9: 3, 100: 2}},
	{"out": 10, "n": 1, "in": {11: 3, 9: 3}},
	{"out": 12, "n": 1, "in": {3: 8}},
	{"out": 13, "n": 1, "in": {9: 8}},
]
# Piecyk: co z czego (każde pieczenie zużywa paliwo)
const SMELT := [
	{"in": 106, "out": 107},
	{"in": 5, "out": 108},
]
# Paliwo: ile przedmiotów upiecze jedna sztuka
const FUEL := {100: 1, 9: 2, 5: 3, 108: 8}


static func item_name(id: int) -> String:
	return NAMES.get(id, "?")


static func is_block(id: int) -> bool:
	return id > 0 and id < 100


static func item_color(id: int) -> Color:
	if id in COLORS:
		return COLORS[id]
	if id in VoxelWorld.COLORS:
		var c: Color = VoxelWorld.COLORS[id]
		c.a = 1.0
		return c
	return Color.WHITE


static func tool_kind(id: int) -> String:
	var t: Dictionary = TOOLS.get(id, {})
	return t.get("kind", "")


static func attack_damage(id: int) -> float:
	var t: Dictionary = TOOLS.get(id, {})
	return t.get("dmg", 1.0)


static func block_tool(b: int) -> String:
	match b:
		3, 7, 12:
			return "pick"
		5, 9, 13:
			return "axe"
	return ""


static func break_time(b: int, tool_id: int) -> float:
	var hardness: float = HARDNESS.get(b, 1.0)
	if b == 7 and tool_id != STONE_PICK:
		return 30.0
	var t: Dictionary = TOOLS.get(tool_id, {})
	var mult := 1.0
	var need := block_tool(b)
	if need != "" and t.get("kind", "") == need:
		mult = t["speed"]
	return hardness / mult


static func drop_for(b: int) -> int:
	if b == 1:
		return 2
	if b == 6:
		return 0
	return b


static func recipe_text(r: Dictionary) -> String:
	var parts: Array[String] = []
	for id in r["in"]:
		parts.append("%d %s" % [r["in"][id], item_name(id)])
	return ", ".join(parts)
