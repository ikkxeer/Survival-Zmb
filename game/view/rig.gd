extends Node3D
## Procedurally animated character: chibi heroes, sprouted zombies and neighbours.
## Parts are separate MeshInstances parented to pivots so limbs can swing.

var body := Node3D.new()      # squash / bob / lean
var head := Node3D.new()
var eyes:MeshInstance3D
var arm_l := Node3D.new()
var arm_r := Node3D.new()
var leg_l := Node3D.new()
var leg_r := Node3D.new()
var gun := Node3D.new()
var pan:MeshInstance3D
var extra := Node3D.new()     # sprouts, hats that wobble
var parts := []
var blob:MeshInstance3D
var label:Label3D
var bar:MeshInstance3D
var flashlight:SpotLight3D
var zombie := false
var kind := 0
var height := 2.0
var phase := 0.0
var blink := 2.0
var recoil := 0.0
var swing := 0.0
var hit_flash := 0.0
var yaw := 0.0
var last := Vector3.ZERO
var speed := 0.0
var lean := 0.0
var spawn_t := 0.0
var death := -1.0
var roll_t := 0.0
var gun_kind := -1
var aim_blend := 0.0
var shake := 0.0
var bob_scale := 1.0
var ground_vel := Vector2.ZERO   # smoothed world velocity on the ground plane
var fire_t := 0.0                # keeps the weapon raised for a moment after shooting
var hip_y := 0.0
var gun_home := Vector3.ZERO
var move_amt := 0.0
const ROLL_TIME := 0.34          # matches the dodge length in main.gd
var rummage := false             # searching a container or car: lean in and dig
var bar_t := 0.0                 # health bar shows for a moment after a hit

func setup_pivots(shoulder_y:float, shoulder_x:float, hip_y:float, hip_x:float, neck_y:float):
	add_child(body)
	body.add_child(head)
	head.position = Vector3(0, neck_y, 0)
	head.add_child(extra)
	for a in [[arm_l, -1], [arm_r, 1]]:
		body.add_child(a[0])
		a[0].position = Vector3(a[1] * shoulder_x, shoulder_y, 0)
	for l in [[leg_l, -1], [leg_r, 1]]:
		body.add_child(l[0])
		l[0].position = Vector3(l[1] * hip_x, hip_y, 0)
	body.add_child(gun)
	gun.position = Vector3(0.2, shoulder_y - 0.12, 0.38)
	gun_home = gun.position
	self.hip_y = hip_y

func muzzle_point() -> Vector3:
	## Tip of the held weapon in world space (where shots visually start).
	if not is_inside_tree(): return global_position + Vector3(0, 1.1, 0)
	return gun.global_position + global_basis.z * 0.42

func add_part(parent:Node3D, mesh:Mesh, mat:Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	parts.append(mi)
	return mi

func set_flash(v:float):
	for p in parts: p.set_instance_shader_parameter("flash", v)

func set_tint(c:Color):
	for p in parts: p.set_instance_shader_parameter("itint", c)

func set_burn(v:float):
	for p in parts: p.set_instance_shader_parameter("burn", v)

func face(dir:Vector2, dt:float, rate:float = 14.0):
	if dir.length_squared() < 0.0001: return
	yaw = lerp_angle(yaw, atan2(dir.x, dir.y), 1.0 - exp(-rate * dt))
	rotation.y = yaw

## Hero / neighbour animation. vel: world ground velocity (m/s). state: 0 alive, 1 downed, 2 dead.
func animate_hero(dt:float, t:float, vel:Vector2, aiming:bool, firing:bool, state:int, rolling:bool, reloading:bool, using:bool):
	var speed := vel.length()
	move_amt = move_toward(move_amt, clampf(speed / 4.5, 0.0, 1.3), dt * 6.0)
	var moving := minf(move_amt, 1.0)
	# cadence follows real speed so feet don't skate; a little idle drift keeps it alive
	phase += dt * speed * 2.7
	blink -= dt
	var b := 1.0
	if blink < 0.12: b = 0.1
	if blink < 0: blink = randf_range(2.0, 5.0)
	if eyes: eyes.scale.y = b
	hit_flash = maxf(0.0, hit_flash - dt * 6.0)
	set_flash(hit_flash)
	recoil = move_toward(recoil, 0.0, dt * 7.0)
	swing = move_toward(swing, 0.0, dt * 3.5)
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, dt * (9.0 if aiming else 3.0))
	if state == 1 or state == 2:
		body.rotation = body.rotation.lerp(Vector3(-1.35, 0, 0.2 * sin(t * 2.0)), 1.0 - exp(-8 * dt))
		body.position = body.position.lerp(Vector3(0, 0.35, 0), 1.0 - exp(-8 * dt))
		arm_l.rotation = Vector3(-2.6 + sin(t * 3.0) * 0.4 * moving, 0, 0)
		arm_r.rotation = Vector3(-2.6 - sin(t * 3.0) * 0.4 * moving, 0, 0)
		leg_l.rotation = Vector3(0.2, 0, 0)
		leg_r.rotation = Vector3(-0.1, 0, 0)
		head.rotation.x = 0.9
		gun.visible = false
		if eyes: eyes.scale.y = 0.15
		return
	gun.visible = gun_kind >= 0 and not rolling
	head.rotation.x = 0.0
	if rolling:
		# one clean forward roll around the body's middle, tucked into a ball, with a little hop
		roll_t += dt
		var k := clampf(roll_t / ROLL_TIME, 0.0, 1.0)
		var turn := TAU * (k * k * (3.0 - 2.0 * k))
		var mid := 0.85
		var tuck := sin(PI * k)
		var spin := Basis(Vector3.RIGHT, turn).scaled(Vector3.ONE * (1.0 - 0.22 * tuck))
		body.transform = Transform3D(spin, Vector3(0, mid + 0.25 * tuck - 0.3 * tuck, 0) + spin * Vector3(0, -mid, 0))
		leg_l.rotation = Vector3(-1.4 * tuck, 0, 0)
		leg_r.rotation = Vector3(-1.4 * tuck, 0, 0)
		arm_l.rotation = Vector3(-2.2 * tuck, 0, 0.3)
		arm_r.rotation = Vector3(-2.2 * tuck, 0, -0.3)
		head.rotation.x = 0.5 * tuck
		return
	roll_t = 0.0
	body.scale = Vector3.ONE
	# movement in the character's own frame: forward/back and sideways
	var fwd_dir := Vector2(sin(yaw), cos(yaw))
	var right_dir := Vector2(cos(yaw), -sin(yaw))
	var dir := vel / maxf(speed, 0.001)
	var fwd := dir.dot(fwd_dir) * moving
	var side := dir.dot(right_dir) * moving
	var s := sin(phase)
	var c := cos(phase)
	var stride := 0.3 + 0.55 * moving
	# legs: swing along the walking direction, lift the leg that is stepping
	leg_l.rotation = Vector3(s * stride * fwd, 0, s * stride * side * 0.6)
	leg_r.rotation = Vector3(-s * stride * fwd, 0, -s * stride * side * 0.6)
	leg_l.position.y = hip_y + maxf(0.0, c) * 0.07 * moving
	leg_r.position.y = hip_y + maxf(0.0, -c) * 0.07 * moving
	# body: two bobs per cycle, lean into the motion, hips counter-twist
	var bob := absf(c) * 0.08 * moving * bob_scale
	var breathe := sin(t * 2.2) * 0.012 * (1.0 - moving)
	body.position = Vector3(0, bob + breathe - recoil * 0.03, -recoil * 0.07)
	body.rotation = Vector3(0.16 * fwd - recoil * 0.12, s * 0.12 * moving, -0.1 * side + sin(phase) * 0.02 * moving)
	head.rotation.y = -s * 0.1 * moving
	head.rotation.z = sin(t * 1.3) * 0.04 * (1.0 - moving)
	# arms: natural swing when relaxed, shouldered weapon when aiming
	var swing_l := -s * stride * 0.8 * maxf(absf(fwd), absf(side))
	var aim_x := -1.45 + recoil * 0.45
	var low_x := -0.55 + swing_l * 0.3
	arm_r.rotation = Vector3(lerpf(low_x, aim_x, aim_blend), 0, lerpf(-0.12, -0.05, aim_blend))
	arm_l.rotation = Vector3(lerpf(swing_l + breathe * 4.0, aim_x + 0.15, aim_blend * 0.9), 0, lerpf(0.1, 0.55, aim_blend))
	gun.position = gun_home + Vector3(0, lerpf(-0.16, 0.0, aim_blend), lerpf(-0.12, 0.0, aim_blend) - recoil * 0.12)
	if reloading:
		gun.rotation = Vector3(0.6 + sin(t * 12.0) * 0.2, 0, 0.3)
		arm_l.rotation.x = -0.9 + sin(t * 12.0) * 0.3
	else:
		gun.rotation = Vector3(lerpf(0.55, 0.0, aim_blend) - recoil * 0.5, lerpf(-0.35, 0.0, aim_blend), 0)
	if using and rummage:
		# lean into the boot and dig through it with both hands
		body.rotation.x = 0.55 + sin(t * 7.0) * 0.06
		body.position.y = -0.05 + absf(sin(t * 7.0)) * 0.03
		head.rotation.x = 0.35
		head.rotation.y = sin(t * 2.3) * 0.35
		arm_l.rotation = Vector3(-0.9 + sin(t * 16.0) * 0.55, 0, 0.25 + sin(t * 8.0) * 0.15)
		arm_r.rotation = Vector3(-0.9 - sin(t * 16.0) * 0.55, 0, -0.25 - cos(t * 8.0) * 0.15)
		gun.visible = false
	elif using:
		arm_l.rotation.x = -1.1 + sin(t * 14.0) * 0.35
		arm_r.rotation.x = -1.1 - sin(t * 14.0) * 0.35
	if swing > 0 and pan:
		pan.visible = true
		var k := 1.0 - swing
		arm_l.rotation = Vector3(-1.4, 0, lerpf(1.3, -0.9, k))
	elif pan:
		pan.visible = false

## Zombie animation. flags from the simulation snapshot.
func animate_zombie(dt:float, t:float, moving:float, flags:int):
	var attacking := flags & 1 != 0
	var climbing := flags & 2 != 0
	var dormant := flags & 4 != 0
	var stunned := flags & 16 != 0
	var fuse := flags & 32 != 0
	var windup := flags & 64 != 0
	var burning := flags & 128 != 0
	var rate := 6.0 if kind != 1 else 11.0
	if kind == 2 or kind == 7: rate = 4.0
	phase += dt * rate * maxf(moving, 0.15)
	hit_flash = maxf(0.0, hit_flash - dt * 7.0)
	set_flash(maxf(hit_flash, (0.6 + 0.4 * sin(t * 30.0)) * 0.5 if fuse else 0.0))
	set_burn(1.0 if burning else 0.0)
	var s := sin(phase)
	var sway := sin(phase * 0.5)
	if dormant:
		body.rotation = Vector3(0.35, 0, sin(t * 0.8 + position.x) * 0.15)
		body.position = Vector3(0, -0.05, 0)
		head.rotation = Vector3(0.6, 0, 0.3)
		arm_l.rotation.x = -0.2
		arm_r.rotation.x = -0.2
		return
	var lean_fwd := 0.18
	if kind == 1: lean_fwd = 0.85  # runners: crouched sprinters, readable even when still
	if kind == 4: lean_fwd = 0.6
	var shake_v := (sin(t * 60.0) * 0.06) if stunned else 0.0
	body.position = Vector3(shake_v, absf(s) * 0.07 * moving + (0.55 + 0.3 * absf(sin(t * 6.0)) if climbing else 0.0), 0)
	body.rotation = Vector3(lean_fwd * ((0.75 + moving * 0.25) if kind == 1 else (0.4 + moving * 0.6)), 0, sway * 0.12 + shake_v)
	head.rotation = Vector3(0.1 + sin(t * 1.7 + position.z) * 0.1, sin(t * 0.9 + position.x) * 0.2, sway * 0.18)
	leg_l.rotation.x = s * 0.6 * moving
	leg_r.rotation.x = -s * 0.6 * moving
	var reach := -1.35
	if kind == 3: reach = -1.0
	if kind == 7: reach = -0.45 - 0.15 * sin(t * 1.3)
	var arm_bob := sin(phase * 0.5 + 1.0) * 0.15
	if windup or attacking:
		var k := (sin(t * 12.0) * 0.5 + 0.5)
		arm_l.rotation.x = lerpf(-2.6, -0.8, k) if windup else -0.6
		arm_r.rotation.x = arm_l.rotation.x
		body.rotation.x = -0.15 if windup else 0.35
	elif kind == 1:
		# arms swept back, the opposite of the shambling reach of a common brotado
		arm_l.rotation.x = 1.0 + sin(phase) * 0.3
		arm_r.rotation.x = 1.0 - sin(phase) * 0.3
	else:
		arm_l.rotation.x = reach + arm_bob
		arm_r.rotation.x = reach - arm_bob
	if climbing:
		arm_l.rotation.x = -2.8 + s * 0.4
		arm_r.rotation.x = -2.8 - s * 0.4
	extra.rotation = Vector3(sin(t * 5.0 + position.x) * 0.25, 0, cos(t * 4.0) * 0.25)
