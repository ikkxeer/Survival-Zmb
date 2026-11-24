extends Camera3D
## Local orbit and zoom never change the authoritative simulation coordinates.
var yaw := 0.45
var elevation := 0.29
var distance := 7.4
var boom := 7.4
var tracking := false
var pivot := Vector3.ZERO

func _ready():
	fov = 57
	near = 0.08
	far = 160
	overview()

func overview():
	tracking = false
	yaw = 0.45
	elevation = 0.29
	distance = 7.4
	position = Vector3(10,5,12)
	look_at(Vector3(-1,1.0,0))

func orbit(motion:Vector2):
	yaw -= motion.x*0.005
	elevation = clampf(elevation+motion.y*0.004,0.12,0.88)

func zoom(direction:int):
	distance = clampf(distance + direction*0.8,4.4,11.0)

func movement(input:Vector2) -> Vector2:
	return input.rotated(-yaw)

func follow(target:Vector3,obstacles:Array[AABB],dt:float):
	var goal := target+Vector3.UP*1.25
	if not tracking:
		pivot = goal
		boom = distance
		tracking = true
	else:
		pivot = pivot.lerp(goal,1-exp(-18*dt))
	var axis := Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))
	var clearance := distance
	for bounds in obstacles:
		var hit = bounds.intersects_segment(pivot,pivot+axis*distance)
		if hit != null:
			clearance = minf(clearance,maxf(0.15,pivot.distance_to(hit)-0.16))
	boom = minf(clearance,lerpf(boom,clearance,1-exp(-6*dt)))
	position = pivot+axis*boom
	look_at(pivot)
