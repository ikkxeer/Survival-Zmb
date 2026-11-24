extends Camera3D
## One continuous camera. The wheel slides from the high tactical view to a low
## third-person view; dragging with the right button orbits around the player.
## It never changes simulation coordinates: movement input is rotated by `yaw`.

const Map = preload("res://game/map.gd")
const ZOOM_STEP := 0.1

var yaw := 0.0            # 0: camera south of the player looking north
var tilt := 0.0           # player adjustment on top of the zoom-derived elevation
var zoom_t := 1.0         # 1 tactical, 0 third person
var zoom_goal := 1.0
var pivot := Vector3.ZERO
var boom := 22.0
var tracking := false
var sensitivity := 1.0
var obstacles:Array[AABB] = []

func _ready():
	near = 0.1
	far = 220.0
	for r in Map.solids():
		var h := 5.5 if r.size.x > 1.5 else 4.0
		obstacles.append(AABB(Vector3(r.position.x, 0, r.position.y), Vector3(r.size.x, h, r.size.y)))
	apply_lens()

func reset():
	tracking = false
	yaw = 0.0
	tilt = 0.0
	zoom_t = 1.0
	zoom_goal = 1.0
	apply_lens()

func distance() -> float:
	return lerpf(6.0, 22.0, zoom_t)

func elevation() -> float:
	return clampf(lerpf(0.3, 0.9, zoom_t) + tilt, 0.12, 1.25)

func apply_lens():
	fov = lerpf(56.0, 40.0, zoom_t)

func orbit(motion:Vector2):
	yaw -= motion.x * 0.005 * sensitivity
	tilt = clampf(tilt + motion.y * 0.004 * sensitivity, -0.35, 0.35)

func zoom(direction:int):
	zoom_goal = clampf(zoom_goal + direction * ZOOM_STEP, 0.0, 1.0)

func movement(input:Vector2) -> Vector2:
	return input.rotated(-yaw)

func axis() -> Vector3:
	var e := elevation()
	return Vector3(sin(yaw) * cos(e), sin(e), cos(yaw) * cos(e))

func follow(target:Vector3, dt:float, shake:Vector3 = Vector3.ZERO):
	zoom_t = move_toward(zoom_t, zoom_goal, dt * 3.0)
	apply_lens()
	var goal := target + Vector3.UP * lerpf(1.3, 0.0, zoom_t)
	if not tracking:
		pivot = goal
		boom = distance()
		tracking = true
	else:
		pivot = pivot.lerp(goal, 1.0 - exp(-12.0 * dt))
	var dir := axis()
	var want := distance()
	var clearance := want
	# From high up the view clears the roofs; only the low third-person boom needs collision.
	if zoom_t < 0.55:
		clearance = clear_distance(dir, want)
	boom = minf(clearance, lerpf(boom, clearance, 1.0 - exp(-6.0 * dt)))
	position = pivot + dir * boom + shake
	look_at(pivot + shake * 0.5)

func clear_distance(dir:Vector3, want:float) -> float:
	var clearance := want
	for b in obstacles:
		var hit = b.intersects_segment(pivot, pivot + dir * want)
		if hit != null: clearance = minf(clearance, maxf(0.6, pivot.distance_to(hit) - 0.25))
	return clearance

func aim_point(screen:Vector2, height:float = 1.0):
	## Point under the cursor on the firing plane, or null when the ray never reaches it.
	var o := project_ray_origin(screen)
	var n := project_ray_normal(screen)
	var hit = Plane(Vector3.UP, height).intersects_ray(o, n)
	if hit == null or (hit as Vector3).distance_to(o) > 90.0: return null
	return hit
