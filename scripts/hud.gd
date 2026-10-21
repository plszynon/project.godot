class_name HUD
extends Control
## Dotykowy interfejs: joystick, patrzenie, przyciski, pasek bloków. Obsługuje wiele palców naraz.

signal menu_pressed
signal fly_pressed
signal sim_pressed

var player: Player
var active := true
var move := Vector2.ZERO
var look_accum := Vector2.ZERO
var jump_held := false
var down_held := false
var action_tap := false
var action_held := false
var build_mode := false
var selected := 0
var sim_label := "1x"

var _move_idx := -1
var _move_origin := Vector2.ZERO
var _look_idx := -1
var _look_start := Vector2.ZERO
var _look_time := 0.0
var _look_moved := false
var _jump_idx := -1
var _down_idx := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _sz() -> Vector2:
	return get_viewport_rect().size

func _jump_c() -> Vector2: return Vector2(_sz().x - 110, _sz().y - 110)
func _mode_c() -> Vector2: return Vector2(_sz().x - 250, _sz().y - 90)
func _fly_c() -> Vector2: return Vector2(_sz().x - 110, _sz().y - 235)
func _down_c() -> Vector2: return Vector2(_sz().x - 235, _sz().y - 215)
func _menu_rect() -> Rect2: return Rect2(_sz().x - 104, 14, 90, 54)
func _sim_rect() -> Rect2: return Rect2(_sz().x - 214, 14, 100, 54)
func _slot_rect(i: int) -> Rect2:
	var x0 := (_sz().x - 660.0) * 0.5
	return Rect2(x0 + i * 74.0, _sz().y - 82.0, 68, 68)


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
	for i in range(9):
		if _slot_rect(i).has_point(pos):
			selected = i
			return
	if _menu_rect().has_point(pos):
		menu_pressed.emit()
		return
	if _sim_rect().has_point(pos):
		sim_pressed.emit()
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
		if (pos - _look_start).length() > 22.0:
			_look_moved = true
			action_held = false


func _process(delta: float) -> void:
	if _look_idx != -1 and not _look_moved:
		_look_time += delta
		if _look_time > 0.4:
			action_held = true
	queue_redraw()


func _btn(p: Vector2, r: float, text: String, pressed: bool, fs: int = 22) -> void:
	draw_circle(p, r, Color(0, 0, 0, 0.6 if pressed else 0.35))
	draw_arc(p, r, 0, TAU, 32, Color(1, 1, 1, 0.6), 3.0)
	_text(p, text, fs)


func _text(center: Vector2, text: String, fs: int) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, center + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw() -> void:
	var s := _sz()
	var c := s * 0.5
	draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), Color(1, 1, 1, 0.85), 2.0)
	draw_line(c + Vector2(0, -10), c + Vector2(0, 10), Color(1, 1, 1, 0.85), 2.0)
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
	for r in [_menu_rect(), _sim_rect()]:
		draw_rect(r, Color(0, 0, 0, 0.4))
		draw_rect(r, Color(1, 1, 1, 0.6), false, 2.0)
	_text(_menu_rect().get_center(), "MENU", 20)
	_text(_sim_rect().get_center(), "SYM " + sim_label, 20)
	# pasek bloków
	for i in range(9):
		var r := _slot_rect(i)
		var id: int = VoxelWorld.HOTBAR[i]
		var col: Color = VoxelWorld.COLORS[id]
		col.a = 1.0
		draw_rect(r, Color(0, 0, 0, 0.45))
		draw_rect(r.grow(-8), col)
		draw_rect(r, Color(1, 0.9, 0.2) if i == selected else Color(1, 1, 1, 0.4), false, 4.0 if i == selected else 2.0)
		if player != null and not player.creative:
			var n: int = player.inventory.get(id, 0)
			draw_string(ThemeDB.fallback_font, r.position + Vector2(6, 62), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
