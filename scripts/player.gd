class_name Player
extends Node3D
## Gracz: kolizje z blokami, życie, kopanie z czasem, walka, jedzenie, crafting.

const HALF := 0.3
const HEIGHT := 1.8
const EYE := 1.62
const REACH := 5.5
const MOB_REACH := 3.8
const MAX_HP := 20.0

var world: VoxelWorld
var hud: HUD
var cam: Camera3D
var outline: MeshInstance3D
var vel := Vector3.ZERO
var pitch := 0.0
var flying := false
var on_ground := false
var creative := true
var frozen := false
var dead := false
var health := MAX_HP
var air := 10.0
var hurt_t := 0.0
var inventory := {}
var slots: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0]
var target: Dictionary = {}
var mob_target: Mob = null
var spawn_point := Vector3.ZERO
var break_prog := 0.0
var break_pos := Vector3i.ZERO

var _cd := 0.0
var _invuln := 0.0
var _since_hurt := 0.0
var _fall_peak := 0.0
var _lava_t := 0.0
var _drown_t := 0.0
var _regen_t := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.position = Vector3(0, EYE, 0)
	cam.near = 0.05
	cam.far = 250.0
	add_child(cam)
	cam.make_current()
	outline = _make_outline()
	add_child(outline)


func _make_outline() -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = Vector3(1.006, 1.006, 1.006)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0.28)
	bm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.top_level = true
	mi.visible = false
	return mi


# ---------------------------------------------------------------- ekwipunek
func init_slots() -> void:
	if creative:
		slots = VoxelWorld.HOTBAR.duplicate()
	else:
		refill_slots()


func selected_id() -> int:
	if hud == null:
		return 0
	return slots[hud.selected]


func refill_slots() -> void:
	if creative:
		return
	for i in range(slots.size()):
		if slots[i] != 0 and inventory.get(slots[i], 0) <= 0:
			slots[i] = 0
	for id in inventory.keys():
		if inventory[id] > 0 and not slots.has(id):
			var e := slots.find(0)
			if e >= 0:
				slots[e] = id


func add_item(id: int, n: int = 1) -> void:
	if creative or id == 0:
		return
	inventory[id] = inventory.get(id, 0) + n
	refill_slots()
	if hud != null:
		hud.toast("+%d %s" % [n, Items.item_name(id)])


func take_item(id: int, n: int = 1) -> bool:
	if creative:
		return true
	if inventory.get(id, 0) < n:
		return false
	inventory[id] -= n
	if inventory[id] <= 0:
		inventory.erase(id)
	refill_slots()
	return true


func can_craft(r: Dictionary) -> bool:
	for id in r["in"]:
		if inventory.get(id, 0) < r["in"][id]:
			return false
	return true


func craft(r: Dictionary) -> bool:
	if not can_craft(r):
		return false
	for id in r["in"]:
		take_item(id, r["in"][id])
	add_item(r["out"], r["n"])
	return true


func on_mob_killed(kind: int) -> void:
	if creative:
		return
	match kind:
		Mob.Kind.PIG, Mob.Kind.COW:
			add_item(Items.RAW_MEAT, randi_range(1, 2))
		Mob.Kind.ZOMBIE:
			add_item(Items.STICK, randi_range(1, 2))


# ---------------------------------------------------------------- życie
func hurt(amount: float, from_dir: Vector3 = Vector3.ZERO, knock := true) -> void:
	if creative or dead or _invuln > 0.0:
		return
	health -= amount
	_invuln = 0.5
	hurt_t = 0.4
	_since_hurt = 0.0
	if knock:
		vel.x += from_dir.x * 6.0
		vel.z += from_dir.z * 6.0
		vel.y = 4.0
	if health <= 0.0:
		health = 0.0
		dead = true
		vel = Vector3.ZERO
		if hud != null:
			hud.reset_input()


func heal(amount: float) -> void:
	health = minf(MAX_HP, health + amount)


func respawn() -> void:
	dead = false
	health = MAX_HP
	air = 10.0
	vel = Vector3.ZERO
	flying = false
	_invuln = 2.0
	world.ensure_around(spawn_point, 1)
	position = Vector3(spawn_point.x, world.surface_y(floori(spawn_point.x), floori(spawn_point.z)) + 1.01, spawn_point.z)
	_fall_peak = position.y
	if hud != null:
		hud.toast("Odrodziłeś się")


func toggle_fly() -> void:
	flying = not flying
	vel = Vector3.ZERO


# ---------------------------------------------------------------- pętla
func _process(delta: float) -> void:
	if world == null or hud == null:
		return
	delta = minf(delta, 0.05)
	hurt_t = maxf(0.0, hurt_t - delta)
	_invuln -= delta
	if frozen or dead:
		return
	var look := hud.consume_look()
	rotation.y -= look.x * 0.0045
	pitch = clampf(pitch - look.y * 0.0045, -1.5, 1.5)
	cam.rotation.x = pitch
	_move(delta)
	_vitals(delta)
	_update_target()
	_actions(delta)


func _vitals(delta: float) -> void:
	if creative:
		health = MAX_HP
		air = 10.0
		return
	_since_hurt += delta
	var lava := VoxelWorld.LAVA
	if _fluid_kind_at(position + Vector3(0, 0.3, 0)) == lava or _fluid_kind_at(position + Vector3(0, 1.0, 0)) == lava:
		_lava_t += delta
		if _lava_t >= 0.5:
			_lava_t = 0.0
			hurt(3.0, Vector3.ZERO, false)
	if _fluid_kind_at(cam.global_position) == VoxelWorld.WATER:
		air -= delta
		if air <= 0.0:
			_drown_t += delta
			if _drown_t >= 1.0:
				_drown_t = 0.0
				hurt(2.0, Vector3.ZERO, false)
	else:
		air = minf(10.0, air + delta * 5.0)
		_drown_t = 0.0
	if health < MAX_HP and _since_hurt > 8.0:
		_regen_t += delta
		if _regen_t >= 3.0:
			_regen_t = 0.0
			heal(1.0)


func _move(delta: float) -> void:
	var mv := hud.move
	if Input.is_key_pressed(KEY_W): mv.y -= 1.0
	if Input.is_key_pressed(KEY_S): mv.y += 1.0
	if Input.is_key_pressed(KEY_A): mv.x -= 1.0
	if Input.is_key_pressed(KEY_D): mv.x += 1.0
	mv = mv.limit_length(1.0)
	var wish := global_transform.basis * Vector3(mv.x, 0.0, mv.y)
	var jump := hud.jump_held or Input.is_key_pressed(KEY_SPACE)
	var down := hud.down_held or Input.is_key_pressed(KEY_SHIFT)
	var fk := _fluid_kind_at(position + Vector3(0, 0.5, 0))
	if flying:
		vel = Vector3(wish.x * 12.0, (float(jump) - float(down)) * 9.0, wish.z * 12.0)
	else:
		var spd := 4.6
		if fk == VoxelWorld.WATER:
			spd = 2.6
		elif fk == VoxelWorld.LAVA:
			spd = 1.5
		vel.x = lerpf(vel.x, wish.x * spd, minf(1.0, delta * 14.0))
		vel.z = lerpf(vel.z, wish.z * spd, minf(1.0, delta * 14.0))
		if fk != 0:
			vel.y = maxf(vel.y - 8.0 * delta, -2.5)
			if jump:
				vel.y = 3.6
		else:
			vel.y = maxf(vel.y - 28.0 * delta, -40.0)
			if jump and on_ground:
				vel.y = 8.6
	if on_ground or flying or fk != 0:
		_fall_peak = position.y
	else:
		_fall_peak = maxf(_fall_peak, position.y)
	var was_ground := on_ground
	_step(vel * delta)
	if on_ground and not was_ground and not creative:
		var fall := _fall_peak - position.y
		if fall > 3.5:
			hurt(floorf(fall - 3.0), Vector3.ZERO, false)


func _fluid_kind_at(p: Vector3) -> int:
	return VoxelWorld.fluid_kind(world.get_block(floori(p.x), floori(p.y), floori(p.z)))


func _hit(p: Vector3) -> bool:
	var x0 := floori(p.x - HALF)
	var x1 := floori(p.x + HALF - 0.0001)
	var y0 := floori(p.y)
	var y1 := floori(p.y + HEIGHT - 0.0001)
	var z0 := floori(p.z - HALF)
	var z1 := floori(p.z + HALF - 0.0001)
	for y in range(y0, y1 + 1):
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var b := world.get_block(x, y, z)
				if b < 0 or VoxelWorld.is_solid(b):
					return true
	return false


func _step(d: Vector3) -> void:
	var was_ground := on_ground
	on_ground = false
	var p := position
	p.x += d.x
	if _hit(p):
		if was_ground and not flying and not _hit(Vector3(p.x, p.y + 1.01, p.z)):
			p.y += 1.01
		else:
			p.x -= d.x
			vel.x = 0.0
	p.z += d.z
	if _hit(p):
		if was_ground and not flying and not _hit(Vector3(p.x, p.y + 1.01, p.z)):
			p.y += 1.01
		else:
			p.z -= d.z
			vel.z = 0.0
	p.y += d.y
	if _hit(p):
		if d.y < 0.0:
			on_ground = true
			var q := Vector3(p.x, floorf(p.y) + 1.001, p.z)
			if _hit(q):
				p.y -= d.y
			else:
				p = q
		else:
			p.y -= d.y
		vel.y = 0.0
	position = p


# ---------------------------------------------------------------- cel i akcje
func _update_target() -> void:
	var o := cam.global_position
	var dir := -cam.global_transform.basis.z
	target = world.raycast(o, dir, REACH)
	mob_target = null
	var best := MOB_REACH
	for m: Mob in get_tree().get_nodes_in_group("mobs"):
		var t := m.ray_t(o, dir)
		if t >= 0.0 and t < best:
			best = t
			mob_target = m
	if mob_target != null and not target.is_empty() and float(target["t"]) < best:
		mob_target = null
	if target.is_empty() or mob_target != null:
		outline.visible = false
	else:
		outline.visible = true
		outline.global_position = Vector3(target.pos) + Vector3(0.5, 0.5, 0.5)


func _actions(delta: float) -> void:
	_cd -= delta
	var sel := selected_id()
	var tap := hud.action_tap
	hud.action_tap = false
	if hud.build_mode:
		break_prog = 0.0
		if tap or (hud.action_held and _cd <= 0.0):
			_cd = 0.25
			if Items.FOOD.has(sel):
				_eat(sel)
			elif Items.is_block(sel):
				_place(sel)
		return
	if mob_target != null:
		break_prog = 0.0
		if tap or (hud.holding and _cd <= 0.0):
			_cd = 0.5
			var fwd := -global_transform.basis.z
			fwd.y = 0.0
			var dmg := 999.0 if creative else Items.attack_damage(sel)
			mob_target.hurt(dmg, fwd.normalized())
		return
	if target.is_empty():
		break_prog = 0.0
		return
	if creative:
		if tap or (hud.action_held and _cd <= 0.0):
			_cd = 0.2
			_break_block()
		return
	var tp: Vector3i = target.pos
	if tp != break_pos:
		break_prog = 0.0
		break_pos = tp
	if hud.holding:
		break_prog += delta / Items.break_time(int(target["block"]), sel)
		if break_prog >= 1.0:
			break_prog = 0.0
			_break_block()
	else:
		break_prog = maxf(0.0, break_prog - delta * 2.0)


func _break_block() -> void:
	var p: Vector3i = target.pos
	var b: int = target.block
	world.set_block(p.x, p.y, p.z, VoxelWorld.AIR)
	if creative:
		return
	var drop := Items.drop_for(b)
	if drop > 0:
		add_item(drop, 1)
	elif b == VoxelWorld.LEAVES and randf() < 0.3:
		add_item(Items.STICK, 1)


func _eat(id: int) -> void:
	if creative:
		return
	if health >= MAX_HP:
		hud.toast("Masz pełne życie")
		return
	if take_item(id, 1):
		heal(Items.FOOD[id])


func _place(id: int) -> void:
	if target.is_empty():
		return
	var np: Vector3i = target.pos + target.normal
	var cur := world.get_block(np.x, np.y, np.z)
	if cur != VoxelWorld.AIR and not VoxelWorld.is_fluid(cur):
		return
	if not creative and inventory.get(id, 0) <= 0:
		return
	if VoxelWorld.is_solid(id) and _overlaps(np):
		return
	world.set_block(np.x, np.y, np.z, id)
	if not creative:
		take_item(id, 1)


func _overlaps(b: Vector3i) -> bool:
	var p := position
	return p.x - HALF < b.x + 1 and p.x + HALF > b.x \
		and p.y < b.y + 1 and p.y + HEIGHT > b.y \
		and p.z - HALF < b.z + 1 and p.z + HALF > b.z
