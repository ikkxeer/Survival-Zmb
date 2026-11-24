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
var beacons := []
var drops := {}
var people := {}
var community := []
var projectiles := []
var ghost:MeshInstance3D
var ghost_range:MeshInstance3D
var local_id := 0
var night := 0.0
var bar_quad:QuadMesh
var blob_quad:QuadMesh

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
			for i in 3:
				extra.box(Kit.rot(-0.1 + i * 0.1, 0.78, -0.05, 0, 0, -0.3 + i * 0.3), Vector3(0.04, 0.35, 0.04), C("6cc05a"), 0.015)
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
			torso.cylinder(Kit.at(0, 1.4, 0), 1.25, 0.6, 2.8, C("7a4aa8"), 20, true, 0.25)
			torso.cylinder(Kit.at(0, 0.08, 0), 1.28, 1.28, 0.16, C("f2c14e"), 20)
			torso.cylinder(Kit.at(0, 2.2, 0), 0.92, 0.9, 0.14, C("f2c14e"), 20)
			for i in 8:
				var a := TAU * i / 8.0
				torso.sphere(Kit.at(cos(a) * 1.0, 1.0, sin(a) * 1.0), Vector3(0.12, 0.12, 0.12), C("ff7ab8"), 8, 5)
				torso.cylinder(Kit.rot(cos(a) * 0.95, 1.6, sin(a) * 0.95, a, 0.1), 0.05, 0.05, 1.6, C("4f9a4a"), 6)
			torso.box(Kit.at(0, 2.75, 0), Vector3(1.3, 0.6, 0.9), C("8a5ab8"), 0.25)
			head_base(head, C("c9dca0"), true, 2.2)
			head.cylinder(Kit.at(0, 1.6, 0), 0.6, 0.62, 0.32, C("f2c14e"), 16, false)
			for i in 6:
				var a := TAU * i / 6.0
				head.cylinder(Kit.at(cos(a) * 0.58, 1.85, sin(a) * 0.58), 0.1, 0.01, 0.3, C("f2c14e"), 6)
				head.sphere(Kit.at(cos(a) * 0.58, 1.72, sin(a) * 0.58), Vector3(0.07, 0.07, 0.07), C(["e8463c", "4cc9f0", "06d6a0"][i % 3]), 6, 4)
			leaf_sprout(extra, 3)
	out.torso = torso.commit()
	out.head = head.commit()
	out.extra = extra.commit()
	var arm_len := 0.32
	var thick := 1.0
	if kind == 4: arm_len = 0.55
	if kind == 2: thick = 1.25
	if kind == 7:
		arm_len = 1.4
		thick = 2.0
	out.arm = arm_mesh(shirt if kind in [0, 2] else (C("7a6aa8") if kind == 4 else (C("8a5ab8") if kind == 7 else skin)), skin, arm_len, thick)
	out.leg = leg_mesh(pants, C("5a4a3a"), 1.25 if kind == 2 else 1.0)
	cache[key] = out
	return out

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
		r.setup_pivots(2.75, 0.85, 0.3, 0.4, 3.0)
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
	r.eyes = r.add_part(r.head, eyes_mesh(true, big), toon)
	r.eyes.position = Vector3(0, 0.36 * big, 0)
	if kind == 2: r.extra.position.y = 0.6
	if kind == 7: r.extra.position.y = 1.4
	r.add_part(r.extra, parts.extra, toon_char)
	r.add_part(r.arm_l, parts.arm, toon_char)
	r.add_part(r.arm_r, parts.arm, toon_char)
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
	)

func structure_mesh(kind:int, lvl:int) -> ArrayMesh:
	return cached("s%d_%d" % [kind, lvl], func(k:Kit):
		match kind:
			Data.S_WIRE:
				for p in [Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(-0.4, 0.4), Vector2(0.4, 0.4)]:
					k.cylinder(Kit.at(p.x, 0.4, p.y), 0.04, 0.04, 0.8, C("8b5e3c"), 6)
				for i in 2 + lvl:
					var y := 0.2 + i * 0.22
					for s in [-0.4, 0.4]:
						k.box(Kit.rot(0, y, s, 0, 0, 0.05 * (i % 2)), Vector3(0.8, 0.02, 0.02), C("c8ccd4"), 0.0)
						k.box(Kit.rot(s, y, 0, PI * 0.5, 0, 0.05 * (i % 2)), Vector3(0.8, 0.02, 0.02), C("c8ccd4"), 0.0)
					for j in 4: k.box(Kit.rot(-0.3 + j * 0.2, y, 0.4, j * 0.8, 0.5), Vector3(0.08, 0.015, 0.015), C("e6e6ea"), 0.0)
				k.box(Kit.rot(0, 0.35, 0, PI * 0.25), Vector3(1.1, 0.02, 0.02), C("c8ccd4"), 0.0)
				k.box(Kit.rot(0, 0.35, 0, -PI * 0.25), Vector3(1.1, 0.02, 0.02), C("c8ccd4"), 0.0)
			Data.S_COIL:
				k.box(Kit.at(0, 0.15, 0), Vector3(0.7, 0.3, 0.7), C("3d4a5c"), 0.08, 0.3)
				k.cylinder(Kit.at(0, 0.8, 0), 0.08, 0.08, 1.1, C("c8ccd4"), 8)
				for i in 3 + lvl:
					var y := 0.45 + i * 0.2
					k.cylinder(Kit.at(0, y, 0), 0.32 - i * 0.03, 0.32 - i * 0.03, 0.08, C("4cc9c0"), 14, true, 0.2)
				for s in [-1, 1]: k.box(Kit.at(s * 0.3, 0.38, 0.3), Vector3(0.08, 0.08, 0.04), Kit.glow(C("ffd166")), 0.02)
			Data.S_TURRET:
				for i in 3:
					var a := TAU * i / 3.0
					k.cylinder(Kit.rot(cos(a) * 0.22, 0.3, sin(a) * 0.22, -a, 0, 0.35), 0.04, 0.04, 0.65, C("5a6a80"), 6)
				k.cylinder(Kit.at(0, 0.62, 0), 0.26, 0.3, 0.16, C(["e85d5d", "4f86c6", "5ab07a"][lvl]), 14)
			Data.S_GEN:
				k.box(Kit.at(0, 0.38, 0), Vector3(0.85, 0.7, 0.62), C("f2c14e"), 0.1, 0.3)
				k.box(Kit.at(0, 0.76, 0), Vector3(0.7, 0.08, 0.5), C("3d4a5c"), 0.03)
				k.cylinder(Kit.at(0.3, 0.95, -0.15), 0.06, 0.06, 0.4, C("5a5a68"), 8)
				k.box(Kit.at(-0.15, 0.45, 0.32), Vector3(0.3, 0.2, 0.03), C("2b2d42"), 0.02)
				for i in 3: k.sphere(Kit.at(-0.25 + i * 0.1, 0.45, 0.34), Vector3(0.03, 0.03, 0.02), Kit.glow(C(["5ae85a", "ffd166", "ff5a5a"][i])), 6, 4)
				for s in [-1, 1]: k.box(Kit.at(s * 0.45, 0.06, 0), Vector3(0.1, 0.12, 0.7), C("3d4a5c"), 0.03)
				if lvl > 0: k.box(Kit.at(0, 0.88, 0.1), Vector3(0.3, 0.18, 0.2), C("e8463c"), 0.04)
			Data.S_LIGHT:
				k.box(Kit.at(0, 0.1, 0), Vector3(0.5, 0.2, 0.5), C("3d4a5c"), 0.05)
				k.cylinder(Kit.at(0, 1.1, 0), 0.06, 0.07, 2.0, C("5a6a80"), 8)
				k.box(Kit.rot(0, 2.15, 0.1, 0, 0.5), Vector3(0.5, 0.35, 0.3), C("3d4a5c"), 0.06)
				k.box(Kit.rot(0, 2.1, 0.22, 0, 0.5), Vector3(0.42, 0.28, 0.06), Kit.glow(C("fff2c0")), 0.04)
			Data.S_BENCH:
				k.box(Kit.at(0, 0.62, 0), Vector3(0.95, 0.1, 0.7), C("c98a55"), 0.03, 0.2)
				for x in [-0.4, 0.4]:
					for z in [-0.28, 0.28]: k.box(Kit.at(x, 0.3, z), Vector3(0.08, 0.6, 0.08), C("8b5e3c"), 0.02)
				k.box(Kit.at(0.3, 0.75, 0.15), Vector3(0.2, 0.16, 0.15), C("5a6a80"), 0.03)
				k.box(Kit.at(-0.2, 0.74, -0.1), Vector3(0.35, 0.14, 0.2), C("e85d5d"), 0.04)
				k.box(Kit.rot(0.05, 0.69, 0.18, 0.4), Vector3(0.4, 0.02, 0.1), C("c8ccd4"), 0.0)
				k.box(Kit.at(0, 0.2, 0), Vector3(0.8, 0.05, 0.6), C("8b5e3c"), 0.02)
				if lvl > 0: k.box(Kit.at(-0.35, 0.95, 0.2), Vector3(0.12, 0.5, 0.12), C("4f86c6"), 0.03)
			Data.S_MINE:
				for i in 5:
					var a := TAU * i / 5.0
					k.cylinder(Kit.rot(cos(a) * 0.12, 0.08, sin(a) * 0.12, 0, 0, PI * 0.5), 0.06, 0.06, 0.3, C("e8463c"), 8)
				k.cylinder(Kit.at(0, 0.08, 0), 0.08, 0.08, 0.14, C("f2c14e"), 8)
				k.cylinder(Kit.rot(0, 0.22, 0, 0, 0.4), 0.01, 0.01, 0.2, C("2f2f38"), 4)
	)

func turret_head(lvl:int) -> ArrayMesh:
	return cached("thead%d" % lvl, func(k:Kit):
		k.box(Kit.at(0, 0.0, 0), Vector3(0.42, 0.32, 0.5), C("f6f0e0"), 0.1, 0.2)
		k.box(Kit.at(0, 0.18, -0.05), Vector3(0.3, 0.06, 0.3), C(["e85d5d", "4f86c6", "5ab07a"][lvl]), 0.03)
		for x in ([0.0] if lvl == 0 else [-0.09, 0.09]):
			k.cylinder(Kit.rot(x, 0.0, 0.42, 0, PI * 0.5), 0.05, 0.05, 0.4, C("3a3a48"), 8)
		k.sphere(Kit.at(0.15, 0.1, 0.25), Vector3(0.04, 0.04, 0.03), Kit.glow(C("ff5a5a")), 6, 4)
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
		var l := SpotLight3D.new()
		l.position = Vector3(0, 2.1, 0.3)
		l.rotation.x = -0.9
		l.spot_range = 9.0
		l.spot_angle = 50.0
		l.light_color = Color("fff1c8")
		l.light_energy = 0.0
		l.name = "Lamp"
		n.add_child(l)
	var bar := MeshInstance3D.new()
	bar.mesh = bar_quad
	bar.material_override = bar_mat
	bar.position.y = 1.9 if kind != Data.S_LIGHT else 2.7
	bar.scale = Vector3(0.8, 1, 1)
	bar.visible = false
	bar.name = "Bar"
	bar.set_instance_shader_parameter("fill", Color("7be07b"))
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(bar)
	return n

func ghost_mesh(kind:int) -> Mesh:
	if kind == Data.S_WALL: return wall_mesh(0, 0)
	return structure_mesh(kind, 0)

# ================================================================== loot, banners, balloons
func loot_mesh(kind:int) -> ArrayMesh:
	return cached("loot%d" % kind, func(k:Kit):
		match kind:
			0:
				k.box(Kit.at(0, 0.5, 0), Vector3(1.4, 0.95, 0.9), C("4f9a6a"), 0.08, 0.3)
				k.box(Kit.rot(0, 1.02, -0.05, 0, -0.12), Vector3(1.45, 0.08, 0.95), C("3f7a54"), 0.03)
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
		var sp := MeshInstance3D.new()
		sp.mesh = sparkle_mesh()
		sp.material_override = glow_mat
		sp.position.y = 2.0 if l.kind == 1 else 1.6
		sp.name = "Sparkle"
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(sp)
		n.position = Vector3(l.p.x, 0, l.p.y)
		n.rotation.y = fmod(l.p.x * 1.7 + l.p.y, 1.0) - 0.5 + (PI * 0.5 if l.kind == 1 and absf(fmod(l.p.y, 24.0) - 12.0) < 3.0 else 0.0)
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
	ghost = MeshInstance3D.new()
	ghost.material_override = ghost_mat
	ghost.visible = false
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost)

func set_beacon(i:int, claimed:bool, frac:float):
	var n:Node3D = beacons[i]
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
	for d in [heroes, horde, structs, drops, people]:
		for n in d.values(): n.queue_free()
		d.clear()
	for n in community: n.queue_free()
	community.clear()
	for p in projectiles: p.queue_free()
	projectiles.clear()
	for i in beacons.size(): set_beacon(i, false, 0.0)
	for n in loot_nodes: n.visible = true
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
	for id in heroes:
		if not hero_target.has(id): continue
		var p:Dictionary = hero_target[id]
		var r:Rig = heroes[id]
		var target := Vector3(p.p.x, 0, p.p.y)
		if id == local_id and local_pos != Vector3.INF: target = local_pos
		var before := r.position
		r.position = target if id == local_id else r.position.lerp(target, 1.0 - exp(-14.0 * dt))
		var vel := (r.position - before) / maxf(dt, 0.0001)
		var moving := clampf(Vector2(vel.x, vel.z).length() / 4.5, 0.0, 1.0)
		var aim:Vector2 = local_aim if id == local_id and local_aim != Vector2.ZERO else p.aim
		var aiming:bool = p.fire or p.st == 0
		r.face(aim if p.st == 0 else Vector2(vel.x, vel.z), dt)
		r.animate_hero(dt, t, moving, aiming, p.fire, p.st, p.roll, p.rl > 0, p.use and p.hold != "")
		r.flashlight.light_energy = (2.2 if p.st == 0 else 0.0) * smoothstep(0.3, 0.9, night_amount)
		r.label.modulate.a = 0.0 if id == local_id else 1.0
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
		if info[3] > 0.05: z.hit_flash = 1.0
		var hp:float = info[0]
		z.bar.visible = hp < 0.999
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
		if info[0] == Data.S_COIL:
			var top:MeshInstance3D = n.get_node("Top")
			top.set_instance_shader_parameter("itint", Color(1, 1, 1) if on else Color(0.3, 0.3, 0.35))
			top.scale = Vector3.ONE * (1.0 + 0.08 * sin(t * 9.0 + cell))
		if info[0] == Data.S_LIGHT:
			(n.get_node("Lamp") as SpotLight3D).light_energy = 3.0 * night_amount if on else 0.0
		if info[0] == Data.S_GEN:
			mesh.position.x = sin(t * 50.0) * 0.008
	for i in loot_nodes.size():
		var sp:Node3D = loot_nodes[i].get_node("Sparkle")
		if sp.visible:
			sp.position.y = (2.0 if Map.LOOT[i].kind == 1 else 1.6) + sin(t * 2.5 + i) * 0.12
			sp.rotation.y = t * 1.5
	for i in beacons.size():
		var n:Node3D = beacons[i]
		var claimed:bool = n.get_meta("claimed", false)
		(n.get_node("Light") as OmniLight3D).light_energy = 1.4 * night_amount if claimed and not blackout else 0.0
		(n.get_node("Flag") as Node3D).rotation.y = sin(t * 1.3 + i) * 0.25
	for id in people:
		var r:Rig = people[id]
		var info:Array = people_target[id]
		var before := r.position
		r.position = r.position.lerp(info[0], 1.0 - exp(-10.0 * dt))
		var vel := r.position - before
		var moving := clampf(vel.length() / maxf(dt, 0.0001) / 3.0, 0.0, 1.0)
		r.face(Vector2(vel.x, vel.z), dt)
		r.animate_hero(dt, t, moving, false, false, 0, false, false, false)
		if info[1] == 0:
			r.arm_r.rotation = Vector3(-2.8, 0, -0.3 + sin(t * 9.0) * 0.4)
			r.label.visible = true
			r.label.position.y = 2.6 + sin(t * 4.0) * 0.1
		else:
			r.label.visible = false
	for i in community.size():
		var r:Rig = community[i]
		r.animate_hero(dt, t, 0.0, false, false, 0, false, false, i % 3 == 0)
	for id in drops:
		var d:Array = drop_info[id]
		var mi:MeshInstance3D = drops[id]
		var fall:float = d[3]
		mi.position = Vector3(d[1] + sin(t * 0.7) * 0.3 * minf(fall, 1.0), maxf(0.0, fall) * 4.0, d[2])
		mi.rotation.y = t * 0.3

func show_ghost(kind:int, at:Vector3, valid:bool):
	if kind < 0:
		ghost.visible = false
		return
	ghost.visible = true
	ghost.mesh = ghost_mesh(kind)
	ghost.position = at
	ghost_mat.set_shader_parameter("color", Color(0.45, 1.0, 0.6, 0.5) if valid else Color(1.0, 0.35, 0.35, 0.5))
