extends Node
## Autoload "Game": ustawienia świata, zapis i wczytywanie.

const SAVE_DIR := "user://worlds/"

var world_name := "Mój świat"
var seed_text := ""
var seed_value := 0
var creative := true
var water_level := 14
var mountain := 1.0
var lava := 0.5
var base_sim := 1.0
const SETTINGS_PATH := "user://settings.cfg"
const GFX_NAMES := ["Niska", "Średnia", "Wysoka"]
const MSAA_NAMES := ["Wyłączone", "2x", "4x"]

var render_dist := 3   # zasięg widzenia w chunkach (2..6)
var shadows := false   # cienie od słońca
var msaa := 0          # 0 wył, 1 = 2x, 2 = 4x
var experimental_made := false   # świat eksperymentalny tworzymy tylko raz
const EXPERIMENTAL_NAME := "Świat eksperymentalny"
var save_chunks: Dictionary = {}   # Vector2i -> PackedByteArray (zmienione chunki)
var save_data: Dictionary = {}


func _ready() -> void:
	load_settings()


func apply_preset(p: int) -> void:
	match p:
		0:
			render_dist = 2
			shadows = false
			msaa = 0
		1:
			render_dist = 4
			shadows = false
			msaa = 0
		_:
			render_dist = 5
			shadows = true
			msaa = 1


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	render_dist = clampi(int(cf.get_value("gfx", "render_dist", 3)), 2, 6)
	shadows = bool(cf.get_value("gfx", "shadows", false))
	msaa = clampi(int(cf.get_value("gfx", "msaa", 0)), 0, 2)
	experimental_made = bool(cf.get_value("meta", "experimental_made", false))


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("gfx", "render_dist", render_dist)
	cf.set_value("gfx", "shadows", shadows)
	cf.set_value("gfx", "msaa", msaa)
	cf.set_value("meta", "experimental_made", experimental_made)
	cf.save(SETTINGS_PATH)


## Przy pierwszym uruchomieniu tworzy gotowy świat eksperymentalny
## (tryb kreatywny, wysokie góry, dużo lawy, szybkie zmiany świata).
## Jeśli go usuniesz, nie pojawi się ponownie.
func ensure_experimental() -> void:
	if experimental_made:
		return
	experimental_made = true
	save_settings()
	var path := SAVE_DIR + EXPERIMENTAL_NAME.validate_filename() + ".sav"
	if FileAccess.file_exists(path):
		return
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_var({
		"name": EXPERIMENTAL_NAME,
		"seed_text": "eksperyment",
		"seed": seed_from_text("eksperyment"),
		"creative": true,
		"water": 14,
		"mountain": 1.6,
		"lava": 1.0,
		"sim": 2.0,
		"chunks": {},
	})
	f.close()


func seed_from_text(t: String) -> int:
	t = t.strip_edges()
	if t.is_empty():
		return randi() & 0x7fffffff
	if t.is_valid_int():
		return absi(int(t)) & 0x7fffffff
	return t.hash() & 0x7fffffff


func start_new(n: String, seed_txt: String, is_creative: bool, water: int, mount: float, lav: float, sim: float) -> void:
	world_name = n.strip_edges() if not n.strip_edges().is_empty() else "Świat"
	seed_text = seed_txt
	seed_value = seed_from_text(seed_txt)
	creative = is_creative
	water_level = water
	mountain = mount
	lava = lav
	base_sim = sim
	save_chunks = {}
	save_data = {}


func list_worlds() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(SAVE_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".sav"):
			out.append(f.get_basename())
	return out


func write_save(d: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + world_name.validate_filename() + ".sav"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(d)
	f.close()
	return true


func load_world(fname: String) -> bool:
	var path := SAVE_DIR + fname + ".sav"
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var d = f.get_var()
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return false
	save_data = d
	world_name = d.get("name", fname)
	seed_text = d.get("seed_text", "")
	seed_value = d.get("seed", 0)
	creative = d.get("creative", true)
	water_level = d.get("water", 14)
	mountain = d.get("mountain", 1.0)
	lava = d.get("lava", 0.5)
	base_sim = d.get("sim", 1.0)
	save_chunks = d.get("chunks", {})
	return true


func delete_world(fname: String) -> void:
	DirAccess.remove_absolute(SAVE_DIR + fname + ".sav")
