extends Node3D
## The neighbourhood: static scenery merged into a few chunked meshes, vegetation in
## MultiMeshes, festival decorations, lighting rig, day/night cycle and weather.

const Kit = preload("res://game/view/kit.gd")
const Map = preload("res://game/map.gd")
const Data = preload("res://game/data.gd")

const CHUNK := 24.0
var toon:ShaderMaterial
var foliage:ShaderMaterial
var sway:ShaderMaterial
var chunks := {}
var sun := DirectionalLight3D.new()
var env := Environment.new()
var world_env := WorldEnvironment.new()
var sky_mat := ShaderMaterial.new()
var cam_attr := CameraAttributesPractical.new()
var lamps := []
var rain:GPUParticles3D
var leaves:GPUParticles3D
var fireflies:GPUParticles3D
var smoke := []
var butterflies := []
var flash_light := 0.0
var rng := RandomNumberGenerator.new()
var quality := 2
var grass_mm:MultiMeshInstance3D
var tod_now := 0.3
var cur_fog := 0.0
var cur_wet := 0.0
var cur_blackout := 0.0
var cur_red := 0.0
var label_nodes := []
var stage_lights := []
var finale_on := 0.0

# palette
const GRASS_A = "7cc46a"
const WALLS = ["f7dcae", "a9dccb", "f6bcab", "c9d3f2", "fff0c4", "f3c98f"]
const ROOFS = ["dc6553", "5384c0", "5aa572", "9a6ab8", "e8973f", "d75a7a"]
const DOORS = ["4a7aa8", "b85a4a", "5a9a6a", "7d5aa8"]
const FOLIAGE = ["6cc05a", "52aa5c", "8fd16a", "f4a9c4", "f2c54a"]

func _init():
	rng.seed = 7
	toon = ShaderMaterial.new()
	toon.shader = load("res://game/shaders/toon.gdshader")
	foliage = ShaderMaterial.new()
	foliage.shader = toon.shader
	foliage.set_shader_parameter("wind_amp", 0.05)
	foliage.set_shader_parameter("rim_strength", 0.45)
	sway = ShaderMaterial.new()
	sway.shader = toon.shader
	sway.set_shader_parameter("wind_amp", 0.35)

static func col(hex:String) -> Color:
	return Color(hex)

func K(p:Vector2) -> Kit:
	var key := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	if not chunks.has(key): chunks[key] = Kit.new()
	return chunks[key]

func yaw_for(face:Vector2) -> float:
	return atan2(face.x, face.y)

# ================================================================== build
func build():
	var t0 := Time.get_ticks_msec()
	setup_environment()
	build_ground()
	build_streets()
	build_plaza()
	build_base()
	for h in Map.HOUSES: house(h.rect, h.face, h.style)
	build_sites()
	build_park()
	build_parking()
	build_props()
	build_border()
	build_festival()
	for key in chunks:
		var mi := MeshInstance3D.new()
		mi.mesh = chunks[key].commit()
		mi.material_override = toon
		add_child(mi)
	chunks.clear()
	build_trees()
	build_grass()
	build_particles()
	print("Barrio construido en %d ms" % (Time.get_ticks_msec() - t0))

func setup_environment():
	add_child(world_env)
	world_env.environment = env
	world_env.camera_attributes = cam_attr
	var sky := Sky.new()
	sky_mat.shader = load("res://game/shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.tonemap_white = 3.2
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(5, 0.5)
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.14
	env.adjustment_contrast = 1.08
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.004
	env.fog_sky_affect = 0.15
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_light_affect = 0.15
	add_child(sun)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	cam_attr.dof_blur_far_enabled = false
	cam_attr.dof_blur_far_distance = 40.0
	cam_attr.dof_blur_far_transition = 18.0
	cam_attr.dof_blur_amount = 0.05

func set_quality(q:int):
	quality = q
	sun.shadow_enabled = q >= 1
	env.ssao_enabled = q >= 2
	cam_attr.dof_blur_far_enabled = q >= 3
	env.volumetric_fog_enabled = q >= 3 and cur_fog > 0.05
	RenderingServer.directional_shadow_atlas_set_size(4096 if q >= 2 else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if q >= 2 else RenderingServer.SHADOW_QUALITY_HARD)
	if grass_mm: grass_mm.multimesh.visible_instance_count = -1 if q >= 2 else grass_mm.multimesh.instance_count / (2 if q == 1 else 4)
	for p in [leaves, fireflies]:
		if p: p.amount_ratio = 1.0 if q >= 2 else 0.5

# ================================================================== ground
func ground_plane(rect:Rect2, pattern:int, a:String, b:String, c:String, y:float = 0.0):
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = rect.size
	pm.subdivide_width = 0
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = load("res://game/shaders/ground.gdshader")
	m.set_shader_parameter("pattern", pattern)
	m.set_shader_parameter("color_a", Color(a))
	m.set_shader_parameter("color_b", Color(b))
	m.set_shader_parameter("color_c", Color(c))
	m.set_shader_parameter("rim_strength", 0.0)
	m.set_shader_parameter("gloss", 0.05 if pattern == 0 else 0.25)
	mi.material_override = m
	mi.position = Vector3(rect.get_center().x, y, rect.get_center().y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func build_ground():
	ground_plane(Rect2(-70, -62, 140, 124), 0, GRASS_A, "a7d76c", "5fae5e", -0.02)
	for z in Map.ROADS_H: ground_plane(Rect2(-60, z - 2, 120, 4), 1, "727d92", "7f8aa0", "000000", 0.0)
	for x in Map.ROADS_V:
		ground_plane(Rect2(x - 2, -60, 4, 48 - 2), 1, "727d92", "7f8aa0", "000000", 0.005)
		ground_plane(Rect2(x - 2, -10, 4, 20), 1, "727d92", "7f8aa0", "000000", 0.005)
		ground_plane(Rect2(x - 2, 14, 4, 46), 1, "727d92", "7f8aa0", "000000", 0.005)
	ground_plane(Rect2(-11, -9, 22, 18), 2, "f4dcab", "eac88f", "c89f73", 0.02)
	ground_plane(Rect2(-11, 15, 22, 6), 1, "8590a3", "929cae", "000000", 0.01)
	ground_plane(Rect2(-28, -6, 10, 10), 2, "d9dde3", "cfd4db", "a9b0ba", 0.015)
	ground_plane(Rect2(-33, 19, 13, 10), 2, "d9cbb3", "cbbb9f", "a99a80", 0.015)
	ground_plane(Rect2(20.5, -5, 11, 8), 2, "d9d3c9", "cbc4b8", "a59d90", 0.015)

func is_open_grass(p:Vector2) -> bool:
	for z in Map.ROADS_H: if absf(p.y - z) < 3.4: return false
	for x in Map.ROADS_V: if absf(p.x - x) < 3.4: return false
	for r in [Rect2(-11.5, -9.5, 23, 19), Rect2(-11.5, 14.5, 23, 7), Rect2(-28.5, -6.5, 11, 11), Rect2(-33.5, 18.5, 14, 11), Rect2(20, -5.5, 12, 9)]:
		if r.has_point(p): return false
	for r in Map.solids():
		if r.grow(0.6).has_point(p): return false
	if Rect2(-4.5, -27, 9, 8).has_point(p): return false
	return true

func build_streets():
	var line := col("f6eed6")
	for z in Map.ROADS_H:
		for x in range(-58, 58, 3):
			if absf(x - Map.ROADS_V[0]) < 2.5 or absf(x - Map.ROADS_V[1]) < 2.5: continue
			K(Vector2(x, z)).box(Kit.at(x, 0.02, z), Vector3(1.4, 0.02, 0.16), line, 0.0)
		for side in [-1, 1]:
			for seg in [[-60.0, -16.0], [-12.0, 12.0], [16.0, 60.0]]:
				var cx:float = (seg[0] + seg[1]) * 0.5
				K(Vector2(cx, z)).box(Kit.at(cx, 0.07, z + side * 2.5), Vector3(seg[1] - seg[0], 0.14, 1.0), col("e6dbc3"), 0.04, 0.2)
				K(Vector2(cx, z)).box(Kit.at(cx, 0.08, z + side * 2.0), Vector3(seg[1] - seg[0], 0.16, 0.14), col("cdbfa5"), 0.03)
	for x in Map.ROADS_V:
		for z in range(-58, 58, 3):
			if absf(z - Map.ROADS_H[0]) < 2.5 or absf(z - Map.ROADS_H[1]) < 2.5: continue
			K(Vector2(x, z)).box(Kit.at(x, 0.025, z), Vector3(0.16, 0.02, 1.4), line, 0.0)
		for side in [-1, 1]:
			for seg in [[-60.0, -14.5], [-9.5, 9.5], [14.5, 60.0]]:
				var cz:float = (seg[0] + seg[1]) * 0.5
				K(Vector2(x, cz)).box(Kit.at(x + side * 2.5, 0.07, cz), Vector3(1.0, 0.14, seg[1] - seg[0]), col("e6dbc3"), 0.04, 0.2)
				K(Vector2(x, cz)).box(Kit.at(x + side * 2.0, 0.08, cz), Vector3(0.14, 0.16, seg[1] - seg[0]), col("cdbfa5"), 0.03)
	# zebra crossings at every junction
	for x in Map.ROADS_V:
		for z in Map.ROADS_H:
			for side in [-1, 1]:
				for i in 5:
					var off := -1.4 + i * 0.7
					K(Vector2(x, z)).box(Kit.at(x + off, 0.03, z + side * 3.0), Vector3(0.42, 0.02, 1.2), line, 0.0)
					K(Vector2(x, z)).box(Kit.at(x + side * 3.0, 0.03, z + off), Vector3(1.2, 0.02, 0.42), line, 0.0)
	# street lamps
	var spots := []
	for z in Map.ROADS_H:
		for x in [-30.0, -20.0, -8.0, 8.0, 20.0, 30.0]: spots.append(Vector2(x, z - 2.6))
	for x in Map.ROADS_V:
		for z in [-24.0, -4.0, 4.0, 24.0]: spots.append(Vector2(x + 2.6, z))
	for s in spots: street_lamp(s)

func street_lamp(p:Vector2):
	var k := K(p)
	k.cylinder(Kit.at(p.x, 0.15, p.y), 0.16, 0.14, 0.3, col("3e4a5c"), 8)
	k.cylinder(Kit.at(p.x, 1.9, p.y), 0.06, 0.06, 3.6, col("3e4a5c"), 8)
	k.box(Kit.at(p.x, 3.72, p.y), Vector3(0.5, 0.12, 0.5), col("3e4a5c"), 0.05)
	k.sphere(Kit.at(p.x, 3.55, p.y), Vector3(0.22, 0.22, 0.22), Kit.glow(col("ffe6a8")), 10, 6)
	var l := OmniLight3D.new()
	l.position = Vector3(p.x, 3.3, p.y)
	l.light_color = Color("ffc47a")
	l.omni_range = 8.0
	l.omni_attenuation = 1.4
	l.light_energy = 0.0
	l.shadow_enabled = false
	add_child(l)
	lamps.append(l)

func build_plaza():
	var k := K(Vector2(0, 0))
	# low planters along the plaza edge with flowers
	for corner in [Vector2(-9.5, -7.5), Vector2(9.5, -7.5), Vector2(-9.5, 7.5), Vector2(9.5, 7.5)]:
		k.box(Kit.at(corner.x, 0.25, corner.y), Vector3(2.4, 0.5, 2.4), col("c9a27c"), 0.1, 0.25)
		k.box(Kit.at(corner.x, 0.5, corner.y), Vector3(2.1, 0.08, 2.1), col("7a5a40"), 0.04)
		for i in 9:
			var a := i * 2.39
			var rr := 0.25 + 0.6 * fmod(i * 0.37, 1.0)
			var fc:String = ["ff8fa3", "ffd166", "c59dff", "ffffff"][i % 4]
			k.sphere(Kit.at(corner.x + cos(a) * rr, 0.62, corner.y + sin(a) * rr), Vector3(0.18, 0.13, 0.18), col("5aa55a"), 8, 4)
			k.sphere(Kit.at(corner.x + cos(a) * rr, 0.74, corner.y + sin(a) * rr), Vector3(0.1, 0.07, 0.1), col(fc), 8, 4)
	# benches
	for b in [[Vector2(-6.5, 6.8), 0.0], [Vector2(6.5, 6.8), 0.0], [Vector2(-6.5, -6.5), PI], [Vector2(6.5, -6.5), PI]]:
		bench(k, b[0], b[1])

func bench(k:Kit, p:Vector2, yaw:float):
	var xf := Kit.rot(p.x, 0, p.y, yaw)
	for x in [-0.7, 0.7]:
		k.box(xf * Kit.at(x, 0.22, 0), Vector3(0.1, 0.44, 0.5), col("4a4f5c"), 0.03)
	for i in 3: k.box(xf * Kit.at(0, 0.46, -0.16 + i * 0.16), Vector3(1.7, 0.06, 0.13), col("c98a55"), 0.03)
	for i in 2: k.box(xf * Kit.at(0, 0.7 + i * 0.18, -0.28), Vector3(1.7, 0.12, 0.05), col("c98a55"), 0.03)

# ================================================================== buildings
func walls_with_windows(k:Kit, xf:Transform3D, w:float, d:float, h:float, wall:Color, trim:Color, shutter:Color, front_door:bool, door_col:Color):
	k.box(xf * Kit.at(0, 0.15, 0), Vector3(w + 0.25, 0.3, d + 0.25), col("b6a99b"), 0.05, 0.2)
	k.box(xf * Kit.at(0, 0.3 + h * 0.5, 0), Vector3(w, h, d), wall, 0.09, 0.22, 1)
	for cx in [-1, 1]:
		for cz in [-1, 1]:
			k.box(xf * Kit.at(cx * (w * 0.5 - 0.02), 0.3 + h * 0.5, cz * (d * 0.5 - 0.02)), Vector3(0.22, h + 0.02, 0.22), trim, 0.05)
	k.box(xf * Kit.at(0, 0.3 + h - 0.05, 0), Vector3(w + 0.12, 0.14, d + 0.12), trim, 0.04)
	var glass := Kit.glow(col("bfe2ff"), 1.0)
	var floors := 1 if h < 3.0 else 2
	for f in floors:
		var y := 0.3 + 1.25 + f * 1.55
		var xs := [-w * 0.3, w * 0.3] if front_door and f == 0 else ([-w * 0.3, 0.0, w * 0.3] if w > 5 else [-w * 0.25, w * 0.25])
		for x in xs: window(k, xf * Kit.at(x, y, d * 0.5), trim, glass, shutter)
		for side in [-1, 1]:
			window(k, xf * Kit.rot(side * w * 0.5, y, 0, side * PI * 0.5), trim, glass, shutter)
		window(k, xf * Kit.rot(0, y, -d * 0.5, PI), trim, glass, shutter)
	if front_door:
		var dz := d * 0.5
		k.box(xf * Kit.at(0, 1.4, dz + 0.02), Vector3(1.25, 2.2, 0.14), trim, 0.05)
		k.box(xf * Kit.at(0, 1.35, dz + 0.07), Vector3(0.95, 2.0, 0.1), door_col, 0.08, 0.15)
		k.box(xf * Kit.at(0, 1.95, dz + 0.13), Vector3(0.5, 0.4, 0.04), glass, 0.04)
		k.sphere(xf * Kit.at(0.3, 1.3, dz + 0.16), Vector3(0.06, 0.06, 0.06), col("f2c14e"), 8, 4)
		k.box(xf * Kit.at(0, 0.12, dz + 0.55), Vector3(1.6, 0.24, 0.8), col("cfc5b8"), 0.05)
		var awning := xf * Kit.rot(0, 2.75, dz + 0.45, 0, 0.35)
		k.box(awning, Vector3(1.8, 0.1, 0.95), shutter.darkened(0.1), 0.04)
		k.sphere(xf * Kit.at(0.85, 2.2, dz + 0.2), Vector3(0.12, 0.16, 0.12), Kit.glow(col("ffd27a")), 8, 5)

func window(k:Kit, xf:Transform3D, trim:Color, glass:Color, shutter:Color):
	k.box(xf * Kit.at(0, 0, 0.0), Vector3(1.05, 1.15, 0.16), trim, 0.05)
	k.box(xf * Kit.at(0, 0, 0.05), Vector3(0.8, 0.9, 0.1), glass, 0.03)
	k.box(xf * Kit.at(0, 0, 0.11), Vector3(0.06, 0.9, 0.04), trim, 0.01)
	k.box(xf * Kit.at(0, 0.05, 0.11), Vector3(0.8, 0.06, 0.04), trim, 0.01)
	for s in [-1, 1]:
		k.box(xf * Kit.at(s * 0.68, 0, 0.06), Vector3(0.3, 1.1, 0.07), shutter, 0.04)
		for i in 4: k.box(xf * Kit.at(s * 0.68, -0.38 + i * 0.25, 0.1), Vector3(0.26, 0.04, 0.02), shutter.darkened(0.15), 0.0)
	k.box(xf * Kit.at(0, -0.62, 0.14), Vector3(1.0, 0.2, 0.24), col("b77a4f"), 0.04)
	for i in 4:
		var fc:String = ["ff7f9e", "ffd166", "ffffff", "b48cff"][i % 4]
		k.sphere(xf * Kit.at(-0.33 + i * 0.22, -0.48, 0.15), Vector3(0.1, 0.09, 0.1), col(fc), 6, 4)

func house(rect:Rect2, face:Vector2, style:int):
	var c := rect.get_center()
	var k := K(c)
	var horizontal := absf(face.x) > 0.5
	var w := rect.size.y if horizontal else rect.size.x
	var d := rect.size.x if horizontal else rect.size.y
	var xf := Transform3D(Basis(Vector3.UP, yaw_for(face)), Vector3(c.x, 0, c.y))
	var seed := int(absf(c.x * 13 + c.y * 7))
	var wall := col(WALLS[(seed + style) % WALLS.size()])
	var roof := col(ROOFS[(seed / 3 + style) % ROOFS.size()])
	var trim := col("fffaf0")
	var shutter := col(DOORS[(seed + 1) % DOORS.size()]).lightened(0.15)
	var h := 2.4
	walls_with_windows(k, xf, w - 0.2, d - 0.2, h, wall, trim, shutter, true, col(DOORS[seed % DOORS.size()]))
	var rh := 1.5 + 0.2 * style
	k.gable(xf * Kit.rot(0, 0.3 + h, 0, PI * 0.5), d - 0.2, rh, w - 0.3, wall.lightened(0.05))
	k.roof(xf * Kit.rot(0, 0.3 + h, 0, PI * 0.5), d + 0.5, rh, w + 0.5, roof, 0.16, 0.06)
	k.box(xf * Kit.at(w * 0.28, 0.3 + h + rh * 0.75, -d * 0.12), Vector3(0.55, 1.3, 0.55), col("b9705e"), 0.05, 0.2)
	k.box(xf * Kit.at(w * 0.28, 0.3 + h + rh * 0.75 + 0.68, -d * 0.12), Vector3(0.68, 0.14, 0.68), col("8f564a"), 0.04)
	smoke.append(xf * Vector3(w * 0.28, 0.3 + h + rh * 0.75 + 0.8, -d * 0.12))
	# garden details in front of the house
	var gz := d * 0.5 + 1.1
	k.box(xf * Kit.at(-w * 0.32, 0.45, gz - 0.15), Vector3(0.14, 0.9, 0.14), col("7b5b44"), 0.03)
	k.box(xf * Kit.at(-w * 0.32, 0.95, gz - 0.15), Vector3(0.4, 0.3, 0.5), col(["e85d5d", "4f86c6", "5ab07a"][style % 3]), 0.1)
	for side in [-1, 1]:
		k.sphere(xf * Kit.at(side * (w * 0.5 - 0.3), 0.35, d * 0.5 + 0.35), Vector3(0.5, 0.42, 0.4), col(FOLIAGE[(seed + side + 3) % 3]), 10, 6, 0.3)
		k.sphere(xf * Kit.at(side * (w * 0.5 - 0.15), 0.62, d * 0.5 + 0.45), Vector3(0.12, 0.1, 0.12), col("ff9fb8"), 6, 4)

func build_base():
	var r:Rect2 = Map.BASE
	var c := r.get_center()
	var k := K(c)
	var xf := Transform3D(Basis(), Vector3(c.x, 0, c.y))
	var w := r.size.x - 0.1
	var d := r.size.y - 0.1
	var h := 3.4
	walls_with_windows(k, xf, w, d, h, col("ffd99a"), col("fffaf0"), col("e8665a"), true, col("3f6f9f"))
	k.gable(xf * Kit.rot(0, 0.3 + h, 0, PI * 0.5), d, 1.9, w - 0.1, col("ffe2b0"))
	k.roof(xf * Kit.rot(0, 0.3 + h, 0, PI * 0.5), d + 0.7, 1.9, w + 0.7, col("4c7fc0"), 0.18, 0.07)
	# rooftop lookout for the vigía survivors and a weather vane
	k.box(xf * Kit.at(0, 0.3 + h + 2.0, 0), Vector3(1.4, 0.15, 1.4), col("c98a55"), 0.04)
	for sx in [-1, 1]:
		for sz in [-1, 1]: k.cylinder(xf * Kit.at(sx * 0.6, 0.3 + h + 2.35, sz * 0.6), 0.05, 0.05, 0.6, col("8a5a3a"), 6)
	k.cylinder(xf * Kit.at(1.8, 0.3 + h + 1.4, -0.8), 0.04, 0.04, 2.2, col("3e4a5c"), 6)
	k.box(xf * Kit.at(1.8, 0.3 + h + 2.4, -0.8), Vector3(0.6, 0.35, 0.03), col("e8665a"), 0.0)
	# sign
	k.box(xf * Kit.at(0, 3.25, d * 0.5 + 0.12), Vector3(3.4, 0.7, 0.14), col("2f5168"), 0.08)
	k.box(xf * Kit.at(0, 3.25, d * 0.5 + 0.05), Vector3(3.6, 0.85, 0.08), col("f2c14e"), 0.06)
	label_at("LA VERBENA", Vector3(c.x, 3.25, c.y + d * 0.5 + 0.21), 0.0062, Color("fff2c9"), false)
	# bunting around the eaves
	for side in [-1.0, 1.0]:
		for i in 9:
			var x := -w * 0.5 + i * w / 8.0
			var fc:String = ["ff6b6b", "ffd166", "06d6a0", "4cc9f0", "f78fb3"][i % 5]
			k.box(xf * Kit.rot(x, 3.5 - 0.15 * sin(i * PI / 8.0), side * (d * 0.5 + 0.55), PI * 0.25, 0, 0), Vector3(0.22, 0.32, 0.02), col(fc), 0.0)
	# porch lanterns and steps
	for sx in [-1, 1]:
		k.cylinder(xf * Kit.at(sx * 2.1, 0.9, d * 0.5 + 1.2), 0.07, 0.07, 1.8, col("6b4f3c"), 6)
		k.sphere(xf * Kit.at(sx * 2.1, 1.95, d * 0.5 + 1.2), Vector3(0.28, 0.34, 0.28), Kit.glow(col("ffb35c")), 10, 6)
	# barrels and crates suggesting a fortified home
	k.cylinder(xf * Kit.at(-w * 0.5 - 0.5, 0.45, d * 0.5 - 0.4), 0.38, 0.38, 0.9, col("b8743f"), 12, true, 0.3)
	k.box(xf * Kit.at(w * 0.5 + 0.55, 0.35, d * 0.5 - 0.5), Vector3(0.7, 0.7, 0.7), col("d49a5c"), 0.06, 0.3)
	k.box(xf * Kit.at(w * 0.5 + 0.55, 0.95, d * 0.5 - 0.45), Vector3(0.5, 0.5, 0.5), col("e0b070"), 0.05, 0.3)
	# shop counter (tienda) beside the house
	var sx := Transform3D(Basis(), Vector3(4.6, 0, 3.6))
	k.box(sx * Kit.at(0, 0.55, 0), Vector3(1.8, 1.1, 0.8), col("e8665a"), 0.08, 0.3)
	k.box(sx * Kit.at(0, 1.13, 0), Vector3(2.0, 0.08, 1.0), col("fff2d6"), 0.03)
	for x in [-0.85, 0.85]: k.cylinder(sx * Kit.at(x, 1.65, -0.3), 0.04, 0.04, 1.1, col("6b4f3c"), 6)
	for i in 6:
		var stripe := col("fff2d6") if i % 2 == 0 else col("e8665a")
		k.box(sx * Kit.rot(-0.83 + i * 0.33, 2.2, 0.05, 0, 0.35), Vector3(0.33, 0.06, 1.3), stripe, 0.01)
	label_at("TIENDA", Vector3(4.6, 1.5, 3.25), 0.0045, Color("fff2c9"), true)
	# plaza bell: ringing it votes to bring the night forward
	var b:Vector2 = Map.BELL
	for side in [-0.45, 0.45]:
		k.box(Kit.rot(b.x + side, 1.3, b.y, 0, 0, -side * 0.12), Vector3(0.16, 2.6, 0.16), col("8b5e3c"), 0.04)
	k.box(Kit.at(b.x, 2.65, b.y), Vector3(1.3, 0.18, 0.5), col("c44b3b"), 0.06)
	k.box(Kit.rot(b.x - 0.33, 2.85, b.y, 0, 0, 0.5), Vector3(0.8, 0.08, 0.55), col("e8665a"), 0.03)
	k.box(Kit.rot(b.x + 0.33, 2.85, b.y, 0, 0, -0.5), Vector3(0.8, 0.08, 0.55), col("e8665a"), 0.03)
	k.cylinder(Kit.at(b.x, 2.22, b.y), 0.32, 0.16, 0.5, col("e0a63a"), 14, true, 0.2)
	k.sphere(Kit.at(b.x, 1.94, b.y), Vector3(0.07, 0.07, 0.07), col("8b5e3c"), 6, 4)
	k.box(Kit.at(b.x, 0.08, b.y), Vector3(1.4, 0.16, 0.8), col("cfc5b8"), 0.04)
	label_at("CAMPANA", Vector3(b.x, 3.25, b.y), 0.004, Color("fff2c9"), true)
	build_stage()

func build_stage():
	## Festival stage where the four pieces are installed to light the verbena.
	var c:Vector2 = Map.STAGE
	var k := K(c)
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(c.x, 0, c.y))
	k.box(xf * Kit.at(0, 0.3, 0), Vector3(6.0, 0.6, 2.6), col("b77a4f"), 0.08, 0.3)
	for i in 12: k.box(xf * Kit.at(-2.75 + i * 0.5, 0.62, 0), Vector3(0.46, 0.04, 2.5), col("c98a55") if i % 2 else col("b77a4f"), 0.0)
	for i in 3: k.box(xf * Kit.at(-0.9 + i * 0.9, 0.12, -1.55), Vector3(0.8, 0.24, 0.5), col("cfc5b8"), 0.04)
	for sx in [-1.0, 1.0]:
		k.box(xf * Kit.at(sx * 2.85, 2.2, 1.1), Vector3(0.28, 3.8, 0.28), col("e8665a"), 0.06)
	k.box(xf * Kit.at(0, 4.1, 1.1), Vector3(6.0, 0.4, 0.3), col("e8665a"), 0.08)
	for i in 15:
		var x := -2.8 + i * 0.4
		var colors := ["ff6b6b", "ffd166", "06d6a0", "4cc9f0", "f78fb3"]
		k.sphere(xf * Kit.at(x, 4.35, 1.1), Vector3(0.11, 0.11, 0.11), Kit.glow(col(colors[i % 5])), 6, 4)
	for side in [-1, 1]:
		for j in 6:
			var colors := ["ffd166", "ff6b6b", "4cc9f0"]
			k.sphere(xf * Kit.at(side * 2.85, 0.8 + j * 0.55, 1.28), Vector3(0.1, 0.1, 0.1), Kit.glow(col(colors[j % 3])), 6, 4)
	for i in 4:
		k.cylinder(xf * Kit.at(-2.1 + i * 1.4, 0.75, 0.2), 0.35, 0.4, 0.3, col("fff2d6"), 12, true, 0.2)
	label_at("ESCENARIO", xf * Vector3(0, 4.75, 1.1), 0.0055, Color("fff2c9"), true)
	var colors := [Color("ff6b8b"), Color("4cc9f0"), Color("ffd166"), Color("06d6a0")]
	for i in 4:
		var l := SpotLight3D.new()
		l.position = xf * Vector3(-2.4 + i * 1.6, 4.0, 0.6)
		l.rotation = Vector3(-1.0, 0, 0)
		l.light_color = colors[i]
		l.spot_range = 22.0
		l.spot_angle = 30.0
		l.light_energy = 0.0
		add_child(l)
		stage_lights.append(l)

func update_finale(on:bool, t:float, dt:float):
	finale_on = move_toward(finale_on, 1.0 if on else 0.0, dt * 0.8)
	for i in stage_lights.size():
		var l:SpotLight3D = stage_lights[i]
		l.light_energy = finale_on * 6.0
		l.rotation = Vector3(-0.7 - 0.3 * sin(t * 1.3 + i), PI * 0.5 + sin(t * 0.9 + i * 1.7) * 0.9, 0)

func build_sites():
	taller(Map.SITES[0])
	dispensario(Map.SITES[1])
	economato(Map.SITES[2])
	almacen(Map.SITES[3])
	gasolinera(Map.SITES[4])
	comisaria(Map.SITES[5])

func site_xf(s:Dictionary) -> Transform3D:
	var c:Vector2 = s.rect.get_center()
	return Transform3D(Basis(Vector3.UP, yaw_for(s.face)), Vector3(c.x, 0, c.y))

func site_dims(s:Dictionary) -> Vector2:
	var horizontal := absf(s.face.x) > 0.5
	return Vector2(s.rect.size.y if horizontal else s.rect.size.x, s.rect.size.x if horizontal else s.rect.size.y)

func sign_board(k:Kit, xf:Transform3D, text:String, at:Vector3, bg:Color, width:float):
	k.box(xf * Kit.at(at.x, at.y, at.z), Vector3(width, 0.8, 0.16), bg, 0.08)
	k.box(xf * Kit.at(at.x, at.y, at.z - 0.04), Vector3(width + 0.2, 0.95, 0.08), col("fffaf0"), 0.06)
	var wp := xf * Vector3(at.x, at.y, at.z + 0.1)
	label_at(text, wp, 0.0058, Color("fffaf0"), false, xf.basis)

func label_at(text:String, pos:Vector3, px:float, color:Color, billboard:bool, basis:Basis = Basis()):
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.outline_size = 14
	l.outline_modulate = Color(0.12, 0.1, 0.16, 0.9)
	l.modulate = color
	l.pixel_size = px
	l.position = pos
	l.basis = basis
	l.double_sided = false
	if billboard: l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)
	label_nodes.append(l)
	return l


func roof_sign(text:String, center:Vector2, top:float, width:float, bg:Color):
	## A billboard on the roof, tilted towards the camera so every property reads from above.
	var k := K(center)
	var xf := Transform3D(Basis(Vector3(1, 0, 0), -0.45), Vector3(center.x, top + 0.9, center.y))
	for sx in [-1, 1]: k.box(Kit.at(center.x + sx * width * 0.38, top + 0.45, center.y + 0.1), Vector3(0.12, 0.9, 0.12), col("5a5a68"), 0.03)
	k.box(xf * Kit.at(0, 0.35, 0), Vector3(width + 0.25, 1.15, 0.12), col("fffaf0"), 0.08)
	k.box(xf * Kit.at(0, 0.35, 0.05), Vector3(width, 0.95, 0.1), bg, 0.08)
	for i in int(width / 0.7):
		k.sphere(xf * Kit.at(-width * 0.5 + 0.35 + i * 0.7, 0.98, 0.08), Vector3(0.07, 0.07, 0.07), Kit.glow(col(["ffd166", "ffffff"][i % 2])), 6, 4)
	var l:Label3D = label_at(text, xf * Vector3(0, 0.35, 0.13), 0.0078, Color("fffaf0"), false, xf.basis)
	l.font_size = 96

func flat_roof(xf:Transform3D, w:float, d:float, top:float, trim:Color, seed:int):
	var k := K(Vector2(xf.origin.x, xf.origin.z))
	for side in [-1, 1]:
		k.box(xf * Kit.at(side * (w * 0.5 - 0.1), top + 0.18, 0), Vector3(0.24, 0.36, d), trim, 0.05)
		k.box(xf * Kit.at(0, top + 0.18, side * (d * 0.5 - 0.1)), Vector3(w, 0.36, 0.24), trim, 0.05)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = seed
	for i in 3:
		var p := Vector3(rng2.randf_range(-w * 0.35, w * 0.35), top, rng2.randf_range(-d * 0.3, d * 0.3))
		k.box(xf * Kit.at(p.x, top + 0.3, p.z), Vector3(0.9, 0.6, 0.7), col("c8ccd4"), 0.08, 0.25)
		k.cylinder(xf * Kit.at(p.x, top + 0.62, p.z), 0.25, 0.25, 0.04, col("8f97a8"), 12)
	for i in 2:
		k.box(xf * Kit.at(-w * 0.25 + i * w * 0.5, top + 0.08, d * 0.25), Vector3(1.2, 0.16, 0.8), Kit.glow(col("bfe2ff"), 0.6), 0.04)

func roof_cross(center:Vector2, top:float, c:Color, size:float):
	var k := K(center)
	k.cylinder(Kit.at(center.x, top + 0.03, center.y), size, size, 0.05, col("fffaf0"), 24)
	k.box(Kit.at(center.x, top + 0.07, center.y), Vector3(size * 1.2, 0.04, size * 0.4), c, 0.0)
	k.box(Kit.at(center.x, top + 0.07, center.y), Vector3(size * 0.4, 0.04, size * 1.2), c, 0.0)

func taller(s:Dictionary):
	var k := K(s.rect.get_center())
	var xf := site_xf(s)
	var dm := site_dims(s)
	var w := dm.x - 0.2
	var d := dm.y - 0.2
	k.box(xf * Kit.at(0, 1.6, 0), Vector3(w, 3.2, d), col("e7b07a"), 0.1, 0.25)
	k.box(xf * Kit.at(0, 3.3, 0), Vector3(w + 0.4, 0.3, d + 0.4), col("8b5e3c"), 0.06)
	for i in 3:
		var z := -d * 0.33 + i * d * 0.33
		k.cylinder(xf * Kit.rot(0, 3.45, z, 0, 0, PI * 0.5), 0.9, 0.9, w + 0.2, col("c46a45"), 10, true)
	k.box(xf * Kit.at(0, 1.35, d * 0.5 + 0.02), Vector3(w * 0.55, 2.5, 0.12), col("6b7384"), 0.04)
	for i in 8: k.box(xf * Kit.at(0, 0.3 + i * 0.3, d * 0.5 + 0.1), Vector3(w * 0.53, 0.06, 0.04), col("8f97a8"), 0.0)
	for i in 6:
		var stripe := col("ffd166") if i % 2 == 0 else col("2b2d42")
		k.box(xf * Kit.rot(-w * 0.27 + i * w * 0.11, 2.75, d * 0.5 + 0.1, 0, 0, 0.6), Vector3(0.35, 0.15, 0.05), stripe, 0.0)
	sign_board(k, xf, "TALLER", Vector3(0, 3.0, d * 0.5 + 0.25), col("c44b3b"), 2.6)
	for i in 4: k.cylinder(xf * Kit.at(w * 0.5 + 0.7, 0.15 + i * 0.3, d * 0.3), 0.42, 0.42, 0.28, col("2f2f38"), 12)
	for i in 3: k.cylinder(xf * Kit.at(-w * 0.5 - 0.6, 0.5, -d * 0.3 + i * 0.85), 0.35, 0.35, 1.0, col(["4f86c6", "e85d5d", "5ab07a"][i]), 12, true, 0.3)
	for i in 2: window(k, xf * Kit.at(w * 0.36 * (1 if i else -1), 1.9, d * 0.5), col("fffaf0"), Kit.glow(col("bfe2ff")), col("8b5e3c"))
	for i in 3: window(k, xf * Kit.rot(-w * 0.3 + i * w * 0.3, 1.9, -d * 0.5, PI), col("fffaf0"), Kit.glow(col("bfe2ff")), col("8b5e3c"))
	roof_sign("TALLER", s.rect.get_center() + Vector2(0, 1.2), 4.3, 3.0, col("c44b3b"))

func dispensario(s:Dictionary):
	var k := K(s.rect.get_center())
	var xf := site_xf(s)
	var dm := site_dims(s)
	var w := dm.x - 0.2
	var d := dm.y - 0.2
	walls_with_windows(k, xf, w, d, 3.6, col("f4fbf8"), col("7cd0c0"), col("7cd0c0"), true, col("5aa89a"))
	k.box(xf * Kit.at(0, 4.05, 0), Vector3(w + 0.3, 0.35, d + 0.3), col("7cd0c0"), 0.08)
	k.box(xf * Kit.at(0, 4.6, 0), Vector3(1.0, 0.8, 0.2), col("ffffff"), 0.06)
	k.box(xf * Kit.at(0, 4.6, 0.12), Vector3(0.7, 0.2, 0.06), Kit.glow(col("e85d5d"), 0.6), 0.02)
	k.box(xf * Kit.at(0, 4.6, 0.12), Vector3(0.2, 0.7, 0.06), Kit.glow(col("e85d5d"), 0.6), 0.02)
	sign_board(k, xf, "DISPENSARIO", Vector3(0, 3.3, d * 0.5 + 0.3), col("5aa89a"), 3.6)
	flat_roof(xf, w + 0.3, d + 0.3, 4.22, col("5aa89a"), 3)
	roof_cross(s.rect.get_center() + Vector2(-1.5, -0.8), 4.22, col("e8463c"), 1.4)
	roof_sign("DISPENSARIO", s.rect.get_center() + Vector2(1.0, 2.2), 4.22, 4.2, col("5aa89a"))
	var amb := xf * Kit.at(w * 0.5 + 1.8, 0, d * 0.5 - 1.2)
	car(k, amb, col("fafafa"), col("e85d5d"))

func economato(s:Dictionary):
	var k := K(s.rect.get_center())
	var xf := site_xf(s)
	var dm := site_dims(s)
	var w := dm.x - 0.2
	var d := dm.y - 0.2
	k.box(xf * Kit.at(0, 1.8, 0), Vector3(w, 3.6, d), col("fff0c4"), 0.1, 0.22)
	k.box(xf * Kit.at(0, 1.4, d * 0.5 + 0.02), Vector3(w - 1.2, 2.3, 0.12), Kit.glow(col("cdeeff"), 1.0), 0.04)
	for i in 7: k.box(xf * Kit.at(-w * 0.5 + 0.6 + i * (w - 1.2) / 6.0, 1.4, d * 0.5 + 0.1), Vector3(0.1, 2.3, 0.08), col("fffaf0"), 0.02)
	for i in 10:
		var stripe := col("e85d5d") if i % 2 == 0 else col("fffaf0")
		k.box(xf * Kit.rot(-w * 0.45 + i * w * 0.1, 2.85, d * 0.5 + 0.6, 0, 0.4), Vector3(w * 0.1, 0.07, 1.4), stripe, 0.02)
	k.box(xf * Kit.at(0, 3.75, 0), Vector3(w + 0.3, 0.3, d + 0.3), col("f2c14e"), 0.06)
	sign_board(k, xf, "ECONOMATO", Vector3(0, 4.3, d * 0.5 - 0.2), col("e85d5d"), 4.2)
	flat_roof(xf, w + 0.3, d + 0.3, 3.9, col("e85d5d"), 5)
	for i in 6: k.box(xf * Kit.at(-w * 0.42 + i * w * 0.168, 1.5, -d * 0.5 - 0.03), Vector3(w * 0.12, 1.6, 0.08), Kit.glow(col("cdeeff"), 0.8), 0.04)
	roof_sign("ECONOMATO", s.rect.get_center() + Vector2(0, 1.6), 3.9, 5.2, col("e85d5d"))
	for i in 3:
		var cx := w * 0.5 + 0.8
		var cxf := xf * Kit.rot(cx, 0, d * 0.5 - 0.6 - i * 0.7, PI * 0.5)
		k.box(cxf * Kit.at(0, 0.6, 0), Vector3(0.7, 0.45, 0.5), col("b8c0cc"), 0.03)
		for wx in [-0.25, 0.25]:
			for wz in [-0.2, 0.2]: k.sphere(cxf * Kit.at(wx, 0.1, wz), Vector3(0.07, 0.07, 0.07), col("2f2f38"), 6, 4)

func almacen(s:Dictionary):
	var k := K(s.rect.get_center())
	var xf := site_xf(s)
	var dm := site_dims(s)
	var w := dm.x - 0.2
	var d := dm.y - 0.2
	k.box(xf * Kit.at(0, 1.9, 0), Vector3(w, 3.8, d), col("b9c4cf"), 0.08, 0.25)
	for i in int(w * 2.5): k.box(xf * Kit.at(-w * 0.5 + 0.2 + i * 0.4, 1.9, d * 0.5 + 0.03), Vector3(0.08, 3.7, 0.06), col("a3afbb"), 0.0)
	k.roof(xf * Kit.rot(0, 3.8, 0, PI * 0.5), d + 0.4, 1.0, w + 0.4, col("6d8aa6"), 0.14, 0.04)
	k.gable(xf * Kit.rot(0, 3.8, 0, PI * 0.5), d, 1.0, w - 0.1, col("b9c4cf"))
	k.box(xf * Kit.at(0, 1.5, d * 0.5 + 0.05), Vector3(3.4, 3.0, 0.1), col("e39a4c"), 0.04)
	for i in 10: k.box(xf * Kit.at(0, 0.2 + i * 0.3, d * 0.5 + 0.11), Vector3(3.3, 0.05, 0.03), col("c47f38"), 0.0)
	sign_board(k, xf, "ALMACÉN", Vector3(0, 3.4, d * 0.5 + 0.2), col("8b5e3c"), 3.0)
	for i in 4: k.box(xf * Kit.rot(-w * 0.3 + i * w * 0.2, 4.15, d * 0.2, 0, -0.42), Vector3(0.9, 0.1, 1.3), Kit.glow(col("bfe2ff"), 0.5), 0.03)
	for i in 3: k.box(xf * Kit.rot(-w * 0.25 + i * w * 0.25, 4.15, -d * 0.2, 0, 0.42), Vector3(0.9, 0.1, 1.3), Kit.glow(col("bfe2ff"), 0.5), 0.03)
	roof_sign("ALMACÉN", s.rect.get_center() + Vector2(0, 0.6), 4.6, 3.6, col("8b5e3c"))
	for i in 5:
		var px := -w * 0.5 + 0.8 + (i % 3) * 1.0
		var pz := d * 0.5 + 1.2 + (i / 3) * 1.0
		k.box(xf * Kit.at(px + w * 0.6, 0.4, pz - d * 0.6), Vector3(0.85, 0.8, 0.85), col("d49a5c"), 0.05, 0.3)

func gasolinera(s:Dictionary):
	var k := K(s.rect.get_center())
	var xf := site_xf(s)
	var dm := site_dims(s)
	var w := dm.x - 0.2
	var d := dm.y - 0.2
	walls_with_windows(k, xf, w, d, 2.6, col("fff6ea"), col("e86a5c"), col("e86a5c"), true, col("e86a5c"))
	k.box(xf * Kit.at(0, 3.05, 0), Vector3(w + 0.3, 0.3, d + 0.3), col("e86a5c"), 0.06)
	sign_board(k, xf, "GASOLINERA", Vector3(0, 2.45, d * 0.5 + 0.35), col("e86a5c"), 3.3)
	flat_roof(xf, w + 0.3, d + 0.3, 3.2, col("e86a5c"), 9)
	var cxf := Transform3D(Basis(), Vector3(-23.0, 0, -0.5))
	for px in [-3.0, 3.0]:
		for pz in [-3.0, 3.0]:
			K(Vector2(-23, 0)).cylinder(cxf * Kit.at(px, 1.8, pz), 0.16, 0.16, 3.6, col("fffaf0"), 10)
	K(Vector2(-23, 0)).box(cxf * Kit.at(0, 3.75, 0), Vector3(8.0, 0.4, 8.0), col("fffaf0"), 0.1)
	K(Vector2(-23, 0)).box(cxf * Kit.at(0, 3.7, 0), Vector3(8.15, 0.25, 8.15), col("e86a5c"), 0.08)
	for i in 4: K(Vector2(-23, 0)).box(cxf * Kit.at(0, 3.97, -3.0 + i * 2.0), Vector3(7.6, 0.03, 0.5), col("ffd166") if i % 2 == 0 else col("e86a5c"), 0.0)
	roof_sign("GASOLINERA", Vector2(-23, 2.0), 3.95, 4.6, col("e86a5c"))
	for i in 4: K(Vector2(-23, 0)).box(cxf * Kit.at(-2.6 + i * 1.75, 3.53, 0), Vector3(0.9, 0.04, 6.5), Kit.glow(col("fff2d0"), 0.9), 0.0)
	for p in Map.PROPS:
		if p.kind != "pump": continue
		var c:Vector2 = p.rect.get_center()
		var kk := K(c)
		kk.box(Kit.at(c.x, 0.1, c.y), Vector3(1.0, 0.2, 1.0), col("cfd4db"), 0.04)
		kk.box(Kit.at(c.x, 0.85, c.y), Vector3(0.6, 1.3, 0.45), col("e86a5c"), 0.08, 0.25)
		kk.box(Kit.at(c.x, 1.15, c.y + 0.23), Vector3(0.42, 0.3, 0.04), Kit.glow(col("b8f0ff"), 0.8), 0.02)
		kk.cylinder(Kit.rot(c.x + 0.36, 0.9, c.y, 0, 0, 0.3), 0.04, 0.04, 0.7, col("2f2f38"), 6)
	var pole := Vector2(-18.5, -6.5)
	K(pole).cylinder(Kit.at(pole.x, 2.5, pole.y), 0.12, 0.12, 5.0, col("8f97a8"), 8)
	K(pole).box(Kit.at(pole.x, 5.2, pole.y), Vector3(1.6, 1.4, 0.25), col("e86a5c"), 0.1)
	K(pole).box(Kit.at(pole.x, 5.2, pole.y + 0.1), Vector3(1.3, 1.1, 0.1), Kit.glow(col("ffe6a8"), 0.6), 0.04)

func comisaria(s:Dictionary):
	var k := K(s.rect.get_center())
	var xf := site_xf(s)
	var dm := site_dims(s)
	var w := dm.x - 0.2
	var d := dm.y - 0.2
	walls_with_windows(k, xf, w, d, 3.6, col("dbe4f6"), col("ffffff"), col("4f6fb8"), true, col("2f4f88"))
	k.box(xf * Kit.at(0, 4.05, 0), Vector3(w + 0.3, 0.35, d + 0.3), col("4f6fb8"), 0.08)
	sign_board(k, xf, "COMISARÍA", Vector3(0, 3.35, d * 0.5 + 0.3), col("2f4f88"), 3.4)
	flat_roof(xf, w + 0.3, d + 0.3, 4.22, col("4f6fb8"), 13)
	var star:Vector2 = s.rect.get_center() + Vector2(1.5, -1.0)
	k.cylinder(Kit.at(star.x, 4.25, star.y), 1.3, 1.3, 0.05, col("f2c14e"), 5)
	k.cylinder(Kit.rot(star.x, 4.26, star.y, PI / 5.0), 1.3, 1.3, 0.05, col("f2c14e"), 5)
	roof_sign("COMISARÍA", s.rect.get_center() + Vector2(-0.5, 2.2), 4.22, 4.0, col("2f4f88"))
	k.box(xf * Kit.at(-0.4, 4.5, 0), Vector3(0.5, 0.35, 0.5), Kit.glow(col("ff5a5a"), 0.8), 0.12)
	k.box(xf * Kit.at(0.4, 4.5, 0), Vector3(0.5, 0.35, 0.5), Kit.glow(col("5a8aff"), 0.8), 0.12)
	k.cylinder(xf * Kit.at(w * 0.5 + 1.0, 2.5, d * 0.5 + 0.5), 0.06, 0.06, 5.0, col("dddddd"), 6)
	k.box(xf * Kit.at(w * 0.5 + 1.45, 4.5, d * 0.5 + 0.5), Vector3(0.9, 0.6, 0.03), col("f2c14e"), 0.0)
	car(k, xf * Kit.rot(-w * 0.5 - 1.8, 0, d * 0.5 - 1.0, PI * 0.5), col("fafafa"), col("2f4f88"))

func car(k:Kit, xf:Transform3D, body:Color, accent:Color):
	k.box(xf * Kit.at(0, 0.55, 0), Vector3(1.7, 0.6, 3.2), body, 0.22, 0.25, 1)
	k.box(xf * Kit.at(0, 1.05, -0.15), Vector3(1.45, 0.55, 1.7), body, 0.2, 0.0, 1)
	k.box(xf * Kit.at(0, 1.07, -0.15), Vector3(1.5, 0.38, 1.5), col("8fc3e8"), 0.12)
	k.box(xf * Kit.at(0, 0.6, 0), Vector3(1.74, 0.14, 3.0), accent, 0.05)
	for x in [-0.82, 0.82]:
		for z in [-1.0, 1.0]:
			k.cylinder(xf * Kit.rot(x, 0.32, z, 0, 0, PI * 0.5), 0.32, 0.32, 0.26, col("2f2f38"), 12)
			k.cylinder(xf * Kit.rot(x * 1.04, 0.32, z, 0, 0, PI * 0.5), 0.16, 0.16, 0.27, col("c8ccd4"), 8)
	for x in [-0.55, 0.55]: k.sphere(xf * Kit.at(x, 0.65, 1.6), Vector3(0.14, 0.12, 0.06), Kit.glow(col("fff2c0"), 0.5), 8, 4)

func build_park():
	var k := K(Vector2(0, -22))
	ground_plane(Rect2(-1.2, -31, 2.4, 17), 3, "d9b98a", "c9a574", "b08e62", 0.01)
	ground_plane(Rect2(-11.5, -22.7, 23, 2.4), 3, "d9b98a", "c9a574", "b08e62", 0.012)
	# fountain
	var f := Vector3(0, 0, -23)
	k.cylinder(Kit.at(f.x, 0.3, f.z), 2.0, 2.1, 0.6, col("d9d2c5"), 24, true, 0.2)
	k.cylinder(Kit.at(f.x, 0.62, f.z), 1.95, 1.95, 0.08, col("c9c0b0"), 24)
	k.cylinder(Kit.at(f.x, 1.0, f.z), 0.35, 0.45, 1.2, col("d9d2c5"), 12)
	k.cylinder(Kit.at(f.x, 1.65, f.z), 0.9, 0.6, 0.25, col("d9d2c5"), 16)
	k.sphere(Kit.at(f.x, 2.1, f.z), Vector3(0.35, 0.45, 0.35), col("f2c14e"), 12, 8)
	var water := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.85
	cm.bottom_radius = 1.85
	cm.height = 0.05
	cm.radial_segments = 32
	water.mesh = cm
	var wm := ShaderMaterial.new()
	wm.shader = load("res://game/shaders/water.gdshader")
	water.material_override = wm
	water.position = f + Vector3(0, 0.52, 0)
	add_child(water)
	# kiosk / bandstand
	var kp := Vector3(7.5, 0, -20.5)
	k.cylinder(Kit.at(kp.x, 0.2, kp.z), 1.8, 1.9, 0.4, col("e9dcc6"), 8, true, 0.2)
	for i in 8:
		var a := TAU * i / 8.0
		k.cylinder(Kit.at(kp.x + cos(a) * 1.5, 1.5, kp.z + sin(a) * 1.5), 0.08, 0.08, 2.2, col("fffaf0"), 6)
	k.cylinder(Kit.at(kp.x, 2.8, kp.z), 0.2, 2.1, 0.9, col("e8665a"), 8, true)
	k.sphere(Kit.at(kp.x, 3.35, kp.z), Vector3(0.18, 0.18, 0.18), col("f2c14e"), 8, 6)
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		k.sphere(Kit.at(kp.x + cos(a) * 1.9, 2.25, kp.z + sin(a) * 1.9), Vector3(0.14, 0.18, 0.14), Kit.glow(col(["ff6b6b", "ffd166", "4cc9f0"][i % 3])), 8, 5)
	# playground
	var pg := Vector3(-7.5, 0, -25.5)
	for x in [-1.0, 1.0]:
		k.cylinder(Kit.rot(pg.x + x, 1.1, pg.z - 0.6, 0, 0.25), 0.07, 0.07, 2.3, col("e85d5d"), 6)
		k.cylinder(Kit.rot(pg.x + x, 1.1, pg.z + 0.6, 0, -0.25), 0.07, 0.07, 2.3, col("e85d5d"), 6)
	k.cylinder(Kit.rot(pg.x, 2.15, pg.z, 0, 0, PI * 0.5), 0.07, 0.07, 2.3, col("4f86c6"), 6)
	for x in [-0.45, 0.45]:
		k.box(Kit.at(pg.x + x, 0.55, pg.z), Vector3(0.5, 0.06, 0.25), col("ffd166"), 0.02)
		k.cylinder(Kit.at(pg.x + x, 1.35, pg.z), 0.015, 0.015, 1.6, col("777777"), 4)
	var sl := Vector3(-4.5, 0, -28.5)
	k.box(Kit.at(sl.x - 0.9, 0.8, sl.z), Vector3(0.9, 1.6, 0.9), col("5ab07a"), 0.08)
	k.box(Kit.rot(sl.x + 0.4, 0.8, sl.z, PI * 0.5, 0, -0.55), Vector3(0.7, 0.08, 2.4), col("ffd166"), 0.03)
	for b in [[Vector2(-3.5, -18.5), PI * 0.5], [Vector2(3.5, -18.5), -PI * 0.5], [Vector2(-3.5, -27.5), PI * 0.5]]:
		bench(k, b[0], b[1])
	for i in 14:
		var a := i * 0.45
		var p := Vector2(cos(a) * 3.2, -23 + sin(a) * 3.2)
		if absf(p.x) < 1.4 or absf(p.y + 21.5) < 1.4: continue
		k.sphere(Kit.at(p.x, 0.3, p.y), Vector3(0.35, 0.3, 0.35), col("5fae5e"), 8, 5, 0.3)
		k.sphere(Kit.at(p.x, 0.55, p.y), Vector3(0.13, 0.1, 0.13), col(["ff8fa3", "ffd166", "c59dff"][i % 3]), 6, 4)

func build_parking():
	for i in 9:
		var x := -9.0 + i * 2.25
		K(Vector2(x, 17)).box(Kit.at(x, 0.03, 17.5), Vector3(0.12, 0.02, 4.2), col("f6eed6"), 0.0)
	var colors := ["ef8f8f", "8fc3ef", "f2d27a", "9fe0b0", "c9a8f0"]
	var spots := [-7.9, -3.4, 3.4, 7.9]
	for i in spots.size():
		car(K(Vector2(spots[i], 17)), Kit.rot(spots[i], 0, 17.4, 0.04 * (i - 1.5)), col(colors[i]), col(colors[(i + 2) % 5]).darkened(0.2))

func build_props():
	# loot containers are drawn by the dynamic layer; here only static clutter
	for p in [Vector2(-14.5, 4.5), Vector2(14.5, -20.5), Vector2(-14.5, 24.5), Vector2(27.5, 12.5), Vector2(-27.5, -12.5), Vector2(-8.5, -12.5), Vector2(6.5, 12.5)]:
		pass
	# hydrants and mailboxes along the sidewalks
	for p in [Vector2(-11.3, -10.6), Vector2(11.3, 10.6), Vector2(16.6, -16.0), Vector2(-16.6, 16.0), Vector2(11.3, -14.0), Vector2(-11.3, 14.0)]:
		var k := K(p)
		k.cylinder(Kit.at(p.x, 0.35, p.y), 0.16, 0.18, 0.7, col("e8463c"), 10, true, 0.3)
		k.sphere(Kit.at(p.x, 0.72, p.y), Vector3(0.16, 0.12, 0.16), col("e8463c"), 8, 4)
		k.cylinder(Kit.rot(p.x, 0.45, p.y, 0, 0, PI * 0.5), 0.07, 0.07, 0.48, col("c8c8c8"), 6)

func build_border():
	# Hedges and picket fences beyond the walkable area frame the neighbourhood.
	var bb:Rect2 = Map.BOUNDS
	for side in 4:
		var length := bb.size.x if side % 2 == 0 else bb.size.y
		for i in range(0, int(length) + 2, 2):
			var p: Vector2
			match side:
				0: p = Vector2(bb.position.x + i, bb.position.y - 1.0)
				1: p = Vector2(bb.end.x + 1.0, bb.position.y + i)
				2: p = Vector2(bb.position.x + i, bb.end.y + 1.0)
				_: p = Vector2(bb.position.x - 1.0, bb.position.y + i)
			var near_road := false
			for z in Map.ROADS_H: if absf(p.y - z) < 3.0: near_road = true
			for x in Map.ROADS_V: if absf(p.x - x) < 3.0: near_road = true
			if near_road: continue
			var k := K(p)
			k.sphere(Kit.at(p.x, 0.55, p.y), Vector3(1.25, 0.75, 1.25), col(FOLIAGE[(i / 2 + side) % 3]).darkened(0.08), 10, 6, 0.35)
	# road barriers where the streets leave the map
	for front in Map.FRONTS:
		for p in front:
			var k := K(p)
			var horizontal := absf(p.x) > absf(p.y)
			var xf := Kit.rot(p.x * 1.04, 0, p.y * 1.04, PI * 0.5 if horizontal else 0.0)
			for off in [-1.4, 1.4]:
				k.box(xf * Kit.at(off, 0.45, 0), Vector3(0.12, 0.9, 0.12), col("fafafa"), 0.03)
			for i in 5:
				k.box(xf * Kit.at(-1.2 + i * 0.6, 0.75, 0), Vector3(0.5, 0.25, 0.08), col("e8463c") if i % 2 == 0 else col("fafafa"), 0.02)

# ================================================================== festival
func string_lights(a:Vector3, b:Vector3, sag:float, count:int):
	var k := K(Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5))
	var colors := ["ff6b6b", "ffd166", "06d6a0", "4cc9f0", "f78fb3", "ffffff"]
	for i in count + 1:
		var t := float(i) / count
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		if i < count:
			var q := a.lerp(b, (i + 1.0) / count) - Vector3(0, sag * 4.0 * ((i + 1.0) / count) * (1.0 - (i + 1.0) / count), 0)
			var mid := (p + q) * 0.5
			var len := p.distance_to(q)
			var xf := Transform3D(Basis.looking_at((q - p).normalized(), Vector3.UP), mid)
			k.box(xf, Vector3(0.025, 0.025, len), col("3b3b48"), 0.0)
		k.sphere(Kit.at(p.x, p.y - 0.12, p.z), Vector3(0.1, 0.13, 0.1), Kit.glow(col(colors[i % colors.size()])), 6, 4)

func pole(p:Vector2, h:float):
	var k := K(p)
	k.cylinder(Kit.at(p.x, h * 0.5, p.y), 0.09, 0.11, h, col("7b5b44"), 8)
	k.sphere(Kit.at(p.x, h + 0.05, p.y), Vector3(0.14, 0.14, 0.14), col("f2c14e"), 8, 4)

func build_festival():
	var corners := [Vector2(-10.5, -8.5), Vector2(10.5, -8.5), Vector2(10.5, 8.5), Vector2(-10.5, 8.5)]
	for c in corners: pole(c, 4.6)
	for i in 4:
		var a:Vector2 = corners[i]
		var b:Vector2 = corners[(i + 1) % 4]
		string_lights(Vector3(a.x, 4.5, a.y), Vector3(b.x, 4.5, b.y), 0.8, 18)
	# garlands across the streets near the plaza
	for x in Map.ROADS_V:
		for z in [-6.0, 6.0]:
			pole(Vector2(x - 2.9, z), 4.2)
			pole(Vector2(x + 2.9, z), 4.2)
			string_lights(Vector3(x - 2.9, 4.1, z), Vector3(x + 2.9, 4.1, z), 0.6, 9)
	for z in Map.ROADS_H:
		for x in [-6.0, 6.0]:
			pole(Vector2(x, z - 2.9), 4.2)
			pole(Vector2(x, z + 2.9), 4.2)
			string_lights(Vector3(x, 4.1, z - 2.9), Vector3(x, 4.1, z + 2.9), 0.6, 9)
	# papel picado bunting: swaying pennants in a MultiMesh
	var pk := Kit.new()
	pk.gable(Transform3D(Basis(Vector3(0, 0, 1), PI), Vector3(0, 0, 0)), 0.34, 0.42, 0.02, Color.WHITE)
	pk.gable(Transform3D(Basis(Vector3(0, 0, 1), PI).rotated(Vector3.UP, PI), Vector3(0, 0, 0)), 0.34, 0.42, 0.02, Color.WHITE)
	var spots := []
	for i in 4:
		var a:Vector2 = corners[i]
		var b:Vector2 = corners[(i + 1) % 4]
		for j in 22:
			var t := (j + 0.5) / 22.0
			var p := a.lerp(b, t)
			spots.append([Vector3(p.x, 3.95 - 0.7 * 4.0 * t * (1.0 - t), p.y), atan2(b.x - a.x, b.y - a.y) + PI * 0.5])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = pk.commit()
	mm.instance_count = spots.size()
	var colors := ["ff6b6b", "ffd166", "06d6a0", "4cc9f0", "f78fb3", "c59dff"]
	for i in spots.size():
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, spots[i][1]), spots[i][0]))
		mm.set_instance_color(i, Color(colors[i % colors.size()]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = sway
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

# ================================================================== vegetation
func tree_mesh(variant:int) -> ArrayMesh:
	var k := Kit.new()
	var trunk := col("9a6a48")
	match variant:
		0, 1, 3:
			k.cylinder(Kit.at(0, 0.9, 0), 0.22, 0.16, 1.8, trunk, 8, false, 0.3)
			var fc := Color.WHITE
			k.sphere(Kit.at(0, 2.5, 0), Vector3(1.35, 1.15, 1.35), fc, 11, 7, 0.38)
			k.sphere(Kit.at(0.55, 2.95, 0.3), Vector3(0.85, 0.75, 0.85), fc.lightened(0.1), 9, 6, 0.3)
			k.sphere(Kit.at(-0.6, 2.75, -0.25), Vector3(0.8, 0.7, 0.8), fc, 9, 6, 0.32)
			k.sphere(Kit.at(0.1, 3.4, -0.1), Vector3(0.65, 0.55, 0.65), fc.lightened(0.15), 8, 5, 0.25)
			if variant == 3:
				for i in 7:
					var a := i * 2.4
					k.sphere(Kit.at(cos(a) * 1.0, 2.4 + sin(i * 1.7) * 0.6, sin(a) * 1.0), Vector3(0.16, 0.16, 0.16), col("e8463c"), 6, 4)
		2:
			k.cylinder(Kit.at(0, 0.6, 0), 0.2, 0.15, 1.2, trunk, 8, false, 0.3)
			for i in 3:
				k.cylinder(Kit.at(0, 1.5 + i * 0.85, 0), 1.35 - i * 0.35, 0.15, 1.4 - i * 0.15, Color.WHITE.darkened(0.05 * i), 12, true, 0.35)
		4:
			k.cylinder(Kit.at(0, 1.2, 0), 0.18, 0.12, 2.4, trunk, 8, false, 0.3)
			k.sphere(Kit.at(0, 2.9, 0), Vector3(1.0, 0.85, 1.0), Color.WHITE, 12, 8, 0.3)
	return k.commit()

func build_trees():
	var groups := {}
	var add := func(p:Vector2, variant:int, color:Color, s:float):
		if not groups.has(variant): groups[variant] = []
		groups[variant].append([p, color, s])
	for t in Map.TREES:
		var v := int(absf(t.x * 3 + t.y)) % 5
		add.call(t, v if v != 2 else 2, tree_color(v, t), 1.0 + fmod(absf(t.x * 7.3 + t.y), 0.3))
	# forest beyond the borders
	var bb:Rect2 = Map.BOUNDS
	for i in 260:
		var p := Vector2(rng.randf_range(-62, 62), rng.randf_range(-56, 56))
		if bb.grow(1.5).has_point(p): continue
		var road := false
		for z in Map.ROADS_H: if absf(p.y - z) < 3.2 and absf(p.x) > 30: road = true
		for x in Map.ROADS_V: if absf(p.x - x) < 3.2 and absf(p.y) > 26: road = true
		if road: continue
		var v := rng.randi_range(0, 4)
		add.call(p, v, tree_color(v, p), rng.randf_range(0.95, 1.5))
	# bushes within the neighbourhood (decorative, low)
	var bush := Kit.new()
	bush.sphere(Kit.at(0, 0.35, 0), Vector3(0.6, 0.5, 0.6), Color.WHITE, 8, 5, 0.35)
	bush.sphere(Kit.at(0.35, 0.5, 0.1), Vector3(0.4, 0.35, 0.4), Color.WHITE.lightened(0.1), 7, 4, 0.3)
	var bush_list := []
	for i in 160:
		var p := Vector2(rng.randf_range(-34, 34), rng.randf_range(-30, 30))
		if not is_open_grass(p): continue
		bush_list.append([p, col(FOLIAGE[rng.randi_range(0, 2)]).darkened(rng.randf_range(0.0, 0.12)), rng.randf_range(0.7, 1.2)])
	for variant in groups: spawn_mm(tree_mesh(variant), groups[variant], foliage, true)
	spawn_mm(bush.commit(), bush_list, foliage, true)

func tree_color(v:int, p:Vector2) -> Color:
	var h := fmod(absf(p.x * 1.7 + p.y * 2.3), 1.0)
	match v:
		3: return col("6cc05a").lerp(col("8fd16a"), h)
		4: return col("f4a9c4").lerp(col("ffc4d8"), h)
		2: return col("3f9a6a").lerp(col("52aa5c"), h)
		1: return col("f2c54a").lerp(col("ec9a4a"), h) if h > 0.75 else col("8fd16a")
	return col("6cc05a").lerp(col("52aa5c"), h)

func spawn_mm(mesh:Mesh, list:Array, mat:Material, shadows:bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		var item:Array = list[i]
		var p:Vector2 = item[0]
		var s:float = item[2]
		var b := Basis(Vector3.UP, fmod(p.x * 12.9 + p.y * 7.7, TAU)).scaled(Vector3(s, s * rng.randf_range(0.9, 1.1), s))
		mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, 0, p.y)))
		mm.set_instance_color(i, item[1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi

func build_grass():
	var tuft := Kit.new()
	for i in 5:
		var a := i * TAU / 5.0 + 0.3
		var xf := Transform3D(Basis(Vector3.UP, a) * Basis(Vector3(1, 0, 0), 0.3 * (1 if i % 2 else -1)), Vector3(cos(a) * 0.04, 0, sin(a) * 0.04))
		tuft.blade(xf, 0.09, 0.3 + 0.08 * (i % 3), Color(0.55, 0.55, 0.55), Color.WHITE)
	var flower := Kit.new()
	flower.blade(Kit.at(0, 0, 0), 0.03, 0.3, col("4f8a46"), col("6aa85a"))
	flower.blade(Kit.rot(0, 0, 0, PI * 0.5), 0.03, 0.3, col("4f8a46"), col("6aa85a"))
	flower.disc(Kit.at(0, 0.3, 0), 0.085, 6, Color.WHITE, col("ffd166"))
	var tufts := []
	var flowers := []
	var grng := RandomNumberGenerator.new()
	grng.seed = 11
	for i in 9000:
		var p := Vector2(grng.randf_range(-44, 44), grng.randf_range(-40, 40))
		if not is_open_grass(p): continue
		var g := col("6fbf5f").lerp(col("a6d96a"), grng.randf())
		tufts.append([p, g, grng.randf_range(0.7, 1.4)])
		if grng.randf() < 0.12:
			flowers.append([p + Vector2(grng.randf_range(-0.4, 0.4), grng.randf_range(-0.4, 0.4)), col(["ffffff", "ff9fb8", "ffd166", "c59dff", "8fd3ff"][grng.randi_range(0, 4)]), grng.randf_range(0.8, 1.3)])
	var gm := ShaderMaterial.new()
	gm.shader = toon.shader
	gm.set_shader_parameter("wind_amp", 0.6)
	gm.set_shader_parameter("rim_strength", 0.1)
	grass_mm = spawn_mm(tuft.commit(), tufts, gm, false)
	spawn_mm(flower.commit(), flowers, gm, false)

# ================================================================== particles
func particle_quad(size:Vector2, color:Color, unshaded:bool = false) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 3.0
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	return q

func build_particles():
	rain = GPUParticles3D.new()
	var rm := ParticleProcessMaterial.new()
	rm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rm.emission_box_extents = Vector3(28, 1, 22)
	rm.direction = Vector3(0.15, -1, 0.05)
	rm.spread = 2.0
	rm.initial_velocity_min = 22.0
	rm.initial_velocity_max = 26.0
	rm.gravity = Vector3.ZERO
	rain.process_material = rm
	var drop := BoxMesh.new()
	drop.size = Vector3(0.03, 0.7, 0.03)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(0.8, 0.88, 1.0, 0.45)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = dm
	rain.draw_pass_1 = drop
	rain.amount = 1400
	rain.lifetime = 0.75
	rain.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	rain.emitting = false
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)

	leaves = GPUParticles3D.new()
	var lm := ParticleProcessMaterial.new()
	lm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	lm.emission_box_extents = Vector3(30, 1, 24)
	lm.direction = Vector3(1, -0.3, 0.3)
	lm.spread = 40.0
	lm.initial_velocity_min = 0.6
	lm.initial_velocity_max = 1.6
	lm.gravity = Vector3(0.4, -0.5, 0.1)
	lm.angular_velocity_min = -180
	lm.angular_velocity_max = 180
	lm.angle_min = 0
	lm.angle_max = 360
	lm.turbulence_enabled = true
	lm.turbulence_noise_strength = 0.6
	lm.turbulence_influence_min = 0.05
	lm.turbulence_influence_max = 0.15
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color("ffb7c9"), Color("ffffff"), Color("f2c54a"), Color("8fd16a")])
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	lm.color_initial_ramp = gt
	leaves.process_material = lm
	var petal := particle_quad(Vector2(0.14, 0.1), Color.WHITE)
	(petal.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	leaves.draw_pass_1 = petal
	leaves.amount = 160
	leaves.lifetime = 9.0
	leaves.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(leaves)

	fireflies = GPUParticles3D.new()
	var fm := ParticleProcessMaterial.new()
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	fm.emission_box_extents = Vector3(30, 1.2, 24)
	fm.gravity = Vector3.ZERO
	fm.initial_velocity_min = 0.1
	fm.initial_velocity_max = 0.4
	fm.spread = 180
	fm.turbulence_enabled = true
	fm.turbulence_noise_strength = 1.2
	fm.turbulence_influence_min = 0.1
	fm.turbulence_influence_max = 0.3
	var fade := Curve.new()
	fade.add_point(Vector2(0, 0))
	fade.add_point(Vector2(0.3, 1))
	fade.add_point(Vector2(0.7, 1))
	fade.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = fade
	fm.scale_curve = ct
	fireflies.process_material = fm
	fireflies.draw_pass_1 = particle_quad(Vector2(0.12, 0.12), Color("d8ff8a"), true)
	fireflies.amount = 90
	fireflies.lifetime = 5.0
	fireflies.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 20, 80))
	fireflies.emitting = false
	add_child(fireflies)

	for s in smoke:
		var sp := CPUParticles3D.new()
		sp.position = s
		sp.amount = 6
		sp.lifetime = 3.5
		sp.direction = Vector3(0.3, 1, 0)
		sp.spread = 12
		sp.initial_velocity_min = 0.4
		sp.initial_velocity_max = 0.7
		sp.gravity = Vector3(0.25, 0.05, 0)
		sp.scale_amount_min = 0.5
		sp.scale_amount_max = 1.0
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.4))
		sc.add_point(Vector2(1, 1.6))
		sp.scale_amount_curve = sc
		var sm := SphereMesh.new()
		sm.radius = 0.25
		sm.height = 0.5
		sm.radial_segments = 8
		sm.rings = 4
		var smm := StandardMaterial3D.new()
		smm.albedo_color = Color(0.95, 0.95, 1.0, 0.45)
		smm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		sm.material = smm
		sp.mesh = sm
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sp)
	# fountain spray
	var spray := CPUParticles3D.new()
	spray.position = Vector3(0, 2.3, -23)
	spray.amount = 40
	spray.lifetime = 1.1
	spray.direction = Vector3.UP
	spray.spread = 25
	spray.initial_velocity_min = 2.5
	spray.initial_velocity_max = 3.2
	spray.gravity = Vector3(0, -7, 0)
	var dropm := SphereMesh.new()
	dropm.radius = 0.05
	dropm.height = 0.1
	dropm.radial_segments = 6
	dropm.rings = 3
	var dmm := StandardMaterial3D.new()
	dmm.albedo_color = Color(0.75, 0.92, 1.0)
	dmm.emission_enabled = true
	dmm.emission = Color(0.4, 0.6, 0.8)
	dropm.material = dmm
	spray.mesh = dropm
	add_child(spray)
	# butterflies
	var wing := Kit.new()
	for s in [-1, 1]: wing.box(Kit.rot(s * 0.09, 0, 0, 0, 0, 0), Vector3(0.16, 0.01, 0.13), Color.WHITE, 0.0)
	var wmesh := wing.commit()
	for i in 14:
		var b := MeshInstance3D.new()
		b.mesh = wmesh
		b.material_override = toon
		b.set_instance_shader_parameter("itint", col(["ffd166", "ff9fb8", "8fd3ff", "ffffff", "c59dff"][i % 5]))
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
		butterflies.append([b, Vector2(rng.randf_range(-30, 30), rng.randf_range(-26, 26)), rng.randf() * 10.0])

# ================================================================== time of day
const TOD_KEYS = [
	# tod, sky top, horizon, light colour, light energy, ambient colour, ambient energy, fog colour
	[0.00, "0f1736", "26325f", "9fb6ff", 0.55, "52619f", 0.62, "1c2448"],
	[0.20, "28346a", "7c6aa0", "ffb08a", 0.35, "7a6f9e", 0.6, "5a5378"],
	[0.27, "6fa6e6", "ffd2b4", "ffe2bf", 1.0, "b4bfe6", 0.68, "e8d2c4"],
	[0.40, "5ca4ef", "d6ecff", "fff7e8", 1.35, "c3d6ff", 0.72, "cfe2f2"],
	[0.62, "62a0ea", "e4eeff", "fff3dc", 1.3, "c8d6f5", 0.72, "d6e2ee"],
	[0.71, "6b8fdc", "ffd49a", "ffd09a", 1.15, "d3c2d8", 0.7, "f2d6b4"],
	[0.77, "5a54a6", "ff9468", "ff8d5c", 0.85, "c69ab8", 0.66, "f0a088"],
	[0.82, "232b66", "8a5c96", "b3a6ff", 0.45, "6a64a6", 0.62, "4a3f6e"],
	[0.90, "121a3c", "2b3566", "a6bcff", 0.58, "52619f", 0.62, "1f284c"],
	[1.00, "0f1736", "26325f", "9fb6ff", 0.55, "52619f", 0.62, "1c2448"],
]

func sample_tod(t:float) -> Array:
	t = fposmod(t, 1.0)
	for i in TOD_KEYS.size() - 1:
		var a:Array = TOD_KEYS[i]
		var b:Array = TOD_KEYS[i + 1]
		if t >= a[0] and t <= b[0]:
			var f := smoothstep(0.0, 1.0, (t - a[0]) / maxf(0.0001, b[0] - a[0]))
			return [Color(a[1]).lerp(Color(b[1]), f), Color(a[2]).lerp(Color(b[2]), f), Color(a[3]).lerp(Color(b[3]), f),
				lerpf(a[4], b[4], f), Color(a[5]).lerp(Color(b[5]), f), lerpf(a[6], b[6], f), Color(a[7]).lerp(Color(b[7]), f)]
	return sample_tod(0.0)

func update_time(tod:float, event:int, wx:int, focus:Vector3, dt:float, t:float):
	# wrap-aware smoothing of the time of day
	var diff := fposmod(tod - tod_now + 0.5, 1.0) - 0.5
	tod_now = fposmod(tod_now + diff * minf(1.0, dt * 1.5), 1.0)
	var k := sample_tod(tod_now)
	var night := clampf(1.0 - smoothstep(0.22, 0.3, tod_now) + smoothstep(0.74, 0.82, tod_now), 0.0, 1.0)
	var day := 1.0 - night
	var is_night_phase := event >= 0
	var blackout := 1.0 if is_night_phase and event == 1 and night > 0.5 else 0.0
	var fog_target := 1.0 if is_night_phase and event == 3 and night > 0.3 else 0.0
	var red_target := 1.0 if is_night_phase and event == 5 and night > 0.3 else 0.0
	var wet_target := 1.0 if wx == 2 or (is_night_phase and event == 4 and night > 0.3) else 0.0
	cur_blackout = move_toward(cur_blackout, blackout, dt * 0.8)
	cur_fog = move_toward(cur_fog, fog_target, dt * 0.25)
	cur_red = move_toward(cur_red, red_target, dt * 0.3)
	cur_wet = move_toward(cur_wet, wet_target, dt * 0.2)
	# light direction: sun sweeps east→south→west by day, moon by night
	var sun_t := clampf((tod_now - 0.22) / 0.58, 0.0, 1.0)
	var az := lerpf(-1.25, 1.25, sun_t)
	var el := lerpf(0.18, 1.05, sin(sun_t * PI))
	if night > 0.5:
		var mt := fposmod(tod_now - 0.78, 1.0) / 0.44
		az = lerpf(1.0, -1.0, clampf(mt, 0, 1))
		el = 0.85
	var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el) * 0.9 + 0.3).normalized()
	sun.basis = Basis.looking_at(-dir, Vector3.UP)
	var light_col:Color = k[2]
	var energy:float = k[3]
	var amb:Color = k[4]
	var fogc:Color = k[6]
	var clouds := 0.25 + 0.35 * float(wx >= 1) + 0.3 * cur_wet
	energy *= 1.0 - 0.35 * cur_wet - 0.2 * float(wx == 1) * day
	if cur_fog > 0:
		fogc = fogc.lerp(Color("8f98bd"), cur_fog * 0.75)
		amb = amb.lerp(Color("8f98bd"), cur_fog * 0.3)
	if cur_red > 0:
		light_col = light_col.lerp(Color("ff7a6a"), cur_red * 0.7)
		amb = amb.lerp(Color("a0507a"), cur_red * 0.6)
		fogc = fogc.lerp(Color("5a2038"), cur_red * 0.7)
	flash_light = maxf(0.0, flash_light - dt * 3.0)
	sun.light_color = light_col.lerp(Color.WHITE, flash_light * 0.6)
	sun.light_energy = energy + flash_light * 2.5
	env.ambient_light_color = amb
	env.ambient_light_energy = k[5] * 0.62 + flash_light
	env.fog_light_color = fogc
	env.fog_density = 0.0018 + 0.03 * cur_fog + 0.004 * cur_wet
	env.fog_height_density = 0.35 * cur_fog
	env.fog_height = 2.5
	env.volumetric_fog_enabled = quality >= 3 and cur_fog > 0.05
	env.volumetric_fog_density = 0.04 * cur_fog
	env.volumetric_fog_albedo = Color(0.75, 0.8, 0.95)
	env.adjustment_saturation = 1.22 - 0.15 * cur_fog - 0.1 * cur_wet
	sky_mat.set_shader_parameter("top_color", k[0])
	sky_mat.set_shader_parameter("horizon_color", k[1])
	sky_mat.set_shader_parameter("sun_dir", dir if day > 0.5 else -dir)
	sky_mat.set_shader_parameter("moon_dir", dir if night > 0.5 else -dir)
	sky_mat.set_shader_parameter("stars", night)
	sky_mat.set_shader_parameter("cloud_cover", clouds)
	sky_mat.set_shader_parameter("ground_color", fogc)
	var glow := smoothstep(0.25, 0.9, night) * (1.0 - 0.85 * cur_blackout)
	RenderingServer.global_shader_parameter_set("g_night_glow", glow)
	RenderingServer.global_shader_parameter_set("g_day", day)
	RenderingServer.global_shader_parameter_set("g_wet", cur_wet)
	RenderingServer.global_shader_parameter_set("g_wind", 0.5 + 0.8 * cur_wet + 0.3 * sin(t * 0.13))
	for l in lamps: l.light_energy = glow * 1.6
	# follow the camera with the ambient particle volumes
	for p in [rain, leaves, fireflies]:
		if p: p.global_position = Vector3(focus.x, 0, focus.z)
	rain.position.y = 16.0
	leaves.position.y = 7.0
	fireflies.position.y = 1.2
	rain.emitting = cur_wet > 0.3
	rain.amount_ratio = clampf(cur_wet, 0.1, 1.0)
	leaves.emitting = day > 0.5 and cur_wet < 0.5
	fireflies.emitting = night > 0.6 and cur_wet < 0.5 and cur_red < 0.5
	for b in butterflies:
		var node:MeshInstance3D = b[0]
		node.visible = day > 0.6 and cur_wet < 0.3
		if not node.visible: continue
		var ph:float = b[2]
		var base:Vector2 = b[1]
		var pos := Vector3(base.x + sin(t * 0.3 + ph) * 4.0, 1.0 + 0.4 * sin(t * 1.7 + ph), base.y + cos(t * 0.23 + ph * 1.3) * 3.0)
		var vel := Vector3(cos(t * 0.3 + ph), 0, -sin(t * 0.23 + ph * 1.3))
		node.position = pos
		node.rotation.y = atan2(vel.x, vel.z)
		node.scale = Vector3(absf(sin(t * 14.0 + ph)) * 0.9 + 0.1, 1, 1)

func lightning():
	flash_light = 1.0
