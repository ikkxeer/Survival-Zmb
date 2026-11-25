extends SubViewport
## A real 3D book for the map. Leather cover with gold trim, spine, a block of
## pages whose top dips towards the gutter, loose leaves that turn, and the map
## printed on the open spread. `open` runs 0 (closed) to 1 (open and readable);
## everything, including the camera move, is derived from that one number.

const Kit = preload("res://game/view/kit.gd")
const St = preload("res://game/ui/style.gd")

const SS := 1.5
const PW := 5.0                   # width of one page
const PD := 6.0                   # page depth
const COV := 0.14                 # cover thickness
const PAGE_H := 0.25              # height of each half block once open
const MAP_W := 9.6
const MAP_H := MAP_W * 540.0 / 936.0
const SURFACE_Y := COV + PAGE_H   # top of the pages when open
const CREAM := Color("f6ead0")
const CREAM_DARK := Color("d9c9a2")

var open := 0.0:
	set(v):
		open = v
		apply()
var tween:Tween
var cam := Camera3D.new()
var root3d := Node3D.new()
var cover_pivot := Node3D.new()
var spine := Node3D.new()
var left_block := MeshInstance3D.new()
var right_block := MeshInstance3D.new()
var leaves := []
var map_mesh := MeshInstance3D.new()
var map_mat := StandardMaterial3D.new()
var shade_mesh := MeshInstance3D.new()
var shadow := MeshInstance3D.new()
var ribbon := MeshInstance3D.new()
var clock := 0.0
var leather := StandardMaterial3D.new()
var paper := StandardMaterial3D.new()

static func dip(x:float) -> float:
	## How far the page surface sinks into the gutter.
	return 0.13 * exp(-x * x / 1.5)

static func dip_slope(x:float) -> float:
	return 0.13 * exp(-x * x / 1.5) * (2.0 * x / 1.5)

func _init(px:Vector2i = Vector2i(1040, 668)):
	size = Vector2i(Vector2(px) * SS)
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff3e2")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58, -28, 0)
	key.light_energy = 0.62
	key.light_color = Color("fff0d8")
	key.shadow_enabled = true
	key.shadow_blur = 2.0
	key.directional_shadow_max_distance = 40.0
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 150, 0)
	fill.light_energy = 0.15
	fill.light_color = Color("cfe0ff")
	add_child(fill)
	leather.vertex_color_use_as_albedo = true
	leather.vertex_color_is_srgb = true
	leather.roughness = 0.5
	leather.metallic = 0.05
	paper.vertex_color_use_as_albedo = true
	paper.vertex_color_is_srgb = true
	paper.roughness = 0.9
	paper.cull_mode = BaseMaterial3D.CULL_DISABLED
	map_mat.roughness = 1.0
	map_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	map_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	map_mat.emission_enabled = true
	map_mat.emission_energy_multiplier = 0.2
	add_child(root3d)
	cam.fov = 30.0
	cam.far = 120.0
	add_child(cam)
	build()

func _ready():
	apply()

# ------------------------------------------------------------------ geometry
func quad(st:SurfaceTool, p:Array, n:Vector3, c:Color, uv:Array = []):
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_color(c)
		if uv.size() == 4: st.set_uv(uv[idx])
		st.add_vertex(p[idx])

func page_block(x0:float, x1:float) -> ArrayMesh:
	## One half of the page block: top surface following the gutter dip and three
	## side walls showing the edges of the sheets.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 40
	var xs := []
	for i in nx + 1: xs.append(lerpf(x0, x1, float(i) / nx))
	var z0 := -PD * 0.5
	var z1 := PD * 0.5
	for i in nx:
		var a:float = xs[i]
		var b:float = xs[i + 1]
		var ya := PAGE_H - dip(a)
		var yb := PAGE_H - dip(b)
		var n := Vector3(-dip_slope((a + b) * 0.5) * -1.0, 1.0, 0.0).normalized()
		n = Vector3(dip_slope((a + b) * 0.5), 1.0, 0.0).normalized()
		quad(st, [Vector3(a, ya, z0), Vector3(b, yb, z0), Vector3(b, yb, z1), Vector3(a, ya, z1)], n, CREAM.darkened(0.55 * exp(-pow((a + b) * 0.5, 2) / 1.2)))
		# front and back walls: horizontal bands like stacked sheets
		var bands := 8
		for s in bands:
			var c := CREAM if s % 2 == 0 else CREAM_DARK
			var s0 := float(s) / bands
			var s1 := float(s + 1) / bands
			quad(st, [Vector3(a, ya * s0, z1), Vector3(b, yb * s0, z1), Vector3(b, yb * s1, z1), Vector3(a, ya * s1, z1)], Vector3(0, 0, 1), c)
			quad(st, [Vector3(b, yb * s0, z0), Vector3(a, ya * s0, z0), Vector3(a, ya * s1, z0), Vector3(b, yb * s1, z0)], Vector3(0, 0, -1), c)
	var ex := x1 if absf(x1) > absf(x0) else x0
	var sgn := signf(ex)
	var h := PAGE_H - dip(ex)
	for s in 8:
		var c := CREAM if s % 2 == 0 else CREAM_DARK
		var s0 := h * float(s) / 8
		var s1 := h * float(s + 1) / 8
		quad(st, [Vector3(ex, s0, z0), Vector3(ex, s0, z1), Vector3(ex, s1, z1), Vector3(ex, s1, z0)], Vector3(sgn, 0, 0), c)
	return st.commit()

func map_surface() -> ArrayMesh:
	## The printed map: same dip as the pages so it bends into the gutter.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 64
	var nz := 8
	for i in nx:
		for j in nz:
			var xa := -MAP_W * 0.5 + MAP_W * i / nx
			var xb := -MAP_W * 0.5 + MAP_W * (i + 1) / nx
			var za := -MAP_H * 0.5 + MAP_H * j / nz
			var zb := -MAP_H * 0.5 + MAP_H * (j + 1) / nz
			var ya := SURFACE_Y - dip(xa) + 0.006
			var yb := SURFACE_Y - dip(xb) + 0.006
			var n := Vector3(dip_slope((xa + xb) * 0.5), 1.0, 0.0).normalized()
			var uv := [Vector2(float(i) / nx, float(j) / nz), Vector2(float(i + 1) / nx, float(j) / nz), Vector2(float(i + 1) / nx, float(j + 1) / nz), Vector2(float(i) / nx, float(j + 1) / nz)]
			quad(st, [Vector3(xa, ya, za), Vector3(xb, yb, za), Vector3(xb, yb, zb), Vector3(xa, ya, zb)], n, Color.WHITE, uv)
	return st.commit()

func gutter_shade() -> ArrayMesh:
	## Translucent darkening over the map where the paper curls into the spine.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 64
	for i in nx:
		var xa := -MAP_W * 0.5 + MAP_W * i / nx
		var xb := -MAP_W * 0.5 + MAP_W * (i + 1) / nx
		var ya := SURFACE_Y - dip(xa) + 0.011
		var yb := SURFACE_Y - dip(xb) + 0.011
		var ca := Color(0.12, 0.07, 0.12, 0.5 * exp(-xa * xa / 0.9))
		var cb := Color(0.12, 0.07, 0.12, 0.5 * exp(-xb * xb / 0.9))
		var pts := [Vector3(xa, ya, -MAP_H * 0.5), Vector3(xb, yb, -MAP_H * 0.5), Vector3(xb, yb, MAP_H * 0.5), Vector3(xa, ya, MAP_H * 0.5)]
		var cols := [ca, cb, cb, ca]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_color(cols[idx])
			st.add_vertex(pts[idx])
	return st.commit()

func cover_mesh() -> ArrayMesh:
	## Leather slab, gold frame and corner caps on the outside, endpaper inside.
	var k := Kit.new()
	var cw := PW + 0.25
	var cd := PD + 0.25
	var cx := cw * 0.5
	var brown := Color("6b3f2a")
	var gold := Color("d9b03a")
	k.box(Kit.at(cx, 0, 0), Vector3(cw, COV, cd), brown, 0.05, 0.15)
	k.box(Kit.at(cx, COV * 0.5 + 0.012, 0), Vector3(cw - 0.35, 0.03, cd - 0.35), Color("824f35"), 0.02)
	for z in [-1, 1]: k.box(Kit.at(cx, COV * 0.5 + 0.03, z * (cd * 0.5 - 0.25)), Vector3(cw - 0.5, 0.025, 0.05), gold, 0.01)
	k.box(Kit.at(0.3, COV * 0.5 + 0.03, 0), Vector3(0.05, 0.025, cd - 0.5), gold, 0.01)
	k.box(Kit.at(cw - 0.25, COV * 0.5 + 0.03, 0), Vector3(0.05, 0.025, cd - 0.5), gold, 0.01)
	for x in [0.28, cw - 0.28]:
		for z in [-1, 1]: k.box(Kit.at(x, COV * 0.5 + 0.02, z * (cd * 0.5 - 0.28)), Vector3(0.34, 0.045, 0.34), gold, 0.03)
	k.cylinder(Kit.at(cx, COV * 0.5 + 0.03, 0.9), 0.62, 0.62, 0.03, gold, 28)
	k.cylinder(Kit.at(cx, COV * 0.5 + 0.05, 0.9), 0.5, 0.5, 0.03, Color("8a5638"), 28)
	# emblem: a little house under a string of bunting
	k.box(Kit.at(cx, COV * 0.5 + 0.1, 0.98), Vector3(0.42, 0.06, 0.3), gold, 0.01)
	k.roof(Kit.rot(cx, COV * 0.5 + 0.13, 0.98, PI * 0.5), 0.5, 0.2, 0.5, gold.lightened(0.1), 0.03, 0.01)
	for i in 5: k.box(Kit.rot(cx - 0.42 + i * 0.21, COV * 0.5 + 0.06, 0.55 + 0.03 * sin(i * 0.8 * PI / 2.0), 0.0), Vector3(0.1, 0.02, 0.1), gold.lightened(0.15 * (i % 2)), 0.0)
	k.box(Kit.at(cx, -COV * 0.5 - 0.012, 0), Vector3(cw - 0.3, 0.03, cd - 0.3), Color("efe0bc"), 0.02)
	return k.commit()

func build():
	# soft contact shadow under the book
	var sq := QuadMesh.new()
	sq.orientation = PlaneMesh.FACE_Y
	sq.size = Vector2(16, 10)
	shadow.mesh = sq
	var sm := ShaderMaterial.new()
	sm.shader = load("res://game/shaders/soft.gdshader")
	sm.set_shader_parameter("color", Color(0.1, 0.05, 0.12, 0.55))
	shadow.material_override = sm
	shadow.position.y = -0.02
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3d.add_child(shadow)
	# back cover and spine
	var bk := Kit.new()
	bk.box(Kit.at((PW + 0.25) * 0.5, COV * 0.5, 0), Vector3(PW + 0.25, COV, PD + 0.25), Color("6b3f2a"), 0.05, 0.15)
	bk.box(Kit.at(-0.1, COV * 0.5, 0), Vector3(0.24, COV, PD + 0.25), Color("5a3322"), 0.04)
	var back := MeshInstance3D.new()
	back.mesh = bk.commit()
	back.material_override = leather
	root3d.add_child(back)
	var sp := Kit.new()
	var hc := 2.0 * COV + 2.0 * PAGE_H
	sp.box(Kit.at(-0.1, hc * 0.5, 0), Vector3(0.22, hc, PD + 0.25), Color("5a3322"), 0.06, 0.2)
	for i in 3: sp.box(Kit.at(-0.2, hc * (0.2 + i * 0.3), 0), Vector3(0.04, 0.04, PD + 0.3), Color("d9b03a"), 0.01)
	var spm := MeshInstance3D.new()
	spm.mesh = sp.commit()
	spm.material_override = leather
	spine.add_child(spm)
	root3d.add_child(spine)
	# page blocks
	right_block.mesh = page_block(0.0, PW)
	left_block.mesh = page_block(-PW, 0.0)
	for b in [right_block, left_block]:
		b.material_override = paper
		b.position.y = COV
		root3d.add_child(b)
	# turning leaves
	for i in 3:
		var lk := Kit.new()
		lk.box(Kit.at(PW * 0.5, 0, 0), Vector3(PW - 0.05, 0.025, PD - 0.08), CREAM, 0.01)
		var pivot := Node3D.new()
		var lm := MeshInstance3D.new()
		lm.mesh = lk.commit()
		lm.material_override = leather
		pivot.add_child(lm)
		root3d.add_child(pivot)
		leaves.append(pivot)
	# front cover on its hinge, title lettering on the outside
	var cm := MeshInstance3D.new()
	cm.mesh = cover_mesh()
	cm.material_override = leather
	cover_pivot.add_child(cm)
	var title := Label3D.new()
	title.text = "El barrio"
	title.font = St.font("title", 700)
	title.font_size = 110
	title.pixel_size = 0.0085
	title.modulate = Color("f2cf6a")
	title.outline_size = 10
	title.outline_modulate = Color("3a2014")
	title.rotation_degrees = Vector3(-90, 0, 0)
	title.position = Vector3((PW + 0.25) * 0.5, COV * 0.5 + 0.09, -0.75)
	title.double_sided = false
	cover_pivot.add_child(title)
	var sub := Label3D.new()
	sub.text = "La última verbena"
	sub.font = St.font("body", 700)
	sub.font_size = 64
	sub.pixel_size = 0.0075
	sub.modulate = Color("e8c25a")
	sub.outline_size = 8
	sub.outline_modulate = Color("3a2014")
	sub.rotation_degrees = Vector3(-90, 0, 0)
	sub.position = Vector3((PW + 0.25) * 0.5, COV * 0.5 + 0.09, 1.75)
	sub.double_sided = false
	cover_pivot.add_child(sub)
	root3d.add_child(cover_pivot)
	# printed map on the open spread
	map_mesh.mesh = map_surface()
	map_mesh.material_override = map_mat
	map_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3d.add_child(map_mesh)
	shade_mesh.mesh = gutter_shade()
	var shade_mat := StandardMaterial3D.new()
	shade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shade_mat.vertex_color_use_as_albedo = true
	shade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shade_mesh.material_override = shade_mat
	shade_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3d.add_child(shade_mesh)
	# ribbon bookmark hanging from the gutter over the front edge
	var rk := Kit.new()
	rk.box(Kit.at(0, 0, 0), Vector3(0.3, 0.02, 1.1), Color("b8353a"), 0.01)
	ribbon.mesh = rk.commit()
	ribbon.material_override = leather
	ribbon.position = Vector3(1.6, SURFACE_Y - dip(1.6) - 0.02, PD * 0.5 + 0.12)
	root3d.add_child(ribbon)

func set_map_texture(tex:Texture2D):
	map_mat.albedo_texture = tex
	map_mat.emission_texture = tex

# ------------------------------------------------------------------ animation
static func seg(t:float, a:float, b:float) -> float:
	return smoothstep(a, b, t)

static func ease_io(x:float) -> float:
	return x * x * (3.0 - 2.0 * x)

func apply():
	if not cam.is_inside_tree(): return
	var o := open
	# the book drops in and settles
	var intro := seg(o, 0.0, 0.16)
	root3d.scale = Vector3.ONE * lerpf(0.82, 1.0, intro)
	root3d.position = Vector3(0, lerpf(1.2, 0.0, ease_io(intro)), 0)
	root3d.rotation.y = lerpf(-0.22, 0.0, seg(o, 0.0, 0.7))
	shadow.scale = Vector3.ONE * lerpf(1.2, 1.0, intro)
	(shadow.material_override as ShaderMaterial).set_shader_parameter("color", Color(0.1, 0.05, 0.12, 0.55 * intro))
	# cover swings open about the spine and drops to lie beside the pages
	var cv := ease_io(seg(o, 0.2, 0.62))
	var theta := PI * cv
	cover_pivot.rotation = Vector3(0, 0, theta)
	var closed_y := COV + 2.0 * PAGE_H + COV * 0.5
	cover_pivot.position = Vector3(0, lerpf(closed_y, COV * 0.5, ease_io(clampf((theta - 0.6) / (PI - 0.6), 0.0, 1.0))), 0)
	spine.scale = Vector3(1, lerpf(1.0, COV / (2.0 * COV + 2.0 * PAGE_H) + 0.02, seg(o, 0.3, 0.7)), 1)
	# leaves turn one after the other
	var flipped := 0.0
	for i in leaves.size():
		var f := ease_io(seg(o, 0.42 + 0.11 * i, 0.76 + 0.11 * i))
		flipped += f / leaves.size()
		var pivot:Node3D = leaves[i]
		pivot.visible = f > 0.002 and f < 0.998
		pivot.rotation = Vector3(0, 0.05 * sin(f * PI) * (i - 1), PI * f)
		pivot.position = Vector3(0, lerpf(COV + 2.0 * PAGE_H - 0.01 * i, COV + PAGE_H, f) + sin(f * PI) * 0.18, 0)
	right_block.scale = Vector3(1, 2.0 - flipped, 1)
	left_block.scale = Vector3(1, maxf(0.02, flipped), 1)
	left_block.visible = flipped > 0.01
	# the map prints onto the pages
	var a := seg(o, 0.84, 0.97)
	map_mat.albedo_color = Color(1, 1, 1, a)
	map_mat.emission_energy_multiplier = 0.2 * a
	map_mesh.visible = a > 0.01
	shade_mesh.visible = a > 0.01
	ribbon.visible = a > 0.01
	ribbon.scale = Vector3(1, 1, a)
	# camera: starts on the closed book, pulls back and tilts to read the spread
	var cm := ease_io(seg(o, 0.08, 0.9))
	var target := Vector3(lerpf(PW * 0.5 + 0.1, 0.0, cm), lerpf(0.45, 0.2, cm), lerpf(0.2, 0.1, cm))
	var dist := lerpf(11.5, 14.2, cm)
	var pitch := deg_to_rad(lerpf(40.0, 62.0, cm))
	var yaw := lerpf(-0.28, 0.0, cm) + (sin(clock * 0.5) * 0.006 if o >= 1.0 else 0.0)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.look_at(target, Vector3.UP)

func _process(dt:float):
	clock += dt
	if open >= 1.0 and render_target_update_mode != SubViewport.UPDATE_DISABLED: apply()

func play_open(duration:float = 2.2):
	if tween: tween.kill()
	open = 0.0
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tween = create_tween()
	tween.tween_property(self, "open", 1.0, duration)

func skip_to_open():
	if tween: tween.kill()
	open = 1.0

func stop():
	if tween: tween.kill()
	render_target_update_mode = SubViewport.UPDATE_DISABLED

func is_open() -> bool:
	return open >= 0.97

# ------------------------------------------------------------------ picking
func map_to_screen(map_px:Vector2, map_size:Vector2) -> Vector2:
	## Where a point of the printed map appears in this viewport's control, in its own units.
	var x := (map_px.x / map_size.x - 0.5) * MAP_W
	var z := (map_px.y / map_size.y - 0.5) * MAP_H
	return cam.unproject_position(Vector3(x, SURFACE_Y - dip(x) + 0.006, z)) / SS

func screen_to_map(local:Vector2, map_size:Vector2):
	## Map pixel under a point of the control, or null when it is not on the map.
	var p := local * SS
	var o := cam.project_ray_origin(p)
	var d := cam.project_ray_normal(p)
	var hit = Plane(Vector3.UP, SURFACE_Y).intersects_ray(o, d)
	if hit == null: return null
	for i in 3:
		# the page sinks into the gutter: re-aim at the height of the paper under that point
		hit = Plane(Vector3.UP, SURFACE_Y - dip(hit.x) + 0.006).intersects_ray(o, d)
		if hit == null: return null
	var u:float = (hit.x / MAP_W) + 0.5
	var v:float = (hit.z / MAP_H) + 0.5
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0: return null
	return Vector2(u * map_size.x, v * map_size.y)
