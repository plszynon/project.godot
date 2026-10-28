extends Node
## Test integracyjny: uruchamia prawdziwą scenę gry i symuluje dotyk.

func _ready() -> void:
	Game.start_new("test gry", "moj-seed", true, 14, 1.0, 1.0, 1.0)
	var gs = load("res://scenes/game_scene.tscn").instantiate()
	add_child(gs)
	for i in range(90):
		await get_tree().process_frame
	var p: Player = gs.player
	var w: VoxelWorld = gs.world
	print("po 90 klatkach: pozycja ", p.position, " chunków ", w.chunks.size(), " meshy ", _meshed(w))
	var start := p.position
	var ok := true
	if not (p.position.y > 0.0 and p.position.y < 48.0): ok = false; print("FAIL gracz poza światem")
	# chód do przodu (joystick)
	gs.hud.move = Vector2(0, -1)
	for i in range(120):
		await get_tree().process_frame
	gs.hud.move = Vector2.ZERO
	print("po marszu: ", p.position, " przesunięcie ", snappedf(start.distance_to(p.position), 0.1))
	if start.distance_to(p.position) < 3.0: ok = false; print("FAIL gracz się nie ruszył")
	# lot + kopanie
	p.toggle_fly()
	gs.hud.jump_held = true
	for i in range(30):
		await get_tree().process_frame
	gs.hud.jump_held = false
	print("lot w górę: y=", snappedf(p.position.y, 0.1), " flying=", p.flying)
	# patrzenie w dół i kopanie
	p.pitch = -1.4
	p.cam.rotation.x = p.pitch
	for i in range(3):
		await get_tree().process_frame
	print("cel: ", p.target)
	var before := w.get_block(p.target.pos.x, p.target.pos.y, p.target.pos.z) if not p.target.is_empty() else -2
	gs.hud.build_mode = false
	gs.hud.action_tap = true
	for i in range(3):
		await get_tree().process_frame
	var tp: Vector3i = p.target.pos if not p.target.is_empty() else Vector3i.ZERO
	# dotyk: joystick lewą stroną, patrzenie prawą, tap = akcja, hotbar
	var h: HUD = gs.hud
	h._on_press(1, Vector2(200, 500))
	h._on_drag(1, Vector2(200, 440), Vector2(0, -60))
	if h.move.y > -0.5: ok = false; print("FAIL joystick ", h.move)
	h._on_release(1)
	if h.move != Vector2.ZERO: ok = false; print("FAIL joystick release")
	h._on_press(2, Vector2(900, 300))
	h._on_release(2)
	if not h.action_tap: ok = false; print("FAIL tap")
	h.action_tap = false
	h._on_press(3, Vector2(900, 300))
	h._on_drag(3, Vector2(960, 300), Vector2(60, 0))
	h._on_release(3)
	if h.action_tap or h.consume_look().x != 60.0: ok = false; print("FAIL look drag")
	h._on_press(4, h._slot_rect(3).get_center())
	if h.selected != 3: ok = false; print("FAIL hotbar")
	h._on_release(4)
	h._on_press(5, h._mode_c())
	if not h.build_mode: ok = false; print("FAIL tryb")
	h._on_release(5)
	print("dotyk OK")
	# zapis
	gs.save_game()
	print("zapisane światy: ", Game.list_worlds())
	if not Game.list_worlds().has("test gry"): ok = false; print("FAIL brak zapisu")
	Game.delete_world("test gry")
	# menu pauzy
	gs._open_menu(true)
	await get_tree().process_frame
	gs._open_menu(false)
	gs._cycle_sim()
	await get_tree().process_frame
	print("WYNIK GRY: ", "OK" if ok else "BŁĄD")
	get_tree().quit(0 if ok else 1)

func _meshed(w: VoxelWorld) -> int:
	var n := 0
	for cp in w.chunks:
		if w.chunks[cp].node != null and w.chunks[cp].node.mesh != null: n += 1
	return n
