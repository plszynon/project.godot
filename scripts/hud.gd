class_name HUD
extends Control
## Dotykowy interfejs: joystick, patrzenie, przyciski, serca, pasek przedmiotów, paleta bloków.

signal menu_pressed
signal fly_pressed
signal sim_pressed
signal craft_pressed
signal respawn_pressed

var player: Player
var active := true
var move := Vector2.ZERO
var look_accum := Vector2.ZERO
var jump_held := false
var down_held := false
var action_tap := false
var action_held := false
var holding := false
var build_mode := false
var selected := 0
var sim_label := "1x"
var palette_open := false

var _move_idx := -1
var _move_origin := Vector2.ZERO
var _look_idx := -1
var _look_start := Vector2.ZERO
var _look_time := 0.0
var _look_moved := false
var _jump_idx := -1
var _down_idx := -1
var _toast := ""
var _toast_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func toast(t: String) -> void:
	_toast = t
	_toast_t = 2.5


func _sz() -> Vector2:
	return get_viewport_rect().size

func _jump_c() -> Vector2: return Vector2(_sz().x - 110, _sz().y - 110)
func _mode_c() -> Vector2: return Vector2(_sz().x - 250, _sz().y - 90)
func _fly_c() -> Vector2: return Vector2(_sz().x - 110, _sz().y - 235)
func _down_c() -> Vector2: return Vector2(_sz().x - 235, _sz().y - 215)
func _menu_rect() -> Rect2: return Rect2(_sz().x - 104, 14, 90, 54)
func _sim_rect() -> Rect2: return Rect2(_sz().x - 214, 14, 100, 54)
func _side_rect() -> Rect2: return Rect2(_sz().x - 324, 14, 100, 54)
func _respawn_rect() -> Rect2: return Rect2(_sz().x * 0.5 - 160, _sz().y * 0.5 + 30, 320, 84)
func _slot_rect(i: int) -> Rect2:
	var x0 := (_sz().x - 660.0) * 0.5
	return Rect2(x0 + i * 74.0, _sz().y - 82.0, 68, 68)
func _pal_rect(i: int) -> Rect2:
	var x0 := (_sz().x - 6.0 * 94.0) * 0.5
	var y0 := _sz().y * 0.5 - 130.0
	return Rect2(x0 + (i % 6) * 94.0, y0 + (i / 6) * 94.0, 84, 84)


func consume_look() -> Vector2:
	var v := look_accum
	look_accum = Vector2.ZERO
	return v


func reset_input() -> void:
	_move_idx = -1
	_look_idx = -1
	_jump_idx = -1
	_down_idx = -1
	move = Vector2.ZERO
	look_accum = Vector2.ZERO
	jump_held = false
	down_held = false
	action_tap = false
	action_held = false
	holding = false
	palette_open = false


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_on_press(e.index, e.position)
		else:
			_on_release(e.index)
	elif event is InputEventScreenDrag:
		var e2 := event as InputEventScreenDrag
		_on_drag(e2.index, e2.position, e2.relative)


func _on_press(idx: int, pos: Vector2) -> void:
	if player != null and player.dead:
		if _respawn_rect().has_point(pos):
			respawn_pressed.emit()
		return
	for i in range(9):
		if _slot_rect(i).has_point(pos):
			selected = i
			return
	if palette_open:
		for i in range(Items.CREATIVE_BLOCKS.size()):
			if _pal_rect(i).has_point(pos):
				player.slots[selected] = Items.CREATIVE_BLOCKS[i]
				break
		palette_open = false
		return
	if _menu_rect().has_point(pos):
		menu_pressed.emit()
		return
	if _sim_rect().has_point(pos):
		sim_pressed.emit()
		return
	if _side_rect().has_point(pos):
		if player != null and player.creative:
			palette_open = true
		else:
			craft_pressed.emit()
		return
	if pos.distance_to(_jump_c()) < 70.0:
		_jump_idx = idx
		jump_held = true
		return
	if pos.distance_to(_mode_c()) < 56.0:
		build_mode = not build_mode
		return
	if player != null and player.creative:
		if pos.distance_to(_fly_c()) < 50.0:
			fly_pressed.emit()
			return
		if player.flying and pos.distance_to(_down_c()) < 50.0:
			_down_idx = idx
			down_held = true
			return
	if pos.x < _sz().x * 0.42 and _move_idx == -1:
		_move_idx = idx
		_move_origin = pos
		move = Vector2.ZERO
	elif _look_idx == -1:
		_look_idx = idx
		_look_start = pos
		_look_time = 0.0
		_look_moved = false


func _on_release(idx: int) -> void:
	if idx == _move_idx:
		_move_idx = -1
		move = Vector2.ZERO
	elif idx == _look_idx:
		if not _look_moved and _look_time < 0.25:
			action_tap = true
		_look_idx = -1
		action_held = false
		holding = false
	elif idx == _jump_idx:
		_jump_idx = -1
		jump_held = false
	elif idx == _down_idx:
		_down_idx = -1
		down_held = false


func _on_drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if idx == _move_idx:
		move = ((pos - _move_origin) / 80.0).limit_length(1.0)
	elif idx == _look_idx:
		look_accum += rel
		if (pos - _look_start).length() > 30.0:
			_look_moved = true
			action_held = false
			holding = false


func _process(delta: float) -> void:
	if _look_idx != -1 and not _look_moved:
		_look_time += delta
		holding = true
		if _look_time > 0.4:
			action_held = true
	_toast_t -= delta
	queue_redraw()


# ---------------------------------------------------------------- rysowanie
func _btn(p: Vector2, r: float, text: String, pressed: bool, fs: int = 22) -> void:
	draw_circle(p, r, Color(0, 0, 0, 0.6 if pressed else 0.35))
	draw_arc(p, r, 0, TAU, 32, Color(1, 1, 1, 0.6), 3.0)
	_text(p, text, fs)


func _text(center: Vector2, text: String, fs: int, col: Color = Color.WHITE) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, center + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _box_btn(r: Rect2, text: String) -> void:
	draw_rect(r, Color(0, 0, 0, 0.4))
	draw_rect(r, Color(1, 1, 1, 0.6), false, 2.0)
	_text(r.get_center(), text, 20)


func _heart_shape(p: Vector2, s: float, col: Color, frac: float) -> void:
	var y0 := p.y + s * 0.7
	var y1 := p.y + s * 1.9
	draw_circle(Vector2(p.x + s * 0.5, p.y + s * 0.5), s * 0.52, col)
	if frac > 0.75:
		draw_circle(Vector2(p.x + s * 1.5, p.y + s * 0.5), s * 0.52, col)
		draw_colored_polygon(PackedVector2Array([Vector2(p.x, y0), Vector2(p.x + 2.0 * s, y0), Vector2(p.x + s, y1)]), col)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(p.x, y0), Vector2(p.x + s, y0), Vector2(p.x + s, y1)]), col)


## Ikona przedmiotu: tekstura bloku albo kolorowy kwadrat dla narzędzi i jedzenia.
func _icon(r: Rect2, id: int) -> void:
	if not Items.is_block(id) and VoxelWorld.fluid_kind(id) == 0:
		draw_rect(r, Items.item_color(id))
		return
	var k := VoxelWorld.fluid_kind(id)
	var t := BlockTex.tile_for(id, 2)
	var tint := Color.WHITE
	if k == VoxelWorld.WATER:
		t = BlockTex.WATER
		tint = Color(0.35, 0.55, 1.0)
	elif k == VoxelWorld.LAVA:
		t = BlockTex.LAVA
	var ts := BlockTex.TS * BlockTex.ICON_SCALE
	var src := Rect2((t % BlockTex.COLS) * ts, (t / BlockTex.COLS) * ts, ts, ts)
	draw_texture_rect_region(BlockTex.icon_atlas(), r, src, tint)


func _draw() -> void:
	var s := _sz()
	var c := s * 0.5
	# celownik
	var cross_col := Color(1, 0.3, 0.3, 0.95) if (player != null and player.mob_target != null) else Color(1, 1, 1, 0.85)
	draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), cross_col, 2.0)
	draw_line(c + Vector2(0, -10), c + Vector2(0, 10), cross_col, 2.0)
	# pasek postępu kopania
	if player != null and player.break_prog > 0.01:
		draw_rect(Rect2(c.x - 60, c.y + 30, 120, 10), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(c.x - 60, c.y + 30, 120.0 * clampf(player.break_prog, 0, 1), 10), Color(1, 0.85, 0.2))
	# joystick
	var base := _move_origin if _move_idx != -1 else Vector2(150, s.y - 150)
	draw_circle(base, 80, Color(1, 1, 1, 0.10))
	draw_arc(base, 80, 0, TAU, 40, Color(1, 1, 1, 0.35), 3.0)
	draw_circle(base + move * 80.0, 34, Color(1, 1, 1, 0.35))
	# przyciski
	_btn(_jump_c(), 58, "SKOK", _jump_idx != -1)
	_btn(_mode_c(), 48, "BUDUJ" if build_mode else "KOP", false)
	if player != null and player.creative:
		_btn(_fly_c(), 42, "LOT", player.flying, 20)
		if player.flying:
			_btn(_down_c(), 42, "DÓŁ", _down_idx != -1, 20)
	_box_btn(_menu_rect(), "MENU")
	_box_btn(_sim_rect(), "SYM " + sim_label)
	_box_btn(_side_rect(), "BLOKI" if (player != null and player.creative) else "CRAFT")
	# serca i powietrze (przetrwanie)
	if player != null and not player.creative:
		for i in range(10):
			var fill := clampf((player.health - i * 2.0) / 2.0, 0.0, 1.0)
			var p := Vector2(16 + i * 30.0, 16)
			_heart_shape(p, 13.0, Color(0.22, 0.05, 0.08, 0.9), 1.0)
			if fill > 0.0:
				_heart_shape(p + Vector2(1.5, 1.5), 11.0, Color(0.92, 0.13, 0.16), fill)
		if player.air < 9.9:
			for i in range(int(ceilf(player.air))):
				draw_circle(Vector2(26 + i * 28.0, 70), 9.0, Color(0.5, 0.75, 1.0, 0.9))
	# pasek przedmiotów
	for i in range(9):
		var r := _slot_rect(i)
		var id: int = player.slots[i] if player != null else 0
		draw_rect(r, Color(0, 0, 0, 0.45))
		if id != 0:
			_icon(r.grow(-8), id)
			if not Items.is_block(id):
				_text(r.get_center(), Items.LABELS.get(id, "?"), 17, Color.BLACK)
			if player != null and not player.creative:
				draw_string(ThemeDB.fallback_font, r.position + Vector2(6, 62), str(player.inventory.get(id, 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		draw_rect(r, Color(1, 0.9, 0.2) if i == selected else Color(1, 1, 1, 0.4), false, 4.0 if i == selected else 2.0)
	# nazwa wybranego przedmiotu
	if player != null and player.slots[selected] != 0:
		_text(Vector2(s.x * 0.5, s.y - 98), Items.item_name(player.slots[selected]), 20)
	# paleta bloków (kreatywny)
	if palette_open:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.45))
		for i in range(Items.CREATIVE_BLOCKS.size()):
			var id2: int = Items.CREATIVE_BLOCKS[i]
			var pr := _pal_rect(i)
			draw_rect(pr, Color(0, 0, 0, 0.6))
			_icon(pr.grow(-10), id2)
			draw_rect(pr, Color(1, 1, 1, 0.5), false, 2.0)
			draw_rect(Rect2(pr.position.x, pr.end.y - 24, pr.size.x, 24), Color(0, 0, 0, 0.65))
			_text(pr.get_center() + Vector2(0, 30), Items.item_name(id2), 15, Color.WHITE)
		_text(Vector2(s.x * 0.5, s.y * 0.5 - 160), "Wybierz blok dla zaznaczonego slotu", 24)
	# komunikat
	if _toast_t > 0.0:
		var f := ThemeDB.fallback_font
		var w := f.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_rect(Rect2(s.x * 0.5 - w * 0.5 - 14, 96, w + 28, 40), Color(0, 0, 0, 0.55))
		_text(Vector2(s.x * 0.5, 116), _toast, 24)
	# błysk obrażeń
	if player != null and player.hurt_t > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(1, 0, 0, clampf(player.hurt_t, 0, 0.4) * 0.8))
	# śmierć
	if player != null and player.dead:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.35, 0, 0, 0.65))
		_text(Vector2(s.x * 0.5, s.y * 0.5 - 40), "ZGINĄŁEŚ", 64)
		_box_btn(_respawn_rect(), "ODRODŹ SIĘ")
