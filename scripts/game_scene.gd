extends Node3D
## Scena gry: składa świat, gracza, HUD i menu pauzy.

const DAY_LEN := 1200.0   # 10 min dnia + 10 min nocy
const SIM_STEPS := [0.0, 1.0, 3.0, 10.0]
const SIM_NAMES := ["STOP", "1x", "3x", "10x"]

var world: VoxelWorld
var player: Player
var hud: HUD
var env: Environment
var menu_layer: CanvasLayer
var sim_btn: Button
var dist_btn: Button
var shadow_btn: Button
var msaa_btn: Button
var sun: DirectionalLight3D
var fog_base := 0.05
var craft_layer: CanvasLayer
var inv_layer: CanvasLayer
var inv_box: VBoxContainer
var _icon_cache := {}
var furn_layer: CanvasLayer
var furn_box: VBoxContainer
var furn_status: Label
var chest_layer: CanvasLayer
var chest_box: VBoxContainer
var chest_pos := Vector3i.ZERO
var smelt_t := 0.0
var smelt_out := 0
var fuel_left := 0
const SMELT_TIME := 3.0
var craft_box: VBoxContainer
var mobs: MobManager
var day_time := 0.04
var sim_i := 1
var _autosave := 0.0


func _ready() -> void:
	var sd: Dictionary = Game.save_data
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.fog_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 48.0
	sun.shadow_normal_bias = 1.0
	add_child(sun)

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
		day_time = sd.get("day_time", 0.04)
		player.inventory = sd.get("inventory", {})
		world.chests = sd.get("chests", {})
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
	player.sleep_requested.connect(_on_sleep)
	player.furnace_requested.connect(func(): _open_furnace(true))
	player.chest_requested.connect(func(pos: Vector3i):
		chest_pos = pos
		_open_chest(true))
	hud.menu_pressed.connect(func(): _open_menu(true))
	hud.fly_pressed.connect(player.toggle_fly)
	hud.sim_pressed.connect(_cycle_sim)
	hud.craft_pressed.connect(func(): _open_craft(true))
	hud.inventory_pressed.connect(func(): _open_inventory(true))
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
	_build_inventory()
	var fp := _make_panel()
	furn_layer = fp[0]
	furn_box = fp[1]
	var cp := _make_panel()
	chest_layer = cp[0]
	chest_box = cp[1]
	if not Game.creative and not sd.has("player_pos"):
		hud.toast("Przytrzymaj palec na drzewie, żeby zebrać drewno")
	_update_sim_labels()
	_apply_gfx()


func _on_sleep(bed: Vector3i) -> void:
	player.spawn_point = Vector3(bed.x + 0.5, bed.y, bed.z + 0.5)
	if sin(day_time * TAU) < -0.05:
		day_time = 0.0
		hud.toast("Dobrze spałeś. Jest poranek, a łóżko to Twój nowy punkt odrodzenia")
	else:
		hud.toast("Punkt odrodzenia ustawiony. Spać można tylko w nocy")


func _process(delta: float) -> void:
	if smelt_out != 0:
		smelt_t -= delta
		if smelt_t <= 0.0:
			player.add_item(smelt_out, 1)
			smelt_out = 0
			if furn_layer.visible:
				_refresh_furnace()
		elif furn_status != null and furn_layer.visible:
			furn_status.text = "Pieczenie... %d%%" % int((1.0 - smelt_t / SMELT_TIME) * 100.0)
	if world.sim_speed > 0.0:
		day_time = fposmod(day_time + delta / DAY_LEN * minf(world.sim_speed, 3.0), 1.0)
	var sun_h := sin(day_time * TAU)
	var light := clampf(0.55 + sun_h * 0.6, 0.3, 1.0)
	var k := clampf(sun_h * 2.0 + 0.5, 0.0, 1.0)
	var sky := Color(0.03, 0.04, 0.10).lerp(Color(0.55, 0.78, 0.97), k)
	env.background_color = sky
	env.fog_light_color = sky
	# im wyżej gracz leci, tym rzadsza mgła (inaczej z lotu ptaka wszystko jest białe)
	env.fog_density = fog_base / (1.0 + maxf(0.0, player.position.y - 30.0) / 15.0)
	world.set_light(light)
	if Game.shadows:
		sun.light_energy = clampf(sun_h * 1.6, 0.0, 1.0) * 0.35
		sun.rotation = Vector3(-deg_to_rad(15.0 + 65.0 * clampf(sun_h, 0.0, 1.0)), day_time * TAU, 0.0)
	_autosave += delta
	if _autosave > 45.0:
		_autosave = 0.0
		save_game()


func _cycle_sim() -> void:
	sim_i = (sim_i + 1) % SIM_STEPS.size()
	world.sim_speed = Game.base_sim * SIM_STEPS[sim_i]
	_update_sim_labels()


func _cycle_dist() -> void:
	Game.render_dist = Game.render_dist + 1 if Game.render_dist < 6 else 2
	_apply_gfx()
	Game.save_settings()


func _toggle_shadows() -> void:
	Game.shadows = not Game.shadows
	_apply_gfx()
	Game.save_settings()


func _cycle_msaa() -> void:
	Game.msaa = (Game.msaa + 1) % 3
	_apply_gfx()
	Game.save_settings()


func _apply_gfx() -> void:
	var r := Game.render_dist
	world.set_render_distance(r)
	world.set_shadows(Game.shadows)
	sun.visible = Game.shadows
	fog_base = 1.8 / (r * 16.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if Game.shadows else Environment.AMBIENT_SOURCE_BG
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.3
	player.cam.far = maxf(60.0, (r + 2) * 16.0 + 16.0)
	get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][Game.msaa]
	if dist_btn != null:
		dist_btn.text = "Zasięg widzenia: %d" % r
		shadow_btn.text = "Cienie: " + ("włączone" if Game.shadows else "wyłączone")
		msaa_btn.text = "Wygładzanie: " + Game.MSAA_NAMES[Game.msaa]


func _update_sim_labels() -> void:
	hud.sim_label = SIM_NAMES[sim_i]
	if sim_btn != null:
		sim_btn.text = "Symulacja świata: " + SIM_NAMES[sim_i]


func save_game() -> void:
	var d := {
		"name": Game.world_name, "seed_text": Game.seed_text, "seed": Game.seed_value,
		"creative": Game.creative, "water": Game.water_level, "mountain": Game.mountain,
		"lava": Game.lava, "sim": Game.base_sim, "rdist": Game.render_dist,
		"player_pos": player.position, "player_yaw": player.rotation.y,
		"day_time": day_time, "inventory": player.inventory,
		"health": player.health, "slots": player.slots, "spawn_point": player.spawn_point,
		"chunks": world.collect_modified(), "chests": world.chests,
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


# ---------------------------------------------------------------- ekwipunek (EQ)
func _build_inventory() -> void:
	inv_layer = CanvasLayer.new()
	inv_layer.layer = 9
	inv_layer.visible = false
	add_child(inv_layer)
	var th := Theme.new()
	th.default_font_size = 24
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.theme = th
	inv_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	dim.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(1280, 0)
	scroll.add_child(center)
	inv_box = VBoxContainer.new()
	inv_box.add_theme_constant_override("separation", 10)
	center.add_child(inv_box)


func _open_inventory(open: bool) -> void:
	inv_layer.visible = open
	hud.active = not open
	hud.reset_input()
	player.frozen = open
	if open:
		_refresh_inventory()


func _item_icon(id: int) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var tex: Texture2D
	if Items.is_block(id):
		var t := BlockTex.tile_for(id, 2)
		var k := VoxelWorld.fluid_kind(id)
		if k == VoxelWorld.WATER:
			t = BlockTex.WATER
		elif k == VoxelWorld.LAVA:
			t = BlockTex.LAVA
		var ts := BlockTex.TS * BlockTex.ICON_SCALE
		var at := AtlasTexture.new()
		at.atlas = BlockTex.icon_atlas()
		at.region = Rect2((t % BlockTex.COLS) * ts, (t / BlockTex.COLS) * ts, ts, ts)
		tex = at
	else:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Items.item_color(id))
		tex = ImageTexture.create_from_image(img)
	_icon_cache[id] = tex
	return tex


func _inv_button(text: String, id: int, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	if id != 0:
		b.icon = _item_icon(id)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 48)
	return b


func _assign_slot(id: int) -> void:
	var cur := player.slots.find(id)
	var old: int = player.slots[hud.selected]
	if cur >= 0 and cur != hud.selected:
		player.slots[cur] = old
	player.slots[hud.selected] = id
	_refresh_inventory()


func _refresh_inventory() -> void:
	for c in inv_box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "Ekwipunek: dotknij przedmiot, a trafi do zaznaczonego slotu (%d)" % (hud.selected + 1)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(900, 0)
	inv_box.add_child(title)
	var ids: Array = []
	for id in player.inventory:
		if player.inventory[id] > 0:
			ids.append(id)
	ids.sort()
	if ids.is_empty():
		var empty := Label.new()
		empty.text = "Pusto. Zbieraj drewno z drzew i kop bloki."
		inv_box.add_child(empty)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for id in ids:
		var b := _inv_button("%s  x%d" % [Items.item_name(id), player.inventory[id]], id, Vector2(222, 70))
		b.pressed.connect(func(): _assign_slot(id))
		grid.add_child(b)
	inv_box.add_child(grid)
	var hl := Label.new()
	hl.text = "Pasek (dotknij slot, żeby go wybrać):"
	inv_box.add_child(hl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in range(9):
		var sid: int = player.slots[i]
		var sb := _inv_button(str(i + 1), sid, Vector2(94, 70))
		if i == hud.selected:
			sb.modulate = Color(1.0, 0.92, 0.35)
		sb.pressed.connect(func():
			hud.selected = i
			_refresh_inventory())
		row.add_child(sb)
	inv_box.add_child(row)
	var close := Button.new()
	close.text = "Zamknij"
	close.custom_minimum_size = Vector2(700, 64)
	close.pressed.connect(func(): _open_inventory(false))
	inv_box.add_child(close)


func _make_panel() -> Array:
	var layer := CanvasLayer.new()
	layer.layer = 9
	layer.visible = false
	add_child(layer)
	var th := Theme.new()
	th.default_font_size = 24
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.theme = th
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	dim.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(1280, 0)
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	return [layer, box]


func _clear(box: VBoxContainer) -> void:
	for c in box.get_children():
		c.queue_free()


func _label(box: VBoxContainer, t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(900, 0)
	box.add_child(l)
	return l


func _close_btn(box: VBoxContainer, fn: Callable) -> void:
	var close := Button.new()
	close.text = "Zamknij"
	close.custom_minimum_size = Vector2(700, 64)
	close.pressed.connect(fn)
	box.add_child(close)


# ---------------------------------------------------------------- piecyk
func _open_furnace(open: bool) -> void:
	furn_layer.visible = open
	hud.active = not open
	hud.reset_input()
	player.frozen = open
	if open:
		_refresh_furnace()


func _take_fuel(exclude: int) -> bool:
	var ids: Array = Items.FUEL.keys()
	ids.sort_custom(func(a, b): return Items.FUEL[a] < Items.FUEL[b])
	for id in ids:
		if id != exclude and player.inventory.get(id, 0) > 0:
			player.take_item(id, 1)
			fuel_left += Items.FUEL[id]
			return true
	return false


func _start_smelt(r: Dictionary) -> void:
	if smelt_out != 0 or player.inventory.get(r["in"], 0) < 1:
		return
	if fuel_left <= 0 and not _take_fuel(r["in"]):
		hud.toast("Brak paliwa (drewno, deski, patyki lub węgiel)")
		return
	player.take_item(r["in"], 1)
	fuel_left -= 1
	smelt_out = r["out"]
	smelt_t = SMELT_TIME
	_refresh_furnace()


func _refresh_furnace() -> void:
	_clear(furn_box)
	_label(furn_box, "Piecyk")
	_label(furn_box, "Paliwo: starczy na %d pieczeń. Paliwo to drewno, deski, patyki lub węgiel drzewny." % fuel_left)
	furn_status = _label(furn_box, "Pieczenie... 0%" if smelt_out != 0 else "Wybierz, co upiec:")
	for r in Items.SMELT:
		var b := _inv_button("%s  →  %s   (masz %d)" % [Items.item_name(r["in"]), Items.item_name(r["out"]), player.inventory.get(r["in"], 0)], r["in"], Vector2(700, 70))
		b.disabled = smelt_out != 0 or player.inventory.get(r["in"], 0) < 1
		b.pressed.connect(func(): _start_smelt(r))
		furn_box.add_child(b)
	_close_btn(furn_box, func(): _open_furnace(false))


# ---------------------------------------------------------------- skrzynia
func _open_chest(open: bool) -> void:
	chest_layer.visible = open
	hud.active = not open
	hud.reset_input()
	player.frozen = open
	if open:
		if not world.chests.has(chest_pos):
			world.chests[chest_pos] = {}
		_refresh_chest()


func _chest_take(id: int) -> void:
	var cont: Dictionary = world.chests[chest_pos]
	player.give_silent(id, cont.get(id, 0))
	cont.erase(id)
	_refresh_chest()


func _chest_put(id: int) -> void:
	var n: int = player.inventory.get(id, 0)
	if n <= 0:
		return
	player.take_item(id, n)
	var cont: Dictionary = world.chests[chest_pos]
	cont[id] = cont.get(id, 0) + n
	_refresh_chest()


func _item_grid(items: Dictionary, fn: Callable) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var ids: Array = items.keys()
	ids.sort()
	for id in ids:
		if items[id] <= 0:
			continue
		var b := _inv_button("%s  x%d" % [Items.item_name(id), items[id]], id, Vector2(222, 70))
		b.pressed.connect(func(): fn.call(id))
		grid.add_child(b)
	return grid


func _refresh_chest() -> void:
	_clear(chest_box)
	_label(chest_box, "Skrzynia: dotknij przedmiot, żeby przenieść cały stos")
	_label(chest_box, "W skrzyni:")
	var cont: Dictionary = world.chests.get(chest_pos, {})
	if cont.is_empty():
		_label(chest_box, "(pusto)")
	else:
		chest_box.add_child(_item_grid(cont, _chest_take))
	_label(chest_box, "Twoje przedmioty:")
	if player.inventory.is_empty():
		_label(chest_box, "(pusto)")
	else:
		chest_box.add_child(_item_grid(player.inventory, _chest_put))
	_close_btn(chest_box, func(): _open_chest(false))


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
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)
	var title := Label.new()
	title.text = "Pauza"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_mb("Wznów", func(): _open_menu(false)))
	box.add_child(_mb("Zapisz", save_game))
	dist_btn = _mb("", _cycle_dist)
	box.add_child(dist_btn)
	shadow_btn = _mb("", _toggle_shadows)
	box.add_child(shadow_btn)
	msaa_btn = _mb("", _cycle_msaa)
	box.add_child(msaa_btn)
	sim_btn = _mb("", _cycle_sim)
	box.add_child(sim_btn)
	box.add_child(_mb("Zapisz i wyjdź do menu", func():
		save_game()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))


func _mb(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(460, 56)
	b.pressed.connect(cb)
	return b


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if player != null and world != null:
			save_game()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if furn_layer != null and furn_layer.visible:
			_open_furnace(false)
		elif chest_layer != null and chest_layer.visible:
			_open_chest(false)
		elif inv_layer != null and inv_layer.visible:
			_open_inventory(false)
		elif craft_layer != null and craft_layer.visible:
			_open_craft(false)
		elif menu_layer != null:
			_open_menu(not menu_layer.visible)
