extends Node
## Test przetrwania: crafting, serca, moby, jedzenie, kopanie z czasem, śmierć.

var ok := true

func check(c: bool, msg: String) -> void:
	print(("OK   " if c else "FAIL ") + msg)
	if not c:
		ok = false

func frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _ready() -> void:
	Game.start_new("test survival", "42", false, 14, 1.0, 0.0, 1.0)
	var gs = load("res://scenes/game_scene.tscn").instantiate()
	add_child(gs)
	await frames(40)
	var p: Player = gs.player
	var w: VoxelWorld = gs.world
	var h: HUD = gs.hud
	check(not p.creative, "tryb przetrwania")
	check(p.slots.count(0) == 9, "pusty ekwipunek na starcie")
	check(p.health == 20.0, "pełne serca")

	# crafting
	p.add_item(5, 5)
	check(p.slots.has(5), "drewno trafia na pasek")
	for i in range(3): p.craft(Items.RECIPES[0])      # deski
	check(p.inventory.get(9, 0) == 12 and p.inventory.get(5, 0) == 2, "deski z drewna (%s)" % str(p.inventory))
	p.craft(Items.RECIPES[1])                          # patyki
	check(p.craft(Items.RECIPES[2]), "kilof z desek i patyków")
	check(p.inventory.get(Items.WOOD_PICK, 0) == 1, "kilof w ekwipunku")
	check(not p.craft(Items.RECIPES[3]), "kamienny kilof bez kamienia się nie uda")

	# obrażenia i regeneracja
	p.hurt(5.0)
	check(p.health == 15.0, "obrażenia zabierają serca (%s)" % p.health)
	p.hurt(5.0)
	check(p.health == 15.0, "krótka nietykalność po ciosie")

	# kopanie z przytrzymaniem
	p.pitch = -1.4
	p.cam.rotation.x = p.pitch
	await frames(3)
	check(not p.target.is_empty(), "jest cel pod nogami")
	var tpos: Vector3i = p.target.pos
	var drop_id := Items.drop_for(int(p.target["block"]))
	var dirt_before: int = p.inventory.get(drop_id, 0)
	h.holding = true
	await frames(90)
	h.holding = false
	check(w.get_block(tpos.x, tpos.y, tpos.z) == VoxelWorld.AIR, "blok wykopany po przytrzymaniu")
	check(p.inventory.get(drop_id, 0) >= dirt_before + 1, "kopanie daje drop: %s" % Items.item_name(drop_id))
	check(Items.drop_for(1) == 2, "trawa daje ziemię")

	# moby
	var pig := Mob.new()
	gs.add_child(pig)
	pig.setup(Mob.Kind.PIG, w, p)
	var fwd := -p.global_transform.basis.z
	pig.position = p.position + Vector3(fwd.x, 0, fwd.z).normalized() * 2.0 + Vector3(0, 1, 0)
	await frames(30)
	check(is_instance_valid(pig) and pig.position.y > 0.0, "świnia stoi na ziemi (y=%.1f)" % pig.position.y)
	pig.hurt(100.0)
	await frames(2)
	check(p.inventory.get(Items.RAW_MEAT, 0) >= 1, "świnia dropi mięso")

	# jedzenie
	p.heal(0.0)
	var meat_slot := p.slots.find(Items.RAW_MEAT)
	check(meat_slot >= 0, "mięso na pasku")
	h.selected = meat_slot
	h.build_mode = true
	var hp0 := p.health
	var meat0: int = p.inventory.get(Items.RAW_MEAT, 0)
	h.action_tap = true
	await frames(3)
	check(p.health > hp0 and p.inventory.get(Items.RAW_MEAT, 0) == meat0 - 1, "jedzenie leczy (%s -> %s)" % [hp0, p.health])
	h.build_mode = false

	# zombie atakuje
	p._invuln = 0.0
	var hp1 := p.health
	var z := Mob.new()
	gs.add_child(z)
	z.setup(Mob.Kind.ZOMBIE, w, p)
	z.position = p.position + Vector3(0.8, 0, 0)
	await frames(30)
	check(p.health < hp1, "zombie rani gracza (%s -> %s)" % [hp1, p.health])
	# gracz zabija zombie mieczem
	z.hurt(50.0)
	await frames(2)
	check(not is_instance_valid(z) or z._dead, "zombie ginie")

	# raycast w moba
	var cow := Mob.new()
	gs.add_child(cow)
	cow.setup(Mob.Kind.COW, w, p)
	cow.position = Vector3(10, 10, 10)
	cow.set_process(false)
	var t := cow.ray_t(Vector3(10, 10.5, 5), Vector3(0, 0, 1))
	check(absf(t - 4.55) < 0.1, "ray_t trafia w moba (t=%.2f)" % t)
	check(cow.ray_t(Vector3(10, 10.5, 5), Vector3(0, 1, 0)) < 0.0, "ray_t pudłuje")
	cow.queue_free()

	# śmierć i odrodzenie
	p._invuln = 0.0
	p.hurt(100.0)
	check(p.dead, "gracz ginie")
	var hp_before_respawn := p.health
	p.respawn()
	await frames(5)
	check(not p.dead and p.health == 20.0 and hp_before_respawn == 0.0, "odrodzenie")

	# zapis z ekwipunkiem
	gs.save_game()
	Game.load_world("test survival")
	check(Game.save_data.has("slots") and Game.save_data["inventory"].size() > 0, "zapis ekwipunku i pasków")
	Game.delete_world("test survival")

	print("WYNIK PRZETRWANIA: ", "OK" if ok else "BŁĄD")
	get_tree().quit(0 if ok else 1)
