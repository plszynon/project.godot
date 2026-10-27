extends Control
## Menu główne: tworzenie nowego świata (seed, tryb, suwaki) i lista zapisanych światów.

var name_edit: LineEdit
var seed_edit: LineEdit
var mode_opt: OptionButton
var s_water: HSlider
var s_mount: HSlider
var s_lava: HSlider
var s_sim: HSlider
var s_dist: HSlider
var gfx_opt: OptionButton
var shadow_chk: CheckBox
var msaa_opt: OptionButton
var saved_box: VBoxContainer


func _ready() -> void:
	var th := Theme.new()
	th.default_font_size = 26
	theme = th
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.11, 0.16)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	scroll.add_child(root)

	var title := Label.new()
	title.text = "ŻYWY ŚWIAT"
	title.add_theme_font_size_override("font_size", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# --- nowy świat
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	left.add_child(_label("Nowy świat"))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Nazwa świata"
	name_edit.text = "Mój świat"
	name_edit.custom_minimum_size = Vector2(0, 56)
	left.add_child(name_edit)
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "Seed (puste = losowy)"
	seed_edit.custom_minimum_size = Vector2(0, 56)
	left.add_child(seed_edit)
	mode_opt = OptionButton.new()
	mode_opt.add_item("Tryb kreatywny")
	mode_opt.add_item("Tryb przetrwania")
	mode_opt.custom_minimum_size = Vector2(0, 56)
	left.add_child(mode_opt)
	s_water = _slider(left, "Poziom wody", 8, 22, 1, 14)
	s_mount = _slider(left, "Góry", 0.3, 2.0, 0.1, 1.0)
	s_lava = _slider(left, "Lawa", 0.0, 2.0, 0.1, 0.5)
	s_sim = _slider(left, "Szybkość zmian świata", 0.5, 4.0, 0.5, 1.0)
	left.add_child(_label("Grafika"))
	gfx_opt = OptionButton.new()
	for n in Game.GFX_NAMES:
		gfx_opt.add_item("Preset: " + n)
	gfx_opt.custom_minimum_size = Vector2(0, 56)
	gfx_opt.select(-1)
	gfx_opt.item_selected.connect(_on_preset)
	left.add_child(gfx_opt)
	s_dist = _slider(left, "Zasięg widzenia (chunki, mniej = płynniej)", 2, 6, 1, Game.render_dist)
	shadow_chk = CheckBox.new()
	shadow_chk.text = "Cienie (wolniej)"
	shadow_chk.button_pressed = Game.shadows
	shadow_chk.custom_minimum_size = Vector2(0, 56)
	left.add_child(shadow_chk)
	msaa_opt = OptionButton.new()
	for n in Game.MSAA_NAMES:
		msaa_opt.add_item("Wygładzanie: " + n)
	msaa_opt.select(Game.msaa)
	msaa_opt.custom_minimum_size = Vector2(0, 56)
	left.add_child(msaa_opt)
	var create := Button.new()
	create.text = "UTWÓRZ ŚWIAT"
	create.custom_minimum_size = Vector2(0, 70)
	create.pressed.connect(_on_create)
	left.add_child(create)

	# --- zapisane światy
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)
	right.add_child(_label("Zapisane światy"))
	saved_box = VBoxContainer.new()
	saved_box.add_theme_constant_override("separation", 8)
	right.add_child(saved_box)
	_refresh_saved()


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 32)
	return l


func _slider(parent: Control, text: String, mn: float, mx: float, step: float, val: float) -> HSlider:
	var l := Label.new()
	l.text = "%s: %s" % [text, str(val)]
	parent.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(0, 44)
	s.value_changed.connect(func(v: float): l.text = "%s: %s" % [text, str(snappedf(v, step))])
	parent.add_child(s)
	return s


func _refresh_saved() -> void:
	for c in saved_box.get_children():
		c.queue_free()
	var worlds := Game.list_worlds()
	if worlds.is_empty():
		var l := Label.new()
		l.text = "(brak zapisów)"
		saved_box.add_child(l)
		return
	for w in worlds:
		var row := HBoxContainer.new()
		var b := Button.new()
		b.text = w
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 60)
		b.pressed.connect(_on_load.bind(w))
		row.add_child(b)
		var d := Button.new()
		d.text = "X"
		d.custom_minimum_size = Vector2(60, 60)
		d.pressed.connect(func():
			Game.delete_world(w)
			_refresh_saved())
		row.add_child(d)
		saved_box.add_child(row)


func _on_preset(i: int) -> void:
	Game.apply_preset(i)
	s_dist.value = Game.render_dist
	shadow_chk.button_pressed = Game.shadows
	msaa_opt.select(Game.msaa)


func _store_gfx() -> void:
	Game.render_dist = int(s_dist.value)
	Game.shadows = shadow_chk.button_pressed
	Game.msaa = msaa_opt.selected
	Game.save_settings()


func _on_create() -> void:
	_store_gfx()
	Game.start_new(name_edit.text, seed_edit.text, mode_opt.selected == 0,
		int(s_water.value), s_mount.value, s_lava.value, s_sim.value)
	get_tree().change_scene_to_file("res://scenes/game_scene.tscn")


func _on_load(fname: String) -> void:
	_store_gfx()
	if Game.load_world(fname):
		get_tree().change_scene_to_file("res://scenes/game_scene.tscn")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
