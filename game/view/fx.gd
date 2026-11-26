extends Node3D
## Pooled combat and feedback effects driven by simulation events.

const Kit = preload("res://game/view/kit.gd")
const Data = preload("res://game/data.gd")

var fx_shader:Shader = load("res://game/shaders/fx.gdshader")
var soft_shader:Shader = load("res://game/shaders/soft.gdshader")
var tracers := []
var slugs := []      # projectile cores
var trails := []     # tapered glow behind each projectile
var flashes := []
var lights := []
var light_i := 0
var numbers := []
var number_i := 0
var rings := []
var ring_i := 0
var bolts := []
var pools := {}
var pool_i := {}
var trauma := 0.0
var show_numbers := true
var bright := true     # accessibility: when false, lights and blasts are toned down
var live := []   # [node, age, life, kind, data]

func _ready():
	var unit := BoxMesh.new()
	unit.size = Vector3(1, 1, 1)
	for i in 96:
		var mi := MeshInstance3D.new()
		mi.mesh = unit
		mi.material_override = mat_fx(Color("ffe08a"), 3.0)
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		tracers.append(mi)
	var core := SphereMesh.new()
	core.radius = 0.5
	core.height = 1.0
	core.radial_segments = 10
	core.rings = 6
	var cone_kit := Kit.new()
	cone_kit.cylinder(Kit.rot(0, 0, 0.5, 0.0, PI * 0.5), 0.5, 0.0, 1.0, Color.WHITE, 10, false)
	var cone := cone_kit.commit()
	for i in 72:
		for pair in [[slugs, core, 4.0], [trails, cone, 1.6]]:
			var mi := MeshInstance3D.new()
			mi.mesh = pair[1]
			mi.material_override = mat_fx(Color("ffe08a"), pair[2])
			mi.visible = false
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			(pair[0] as Array).append(mi)
	var star := Kit.new()
	# muzzle flash: a bright core, a forward spike and four petals around the barrel
	star.sphere(Kit.at(0, 0, 0.05), Vector3(0.14, 0.14, 0.2), Color.WHITE, 8, 5)
	star.box(Kit.at(0, 0, 0.28), Vector3(0.07, 0.07, 0.5), Color.WHITE, 0.0)
	for i in 4: star.box(Kit.rot(0, 0, 0.08, 0.0, 0.0, i * PI * 0.5 + PI * 0.25), Vector3(0.05, 0.34, 0.05), Color(1, 0.85, 0.6), 0.0)
	var star_mesh := star.commit()
	for i in 12:
		var mi := MeshInstance3D.new()
		mi.mesh = star_mesh
		mi.material_override = mat_fx(Color("ffd27a"), 4.0)
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		flashes.append(mi)
	for i in 6:
		var l := OmniLight3D.new()
		l.light_energy = 0.0
		l.omni_range = 6.0
		l.shadow_enabled = false
		add_child(l)
		lights.append([l, 0.0])
	for i in 40:
		var l := Label3D.new()
		l.font_size = 64
		l.outline_size = 16
		l.pixel_size = 0.006
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.outline_modulate = Color(0.15, 0.08, 0.15, 1)
		l.visible = false
		add_child(l)
		numbers.append([l, 0.0, Vector3.ZERO])
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	for i in 16:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		var m := ShaderMaterial.new()
		m.shader = soft_shader
		m.set_shader_parameter("shape", 1)
		m.set_shader_parameter("color", Color(1, 1, 1, 0.9))
		mi.material_override = m
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		rings.append(mi)
	make_pool("sparks", 10, func(p:CPUParticles3D):
		p.amount = 10
		p.lifetime = 0.35
		p.explosiveness = 1.0
		p.spread = 70.0
		p.direction = Vector3(0, 1, 0)
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 6.0
		p.gravity = Vector3(0, -12, 0)
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.0
		p.mesh = small_box(Vector3(0.06, 0.06, 0.18), Color("ffe6a0"), true)
		p.particle_flag_align_y = true
	)
	make_pool("confetti", 10, func(p:CPUParticles3D):
		p.amount = 34
		p.lifetime = 1.4
		p.explosiveness = 0.95
		p.spread = 180.0
		p.direction = Vector3(0, 1, 0)
		p.initial_velocity_min = 3.5
		p.initial_velocity_max = 7.5
		p.gravity = Vector3(0, -6, 0)
		p.damping_min = 2.0
		p.damping_max = 4.0
		p.angular_velocity_min = -720
		p.angular_velocity_max = 720
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.3
		p.mesh = small_box(Vector3(0.12, 0.02, 0.08), Color.WHITE, false)
		var g := Gradient.new()
		g.colors = PackedColorArray([Color("ff6b6b"), Color("ffd166"), Color("06d6a0"), Color("4cc9f0"), Color("f78fb3"), Color("c59dff")])
		g.offsets = PackedFloat32Array([0, 0.2, 0.4, 0.6, 0.8, 1.0])
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		p.color_initial_ramp = g
	)
	make_pool("leaves", 8, func(p:CPUParticles3D):
		p.amount = 12
		p.lifetime = 1.2
		p.explosiveness = 0.9
		p.spread = 180.0
		p.direction = Vector3(0, 1, 0)
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 4.5
		p.gravity = Vector3(0, -4, 0)
		p.angular_velocity_min = -400
		p.angular_velocity_max = 400
		p.mesh = small_box(Vector3(0.18, 0.02, 0.1), Color("7cd06a"), false)
	)
	make_pool("puff", 10, func(p:CPUParticles3D):
		p.amount = 10
		p.lifetime = 0.8
		p.explosiveness = 0.95
		p.spread = 180.0
		p.direction = Vector3(0, 1, 0)
		p.initial_velocity_min = 0.8
		p.initial_velocity_max = 2.2
		p.gravity = Vector3(0, 0.8, 0)
		p.damping_min = 2.0
		p.damping_max = 3.0
		var c := Curve.new()
		c.add_point(Vector2(0, 0.5))
		c.add_point(Vector2(0.3, 1.0))
		c.add_point(Vector2(1, 0.0))
		p.scale_amount_curve = c
		p.scale_amount_min = 1.0
		p.scale_amount_max = 1.8
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.6
		sm.radial_segments = 8
		sm.rings = 4
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.96, 0.94, 1.0)
		m.vertex_color_use_as_albedo = true
		sm.material = m
		p.mesh = sm
	)
	make_pool("debris", 8, func(p:CPUParticles3D):
		p.amount = 14
		p.lifetime = 1.0
		p.explosiveness = 1.0
		p.spread = 80.0
		p.direction = Vector3(0, 1, 0)
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 6.0
		p.gravity = Vector3(0, -14, 0)
		p.angular_velocity_min = -600
		p.angular_velocity_max = 600
		p.mesh = small_box(Vector3(0.14, 0.06, 0.3), Color("c98a55"), false)
	)
	make_pool("heal", 6, func(p:CPUParticles3D):
		p.amount = 10
		p.lifetime = 1.0
		p.explosiveness = 0.6
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.6
		p.direction = Vector3(0, 1, 0)
		p.spread = 15.0
		p.initial_velocity_min = 1.2
		p.initial_velocity_max = 2.0
		p.gravity = Vector3.ZERO
		var k := Kit.new()
		k.box(Kit.at(0, 0, 0), Vector3(0.2, 0.06, 0.06), Color.WHITE, 0.0)
		k.box(Kit.at(0, 0, 0), Vector3(0.06, 0.2, 0.06), Color.WHITE, 0.0)
		var mesh := k.commit()
		mesh.surface_set_material(0, mat_fx(Color("6aff9a"), 2.5))
		p.mesh = mesh
	)
	make_pool("goo", 6, func(p:CPUParticles3D):
		p.amount = 12
		p.lifetime = 0.6
		p.explosiveness = 1.0
		p.spread = 80.0
		p.direction = Vector3(0, 1, 0)
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 4.0
		p.gravity = Vector3(0, -12, 0)
		p.mesh = small_box(Vector3(0.12, 0.12, 0.12), Color("b86ae8"), true)
	)
	make_pool("flame", 6, func(p:CPUParticles3D):
		p.amount = 18
		p.lifetime = 0.35
		p.explosiveness = 0.4
		p.spread = 14.0
		p.direction = Vector3(0, 0, 1)
		p.initial_velocity_min = 11.0
		p.initial_velocity_max = 15.0
		p.gravity = Vector3.ZERO
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		var g := Gradient.new()
		g.colors = PackedColorArray([Color("fff2a0"), Color("ff9a3a"), Color("ff4ab0")])
		p.color_ramp = g
		p.local_coords = false
		p.mesh = small_box(Vector3(0.16, 0.16, 0.16), Color.WHITE, true)
	)
	make_pool("smoke", 10, func(p:CPUParticles3D):
		p.amount = 5
		p.lifetime = 0.55
		p.explosiveness = 0.9
		p.spread = 25.0
		p.direction = Vector3(0, 0.3, 1)
		p.initial_velocity_min = 0.8
		p.initial_velocity_max = 2.0
		p.gravity = Vector3(0, 1.2, 0)
		p.damping_min = 3.0
		p.damping_max = 5.0
		var c := Curve.new()
		c.add_point(Vector2(0, 0.3))
		c.add_point(Vector2(0.35, 1.0))
		c.add_point(Vector2(1, 0.0))
		p.scale_amount_curve = c
		p.scale_amount_min = 0.15
		p.scale_amount_max = 0.3
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.6
		sm.radial_segments = 8
		sm.rings = 4
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.92, 0.9, 0.95, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.material = m
		p.mesh = sm
	)
	make_pool("casing", 12, func(p:CPUParticles3D):
		p.amount = 1
		p.lifetime = 0.7
		p.explosiveness = 1.0
		p.spread = 20.0
		p.direction = Vector3(1, 1.2, -0.3)
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 3.5
		p.gravity = Vector3(0, -16, 0)
		p.angular_velocity_min = -900
		p.angular_velocity_max = 900
		p.local_coords = false
		var b := BoxMesh.new()
		b.size = Vector3(0.035, 0.035, 0.09)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("e7b84a")
		m.metallic = 0.6
		m.roughness = 0.3
		b.material = m
		p.mesh = b
	)
	make_pool("dust", 28, func(p:CPUParticles3D):
		p.amount = 6
		p.lifetime = 0.5
		p.explosiveness = 1.0
		p.spread = 50.0
		p.direction = Vector3(0, 1, 0)
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 2.4
		p.gravity = Vector3(0, -2, 0)
		p.damping_min = 3.0
		p.damping_max = 4.0
		var c := Curve.new()
		c.add_point(Vector2(0, 0.4))
		c.add_point(Vector2(0.3, 1.0))
		c.add_point(Vector2(1, 0.0))
		p.scale_amount_curve = c
		p.scale_amount_min = 0.3
		p.scale_amount_max = 0.55
		var sm := SphereMesh.new()
		sm.radius = 0.25
		sm.height = 0.5
		sm.radial_segments = 6
		sm.rings = 3
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("d8c7a6")
		sm.material = m
		p.mesh = sm
	)
	make_pool("hit", 12, func(p:CPUParticles3D):
		p.amount = 8
		p.lifetime = 0.4
		p.explosiveness = 1.0
		p.spread = 45.0
		p.direction = Vector3(0, 0.4, 1)
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 4.5
		p.gravity = Vector3(0, -10, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.2
		p.mesh = small_box(Vector3(0.09, 0.09, 0.09), Color("9be36a"), false)
	)
	make_pool("clods", 24, func(p:CPUParticles3D):
		# lumps of earth thrown up as a brotado breaks the surface
		p.amount = 9
		p.lifetime = 0.9
		p.explosiveness = 0.9
		p.spread = 40.0
		p.direction = Vector3(0, 1, 0)
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 5.5
		p.gravity = Vector3(0, -14, 0)
		p.angular_velocity_min = -500
		p.angular_velocity_max = 500
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.5
		p.mesh = small_box(Vector3(0.14, 0.11, 0.13), Color.WHITE, false)
		var g := Gradient.new()
		g.colors = PackedColorArray([Color("6b4a32"), Color("8a6342"), Color("54402c"), Color("7d5a3c"), Color("5fae5e")])
		g.offsets = PackedFloat32Array([0, 0.3, 0.55, 0.8, 0.95])
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		p.color_initial_ramp = g
	)
	make_pool("bits", 8, func(p:CPUParticles3D):
		# odds and ends thrown out while someone rummages: cans, screws, rags, coins
		p.amount = 6
		p.lifetime = 0.8
		p.explosiveness = 0.85
		p.spread = 35.0
		p.direction = Vector3(0, 1, 0)
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 4.5
		p.gravity = Vector3(0, -12, 0)
		p.angular_velocity_min = -600
		p.angular_velocity_max = 600
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.4
		p.mesh = small_box(Vector3(0.1, 0.08, 0.06), Color.WHITE, false)
		var g := Gradient.new()
		g.colors = PackedColorArray([Color("c8ccd4"), Color("e8463c"), Color("f2c14e"), Color("5a9ae8"), Color("8b5e3c"), Color("7cd06a")])
		g.offsets = PackedFloat32Array([0, 0.2, 0.4, 0.6, 0.8, 1.0])
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		p.color_initial_ramp = g
	)
	make_pool("stars", 4, func(p:CPUParticles3D):
		p.amount = 24
		p.lifetime = 1.2
		p.explosiveness = 0.9
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_radius = 1.0
		p.emission_ring_inner_radius = 0.8
		p.emission_ring_height = 0.1
		p.direction = Vector3(0, 1, 0)
		p.spread = 10.0
		p.initial_velocity_min = 1.5
		p.initial_velocity_max = 3.0
		p.gravity = Vector3.ZERO
		p.mesh = small_box(Vector3(0.1, 0.1, 0.1), Color("ffe680"), true)
	)

func mat_fx(c:Color, energy:float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = fx_shader
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("energy", energy)
	return m

func small_box(size:Vector3, c:Color, glowing:bool) -> Mesh:
	var b := BoxMesh.new()
	b.size = size
	if glowing:
		b.material = mat_fx(c, 3.0)
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		b.material = m
	return b

func make_pool(name:String, count:int, setup:Callable):
	pools[name] = []
	pool_i[name] = 0
	for i in count:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		setup.call(p)
		add_child(p)
		pools[name].append(p)

func burst(name:String, at:Vector3, dir:Vector3 = Vector3.ZERO):
	var list:Array = pools[name]
	var p:CPUParticles3D = list[pool_i[name]]
	pool_i[name] = (pool_i[name] + 1) % list.size()
	p.global_position = at
	if dir != Vector3.ZERO:
		p.global_basis = Basis.looking_at(-dir.normalized(), Vector3.UP) if absf(dir.normalized().y) < 0.99 else Basis()
	p.restart()
	p.emitting = true

func light(at:Vector3, c:Color, energy:float, life:float = 0.08, rng:float = 6.0):
	var l:OmniLight3D = lights[light_i][0]
	lights[light_i][1] = life
	light_i = (light_i + 1) % lights.size()
	l.global_position = at
	if not bright: energy *= 0.25
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.set_meta("e", energy)
	l.set_meta("life", life)

func tracer(a:Vector3, b:Vector3, c:Color, width:float = 0.06, life:float = 0.08):
	## Static beam (turret zaps, special shots).
	var mi:MeshInstance3D = tracers.pop_front()
	tracers.append(mi)
	var d := a.distance_to(b)
	if d < 0.05: return
	mi.visible = true
	mi.global_transform = Transform3D(Basis.looking_at((b - a) / d, Vector3.UP).scaled(Vector3(width, width, d)), (a + b) * 0.5)
	(mi.material_override as ShaderMaterial).set_shader_parameter("color", c)
	live.append([mi, 0.0, life, "tracer", null])

func bullet(a:Vector3, b:Vector3, c:Color, width:float, speed:float, streak:float):
	## A real-looking projectile: a bright rounded slug flying from the muzzle to the
	## impact point at a visible speed, with a short tapered glow behind it.
	var d := a.distance_to(b)
	if d < 0.05: return
	var slug:MeshInstance3D = slugs.pop_front()
	slugs.append(slug)
	var trail:MeshInstance3D = trails.pop_front()
	trails.append(trail)
	(slug.material_override as ShaderMaterial).set_shader_parameter("color", c.lerp(Color.WHITE, 0.55))
	(trail.material_override as ShaderMaterial).set_shader_parameter("color", c)
	for mi in [slug, trail]:
		mi.set_instance_shader_parameter("fade", 1.0)
		mi.visible = false   # placed by the first update, never shown at a stale spot
	live.append([slug, 0.0, d / speed, "bullet", [a, b, d, width, streak, trail]])

func muzzle(at:Vector3, c:Color, size:float = 1.0, dir:Vector3 = Vector3.ZERO):
	var mi:MeshInstance3D = flashes.pop_front()
	flashes.append(mi)
	mi.visible = true
	mi.global_position = at
	if dir.length_squared() > 0.01:
		mi.global_basis = Basis.looking_at(-dir.normalized(), Vector3.UP).rotated(dir.normalized(), randf() * TAU)
		mi.scale = Vector3(size, size, size * randf_range(0.9, 1.4))
	else:
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
		mi.scale = Vector3.ONE * size
	(mi.material_override as ShaderMaterial).set_shader_parameter("color", c.lerp(Color("fff3c4"), 0.5))
	live.append([mi, 0.0, 0.05, "flash", size])
	light(at, Color("ffd9a0"), 3.0 * size, 0.06)

func impact(at:Vector3, dir:Vector3, on_enemy:bool):
	if on_enemy:
		burst("hit", at + Vector3(0, 0.9, 0), dir)
	else:
		burst("dust", Vector3(at.x, 0.1, at.z))
		burst("sparks", at, -dir)

func number(at:Vector3, text:String, c:Color, big:bool):
	if not show_numbers: return
	var n:Array = numbers[number_i]
	number_i = (number_i + 1) % numbers.size()
	var l:Label3D = n[0]
	l.text = text
	l.modulate = c
	l.visible = true
	l.font_size = 80 if big else 58
	l.global_position = at + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.2, 0.2))
	n[1] = 0.0
	n[2] = l.global_position

func ring(at:Vector3, c:Color, from:float, to:float, life:float, pulse:bool = false):
	var mi:MeshInstance3D = rings[ring_i]
	ring_i = (ring_i + 1) % rings.size()
	mi.visible = true
	mi.global_position = at + Vector3(0, 0.06, 0)
	mi.set_instance_shader_parameter("itint", c)
	live.append([mi, 0.0, life, "ring", [from, to, pulse]])

func zigzag(points:Array, c:Color, width:float, life:float, vertical:bool):
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size() - 1:
		var a:Vector3 = points[i]
		var b:Vector3 = points[i + 1]
		var side := Vector3(width, 0, 0) if vertical else (b - a).cross(Vector3.UP).normalized() * width
		for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
			im.surface_add_vertex(v)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat_fx(c, 4.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	live.append([mi, 0.0, life, "bolt", null])

func jagged(a:Vector3, b:Vector3, steps:int, amp:float) -> Array:
	var pts := [a]
	for i in range(1, steps):
		var t := float(i) / steps
		pts.append(a.lerp(b, t) + Vector3(randf_range(-amp, amp), randf_range(-amp, amp) * 0.4, randf_range(-amp, amp)))
	pts.append(b)
	return pts

func shake(amount:float):
	trauma = minf(1.0, trauma + amount)

# ------------------------------------------------------------------ events
func gun_color(g:int) -> Color:
	if g == 7: return Color("8ff6ff")
	return Color(Data.WEAPONS[clampi(g, 0, Data.WEAPONS.size() - 1)].color).lightened(0.3)

func shot(owner:int, g:int, a:Vector3, b:Vector3, local:bool, hit:int = -1, first:bool = true):
	var c := gun_color(g)
	var dir := (b - a).normalized()
	# width, speed (m/s) and glow length: pistol, shotgun, smg, rifle, sniper, launcher, flame, turret
	var spec:Array = [[0.06, 46.0, 0.9], [0.05, 40.0, 0.6], [0.05, 52.0, 0.8], [0.06, 62.0, 1.2], [0.08, 95.0, 2.2], [0.0, 1.0, 0.0], [0.0, 1.0, 0.0], [0.07, 32.0, 1.8]][clampi(g, 0, 7)]
	if g != 5 and g != 6: bullet(a, b, c, spec[0], spec[1], spec[2])
	if first and owner != -999:
		muzzle(a + dir * 0.08, c, 1.4 if g in [1, 4, 5] else 0.9, dir)
		burst("smoke", a + dir * 0.2, dir)
		if g in [0, 2, 3, 4] and owner > 0: burst("casing", a - dir * 0.25 + Vector3(0, 0.05, 0), dir.cross(Vector3.UP) * -1.0)
	if g != 5 and a.distance_to(b) > 0.5:
		live.append([null, 0.0, a.distance_to(b) / spec[1], "impact", [b, dir, hit == 1]])

func explosion(at:Vector3, radius:float):
	burst("puff", at + Vector3(0, 0.3, 0))
	burst("confetti", at + Vector3(0, 0.4, 0))
	burst("debris", at)
	burst("sparks", at)
	light(at + Vector3(0, 1.0, 0), Color("ffb35c"), 8.0, 0.25, radius * 4.0)
	ring(at, Color("ffd9a0"), 0.3, radius * 2.2, 0.35)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	mi.mesh = sm
	mi.material_override = mat_fx(Color("ffcf7a"), 3.0 if bright else 0.8)
	mi.position = at + Vector3(0, 0.4, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	live.append([mi, 0.0, 0.22, "blast", radius])
	shake(0.35)

func death(at:Vector3, kind:int):
	# the body falls on its own now: a pop of confetti and leaves, dust at the feet
	burst("confetti", at + Vector3(0, 1.2, 0))
	burst("leaves", at + Vector3(0, 1.3, 0))
	burst("dust", at)
	if kind == 7:
		for i in 4: burst("confetti", at + Vector3(randf_range(-1.5, 1.5), 2.0 + i * 0.5, randf_range(-1.5, 1.5)))
		shake(0.6)

func bolt(at:Vector3):
	var top := at + Vector3(randf_range(-2, 2), 26, randf_range(-1, 1))
	zigzag(jagged(top, at, 9, 1.4), Color("e8f4ff"), 0.22, 0.22, true)
	light(at + Vector3(0, 2, 0), Color("cfe4ff"), 12.0, 0.2, 18.0)
	burst("sparks", at)
	burst("puff", at)
	ring(at, Color("cfe4ff"), 0.5, 4.5, 0.4)
	shake(0.45)

func zap(a:Vector3, b:Vector3):
	zigzag(jagged(a, b, 6, 0.25), Color("9ff6ff"), 0.05, 0.12, false)
	light(b, Color("9ff6ff"), 2.5, 0.08)

# ------------------------------------------------------------------ update
func _process(dt:float):
	for i in range(live.size() - 1, -1, -1):
		var e:Array = live[i]
		e[1] += dt
		var f:float = e[1] / e[2]
		var node:Node3D = e[0]
		if f >= 1.0:
			if e[3] == "impact":
				impact(e[4][0], e[4][1], e[4][2])
			elif e[3] == "bullet":
				node.visible = false
				(e[4][5] as Node3D).visible = false
			elif e[3] in ["blast", "bolt"]: node.queue_free()
			else: node.visible = false
			live.remove_at(i)
			continue
		match e[3]:
			"bullet":
				var d:Array = e[4]
				var a:Vector3 = d[0]
				var b:Vector3 = d[1]
				var dist:float = d[2]
				var w:float = d[3]
				var trail:MeshInstance3D = d[5]
				var head_d := dist * f
				var dir := (b - a) / dist
				var head := a + dir * head_d
				var look := Basis.looking_at(dir, Vector3.UP) if absf(dir.y) < 0.99 else Basis()
				node.visible = true
				node.global_transform = Transform3D(look.scaled(Vector3(w * 1.6, w * 1.6, w * 3.2)), head)
				var tl := minf(float(d[4]), head_d)
				trail.visible = tl > 0.05
				if trail.visible: trail.global_transform = Transform3D(look.scaled(Vector3(w * 1.5, w * 1.5, tl)), head)
			"tracer", "flash", "bolt":
				(node as GeometryInstance3D).set_instance_shader_parameter("fade", 1.0 - f)
			"ring":
				var d:Array = e[4]
				var s:float = lerpf(d[0], d[1], 1.0 - pow(1.0 - f, 3.0))
				if d[2]: s = d[1] * (0.85 + 0.15 * sin(e[1] * 12.0))
				node.scale = Vector3(s, 1, s)
				(node as GeometryInstance3D).set_instance_shader_parameter("fade", 1.0 - f if not d[2] else 0.9)
			"blast":
				node.scale = Vector3.ONE * lerpf(0.5, e[4] * 2.0, sqrt(f))
				(node as GeometryInstance3D).set_instance_shader_parameter("fade", 1.0 - f)
	for l in lights:
		if l[1] > 0:
			l[1] -= dt
			var light_node:OmniLight3D = l[0]
			light_node.light_energy = float(light_node.get_meta("e", 0.0)) * maxf(0.0, l[1] / float(light_node.get_meta("life", 0.1)))
		else:
			(l[0] as OmniLight3D).light_energy = 0.0
	for n in numbers:
		var l:Label3D = n[0]
		if not l.visible: continue
		n[1] += dt
		var f:float = n[1] / 0.8
		if f >= 1.0:
			l.visible = false
			continue
		l.global_position = n[2] + Vector3(0, 1.8 + f * 1.2, 0)
		var pop := 1.0 + 0.6 * maxf(0.0, 1.0 - f * 6.0)
		l.scale = Vector3.ONE * pop
		l.modulate.a = 1.0 - smoothstep(0.6, 1.0, f)
		l.outline_modulate.a = l.modulate.a
	trauma = maxf(0.0, trauma - dt * 1.6)
