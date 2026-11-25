extends Node
## The neighbourhood as a small 3D model for the maps: raised buildings, trees,
## cars and your defences on a diorama slab, seen from a tilted camera. One
## shared world feeds two viewports (big map and minimap). The 2D markers are
## drawn on top by projecting world points through these same cameras.

const Kit = preload("res://game/view/kit.gd")
const Map = preload("res://game/map.gd")
const Data = preload("res://game/data.gd")

const SS := 1.5              # render scale: sharper than the control it is drawn into
const PITCH := deg_to_rad(56.0)

var big_vp := SubViewport.new()
var mini_vp := SubViewport.new()
var big_cam := Camera3D.new()
var mini_cam := Camera3D.new()
var toon := ShaderMaterial.new()
var sites := []              # MeshInstance3D per property, tinted when conquered
var structs := MeshInstance3D.new()
var struct_sig := -1
var big_size := Vector2(700, 620)
var mini_size := Vector2(196, 176)

func _init():
	toon.shader = load("res://game/shaders/toon.gdshader")
	for vp in [big_vp, mini_vp]:
		vp.msaa_3d = Viewport.MSAA_4X
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
	big_vp.own_world_3d = true
	mini_vp.world_3d = big_vp.world_3d
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("cfe9e4")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff4e0")
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	big_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.0
	sun.light_color = Color("fff1d6")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	big_vp.add_child(sun)
	var root := Node3D.new()
	big_vp.add_child(root)
	build(root)
	structs.material_override = toon
	root.add_child(structs)
	for cam in [big_cam, mini_cam]:
		cam.fov = 30.0
		cam.far = 400.0
	big_vp.add_child(big_cam)
	mini_vp.add_child(mini_cam)
	set_sizes(mini_size, big_size)

func set_sizes(mini:Vector2, big:Vector2):
	mini_size = mini
	big_size = big
	mini_vp.size = Vector2i(mini * SS)
	big_vp.size = Vector2i(big * SS)

static func hex(h:String) -> Color:
	return Color(h)

func in_any(pt:Vector2, margin:float) -> bool:
	for r in Map.solids():
		if (r as Rect2).grow(margin).has_point(pt): return true
	for z in Map.ROADS_H: if absf(pt.y - z) < 3.4: return true
	for x in Map.ROADS_V: if absf(pt.x - x) < 3.4: return true
	if Rect2(-12, -10, 24, 20).has_point(pt) or Rect2(-12, 14, 24, 7).has_point(pt) or Rect2(-13, -29, 26, 16).has_point(pt): return true
	return false

func window_box(k:Kit, xf:Transform3D, x:float, y:float, z:float, sx:float, sy:float, sz:float):
	k.box(xf * Kit.at(x, y, z), Vector3(sx + 0.14, sy + 0.14, sz + 0.02), hex("fffaf0"), 0.03)
	k.box(xf * Kit.at(x, y, z + (0.03 if sz < 0.5 and sx > sz else 0.0)), Vector3(sx, sy, sz), hex("7fb4d8"), 0.02)

func house(k:Kit, r:Rect2, face:Vector2, wall:Color, roof:Color, height:float, door:Color, tintable:bool = false):
	## A little house: plinth, walls, door and windows on every side, overhanging roof, chimney.
	var c := r.get_center()
	var yaw := atan2(face.x, face.y)
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, 0, c.y))
	var vertical := absf(face.y) > 0.5
	var w := (r.size.x if vertical else r.size.y) - 0.3
	var d := (r.size.y if vertical else r.size.x) - 0.3
	k.box(xf * Kit.at(0, 0.12, 0), Vector3(w + 0.3, 0.24, d + 0.3), hex("b6a99b") if not tintable else Color(0.85, 0.85, 0.85), 0.05)
	k.box(xf * Kit.at(0, 0.24 + height * 0.5, 0), Vector3(w, height, d), wall, 0.1, 0.2)
	for sx in [-1, 1]:
		for sz in [-1, 1]: k.box(xf * Kit.at(sx * w * 0.5, 0.24 + height * 0.5, sz * d * 0.5), Vector3(0.22, height + 0.04, 0.22), Color(0.96, 0.96, 0.96) if tintable else hex("fffaf0"), 0.04)
	var wy := 0.24 + height * 0.55
	var glass := Color(0.35, 0.5, 0.65) if tintable else hex("7fb4d8")
	for sx in [-0.28, 0.28]:
		k.box(xf * Kit.at(sx * w, wy, d * 0.5 + 0.02), Vector3(0.78, 0.84, 0.1), Color(0.96, 0.96, 0.96) if tintable else hex("fffaf0"), 0.03)
		k.box(xf * Kit.at(sx * w, wy, d * 0.5 + 0.06), Vector3(0.6, 0.66, 0.06), glass, 0.02)
		k.box(xf * Kit.at(sx * w, wy, -d * 0.5 - 0.06), Vector3(0.6, 0.66, 0.06), glass, 0.02)
	for sz in [-1, 1]:
		k.box(xf * Kit.at(w * 0.5 + 0.06, wy, sz * d * 0.22), Vector3(0.06, 0.66, 0.6), glass, 0.02)
		k.box(xf * Kit.at(-w * 0.5 - 0.06, wy, sz * d * 0.22), Vector3(0.06, 0.66, 0.6), glass, 0.02)
	k.box(xf * Kit.at(0, 0.24 + 0.85, d * 0.5 + 0.05), Vector3(0.95, 1.7, 0.12), door, 0.04)
	k.box(xf * Kit.at(0, 0.24 + 1.78, d * 0.5 + 0.35), Vector3(1.5, 0.1, 0.8), roof.darkened(0.1), 0.03)
	k.box(xf * Kit.at(0, 0.1, d * 0.5 + 0.5), Vector3(1.3, 0.2, 0.8), hex("cfc5b8") if not tintable else Color(0.8, 0.8, 0.8), 0.04)
	# gable roof with its ridge along the long side
	var rx := xf * Kit.rot(0, 0.24 + height, 0, PI * 0.5) if w >= d else xf * Kit.at(0, 0.24 + height, 0)
	var span := d + 0.5 if w >= d else w + 0.5
	var run := w + 0.4 if w >= d else d + 0.4
	k.roof(rx, span, minf(span * 0.38, 1.6), run, roof, 0.16, 0.05)
	k.box(xf * Kit.at(w * 0.28, 0.24 + height + 1.05, -d * 0.15), Vector3(0.4, 0.9, 0.4), hex("a8745a") if not tintable else Color(0.7, 0.7, 0.7), 0.04)

func tree(k:Kit, t:Vector2, i:int):
	var h := fmod(i * 0.618, 1.0)
	var leaf := hex(["5fb85a", "6cc05a", "52aa5c", "f4a9c4"][i % 4])
	var sc := 0.85 + h * 0.4
	k.cylinder(Kit.at(t.x, 0.55, t.y), 0.16, 0.26, 1.1, hex("8b5e3c"), 7)
	if i % 5 == 4:
		k.cylinder(Kit.at(t.x, 1.6, t.y), 0.95 * sc, 0.0, 1.5, hex("3f9a52"), 8)
		k.cylinder(Kit.at(t.x, 2.5, t.y), 0.7 * sc, 0.0, 1.3, hex("49a85a"), 8)
		k.cylinder(Kit.at(t.x, 3.3, t.y), 0.45 * sc, 0.0, 1.1, hex("56b866"), 8)
	else:
		k.sphere(Kit.at(t.x, 1.9, t.y), Vector3(1.05, 0.9, 1.05) * sc, leaf, 12, 8, 0.25)
		k.sphere(Kit.at(t.x + 0.45 * sc, 2.3, t.y - 0.2), Vector3(0.7, 0.65, 0.7) * sc, leaf.lightened(0.1), 10, 7, 0.2)
		k.sphere(Kit.at(t.x - 0.4 * sc, 2.35, t.y + 0.25), Vector3(0.65, 0.6, 0.65) * sc, leaf.lightened(0.05), 10, 7, 0.2)

func car(k:Kit, c:Vector2, yaw:float, body:Color):
	var xf := Kit.rot(c.x, 0, c.y, -yaw)
	k.box(xf * Kit.at(0, 0.55, 0), Vector3(1.7, 0.6, 3.2), body, 0.25, 0.2, 1)
	k.box(xf * Kit.at(0, 1.05, -0.15), Vector3(1.45, 0.55, 1.7), body.lightened(0.08), 0.2, 0.0, 1)
	k.box(xf * Kit.at(0, 1.08, -0.15), Vector3(1.5, 0.36, 1.45), hex("8fc3e8"), 0.1)
	k.box(xf * Kit.at(0, 0.62, 0), Vector3(1.74, 0.12, 3.0), body.darkened(0.25), 0.04)
	for x in [-0.85, 0.85]:
		for z in [-1.0, 1.0]: k.cylinder(xf * Kit.rot(x, 0.32, z, 0, 0, PI * 0.5), 0.32, 0.32, 0.26, hex("2f2f38"), 12)
	for x in [-0.55, 0.55]: k.sphere(xf * Kit.at(x, 0.65, 1.62), Vector3(0.14, 0.12, 0.06), Kit.glow(hex("fff2c0"), 0.6), 8, 4)

func build(root:Node3D):
	var k := Kit.new()
	# diorama slab: soil block with a grass top and a darker rim
	k.box(Kit.at(0, -1.3, 0), Vector3(76, 1.8, 68), hex("7a5a40"), 0.3)
	k.box(Kit.at(0, -0.3, 0), Vector3(74.6, 0.2, 66.6), hex("5a9a48"), 0.06)
	k.box(Kit.at(0, -0.2, 0), Vector3(74, 0.4, 66), hex("8fcf6a"), 0.1, 0.25)
	# streets with kerbs, lane dashes and crosswalks
	for z in Map.ROADS_H:
		k.box(Kit.at(0, 0.03, z), Vector3(74, 0.1, 4), hex("626879"), 0.02)
		k.box(Kit.at(0, 0.05, z - 2.5), Vector3(74, 0.1, 1.0), hex("dcd2c2"), 0.02)
		k.box(Kit.at(0, 0.05, z + 2.5), Vector3(74, 0.1, 1.0), hex("dcd2c2"), 0.02)
		for i in 15:
			var x := -34.0 + i * 4.8
			if absf(absf(x) - 14.0) < 3.0 or absf(x) < 3.0 and absf(z) < 13: continue
			k.box(Kit.at(x, 0.1, z), Vector3(2.0, 0.02, 0.16), hex("f6eed6"), 0.0)
	for x in Map.ROADS_V:
		k.box(Kit.at(x, 0.04, 0), Vector3(4, 0.1, 66), hex("626879"), 0.02)
		k.box(Kit.at(x - 2.5, 0.06, 0), Vector3(1.0, 0.1, 66), hex("dcd2c2"), 0.02)
		k.box(Kit.at(x + 2.5, 0.06, 0), Vector3(1.0, 0.1, 66), hex("dcd2c2"), 0.02)
		for i in 13:
			var z := -30.0 + i * 5.0
			if absf(absf(z) - 12.0) < 3.0: continue
			k.box(Kit.at(x, 0.11, z), Vector3(0.16, 0.02, 2.0), hex("f6eed6"), 0.0)
	for z in Map.ROADS_H:
		for x in Map.ROADS_V:
			for j in 5:
				k.box(Kit.at(x - 1.6 + j * 0.8, 0.12, z + 2.9), Vector3(0.4, 0.02, 1.2), hex("f6eed6"), 0.0)
				k.box(Kit.at(x - 1.6 + j * 0.8, 0.12, z - 2.9), Vector3(0.4, 0.02, 1.2), hex("f6eed6"), 0.0)
	# plaza: warm tiles, a low kerb and festive bulbs round the edge
	k.box(Kit.at(0, 0.08, 0), Vector3(22.6, 0.16, 18.6), hex("dcd2c2"), 0.05)
	k.box(Kit.at(0, 0.12, 0), Vector3(22, 0.16, 18), hex("f0cf8a"), 0.03)
	for i in range(-10, 11, 2): k.box(Kit.at(i, 0.21, 0), Vector3(0.05, 0.02, 18), hex("e0b96a"), 0.0)
	for i in range(-8, 9, 2): k.box(Kit.at(0, 0.21, i), Vector3(22, 0.02, 0.05), hex("e0b96a"), 0.0)
	for i in 23:
		var x := -11.0 + i
		for z in [-9.0, 9.0]: k.sphere(Kit.at(x, 0.9 + 0.1 * sin(i * 0.9), z), Vector3(0.1, 0.1, 0.1), Kit.glow(Color.from_hsv(fmod(i * 0.13, 1.0), 0.55, 1.0), 0.8), 6, 4)
	for i in 19:
		var z := -9.0 + i
		for x in [-11.0, 11.0]: k.sphere(Kit.at(x, 0.9, z), Vector3(0.1, 0.1, 0.1), Kit.glow(Color.from_hsv(fmod(i * 0.17, 1.0), 0.55, 1.0), 0.8), 6, 4)
	# parking lot with bays, park with paths and flower beds
	k.box(Kit.at(0, 0.08, 17.5), Vector3(22, 0.14, 5.4), hex("7b8196"), 0.03)
	for i in 9: k.box(Kit.at(-9.0 + i * 2.25, 0.17, 17.5), Vector3(0.1, 0.02, 4.4), hex("f6eed6"), 0.0)
	k.box(Kit.at(0, 0.07, -22), Vector3(26, 0.1, 15), hex("7cbf62"), 0.04)
	k.box(Kit.at(0, 0.12, -22), Vector3(2.4, 0.06, 15), hex("d9b98a"), 0.02)
	k.box(Kit.at(0, 0.12, -22), Vector3(24, 0.06, 2.4), hex("d9b98a"), 0.02)
	for bx in [-7.0, 7.0]:
		for bz in [-27.0, -17.0]:
			k.box(Kit.at(bx, 0.2, bz), Vector3(3.2, 0.3, 2.2), hex("8b5e3c"), 0.05)
			for j in 7: k.sphere(Kit.at(bx - 1.2 + j * 0.4, 0.5 + 0.04 * (j % 2), bz + 0.5 * sin(j * 2.1)), Vector3(0.2, 0.16, 0.2), Color.from_hsv(fmod(j * 0.19 + bx * 0.1, 1.0), 0.5, 1.0), 6, 4)
	# neighbours' homes
	var wcols := ["f7dcae", "a9dccb", "f6bcab", "c9d3f2"]
	var rcols := ["dc6553", "5384c0", "5aa572", "9a6ab8"]
	for i in Map.HOUSES.size():
		var h:Dictionary = Map.HOUSES[i]
		house(k, h.rect, h.face, hex(wcols[(int(h.style) + i) % 4]), hex(rcols[(int(h.style) + i) % 4]), 2.3, hex(["4a7aa8", "b85a4a", "5a9a6a", "7d5aa8"][i % 4]))
	# the party house: taller, with bunting, a sign and a porch
	var b:Rect2 = Map.BASE
	house(k, b, Vector2.DOWN, hex("ffd99a"), hex("4c7fc0"), 3.3, hex("3f6f9f"))
	var bc := b.get_center()
	k.box(Kit.at(bc.x, 3.0, bc.y + b.size.y * 0.5 + 0.35), Vector3(3.0, 0.6, 0.16), hex("f2c14e"), 0.05)
	for i in 9:
		k.box(Kit.rot(bc.x - 2.8 + i * 0.7, 3.62 - 0.12 * sin(i * PI / 8.0), bc.y + b.size.y * 0.5 + 0.6, PI * 0.25), Vector3(0.28, 0.4, 0.04), Color.from_hsv(fmod(i * 0.16, 1.0), 0.6, 1.0), 0.0)
	for sx in [-1, 1]:
		k.cylinder(Kit.at(bc.x + sx * 2.2, 0.9, bc.y + b.size.y * 0.5 + 1.3), 0.06, 0.06, 1.8, hex("6b4f3c"), 6)
		k.sphere(Kit.at(bc.x + sx * 2.2, 1.9, bc.y + b.size.y * 0.5 + 1.3), Vector3(0.22, 0.28, 0.22), Kit.glow(hex("ffb35c"), 0.9), 8, 6)
	# stage, bell, shop stall and noticeboard
	var st:Vector2 = Map.STAGE
	k.box(Kit.at(st.x, 0.4, st.y), Vector3(2.6, 0.8, 4.4), hex("c98a55"), 0.06)
	for z in [-2.0, 2.0]: k.cylinder(Kit.at(st.x - 1.0, 1.9, st.y + z), 0.07, 0.07, 2.2, hex("8b5e3c"), 6)
	k.box(Kit.rot(st.x, 3.1, st.y, 0, 0, 0.3), Vector3(2.8, 0.1, 4.6), hex("e8665a"), 0.04)
	k.box(Kit.at(Map.BELL.x, 0.9, Map.BELL.y), Vector3(0.9, 1.8, 0.9), hex("8b5e3c"), 0.05)
	k.sphere(Kit.at(Map.BELL.x, 1.9, Map.BELL.y), Vector3(0.35, 0.4, 0.35), hex("e0a63a"), 10, 6)
	k.box(Kit.at(4.6, 0.55, 3.6), Vector3(1.8, 1.1, 0.8), hex("e8665a"), 0.06)
	for i in 6: k.box(Kit.rot(3.8 + i * 0.33, 2.0, 3.6, 0, 0.35), Vector3(0.33, 0.06, 1.3), hex("fff2d6") if i % 2 == 0 else hex("e8665a"), 0.01)
	k.box(Kit.at(Map.BOARD.x, 1.2, Map.BOARD.y), Vector3(1.6, 1.0, 0.12), hex("c98a55"), 0.04)
	for sx in [-0.7, 0.7]: k.box(Kit.at(Map.BOARD.x + sx, 0.7, Map.BOARD.y), Vector3(0.1, 1.4, 0.1), hex("8b5e3c"), 0.02)
	# props and trees
	for p in Map.PROPS:
		var pr:Rect2 = p.rect
		var pc := pr.get_center()
		match p.kind:
			"fountain":
				k.cylinder(Kit.at(pc.x, 0.45, pc.y), 2.05, 2.15, 0.9, hex("d9d2c5"), 24)
				k.cylinder(Kit.at(pc.x, 0.92, pc.y), 1.75, 1.75, 0.06, hex("6fc3e8"), 24)
				k.cylinder(Kit.at(pc.x, 1.5, pc.y), 0.3, 0.4, 1.3, hex("d9d2c5"), 10)
				k.cylinder(Kit.at(pc.x, 2.2, pc.y), 0.9, 0.5, 0.2, hex("d9d2c5"), 14)
				k.sphere(Kit.at(pc.x, 2.5, pc.y), Vector3(0.3, 0.4, 0.3), hex("f2c14e"), 10, 6)
			"kiosk":
				k.cylinder(Kit.at(pc.x, 0.2, pc.y), 1.9, 2.0, 0.4, hex("e9dcc6"), 8)
				for j in 6:
					var a := TAU * j / 6.0
					k.cylinder(Kit.at(pc.x + cos(a) * 1.5, 1.3, pc.y + sin(a) * 1.5), 0.07, 0.07, 1.8, hex("fffaf0"), 6)
				k.cylinder(Kit.at(pc.x, 2.5, pc.y), 2.1, 0.1, 1.0, hex("e85d5d"), 8)
			_:
				k.box(Kit.at(pc.x, 0.5, pc.y), Vector3(0.7, 1.0, 0.7), hex("e8463c"), 0.05)
				k.box(Kit.at(pc.x, 1.05, pc.y), Vector3(0.8, 0.1, 0.8), hex("3d4a5c"), 0.02)
	for i in Map.TREES.size(): tree(k, Map.TREES[i], i)
	# bushes and flowers on the open grass
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var placed := 0
	for tries in 400:
		if placed >= 70: break
		var pt := Vector2(rng.randf_range(-34, 34), rng.randf_range(-30, 30))
		if in_any(pt, 1.0): continue
		placed += 1
		if placed % 3 == 0:
			k.sphere(Kit.at(pt.x, 0.3, pt.y), Vector3(0.45, 0.35, 0.45), hex("4fa854"), 8, 5, 0.2)
			k.sphere(Kit.at(pt.x + 0.25, 0.55, pt.y), Vector3(0.1, 0.09, 0.1), Color.from_hsv(rng.randf(), 0.5, 1.0), 6, 4)
		else:
			for j in 3: k.sphere(Kit.at(pt.x + j * 0.2 - 0.2, 0.18, pt.y + 0.1 * (j % 2)), Vector3(0.09, 0.08, 0.09), Color.from_hsv(rng.randf(), 0.45, 1.0), 6, 4)
	# cars
	var carcols := ["ef8f8f", "8fc3ef", "f2d27a", "9fe0b0", "c9a8f0", "fafafa"]
	var cars := Map.cars()
	for i in cars.size(): car(k, cars[i][0], cars[i][1], hex(carcols[i % carcols.size()]))
	# street lamps along the avenues
	for z in Map.ROADS_H:
		for i in 8:
			var x := -31.0 + i * 9.0
			k.cylinder(Kit.at(x, 1.2, z + 3.1), 0.05, 0.06, 2.4, hex("5a6a80"), 6)
			k.sphere(Kit.at(x, 2.5, z + 3.1), Vector3(0.18, 0.14, 0.18), Kit.glow(hex("fff2c0"), 0.7), 8, 5)
	var m := MeshInstance3D.new()
	m.mesh = k.commit()
	m.material_override = toon
	root.add_child(m)
	# properties: same house design, bigger, tinted by whether they belong to the neighbourhood
	for i in Map.SITES.size():
		var s:Dictionary = Map.SITES[i]
		var r:Rect2 = s.rect
		var sk := Kit.new()
		house(sk, r, s.face, Color.WHITE, Color(0.78, 0.78, 0.78), 3.5, Color(0.55, 0.55, 0.6), true)
		var c := r.get_center()
		match i:
			0: sk.cylinder(Kit.at(c.x + 1.0, 5.2, c.y), 0.45, 0.45, 0.5, Color(0.6, 0.6, 0.6), 12)
			1: sk.box(Kit.at(c.x, 5.0, c.y), Vector3(1.6, 0.4, 0.5), Color.WHITE, 0.02); sk.box(Kit.at(c.x, 5.0, c.y), Vector3(0.5, 0.4, 1.6), Color.WHITE, 0.02)
			2: sk.box(Kit.at(c.x - 2.0, 4.8, c.y), Vector3(2.2, 0.9, 0.2), Color(0.9, 0.9, 0.9), 0.03)
			3: for j in 3: sk.box(Kit.at(c.x - 3.0 + j * 3.0, 4.6, c.y), Vector3(2.4, 0.6, 5.0), Color(0.82, 0.82, 0.82), 0.05)
			4: sk.box(Kit.at(c.x, 3.3, c.y + r.size.y * 0.5 + 0.8), Vector3(r.size.x, 0.2, 1.8), Color(0.9, 0.9, 0.9), 0.03)
			5: sk.cylinder(Kit.at(c.x + 1.5, 5.0, c.y), 0.12, 0.12, 2.0, Color(0.85, 0.85, 0.85), 6); sk.box(Kit.at(c.x + 1.9, 5.7, c.y), Vector3(0.8, 0.5, 0.05), Color(0.95, 0.95, 0.95), 0.0)
		var mi := MeshInstance3D.new()
		mi.mesh = sk.commit()
		mi.material_override = toon
		root.add_child(mi)
		sites.append(mi)

func update(s:Dictionary, me:Vector2, yaw:float, show_mini:bool, show_big:bool):
	for i in sites.size():
		var claimed:bool = s.si[i][0]
		sites[i].set_instance_shader_parameter("itint", Color(Data.SITES[i].color).lightened(0.15) if claimed else Color(0.66, 0.68, 0.74))
	var st:PackedInt32Array = s.st
	var sig := hash(st)
	if sig != struct_sig:
		struct_sig = sig
		var k := Kit.new()
		for i in range(0, st.size(), 8):
			var cell := st[i]
			var wp := Vector2(cell % 74 - 37 + 0.5, cell / 74 - 33 + 0.5)
			var kind := st[i + 1]
			var def:Array = [[0.9, "b07a4a"], [0.35, "d6dbe2"], [1.4, "4cc9c0"], [1.1, "e85d5d"], [0.9, "f2c14e"], [1.8, "fff2c0"], [0.8, "c98a55"], [0.25, "e8463c"]][clampi(kind, 0, 7)]
			k.box(Kit.at(wp.x, def[0] * 0.5, wp.y), Vector3(0.85, def[0], 0.85), hex(def[1]), 0.05)
		structs.mesh = k.commit() if not k.is_empty() else null
	# big map: whole neighbourhood, north up. Minimap: follows you and turns with the camera.
	place(big_cam, Vector3(0, 0, 1.5), 0.0, 122.0)
	place(mini_cam, Vector3(me.x, 0, me.y), yaw, 58.0)
	big_vp.render_target_update_mode = SubViewport.UPDATE_ONCE if show_big and Engine.get_process_frames() % 6 == 0 else SubViewport.UPDATE_DISABLED
	mini_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if show_mini else SubViewport.UPDATE_DISABLED

func place(cam:Camera3D, focus:Vector3, yaw:float, dist:float):
	var axis := Vector3(sin(yaw) * cos(PITCH), sin(PITCH), cos(yaw) * cos(PITCH))
	cam.position = focus + axis * dist
	cam.look_at(focus, Vector3.UP)

func texture(big:bool) -> Texture2D:
	return (big_vp if big else mini_vp).get_texture()

func project(big:bool, wp:Vector3) -> Vector2:
	var cam := big_cam if big else mini_cam
	if not cam.is_inside_tree(): return Vector2.ZERO
	return cam.unproject_position(wp) / SS

func scale_at(big:bool, p:Vector2) -> float:
	return project(big, Vector3(p.x + 1.0, 0.3, p.y)).distance_to(project(big, Vector3(p.x, 0.3, p.y)))

func ground_at(big:bool, screen:Vector2):
	## World point on the ground under a position of the map, or null.
	var cam := big_cam if big else mini_cam
	if not cam.is_inside_tree(): return null
	var p := screen * SS
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(p), cam.project_ray_normal(p))
	return null if hit == null else Vector2(hit.x, hit.z)
