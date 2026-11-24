extends SubViewport
## A tiny 3D "photo" of a game object for the HUD: the same meshes and toon
## material as the world, lit like a sunny afternoon, on a transparent background.
## It renders once and only again when asked (refresh), so it costs nothing per frame.

const Kit = preload("res://game/view/kit.gd")

var cam := Camera3D.new()
var pivot := Node3D.new()

func _init(px:int = 192):
	size = Vector2i(px, px)
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_ONCE
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff1dc")
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -35, 0)
	key.light_energy = 0.9
	key.light_color = Color("fff4e0")
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.25
	fill.light_color = Color("c9d8ff")
	add_child(fill)
	add_child(pivot)
	cam.fov = 28.0
	add_child(cam)

func frame(center:Vector3, distance:float, yaw_deg:float = -32.0, pitch_deg:float = -24.0):
	## Point the camera at `center` from the given angle (a three-quarter view).
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0))
	cam.position = center + b * Vector3(0, 0, distance)
	cam.look_at(center)
	refresh()

func add_mesh(mesh:Mesh, xf:Transform3D, mat:Material):
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	mi.material_override = mat
	pivot.add_child(mi)

func refresh():
	render_target_update_mode = SubViewport.UPDATE_ONCE

static func materials_mesh() -> ArrayMesh:
	## A pallet stacked with planks and a couple of bricks, tied with rope.
	var k := Kit.new()
	var wood := Color("c98a55")
	for z in [-0.42, 0.0, 0.42]: k.box(Kit.at(0, 0.06, z), Vector3(1.3, 0.12, 0.22), wood.darkened(0.2), 0.02)
	k.box(Kit.at(0, 0.16, 0), Vector3(1.3, 0.08, 1.06), wood.darkened(0.08), 0.02)
	for row in 3:
		for i in 4:
			var tint := wood.lightened(0.08 * ((i + row) % 3))
			k.box(Kit.rot(-0.45 + i * 0.3, 0.3 + row * 0.17, 0, 0.03 * ((i * 7 + row) % 3 - 1)), Vector3(0.27, 0.15, 1.0), tint, 0.04, 0.2)
	k.box(Kit.rot(0.25, 0.86, 0.1, 0.4), Vector3(0.42, 0.2, 0.22), Color("e07a5f"), 0.04, 0.2)
	k.box(Kit.rot(-0.2, 0.86, -0.15, -0.2), Vector3(0.42, 0.2, 0.22), Color("d86a50"), 0.04, 0.2)
	for x in [-0.32, 0.32]: k.box(Kit.at(x, 0.48, 0), Vector3(0.05, 0.62, 1.04), Color("e8d3a0"), 0.01)
	return k.commit()
