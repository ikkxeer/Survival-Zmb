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

func build(root:Node3D):
	var k := Kit.new()
	# diorama slab: a brown block with a grass top
	k.box(Kit.at(0, -1.2, 0), Vector3(75, 1.6, 67), hex("8a6a4c"), 0.2)
	k.box(Kit.at(0, -0.2, 0), Vector3(74, 0.4, 66), hex("86c466"), 0.1)
	for z in Map.ROADS_H: k.box(Kit.at(0, 0.04, z), Vector3(74, 0.1, 4), hex("6d7385"), 0.02)
	for x in Map.ROADS_V: k.box(Kit.at(x, 0.05, 0), Vector3(4, 0.1, 66), hex("6d7385"), 0.02)
	k.box(Kit.at(0, 0.08, 0), Vector3(22, 0.16, 18), hex("f0cf8a"), 0.04)
	k.box(Kit.at(0, 0.08, 17.5), Vector3(22, 0.12, 5), hex("858ba0"), 0.02)
	k.box(Kit.at(0, 0.07, -22), Vector3(24, 0.1, 14), hex("c9a574"), 0.04)
	# decorative houses with pitched roofs
	for h in Map.HOUSES:
		var r:Rect2 = h.rect
		var c := r.get_center()
		var wall := hex(["f7dcae", "a9dccb", "f6bcab"][int(h.style) % 3])
		var roof := hex(["dc6553", "5384c0", "5aa572"][int(h.style) % 3])
		k.box(Kit.at(c.x, 1.1, c.y), Vector3(r.size.x - 0.3, 2.2, r.size.y - 0.3), wall, 0.08)
		k.roof(Kit.rot(c.x, 2.2, c.y, PI * 0.5), r.size.y + 0.4, 1.3, r.size.x + 0.2, roof, 0.16, 0.05)
	# the party house
	var b:Rect2 = Map.BASE
	var bc := b.get_center()
	k.box(Kit.at(bc.x, 1.7, bc.y), Vector3(b.size.x - 0.2, 3.4, b.size.y - 0.2), hex("ffd99a"), 0.1)
	k.roof(Kit.rot(bc.x, 3.4, bc.y, PI * 0.5), b.size.y + 0.7, 1.9, b.size.x + 0.5, hex("4c7fc0"), 0.18, 0.06)
	k.box(Kit.at(bc.x, 1.1, bc.y + b.size.y * 0.5 + 0.1), Vector3(1.0, 2.0, 0.1), hex("3f6f9f"), 0.03)
	# props, trees and cars
	for p in Map.PROPS:
		var r:Rect2 = p.rect
		var c := r.get_center()
		match p.kind:
			"fountain":
				k.cylinder(Kit.at(c.x, 0.4, c.y), 2.0, 2.1, 0.8, hex("d9d2c5"), 20)
				k.cylinder(Kit.at(c.x, 0.82, c.y), 1.7, 1.7, 0.06, hex("6fc3e8"), 20)
				k.cylinder(Kit.at(c.x, 1.4, c.y), 0.3, 0.4, 1.2, hex("d9d2c5"), 10)
			"kiosk":
				k.box(Kit.at(c.x, 0.8, c.y), Vector3(2.6, 1.6, 2.6), hex("e9dcc6"), 0.08)
				k.cylinder(Kit.at(c.x, 2.0, c.y), 2.0, 0.1, 1.0, hex("e85d5d"), 8)
			_:
				k.box(Kit.at(c.x, 0.5, c.y), Vector3(0.7, 1.0, 0.7), hex("e8463c"), 0.05)
	for t in Map.TREES:
		k.cylinder(Kit.at(t.x, 0.5, t.y), 0.18, 0.25, 1.0, hex("8b5e3c"), 6)
		k.sphere(Kit.at(t.x, 1.9, t.y), Vector3(1.0, 1.0, 1.0), hex("5fb85a"), 10, 7, 0.2)
	for car in Map.cars():
		var c:Vector2 = car[0]
		var yaw:float = car[1]
		k.box(Kit.rot(c.x, 0.5, c.y, -yaw), Vector3(1.7, 0.7, 3.2), hex("ef8f8f"), 0.2)
		k.box(Kit.rot(c.x, 1.0, c.y, -yaw), Vector3(1.4, 0.5, 1.6), hex("8fc3e8"), 0.15)
	var m := MeshInstance3D.new()
	m.mesh = k.commit()
	m.material_override = toon
	root.add_child(m)
	# properties: taller blocks, tinted by whether they belong to the neighbourhood
	for i in Map.SITES.size():
		var s:Dictionary = Map.SITES[i]
		var r:Rect2 = s.rect
		var c := r.get_center()
		var sk := Kit.new()
		sk.box(Kit.at(c.x, 1.7, c.y), Vector3(r.size.x - 0.2, 3.4, r.size.y - 0.2), Color.WHITE, 0.1)
		sk.box(Kit.at(c.x, 3.55, c.y), Vector3(r.size.x + 0.2, 0.3, r.size.y + 0.2), Color(0.8, 0.8, 0.8), 0.06)
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
	place(big_cam, Vector3(0, 0, 1.5), 0.0, 112.0)
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
