extends Node3D
## Scena gry: składa świat, gracza, HUD i menu pauzy.

const DAY_LEN := 300.0
const SIM_STEPS := [0.0, 1.0, 3.0, 10.0]
const SIM_NAMES := ["STOP", "1x", "3x", "10x"]

var world: VoxelWorld
var player: Player
var hud: HUD
var env: Environment
var menu_layer: CanvasLayer
var sim_btn: Button
var craft_layer: CanvasLayer
var craft_box: VBoxContainer
var mobs: MobManager
var day_time := 0.3
var sim_i := 1
var _autosave := 0.0


func _ready() -> void:
	var sd: Dictionary = Game.save_data
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.fog_enabled = true
	env.fog_density = 0.022
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	world = VoxelWorld.new()
	add_child(world)
	world.setup(Game.seed_value, Game.water_level, Game.mountain, Game.lava)
	world.sim_speed = Game.base_sim * SIM_STEPS[sim_i]

	player = Player.new()
	player.creative = Game.creative
	add_child(player)
	player.world = world

	var spawn: Vector3
	if sd.has("player_pos"):
		spawn = sd["player_pos"]
		player.rotation.y = sd.get("player_yaw", 0.0)
		day_time = sd.get("day_time", 0.3)
		player.inventory = sd.get("inventory", {})
		player.health = sd.get("health", Player.MAX_HP)
		player.spawn_point = sd.get("spawn_point", spawn)
		world.ensure_around(spawn, 2)
	else:
		spawn = world.find_spawn()
		world.ensure_around(spawn, 2)
		spawn.y = world.surface_y(floori(spawn.x), floori(spawn.z)) + 1.01
		player.spawn_point = spawn
	player.position = spawn
	world.player_node = player

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HUD.new()
	layer.add_child(hud)
	hud.player = player
	player.hud = hud
	hud.menu_pressed.connect(func(): _open_menu(true))
	hud.fly_pressed.connect(player.toggle_fly)
	hud.sim_pressed.connect(_cycle_sim)
	hud.craft_pressed.connect(func(): _open_craft(true))
	hud.respawn_pressed.connect(player.respawn)
	if sd.has("slots"):
		player.slots = sd["slots"]
	else:
		player.init_slots()
	player.refill_slots()
	mobs = MobManager.new()
	add_child(mobs)
	mobs.world = world
	mobs.player = player
	_build_menu()
	_build_craft()
	if not Game.creative and not sd.has("player_pos"):
		hud.toast("Przytrzymaj palec na drzewie, żeby zebrać drewno")
	_update_sim_labels()


func _process(delta: float) -> void:
	if world.sim_speed > 0.0:
		day_time = fposmod(day_time + delta / DAY_LEN * minf(world.sim_speed, 3.0), 1.0)
	var sun := sin(day_time * TAU)
	var light := clampf(0.55 + sun * 0.6, 0.2, 1.0)
	var k := clampf(sun * 2.0 + 0.5, 0.0, 1.0)
	var sky := Color(0.03, 0.04, 0.10).lerp(Color(0.55, 0.78, 0.97), k)
	env.background_color = sky
	env.fog_light_color = sky
	world.set_light(light)
	_autosave += delta
	if _autosave > 45.0:
		_autosave = 0.0
		save_game()


func _cycle_sim() -> void:
	sim_i = (sim_i + 1) % SIM_STEPS.size()
	world.sim_speed = Game.base_sim * SIM_STEPS[sim_i]
	_update_sim_labels()


func _update_sim_labels() -> void:
	hud.sim_label = SIM_NAMES[sim_i]
	if sim_btn != null:
		sim_btn.text = "Symulacja świata: " + SIM_NAMES[sim_i]


func save_game() -> void:
	var d := {
		"name": Game.world_name, "seed_text": Game.seed_text, "seed": Game.seed_value,
		"creative": Game.creative, "water": Game.water_level, "mountain": Game.mountain,
		"lava": Game.lava, "sim": Game.base_sim,
		"player_pos": player.position, "player_yaw": player.rotation.y,
		"day_time": day_time, "inventory": player.inventory,
		"health": player.health, "slots": player.slots, "spawn_point": player.spawn_point,
		"chunks": world.collect_modified(),
	}
	Game.write_save(d)


func _open_menu(open: bool) -> void:
	menu_layer.visible = open
	hud.active = not open
	hud.reset_input()
	player.frozen = open


func _open_craft(open: bool) -> void:
	craft_layer.visible = open
	hud.active = not open
	hud.reset_input()
	player.frozen = open
	if open:
		_refresh_craft()


func _refresh_craft() -> void:
	for c in craft_box.get_children():
		c.queue_free()
	var have: Array[String] = []
	for id in player.inventory:
		if player.inventory[id] > 0:
			have.append("%s x%d" % [Items.item_name(id), player.inventory[id]])
	var l := Label.new()
	l.text = "Masz: " + (", ".join(have) if not have.is_empty() else "nic")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(700, 0)
	craft_box.add_child(l)
	for r in Items.RECIPES:
		var b := Button.new()
		b.text = "%s x%d   (%s)" % [Items.item_name(r["out"]), r["n"], Items.recipe_text(r)]
		b.custom_minimum_size = Vector2(700, 64)
		b.disabled = not player.can_craft(r)
		b.pressed.connect(func():
			player.craft(r)
			_refresh_craft())
		craft_box.add_child(b)
	var close := Button.new()
	close.text = "Zamknij"
	close.custom_minimum_size = Vector2(700, 64)
	close.pressed.connect(func(): _open_craft(false))
	craft_box.add_child(close)


func _build_craft() -> void:
	craft_layer = CanvasLayer.new()
	craft_layer.layer = 9
	craft_layer.visible = false
	add_child(craft_layer)
	var th := Theme.new()
	th.default_font_size = 26
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.theme = th
	craft_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	dim.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(1280, 0)
	scroll.add_child(center)
	craft_box = VBoxContainer.new()
	craft_box.add_theme_constant_override("separation", 8)
	center.add_child(craft_box)


func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 10
	menu_layer.visible = false
	add_child(menu_layer)
	var th := Theme.new()
	th.default_font_size = 30
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.theme = th
	menu_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Label.new()
	title.text = "Pauza"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_mb("Wznów", func(): _open_menu(false)))
	box.add_child(_mb("Zapisz", save_game))
	sim_btn = _mb("", _cycle_sim)
	box.add_child(sim_btn)
	box.add_child(_mb("Zapisz i wyjdź do menu", func():
		save_game()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))


func _mb(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(460, 66)
	b.pressed.connect(cb)
	return b


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if player != null and world != null:
			save_game()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if craft_layer != null and craft_layer.visible:
			_open_craft(false)
		elif menu_layer != null:
			_open_menu(not menu_layer.visible)
