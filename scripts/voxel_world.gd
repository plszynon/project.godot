class_name VoxelWorld
extends Node3D
## Świat z bloków: generowanie z seeda, chunki, meshe, symulacja płynów i trawy.

const CS := 16            # rozmiar chunka (x, z)
const CH := 48            # wysokość świata
const TICK := 0.25        # co ile sekund krok symulacji
const GEN_BUDGET_US := 5000
const MESH_BUDGET_US := 6000

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const SAND := 4
const WOOD := 5
const LEAVES := 6
const OBSIDIAN := 7
const SNOW := 8
const PLANKS := 9
# Płyny: id = rodzaj * 16 + poziom (1..8, 8 = źródło)
const WATER := 1
const LAVA := 2
const HOTBAR := [1, 2, 3, 4, 5, 6, 7, 24, 40]

const COLORS := {
	1: Color(0.33, 0.62, 0.2),
	2: Color(0.45, 0.32, 0.2),
	3: Color(0.5, 0.5, 0.52),
	4: Color(0.86, 0.8, 0.52),
	5: Color(0.42, 0.3, 0.16),
	6: Color(0.18, 0.45, 0.15),
	7: Color(0.14, 0.08, 0.24),
	8: Color(0.95, 0.97, 1.0),
	9: Color(0.72, 0.55, 0.3),
	24: Color(0.15, 0.35, 0.85, 0.62),
	40: Color(1.0, 0.42, 0.05, 1.0),
}

const DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const HDIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

# Ściany: 0 góra, 1 dół, 2 +x, 3 -x, 4 +z, 5 -z (wierzchołki zgodnie z ruchem wskazówek zegara od zewnątrz)
const FACE_N := [Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const FACE_SHADE := [1.0, 0.55, 0.78, 0.78, 0.88, 0.88]
const FACE_V := [
	[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0)],
	[Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)],
]


class Chunk:
	var pos := Vector2i.ZERO
	var data := PackedByteArray()
	var node: MeshInstance3D = null
	var dirty := true
	var modified := false
	var top := 0
	var job := -1
	var result := {}


var R := 3               # promień widoczności w chunkach (z ustawień)
var seed_value := 0
var water_level := 14
var mountain := 1.0
var lava_amount := 0.5
var sim_speed := 1.0
var light_level := 1.0
var player_node: Node3D = null

var chunks := {}          # Vector2i -> Chunk
var active := {}          # Vector3i -> true (komórki płynów do przeliczenia)
var noise_a: FastNoiseLite
var noise_b: FastNoiseLite
var noise_m: FastNoiseLite
var mat_solid: StandardMaterial3D
var mat_fluid: StandardMaterial3D

var _wanted: Array[Vector2i] = []
var _wanted_mesh: Array[Vector2i] = []
var _last_cc := Vector2i(1 << 20, 1 << 20)
var _sim_accum := 0.0
var _jobs: Array[Chunk] = []


# ---------------------------------------------------------------- helpers
static func fluid_kind(b: int) -> int:
	if b > 16 and b < 48 and (b & 15) != 0:
		return b >> 4
	return 0

static func fluid_id(kind: int, level: int) -> int:
	return kind * 16 + level

static func is_fluid(b: int) -> bool:
	return fluid_kind(b) != 0

static func is_solid(b: int) -> bool:
	return b > 0 and fluid_kind(b) == 0


func setup(seed_v: int, water: int, mount: float, lava_amt: float) -> void:
	seed_value = seed_v
	R = Game.render_dist
	water_level = water
	mountain = mount
	lava_amount = lava_amt
	noise_a = _mk_noise(seed_v, 0.006, 3)
	noise_b = _mk_noise(seed_v + 1, 0.035, 2)
	noise_m = _mk_noise(seed_v + 2, 0.010, 3)
	mat_solid = StandardMaterial3D.new()
	mat_solid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_solid.vertex_color_use_as_albedo = true
	mat_fluid = StandardMaterial3D.new()
	mat_fluid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_fluid.vertex_color_use_as_albedo = true
	mat_fluid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_fluid.cull_mode = BaseMaterial3D.CULL_DISABLED


func _mk_noise(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.frequency = freq
	n.fractal_octaves = oct
	return n


func set_render_distance(r: int) -> void:
	R = clampi(r, 2, 6)
	_last_cc = Vector2i(1 << 20, 1 << 20)   # wymusza przeliczenie listy chunków


func set_light(l: float) -> void:
	light_level = l
	var c := Color(l, l, l, 1.0)
	mat_solid.albedo_color = c
	mat_fluid.albedo_color = c


func _hash(x: int, z: int, salt: int = 0) -> int:
	var h := x * 374761393 + z * 668265263 + seed_value * 1013904223 + salt * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff


func _height(wx: int, wz: int) -> int:
	var cont := noise_a.get_noise_2d(wx, wz)
	var det := noise_b.get_noise_2d(wx, wz)
	var mt := maxf(0.0, noise_m.get_noise_2d(wx, wz) - 0.1)
	var h := float(water_level) + 3.0 + cont * 9.0 + det * 3.0 + mt * mountain * 40.0
	return clampi(int(h), 2, CH - 9)


# ---------------------------------------------------------------- blocks
func get_block(x: int, y: int, z: int) -> int:
	if y < 0:
		return STONE
	if y >= CH:
		return AIR
	var c: Chunk = chunks.get(Vector2i(x >> 4, z >> 4))
	if c == null:
		return -1
	return c.data[(y * CS + (z & 15)) * CS + (x & 15)]


func set_block(x: int, y: int, z: int, b: int) -> void:
	if y < 0 or y >= CH:
		return
	var cp := Vector2i(x >> 4, z >> 4)
	var c: Chunk = chunks.get(cp)
	if c == null:
		return
	var lx := x & 15
	var lz := z & 15
	c.data[(y * CS + lz) * CS + lx] = b
	c.modified = true
	c.dirty = true
	if y >= c.top:
		c.top = y + 1
	if lx == 0:
		_mark_dirty(cp + Vector2i(-1, 0))
	elif lx == CS - 1:
		_mark_dirty(cp + Vector2i(1, 0))
	if lz == 0:
		_mark_dirty(cp + Vector2i(0, -1))
	elif lz == CS - 1:
		_mark_dirty(cp + Vector2i(0, 1))
	_activate(Vector3i(x, y, z))
	for d: Vector3i in DIRS:
		_activate(Vector3i(x + d.x, y + d.y, z + d.z))


func _mark_dirty(cp: Vector2i) -> void:
	var c: Chunk = chunks.get(cp)
	if c != null:
		c.dirty = true


func _activate(p: Vector3i) -> void:
	if fluid_kind(get_block(p.x, p.y, p.z)) != 0:
		active[p] = true


func surface_y(x: int, z: int) -> int:
	for y in range(CH - 1, -1, -1):
		var b := get_block(x, y, z)
		if b > 0 and fluid_kind(b) == 0:
			return y
	return 0


func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var p := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var sx := 1 if dir.x > 0.0 else -1
	var sy := 1 if dir.y > 0.0 else -1
	var sz := 1 if dir.z > 0.0 else -1
	var tdx := absf(1.0 / dir.x) if dir.x != 0.0 else INF
	var tdy := absf(1.0 / dir.y) if dir.y != 0.0 else INF
	var tdz := absf(1.0 / dir.z) if dir.z != 0.0 else INF
	var tmx := (float(p.x + (1 if sx > 0 else 0)) - origin.x) / dir.x if dir.x != 0.0 else INF
	var tmy := (float(p.y + (1 if sy > 0 else 0)) - origin.y) / dir.y if dir.y != 0.0 else INF
	var tmz := (float(p.z + (1 if sz > 0 else 0)) - origin.z) / dir.z if dir.z != 0.0 else INF
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		var b := get_block(p.x, p.y, p.z)
		if b > 0 and fluid_kind(b) == 0 and normal != Vector3i.ZERO:
			return {"pos": p, "normal": normal, "block": b, "t": t}
		if tmx < tmy and tmx < tmz:
			p.x += sx
			t = tmx
			tmx += tdx
			normal = Vector3i(-sx, 0, 0)
		elif tmy < tmz:
			p.y += sy
			t = tmy
			tmy += tdy
			normal = Vector3i(0, -sy, 0)
		else:
			p.z += sz
			t = tmz
			tmz += tdz
			normal = Vector3i(0, 0, -sz)
	return {}


# ---------------------------------------------------------------- generation
func find_spawn() -> Vector3:
	for r in range(0, 400, 8):
		for i in range(-r, r + 1, 8):
			for pt: Vector2i in [Vector2i(i, -r), Vector2i(i, r), Vector2i(-r, i), Vector2i(r, i)]:
				var h := _height(pt.x, pt.y)
				if h > water_level + 1 and h < 30:
					return Vector3(pt.x + 0.5, h + 2, pt.y + 0.5)
	return Vector3(8.5, 30, 8.5)


func ensure_chunk(cp: Vector2i) -> void:
	if not chunks.has(cp):
		chunks[cp] = _gen_chunk(cp)


func ensure_around(p: Vector3, radius: int) -> void:
	var cc := Vector2i(floori(p.x / CS), floori(p.z / CS))
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			ensure_chunk(cc + Vector2i(dx, dz))


func _gen_chunk(cp: Vector2i) -> Chunk:
	var c := Chunk.new()
	c.pos = cp
	if Game.save_chunks.has(cp):
		c.data = Game.save_chunks[cp]
		c.modified = true
		c.top = CH
		return c
	c.data.resize(CS * CH * CS)
	var ox := cp.x * CS
	var oz := cp.y * CS
	var hs := PackedInt32Array()
	hs.resize(CS * CS)
	var top := 0
	for z in range(CS):
		for x in range(CS):
			var wx := ox + x
			var wz := oz + z
			var h := _height(wx, wz)
			hs[z * CS + x] = h
			var beach := h <= water_level + 1
			for y in range(0, h + 1):
				var b := STONE
				if y == h:
					b = SAND if beach else (SNOW if h >= 36 else GRASS)
				elif y >= h - 3:
					b = SAND if beach else DIRT
				c.data[(y * CS + z) * CS + x] = b
			top = maxi(top, h + 1)
			if h < water_level:
				for y in range(h + 1, water_level + 1):
					c.data[(y * CS + z) * CS + x] = fluid_id(WATER, 8)
				top = maxi(top, water_level + 1)
			elif h >= 24 and lava_amount > 0.0 and _hash(wx, wz, 7) % 1000 < int(lava_amount * 5.0):
				c.data[(h * CS + z) * CS + x] = fluid_id(LAVA, 8)
				active[Vector3i(wx, h, wz)] = true
	# drzewa (tylko we wnętrzu chunka, żeby nie przekraczać granic)
	for z in range(2, CS - 2):
		for x in range(2, CS - 2):
			var h := hs[z * CS + x]
			if c.data[(h * CS + z) * CS + x] != GRASS:
				continue
			if _hash(ox + x, oz + z, 3) % 200 >= 3:
				continue
			var th := 4 + _hash(ox + x, oz + z, 4) % 2
			if h + th + 3 >= CH:
				continue
			for ty in range(1, th + 1):
				c.data[((h + ty) * CS + z) * CS + x] = WOOD
			for ly in range(th - 1, th + 2):
				var r := 2 if ly < th + 1 else 1
				for lz in range(-r, r + 1):
					for lx in range(-r, r + 1):
						if absi(lx) + absi(lz) > r + 1:
							continue
						var idx := ((h + ly) * CS + z + lz) * CS + x + lx
						if c.data[idx] == AIR:
							c.data[idx] = LEAVES
			top = maxi(top, h + th + 2)
	c.top = top
	return c


# ---------------------------------------------------------------- meshing
const OFFS := [256, -256, 1, -1, 16, -16]
const FDX := [0, 0, 1, -1, 0, 0]
const FDY := [1, -1, 0, 0, 0, 0]
const FDZ := [0, 0, 0, 0, 1, -1]
const MAX_JOBS := 3


func _nbj(data: PackedByteArray, dpx: PackedByteArray, dmx: PackedByteArray, dpz: PackedByteArray, dmz: PackedByteArray, x: int, y: int, z: int) -> int:
	if y < 0:
		return STONE
	if y >= CH:
		return AIR
	if x < 0:
		return dmx[(y * CS + z) * CS + CS - 1]
	if x >= CS:
		return dpx[(y * CS + z) * CS]
	if z < 0:
		return dmz[(y * CS + CS - 1) * CS + x]
	if z >= CS:
		return dpz[y * CS * CS + x]
	return data[(y * CS + z) * CS + x]


func _face_visible(b: int, nb: int) -> bool:
	if nb == 0:
		return true
	if nb < 0:
		return false
	if fluid_kind(nb) != 0:
		return true
	if nb == LEAVES:
		return b != LEAVES
	return false


func _add_quad(vs: PackedVector3Array, cs: PackedColorArray, idx: PackedInt32Array, o: Vector3, f: int, hs: float, col: Color) -> void:
	var base := vs.size()
	for v: Vector3 in FACE_V[f]:
		vs.append(o + Vector3(v.x, v.y * hs, v.z))
		cs.append(col)
	idx.append(base)
	idx.append(base + 1)
	idx.append(base + 2)
	idx.append(base)
	idx.append(base + 2)
	idx.append(base + 3)


func neighbors_loaded(cp: Vector2i) -> bool:
	return chunks.has(cp + Vector2i(1, 0)) and chunks.has(cp + Vector2i(-1, 0)) \
		and chunks.has(cp + Vector2i(0, 1)) and chunks.has(cp + Vector2i(0, -1))


## Czysta funkcja (bez dostępu do drzewa sceny) - może działać w wątku roboczym.
func _compute_mesh(data: PackedByteArray, top: int, ox: int, oz: int, dpx: PackedByteArray, dmx: PackedByteArray, dpz: PackedByteArray, dmz: PackedByteArray) -> Dictionary:
	var sv := PackedVector3Array()
	var sc := PackedColorArray()
	var si := PackedInt32Array()
	var fv := PackedVector3Array()
	var fc := PackedColorArray()
	var fi := PackedInt32Array()
	for y in range(mini(top, CH)):
		var ylim := y > 0 and y < CH - 1
		for z in range(CS):
			for x in range(CS):
				var idx := (y * CS + z) * CS + x
				var b: int = data[idx]
				if b == 0:
					continue
				var o := Vector3(x, y, z)
				var kind := fluid_kind(b)
				var inner := ylim and x > 0 and x < CS - 1 and z > 0 and z < CS - 1
				if kind == 0:
					for f in range(6):
						var nb: int
						if inner:
							nb = data[idx + OFFS[f]]
						else:
							nb = _nbj(data, dpx, dmx, dpz, dmz, x + FDX[f], y + FDY[f], z + FDZ[f])
						if nb > 0 and nb < 16 and nb != LEAVES:
							continue
						if not _face_visible(b, nb):
							continue
						var col: Color = COLORS[DIRT] if (b == GRASS and f != 0) else COLORS[b]
						var variation := 0.88 + 0.12 * float((((ox + x) * 73856093) ^ (y * 19349663) ^ ((oz + z) * 83492791)) & 7) / 7.0
						col = col * (FACE_SHADE[f] * variation)
						col.a = 1.0
						_add_quad(sv, sc, si, o, f, 1.0, col)
				else:
					var lvl := b & 15
					var above := _nbj(data, dpx, dmx, dpz, dmz, x, y + 1, z)
					var same_above := fluid_kind(above) == kind
					var h := 1.0 if same_above else maxf(0.1, 0.9 * float(lvl) / 8.0)
					var fcol: Color = Color(0.15, 0.35, 0.85, 0.62) if kind == WATER else Color(1.0, 0.42, 0.05, 1.0)
					if not same_above and not (above > 0 and is_solid(above) and above != LEAVES):
						_add_quad(fv, fc, fi, o, 0, h, fcol)
					for f in range(2, 6):
						var nb := _nbj(data, dpx, dmx, dpz, dmz, x + FDX[f], y, z + FDZ[f])
						var show := false
						if nb == 0 or nb == LEAVES:
							show = true
						elif fluid_kind(nb) == kind:
							show = (not same_above) and (nb & 15) < lvl
						if show:
							var c2 := fcol
							if kind == WATER:
								c2 = fcol * FACE_SHADE[f]
								c2.a = fcol.a
							_add_quad(fv, fc, fi, o, f, h, c2)
	return {"sv": sv, "sc": sc, "si": si, "fv": fv, "fc": fc, "fi": fi}


func _apply_mesh(c: Chunk, r: Dictionary) -> void:
	if c.node == null:
		c.node = MeshInstance3D.new()
		c.node.position = Vector3(c.pos.x * CS, 0, c.pos.y * CS)
		add_child(c.node)
	var mesh := ArrayMesh.new()
	var s := 0
	if r["sv"].size() > 0:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = r["sv"]
		arr[Mesh.ARRAY_COLOR] = r["sc"]
		arr[Mesh.ARRAY_INDEX] = r["si"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(s, mat_solid)
		s += 1
	if r["fv"].size() > 0:
		var arr2 := []
		arr2.resize(Mesh.ARRAY_MAX)
		arr2[Mesh.ARRAY_VERTEX] = r["fv"]
		arr2[Mesh.ARRAY_COLOR] = r["fc"]
		arr2[Mesh.ARRAY_INDEX] = r["fi"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
		mesh.surface_set_material(s, mat_fluid)
		s += 1
	c.node.mesh = mesh if s > 0 else null


func _neighbor_data(cp: Vector2i) -> Array:
	return [chunks[cp + Vector2i(1, 0)].data, chunks[cp + Vector2i(-1, 0)].data,
		chunks[cp + Vector2i(0, 1)].data, chunks[cp + Vector2i(0, -1)].data]


## Synchroniczne budowanie (testy, start gry).
func build_mesh(c: Chunk) -> void:
	var n := _neighbor_data(c.pos)
	var r := _compute_mesh(c.data, c.top, c.pos.x * CS, c.pos.y * CS, n[0], n[1], n[2], n[3])
	c.dirty = false
	_apply_mesh(c, r)


## Asynchroniczne budowanie w wątku roboczym.
func dispatch_mesh(c: Chunk) -> void:
	var n := _neighbor_data(c.pos)
	var d := c.data
	var tp := c.top
	var cp := c.pos
	c.dirty = false
	c.job = WorkerThreadPool.add_task(func(): c.result = _compute_mesh(d, tp, cp.x * CS, cp.y * CS, n[0], n[1], n[2], n[3]))
	_jobs.append(c)


# ---------------------------------------------------------------- streaming
func _process(delta: float) -> void:
	if player_node == null:
		return
	update_streaming()
	if sim_speed > 0.0:
		_sim_accum += delta * sim_speed
		if _sim_accum >= TICK:
			_sim_accum = 0.0
			sim_step(400)
			_random_ticks(60)


func update_streaming() -> void:
	var pp := player_node.position
	var cc := Vector2i(floori(pp.x / CS), floori(pp.z / CS))
	if cc != _last_cc:
		_last_cc = cc
		_rebuild_wanted(cc)
		_unload_far(cc)
	var t0 := Time.get_ticks_usec()
	for cp in _wanted:
		if not chunks.has(cp):
			chunks[cp] = _gen_chunk(cp)
			if Time.get_ticks_usec() - t0 > GEN_BUDGET_US:
				break
	var still: Array[Chunk] = []
	var applied := 0
	for c in _jobs:
		if applied < 3 and WorkerThreadPool.is_task_completed(c.job):
			WorkerThreadPool.wait_for_task_completion(c.job)
			c.job = -1
			_apply_mesh(c, c.result)
			c.result = {}
			applied += 1
		else:
			still.append(c)
	_jobs = still
	for cp in _wanted_mesh:
		if _jobs.size() >= MAX_JOBS:
			break
		var c: Chunk = chunks.get(cp)
		if c != null and c.dirty and c.job < 0 and neighbors_loaded(cp):
			dispatch_mesh(c)


func _rebuild_wanted(cc: Vector2i) -> void:
	_wanted.clear()
	_wanted_mesh.clear()
	var list := []
	for dz in range(-R - 1, R + 2):
		for dx in range(-R - 1, R + 2):
			var d2 := dx * dx + dz * dz
			if d2 <= (R + 1) * (R + 1) + 1:
				list.append([d2, cc + Vector2i(dx, dz)])
	list.sort_custom(func(a, b): return a[0] < b[0])
	for e in list:
		_wanted.append(e[1])
		if e[0] <= R * R + 1:
			_wanted_mesh.append(e[1])


func _unload_far(cc: Vector2i) -> void:
	var lim := (R + 3) * (R + 3)
	for cp: Vector2i in chunks.keys():
		if (cp - cc).length_squared() > lim:
			var c: Chunk = chunks[cp]
			if c.job >= 0:
				WorkerThreadPool.wait_for_task_completion(c.job)
				c.job = -1
				_jobs.erase(c)
			if c.modified:
				Game.save_chunks[cp] = c.data
			if c.node != null:
				c.node.queue_free()
			chunks.erase(cp)


func collect_modified() -> Dictionary:
	var out: Dictionary = Game.save_chunks.duplicate()
	for cp in chunks:
		var c: Chunk = chunks[cp]
		if c.modified:
			out[cp] = c.data
	return out


# ---------------------------------------------------------------- żywy świat
func sim_step(max_cells: int) -> void:
	var cur := active
	active = {}
	var n := 0
	for p: Vector3i in cur.keys():
		if n >= max_cells:
			active[p] = true
			continue
		n += 1
		_process_fluid(p)


func _process_fluid(p: Vector3i) -> void:
	var b := get_block(p.x, p.y, p.z)
	var kind := fluid_kind(b)
	if kind == 0:
		return
	var level := b & 15
	var dec := 1 if kind == WATER else 2
	# lawa + woda = obsydian / kamień
	if kind == LAVA:
		for d: Vector3i in DIRS:
			if fluid_kind(get_block(p.x + d.x, p.y + d.y, p.z + d.z)) == WATER:
				set_block(p.x, p.y, p.z, OBSIDIAN if level == 8 else STONE)
				return
	# płyn bez źródła zanika albo dostosowuje poziom
	if level < 8:
		var expected := 0
		if fluid_kind(get_block(p.x, p.y + 1, p.z)) == kind:
			expected = 7
		for d: Vector3i in HDIRS:
			var nb := get_block(p.x + d.x, p.y, p.z + d.z)
			if fluid_kind(nb) == kind:
				expected = maxi(expected, (nb & 15) - dec)
		if expected <= 0:
			set_block(p.x, p.y, p.z, AIR)
			return
		if expected != level:
			set_block(p.x, p.y, p.z, fluid_id(kind, expected))
			return
	# spływanie w dół
	var below := get_block(p.x, p.y - 1, p.z)
	if below == AIR:
		set_block(p.x, p.y - 1, p.z, fluid_id(kind, 7))
		return
	var bk := fluid_kind(below)
	if bk == kind:
		if (below & 15) < 7:
			set_block(p.x, p.y - 1, p.z, fluid_id(kind, 7))
	elif bk != 0 and kind == WATER:
		set_block(p.x, p.y - 1, p.z, OBSIDIAN if (below & 15) == 8 else STONE)
	# rozlewanie na boki
	var nl := level - dec
	if nl < 1:
		return
	for d: Vector3i in HDIRS:
		var q := Vector3i(p.x + d.x, p.y, p.z + d.z)
		var nb := get_block(q.x, q.y, q.z)
		if nb == AIR:
			set_block(q.x, q.y, q.z, fluid_id(kind, nl))
		elif fluid_kind(nb) == kind:
			if (nb & 15) < nl:
				set_block(q.x, q.y, q.z, fluid_id(kind, nl))
		elif fluid_kind(nb) != 0 and kind == WATER:
			set_block(q.x, q.y, q.z, OBSIDIAN if (nb & 15) == 8 else STONE)


func _random_ticks(count: int) -> void:
	var pp := player_node.position
	for i in range(count):
		var x := int(pp.x) + randi_range(-40, 40)
		var z := int(pp.z) + randi_range(-40, 40)
		var y := CH - 1
		var b := 0
		while y >= 0:
			b = get_block(x, y, z)
			if b != AIR:
				break
			y -= 1
		if b < 0 or y < 0:
			continue
		if b == DIRT:
			if get_block(x, y + 1, z) == AIR:
				for d: Vector3i in HDIRS:
					if get_block(x + d.x, y, z + d.z) == GRASS:
						set_block(x, y, z, GRASS)
						break
		elif is_solid(b) and b != LEAVES and y > 0:
			if get_block(x, y - 1, z) == GRASS:
				set_block(x, y - 1, z, DIRT)
