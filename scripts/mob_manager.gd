class_name MobManager
extends Node
## Pojawianie i znikanie mobów wokół gracza.

var world: VoxelWorld
var player: Player
var _t := 0.0


func _process(delta: float) -> void:
	if world == null or player == null:
		return
	_t += delta
	if _t < 1.5:
		return
	_t = 0.0
	var passive := 0
	var hostile := 0
	for m: Mob in get_tree().get_nodes_in_group("mobs"):
		var d := m.position.distance_to(player.position)
		if d > 60.0 or (m.hostile and player.creative):
			m.remove_from_group("mobs")
			m.queue_free()
			continue
		if m.hostile:
			hostile += 1
		else:
			passive += 1
	if passive < 7 and randf() < 0.5:
		_try_spawn([Mob.Kind.PIG, Mob.Kind.COW, Mob.Kind.SHEEP].pick_random())
	var night := world.light_level < 0.5
	if night and not player.creative and hostile < 5 and randf() < 0.6:
		_try_spawn(Mob.Kind.ZOMBIE)


func _try_spawn(kind: int) -> void:
	var a := randf() * TAU
	var r := randf_range(14.0, 30.0)
	var x := floori(player.position.x + cos(a) * r)
	var z := floori(player.position.z + sin(a) * r)
	if world.get_block(x, 0, z) < 0:
		return
	var y := world.surface_y(x, z)
	var ground := world.get_block(x, y, z)
	if kind != Mob.Kind.ZOMBIE and ground != VoxelWorld.GRASS:
		return
	if kind == Mob.Kind.ZOMBIE and not VoxelWorld.is_solid(ground):
		return
	if world.get_block(x, y + 1, z) != VoxelWorld.AIR or world.get_block(x, y + 2, z) != VoxelWorld.AIR:
		return
	var m := Mob.new()
	add_child(m)
	m.setup(kind, world, player)
	m.position = Vector3(x + 0.5, y + 1.01, z + 0.5)
