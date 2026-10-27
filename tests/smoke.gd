extends Node
## Test dymny: godot --headless --path . res://tests/smoke.tscn

var fails := 0

func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		fails += 1

func _ready() -> void:
	# kierunki ścian: iloczyn wektorowy ma wskazywać DO ŚRODKA (CW od zewnątrz)
	for f in range(6):
		var v: Array = VoxelWorld.FACE_V[f]
		var cr: Vector3 = (v[1] - v[0]).cross(v[2] - v[0])
		var n := Vector3(VoxelWorld.FACE_N[f])
		check(cr.normalized().is_equal_approx(-n), "winding ściany %d" % f)

	var game = Game
	var root := self
	var w := VoxelWorld.new()
	root.add_child(w)
	w.setup(12345, 14, 1.0, 1.0)
	var t0 := Time.get_ticks_msec()
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			w.ensure_chunk(Vector2i(dx, dz))
	print("gen 49 chunków: %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	var meshed := 0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var c = w.chunks[Vector2i(dx, dz)]
			w.build_mesh(c)
			if c.node.mesh != null:
				meshed += 1
	print("mesh 25 chunków: %d ms" % (Time.get_ticks_msec() - t0))
	check(meshed > 20, "chunki mają meshe (%d/25)" % meshed)

	# meshowanie w wątku
	var ac = w.chunks[Vector2i(0, 0)]
	w.dispatch_mesh(ac)
	WorkerThreadPool.wait_for_task_completion(ac.job)
	check(not ac.result.is_empty() and ac.result["sv"].size() > 0, "mesh z wątku roboczego (%d wierzchołków)" % ac.result["sv"].size())
	ac.job = -1
	w._jobs.clear()

	# determinizm seeda
	var w2 := VoxelWorld.new()
	root.add_child(w2)
	w2.setup(12345, 14, 1.0, 1.0)
	w2.ensure_chunk(Vector2i(0, 0))
	check(w2.chunks[Vector2i(0, 0)].data == w.chunks[Vector2i(0, 0)].data, "ten sam seed = ten sam teren")
	var w3 := VoxelWorld.new()
	root.add_child(w3)
	w3.setup(999, 14, 1.0, 1.0)
	w3.ensure_chunk(Vector2i(0, 0))
	check(w3.chunks[Vector2i(0, 0)].data != w.chunks[Vector2i(0, 0)].data, "inny seed = inny teren")

	# raycast
	var sp := w.find_spawn()
	var sy := w.surface_y(floori(sp.x), floori(sp.z))
	var hit := w.raycast(Vector3(sp.x, sy + 3.5, sp.z), Vector3.DOWN, 10.0)
	check(not hit.is_empty() and hit.pos.y == sy and hit.normal == Vector3i(0, 1, 0), "raycast w dół trafia w powierzchnię (y=%d)" % sy)

	# woda: źródło na płaskim terenie rozlewa się i potem znika po usunięciu źródła
	var x := floori(sp.x)
	var z := floori(sp.z)
	var y := sy + 5
	w.set_block(x, y, z, VoxelWorld.fluid_id(VoxelWorld.WATER, 8))
	for i in range(40):
		w.sim_step(1000)
	var cnt := 0
	for dy in range(-6, 8):
		for dz in range(-10, 11):
			for dx in range(-10, 11):
				if VoxelWorld.fluid_kind(w.get_block(x + dx, y + dy, z + dz)) == VoxelWorld.WATER:
					cnt += 1
	check(cnt > 10, "woda spłynęła i rozlała się (%d komórek)" % cnt)
	check(cnt < 2000, "woda nie zalała całego świata")
	w.set_block(x, y, z, VoxelWorld.AIR)
	for i in range(200):
		w.sim_step(1000)
	cnt = 0
	for dy in range(-8, 8):
		for dz in range(-16, 17):
			for dx in range(-16, 17):
				var bb := w.get_block(x + dx, y + dy, z + dz)
				if VoxelWorld.fluid_kind(bb) == VoxelWorld.WATER and (bb & 15) < 8:
					cnt += 1
	check(cnt == 0, "płynąca woda zanika po usunięciu źródła (zostało %d)" % cnt)

	# lawa + woda = obsydian
	var lx := x + 3
	w.set_block(lx, y, z, VoxelWorld.fluid_id(VoxelWorld.LAVA, 8))
	for i in range(30):
		w.sim_step(1000)
	var lava_cnt := 0
	for dy in range(-8, 3):
		for dz in range(-6, 7):
			for dx in range(-6, 7):
				if VoxelWorld.fluid_kind(w.get_block(lx + dx, y + dy, z + dz)) == VoxelWorld.LAVA:
					lava_cnt += 1
	check(lava_cnt > 0, "lawa płynie (%d komórek)" % lava_cnt)
	w.set_block(lx, y + 1, z, VoxelWorld.fluid_id(VoxelWorld.WATER, 8))
	for i in range(30):
		w.sim_step(1000)
	var obs := 0
	for dy in range(-8, 3):
		for dz in range(-6, 7):
			for dx in range(-6, 7):
				if w.get_block(lx + dx, y + dy, z + dz) in [VoxelWorld.OBSIDIAN, VoxelWorld.STONE]:
					obs += 1
	check(obs > 0, "lawa + woda daje obsydian/kamień")

	# zapis/odczyt
	game.start_new("test smoke", "abc", true, 14, 1.0, 0.5, 1.0)
	var ok: bool = game.write_save({"name": "test smoke", "seed": game.seed_value, "chunks": w.collect_modified(), "player_pos": Vector3(1, 2, 3)})
	check(ok, "zapis świata")
	check(game.load_world("test smoke") and game.save_chunks.size() > 0, "wczytanie świata (%d zmienionych chunków)" % game.save_chunks.size())
	game.delete_world("test smoke")

	print("WYNIK: %s" % ("WSZYSTKO OK" if fails == 0 else "%d BŁĘDÓW" % fails))
	get_tree().quit(fails)
