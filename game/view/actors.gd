extends Node3D
## Everything that moves or changes: heroes, zombies, defences, loot, banners,
## balloons, survivors and projectiles. Rebuilt from host snapshots and interpolated.

const Kit = preload("res://game/view/kit.gd")
const Rig = preload("res://game/view/rig.gd")
const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
const Nav = preload("res://game/nav.gd")

signal entity_hit(pos:Vector3)

const SLOT_COLORS = ["ffd166", "4cc9f0", "f78fb3", "06d6a0"]
const SKINS = ["f2c29b", "8d5a3b", "e8b48a", "c68c5e"]
const ZSKINS = ["a6d69c", "b3d39b", "9fcfb6", "c2d9a0"]
const SHIRTS = ["d9a3c8", "9ab8e0", "e6c88f", "f0a3a3", "a3d9c8"]

var toon:ShaderMaterial
var toon_char:ShaderMaterial
var sway:ShaderMaterial
var glow_mat:ShaderMaterial
var bar_mat:ShaderMaterial
var blob_mat:ShaderMaterial
var ghost_mat:ShaderMaterial
var cache := {}
var nav_helper := Nav.new()

var heroes := {}
var horde := {}
var structs := {}
var loot_nodes := []
var local_rolling := false   # the local dodge, ahead of the snapshot
var local_firing := false   # set by main from the local mouse button, ahead of the snapshot
var beacons := []
var drops := {}
var bundles := {}
var piece_nodes := []
var job_nodes := {}
const STAGE_SLOTS = [Vector2(-8.0, 1.1), Vector2(-8.0, -0.3), Vector2(-8.0, -1.7), Vector2(-8.0, -3.1)]
var people := {}
var community := []
var projectiles := []
var ghost:MeshInstance3D
var ghost_range:MeshInstance3D
var local_id := 0
var night := 0.0
var bar_quad:QuadMesh
var blob_quad:QuadMesh
var beam_mat:ShaderMaterial
var zone_mat:ShaderMaterial

func _init():
	var shader:Shader = load("res://game/shaders/toon.gdshader")
	toon = ShaderMaterial.new()
	toon.shader = shader
	toon_char = ShaderMaterial.new()
	toon_char.shader = shader
	toon_char.set_shader_parameter("rim_strength", 0.45)
	toon_char.set_shader_parameter("gloss", 0.3)
	var outline := ShaderMaterial.new()
	outline.shader = load("res://game/shaders/outline.gdshader")
	toon_char.next_pass = outline
	sway = ShaderMaterial.new()
	sway.shader = shader
	sway.set_shader_parameter("wind_amp", 0.25)
	glow_mat = ShaderMaterial.new()
	glow_mat.shader = shader
	glow_mat.set_shader_parameter("glow_always", 1.0)
	beam_mat = ShaderMaterial.new()
	beam_mat.shader = load("res://game/shaders/fx.gdshader")
	beam_mat.set_shader_parameter("color", Color(1.0, 0.93, 0.72))
	beam_mat.set_shader_parameter("energy", 0.22)
	zone_mat = ShaderMaterial.new()
	zone_mat.shader = load("res://game/shaders/soft.gdshader")
	zone_mat.set_shader_parameter("shape", 1)
	zone_mat.set_shader_parameter("color", Color(1.0, 0.92, 0.6, 0.35))
	bar_mat = ShaderMaterial.new()
	bar_mat.shader = load("res://game/shaders/bar.gdshader")
	blob_mat = ShaderMaterial.new()
	blob_mat.shader = load("res://game/shaders/soft.gdshader")
	blob_mat.set_shader_parameter("color", Color(0.12, 0.1, 0.22, 0.42))
	ghost_mat = ShaderMaterial.new()
	ghost_mat.shader = load("res://game/shaders/ghost.gdshader")
	bar_quad = QuadMesh.new()
	bar_quad.size = Vector2(0.9, 0.11)
	blob_quad = QuadMesh.new()
	blob_quad.size = Vector2(1, 1)
	blob_quad.orientation = PlaneMesh.FACE_Y

static func C(hex:String) -> Color:
	return Color(hex)

func cached(key:String, builder:Callable) -> ArrayMesh:
	if not cache.has(key):
		var k := Kit.new()
		builder.call(k)
		cache[key] = k.commit()
	return cache[key]

# ================================================================== heroes
func head_base(k:Kit, skin:Color, zombie:bool = false, big:float = 1.0):
	var r := Vector3(0.4, 0.37, 0.38) * big
	k.cylinder(Kit.at(0, 0.03, 0), 0.12, 0.12, 0.12, skin.darkened(0.1), 8)
	k.sphere(Kit.at(0, 0.36 * big, 0), r, skin, 16, 10, 0.12)
	for s in [-1, 1]:
		k.sphere(Kit.at(s * 0.39 * big, 0.34 * big, 0), Vector3(0.08, 0.1, 0.07) * big, skin.darkened(0.05), 8, 5)
	if not zombie:
		k.sphere(Kit.at(0, 0.3 * big, 0.37 * big), Vector3(0.05, 0.04, 0.04), skin.darkened(0.12), 6, 4)
		for s in [-1, 1]:
			k.sphere(Kit.at(s * 0.23, 0.27, 0.315), Vector3(0.08, 0.045, 0.03), C("ff9aa8"), 8, 4)
		k.box(Kit.rot(0, 0.19, 0.355, 0, 0.2), Vector3(0.11, 0.03, 0.02), C("6a2f3a"), 0.012)
	else:
		k.sphere(Kit.at(0.02, 0.17 * big, 0.33 * big), Vector3(0.12, 0.07, 0.05) * big, C("4a2340"), 8, 5)
		k.box(Kit.at(0.06 * big, 0.21 * big, 0.37 * big), Vector3(0.04, 0.05, 0.02) * big, C("fff6dc"), 0.01)

func boss_eyes() -> ArrayMesh:
	return cached("bosseyes", func(k:Kit):
		for e in [[-0.32, 0.05, 0.2], [0.3, 0.12, 0.16], [0.12, -0.18, 0.1], [-0.12, 0.32, 0.09]]:
			k.sphere(Kit.at(e[0], e[1], 0.8), Vector3(e[2], e[2] * 0.8, 0.08), Kit.glow(C("ff2a3a"), 1.0), 10, 6)
			k.sphere(Kit.at(e[0], e[1], 0.86), Vector3(e[2] * 0.35, e[2] * 0.6, 0.04), Kit.glow(C("fff0a0"), 1.0), 8, 4)
	)

func eyes_mesh(zombie:bool, big:float = 1.0) -> ArrayMesh:
	return cached("eyes%s%.2f" % [zombie, big], func(k:Kit):
		if zombie:
			for s in [-1, 1]:
				var sz := 1.15 if s < 0 else 0.8
				k.sphere(Kit.at(s * 0.15 * big, 0.02 * big, 0.33 * big), Vector3(0.09, 0.1, 0.05) * sz * big, C("fff8e6"), 10, 6)
				k.sphere(Kit.at(s * 0.15 * big, 0.02 * big, 0.375 * big), Vector3(0.035, 0.035, 0.02) * sz * big, Kit.glow(C("3a2a3a"), 0.0), 8, 4)
				k.sphere(Kit.at(s * 0.15 * big, 0.02 * big, 0.38 * big), Vector3(0.025, 0.025, 0.02) * sz * big, Kit.glow(C("d6ff5a"), 1.0), 8, 4)
		else:
			for s in [-1, 1]:
				k.sphere(Kit.at(s * 0.14, 0.02, 0.325), Vector3(0.085, 0.115, 0.05), C("ffffff"), 10, 6)
				k.sphere(Kit.at(s * 0.135, 0.0, 0.365), Vector3(0.06, 0.085, 0.03), C("2b2340"), 10, 6)
				k.sphere(Kit.at(s * 0.135 + 0.025, 0.04, 0.39), Vector3(0.022, 0.022, 0.01), C("ffffff"), 6, 4)
			for s in [-1, 1]:
				k.box(Kit.rot(s * 0.14, 0.15, 0.34, 0, 0, -s * 0.15), Vector3(0.12, 0.025, 0.02), C("3a2a2a"), 0.01)
	)

func arm_mesh(sleeve:Color, skin:Color, length:float = 0.32, thick:float = 1.0) -> ArrayMesh:
	return cached("arm%s%s%.2f%.2f" % [sleeve.to_html(), skin.to_html(), length, thick], func(k:Kit):
		k.sphere(Kit.at(0, -0.02, 0), Vector3(0.12, 0.12, 0.12) * thick, sleeve, 8, 6)
		k.cylinder(Kit.at(0, -length * 0.5, 0), 0.09 * thick, 0.1 * thick, length, sleeve, 10)
		k.sphere(Kit.at(0, -length - 0.08, 0.0), Vector3(0.095, 0.095, 0.095) * thick, skin, 10, 6)
	)

func leg_mesh(pants:Color, shoe:Color, thick:float = 1.0) -> ArrayMesh:
	return cached("leg%s%s%.2f" % [pants.to_html(), shoe.to_html(), thick], func(k:Kit):
		k.cylinder(Kit.at(0, -0.2, 0), 0.11 * thick, 0.12 * thick, 0.38, pants, 10)
		k.box(Kit.at(0, -0.52, 0.05), Vector3(0.21, 0.16, 0.33) * Vector3(thick, 1, 1), shoe, 0.07, 0.3)
		k.box(Kit.at(0, -0.59, 0.05), Vector3(0.22, 0.04, 0.34) * Vector3(thick, 1, 1), shoe.darkened(0.3), 0.02)
	)

func role_look(role:int) -> Dictionary:
	match role:
		0: return {"shirt":"f2a93b", "pants":"3d5a80", "skin":SKINS[0], "hair":"5a3a2a", "shoe":"7a4f2f"}
		1: return {"shirt":"f4f7f6", "pants":"4aa89a", "skin":SKINS[1], "hair":"2a1f1a", "shoe":"4a4f5c"}
		2: return {"shirt":"6b7f4a", "pants":"4a5638", "skin":SKINS[2], "hair":"3a2a1a", "shoe":"2f2f38"}
		3: return {"shirt":"ff9fb8", "pants":"c9a274", "skin":SKINS[3], "hair":"d2562e", "shoe":"7a4f2f"}
	return {}

func hero_torso(role:int, slot:int) -> ArrayMesh:
	return cached("torso%d_%d" % [role, slot], func(k:Kit):
		var L := role_look(role)
		var shirt := C(L.shirt)
		var pants := C(L.pants)
		k.box(Kit.at(0, 0.9, 0), Vector3(0.64, 0.58, 0.46), shirt, 0.21, 0.2, 2)
		k.box(Kit.at(0, 0.66, 0), Vector3(0.6, 0.24, 0.44), pants, 0.11, 0.1)
		var scarf := C(SLOT_COLORS[slot % 4])
		k.cylinder(Kit.at(0, 1.18, 0), 0.24, 0.27, 0.1, scarf, 12)
		k.box(Kit.rot(0.08, 1.06, 0.24, 0.2, 0.3), Vector3(0.12, 0.16, 0.04), scarf, 0.03)
		match role:
			0:
				for s in [-1, 1]: k.box(Kit.at(s * 0.17, 0.98, 0.215), Vector3(0.07, 0.42, 0.05), shirt.darkened(0.25), 0.02)
				k.box(Kit.at(0, 0.92, 0.225), Vector3(0.3, 0.22, 0.04), shirt.darkened(0.15), 0.04)
				k.box(Kit.at(0, 0.74, 0), Vector3(0.66, 0.1, 0.5), C("7a4f2f"), 0.04)
				for s in [-1, 1]: k.box(Kit.at(s * 0.26, 0.7, 0.16), Vector3(0.12, 0.14, 0.1), C("9a6a48"), 0.03)
				k.box(Kit.rot(0.05, 0.95, -0.27, 0, 0, 0.6), Vector3(0.08, 0.5, 0.05), C("aab4c2"), 0.02)
				k.cylinder(Kit.rot(0.2, 1.17, -0.27, 0, 0, 0.6), 0.07, 0.07, 0.04, C("aab4c2"), 8)
			1:
				k.box(Kit.at(0, 0.72, 0), Vector3(0.68, 0.34, 0.5), shirt, 0.12, 0.15)
				k.box(Kit.at(0, 1.08, 0.18), Vector3(0.3, 0.12, 0.12), C("4aa89a"), 0.04)
				k.box(Kit.at(-0.14, 0.95, 0.235), Vector3(0.12, 0.04, 0.02), C("e8463c"), 0.0)
				k.box(Kit.at(-0.14, 0.95, 0.235), Vector3(0.04, 0.12, 0.02), C("e8463c"), 0.0)
				k.box(Kit.at(0, 0.9, -0.3), Vector3(0.44, 0.44, 0.2), C("e8463c"), 0.08, 0.2)
				k.box(Kit.at(0, 0.92, -0.405), Vector3(0.18, 0.05, 0.02), C("ffffff"), 0.0)
				k.box(Kit.at(0, 0.92, -0.405), Vector3(0.05, 0.18, 0.02), C("ffffff"), 0.0)
				k.cylinder(Kit.rot(0.06, 1.02, 0.24, 0, 0, 0), 0.015, 0.015, 0.25, C("3a3a48"), 4)
			2:
				k.box(Kit.at(0, 0.92, 0.02), Vector3(0.68, 0.46, 0.46), C("55673a"), 0.15)
				for s in [-1, 1]:
					for i in 2: k.box(Kit.at(s * 0.15, 0.82 + i * 0.16, 0.25), Vector3(0.14, 0.12, 0.06), C("4a5a32"), 0.03)
				k.box(Kit.rot(0, 0.95, 0.24, 0, 0, 0.7), Vector3(0.09, 0.72, 0.04), C("7a4f2f"), 0.02)
				for i in 5: k.box(Kit.rot(-0.17 + i * 0.085, 0.82 + i * 0.07, 0.27, 0, 0, 0.7), Vector3(0.035, 0.09, 0.035), C("f2c14e"), 0.01)
				k.box(Kit.at(0, 0.95, -0.3), Vector3(0.48, 0.5, 0.22), C("5f7240"), 0.08, 0.2)
			3:
				for s in [-1, 1]: k.box(Kit.at(s * 0.19, 0.9, 0.2), Vector3(0.22, 0.56, 0.08), C("3fb6a8"), 0.06)
				for s in [-1, 1]:
					k.cylinder(Kit.rot(s * 0.07, 0.98, 0.29, 0, PI * 0.5), 0.05, 0.05, 0.14, C("2f2f38"), 8)
				k.box(Kit.rot(0, 0.92, 0.0, 0, 0, -0.75), Vector3(0.07, 0.8, 0.5), C("8b5e3c"), 0.02)
				k.box(Kit.at(0.3, 0.72, -0.1), Vector3(0.16, 0.22, 0.28), C("a87a4a"), 0.05)
	)

func hero_head(role:int) -> ArrayMesh:
	return cached("head%d" % role, func(k:Kit):
		var L := role_look(role)
		var skin := C(L.skin)
		var hair := C(L.hair)
		head_base(k, skin)
		k.sphere(Kit.at(0, 0.46, -0.05), Vector3(0.42, 0.33, 0.39), hair, 14, 8)
		k.box(Kit.rot(-0.12, 0.6, 0.3, 0.3, 0.5), Vector3(0.22, 0.08, 0.14), hair, 0.04)
		match role:
			0:
				k.sphere(Kit.at(0, 0.6, 0), Vector3(0.44, 0.27, 0.44), C("ffd23f"), 16, 8, 0.15, 0.2)
				k.cylinder(Kit.at(0, 0.58, 0.04), 0.5, 0.5, 0.05, C("ffd23f"), 16)
				k.box(Kit.at(0, 0.75, 0), Vector3(0.1, 0.12, 0.8), C("f5c400"), 0.04)
				k.cylinder(Kit.rot(0, 0.66, 0.42, 0, PI * 0.5), 0.07, 0.07, 0.06, Kit.glow(C("fff2a8")), 10)
				k.sphere(Kit.at(0, 0.36, -0.48), Vector3(0.12, 0.18, 0.12), hair, 8, 6)
			1:
				k.sphere(Kit.at(0, 0.56, -0.02), Vector3(0.43, 0.27, 0.41), C("4aa89a"), 14, 8)
				for s in [-1, 1]:
					k.cylinder(Kit.rot(s * 0.14, 0.4, 0.37, 0, PI * 0.5), 0.09, 0.09, 0.02, C("2b2b38"), 12, false)
			2:
				k.sphere(Kit.at(0, 0.6, 0), Vector3(0.46, 0.3, 0.46), C("5f7240"), 16, 8, 0.2, 0.25)
				k.cylinder(Kit.at(0, 0.56, 0), 0.47, 0.47, 0.07, C("4a5a32"), 16)
				k.box(Kit.at(0.22, 0.7, 0.25), Vector3(0.1, 0.1, 0.1), C("e8463c"), 0.03)
			3:
				k.cylinder(Kit.at(0, 0.6, 0), 0.58, 0.58, 0.04, C("e6c98f"), 18)
				k.cylinder(Kit.at(0, 0.7, 0), 0.3, 0.33, 0.2, C("e6c98f"), 14)
				k.cylinder(Kit.at(0, 0.66, 0), 0.335, 0.335, 0.07, C("ff6b8b"), 14)
				k.box(Kit.rot(0.3, 0.8, -0.05, 0.3, 0, -0.7), Vector3(0.05, 0.35, 0.1), C("ffd166"), 0.03)
				k.sphere(Kit.at(0, 0.25, -0.42), Vector3(0.1, 0.22, 0.1), hair, 8, 6)
	)

func make_hero(role:int, slot:int) -> Rig:
	var r := Rig.new()
	r.setup_pivots(1.08, 0.36, 0.62, 0.15, 1.18)
	var L := role_look(role)
	r.add_part(r.body, hero_torso(role, slot), toon_char)
	r.add_part(r.head, hero_head(role), toon_char)
	r.eyes = r.add_part(r.head, eyes_mesh(false), toon)
	r.eyes.position = Vector3(0, 0.36, 0)
	r.add_part(r.arm_l, arm_mesh(C(L.shirt), C(L.skin)), toon_char)
	r.add_part(r.arm_r, arm_mesh(C(L.shirt), C(L.skin)), toon_char)
	r.add_part(r.leg_l, leg_mesh(C(L.pants), C(L.shoe)), toon_char)
	r.add_part(r.leg_r, leg_mesh(C(L.pants), C(L.shoe)), toon_char)
	r.pan = r.add_part(r.arm_l, pan_mesh(), toon_char)
	r.pan.position = Vector3(0, -0.45, 0.1)
	r.pan.visible = false
	add_extras(r, 0.9)
	var fl := SpotLight3D.new()
	fl.position = Vector3(0, 1.0, 0.35)
	fl.rotation.x = -0.45
	fl.spot_range = 11.0
	fl.spot_angle = 28.0
	fl.light_color = Color("fff1c8")
	fl.light_energy = 0.0
	fl.shadow_enabled = false
	r.body.add_child(fl)
	r.flashlight = fl
	return r

func add_extras(r:Rig, blob_size:float):
	r.blob = MeshInstance3D.new()
	r.blob.mesh = blob_quad
	r.blob.material_override = blob_mat
	r.blob.position.y = 0.04
	r.blob.scale = Vector3(blob_size, 1, blob_size)
	r.blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(r.blob)

func make_person(kind:int) -> Rig:
	var looks := [["e85d5d", "4a5a7a", "c68c5e", "6a4a2a"], ["ff9fb8", "f4f7f6", "f2c29b", "f2d06a"], ["ffd23f", "3d5a80", "8d5a3b", "222222"]]
	var L:Array = looks[kind % 3]
	var r := Rig.new()
	r.setup_pivots(1.08, 0.36, 0.62, 0.15, 1.18)
	r.add_part(r.body, cached("ptorso%d" % kind, func(k:Kit):
		k.box(Kit.at(0, 0.9, 0), Vector3(0.62, 0.58, 0.44), C(L[0]), 0.2, 0.2, 2)
		k.box(Kit.at(0, 0.66, 0), Vector3(0.58, 0.24, 0.42), C(L[1]), 0.1)
		if kind == 0:
			for i in 3: k.box(Kit.at(0, 0.72 + i * 0.16, 0.225), Vector3(0.6, 0.04, 0.02), C("8a2f2f"), 0.0)
		if kind == 2: k.box(Kit.at(0, 1.0, 0.25), Vector3(0.2, 0.1, 0.1), C("2f2f38"), 0.03)
	), toon_char)
	r.add_part(r.head, cached("phead%d" % kind, func(k:Kit):
		head_base(k, C(L[2]))
		k.sphere(Kit.at(0, 0.46, -0.05), Vector3(0.42, 0.33, 0.39), C(L[3]), 14, 8)
		if kind == 0:
			k.sphere(Kit.at(0, 0.6, 0), Vector3(0.42, 0.2, 0.42), C("3d5a80"), 12, 6)
			k.box(Kit.at(0, 0.58, 0.35), Vector3(0.4, 0.05, 0.3), C("3d5a80"), 0.03)
		if kind == 1:
			k.box(Kit.at(0, 0.72, 0.1), Vector3(0.36, 0.14, 0.2), C("ffffff"), 0.04)
		if kind == 2:
			k.sphere(Kit.at(0, 0.58, -0.02), Vector3(0.45, 0.28, 0.45), C("ffd23f"), 12, 6)
	), toon_char)
	r.eyes = r.add_part(r.head, eyes_mesh(false), toon)
	r.eyes.position = Vector3(0, 0.36, 0)
	r.add_part(r.arm_l, arm_mesh(C(L[0]), C(L[2])), toon_char)
	r.add_part(r.arm_r, arm_mesh(C(L[0]), C(L[2])), toon_char)
	r.add_part(r.leg_l, leg_mesh(C(L[1]), C("4a4f5c")), toon_char)
	r.add_part(r.leg_r, leg_mesh(C(L[1]), C("4a4f5c")), toon_char)
	r.scale = Vector3.ONE * 0.9
	add_extras(r, 0.85)
	return r

func pan_mesh() -> ArrayMesh:
	return cached("pan", func(k:Kit):
		k.cylinder(Kit.rot(0, -0.05, 0.25, 0, PI * 0.5), 0.03, 0.03, 0.35, C("6b4f3c"), 6)
		k.cylinder(Kit.rot(0, -0.05, 0.62, 0, PI * 0.5), 0.24, 0.2, 0.06, C("3a3a48"), 14)
	)

func gun_mesh(g:int) -> ArrayMesh:
	return cached("gun%d" % g, func(k:Kit):
		var c := C(Data.WEAPONS[g].color)
		match g:
			0:
				k.box(Kit.at(0, 0, 0.05), Vector3(0.12, 0.16, 0.34), c, 0.05, 0.2)
				k.box(Kit.rot(0, -0.12, -0.05, 0, -0.3), Vector3(0.1, 0.2, 0.1), C("8b5e3c"), 0.03)
				k.cylinder(Kit.rot(0, 0.03, 0.3, 0, PI * 0.5), 0.05, 0.05, 0.2, C("e85d5d"), 10)
				k.cylinder(Kit.rot(0, 0.03, 0.42, 0, PI * 0.5), 0.045, 0.055, 0.07, C("d9b07a"), 10)
			1:
				k.box(Kit.at(0, 0, -0.05), Vector3(0.12, 0.14, 0.4), C("8b5e3c"), 0.04)
				k.cylinder(Kit.rot(0, 0.04, 0.35, 0, PI * 0.5), 0.07, 0.15, 0.5, c, 12)
				k.cylinder(Kit.rot(0, 0.04, 0.6, 0, PI * 0.5), 0.17, 0.17, 0.04, C("f2c14e"), 12)
			2:
				k.box(Kit.at(0, 0, 0.1), Vector3(0.13, 0.17, 0.5), c, 0.05, 0.2)
				k.cylinder(Kit.rot(0, -0.12, 0.08, 0, 0, PI * 0.5), 0.12, 0.12, 0.1, C("e85d5d"), 14)
				k.cylinder(Kit.rot(0, 0.03, 0.45, 0, PI * 0.5), 0.04, 0.04, 0.22, C("3a3a48"), 8)
			3:
				k.box(Kit.at(0, 0, 0.12), Vector3(0.11, 0.15, 0.75), c, 0.04, 0.2)
				k.box(Kit.rot(0, -0.04, -0.3, 0, 0.15), Vector3(0.1, 0.17, 0.3), C("8b5e3c"), 0.04)
				k.box(Kit.at(0, -0.13, 0.12), Vector3(0.08, 0.18, 0.1), C("3a3a48"), 0.03)
				k.cylinder(Kit.rot(0, 0.03, 0.6, 0, PI * 0.5), 0.035, 0.035, 0.3, C("3a3a48"), 8)
			4:
				k.box(Kit.at(0, 0, 0.15), Vector3(0.1, 0.14, 0.9), c, 0.04, 0.2)
				k.cylinder(Kit.rot(0, 0.14, 0.15, 0, PI * 0.5), 0.05, 0.05, 0.36, C("2f2f38"), 10)
				k.cylinder(Kit.rot(0, 0.14, 0.34, 0, PI * 0.5), 0.045, 0.045, 0.02, Kit.glow(C("8fd3ff")), 10)
				k.cylinder(Kit.rot(0, 0.02, 0.75, 0, PI * 0.5), 0.03, 0.03, 0.4, C("3a3a48"), 8)
			5:
				k.cylinder(Kit.rot(0, 0.02, 0.2, 0, PI * 0.5), 0.13, 0.13, 0.75, c, 14)
				k.cylinder(Kit.rot(0, 0.02, 0.58, 0, PI * 0.5), 0.15, 0.15, 0.06, C("2f2f38"), 14)
				k.box(Kit.at(0, -0.16, 0.05), Vector3(0.08, 0.2, 0.1), C("2f2f38"), 0.03)
			6:
				k.box(Kit.at(0, 0, 0.1), Vector3(0.12, 0.16, 0.5), C("e85d5d"), 0.05)
				k.cylinder(Kit.at(0, 0.0, -0.15), 0.12, 0.12, 0.35, c, 12)
				k.cylinder(Kit.rot(0, 0.03, 0.45, 0, PI * 0.5), 0.05, 0.08, 0.25, C("3a3a48"), 10)
				k.sphere(Kit.at(0, 0.03, 0.6), Vector3(0.05, 0.05, 0.05), Kit.glow(C("ffb14a")), 8, 4)
	)

func set_gun(r:Rig, g:int):
	if r.gun_kind == g: return
	r.gun_kind = g
	for c in r.gun.get_children(): c.queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = gun_mesh(g)
	mi.material_override = toon_char
	r.gun.add_child(mi)

# ================================================================== zombies
func zombie_parts(kind:int, variant:int) -> Dictionary:
	var key := "z%d_%d" % [kind, variant]
	if cache.has(key): return cache[key]
	var skin := C(ZSKINS[variant % ZSKINS.size()])
	var shirt := C(SHIRTS[(variant + kind) % SHIRTS.size()])
	var pants := C(["7a5a44", "5a6a8a", "6a5a7a"][variant % 3])
	if kind == 4: skin = C("b9b2dc")
	if kind == 5: skin = C("b8d68a")
	var out := {}
	var torso := Kit.new()
	var head := Kit.new()
	var extra := Kit.new()
	match kind:
		0:
			torso.box(Kit.at(0, 0.9, 0), Vector3(0.62, 0.56, 0.44), shirt, 0.18, 0.25, 2)
			for i in 4: torso.box(Kit.rot(-0.22 + i * 0.15, 0.63, 0.2, 0, 0, 0.785), Vector3(0.1, 0.1, 0.04), shirt, 0.01)
			torso.box(Kit.at(0.12, 0.98, 0.22), Vector3(0.12, 0.1, 0.03), skin, 0.02)
			torso.box(Kit.at(0, 0.66, 0), Vector3(0.58, 0.22, 0.42), pants, 0.1)
			head_base(head, skin, true)
			leaf_sprout(extra, 1)
		1:
			torso.box(Kit.at(0, 0.88, 0), Vector3(0.54, 0.56, 0.4), C(["f28a5a", "e86a9a", "5a9ae8"][variant % 3]), 0.18, 0.25, 2)
			torso.sphere(Kit.at(0, 1.12, -0.2), Vector3(0.3, 0.16, 0.16), C(["f28a5a", "e86a9a", "5a9ae8"][variant % 3]).darkened(0.1), 10, 6)
			torso.box(Kit.at(0, 0.66, 0), Vector3(0.52, 0.2, 0.38), pants, 0.09)
			head_base(head, skin, true, 0.92)
			var hood := C(["f28a5a", "e86a9a", "5a9ae8"][variant % 3]).darkened(0.05)
			head.sphere(Kit.at(0, 0.42, -0.08), Vector3(0.42, 0.36, 0.4), hood, 14, 8)
			head.cylinder(Kit.rot(0, 0.72, -0.28, 0, -0.9), 0.16, 0.02, 0.5, hood, 10)
			for i in 3:
				extra.box(Kit.rot(-0.1 + i * 0.1, 0.78, 0.15, 0, 0.4, -0.3 + i * 0.3), Vector3(0.04, 0.3, 0.04), C("6cc05a"), 0.015)
		2:
			torso.box(Kit.at(0, 0.88, 0), Vector3(0.74, 0.6, 0.52), shirt, 0.22, 0.25, 2)
			torso.box(Kit.at(0, 0.64, 0), Vector3(0.7, 0.24, 0.5), pants, 0.1)
			head_base(head, skin, true, 1.55)
			head.sphere(Kit.at(0, 1.0, -0.02), Vector3(0.78, 0.38, 0.78), C("e8463c"), 18, 9, 0.25, 0.25)
			for i in 7:
				var a := i * 2.4
				head.sphere(Kit.at(cos(a) * 0.42, 1.12 + 0.06 * sin(i * 1.3), sin(a) * 0.42), Vector3(0.1, 0.05, 0.1), C("fff6e0"), 8, 4)
		3:
			torso.box(Kit.at(0, 0.9, 0), Vector3(0.7, 0.58, 0.5), C("f2c14e"), 0.18, 0.25, 2)
			torso.box(Kit.at(0, 0.92, 0.26), Vector3(0.6, 0.06, 0.02), C("f6f6f0"), 0.0)
			torso.box(Kit.at(0, 0.66, 0), Vector3(0.66, 0.24, 0.48), pants, 0.1)
			torso.box(Kit.at(0, 0.98, 0.62), Vector3(1.3, 0.2, 0.16), C("a8744a"), 0.05, 0.2)
			torso.box(Kit.at(0, 0.98, 0.72), Vector3(1.35, 0.06, 0.04), C("8b5e3c"), 0.01)
			head_base(head, skin, true)
			head.cylinder(Kit.at(0, 0.82, 0), 0.38, 0.06, 0.75, C("ff7a2e"), 14, true)
			head.cylinder(Kit.at(0, 0.75, 0), 0.31, 0.27, 0.12, C("fafafa"), 14, false)
			head.box(Kit.at(0, 0.5, 0), Vector3(0.82, 0.06, 0.82), C("ff7a2e"), 0.03)
		4:
			torso.box(Kit.at(0, 0.88, 0), Vector3(0.52, 0.56, 0.38), C("7a6aa8"), 0.17, 0.25, 2)
			for i in 3: torso.box(Kit.rot(0, 0.75 + i * 0.13, 0, 0, 0, 0.4 * (i - 1)), Vector3(0.6, 0.04, 0.44), C("4f8a4a"), 0.02)
			torso.box(Kit.at(0, 0.66, 0), Vector3(0.5, 0.2, 0.36), pants, 0.09)
			head_base(head, skin, true, 0.95)
			leaf_sprout(extra, 2)
		5:
			torso.sphere(Kit.at(0, 0.88, 0.05), Vector3(0.5, 0.45, 0.48), skin.lightened(0.05), 16, 10, 0.2)
			for i in 5:
				var a := i * 1.3
				torso.sphere(Kit.at(cos(a) * 0.32, 0.8 + sin(i) * 0.2, 0.3 + sin(a) * 0.1), Vector3(0.07, 0.07, 0.04), C("9a6ab8"), 6, 4)
			torso.box(Kit.at(0, 0.56, 0), Vector3(0.6, 0.2, 0.44), pants, 0.1)
			head_base(head, skin, true, 0.9)
			for i in 4:
				var a := TAU * i / 4.0
				extra.sphere(Kit.rot(cos(a) * 0.09, 0.82, sin(a) * 0.09, a, 0.4), Vector3(0.1, 0.2, 0.06), C("ff7ab8"), 8, 5)
			extra.cylinder(Kit.at(0, 0.7, 0), 0.025, 0.03, 0.2, C("4f9a4a"), 6)
		6:
			torso.box(Kit.at(0, 0.9, 0), Vector3(0.6, 0.56, 0.44), C("3a3a48"), 0.18, 0.2, 2)
			for i in 8:
				var a := TAU * i / 8.0
				torso.cylinder(Kit.at(cos(a) * 0.33, 0.9, sin(a) * 0.25), 0.055, 0.055, 0.4, C("e8463c"), 8)
				torso.cylinder(Kit.at(cos(a) * 0.33, 1.12, sin(a) * 0.25), 0.01, 0.01, 0.06, C("2f2f38"), 4)
			torso.box(Kit.at(0, 0.66, 0), Vector3(0.56, 0.22, 0.42), pants, 0.1)
			head_base(head, skin, true)
			extra.cylinder(Kit.at(0, 0.88, 0), 0.22, 0.02, 0.5, C("4cc9f0"), 12)
			for i in 3: extra.cylinder(Kit.at(0, 0.7 + i * 0.13, 0), 0.19 - i * 0.055, 0.17 - i * 0.055, 0.05, C("ffd166"), 12, false)
			extra.sphere(Kit.at(0, 1.15, 0), Vector3(0.08, 0.08, 0.08), Kit.glow(C("ff4a4a")), 8, 5)
		7:
			# a festival giant torn open from inside: rotten flesh, roots, thorns and a maw
			var rot := C("5f6f4f")
			var robe := C("4a2f63")
			var bark := C("4a3526")
			var vine := C("3f6a35")
			var bone := C("efe2c4")
			var pus := Kit.glow(C("c6ff5a"), 1.0)
			# root legs clawing at the ground
			for i in 6:
				var a := TAU * i / 6.0 + 0.3
				torso.cylinder(Kit.rot(cos(a) * 0.95, 0.35, sin(a) * 0.95, -a, 0, 0.9), 0.26, 0.1, 1.1, bark, 8, true, 0.3)
				torso.cylinder(Kit.rot(cos(a) * 1.5, 0.1, sin(a) * 1.5, -a, 0, 1.35), 0.12, 0.02, 0.7, bark.darkened(0.2), 6)
			# torn festival robe with a ragged hem and broken gold trim
			torso.cylinder(Kit.at(0, 1.25, 0), 1.2, 0.85, 1.8, robe, 18, true, 0.3)
			for i in 14:
				var a := TAU * i / 14.0
				var drop := 0.25 + 0.2 * fmod(i * 0.618, 1.0)
				torso.box(Kit.rot(cos(a) * 1.15, 0.38 - drop * 0.5, sin(a) * 1.15, -a + PI * 0.5, 0.25 * sin(i * 2.1), 0.15), Vector3(0.45, drop + 0.35, 0.06), robe.darkened(0.15), 0.02)
			for i in 9:
				if i % 3 == 2: continue
				var a := TAU * i / 9.0
				torso.box(Kit.rot(cos(a) * 1.0, 1.8 + 0.05 * sin(i), sin(a) * 1.0, -a + PI * 0.5, 0, 0.1 * (i % 2)), Vector3(0.62, 0.12, 0.08), C("c9a032"), 0.02)
			# hunched rotting chest bursting out of the costume
			torso.sphere(Kit.at(0, 2.35, 0.15), Vector3(1.15, 0.95, 0.95), rot, 18, 12, 0.25)
			torso.sphere(Kit.at(0, 2.9, -0.25), Vector3(1.05, 0.65, 0.8), rot.darkened(0.1), 16, 10, 0.2)
			for i in 5:
				torso.box(Kit.rot(0, 2.0 + i * 0.16, 0.95 - abs(i - 2) * 0.05, 0, 0.1, 0), Vector3(1.1 - abs(i - 2) * 0.12, 0.06, 0.08), bone.darkened(0.1), 0.02)
			for i in 9:
				var a := i * 2.39
				torso.sphere(Kit.at(cos(a) * 0.85, 2.2 + sin(i * 1.7) * 0.5, 0.35 + sin(a) * 0.45), Vector3(0.13, 0.13, 0.1), pus, 8, 5)
			# thorns along the back and shoulders
			for i in 9:
				var x := -0.8 + i * 0.2
				var hgt := 0.45 + 0.35 * sin(PI * i / 8.0)
				torso.cylinder(Kit.rot(x, 3.1 + 0.25 * sin(PI * i / 8.0), -0.75, 0, -0.7, x * 0.6), 0.11, 0.0, hgt, bone, 6)
			# vines wrapped round the body
			for i in 7:
				var a := TAU * i / 7.0
				torso.cylinder(Kit.rot(cos(a) * 1.02, 1.7 + i * 0.12, sin(a) * 1.02, -a, 0.9, 0.4), 0.06, 0.05, 1.3, vine, 6)
				torso.cylinder(Kit.rot(cos(a) * 1.08, 1.6 + i * 0.12, sin(a) * 1.08, -a, 0.0, 0.0), 0.02, 0.0, 0.22, bone, 4)
			# the giant's papier-mache head, cracked, with a maw full of teeth
			var mache := C("b9b394")
			head.sphere(Kit.at(0, 0.95, 0), Vector3(0.95, 0.9, 0.88), mache, 18, 12, 0.15)
			head.sphere(Kit.at(0, 0.45, 0.35), Vector3(0.82, 0.42, 0.62), mache.darkened(0.08), 16, 8)
			head.sphere(Kit.at(0, 0.62, 0.62), Vector3(0.66, 0.36, 0.3), C("3a0f1e"), 14, 8)
			head.sphere(Kit.at(0, 0.6, 0.66), Vector3(0.5, 0.24, 0.22), Kit.glow(C("b0203a"), 0.4), 12, 6)
			for i in 9:
				var x := -0.52 + i * 0.13
				var fang := 0.24 + 0.1 * fmod(i * 0.7, 1.0) + (0.14 if i == 2 or i == 6 else 0.0)
				head.cylinder(Kit.rot(x, 0.9 - fang * 0.5, 0.95 - abs(x) * 0.4, 0, PI, 0), 0.07, 0.0, fang, bone, 5)
				head.cylinder(Kit.rot(x + 0.06, 0.36 + 0.1, 0.93 - abs(x) * 0.4, 0, 0, 0), 0.06, 0.0, 0.22, bone.darkened(0.05), 5)
			# heavy, furious brows over the burning eyes
			for sgn in [-1, 1]:
				head.box(Kit.rot(sgn * 0.3, 1.42, 0.82, 0, -0.3, sgn * 0.45), Vector3(0.5, 0.12, 0.2), C("4a3a30"), 0.04)
			for i in 6:
				var a := 0.4 + i * 0.9
				head.box(Kit.rot(cos(a) * 0.55, 1.1 + sin(a) * 0.45, 0.72, 0, 0, a), Vector3(0.5, 0.03, 0.03), C("5a3a2a"), 0.0)
			head.sphere(Kit.at(-0.55, 1.05, 0.55), Vector3(0.3, 0.28, 0.2), C("2a1420"), 10, 6)
			# broken, tilted crown with spikes
			head.cylinder(Kit.rot(0.1, 1.75, -0.05, 0, 0.12, 0.18), 0.6, 0.66, 0.3, C("d9b03a"), 16, false)
			for i in 6:
				if i == 4: continue
				var a := TAU * i / 6.0
				head.cylinder(Kit.rot(cos(a) * 0.62 + 0.1, 2.02 + 0.1 * sin(a), sin(a) * 0.62, 0, 0.12, 0.18), 0.11, 0.0, 0.42, C("d9b03a"), 6)
			# a carnivorous bloom and thorny vines growing out of the skull
			for i in 5:
				var a := TAU * i / 5.0
				extra.sphere(Kit.rot(cos(a) * 0.26, 0.9, sin(a) * 0.26, -a, 0, 0.9), Vector3(0.34, 0.06, 0.16), C("8a1f4a"), 10, 5)
				extra.cylinder(Kit.rot(cos(a) * 0.42, 0.95, sin(a) * 0.42, -a, 0, 1.2), 0.03, 0.0, 0.14, bone, 4)
			extra.sphere(Kit.at(0, 0.92, 0), Vector3(0.16, 0.12, 0.16), Kit.glow(C("ff3a6a"), 1.0), 10, 6)
			extra.cylinder(Kit.at(0, 0.7, 0), 0.08, 0.1, 0.4, vine, 8)
			for i in 3:
				extra.cylinder(Kit.rot(-0.6 + i * 0.6, 0.8, -0.3, 0.4 * i, -0.6, -0.5 + i * 0.5), 0.05, 0.02, 0.9, vine, 6)
	out.torso = torso.commit()
	out.head = head.commit()
	out.extra = extra.commit()
	var arm_len := 0.32
	var thick := 1.0
	if kind == 4: arm_len = 0.55
	if kind == 2: thick = 1.25
	if kind == 7:
		out.arm_r = boss_arm(true)
		out.arm_l = boss_arm(false)
	out.arm = arm_mesh(shirt if kind in [0, 2] else (C("7a6aa8") if kind == 4 else (C("8a5ab8") if kind == 7 else skin)), skin, arm_len, thick)
	out.leg = leg_mesh(pants, C("5a4a3a"), 1.25 if kind == 2 else 1.0)
	cache[key] = out
	return out

func boss_arm(club:bool) -> ArrayMesh:
	## The giant's arms: one ends in a tree-trunk club full of nails, the other in claws.
	var k := Kit.new()
	var rot := C("5f6f4f")
	var bark := C("4a3526")
	var bone := C("efe2c4")
	k.sphere(Kit.at(0, -0.05, 0), Vector3(0.42, 0.42, 0.42), rot, 12, 8)
	k.cylinder(Kit.at(0, -0.7, 0), 0.3, 0.26, 1.3, rot.darkened(0.05), 12, true, 0.2)
	for i in 3: k.cylinder(Kit.rot(0, -0.4 - i * 0.35, 0.05, i * 1.7, 0.9, 0.2), 0.04, 0.03, 0.7, C("3f6a35"), 6)
	if club:
		k.cylinder(Kit.at(0, -1.75, 0.05), 0.32, 0.55, 1.2, bark, 12, true, 0.3)
		for i in 10:
			var a := i * 2.4
			var y := -1.35 - fmod(i * 0.37, 1.0) * 0.9
			k.cylinder(Kit.rot(cos(a) * 0.48, y, sin(a) * 0.48 + 0.05, -a, 0, PI * 0.5), 0.035, 0.0, 0.3, C("8f9fb5"), 4)
		k.sphere(Kit.at(0, -2.35, 0.05), Vector3(0.55, 0.2, 0.55), bark.darkened(0.15), 10, 6)
	else:
		k.sphere(Kit.at(0, -1.5, 0.05), Vector3(0.36, 0.3, 0.32), rot, 10, 6)
		for i in 4:
			var x := -0.24 + i * 0.16
			k.cylinder(Kit.rot(x, -1.8, 0.18, 0, 0.5, (x) * 0.6), 0.07, 0.01, 0.6, bone, 6)
	return k.commit()

func leaf_sprout(k:Kit, count:int):
	k.cylinder(Kit.at(0, 0.78, 0), 0.025, 0.03, 0.22, C("4f9a4a"), 6)
	for i in count + 1:
		var a := TAU * i / (count + 1)
		k.sphere(Kit.rot(cos(a) * 0.14, 0.92, sin(a) * 0.14, -a, 0, 0.5), Vector3(0.16, 0.04, 0.08), C("7cd06a"), 8, 4)

func make_zombie(kind:int, variant:int) -> Rig:
	var r := Rig.new()
	r.zombie = true
	r.kind = kind
	var parts := zombie_parts(kind, variant)
	if kind == 7:
		r.setup_pivots(2.75, 1.25, 0.3, 0.4, 3.0)
	else:
		r.setup_pivots(1.08, 0.36 if kind != 2 else 0.42, 0.62, 0.15, 1.18)
	r.add_part(r.body, parts.torso, toon_char)
	r.add_part(r.head, parts.head, toon_char)
	var big := 1.0
	match kind:
		1: big = 0.92
		2: big = 1.55
		4: big = 0.95
		5: big = 0.9
		7: big = 2.2
	if kind == 7:
		# four burning eyes of different sizes instead of the usual pair
		r.eyes = r.add_part(r.head, boss_eyes(), glow_mat)
		r.eyes.position = Vector3(0, 1.1, 0)
	else:
		r.eyes = r.add_part(r.head, eyes_mesh(true, big), toon)
		r.eyes.position = Vector3(0, 0.36 * big, 0)
	if kind == 2: r.extra.position.y = 0.6
	if kind == 7: r.extra.position.y = 1.4
	r.add_part(r.extra, parts.extra, toon_char)
	r.add_part(r.arm_l, parts.get("arm_l", parts.arm), toon_char)
	r.add_part(r.arm_r, parts.get("arm_r", parts.arm), toon_char)
	if kind == 7:
		var glow := OmniLight3D.new()
		glow.position = Vector3(0, 3.6, 1.2)
		glow.light_color = Color("ff2a3a")
		glow.light_energy = 0.9
		glow.omni_range = 5.0
		glow.shadow_enabled = false
		r.head.add_child(glow)
	if kind != 7:
		r.add_part(r.leg_l, parts.leg, toon_char)
		r.add_part(r.leg_r, parts.leg, toon_char)
	match kind:
		1: r.scale = Vector3.ONE * 0.92
		2: r.scale = Vector3.ONE * 1.18
		3: r.scale = Vector3.ONE * 1.1
		4: r.scale = Vector3(0.95, 1.05, 0.95)
		5: r.scale = Vector3.ONE * 1.05
	add_extras(r, Data.ENEMIES[kind].r * 2.4)
	r.bar = MeshInstance3D.new()
	r.bar.mesh = bar_quad
	r.bar.material_override = bar_mat
	r.bar.position.y = 4.6 if kind == 7 else (2.7 if kind == 2 else 2.25)
	if kind == 7: r.bar.scale = Vector3(2.4, 1.8, 1)
	r.bar.visible = false
	r.bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(r.bar)
	return r

# ================================================================== structures
func wall_mesh(lvl:int, mask:int) -> ArrayMesh:
	return cached("wall%d_%d" % [lvl, mask], func(k:Kit):
		var dirs := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
		var arms := []
		for i in 4: if mask & (1 << i): arms.append(dirs[i])
		if arms.is_empty(): arms = [Vector2(1, 0), Vector2(-1, 0)]
		var wood := C("c98a55")
		var dark := C("8b5e3c")
		var metal := C("8f9fb5")
		if lvl < 2:
			k.box(Kit.at(0, 0.6, 0), Vector3(0.2, 1.2, 0.2), dark, 0.04)
			k.box(Kit.at(0, 1.22, 0), Vector3(0.24, 0.06, 0.24), dark.darkened(0.1), 0.02)
		else:
			k.box(Kit.at(0, 0.7, 0), Vector3(0.24, 1.4, 0.24), C("5a6a80"), 0.05)
		for a in arms:
			var yaw := atan2(a.x, a.y)
			var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(a.x * 0.25, 0, a.y * 0.25))
			if lvl < 2:
				var count := 3 if lvl == 0 else 4
				for i in count:
					var y := 0.25 + i * (0.95 / count) + 0.05
					var tilt := 0.06 * (1 if i % 2 else -1)
					k.box(xf * Kit.rot(0, y, 0, 0, tilt), Vector3(0.12 if lvl == 0 else 0.16, 0.2, 0.56), wood.lerp(C("d9a06a"), fmod(i * 0.37, 1.0)), 0.03, 0.15)
				k.box(xf * Kit.rot(0.03, 0.62, 0, 0, 0.9), Vector3(0.08, 0.12, 0.7), dark, 0.02)
				if lvl == 1:
					for j in 2: k.sphere(xf * Kit.at(0.25, 0.12, -0.14 + j * 0.28), Vector3(0.18, 0.12, 0.15), C("d9c79a"), 8, 5, 0.25)
					for j in 3: k.sphere(xf * Kit.at(0.07, 0.4 + j * 0.25, 0.1), Vector3(0.025, 0.025, 0.025), C("c8ccd4"), 4, 3)
			else:
				k.box(xf * Kit.at(0, 0.7, 0), Vector3(0.14, 1.3, 0.56), metal, 0.03, 0.25)
				for j in 3: k.box(xf * Kit.at(0.075, 0.25 + j * 0.45, 0), Vector3(0.02, 0.06, 0.56), metal.darkened(0.15), 0.0)
				for j in 4:
					k.box(xf * Kit.rot(0.08, 1.25, -0.21 + j * 0.14, 0, 0.6), Vector3(0.02, 0.12, 0.07), C("ffd166") if j % 2 == 0 else C("2b2d42"), 0.0)
				for j in 3:
					for side in [-1, 1]: k.sphere(xf * Kit.at(side * 0.075, 0.22 + j * 0.45, -0.2 + j * 0.2), Vector3(0.025, 0.025, 0.025), C("c8ccd4"), 5, 3)
				for j in 3: k.cylinder(xf * Kit.at(0, 1.42, -0.18 + j * 0.18), 0.03, 0.0, 0.18, C("c8ccd4"), 5)
			# sandbags piled along the foot of every level
			for j in 2:
				k.sphere(xf * Kit.rot(0.2, 0.13, -0.14 + j * 0.28, 0.2 * j), Vector3(0.17, 0.12, 0.15), C("d9c79a").darkened(0.05 * j), 8, 5, 0.25)
			if lvl < 2:
				for j in 3: k.sphere(xf * Kit.at(-0.07, 0.35 + j * 0.3, -0.18 + j * 0.18), Vector3(0.022, 0.022, 0.022), C("8f9fb5"), 4, 3)
		# pointed post top and a little pennant: still the verbena's barricade
		if lvl < 2:
			k.cylinder(Kit.at(0, 1.33, 0), 0.12, 0.0, 0.2, C("8b5e3c"), 6)
		k.cylinder(Kit.at(0.06, 1.55, 0), 0.015, 0.015, 0.5, C("6b4f3c"), 4)
		k.box(Kit.rot(0.06, 1.68, 0.12, 0, 0, 0), Vector3(0.02, 0.18, 0.22), C(["e85d5d", "4cc9f0", "f2c14e"][lvl]), 0.0)
	)

func structure_mesh(kind:int, lvl:int) -> ArrayMesh:
	return cached("s%d_%d" % [kind, lvl], func(k:Kit):
		var wood := C("c98a55")
		var dark := C("8b5e3c")
		var steel := C("8f9fb5")
		var iron := C("3d4a5c")
		var sand := C("d9c79a")
		match kind:
			Data.S_WIRE:
				# two wooden X frames (cheval de frise) wound with a coil of barbed wire
				for z in [-0.38, 0.38]:
					for sgn in [-1, 1]:
						k.box(Kit.rot(0, 0.32, z, 0, 0, sgn * 0.75), Vector3(0.07, 0.95, 0.07), wood.darkened(0.1 * (sgn + 1)), 0.02)
				k.box(Kit.at(0, 0.32, 0), Vector3(0.06, 0.06, 0.9), dark, 0.02)
				var turns := 7 + lvl * 3
				var steps := turns * 10
				var prev := Vector3.ZERO
				for i in steps + 1:
					var u := float(i) / steps
					var a := u * turns * TAU
					var p := Vector3(cos(a) * 0.3, 0.34 + sin(a) * 0.3, -0.46 + u * 0.92)
					if i > 0:
						var mid := (p + prev) * 0.5
						var dir := (p - prev)
						var len := dir.length()
						k.box(Transform3D(Basis.looking_at(dir / len, Vector3.UP), mid), Vector3(0.018, 0.018, len + 0.01), C("d6dbe2"), 0.0)
						if i % 4 == 0: k.box(Transform3D(Basis.looking_at(dir / len, Vector3.UP).rotated(dir / len, a), mid), Vector3(0.09, 0.014, 0.014), C("eef0f4"), 0.0)
					prev = p
				for z in [-0.4, 0.4]: k.sphere(Kit.at(0, 0.06, z), Vector3(0.12, 0.07, 0.1), sand, 6, 4)
			Data.S_COIL:
				# a little Tesla tower: striped base, porcelain insulators, copper winding
				k.box(Kit.at(0, 0.14, 0), Vector3(0.78, 0.28, 0.78), iron, 0.08, 0.3)
				for i in 6:
					var x := -0.33 + i * 0.13
					k.box(Kit.rot(x, 0.14, 0.395, 0, 0, 0.6), Vector3(0.06, 0.34, 0.01), C("f2c14e") if i % 2 == 0 else C("2b2d42"), 0.0)
				for i in 3: k.cylinder(Kit.at(0, 0.34 + i * 0.09, 0), 0.2 - i * 0.02, 0.2 - i * 0.02, 0.06, C("f6f0e0"), 12, true, 0.2)
				k.cylinder(Kit.at(0, 0.95, 0), 0.15, 0.15, 0.9, C("c8ccd4"), 12)
				for i in 10 + lvl * 2:
					k.cylinder(Kit.at(0, 0.55 + i * (0.8 / (10 + lvl * 2)), 0), 0.17, 0.17, 0.035, C("d9823a").lightened(0.1 * (i % 2)), 14, false)
				for a in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
					k.cylinder(Kit.rot(cos(a) * 0.28, 0.6, sin(a) * 0.28, -a, 0, 0.25), 0.025, 0.025, 0.6, C("4a4a58"), 5)
				for i in 12:
					var a := TAU * i / 12.0
					k.sphere(Kit.at(cos(a) * 0.3, 1.45, sin(a) * 0.3), Vector3(0.1, 0.08, 0.1), C("c8ccd4"), 6, 4)
				for s2 in [-1, 1]: k.box(Kit.at(s2 * 0.28, 0.33, 0.37), Vector3(0.08, 0.08, 0.04), Kit.glow(C("9ff6ff")), 0.02)
			Data.S_TURRET:
				# tripod in a ring of sandbags, with an ammo box
				for i in 7:
					var a := TAU * i / 7.0
					k.sphere(Kit.rot(cos(a) * 0.45, 0.12, sin(a) * 0.45, -a), Vector3(0.18, 0.13, 0.12), sand.darkened(0.04 * (i % 2)), 8, 5, 0.25)
				for i in 3:
					var a := TAU * i / 3.0
					k.cylinder(Kit.rot(cos(a) * 0.2, 0.42, sin(a) * 0.2, -a, 0, 0.3), 0.04, 0.035, 0.7, C("5a6a80"), 6)
				k.cylinder(Kit.at(0, 0.72, 0), 0.24, 0.28, 0.14, C(["e85d5d", "4f86c6", "5ab07a"][lvl]), 14, true, 0.2)
				k.box(Kit.at(0.32, 0.3, 0.2), Vector3(0.26, 0.2, 0.16), C("6b7f4a"), 0.03, 0.2)
				k.box(Kit.at(0.32, 0.41, 0.2), Vector3(0.27, 0.03, 0.17), C("55673a"), 0.01)
			Data.S_GEN:
				# generator on a frame with wheels, exhaust and a fuel can
				k.box(Kit.at(0, 0.45, 0), Vector3(0.9, 0.62, 0.62), C("f2c14e"), 0.1, 0.3)
				for i in 5: k.box(Kit.at(-0.3 + i * 0.15, 0.5, 0.315), Vector3(0.05, 0.36, 0.01), C("c99a28"), 0.0)
				k.box(Kit.at(0, 0.78, 0), Vector3(0.75, 0.06, 0.5), iron, 0.03)
				for x in [-0.46, 0.46]:
					k.box(Kit.at(x, 0.5, 0), Vector3(0.04, 0.8, 0.66), iron, 0.02)
				k.box(Kit.at(0, 0.92, 0), Vector3(0.96, 0.04, 0.04), iron, 0.01)
				k.cylinder(Kit.at(0.3, 1.05, -0.18), 0.05, 0.06, 0.45, C("5a5a68"), 8)
				k.cylinder(Kit.rot(0.3, 1.3, -0.18, 0, 0.3), 0.07, 0.07, 0.05, C("3a3a48"), 8)
				for x in [-0.32, 0.32]: k.cylinder(Kit.rot(x, 0.12, 0.33, 0, 0, PI * 0.5), 0.12, 0.12, 0.08, C("2f2f38"), 12)
				k.box(Kit.at(-0.15, 0.55, 0.33), Vector3(0.3, 0.2, 0.03), C("2b2d42"), 0.02)
				for i in 3: k.sphere(Kit.at(-0.25 + i * 0.1, 0.55, 0.35), Vector3(0.03, 0.03, 0.02), Kit.glow(C(["5ae85a", "ffd166", "ff5a5a"][i])), 6, 4)
				k.box(Kit.at(-0.62, 0.22, 0.1), Vector3(0.2, 0.36, 0.14), C("e8463c"), 0.04, 0.2)
				k.cylinder(Kit.at(-0.58, 0.44, 0.1), 0.03, 0.03, 0.06, C("2f2f38"), 6)
				k.cylinder(Kit.rot(0.6, 0.15, -0.1, 0, 0, PI * 0.5), 0.14, 0.14, 0.12, C("3a3a48"), 10)
				if lvl > 0: k.box(Kit.at(0, 0.98, 0.1), Vector3(0.3, 0.14, 0.2), C("e8463c"), 0.04)
			Data.S_LIGHT:
				# tall mast with a ladder; the lamp itself is a separate head that turns
				for i in 5:
					var a := TAU * i / 5.0
					k.sphere(Kit.rot(cos(a) * 0.32, 0.1, sin(a) * 0.32, -a), Vector3(0.15, 0.1, 0.11), sand, 6, 4)
				k.box(Kit.at(0, 0.1, 0), Vector3(0.42, 0.2, 0.42), iron, 0.05)
				k.cylinder(Kit.at(0, 1.45, 0), 0.07, 0.09, 2.7, C("5a6a80"), 8)
				for i in 8: k.box(Kit.at(0, 0.35 + i * 0.3, 0.1), Vector3(0.22, 0.03, 0.03), C("c8ccd4"), 0.0)
				k.box(Kit.at(0, 2.8, 0), Vector3(0.5, 0.06, 0.5), iron, 0.02)
				k.cylinder(Kit.rot(0.25, 1.4, -0.1, 0, 0, 0.12), 0.02, 0.02, 2.7, C("2f2f38"), 4)
			Data.S_BENCH:
				# workbench: vice, pegboard with tools, a saw and a toolbox
				k.box(Kit.at(0, 0.62, 0), Vector3(1.0, 0.1, 0.7), wood, 0.03, 0.2)
				for x in [-0.42, 0.42]:
					for z in [-0.28, 0.28]: k.box(Kit.at(x, 0.3, z), Vector3(0.08, 0.6, 0.08), dark, 0.02)
				k.box(Kit.at(0, 0.2, 0), Vector3(0.84, 0.05, 0.6), dark, 0.02)
				k.box(Kit.at(0, 1.08, -0.33), Vector3(1.0, 0.8, 0.05), C("e9c79a"), 0.02)
				for x in [-0.48, 0.48]: k.box(Kit.at(x, 0.85, -0.33), Vector3(0.06, 0.6, 0.06), dark, 0.02)
				k.box(Kit.rot(-0.3, 1.15, -0.29, 0, 0, 0.6), Vector3(0.06, 0.34, 0.03), C("8b5e3c"), 0.01)
				k.box(Kit.rot(-0.24, 1.28, -0.28, 0, 0, 0.6), Vector3(0.16, 0.07, 0.04), C("5a6a80"), 0.01)
				k.box(Kit.rot(0.0, 1.12, -0.29, 0, 0, -0.3), Vector3(0.05, 0.36, 0.02), C("c8ccd4"), 0.01)
				k.cylinder(Kit.at(0.25, 1.2, -0.29), 0.09, 0.09, 0.02, C("c8ccd4"), 10)
				k.box(Kit.at(0.33, 0.73, 0.15), Vector3(0.18, 0.14, 0.15), C("5a6a80"), 0.03)
				k.box(Kit.at(0.33, 0.78, 0.26), Vector3(0.04, 0.04, 0.12), C("5a6a80"), 0.01)
				k.box(Kit.at(-0.2, 0.75, 0.05), Vector3(0.36, 0.16, 0.2), C("e85d5d"), 0.04)
				k.box(Kit.at(-0.2, 0.86, 0.05), Vector3(0.2, 0.04, 0.04), C("2f2f38"), 0.01)
				k.box(Kit.rot(0.05, 0.69, 0.22, 0.4), Vector3(0.42, 0.02, 0.1), C("c8ccd4"), 0.0)
				if lvl > 0: k.sphere(Kit.at(0.42, 1.5, -0.25), Vector3(0.1, 0.08, 0.1), Kit.glow(C("fff2c0")), 8, 5)
			Data.S_MINE:
				# a bundle of festival firecrackers on a pressure plate
				k.cylinder(Kit.at(0, 0.03, 0), 0.32, 0.34, 0.06, dark, 10)
				for i in 7:
					var a := TAU * i / 6.0
					var p := Vector2.ZERO if i == 6 else Vector2(cos(a), sin(a)) * 0.13
					k.cylinder(Kit.at(p.x, 0.2, p.y), 0.065, 0.065, 0.28, C("e8463c") if i % 2 == 0 else C("f26b5b"), 8)
					k.cylinder(Kit.at(p.x, 0.35, p.y), 0.06, 0.02, 0.04, C("fff2d6"), 8)
				k.cylinder(Kit.at(0, 0.2, 0), 0.215, 0.215, 0.07, C("f2c14e"), 14, false)
				k.cylinder(Kit.rot(0, 0.45, 0, 0, 0.5), 0.012, 0.012, 0.22, C("2f2f38"), 4)
				k.sphere(Kit.at(0, 0.55, 0.06), Vector3(0.03, 0.03, 0.03), Kit.glow(C("ffb35c")), 6, 4)
	)

func turret_head(lvl:int) -> ArrayMesh:
	return cached("thead%d" % lvl, func(k:Kit):
		var paint := C(["e85d5d", "4f86c6", "5ab07a"][lvl])
		k.sphere(Kit.at(0, 0.02, -0.02), Vector3(0.24, 0.2, 0.28), C("f6f0e0"), 12, 8, 0.2)
		k.box(Kit.at(0, 0.0, 0.2), Vector3(0.5, 0.36, 0.06), paint, 0.04, 0.2)
		k.box(Kit.at(0, 0.19, 0.2), Vector3(0.52, 0.04, 0.07), paint.darkened(0.2), 0.01)
		for x in ([0.0] if lvl == 0 else [-0.09, 0.09]):
			k.cylinder(Kit.rot(x, 0.0, 0.5, 0, PI * 0.5), 0.05, 0.05, 0.5, C("3a3a48"), 8)
			k.cylinder(Kit.rot(x, 0.0, 0.76, 0, PI * 0.5), 0.07, 0.07, 0.1, C("2a2a36"), 8)
		k.box(Kit.rot(-0.24, -0.08, 0.05, 0, 0, 0.2), Vector3(0.06, 0.22, 0.3), C("c99a28"), 0.01)
		k.sphere(Kit.at(0.15, 0.12, 0.24), Vector3(0.04, 0.04, 0.03), Kit.glow(C("ff5a5a")), 6, 4)
		k.cylinder(Kit.at(-0.12, 0.35, -0.15), 0.01, 0.01, 0.35, C("6b4f3c"), 4)
		k.box(Kit.at(-0.12, 0.46, -0.07), Vector3(0.01, 0.12, 0.16), C("ffd166"), 0.0)
	)

func light_head() -> ArrayMesh:
	## Lamp housing; the lens faces -Z so the node points where it shines.
	return cached("lighthead", func(k:Kit):
		k.cylinder(Kit.rot(0, 0, 0.0, 0, PI * 0.5), 0.26, 0.3, 0.5, C("3d4a5c"), 14, true, 0.2)
		k.cylinder(Kit.rot(0, 0, -0.27, 0, PI * 0.5), 0.31, 0.31, 0.06, C("c8ccd4"), 14)
		k.cylinder(Kit.rot(0, 0, -0.3, 0, PI * 0.5), 0.25, 0.25, 0.02, Kit.glow(C("fff6d0"), 1.0), 14)
		for s2 in [-1, 1]: k.box(Kit.at(s2 * 0.34, -0.05, 0), Vector3(0.05, 0.32, 0.08), C("5a6a80"), 0.01)
		k.box(Kit.at(0, -0.22, 0), Vector3(0.72, 0.05, 0.1), C("5a6a80"), 0.01)
		for i in 4: k.box(Kit.at(0, 0.0, 0.08 + i * 0.05), Vector3(0.62, 0.04, 0.02), C("2f3a4a"), 0.0)
	)

func beam_mesh() -> ArrayMesh:
	## Soft cone of light along -Z, used at night.
	return cached("beam", func(k:Kit):
		k.cylinder(Kit.rot(0, 0, -0.5, 0, -PI * 0.5), 0.2, 1.0, 1.0, Color.WHITE, 16, false)
	)

func coil_top() -> ArrayMesh:
	return cached("coiltop", func(k:Kit):
		k.sphere(Kit.at(0, 0, 0), Vector3(0.22, 0.22, 0.22), Kit.glow(C("9ff6ff")), 12, 8)
	)

func make_structure(kind:int, lvl:int, mask:int) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = wall_mesh(lvl, mask) if kind == Data.S_WALL else structure_mesh(kind, lvl)
	mi.material_override = toon
	mi.name = "Mesh"
	n.add_child(mi)
	if kind == Data.S_TURRET:
		var head := MeshInstance3D.new()
		head.mesh = turret_head(lvl)
		head.material_override = toon
		head.position.y = 0.88
		head.name = "Head"
		n.add_child(head)
	if kind == Data.S_COIL:
		var top := MeshInstance3D.new()
		top.mesh = coil_top()
		top.material_override = glow_mat
		top.position.y = 1.45
		top.name = "Top"
		n.add_child(top)
	if kind == Data.S_LIGHT:
		var reach := 6.0 + lvl   # same radius the simulation uses to dazzle brotados
		# downward flood that covers the whole dazzle zone…
		var fill := SpotLight3D.new()
		fill.position = Vector3(0, 2.9, 0)
		fill.rotation.x = -PI * 0.5
		fill.spot_range = 11.0
		fill.spot_angle = rad_to_deg(atan(reach / 2.9)) + 4.0
		fill.spot_attenuation = 0.4
		fill.light_color = Color("fff1c8")
		fill.light_energy = 0.0
		fill.name = "Lamp"
		n.add_child(fill)
		# …and a turning searchlight head that follows the closest brotado inside it
		var head := Node3D.new()
		head.name = "Head"
		head.position = Vector3(0, 3.1, 0)
		n.add_child(head)
		var hm := MeshInstance3D.new()
		hm.mesh = light_head()
		hm.material_override = toon
		head.add_child(hm)
		var beam_light := SpotLight3D.new()
		beam_light.spot_range = reach + 3.0
		beam_light.spot_angle = 16.0
		beam_light.light_color = Color("fff6dc")
		beam_light.light_energy = 0.0
		beam_light.name = "Beam"
		head.add_child(beam_light)
		var cone := MeshInstance3D.new()
		cone.mesh = beam_mesh()
		cone.material_override = beam_mat
		cone.scale = Vector3(1.0, 1.0, reach)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.name = "Cone"
		head.add_child(cone)
		# faint ring on the ground marking where brotados get dazzled
		var zone := MeshInstance3D.new()
		zone.mesh = blob_quad
		zone.material_override = zone_mat
		zone.scale = Vector3(reach * 2.0, 1, reach * 2.0)
		zone.position.y = 0.05
		zone.name = "Zone"
		zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(zone)
	var bar := MeshInstance3D.new()
	bar.mesh = bar_quad
	bar.material_override = bar_mat
	bar.position.y = 1.9 if kind != Data.S_LIGHT else 3.6
	bar.scale = Vector3(0.8, 1, 1)
	bar.visible = false
	bar.name = "Bar"
	bar.set_instance_shader_parameter("fill", Color("7be07b"))
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(bar)
	return n

func turret_fired(cell:int, dir:Vector3) -> Vector3:
	## Snap a turret's head onto its target, kick it back and return the barrel tip.
	if not structs.has(cell) or not struct_info.has(cell) or struct_info[cell][0] != Data.S_TURRET: return Vector3.INF
	var n:Node3D = structs[cell]
	var head:Node3D = n.get_node("Head")
	head.rotation.y = atan2(dir.x, dir.z)
	n.set_meta("kick", 1.0)
	return n.position + Vector3(0, 0.88, 0) + Vector3(dir.x, 0, dir.z).normalized() * 0.82

func ghost_mesh(kind:int) -> Mesh:
	if kind == Data.S_WALL: return wall_mesh(0, 0)
	return structure_mesh(kind, 0)

# ================================================================== loot, banners, balloons
func loot_mesh(kind:int) -> ArrayMesh:
	return cached("loot%d" % kind, func(k:Kit):
		match kind:
			0:
				k.box(Kit.at(0, 0.5, 0), Vector3(1.4, 0.95, 0.9), C("4f9a6a"), 0.08, 0.3)
				k.box(Kit.at(0, 0.97, 0), Vector3(1.3, 0.02, 0.8), C("1f2a22"), 0.0)
				for x in [-0.5, 0.5]: k.cylinder(Kit.rot(x, 0.1, 0.4, 0, 0, PI * 0.5), 0.08, 0.08, 0.06, C("2f2f38"), 8)
				k.box(Kit.at(0, 0.6, 0.46), Vector3(0.5, 0.2, 0.02), C("ffd166"), 0.01)
			1:
				var body := C(["ef8f8f", "8fc3ef", "f2d27a"][0])
				k.box(Kit.at(0, 0.55, 0), Vector3(1.7, 0.6, 3.2), body.darkened(0.15), 0.22, 0.25, 1)
				k.box(Kit.at(0, 1.05, -0.15), Vector3(1.45, 0.55, 1.7), body.darkened(0.2), 0.2, 0.0, 1)
				k.box(Kit.at(0, 1.07, -0.15), Vector3(1.5, 0.38, 1.5), C("6f8aa0"), 0.12)
				for x in [-0.82, 0.82]:
					for z in [-1.0, 1.0]: k.cylinder(Kit.rot(x, 0.32, z, 0, 0, PI * 0.5), 0.32, 0.32, 0.26, C("2f2f38"), 12)
				k.box(Kit.rot(0.3, 1.33, 0.5, 0.3), Vector3(0.6, 0.1, 0.5), C("8b5e3c"), 0.03)
				k.box(Kit.at(0, 0.86, -1.1), Vector3(1.4, 0.02, 0.75), C("1f1a22"), 0.0)
			2:
				for i in 3:
					k.box(Kit.rot(0, 0.1 + i * 0.2, 0, 0.1 * i), Vector3(1.1, 0.06, 1.1), C("d9a06a"), 0.01)
					for z in [-0.45, 0.0, 0.45]: k.box(Kit.rot(0, 0.04 + i * 0.2, z, 0.1 * i), Vector3(1.1, 0.08, 0.14), C("b8834f"), 0.01)
				k.box(Kit.at(0.1, 0.75, 0), Vector3(0.6, 0.4, 0.5), C("d49a5c"), 0.05, 0.2)
			3:
				k.box(Kit.at(0, 0.4, 0), Vector3(0.9, 0.8, 0.8), C("e85d5d"), 0.08, 0.25)
				for i in 3: k.box(Kit.at(-0.3 + i * 0.3, 0.4, 0.41), Vector3(0.12, 0.78, 0.02), C("fff2d6"), 0.0)
				k.sphere(Kit.at(0, 0.85, 0), Vector3(0.16, 0.08, 0.16), C("f2c14e"), 8, 4)
			4:
				k.box(Kit.at(0, 0.6, 0), Vector3(0.12, 1.2, 0.12), C("5a6a80"), 0.03)
				k.box(Kit.at(0, 1.15, 0.05), Vector3(0.7, 0.6, 0.3), C("f6f8fa"), 0.06, 0.2)
				k.box(Kit.at(0, 1.15, 0.21), Vector3(0.3, 0.08, 0.02), C("e8463c"), 0.0)
				k.box(Kit.at(0, 1.15, 0.21), Vector3(0.08, 0.3, 0.02), C("e8463c"), 0.0)
			5:
				k.box(Kit.at(0, 0.28, 0), Vector3(0.9, 0.55, 0.55), C("6b7f4a"), 0.05, 0.25)
				k.box(Kit.at(0, 0.58, 0), Vector3(0.92, 0.08, 0.57), C("55673a"), 0.02)
				k.box(Kit.at(0, 0.3, 0.28), Vector3(0.4, 0.12, 0.02), C("f2c14e"), 0.0)
	)

func lid_mesh(kind:int) -> ArrayMesh:
	## The part that opens while someone searches: a container lid or a car boot.
	return cached("lid%d" % kind, func(k:Kit):
		if kind == 0:
			k.box(Kit.at(0, 0.03, 0.47), Vector3(1.45, 0.08, 0.95), C("3f7a54"), 0.03)
			k.box(Kit.at(0, 0.08, 0.85), Vector3(0.4, 0.05, 0.06), C("2f5a3e"), 0.01)
		else:
			var body := C("ef8f8f").darkened(0.15)
			k.box(Kit.at(0, 0.02, -0.42), Vector3(1.55, 0.08, 0.86), body, 0.05)
			k.box(Kit.at(0, -0.1, -0.86), Vector3(1.5, 0.28, 0.06), body.darkened(0.08), 0.03)
			for x in [-0.55, 0.55]: k.box(Kit.at(x, -0.12, -0.9), Vector3(0.22, 0.1, 0.03), Kit.glow(C("ff5a5a"), 0.4), 0.01)
	)

func piece_mesh(i:int) -> ArrayMesh:
	return cached("piece%d" % i, func(k:Kit):
		var c := C(Data.PIECES[i].color)
		match i:
			0:
				k.box(Kit.at(0, 0.4, 0), Vector3(0.7, 0.8, 0.35), C("dfe6ee"), 0.06, 0.25)
				k.box(Kit.at(0, 0.45, 0.18), Vector3(0.55, 0.55, 0.04), c, 0.03)
				for j in 3: k.box(Kit.at(-0.15 + j * 0.15, 0.55, 0.21), Vector3(0.08, 0.16, 0.03), Kit.glow(C("ffd166")), 0.01)
				k.box(Kit.rot(0.1, 0.3, 0.21, 0, 0, 0.6), Vector3(0.25, 0.04, 0.03), C("e8463c"), 0.0)
			1:
				k.cylinder(Kit.at(0, 0.3, 0), 0.4, 0.4, 0.5, C("8b5e3c"), 14, true, 0.2)
				for j in 10:
					var a := TAU * j / 10.0
					k.sphere(Kit.at(cos(a) * 0.42, 0.45, sin(a) * 0.42), Vector3(0.08, 0.1, 0.08), Kit.glow(C(["ffd166", "ff6b6b", "4cc9f0"][j % 3])), 6, 4)
			2:
				for sx in [-0.22, 0.22]:
					k.box(Kit.at(sx, 0.45, 0), Vector3(0.4, 0.9, 0.4), C("2f2f38"), 0.06, 0.2)
					k.cylinder(Kit.rot(sx, 0.55, 0.2, 0, PI * 0.5), 0.13, 0.13, 0.04, c, 14)
					k.cylinder(Kit.rot(sx, 0.25, 0.2, 0, PI * 0.5), 0.07, 0.07, 0.04, c, 10)
			3:
				k.cylinder(Kit.at(0, 0.45, 0), 0.3, 0.3, 0.9, c, 14, true, 0.25)
				for y in [0.2, 0.7]: k.cylinder(Kit.at(0, y, 0), 0.31, 0.31, 0.05, C("b8433a"), 14, false)
				k.cylinder(Kit.at(0.12, 0.93, 0), 0.06, 0.06, 0.08, C("2f2f38"), 8)
	)

func sparkle_mesh() -> ArrayMesh:
	return cached("sparkle", func(k:Kit):
		k.box(Kit.rot(0, 0, 0, PI * 0.25, PI * 0.25), Vector3(0.22, 0.22, 0.22), Kit.glow(C("fff3b0")), 0.06)
	)

func beacon_mesh(site:int, claimed:bool) -> ArrayMesh:
	return cached("beacon%d%s" % [site, claimed], func(k:Kit):
		k.cylinder(Kit.at(0, 0.15, 0), 0.55, 0.62, 0.3, C("cfc5b8"), 10, true, 0.25)
		k.cylinder(Kit.at(0, 1.8, 0), 0.06, 0.06, 3.3, C("6b4f3c"), 8)
		k.sphere(Kit.at(0, 3.5, 0), Vector3(0.12, 0.12, 0.12), C("f2c14e") if claimed else C("8a8a8a"), 8, 5)
		k.sphere(Kit.at(0, 0.45, 0), Vector3(0.18, 0.18, 0.18), Kit.glow(C(Data.SITES[site].color)) if claimed else C("6a6a6a"), 8, 5)
	)

func banner_mesh(site:int, claimed:bool) -> ArrayMesh:
	return cached("banner%d%s" % [site, claimed], func(k:Kit):
		var c := C(Data.SITES[site].color) if claimed else C("9a9a9a")
		k.box(Kit.at(0.55, 0, 0), Vector3(1.0, 0.75, 0.03), c, 0.02)
		k.box(Kit.at(0.55, -0.42, 0), Vector3(1.0, 0.1, 0.035), C("fff2d6") if claimed else C("7a7a7a"), 0.0)
		if claimed: k.sphere(Kit.at(0.55, 0.02, 0.02), Vector3(0.18, 0.18, 0.02), C("fff2d6"), 10, 4)
	)

func balloon_mesh() -> ArrayMesh:
	return cached("balloon", func(k:Kit):
		for i in 8:
			var a := TAU * i / 8.0
			var c := C(["e85d5d", "fff2d6", "4cc9f0", "fff2d6"][i % 4])
			k.sphere(Kit.rot(0, 4.6, 0, a), Vector3(1.6, 1.9, 0.75), c, 10, 8)
		k.cylinder(Kit.at(0, 2.6, 0), 0.5, 0.25, 0.4, C("e85d5d"), 10)
		for i in 4:
			var a := TAU * i / 4.0 + 0.4
			k.cylinder(Kit.rot(cos(a) * 0.4, 1.7, sin(a) * 0.4, 0, 0.1), 0.015, 0.015, 1.6, C("6b4f3c"), 4)
		k.box(Kit.at(0, 0.45, 0), Vector3(1.0, 0.9, 1.0), C("d49a5c"), 0.08, 0.25)
		for i in 2: k.box(Kit.at(0, 0.45, -0.3 + i * 0.6), Vector3(1.02, 0.12, 0.08), C("8b5e3c"), 0.02)
		k.sphere(Kit.at(0, 1.0, 0), Vector3(0.2, 0.12, 0.2), Kit.glow(C("ffd166")), 8, 4)
	)

# ================================================================== lifecycle
func prewarm():
	## Build shared meshes up front so the first horde does not hitch.
	for k in Data.ENEMIES.size():
		for v in 4: zombie_parts(k, v)
	for r in 4:
		hero_head(r)
		for slot in 4: hero_torso(r, slot)
	for g in Data.WEAPONS.size(): gun_mesh(g)
	for k in range(1, Data.STRUCTURES.size()):
		for lvl in Data.STRUCTURES[k].hp.size(): structure_mesh(k, lvl)
	for lvl in 3:
		turret_head(lvl)
		for mask in 16: wall_mesh(lvl, mask)

func build_static():
	prewarm()
	for i in Map.LOOT.size():
		var l:Dictionary = Map.LOOT[i]
		var n := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = loot_mesh(l.kind)
		mi.material_override = toon
		mi.name = "Mesh"
		n.add_child(mi)
		if l.kind <= 1:
			var lid := Node3D.new()
			lid.name = "Lid"
			lid.position = Vector3(0, 1.0, -0.45) if l.kind == 0 else Vector3(0, 0.86, -0.68)
			var lm := MeshInstance3D.new()
			lm.mesh = lid_mesh(l.kind)
			lm.material_override = toon
			lm.name = "LidMesh"
			lid.add_child(lm)
			mi.add_child(lid)
		var sp := MeshInstance3D.new()
		sp.mesh = sparkle_mesh()
		sp.material_override = glow_mat
		sp.position.y = 2.0 if l.kind == 1 else 1.6
		sp.name = "Sparkle"
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(sp)
		n.position = Vector3(l.p.x, 0, l.p.y)
		n.rotation.y = Map.loot_yaw(i)
		add_child(n)
		loot_nodes.append(n)
	for i in Map.SITES.size():
		var s:Dictionary = Map.SITES[i]
		var n := Node3D.new()
		n.position = Vector3(s.beacon.x, 0, s.beacon.y)
		var mi := MeshInstance3D.new()
		mi.name = "Pole"
		mi.material_override = toon
		n.add_child(mi)
		var flag := MeshInstance3D.new()
		flag.name = "Flag"
		flag.material_override = sway
		flag.position = Vector3(0, 2.9, 0)
		n.add_child(flag)
		var bar := MeshInstance3D.new()
		bar.mesh = bar_quad
		bar.material_override = bar_mat
		bar.position.y = 3.9
		bar.scale = Vector3(1.3, 1.3, 1)
		bar.name = "Bar"
		bar.set_instance_shader_parameter("fill", Color(Data.SITES[i].color))
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(bar)
		var light := OmniLight3D.new()
		light.position.y = 1.0
		light.omni_range = 6.0
		light.light_color = Color(Data.SITES[i].color)
		light.light_energy = 0.0
		light.name = "Light"
		n.add_child(light)
		var label := Label3D.new()
		label.text = Data.SITES[i].name
		label.font_size = 64
		label.outline_size = 14
		label.pixel_size = 0.0085
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = 4.4
		label.outline_modulate = Color(0.1, 0.08, 0.14, 0.9)
		label.name = "Label"
		n.add_child(label)
		add_child(n)
		beacons.append(n)
		set_beacon(i, false, 0.0)
	for i in Data.PIECES.size():
		var n := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = piece_mesh(i)
		mi.material_override = toon_char
		mi.name = "Mesh"
		n.add_child(mi)
		var sp := MeshInstance3D.new()
		sp.mesh = sparkle_mesh()
		sp.material_override = glow_mat
		sp.position.y = 1.5
		sp.name = "Sparkle"
		n.add_child(sp)
		var l := Label3D.new()
		l.text = Data.PIECES[i].name
		l.font_size = 48
		l.outline_size = 12
		l.pixel_size = 0.006
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position.y = 2.0
		l.modulate = Color(Data.PIECES[i].color).lightened(0.3)
		l.name = "Label"
		n.add_child(l)
		n.visible = false
		add_child(n)
		piece_nodes.append(n)
	ghost = MeshInstance3D.new()
	ghost.material_override = ghost_mat
	ghost.visible = false
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost)

func set_beacon(i:int, claimed:bool, frac:float):
	var n:Node3D = beacons[i]
	# the neighbourhood comes back to life where the team has taken over
	if n.has_node("Story"): n.get_node("Story").queue_free()
	if claimed:
		var story := Node3D.new()
		story.name = "Story"
		n.add_child(story)
		var face:Vector2 = Map.SITES[i].face
		for j in 2:
			var r := make_person((i + j) % 3)
			r.position = Vector3(face.x * 2.2 + (j - 0.5) * 1.6 * face.y, 0, face.y * 2.2 + (j - 0.5) * 1.6 * face.x)
			r.rotation.y = atan2(-face.x, -face.y)
			story.add_child(r)
		var bunting := MeshInstance3D.new()
		bunting.mesh = cached("site_bunting", func(k:Kit):
			for q in 9:
				var x := -2.0 + q * 0.5
				k.box(Kit.rot(x, 3.2 - 0.25 * sin(q * PI / 8.0), 0, PI * 0.25), Vector3(0.22, 0.3, 0.02), C(["ff6b6b", "ffd166", "06d6a0", "4cc9f0", "f78fb3"][q % 5]), 0.0)
			k.box(Kit.at(0, 3.35, 0), Vector3(4.4, 0.02, 0.02), C("3b3b48"), 0.0))
		bunting.material_override = sway
		bunting.rotation.y = atan2(face.y, face.x)
		bunting.position = Vector3(face.x * 1.2, 0, face.y * 1.2)
		story.add_child(bunting)
	(n.get_node("Pole") as MeshInstance3D).mesh = beacon_mesh(i, claimed)
	(n.get_node("Flag") as MeshInstance3D).mesh = banner_mesh(i, claimed)
	(n.get_node("Flag") as MeshInstance3D).rotation.z = 0.0 if claimed else -0.5
	(n.get_node("Label") as Label3D).modulate = Color(Data.SITES[i].color).lightened(0.3) if claimed else Color(0.85, 0.85, 0.85)
	(n.get_node("Label") as Label3D).text = Data.SITES[i].name + (" ✓" if claimed else "")
	var bar:MeshInstance3D = n.get_node("Bar")
	bar.visible = claimed and frac < 0.999
	bar.set_instance_shader_parameter("value", frac)
	n.set_meta("claimed", claimed)

func clear_all():
	for d in [heroes, horde, structs, drops, people, bundles]:
		for n in d.values(): n.queue_free()
		d.clear()
	for n in community: n.queue_free()
	community.clear()
	for p in projectiles: p.queue_free()
	projectiles.clear()
	for i in beacons.size(): set_beacon(i, false, 0.0)
	for n in loot_nodes: n.visible = true
	for id in job_nodes: job_nodes[id].queue_free()
	job_nodes.clear()
	for n in piece_nodes:
		n.visible = false
		if n.has_meta("info"): n.remove_meta("info")
	ghost.visible = false

# ================================================================== snapshot reconciliation
var hero_target := {}
var horde_target := {}
var horde_info := {}
var struct_info := {}
var people_target := {}
var drop_info := {}

func apply(s:Dictionary, me:int):
	local_id = me
	# heroes
	for id in heroes.keys():
		if not s.pl.has(id):
			heroes[id].queue_free()
			heroes.erase(id)
	for id in s.pl:
		var p:Dictionary = s.pl[id]
		if not heroes.has(id):
			var r := make_hero(p.role, p.slot)
			add_child(r)
			r.position = Vector3(p.p.x, 0, p.p.y)
			r.label = Label3D.new()
			r.label.text = p.name
			r.label.font_size = 48
			r.label.outline_size = 12
			r.label.pixel_size = 0.0068
			r.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			r.label.position.y = 2.55
			r.label.modulate = Color(SLOT_COLORS[p.slot % 4]).lightened(0.25)
			r.label.outline_modulate = Color(0.1, 0.08, 0.14, 0.9)
			r.label.no_depth_test = true
			r.add_child(r.label)
			heroes[id] = r
		var r:Rig = heroes[id]
		set_gun(r, p.gun)
		hero_target[id] = p
	# zombies
	var en:PackedFloat32Array = s.en
	var seen := {}
	for i in range(0, en.size(), 8):
		var key := int(en[i])
		seen[key] = true
		if not horde.has(key):
			var z := make_zombie(int(en[i + 1]), key % 4)
			add_child(z)
			z.position = Vector3(en[i + 2], 0, en[i + 3])
			z.yaw = en[i + 5]
			z.spawn_t = 0.0
			horde[key] = z
		horde_target[key] = Vector3(en[i + 2], 0, en[i + 3])
		horde_info[key] = [en[i + 4], en[i + 5], int(en[i + 6]), en[i + 7]]
	for key in horde.keys():
		if not seen.has(key):
			horde[key].queue_free()
			horde.erase(key)
			horde_target.erase(key)
			horde_info.erase(key)
	# structures
	var st:PackedInt32Array = s.st
	var cells := {}
	for i in range(0, st.size(), 8): cells[st[i]] = [st[i + 1], st[i + 2], st[i + 3], st[i + 4], st[i + 5], st[i + 6]]
	var changed := false
	for cell in structs.keys():
		if not cells.has(cell) or struct_info[cell][0] != cells[cell][0] or struct_info[cell][1] != cells[cell][1]:
			structs[cell].queue_free()
			structs.erase(cell)
			changed = true
	for cell in cells:
		if not structs.has(cell): changed = true
	if changed:
		for cell in structs.keys():
			if cells[cell][0] == Data.S_WALL:
				structs[cell].queue_free()
				structs.erase(cell)
	for cell in cells:
		var info:Array = cells[cell]
		if not structs.has(cell):
			var mask := 0
			if info[0] == Data.S_WALL:
				var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
				for d in 4:
					var nc:int = cell + dirs[d].x + dirs[d].y * nav_helper.W
					if cells.has(nc) and cells[nc][0] == Data.S_WALL: mask |= 1 << d
			var n := make_structure(info[0], info[1], mask)
			var c := nav_helper.center(cell)
			n.position = Vector3(c.x, 0, c.y)
			add_child(n)
			structs[cell] = n
			if not struct_info.has(cell) or struct_info[cell][0] != info[0]:
				n.scale = Vector3(0.2, 0.2, 0.2)
		struct_info[cell] = info
	for cell in struct_info.keys():
		if not cells.has(cell): struct_info.erase(cell)
	# loot
	for i in loot_nodes.size():
		var avail:bool = s.lo[i]
		var n:Node3D = loot_nodes[i]
		n.get_node("Sparkle").visible = avail
		(n.get_node("Mesh") as MeshInstance3D).set_instance_shader_parameter("itint", Color.WHITE if avail else Color(0.62, 0.6, 0.66))
	# banners
	for i in s.si.size():
		var info:Array = s.si[i]
		var frac:float = info[1] / maxf(1.0, info[2])
		if beacons[i].get_meta("claimed", false) != info[0]: set_beacon(i, info[0], frac)
		else:
			var bar:MeshInstance3D = beacons[i].get_node("Bar")
			bar.visible = info[0] and frac < 0.999
			bar.set_instance_shader_parameter("value", frac)
	# survivors walking or trapped
	var sv_seen := {}
	for sv in s.sv:
		var id:int = sv[0]
		sv_seen[id] = true
		if not people.has(id):
			var r := make_person(sv[3])
			add_child(r)
			r.position = Vector3(sv[1], 0, sv[2])
			var l := Label3D.new()
			l.text = "!"
			l.font_size = 96
			l.outline_size = 18
			l.pixel_size = 0.008
			l.modulate = Color("ffd166")
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.position.y = 2.6
			l.no_depth_test = true
			r.add_child(l)
			r.label = l
			people[id] = r
		people_target[id] = [Vector3(sv[1], 0, sv[2]), sv[4]]
	for id in people.keys():
		if not sv_seen.has(id):
			people[id].queue_free()
			people.erase(id)
			people_target.erase(id)
	# community members living at the base
	while community.size() < s.cm.size():
		var idx := community.size()
		var r := make_person(s.cm[idx])
		add_child(r)
		var spots := [Vector3(0, 6.15, -0.5), Vector3(-4.0, 0, 3.4), Vector3(3.2, 0, 2.6), Vector3(0.5, 6.15, -0.1), Vector3(-3.0, 0, -4.2), Vector3(4.2, 0, -3.8)]
		if s.cm[idx] == 2: r.position = spots[0] if idx % 2 == 0 else spots[3]
		else: r.position = spots[1 + idx % 5]
		r.rotation.y = randf() * TAU if s.cm[idx] != 2 else 0.0
		community.append(r)
	while community.size() > s.cm.size(): community.pop_back().queue_free()
	var cp:Array = s.get("cp", [])
	for idx in community.size():
		var post:int = cp[idx] if idx < cp.size() else -1
		var r:Rig = community[idx]
		if r.get_meta("post", -2) == post: continue
		r.set_meta("post", post)
		if post >= 0:
			var b:Vector2 = Map.SITES[post].beacon
			var f:Vector2 = Map.SITES[post].face
			r.position = Vector3(b.x - f.x * 1.5 + f.y * (idx % 2 - 0.5) * 2.0, 0, b.y - f.y * 1.5 + f.x * (idx % 2 - 0.5) * 2.0)
			r.rotation.y = atan2(f.x, f.y)
		else:
			var spots := [Vector3(0, 6.15, -0.5), Vector3(-4.0, 0, 3.4), Vector3(3.2, 0, 2.6), Vector3(0.5, 6.15, -0.1), Vector3(-3.0, 0, -4.2), Vector3(4.2, 0, -3.8)]
			r.position = (spots[0] if idx % 2 == 0 else spots[3]) if s.cm[idx] == 2 else spots[1 + idx % 5]
	# balloons
	var dr_seen := {}
	for d in s.dr:
		var id:int = d[0]
		dr_seen[id] = true
		if not drops.has(id):
			var mi := MeshInstance3D.new()
			mi.mesh = balloon_mesh()
			mi.material_override = toon
			add_child(mi)
			drops[id] = mi
		drop_info[id] = d
	for id in drops.keys():
		if not dr_seen.has(id):
			drops[id].queue_free()
			drops.erase(id)
	# pieces of the verbena
	var pcs:Array = s.get("pc", [])
	for i in mini(pcs.size(), piece_nodes.size()):
		piece_nodes[i].set_meta("info", pcs[i])
	# jobs: search markers, crates to carry, zones to hold
	var job_seen := {}
	for j in s.get("jobs", []):
		if j[5] != 1 or not j[12]: continue
		job_seen[j[0]] = true
		if not job_nodes.has(j[0]):
			var n := Node3D.new()
			var mi := MeshInstance3D.new()
			mi.name = "Mesh"
			mi.material_override = toon_char if j[1] in ["transporte", "relevo"] else glow_mat
			mi.mesh = cached("job_" + j[1], func(k:Kit):
				match j[1]:
					"transporte":
						k.box(Kit.at(0, 0.35, 0), Vector3(0.8, 0.7, 0.7), C("d49a5c"), 0.06, 0.25)
						k.box(Kit.at(0, 0.71, 0), Vector3(0.82, 0.06, 0.72), C("8b5e3c"), 0.02)
						k.box(Kit.at(0, 0.35, 0.36), Vector3(0.3, 0.3, 0.02), C("4cc9f0"), 0.0)
					"relevo":
						k.box(Kit.at(0, 0.35, 0), Vector3(0.6, 0.7, 0.45), C("8f9fb5"), 0.06, 0.25)
						for q in 2: k.cylinder(Kit.at(-0.12 + q * 0.24, 0.85, 0), 0.07, 0.07, 0.3, C("e0a63a"), 8)
						k.sphere(Kit.at(0, 0.4, 0.24), Vector3(0.1, 0.1, 0.04), Kit.glow(C("9ff6ff")), 8, 4)
					"busqueda":
						k.box(Kit.rot(0, 1.4, 0, PI * 0.25, PI * 0.25), Vector3(0.3, 0.3, 0.3), Kit.glow(C("9ff6c8")), 0.08)
						k.cylinder(Kit.at(0, 0.6, 0), 0.03, 0.03, 1.2, Kit.glow(C("9ff6c8")), 6)
					"defensa":
						for q in 12:
							var a := TAU * q / 12.0
							k.cylinder(Kit.at(cos(a) * 4.0, 0.4, sin(a) * 4.0), 0.08, 0.08, 0.8, Kit.glow(C("ffb35c")), 6)
			)
			n.add_child(mi)
			add_child(n)
			job_nodes[j[0]] = n
		job_nodes[j[0]].set_meta("info", j)
	for id in job_nodes.keys():
		if not job_seen.has(id):
			job_nodes[id].queue_free()
			job_nodes.erase(id)
	# supply bundles left on the porch
	var bu_seen := {}
	for b in s.get("bu", []):
		bu_seen[b[0]] = true
		if not bundles.has(b[0]):
			var mi := MeshInstance3D.new()
			mi.mesh = cached("bundle", func(k:Kit):
				k.box(Kit.at(0, 0.3, 0), Vector3(0.75, 0.6, 0.6), C("d49a5c"), 0.06, 0.25)
				k.box(Kit.at(0, 0.3, 0), Vector3(0.12, 0.62, 0.62), C("e85d5d"), 0.02)
				k.box(Kit.at(0, 0.3, 0), Vector3(0.77, 0.62, 0.12), C("e85d5d"), 0.02)
				k.sphere(Kit.at(0, 0.66, 0), Vector3(0.14, 0.09, 0.14), C("ff6b8b"), 8, 4)
				k.box(Kit.at(0.25, 0.42, 0.31), Vector3(0.14, 0.04, 0.02), C("ffffff"), 0.0)
				k.box(Kit.at(0.25, 0.42, 0.31), Vector3(0.04, 0.14, 0.02), C("ffffff"), 0.0))
			mi.material_override = toon
			mi.position = Vector3(b[1], 0, b[2])
			mi.scale = Vector3.ONE * 0.2
			add_child(mi)
			bundles[b[0]] = mi
	for id in bundles.keys():
		if not bu_seen.has(id):
			bundles[id].queue_free()
			bundles.erase(id)
	# projectiles
	var pr:PackedFloat32Array = s.pr
	var count := pr.size() / 4
	while projectiles.size() < count:
		var mi := MeshInstance3D.new()
		mi.material_override = toon
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		projectiles.append(mi)
	for i in projectiles.size():
		var mi:MeshInstance3D = projectiles[i]
		mi.visible = i < count
		if i >= count: continue
		var kind := int(pr[i * 4 + 3])
		mi.mesh = cached("proj%d" % kind, func(k:Kit):
			if kind == 0:
				k.sphere(Kit.at(0, 0, 0), Vector3(0.22, 0.2, 0.22), Kit.glow(C("b86ae8"), 0.6), 10, 6)
				k.sphere(Kit.at(0.1, 0.1, 0.05), Vector3(0.08, 0.08, 0.08), C("e8b0ff"), 6, 4)
			else:
				k.cylinder(Kit.rot(0, 0, 0, 0, 0, PI * 0.5), 0.08, 0.08, 0.36, C("e8463c"), 8)
				k.sphere(Kit.at(0.2, 0, 0), Vector3(0.06, 0.06, 0.06), Kit.glow(C("ffd166")), 6, 4)
		)
		mi.position = Vector3(pr[i * 4], pr[i * 4 + 1], pr[i * 4 + 2])
		mi.rotation = Vector3(Time.get_ticks_msec() * 0.01, Time.get_ticks_msec() * 0.007, 0)

func flash_zombie(key:int):
	if horde.has(key): horde[key].hit_flash = 1.0

# ================================================================== per frame
func update(dt:float, t:float, s:Dictionary, local_pos:Vector3, local_aim:Vector2, night_amount:float, blackout:bool):
	night = night_amount
	var searching := {}
	for id in heroes:
		if not hero_target.has(id): continue
		var p:Dictionary = hero_target[id]
		var r:Rig = heroes[id]
		var target := Vector3(p.p.x, 0, p.p.y)
		if id == local_id and local_pos != Vector3.INF: target = local_pos
		var before := r.position
		r.position = target if id == local_id else r.position.lerp(target, 1.0 - exp(-14.0 * dt))
		var vel := (r.position - before) / maxf(dt, 0.0001)
		# smoothed ground velocity: per-frame deltas are noisy (network, tick rate)
		r.ground_vel = r.ground_vel.lerp(Vector2(vel.x, vel.z), 1.0 - exp(-12.0 * dt))
		if r.ground_vel.length() > 12.0: r.ground_vel = r.ground_vel.normalized() * 12.0
		var aim:Vector2 = local_aim if id == local_id and local_aim != Vector2.ZERO else p.aim
		if p.fire or (id == local_id and local_firing) or r.swing > 0: r.fire_t = 0.9
		r.fire_t = maxf(0.0, r.fire_t - dt)
		var aiming:bool = p.st == 0 and r.fire_t > 0
		# Walk facing where you go (forward with the camera shows your back);
		# turn to the cursor only while shooting or swinging the pan.
		var rolling:bool = local_rolling if id == local_id else p.roll
		var hk:String = p.get("hk", "")
		r.rummage = p.use and hk.begins_with("lo") and p.st == 0
		if r.rummage:
			var li := int(hk.substr(2))
			if li >= 0 and li < Map.LOOT.size():
				searching[li] = true
				r.face(Map.LOOT[li].p - Vector2(r.position.x, r.position.z), dt, 12.0)
		if r.rummage: pass
		elif p.st != 0: r.face(r.ground_vel, dt)
		elif rolling: r.face(r.ground_vel, dt, 30.0)
		elif aiming: r.face(aim, dt, 22.0)
		elif r.ground_vel.length() > 0.5: r.face(r.ground_vel, dt, 10.0)
		r.animate_hero(dt, t, r.ground_vel, aiming, p.fire, p.st, rolling, p.rl > 0, p.use and p.hold != "")
		r.flashlight.light_energy = (2.2 if p.st == 0 else 0.0) * smoothstep(0.3, 0.9, night_amount)
		r.label.visible = id != local_id
		if p.dmg > 0.25: r.hit_flash = 0.7
	for key in horde:
		var z:Rig = horde[key]
		var target:Vector3 = horde_target[key]
		var info:Array = horde_info[key]
		var before := z.position
		z.position = z.position.lerp(target, 1.0 - exp(-12.0 * dt))
		var moving := clampf((z.position - before).length() / maxf(dt, 0.0001) / 2.0, 0.0, 1.0)
		var want:float = info[1]
		z.yaw = lerp_angle(z.yaw, PI * 0.5 - want, 1.0 - exp(-10.0 * dt))
		z.rotation.y = z.yaw
		z.spawn_t += dt
		var grow := clampf(z.spawn_t * 3.0, 0.0, 1.0)
		z.body.scale = Vector3.ONE * (0.4 + 0.6 * grow)
		z.animate_zombie(dt, t, moving, info[2])
		if info[3] > 0.05:
			z.hit_flash = 1.0
			z.bar_t = 2.5
		z.bar_t = maxf(0.0, z.bar_t - dt)
		var hp:float = info[0]
		# only tough enemies keep a bar; the rest show it briefly after being hit
		z.bar.visible = hp < 0.999 and (z.bar_t > 0 or z.kind == 2) and z.kind != 7
		if z.bar.visible:
			z.bar.set_instance_shader_parameter("value", hp)
			z.bar.set_instance_shader_parameter("fill", Color("ff6b6b") if info[2] & 8 == 0 else Color("ffd166"))
	for cell in structs:
		var n:Node3D = structs[cell]
		var info:Array = struct_info[cell]
		n.scale = n.scale.lerp(Vector3.ONE, 1.0 - exp(-10.0 * dt))
		var frac:float = float(info[2]) / maxf(1.0, info[3])
		var bar:MeshInstance3D = n.get_node("Bar")
		bar.visible = frac < 0.98 and info[0] != Data.S_MINE
		bar.set_instance_shader_parameter("value", frac)
		var mesh:MeshInstance3D = n.get_node("Mesh")
		mesh.set_instance_shader_parameter("itint", Color(1, 1, 1).lerp(Color(0.65, 0.58, 0.55), 1.0 - frac))
		var on:bool = info[5] == 1
		if info[0] == Data.S_TURRET:
			var head:Node3D = n.get_node("Head")
			head.rotation.y = lerp_angle(head.rotation.y, PI * 0.5 - deg_to_rad(info[4]), 1.0 - exp(-12.0 * dt))
			var kick:float = n.get_meta("kick", 0.0)
			n.set_meta("kick", maxf(0.0, kick - dt * 8.0))
			head.position = Vector3(0, 0.88, 0) - head.basis.z * 0.1 * kick
		if info[0] == Data.S_COIL:
			var top:MeshInstance3D = n.get_node("Top")
			top.set_instance_shader_parameter("itint", Color(1, 1, 1) if on else Color(0.3, 0.3, 0.35))
			top.scale = Vector3.ONE * (1.0 + 0.08 * sin(t * 9.0 + cell))
		if info[0] == Data.S_LIGHT:
			var lit := night_amount if on else 0.0
			(n.get_node("Lamp") as SpotLight3D).light_energy = 2.2 * lit
			var lhead:Node3D = n.get_node("Head")
			(lhead.get_node("Beam") as SpotLight3D).light_energy = 5.0 * lit
			lhead.get_node("Cone").visible = lit > 0.15
			var zone:MeshInstance3D = n.get_node("Zone")
			zone.visible = lit > 0.15
			zone.set_instance_shader_parameter("itint", Color(1, 1, 1, lit))
			# aim at the nearest brotado inside the zone, otherwise sweep slowly
			var base := n.position
			var reach:float = 6.0 + float(info[1])
			var best := Vector3.INF
			for key in horde:
				var zp:Vector3 = horde[key].position
				if zp.distance_to(base) < reach and (best == Vector3.INF or zp.distance_to(base) < best.distance_to(base)): best = zp
			var want_yaw := t * 0.5 + float(cell) * 0.37
			var want_pitch := -0.42
			if best != Vector3.INF:
				var d := best - base
				want_yaw = atan2(-d.x, -d.z)
				want_pitch = -atan2(2.6, maxf(1.0, Vector2(d.x, d.z).length()))
			lhead.rotation.y = lerp_angle(lhead.rotation.y, want_yaw, 1.0 - exp(-(6.0 if best != Vector3.INF else 2.0) * dt))
			lhead.rotation.x = lerpf(lhead.rotation.x, want_pitch, 1.0 - exp(-5.0 * dt))
		if info[0] == Data.S_GEN:
			mesh.position.x = sin(t * 50.0) * 0.008
	for i in loot_nodes.size():
		# whoever searches here: the boot or lid swings open and the prop rocks
		var ln:Node3D = loot_nodes[i]
		var mesh_node:Node3D = ln.get_node("Mesh")
		var open:float = move_toward(ln.get_meta("open", 0.0), 1.0 if searching.has(i) else 0.0, dt * (4.0 if searching.has(i) else 2.0))
		ln.set_meta("open", open)
		var kind:int = Map.LOOT[i].kind
		if mesh_node.has_node("Lid"):
			var lid:Node3D = mesh_node.get_node("Lid")
			lid.rotation.x = (-1.25 if kind == 0 else 1.15) * (open * open * (3.0 - 2.0 * open)) + (sin(t * 11.0 + i) * 0.05 * open if searching.has(i) else 0.0)
		if searching.has(i):
			mesh_node.rotation = Vector3(sin(t * 13.0 + i) * 0.015, 0, sin(t * 17.0 + i) * (0.03 if kind == 1 else 0.02))
			mesh_node.position.y = absf(sin(t * 9.0)) * 0.02
		else:
			mesh_node.rotation = mesh_node.rotation.lerp(Vector3.ZERO, 1.0 - exp(-10.0 * dt))
			mesh_node.position.y = 0.0
		var sp:Node3D = loot_nodes[i].get_node("Sparkle")
		if sp.visible:
			sp.position.y = (2.0 if Map.LOOT[i].kind == 1 else 1.6) + sin(t * 2.5 + i) * 0.12
			sp.rotation.y = t * 1.5
	for i in beacons.size():
		var n:Node3D = beacons[i]
		var claimed:bool = n.get_meta("claimed", false)
		if n.has_node("Story"):
			for r in n.get_node("Story").get_children():
				if r is Rig: (r as Rig).animate_hero(dt, t + i, Vector2.ZERO, false, false, 0, false, false, fmod(t + i, 4.0) < 2.0)
		(n.get_node("Light") as OmniLight3D).light_energy = 1.4 * night_amount if claimed and not blackout else 0.0
		(n.get_node("Flag") as Node3D).rotation.y = sin(t * 1.3 + i) * 0.25
	for id in people:
		var r:Rig = people[id]
		var info:Array = people_target[id]
		var before := r.position
		r.position = r.position.lerp(info[0], 1.0 - exp(-10.0 * dt))
		var vel := r.position - before
		var moving := clampf(vel.length() / maxf(dt, 0.0001) / 3.0, 0.0, 1.0)
		r.ground_vel = r.ground_vel.lerp(Vector2(vel.x, vel.z) / maxf(dt, 0.0001), 1.0 - exp(-10.0 * dt))
		r.face(r.ground_vel, dt)
		r.animate_hero(dt, t, r.ground_vel, false, false, 0, false, false, false)
		if info[1] == 0:
			r.arm_r.rotation = Vector3(-2.8, 0, -0.3 + sin(t * 9.0) * 0.4)
			r.label.visible = true
			r.label.position.y = 2.6 + sin(t * 4.0) * 0.1
		else:
			r.label.visible = false
	for i in community.size():
		var r:Rig = community[i]
		r.animate_hero(dt, t, Vector2.ZERO, false, false, 0, false, false, i % 3 == 0)
	bundle_bob(t, dt)
	for id in job_nodes:
		var n:Node3D = job_nodes[id]
		if not n.has_meta("info"): continue
		var j:Array = n.get_meta("info")
		var target := Vector3(j[3], 0, j[4])
		if j[1] in ["transporte", "relevo"] and heroes.has(j[9]): target = heroes[j[9]].position + Vector3(0, 2.0, 0)
		n.position = n.position.lerp(target, 1.0 - exp(-14.0 * dt)) if n.position.distance_to(target) < 6.0 else target
		if j[1] == "busqueda": n.rotation.y = t * 1.5
		if j[1] == "defensa": n.rotation.y = t * 0.3
	for i in piece_nodes.size():
		var n:Node3D = piece_nodes[i]
		if not n.has_meta("info"): continue
		var info:Array = n.get_meta("info")
		var st:int = info[0]
		n.visible = st > 0
		if not n.visible: continue
		var sp:Node3D = n.get_node("Sparkle")
		var lab:Label3D = n.get_node("Label")
		sp.visible = st == 1 or st == 3
		lab.visible = st != 4
		var target := Vector3(info[1], 0, info[2])
		if st == 2 and heroes.has(info[3]):
			target = heroes[info[3]].position + Vector3(0, 2.2, 0)
			n.rotation.y = heroes[info[3]].rotation.y
		elif st == 4:
			var slot:Vector2 = STAGE_SLOTS[i]
			target = Vector3(slot.x, 0.9 + 0.08 * sin(t * 2.0 + i), slot.y)
			n.rotation.y = PI * 0.5 + sin(t * 0.8 + i) * 0.2
		else:
			target.y = 0.15 + 0.12 * sin(t * 2.5 + i)
			n.rotation.y = t * 0.8
		n.position = n.position.lerp(target, 1.0 - exp(-14.0 * dt)) if n.position.distance_to(target) < 6.0 else target
		sp.position.y = 1.5 + sin(t * 3.0) * 0.1
	for id in drops:
		var d:Array = drop_info[id]
		var mi:MeshInstance3D = drops[id]
		var fall:float = d[3]
		mi.position = Vector3(d[1] + sin(t * 0.7) * 0.3 * minf(fall, 1.0), maxf(0.0, fall) * 4.0, d[2])
		mi.rotation.y = t * 0.3

func bundle_bob(t:float, dt:float):
	for id in bundles:
		var mi:MeshInstance3D = bundles[id]
		mi.scale = mi.scale.lerp(Vector3.ONE, 1.0 - exp(-8.0 * dt))
		mi.rotation.y = sin(t * 1.5 + id) * 0.15

func show_ghost(kind:int, at:Vector3, valid:bool):
	if kind < 0:
		ghost.visible = false
		return
	ghost.visible = true
	ghost.mesh = ghost_mesh(kind)
	ghost.position = at
	ghost_mat.set_shader_parameter("color", Color(0.45, 1.0, 0.6, 0.5) if valid else Color(1.0, 0.35, 0.35, 0.5))
