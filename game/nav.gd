extends RefCounted
## 1 m navigation grid shared by every peer: static obstacles, player structures,
## collision queries and Dijkstra flow fields towards each objective.
## Flow fields are rebuilt lazily (one per tick) when structures change.

const Map = preload("res://game/map.gd")
const Data = preload("res://game/data.gd")
const INF_D := 1 << 29
const NB := 512                       # bucket ring for Dial's algorithm (max edge cost < NB)
const DIRS = [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]

var W := Map.GRID_SIZE.x
var H := Map.GRID_SIZE.y
var OX := Map.GRID_ORIGIN.x
var OZ := Map.GRID_ORIGIN.y
var solid := PackedByteArray()        # buildings, props, trees, beacons
var skind := PackedInt32Array()       # structure kind per cell or -1
var shp := PackedFloat32Array()       # structure hp per cell (for path costs)
var seeds := {}                       # field key -> Array of cells
var cars := []                        # [centre, yaw] of each car (oriented boxes, see Map.cars)
var car_at := {}                      # cell -> indices of cars overlapping it
var fields := {}                      # "key:mode" -> PackedInt32Array
var dirty := {}                       # "key:mode" -> true
var active := {"base":true}           # objectives kept warm; others rebuild on demand
var delay := 0.0                      # debounce so several builds cause one rebuild

func _init():
	solid.resize(W * H)
	skind.resize(W * H)
	skind.fill(-1)
	shp.resize(W * H)
	for r in Map.solids(): mark_rect(r)
	mark_cars()
	for s in Map.SITES: solid[cell_of(s.beacon)] = 1
	var base_seeds := []
	var br:Rect2 = Map.BASE
	for x in range(int(br.position.x) - 1, int(br.end.x) + 1):
		for z in range(int(br.position.y) - 1, int(br.end.y) + 1):
			var c := cell_xz(x - OX, z - OZ)
			if c >= 0 and solid[c] == 0: base_seeds.append(c)
	seeds["base"] = base_seeds
	for i in Map.SITES.size():
		var list := []
		var bc := cell_of(Map.SITES[i].beacon)
		for d in DIRS:
			var n := cell_xz(bc % W + d.x, bc / W + d.y)
			if n >= 0 and solid[n] == 0: list.append(n)
		seeds["site%d" % i] = list
	mark_all_dirty()
	delay = 0.0

func mark_rect(r:Rect2):
	for x in range(int(r.position.x), int(r.end.x)):
		for z in range(int(r.position.y), int(r.end.y)):
			var c := cell_xz(x - OX, z - OZ)
			if c >= 0: solid[c] = 1

func mark_cars():
	## Cars collide with their exact oriented box. Cells mostly covered by one are
	## also solid (value 2) so flow fields route around and nobody builds there.
	cars = Map.cars()
	var half:Vector2 = Map.CAR_HALF
	var reach := half.length()
	for i in cars.size():
		var c:Vector2 = cars[i][0]
		for x in range(floori(c.x - reach), floori(c.x + reach) + 1):
			for z in range(floori(c.y - reach), floori(c.y + reach) + 1):
				var cell := cell_xz(x - OX, z - OZ)
				if cell < 0: continue
				if car_box_distance(i, Vector2(x + 0.5, z + 0.5)) < 0.72:
					if not car_at.has(cell): car_at[cell] = []
					car_at[cell].append(i)
				if solid[cell] == 0 and in_car(i, Vector2(x + 0.5, z + 0.5), 0.15): solid[cell] = 2

func car_local(i:int, p:Vector2) -> Vector2:
	return (p - cars[i][0]).rotated(cars[i][1])

func in_car(i:int, p:Vector2, grow:float = 0.0) -> bool:
	var l := car_local(i, p)
	return absf(l.x) <= Map.CAR_HALF.x + grow and absf(l.y) <= Map.CAR_HALF.y + grow

func car_box_distance(i:int, p:Vector2) -> float:
	## Distance from p to car i's box (0 inside).
	var l := car_local(i, p)
	var q := Vector2(maxf(absf(l.x) - Map.CAR_HALF.x, 0.0), maxf(absf(l.y) - Map.CAR_HALF.y, 0.0))
	return q.length()

func cell_xz(x:int, z:int) -> int:
	if x < 0 or z < 0 or x >= W or z >= H: return -1
	return z * W + x

func cell_of(p:Vector2) -> int:
	return cell_xz(floori(p.x) - OX, floori(p.y) - OZ)

func center(c:int) -> Vector2:
	return Vector2(c % W + OX + 0.5, c / W + OZ + 0.5)

# ------------------------------------------------------------------ structures
func set_structure(c:int, kind:int, hp:float):
	if c < 0: return
	var changed := skind[c] != kind
	skind[c] = kind
	shp[c] = hp
	if changed: mark_all_dirty()

func clear_structure(c:int):
	if c < 0 or skind[c] < 0: return
	skind[c] = -1
	shp[c] = 0
	mark_all_dirty()

func mark_all_dirty():
	delay = 0.3
	for key in seeds:
		for mode in 2:
			var k := "%s:%d" % [key, mode]
			if active.has(key): dirty[k] = true
			else: fields.erase(k)

func is_free_for_build(c:int) -> bool:
	return c >= 0 and solid[c] == 0 and skind[c] < 0

func blocks(c:int, who:int) -> bool:
	## who: 0 player, 1 zombie, 2 climber
	if c < 0: return who == 0
	if solid[c]: return true
	var k := skind[c]
	if k < 0 or who == 2: return false
	var def:Dictionary = Data.STRUCTURES[k]
	if not def.block: return false
	if who == 0 and def.vault: return false
	return true

func enter_cost(c:int, mode:int) -> int:
	var k := skind[c]
	if k < 0: return 0
	var def:Dictionary = Data.STRUCTURES[k]
	if mode == 1: return 14 if def.block else 4
	if not def.block: return 24 if k == Data.S_WIRE else 0
	return mini(NB - 40, 12 + int(shp[c] * 0.45))

# ------------------------------------------------------------------ flow fields
func update_one(dt:float = 0.0) -> bool:
	## Rebuild a single stale field. Returns true when something was rebuilt.
	delay -= dt
	if delay > 0: return false
	for key in dirty.keys():
		var parts:PackedStringArray = key.split(":")
		build(parts[0], int(parts[1]))
		dirty.erase(key)
		return true
	return false

func build(target:String, mode:int):
	var dist := PackedInt32Array()
	dist.resize(W * H)
	dist.fill(INF_D)
	var buckets := []
	buckets.resize(NB)
	for i in NB: buckets[i] = []
	var pending := 0
	for s in seeds[target]:
		dist[s] = 0
		buckets[0].append(s)
		pending += 1
	var d := 0
	while pending > 0:
		var b:Array = buckets[d % NB]
		if b.is_empty():
			d += 1
			continue
		var c:int = b.pop_back()
		pending -= 1
		if dist[c] != d: continue
		var cx := c % W
		var cz := c / W
		for i in 8:
			var dir:Vector2i = DIRS[i]
			var nx := cx + dir.x
			var nz := cz + dir.y
			if nx < 0 or nz < 0 or nx >= W or nz >= H: continue
			var n := nz * W + nx
			if solid[n]: continue
			var step := 10
			if i >= 4:
				if solid[cz * W + nx] or solid[nz * W + cx]: continue
				if skind[cz * W + nx] >= 0 or skind[nz * W + cx] >= 0: continue
				step = 14
			var nd := d + step + enter_cost(n, mode)
			if nd < dist[n]:
				dist[n] = nd
				buckets[nd % NB].append(n)
				pending += 1
	fields["%s:%d" % [target, mode]] = dist

func field(target:String, mode:int) -> PackedInt32Array:
	var key := "%s:%d" % [target, mode]
	if not fields.has(key): build(target, mode)
	return fields[key]

func next_cell(target:String, mode:int, p:Vector2) -> int:
	## Best neighbouring cell to move into, or -1 when already at the goal / off-grid.
	var dist := field(target, mode)
	var c := cell_of(p)
	if c < 0: return -1
	var best := -1
	var best_d := dist[c]
	var cx := c % W
	var cz := c / W
	for i in 8:
		var dir:Vector2i = DIRS[i]
		var n := cell_xz(cx + dir.x, cz + dir.y)
		if n < 0 or solid[n]: continue
		if i >= 4 and (solid[cz * W + cx + dir.x] or solid[(cz + dir.y) * W + cx]): continue
		if dist[n] < best_d:
			best_d = dist[n]
			best = n
	return best

func distance_at(target:String, mode:int, p:Vector2) -> int:
	var c := cell_of(p)
	return INF_D if c < 0 else field(target, mode)[c]

# ------------------------------------------------------------------ collision
func blocked_cell(p:Vector2, r:float, who:int) -> int:
	## First grid cell overlapped by a circle that is solid for `who`, or -1.
	for x in range(floori(p.x - r), floori(p.x + r) + 1):
		for z in range(floori(p.y - r), floori(p.y + r) + 1):
			var c := cell_xz(x - OX, z - OZ)
			if c >= 0 and car_at.has(c):
				for i in car_at[c]:
					if car_box_distance(i, p) < r: return c
			if c >= 0 and solid[c] == 2 and skind[c] < 0: continue
			if not blocks(c, who): continue
			var q := Vector2(clampf(p.x, x, x + 1), clampf(p.y, z, z + 1))
			if q.distance_squared_to(p) < r * r: return c if c >= 0 else -2
	return -1

func move(p:Vector2, delta:Vector2, r:float, who:int) -> Vector2:
	## Axis-separated sliding movement.
	var out := p
	var tx := out + Vector2(delta.x, 0)
	if blocked_cell(tx, r, who) == -1: out = tx
	var tz := out + Vector2(0, delta.y)
	if blocked_cell(tz, r, who) == -1: out = tz
	return out

func ray(from:Vector2, dir:Vector2, length:float) -> float:
	## Distance until a static obstacle (buildings stop bullets, structures do not).
	var t := 0.3
	while t < length:
		var q := from + dir * t
		var c := cell_of(q)
		if c >= 0 and solid[c] == 1: return t
		if c >= 0 and car_at.has(c):
			for i in car_at[c]:
				if in_car(i, q): return t
		t += 0.25
	return length

func clear_line(a:Vector2, b:Vector2) -> bool:
	var d := a.distance_to(b)
	if d < 0.01: return true
	return ray(a, (b - a) / d, d) >= d - 0.01
