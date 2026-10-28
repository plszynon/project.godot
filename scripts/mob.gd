class_name Mob
extends Node3D
## Moby: świnia, krowa (spokojne) i zombie (wrogie, nocą, palą się w słońcu).

enum Kind { PIG, COW, ZOMBIE, SHEEP }

var kind := Kind.PIG
var world: VoxelWorld
var player: Player
var hp := 10.0
var vel := Vector3.ZERO
var on_ground := false
var half := 0.35
var height := 0.9
var hostile := false
var speed := 1.5
var dir := Vector3.ZERO
var panic := 0.0
var _wander_t := 0.0
var _hurt_t := 0.0
var _attack_cd := 0.0
var _burn_t := 0.0
var _walk := 0.0
var _dead := false
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _parts: Array[MeshInstance3D] = []
var _base: Array[Color] = []


func setup(k: int, w: VoxelWorld, p: Player) -> void:
	kind = k as Kind
	world = w
	player = p
	add_to_group("mobs")
	match kind:
		Kind.PIG:
			_build_pig()
		Kind.COW:
			_build_cow()
		Kind.ZOMBIE:
			_build_zombie()
		Kind.SHEEP:
			_build_sheep()
	rotation.y = randf() * TAU


func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	_parts.append(mi)
	_base.append(col)
	return mi


func _pivot(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	return n


func _build_pig() -> void:
	hp = 10.0
	half = 0.38
	height = 0.85
	speed = 1.5
	var pink := Color(0.95, 0.65, 0.7)
	_box(self, Vector3(0.6, 0.5, 0.9), Vector3(0, 0.55, 0), pink)
	_box(self, Vector3(0.46, 0.4, 0.4), Vector3(0, 0.68, -0.62), pink.lightened(0.08))
	_box(self, Vector3(0.24, 0.17, 0.1), Vector3(0, 0.6, -0.85), Color(0.85, 0.5, 0.55))
	for pos in [Vector3(-0.18, 0.3, -0.3), Vector3(0.18, 0.3, -0.3), Vector3(-0.18, 0.3, 0.3), Vector3(0.18, 0.3, 0.3)]:
		var pv := _pivot(pos)
		_box(pv, Vector3(0.18, 0.3, 0.18), Vector3(0, -0.15, 0), pink.darkened(0.1))
		_legs.append(pv)


func _build_cow() -> void:
	hp = 12.0
	half = 0.45
	height = 1.4
	speed = 1.3
	var brown := Color(0.42, 0.27, 0.17)
	_box(self, Vector3(0.7, 0.7, 1.1), Vector3(0, 0.95, 0), brown)
	_box(self, Vector3(0.5, 0.5, 0.45), Vector3(0, 1.15, -0.78), brown.lightened(0.05))
	_box(self, Vector3(0.3, 0.2, 0.1), Vector3(0, 1.05, -1.02), Color(0.85, 0.75, 0.65))
	_box(self, Vector3(0.45, 0.1, 0.6), Vector3(0, 0.62, 0.05), Color(0.9, 0.88, 0.82))
	for pos in [Vector3(-0.22, 0.6, -0.4), Vector3(0.22, 0.6, -0.4), Vector3(-0.22, 0.6, 0.4), Vector3(0.22, 0.6, 0.4)]:
		var pv := _pivot(pos)
		_box(pv, Vector3(0.2, 0.6, 0.2), Vector3(0, -0.3, 0), brown.darkened(0.15))
		_legs.append(pv)


func _build_sheep() -> void:
	hp = 8.0
	half = 0.4
	height = 1.2
	speed = 1.4
	var wool := Color(0.93, 0.93, 0.93)
	var face := Color(0.78, 0.7, 0.62)
	_box(self, Vector3(0.7, 0.65, 1.0), Vector3(0, 0.8, 0), wool)
	_box(self, Vector3(0.42, 0.42, 0.42), Vector3(0, 0.98, -0.66), face)
	_box(self, Vector3(0.46, 0.2, 0.3), Vector3(0, 1.22, -0.6), wool)
	for pos in [Vector3(-0.2, 0.5, -0.32), Vector3(0.2, 0.5, -0.32), Vector3(-0.2, 0.5, 0.32), Vector3(0.2, 0.5, 0.32)]:
		var pv := _pivot(pos)
		_box(pv, Vector3(0.17, 0.5, 0.17), Vector3(0, -0.25, 0), face.darkened(0.1))
		_legs.append(pv)


func _build_zombie() -> void:
	hp = 20.0
	half = 0.3
	height = 1.9
	speed = 2.3
	hostile = true
	var skin := Color(0.35, 0.6, 0.32)
	var shirt := Color(0.2, 0.35, 0.65)
	var pants := Color(0.25, 0.22, 0.5)
	_box(self, Vector3(0.56, 0.75, 0.3), Vector3(0, 1.125, 0), shirt)
	_box(self, Vector3(0.5, 0.5, 0.5), Vector3(0, 1.75, 0), skin)
	for x in [-0.15, 0.15]:
		var pv := _pivot(Vector3(x, 0.75, 0))
		_box(pv, Vector3(0.27, 0.75, 0.27), Vector3(0, -0.375, 0), pants)
		_legs.append(pv)
	for x in [-0.4, 0.4]:
		var av := _pivot(Vector3(x, 1.42, 0))
		_box(av, Vector3(0.22, 0.7, 0.22), Vector3(0, -0.3, 0), skin)
		av.rotation.x = -PI * 0.5
		_arms.append(av)


func ray_t(o: Vector3, d: Vector3) -> float:
	var mn := position + Vector3(-half, 0, -half)
	var mx := position + Vector3(half, height, half)
	var tmin := 0.0
	var tmax := 1e9
	for i in range(3):
		var oi: float = o[i]
		var di: float = d[i]
		if absf(di) < 0.000001:
			if oi < mn[i] or oi > mx[i]:
				return -1.0
		else:
			var t1: float = (mn[i] - oi) / di
			var t2: float = (mx[i] - oi) / di
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin


func hurt(dmg: float, from: Vector3 = Vector3.ZERO, knock := true) -> void:
	if _dead:
		return
	hp -= dmg
	_hurt_t = 0.25
	if knock:
		vel.x += from.x * 7.0
		vel.z += from.z * 7.0
		vel.y = 5.0
	if not hostile:
		panic = 4.0
	if hp <= 0.0:
		_dead = true
		player.on_mob_killed(kind)
		remove_from_group("mobs")
		queue_free()


func _process(delta: float) -> void:
	if world == null or player == null or _dead:
		return
	delta = minf(delta, 0.05)
	if world.get_block(floori(position.x), clampi(floori(position.y), 0, VoxelWorld.CH - 1), floori(position.z)) < 0:
		return
	_ai(delta)
	_physics(delta)
	_animate(delta)


func _ai(delta: float) -> void:
	_hurt_t = maxf(0.0, _hurt_t - delta)
	_attack_cd -= delta
	panic -= delta
	var to_p := player.position - position
	to_p.y = 0.0
	var dist := to_p.length()
	if hostile and not player.creative and not player.dead and dist < 22.0:
		dir = to_p.normalized() if dist > 0.01 else Vector3.ZERO
		if dist < 1.2 and absf(player.position.y - position.y) < 1.6 and _attack_cd <= 0.0:
			player.hurt(3.0, dir)
			_attack_cd = 1.0
	elif panic > 0.0 and dist > 0.01:
		dir = -to_p.normalized()
	else:
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(2.0, 5.0)
			if randf() < 0.4:
				dir = Vector3.ZERO
			else:
				var a := randf() * TAU
				dir = Vector3(cos(a), 0, sin(a))
	if hostile and world.light_level > 0.85:
		_burn_t += delta
		if _burn_t >= 1.0:
			_burn_t = 0.0
			if _sky_exposed():
				hurt(2.0, Vector3.ZERO, false)
	if dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(1.0, delta * 8.0))


func _sky_exposed() -> bool:
	var x := floori(position.x)
	var z := floori(position.z)
	for y in range(floori(position.y + height), VoxelWorld.CH):
		if VoxelWorld.is_solid(world.get_block(x, y, z)):
			return false
	return true


func _fluid_at(p: Vector3) -> int:
	return VoxelWorld.fluid_kind(world.get_block(floori(p.x), floori(p.y), floori(p.z)))


func _hit(p: Vector3) -> bool:
	var x0 := floori(p.x - half)
	var x1 := floori(p.x + half - 0.0001)
	var y0 := floori(p.y)
	var y1 := floori(p.y + height - 0.0001)
	var z0 := floori(p.z - half)
	var z1 := floori(p.z + half - 0.0001)
	for y in range(y0, y1 + 1):
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var b := world.get_block(x, y, z)
				if b < 0 or VoxelWorld.is_solid(b):
					return true
	return false


func _physics(delta: float) -> void:
	var fk := _fluid_at(position + Vector3(0, 0.3, 0))
	var spd := speed * (2.0 if panic > 0.0 else 1.0)
	var k := minf(1.0, delta * 10.0)
	vel.x = lerpf(vel.x, dir.x * spd, k)
	vel.z = lerpf(vel.z, dir.z * spd, k)
	if fk != 0:
		vel.y = maxf(vel.y - 8.0 * delta, -2.0)
		if dir.length() > 0.1:
			vel.y = 2.0
		if fk == VoxelWorld.LAVA:
			hurt(6.0 * delta, Vector3.ZERO, false)
	else:
		vel.y = maxf(vel.y - 28.0 * delta, -40.0)
	var was_ground := on_ground
	on_ground = false
	var blocked := false
	var d := vel * delta
	var p := position
	p.x += d.x
	if _hit(p):
		p.x -= d.x
		vel.x = 0.0
		blocked = true
	p.z += d.z
	if _hit(p):
		p.z -= d.z
		vel.z = 0.0
		blocked = true
	p.y += d.y
	if _hit(p):
		if d.y < 0.0:
			on_ground = true
			var q := Vector3(p.x, floorf(p.y) + 1.001, p.z)
			p = q if not _hit(q) else Vector3(p.x, p.y - d.y, p.z)
		else:
			p.y -= d.y
		vel.y = 0.0
	position = p
	if blocked and was_ground and dir.length() > 0.1:
		vel.y = 8.0


func _animate(delta: float) -> void:
	var hs := Vector2(vel.x, vel.z).length()
	_walk += hs * delta * 4.0
	var amp := clampf(hs * 0.5, 0.0, 0.7)
	for i in range(_legs.size()):
		var ph := 0.0 if (i == 0 or i == 3) else PI
		_legs[i].rotation.x = sin(_walk + ph) * amp
	for i in range(_arms.size()):
		_arms[i].rotation.x = -PI * 0.5 + sin(_walk * 0.5 + float(i)) * 0.1
	var l := world.light_level
	var red := Color(1, 0.2, 0.2)
	for i in range(_parts.size()):
		var c := _base[i] * l
		c.a = 1.0
		if _hurt_t > 0.0:
			c = c.lerp(red, 0.6)
		(_parts[i].material_override as StandardMaterial3D).albedo_color = c
