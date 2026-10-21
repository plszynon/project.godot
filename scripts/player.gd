class_name Player
extends Node3D
## Gracz: własne kolizje z blokami, latanie, kopanie i stawianie.

const HALF := 0.3
const HEIGHT := 1.8
const EYE := 1.62
const REACH := 6.0

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
var inventory := {}
var target: Dictionary = {}
var _cd := 0.0


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
	var corners := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)]
	var edges := [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
	var verts := PackedVector3Array()
	for e in edges:
		for i in e:
			verts.append(corners[i] * 1.006 - Vector3(0.003, 0.003, 0.003))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0, 0, 0, 1)
	m.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.top_level = true
	mi.visible = false
	return mi


func toggle_fly() -> void:
	flying = not flying
	vel = Vector3.ZERO


func _process(delta: float) -> void:
	if frozen or hud == null or world == null:
		return
	delta = minf(delta, 0.05)
	var look := hud.consume_look()
	rotation.y -= look.x * 0.0045
	pitch = clampf(pitch - look.y * 0.0045, -1.5, 1.5)
	cam.rotation.x = pitch
	_move(delta)
	_update_target()
	_actions(delta)


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
		vel.x = wish.x * spd
		vel.z = wish.z * spd
		if fk != 0:
			vel.y = maxf(vel.y - 8.0 * delta, -2.5)
			if jump:
				vel.y = 3.6
		else:
			vel.y = maxf(vel.y - 28.0 * delta, -40.0)
			if jump and on_ground:
				vel.y = 8.6
	_step(vel * delta)


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


func _update_target() -> void:
	var dir := -cam.global_transform.basis.z
	target = world.raycast(cam.global_position, dir, REACH)
	if target.is_empty():
		outline.visible = false
	else:
		outline.visible = true
		outline.global_position = Vector3(target.pos)


func _actions(delta: float) -> void:
	_cd -= delta
	var fire := false
	if hud.action_tap:
		fire = true
		hud.action_tap = false
	elif hud.action_held and _cd <= 0.0:
		fire = true
	if not fire:
		return
	_cd = 0.22
	if target.is_empty():
		return
	if hud.build_mode:
		_place()
	else:
		_break()


func _break() -> void:
	var p: Vector3i = target.pos
	var b: int = target.block
	world.set_block(p.x, p.y, p.z, VoxelWorld.AIR)
	if not creative:
		if b == VoxelWorld.SNOW:
			b = VoxelWorld.DIRT
		inventory[b] = inventory.get(b, 0) + 1


func _place() -> void:
	var np: Vector3i = target.pos + target.normal
	var cur := world.get_block(np.x, np.y, np.z)
	if cur != VoxelWorld.AIR and not VoxelWorld.is_fluid(cur):
		return
	var id: int = VoxelWorld.HOTBAR[hud.selected]
	if not creative and inventory.get(id, 0) <= 0:
		return
	if VoxelWorld.is_solid(id) and _overlaps(np):
		return
	world.set_block(np.x, np.y, np.z, id)
	if not creative:
		inventory[id] -= 1


func _overlaps(b: Vector3i) -> bool:
	var p := position
	return p.x - HALF < b.x + 1 and p.x + HALF > b.x \
		and p.y < b.y + 1 and p.y + HEIGHT > b.y \
		and p.z - HALF < b.z + 1 and p.z + HALF > b.z
