extends Node3D
## Procedurally animated character: chibi heroes, sprouted zombies and neighbours.
## Parts are separate MeshInstances parented to pivots so limbs can swing.
##
## The animation is layered: a gait cycle with real stance and swing phases (the
## planted foot moves back at ground speed, the free foot lifts and swings
## forward), then springs on top for weight and secondary motion: the body leans
## into acceleration, heads and floppy zombie arms lag behind, weapons kick and
## settle, and hits make the whole body flinch.

const RAGE_TINT := Color(1.25, 0.82, 0.9)      # enraged by the Plañidera: reddened
const RAGE_TINT_CB := Color(1.05, 0.95, 1.45)   # colour-blind mode: a bright violet glow instead
static var colorblind := false
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
var recoil := 0.0              # legacy trigger: setting it to 1.0 fires a medium kick
var swing := 0.0               # frying-pan swing, 1 → 0
var hit_flash := 0.0
var yaw := 0.0
var spawn_t := 0.0
var roll_t := 0.0
var gun_kind := -1
var aim_blend := 0.0
var bob_scale := 1.0
var ground_vel := Vector2.ZERO   # smoothed world velocity on the ground plane
var fire_t := 0.0                # keeps the weapon raised for a moment after shooting
var hip_y := 0.0
var shoulder_x := 0.36
var gun_home := Vector3.ZERO
var move_amt := 0.0
const ROLL_TIME := 0.34          # matches the dodge length in main.gd
var rummage := false             # searching a container or car: lean in and dig
var bar_t := 0.0                 # health bar shows for a moment after a hit
var sprinting := false
var vault := 0.0                 # 0..1 while hopping over a barricade
var vault_target := 0.0
var base_speed := 5.0           # normal walking speed of this character (m/s)
var limp := 0.0                  # 0..1: a dragging left leg (some common brotados)
var on_step:Callable             # (world position, strength) when a foot lands
var on_fx:Callable               # (name, world position) for rolls, landings, strikes

# --- springs (value, velocity)
var lean := Vector2.ZERO
var lean_v := Vector2.ZERO
var rec := 0.0
var rec_v := 0.0
var flinch := Vector2.ZERO
var flinch_v := Vector2.ZERO
var head_s := Vector2.ZERO
var head_v := Vector2.ZERO
var arms := Vector2.ZERO          # zombie arm angles (left, right) with lag
var arms_v := Vector2.ZERO
var prev_vel := Vector2.ZERO
var land_t := 0.0
var was_rolling := false
var prev_pl := 0.0
var prev_pr := 0.5
var twitch_t := 2.0
var last_flash := 0.0           # zombies: last hit flash; heroes: last damage timer
var wind_was := false
var strike_t := 9.0
var emerge := 1.0                 # 0 → 1 while a brotado claws out of the ground
var emerge_dur := 1.7
var dying := -1.0
var fall_dir := Vector2.ZERO
var tinted := false
var base_scale := Vector3.ONE

func setup_pivots(shoulder_y:float, shoulder_x_:float, hip_y_:float, hip_x:float, neck_y:float):
	add_child(body)
	body.add_child(head)
	head.position = Vector3(0, neck_y, 0)
	head.add_child(extra)
	shoulder_x = shoulder_x_
	for a in [[arm_l, -1], [arm_r, 1]]:
		body.add_child(a[0])
		a[0].position = Vector3(a[1] * shoulder_x_, shoulder_y, 0)
	for l in [[leg_l, -1], [leg_r, 1]]:
		body.add_child(l[0])
		l[0].position = Vector3(l[1] * hip_x, hip_y_, 0)
	body.add_child(gun)
	gun.position = Vector3(0.2, shoulder_y - 0.12, 0.38)
	gun_home = gun.position
	hip_y = hip_y_

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

func face_now(dir:Vector2):
	if dir.length_squared() < 0.0001: return
	yaw = atan2(dir.x, dir.y)
	rotation.y = yaw

# ------------------------------------------------------------------ impulses
func kick(power:float):
	## Weapon recoil: the body rocks back and the weapon settles with a little overshoot.
	rec_v += power * 10.0
	aim_blend = 1.0

func hurt(strength:float = 1.0):
	flinch_v += Vector2(-7.0 * strength, randf_range(-4.0, 4.0) * strength)
	hit_flash = maxf(hit_flash, 0.8)

func shove(local_dir:Vector2, strength:float):
	## Directional flinch in the rig's own frame (x: right, y: forward).
	flinch_v += Vector2(-local_dir.y * 8.0, local_dir.x * 6.0) * strength
	head_v += Vector2(-local_dir.y * 9.0, local_dir.x * 9.0) * strength

# ------------------------------------------------------------------ helpers
static func spr(x:float, v:float, target:float, k:float, d:float, dt:float) -> Vector2:
	v += (k * (target - x) - d * v) * dt
	x += v * dt
	return Vector2(x, v)

static func spr2(x:Vector2, v:Vector2, target:Vector2, k:float, d:float, dt:float) -> Array:
	v += (k * (target - x) - d * v) * dt
	x += v * dt
	return [x, v]

static func leg_cycle(p:float, duty:float) -> Vector2:
	## x: -1 (foot behind) .. 1 (foot ahead); y: lift. The stance phase moves the
	## planted foot back linearly (no skating); the swing eases it forward and up.
	p = fposmod(p, 1.0)
	if p < duty: return Vector2(lerpf(1.0, -1.0, p / duty), 0.0)
	var u := (p - duty) / (1.0 - duty)
	return Vector2(lerpf(-1.0, 1.0, u * u * (3.0 - 2.0 * u)), sin(PI * u))

static func ease_out_back(x:float) -> float:
	var c := 1.7
	x -= 1.0
	return 1.0 + (c + 1.0) * x * x * x + c * x * x

func foot_world(side:float) -> Vector3:
	return global_position + global_basis.x * side * 0.16 + Vector3(0, 0.05, 0)

func check_steps(pl:float, pr:float, strength:float):
	## A foot lands when its cycle wraps from swing back into stance.
	if fposmod(pl, 1.0) < fposmod(prev_pl, 1.0) and on_step.is_valid(): on_step.call(foot_world(-1.0), strength)
	if fposmod(pr, 1.0) < fposmod(prev_pr, 1.0) and on_step.is_valid(): on_step.call(foot_world(1.0), strength)
	prev_pl = pl
	prev_pr = pr

func emit_fx(name:String):
	if on_fx.is_valid(): on_fx.call(name, global_position)

# ================================================================== heroes and neighbours
## vel: world ground velocity (m/s). state: 0 alive, 1 downed, 2 dead.
func animate_hero(dt:float, t:float, vel:Vector2, aiming:bool, firing:bool, state:int, rolling:bool, reloading:bool, using:bool, reload_frac:float = 0.0):
	dt = clampf(dt, 0.0, 0.05)
	if dt <= 0.0: return
	if recoil > 0.0:
		kick(recoil)
		recoil = 0.0
	var speed := vel.length()
	move_amt = move_toward(move_amt, clampf(speed / (base_speed * 0.85), 0.0, 1.4), dt * 5.0)
	var moving := minf(move_amt, 1.0)
	var run := clampf((speed - base_speed * 1.1) / (base_speed * 0.2), 0.0, 1.0)
	sprinting = run > 0.4
	# local frame: forward along the facing, right to its side
	var fwd_dir := Vector2(sin(yaw), cos(yaw))
	var right_dir := Vector2(cos(yaw), -sin(yaw))
	var accel := (vel - prev_vel) / dt
	prev_vel = vel
	var lf := vel.dot(fwd_dir)
	var ls := vel.dot(right_dir)
	var af := clampf(accel.dot(fwd_dir), -30.0, 30.0)
	var as_ := clampf(accel.dot(right_dir), -30.0, 30.0)
	# blinking, hit flash
	blink -= dt
	if eyes: eyes.scale.y = 0.1 if blink < 0.12 else 1.0
	if blink < 0: blink = randf_range(2.0, 5.0)
	hit_flash = maxf(0.0, hit_flash - dt * 6.0)
	set_flash(hit_flash)
	# springs: recoil, flinch, lean into acceleration
	var r2 := spr(rec, rec_v, 0.0, 190.0, 15.0, dt)
	rec = r2.x
	rec_v = r2.y
	var f2 := spr2(flinch, flinch_v, Vector2.ZERO, 140.0, 11.0, dt)
	flinch = f2[0]
	flinch_v = f2[1]
	var lean_target := Vector2(clampf(lf * 0.03 + run * 0.24 + af * 0.012, -0.3, 0.55), clampf(-ls * 0.035 - as_ * 0.01, -0.3, 0.3))
	var l2 := spr2(lean, lean_v, lean_target, 70.0, 12.0, dt)
	lean = l2[0]
	lean_v = l2[1]
	swing = move_toward(swing, 0.0, dt * 3.5)
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, dt * (12.0 if aiming else 3.0))
	body.scale = Vector3.ONE
	# ---- downed
	if state == 1 or state == 2:
		body.rotation = body.rotation.lerp(Vector3(-1.35, 0, 0.2 * sin(t * 2.0)), 1.0 - exp(-8 * dt))
		body.position = body.position.lerp(Vector3(0, 0.35, 0), 1.0 - exp(-8 * dt))
		arm_l.rotation = Vector3(-2.6 + sin(t * 3.0) * 0.4 * moving, 0, 0)
		arm_r.rotation = Vector3(-2.6 - sin(t * 3.0) * 0.4 * moving, 0, 0)
		leg_l.rotation = Vector3(0.2 + sin(t * 3.0) * 0.2 * moving, 0, 0)
		leg_r.rotation = Vector3(-0.1 - sin(t * 3.0) * 0.2 * moving, 0, 0)
		head.rotation = Vector3(0.9, 0, 0)
		gun.visible = false
		if eyes: eyes.scale.y = 0.15
		was_rolling = false
		return
	gun.visible = gun_kind >= 0 and not rolling
	# ---- dodge roll: stretch, tuck into a ball and roll over the shoulder, then land
	if rolling:
		if not was_rolling:
			roll_t = 0.0
			emit_fx("roll")
		was_rolling = true
		roll_t += dt
		var k := clampf(roll_t / ROLL_TIME, 0.0, 1.0)
		var turn := TAU * (k * k * (3.0 - 2.0 * k))
		var mid := 0.8
		var tuck := sin(PI * k)
		var stretch := 1.0 + 0.15 * maxf(0.0, 1.0 - k * 6.0)
		var spin := Basis(Vector3.RIGHT, turn).scaled(Vector3(1.0 - 0.2 * tuck, (1.0 - 0.25 * tuck) * stretch, 1.0 - 0.2 * tuck))
		body.transform = Transform3D(spin, Vector3(0, mid + 0.12 * tuck, 0.1 * tuck) + spin * Vector3(0, -mid, 0))
		leg_l.rotation = Vector3(-1.6 * tuck, 0, 0.1)
		leg_r.rotation = Vector3(-1.5 * tuck, 0, -0.1)
		leg_l.scale = Vector3.ONE
		leg_r.scale = Vector3.ONE
		arm_l.rotation = Vector3(-2.3 * tuck, 0, 0.35)
		arm_r.rotation = Vector3(-2.3 * tuck, 0, -0.35)
		head.rotation = Vector3(0.6 * tuck, 0, 0)
		return
	if was_rolling:
		was_rolling = false
		land_t = 0.26
		emit_fx("land")
	roll_t = 0.0
	# ---- gait
	# stride and swing sized so the planted foot keeps pace with the ground
	var stride_len := lerpf(1.45, 2.1, run) * (0.75 + 0.25 * moving)
	phase += speed / stride_len * TAU * dt
	var duty := lerpf(0.6, 0.36, run)
	var pl := phase / TAU
	var pr := pl + 0.5
	var cl := leg_cycle(pl, duty)
	var cr := leg_cycle(pr, duty)
	var dir := Vector2(ls, lf) / maxf(speed, 0.001) if speed > 0.15 else Vector2(0, 1)
	var amp := lerpf(0.68, 0.95, run) * moving
	var lift_h := lerpf(0.08, 0.16, run) * moving
	leg_l.rotation = Vector3(-cl.x * amp * dir.y, 0, cl.x * amp * dir.x * 0.7 + 0.04 * (1.0 - moving))
	leg_r.rotation = Vector3(-cr.x * amp * dir.y, 0, cr.x * amp * dir.x * 0.7 - 0.04 * (1.0 - moving))
	leg_l.position.y = hip_y + cl.y * lift_h
	leg_r.position.y = hip_y + cr.y * lift_h
	leg_l.scale = Vector3(1, 1.0 - cl.y * 0.16 * moving, 1)
	leg_r.scale = Vector3(1, 1.0 - cr.y * 0.16 * moving, 1)
	if moving > 0.3: check_steps(pl, pr, speed)
	else:
		prev_pl = pl
		prev_pr = pr
	# body: highest over the planted foot, lowest as the other one lands; hips sway
	var mid_stance := 0.5 + 0.5 * cos(TAU * 2.0 * (pl - duty * 0.5))
	var bob_amp := lerpf(0.045, 0.1, run) * moving * bob_scale
	var bob := (mid_stance - 0.5) * bob_amp
	var idle := 1.0 - moving
	var breathe := sin(t * 2.3) * idle
	var hip_roll := sin(phase) * 0.05 * moving * (1.0 - 0.6 * run)
	var twist := cl.x * 0.13 * moving * dir.y
	# landing squash after a roll
	var squash := 0.0
	if land_t > 0:
		land_t -= dt
		squash = sin(PI * clampf(1.0 - land_t / 0.26, 0.0, 1.0))
	body.scale = Vector3(1.0 + 0.1 * squash, 1.0 - 0.16 * squash + 0.012 * breathe, 1.0 + 0.1 * squash)
	body.position = Vector3(0, bob - 0.07 * squash - rec * 0.03, -rec * 0.08)
	body.rotation = Vector3(lean.x - rec * 0.16 + flinch.x * 0.12, twist, lean.y + hip_roll + flinch.y * 0.08 + sin(t * 0.55) * 0.02 * idle)
	if squash > 0:
		leg_l.rotation.x += -0.35 * squash
		leg_r.rotation.x += -0.35 * squash
	# head steadies against the body and glances around when idle
	var look := (sin(t * 0.31) * 0.6 + sin(t * 0.83 + 1.3) * 0.4) * 0.3 * idle * (1.0 - aim_blend)
	head.rotation = Vector3(-lean.x * 0.55 - run * 0.08 - flinch.x * 0.05 + rec * 0.08, -twist * 0.9 + look, -hip_roll * 0.6)
	# ---- vaulting a barricade: spring up, tuck the legs, reach over, drop and land
	var was_up := vault > 0.45
	vault = move_toward(vault, vault_target, dt * (7.0 if vault_target > vault else 5.0))
	if vault > 0.001:
		var arc := sin(PI * 0.5 * vault)
		body.position.y += arc * 1.15 * vault_target + arc * 0.5 * (1.0 - vault_target)
		body.rotation.x += 0.35 * arc
		leg_l.rotation.x = lerpf(leg_l.rotation.x, -1.3, arc)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, -1.0, arc)
	if was_up and vault_target == 0.0 and vault < 0.45:
		land_t = 0.22
		emit_fx("land")
	# ---- arms: natural counter-swing, pumping when sprinting, shouldered weapon when aiming
	var arm_amp := lerpf(0.35, 1.15, run) * moving * (1.0 if dir.y >= -0.2 else -1.0)
	var relax_l := cr.x * arm_amp + sin(t * 2.3) * 0.03 * idle
	var relax_r := cl.x * arm_amp - sin(t * 2.3) * 0.03 * idle
	var aim_x := -1.45 + rec * 0.75 + bob * 0.6
	var low_x := -0.5 + relax_r * 0.35
	arm_r.rotation = Vector3(lerpf(low_x if gun_kind >= 0 else -relax_r, aim_x, aim_blend), 0, lerpf(-0.12 - 0.12 * run, -0.05, aim_blend))
	arm_l.rotation = Vector3(lerpf(-relax_l, aim_x + 0.15, aim_blend * 0.9), 0, lerpf(0.1 + 0.12 * run, 0.55, aim_blend))
	gun.position = gun_home + Vector3(0, lerpf(-0.16, 0.0, aim_blend) + bob * 0.3, lerpf(-0.12, 0.0, aim_blend) - rec * 0.14)
	gun.rotation = Vector3(lerpf(0.55, 0.0, aim_blend) - rec * 0.55, lerpf(-0.35, 0.0, aim_blend), 0)
	# ---- reload: tilt the weapon out, fetch a clip from the belt, slap it in, rack it
	if reloading:
		var k := clampf(reload_frac, 0.0, 1.0)
		var tilt := smoothstep(0.0, 0.15, k) - smoothstep(0.78, 0.95, k)
		var to_belt := smoothstep(0.18, 0.32, k) - smoothstep(0.42, 0.58, k)
		var slap := smoothstep(0.58, 0.64, k) - smoothstep(0.64, 0.74, k)
		var rack := smoothstep(0.74, 0.8, k) - smoothstep(0.8, 0.9, k)
		arm_r.rotation = Vector3(lerpf(-0.9, -1.1, tilt), 0, -0.08)
		gun.position = gun_home + Vector3(-0.02 * tilt, -0.1 * tilt + 0.04 * slap, -0.08 * tilt - 0.05 * rack)
		gun.rotation = Vector3(0.75 * tilt - 0.3 * rack, 0.2 * tilt, 0.55 * tilt)
		arm_l.rotation = Vector3(lerpf(-1.05, -0.15, to_belt) - 0.25 * slap, 0, lerpf(0.45, 0.05, to_belt))
		head.rotation.x += 0.3 * tilt
	# ---- interacting
	if using and rummage:
		body.rotation.x = 0.55 + sin(t * 7.0) * 0.06
		body.position.y = -0.05 + absf(sin(t * 7.0)) * 0.03
		head.rotation = Vector3(0.35, sin(t * 2.3) * 0.35, 0)
		arm_l.rotation = Vector3(-0.9 + sin(t * 16.0) * 0.55, 0, 0.25 + sin(t * 8.0) * 0.15)
		arm_r.rotation = Vector3(-0.9 - sin(t * 16.0) * 0.55, 0, -0.25 - cos(t * 8.0) * 0.15)
		gun.visible = false
	elif using:
		arm_l.rotation.x = -1.1 + sin(t * 14.0) * 0.35
		arm_r.rotation.x = -1.1 - sin(t * 14.0) * 0.35
		body.rotation.x += 0.15
	# ---- frying pan: wind up, whip across with the hips, follow through
	if swing > 0 and pan:
		pan.visible = true
		var k := 1.0 - swing
		var wind := smoothstep(0.0, 0.22, k)
		var strike := smoothstep(0.22, 0.5, k)
		var settle := smoothstep(0.6, 1.0, k)
		var across := lerpf(lerpf(0.2, 1.6, wind), -1.2, strike * strike)
		arm_l.rotation = Vector3(lerpf(-1.2, -1.55, wind), 0, lerpf(across, 0.1, settle))
		body.rotation.y += lerpf(lerpf(0.0, 0.5, wind), -0.55, strike) * (1.0 - settle)
		body.rotation.x += 0.22 * strike * (1.0 - settle)
		body.position.z += 0.14 * strike * (1.0 - settle)
		head.rotation.y -= body.rotation.y * 0.5
	elif pan:
		pan.visible = false

# ================================================================== zombies
# Per-kind gait: stride (m per cycle), leg swing, forward lean, side sway, arm style.
const GAITS = {
	0: {"stride":0.75, "leg":0.45, "lean":0.25, "sway":0.15, "arm":"reach", "duty":0.64},
	1: {"stride":1.7, "leg":0.95, "lean":0.8, "sway":0.05, "arm":"back", "duty":0.38},
	2: {"stride":1.15, "leg":0.42, "lean":0.12, "sway":0.12, "arm":"heavy", "duty":0.6},
	3: {"stride":1.05, "leg":0.55, "lean":0.5, "sway":0.07, "arm":"charge", "duty":0.55},
	4: {"stride":0.9, "leg":0.75, "lean":0.7, "sway":0.05, "arm":"drag", "duty":0.5},
	5: {"stride":0.65, "leg":0.35, "lean":0.08, "sway":0.22, "arm":"waddle", "duty":0.62},
	6: {"stride":0.95, "leg":0.6, "lean":0.35, "sway":0.1, "arm":"hold", "duty":0.45},
	7: {"stride":2.6, "leg":0.38, "lean":0.25, "sway":0.08, "arm":"giant", "duty":0.62},
	8: {"stride":1.0, "leg":0.0, "lean":0.1, "sway":0.0, "arm":"wail", "duty":0.5},
}

## Zombie animation. vel: smoothed world velocity; flags from the snapshot; flash: hit flash.
func animate_zombie(dt:float, t:float, vel:Vector2, flags:int, flash:float = 0.0):
	dt = clampf(dt, 0.0, 0.05)
	if dt <= 0.0: return
	var attacking := flags & 1 != 0
	var climbing := flags & 2 != 0
	var dormant := flags & 4 != 0
	var stunned := flags & 16 != 0
	var fuse := flags & 32 != 0
	var windup := flags & 64 != 0
	var burning := flags & 128 != 0
	var raging := flags & 256 != 0
	var wailing := flags & 512 != 0
	var g:Dictionary = GAITS.get(kind, GAITS[0])
	var speed := vel.length()
	var top:float = 3.4 if kind == 1 else (1.2 if kind in [2, 7] else 1.8)
	move_amt = move_toward(move_amt, clampf(speed / top, 0.0, 1.2), dt * 4.0)
	var moving := minf(move_amt, 1.0)
	# hits: flinch on every new hit
	if flash > last_flash + 0.02: hurt(0.8 if kind != 7 else 0.3)
	last_flash = flash
	hit_flash = maxf(0.0, hit_flash - dt * 7.0)
	set_flash(maxf(hit_flash, (0.6 + 0.4 * sin(t * 30.0)) * 0.5 if fuse else 0.0))
	set_burn(1.0 if burning else 0.0)
	if raging != tinted:
		tinted = raging
		set_tint((RAGE_TINT_CB if colorblind else RAGE_TINT) if raging else Color.WHITE)
	var f2 := spr2(flinch, flinch_v, Vector2.ZERO, 110.0, 9.0, dt)
	flinch = f2[0]
	flinch_v = f2[1]
	# twitches: the head jerks, an arm spasms
	twitch_t -= dt
	if twitch_t <= 0:
		twitch_t = randf_range(1.2, 3.8)
		head_v += Vector2(randf_range(-6, 6), randf_range(-9, 9))
		arms_v += Vector2(randf_range(-8, 8), randf_range(-8, 8))
	if kind == 8:
		animate_wailer(dt, t, vel, moving, wailing, stunned)
		return
	if dormant:
		body.rotation = Vector3(0.35 + sin(t * 0.7 + position.x) * 0.04, 0, sin(t * 0.8 + position.x) * 0.15)
		body.position = Vector3(0, -0.05 + sin(t * 1.4 + position.z) * 0.01, 0)
		head.rotation = Vector3(0.6, sin(t * 0.3) * 0.2, 0.3)
		arm_l.rotation = Vector3(-0.2, 0, 0.1)
		arm_r.rotation = Vector3(-0.15, 0, -0.1)
		leg_l.rotation = Vector3.ZERO
		leg_r.rotation = Vector3.ZERO
		return
	# ---- gait
	var rate_mult := 1.3 if raging else 1.0
	phase += (speed / float(g.stride)) * TAU * dt * rate_mult + dt * 0.6 * (1.0 - moving)
	var duty:float = g.duty
	var pl := phase / TAU
	var pr := pl + 0.5
	var cl := leg_cycle(pl, duty)
	var cr := leg_cycle(pr, duty)
	var amp:float = float(g.leg) * moving
	# a dragged left leg: shorter step, the foot scrapes instead of lifting
	var weak := 1.0 - 0.55 * limp
	leg_l.rotation = Vector3(-cl.x * amp * weak, 0, 0.06 * limp)
	leg_r.rotation = Vector3(-cr.x * amp, 0, -0.04 * limp)
	leg_l.position.y = hip_y + cl.y * 0.09 * moving * (1.0 - 0.85 * limp)
	leg_r.position.y = hip_y + cr.y * 0.09 * moving
	if moving > 0.25: check_steps(pl, pr, speed * (3.0 if kind in [2, 7] else 1.0))
	# ---- body
	var mid_stance := 0.5 + 0.5 * cos(TAU * 2.0 * (pl - duty * 0.5))
	var heavy := 1.0 if kind in [2, 7] else 0.0
	var bob := (mid_stance - 0.5) * (0.07 + 0.06 * heavy) * moving
	var on_weak := clampf(1.0 - absf(fposmod(pl, 1.0) - duty * 0.5) / (duty * 0.5), 0.0, 1.0)
	bob -= limp * 0.07 * on_weak * moving
	var sway := sin(phase) * float(g.sway) * (0.4 + 0.6 * moving)
	var lean_fwd:float = float(g.lean) * (0.55 + 0.45 * moving) + (0.15 if raging else 0.0)
	var hop := absf(sin(phase)) * 0.12 * moving if kind == 6 else 0.0
	var shake_v := (sin(t * 60.0) * 0.06) if stunned or fuse else 0.0
	var climb_y := (0.55 + 0.3 * absf(sin(t * 6.0))) if climbing else 0.0
	# ---- attack: rear back on the wind-up, then lunge and slam
	if windup:
		wind_was = true
	elif wind_was:
		wind_was = false
		strike_t = 0.0
		if kind in [2, 7]: emit_fx("slam")
	strike_t += dt
	var strike := 0.0
	if strike_t < 0.35:
		var u := strike_t / 0.35
		strike = sin(PI * minf(1.0, u * 1.6)) * (1.0 - u * 0.3)
	var rear := 1.0 if windup else 0.0
	var spd_scale := 1.0 + heavy * 0.4
	body.position = Vector3(shake_v, bob + hop + climb_y - 0.06 * rear + 0.02 * strike, 0.28 * strike * spd_scale - 0.06 * rear)
	body.rotation = Vector3(lean_fwd - 0.32 * rear + 0.55 * strike + flinch.x * 0.13, sin(phase * 0.5) * 0.08 * moving, sway + limp * 0.08 + shake_v + flinch.y * 0.09)
	# ---- head: floppy, lags behind the body
	var head_target := Vector2(0.12 + sin(t * 1.7 + position.z) * 0.08 - lean_fwd * 0.35 + 0.2 * strike, -sway * 1.6 + sin(t * 0.9 + position.x) * 0.12)
	if kind == 1: head_target.x = -0.25 - lean_fwd * 0.3
	var h2 := spr2(head_s, head_v, head_target, 32.0, 4.5, dt)
	head_s = h2[0]
	head_v = h2[1]
	head.rotation = Vector3(head_s.x - flinch.x * 0.06, sin(t * 0.7 + position.x) * 0.18, head_s.y)
	# ---- arms
	var arm_target := Vector2.ZERO
	var arm_z := Vector2(0.0, 0.0)
	var ph := sin(phase)
	match String(g.arm):
		"reach":
			arm_target = Vector2(-1.35 + sin(t * 1.3 + 1.0) * 0.12, -1.3 + sin(t * 1.1) * 0.12) + Vector2(-ph, ph) * 0.12 * moving
			arm_z = Vector2(0.12, -0.12)
		"back":
			arm_target = Vector2(1.0 + ph * 0.55, 1.0 - ph * 0.55)
			arm_z = Vector2(0.25, -0.25)
		"heavy":
			arm_target = Vector2(-0.25 - ph * 0.45 * moving, -0.25 + ph * 0.45 * moving)
			arm_z = Vector2(0.18, -0.18)
		"charge":
			arm_target = Vector2(-0.85 + ph * 0.15, -0.85 - ph * 0.15)
			arm_z = Vector2(-0.25, 0.25)
		"drag":
			arm_target = Vector2(-0.35 + ph * 0.55, -0.35 - ph * 0.55)
			arm_z = Vector2(0.1, -0.1)
		"waddle":
			arm_target = Vector2(-0.3 + ph * 0.1, -0.3 - ph * 0.1)
			arm_z = Vector2(0.65 + ph * 0.1, -0.65 + ph * 0.1)
		"hold":
			arm_target = Vector2(-1.9 + ph * 0.1, -1.9 - ph * 0.1)
			arm_z = Vector2(-0.55, 0.55)
		"giant":
			arm_target = Vector2(-0.45 - 0.15 * sin(t * 1.3) - ph * 0.35 * moving, -0.45 - 0.15 * sin(t * 1.3) + ph * 0.35 * moving)
			arm_z = Vector2(0.12, -0.12)
	if windup:
		arm_target = Vector2(-2.7, -2.6)
		arm_z = Vector2(0.3, -0.3)
	if strike > 0.05:
		arm_target = arm_target.lerp(Vector2(0.15, 0.2), strike)
	if raging and not windup: arm_target += Vector2(-0.3, -0.3) + Vector2(sin(t * 25.0), cos(t * 23.0)) * 0.08
	if climbing:
		arm_target = Vector2(-2.8 + sin(phase) * 0.4, -2.8 - sin(phase) * 0.4)
	var stiff := 90.0 if (windup or strike > 0.05) else (28.0 if kind != 1 else 55.0)
	var a2 := spr2(arms, arms_v, arm_target, stiff, 5.0 if stiff < 50 else 9.0, dt)
	arms = a2[0]
	arms_v = a2[1]
	arm_l.rotation = Vector3(arms.x, 0, arm_z.x)
	arm_r.rotation = Vector3(arms.y, 0, arm_z.y)
	extra.rotation = Vector3(sin(t * 5.0 + position.x) * 0.25 + head_v.x * 0.02, 0, cos(t * 4.0) * 0.25 + head_v.y * 0.02)
	# swelling before the firecracker one blows
	if fuse:
		var sw := 1.0 + 0.08 * absf(sin(t * 18.0))
		body.scale = Vector3(sw, 1.0 + 0.04 * absf(sin(t * 18.0)), sw)
	elif kind == 5:
		body.scale = Vector3(1.0 + 0.03 * sin(phase * 2.0), 1.0 - 0.02 * sin(phase * 2.0), 1.0 + 0.03 * sin(phase * 2.0))
	else:
		body.scale = Vector3.ONE
	if emerge < 1.0: emerge_pose(t)
	elif tinted == false and dirt > 0.0:
		dirt = 0.0
		set_tint(Color.WHITE)
		arm_l.scale = Vector3.ONE
		arm_r.scale = Vector3.ONE

# ================================================================== rising from the earth
var dirt := 0.0

func rise_scale() -> float:
	return 2.3 if kind == 7 else (1.25 if kind == 2 else 1.0)

func emerge_height() -> float:
	## How deep the body still is. Hidden at first, then the hands break through,
	## head and shoulders push up, and finally it hauls itself out with a little hop.
	var e := emerge
	var k := rise_scale()
	var y := 0.0
	if e < 0.14: y = -2.7
	elif e < 0.36: y = lerpf(-2.2, -1.85, smoothstep(0.14, 0.32, e))
	elif e < 0.7: y = lerpf(-1.85, -0.5, smoothstep(0.36, 0.7, e)) + sin(e * 60.0) * 0.025
	elif e < 0.93:
		var u := (e - 0.7) / 0.23
		y = lerpf(-0.5, 0.0, u * u * (3.0 - 2.0 * u)) + sin(PI * u) * 0.18
	return y * k

func emerge_pose(t:float):
	var e := emerge
	# caked in earth, brushed clean in the last moment
	var d := 1.0 - smoothstep(0.86, 1.0, e)
	if absf(d - dirt) > 0.02 and not tinted:
		dirt = d
		set_tint(Color.WHITE.lerp(Color(0.74, 0.6, 0.47), d))
	# arms reach far up through the earth so the hands break the surface first
	var reach_s := lerpf(2.5, 1.0, smoothstep(0.36, 0.62, e))
	arm_l.scale = Vector3(1, reach_s, 1)
	arm_r.scale = Vector3(1, reach_s, 1)
	if e < 0.36:
		# the hands burst through first and claw at the air
		var c := smoothstep(0.14, 0.24, e)
		arm_l.rotation = Vector3(-3.05 + sin(t * 17.0) * 0.28 * c, 0, 0.18 + sin(t * 9.0) * 0.1)
		arm_r.rotation = Vector3(-3.05 + sin(t * 17.0 + 1.7) * 0.28 * c, 0, -0.18 - sin(t * 8.0) * 0.1)
		body.rotation = Vector3(-0.15, 0, sin(t * 6.0) * 0.08)
		head.rotation = Vector3(-0.45, 0, 0)
	elif e < 0.7:
		# head and shoulders out: grab the ground and drag, one hand after the other
		var u := smoothstep(0.36, 0.5, e)
		var pull_l := sin(t * 7.5)
		var pull_r := sin(t * 7.5 + PI)
		arm_l.rotation = Vector3(lerpf(-3.0, -1.35 + pull_l * 0.55, u), 0, 0.35)
		arm_r.rotation = Vector3(lerpf(-3.0, -1.35 + pull_r * 0.55, u), 0, -0.35)
		body.rotation = Vector3(lerpf(-0.1, 0.55, u), sin(t * 4.0) * 0.15, sin(t * 7.5) * 0.18)
		head.rotation = Vector3(lerpf(-0.4, 0.1, u) + sin(t * 11.0) * 0.06, sin(t * 3.0) * 0.4, sin(t * 5.0) * 0.15)
	elif e < 0.93:
		# palms pressed down, one knee up and over the rim
		var u := smoothstep(0.7, 0.93, e)
		arm_l.rotation = Vector3(lerpf(-1.1, 0.25, u), 0, 0.45)
		arm_r.rotation = Vector3(lerpf(-1.1, 0.2, u), 0, -0.45)
		leg_l.rotation = Vector3(-1.4 * sin(PI * u), 0, 0.1)
		leg_r.rotation = Vector3(-0.3 * sin(PI * u), 0, -0.05)
		body.rotation = Vector3(lerpf(0.6, 0.2, u), 0, sin(t * 6.0) * 0.08)
		head.rotation = Vector3(0.2, 0, 0)
	else:
		# shake the earth off like a wet dog
		var u := smoothstep(0.93, 1.0, e)
		var sh := (1.0 - u)
		body.rotation = Vector3(0.15, sin(t * 28.0) * 0.25 * sh, sin(t * 31.0) * 0.12 * sh)
		head.rotation = Vector3(0.1, sin(t * 34.0) * 0.5 * sh, sin(t * 29.0) * 0.2 * sh)
		arm_l.rotation = Vector3(-0.4, 0, 0.35 + sin(t * 30.0) * 0.3 * sh)
		arm_r.rotation = Vector3(-0.4, 0, -0.35 - sin(t * 27.0) * 0.3 * sh)
	arms = Vector2(arm_l.rotation.x, arm_r.rotation.x)
	arms_v = Vector2.ZERO

func animate_wailer(dt:float, t:float, vel:Vector2, moving:float, wailing:bool, stunned:bool):
	## The Plañidera glides: no steps, the dress sways, the veil trails behind.
	var w := 1.0 if wailing else 0.0
	var hover := 0.22 + sin(t * 1.6) * 0.07 + 0.3 * w
	var shake_v := (sin(t * 50.0) * 0.05) if stunned else 0.0
	var fwd_dir := Vector2(sin(yaw), cos(yaw))
	var lf := vel.dot(fwd_dir)
	body.position = Vector3(shake_v, hover, 0)
	body.rotation = Vector3(clampf(lf * 0.08, -0.2, 0.25) - 0.25 * w + flinch.x * 0.1, sin(t * 0.7) * 0.1, sin(t * 1.3) * 0.07 + flinch.y * 0.08)
	var h2 := spr2(head_s, head_v, Vector2(0.35 - 0.95 * w, sin(t * 0.6) * 0.2), 24.0, 4.0, dt)
	head_s = h2[0]
	head_v = h2[1]
	head.rotation = Vector3(head_s.x, sin(t * 0.4) * 0.3 * (1.0 - w), head_s.y)
	var target := Vector2(-0.7 + sin(t * 1.4) * 0.2, -0.6 + sin(t * 1.2 + 1.0) * 0.2)
	if wailing: target = Vector2(-2.9 + sin(t * 9.0) * 0.15, -2.9 - sin(t * 9.0) * 0.15)
	var a2 := spr2(arms, arms_v, target, 26.0, 4.0, dt)
	arms = a2[0]
	arms_v = a2[1]
	arm_l.rotation = Vector3(arms.x, 0, 0.25 + 0.55 * w)
	arm_r.rotation = Vector3(arms.y, 0, -0.25 - 0.55 * w)
	extra.rotation = Vector3(-0.3 - lf * 0.1 + sin(t * 3.0) * 0.1, 0, sin(t * 2.2) * 0.15)
	var pulse := 1.0 + 0.06 * w * sin(t * 30.0)
	body.scale = Vector3(pulse, 1.0 + 0.05 * w, pulse)

# ================================================================== death
func start_death(away:Vector2):
	## Fall over away from whoever finished it off.
	dying = 0.0
	base_scale = scale
	fall_dir = away.normalized() if away.length_squared() > 0.001 else Vector2(sin(yaw), cos(yaw)) * -1.0
	if bar: bar.visible = false
	if eyes: eyes.scale.y = 0.15

func animate_death(dt:float) -> bool:
	## Returns true when the body has sunk away and the node can be freed.
	dying += dt
	var big := kind == 7
	var span := 0.75 if big else 0.5
	if kind == 8:
		# the Plañidera rises, spins and fades away
		var k := clampf(dying / 0.9, 0.0, 1.0)
		position.y += dt * 2.2
		rotation.y += dt * 9.0 * k
		scale = base_scale * maxf(0.01, 1.0 - k)
		return dying > 0.9
	var a := clampf(dying / span, 0.0, 1.0)
	var ang := 1.45 * a * a
	if dying > span and dying < span + 0.25:
		ang -= 0.14 * sin((dying - span) / 0.25 * PI)
	var f3 := Vector3(fall_dir.x, 0, fall_dir.y)
	var axis := Vector3.UP.cross(f3).normalized()
	if axis.length_squared() < 0.5: axis = Vector3.RIGHT
	basis = (Basis(axis, ang) * Basis(Vector3.UP, yaw)).scaled(base_scale)
	arm_l.rotation = Vector3(lerpf(-2.4, -0.3, a), 0, 0.5 * (1.0 - a) + 0.4)
	arm_r.rotation = Vector3(lerpf(-2.2, -0.2, a), 0, -0.5 * (1.0 - a) - 0.4)
	leg_l.rotation = Vector3(-0.4 * a, 0, 0.15)
	leg_r.rotation = Vector3(0.2 * a, 0, -0.15)
	head.rotation = Vector3(-0.5 * a, 0.3, 0.2)
	set_flash(maxf(0.0, 0.8 - dying * 3.0))
	var sink_at := span + 0.55
	if dying > sink_at:
		var s := (dying - sink_at) / 0.6
		position.y = -1.2 * s * s * (2.5 if big else 1.0)
		if blob: blob.visible = false
	return dying > sink_at + 0.6
