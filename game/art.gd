extends Node3D
## Reused meshes and materials keep the small festival props inexpensive.
var materials := {}
var sphere := SphereMesh.new()
var cube := BoxMesh.new()
var pennants := []
var bulbs := []
var wheel := Node3D.new()
var gondolas:Array[Node3D] = []
var sun := DirectionalLight3D.new()
var env := Environment.new()
var obstacles:Array[AABB] = []
var sky_paint := ShaderMaterial.new()
var contact := ShaderMaterial.new()
var shadow_plane := PlaneMesh.new()
var cylinders := CylinderMesh.new()
var textures := {}
const SURFACES = {
	"road":preload("res://game/materials/asphalt.jpg"),
	"grass":preload("res://game/materials/meadow.jpg"),
	"stone":preload("res://game/materials/pavers.jpg"),
	"tile":preload("res://game/materials/scales.jpg")
}
const COATS = ["e7a34e","e8d7b1","547da0","d46d60"]

func _init():
	contact.shader = preload("res://game/materials/contact.gdshader")
	shadow_plane.size = Vector2.ONE
	cylinders.radial_segments = 14
	cylinders.rings = 0
	cylinders.height = 1
	cylinders.top_radius = 0.5
	cylinders.bottom_radius = 0.5
	sphere.radial_segments = 18
	sphere.rings = 10
	sphere.radius = 0.5
	sphere.height = 1

func mat(color:String):
	if not materials.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(color)
		m.roughness = 0.86
		materials[color] = m
	return materials[color]

func part(parent:Node3D,pos:Vector3,size:Vector3,color:String,round_shape:=false) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = sphere if round_shape else cube
	n.material_override = mat(color)
	parent.add_child(n)
	n.position = pos
	n.scale = size
	return n

func box(p,x,y,z,w,h,d,c):
	return part(p,Vector3(x,y,z),Vector3(w,h,d),c)

func oval(p,x,y,z,w,h,d,c):
	return part(p,Vector3(x,y,z),Vector3(w,h,d),c,true)

func surface(n:MeshInstance3D,kind:String,tint:String,freq:float):
	var key := kind+tint+str(freq)
	if not textures.has(key):
		var m := ShaderMaterial.new()
		m.shader = preload("res://game/materials/masonry.gdshader")
		m.set_shader_parameter("pattern",SURFACES[kind])
		m.set_shader_parameter("pigment",Color(tint))
		m.set_shader_parameter("frequency",freq)
		textures[key] = m
	n.material_override = textures[key]

func shadow(parent:Node3D,at:Vector3,width:float,depth:float):
	var shade := MeshInstance3D.new()
	shade.mesh = shadow_plane
	shade.material_override = contact
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(shade)
	shade.position = at
	shade.scale = Vector3(width,1,depth)

func glow(n:MeshInstance3D,color:String,energy:float):
	var key := "light"+color+str(energy)
	if not materials.has(key):
		var m:StandardMaterial3D = mat(color).duplicate()
		m.emission_enabled = true
		m.emission = Color(color)
		m.emission_energy_multiplier = energy
		materials[key] = m
	n.material_override = materials[key]

func rod(parent:Node3D,a:Vector3,b:Vector3,width:float,color:String):
	var n := MeshInstance3D.new()
	n.mesh = cylinders
	n.material_override = mat(color)
	parent.add_child(n)
	var axis := (b-a).normalized()
	var side := axis.cross(Vector3.RIGHT if absf(axis.x)<0.9 else Vector3.UP).normalized()
	n.transform = Transform3D(Basis(side,axis,side.cross(axis)).scaled_local(Vector3(width,a.distance_to(b),width)),(a+b)*0.5)
	return n

func strand(a:Vector3,b:Vector3,count:int,sag:float):
	var prev := a
	for j in range(1,count+1):
		var f := float(j)/count
		var at := a.lerp(b,f)-Vector3.UP*sin(PI*f)*sag
		rod(self,prev,at,0.026,"453b40")
		rod(self,at,at-Vector3.UP*0.13,0.042,"50423f")
		var hue:String = ["ffac58","fc7965","8ad5ba","ffd68b"][j%4]
		glow(part(self,at-Vector3.UP*0.23,Vector3(0.17,0.23,0.17),hue,true),hue,1.15)
		prev = at

func label3(p,caption,pos,size):
	var l := Label3D.new()
	p.add_child(l)
	l.position = pos
	l.text = caption
	l.font_size = 64
	l.pixel_size = size
	l.outline_size = 7
	l.modulate = Color("fff2c9")
	return l

func house(x,z,color,main:=false):
	var h := Node3D.new()
	add_child(h)
	h.position = Vector3(x,0,z)
	shadow(h,Vector3(0,0.09,0),6.65,6.4)
	obstacles.append(AABB(h.position+Vector3(-2.60,-0.1,-2.46),Vector3(5.2,3.46,4.92)))
	box(h,0,1.05,0,4.7,2.1,4.2,color)
	box(h,0,0.17,0,4.9,0.34,4.4,"877977")
	for sign_x in [-1,1]:
		var roof = box(h,sign_x*1.27,2.68,0,3.0,0.26,4.9,"446273" if main else "ad6562")
		roof.rotation.z = -sign_x*0.42
		surface(roof,"tile","638c9c" if main else ["db8873","98a4a3","bd897d"][int(abs(x+z))%3],0.93)
		for side_z in [-1,1]:
			var trim = box(h,sign_x*1.27,2.62,side_z*2.47,3.02,0.15,0.12,"f0ce9a")
			trim.rotation.z = roof.rotation.z
		# Fill the triangular gable with vertical timber boards below the rafters.
		for j in 8:
			var xx:float = sign_x*(j+0.5)*0.29
			var ht := maxf(0.06,1.02-absf(xx)*0.44)
			box(h,xx,2.08+ht/2,0,0.28,ht,4.16,"c99870" if main else color)
		for zz in [-1.16,1.15]:
			box(h,sign_x*2.36,1.19,zz,0.12,1.13,0.91,"344a52")
			glow(box(h,sign_x*2.44,1.21,zz,0.07,0.89,0.72,"f5b765"),"f4aa58",0.43)
			box(h,sign_x*2.49,1.18,zz,0.05,0.065,0.73,"5e6260")
			box(h,sign_x*2.49,1.18,zz,0.05,0.94,0.06,"5e6260")
		box(h,sign_x*2.28,1.05,2.15,0.15,2.0,0.16,"9a765f")
		for shutter in [-1,1]:
			box(h,sign_x*1.48+shutter*0.68,1.19,2.18,0.23,1.02,0.09,"517c78")
			for y in [0.86,1.07,1.28,1.49]:
				box(h,sign_x*1.48+shutter*0.68,y,2.24,0.21,0.032,0.035,"82a098")
		box(h,sign_x*1.48,1.17,2.12,1.07,1.14,0.11,"37535b")
		glow(box(h,sign_x*1.48,1.17,2.2,0.85,0.91,0.08,"ffd380"),"ffc16b",0.6)
		box(h,sign_x*1.48,1.17,2.26,0.06,0.91,0.06,"597074")
		box(h,sign_x*1.48,0.63,2.25,1.22,0.12,0.3,"f6e3b6")
	# Even the service side faces a playable street.
	for xx in [-1.35,1.25]:
		box(h,xx,1.19,-2.14,0.99,1.12,0.1,"425764")
		glow(box(h,xx,1.21,-2.21,0.77,0.88,0.06,"e7b780"),"e7b780",0.31)
		box(h,xx,1.18,-2.26,0.065,0.93,0.055,"776b5f")
		box(h,xx,1.18,-2.26,0.83,0.05,0.055,"776b5f")
		box(h,xx,0.64,-2.22,1.12,0.11,0.34,"ba9c81")
	box(h,0,0.07,2.43,1.25,0.14,0.53,"b39579")
	box(h,0,0.86,2.14,0.9,1.72,0.15,"355b63")
	oval(h,0.29,0.86,2.27,0.12,0.12,0.09,"ffc969")
	box(h,-1.45,3.05,-1.3,0.53,1.3,0.64,"aa655b")
	box(h,-1.45,3.72,-1.3,0.68,0.17,0.78,"704f4e")
	if main:
		glow(oval(h,0,2.68,2.13,0.47,0.47,0.1,"ffd984"),"f6ba60",0.8)
		box(h,0,2.7,2.21,0.035,0.17,0.035,"674c48")
		box(h,0.05,2.64,2.21,0.13,0.04,0.035,"674c48")
		for side in [-1,1]:
			box(h,side*1.46,0.64,2.42,1.16,0.28,0.34,"9c604c")
			for j in 6:
				var px:float = side*1.46+(j-2.5)*0.17
				oval(h,px,0.83,2.43,0.28,0.25,0.28,"618d6b")
				oval(h,px,0.96,2.43,0.16,0.14,0.15,"e5837c" if j%2 else "e6b555")
		box(h,0,2.02,2.38,2.86,0.67,0.14,"a98559")
		box(h,0,2.02,2.45,2.74,0.54,0.12,"284e54")
		label3(h,"LA VERBENA",Vector3(0,2.02,2.53),0.0042)

func build_world():
	var world := WorldEnvironment.new()
	add_child(world)
	world.environment = env
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.91
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	sky_paint.shader = preload("res://game/materials/festival_sky.gdshader")
	env.sky.sky_material = sky_paint
	env.fog_enabled = true
	env.fog_density = 0.009
	env.fog_sky_affect = 0.18
	env.ambient_light_sky_contribution = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_light_energy = 0.64
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("dce7ff")
	add_child(sun)
	sun.rotation_degrees = Vector3(-31,-41,0)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	surface(box(self,0,-0.36,0,135,0.65,135,"8cb38b"),"grass","8ca977",0.63)
	for x in [-7,7]:
		surface(box(self,x,-0.022,0,3.2,0.07,68,"7b8588"),"road","87949a",0.72)
		for z in range(-30,31,3): box(self,x,0.025,z,0.08,0.025,1.1,"e0ceac")
	for z in [-6,6]:
		surface(box(self,0,-0.016,z,68,0.07,2.6,"859094"),"road","87949a",0.72)
	surface(box(self,0,0.02,0,10.8,0.08,10.8,"ccc69b"),"stone","d5bda0",0.44)
	house(0,0,"e9bd78",true)
	for i in 4:
		var point:Vector2 = preload("res://game/match.gd").CACHES[i]
		var stall := Node3D.new()
		add_child(stall)
		stall.position = Vector3(point.x,0,point.y-2.1)
		obstacles.append(AABB(stall.position+Vector3(-1.34,0,-0.95),Vector3(2.68,2.3,1.9)))
		var accent:String = ["bd7657","5f998d","c59354","7c82a7"][i]
		box(stall,0,0.48,0,2.5,0.95,1.2,accent)
		for side in [-1,1]: box(stall,side*1.08,1.36,0,0.1,1.8,0.1,"775f50")
		for j in 4:
			var px:float = (j-1.5)*0.49
			match i:
				0:
					box(stall,px,1.06,0,0.37,0.16,0.27,"826e5a")
					rod(stall,Vector3(px-0.12,1.18,0),Vector3(px+0.13,1.18,0),0.065,"97a9a6")
				1:
					rod(stall,Vector3(px,0.97,0.1),Vector3(px,1.27,0.1),0.17,"dfd5ba")
					box(stall,px,1.11,0.19,0.12,0.09,0.02,"b86a61")
				2:
					oval(stall,px,1.08,0.03,0.25,0.23,0.23,"ce7a5d")
					oval(stall,px+0.10,1.12,-0.18,0.25,0.23,0.22,"e0ac66")
				3:
					box(stall,px,1.10,0,0.41,0.27,0.38,"ac7859")
					box(stall,px,1.11,0,0.08,0.29,0.39,"ddbf8c")
		for stripe in 7:
			var cloth = box(stall,(stripe-3)*0.38,2.16,0,0.38,0.12,1.9,accent if stripe%2 else "e8d8ab")
			cloth.rotation.x = 0.1
			box(stall,(stripe-3)*0.38,1.99,0.94,0.38,0.22,0.09,accent if stripe%2 else "e8d8ab")
	for side in [-1,1]:
		for j in 7:
			var x:float = side*(3.13+j*0.43)
			var z:float = -3.5 if j%2 == 0 else -3.64
			oval(self,x,0.20,z,0.66,0.48,0.72,"679371")
			oval(self,x+0.11,0.46,z,0.21,0.22,0.21,"e3aa71")
	for x in [-15,-5,5,15]:
		for z in [-18,18]: house(x,z,["d9a599","98b8b1","d5bc91"][absi(x+z)%3])
	for x in [-19,19]:
		for z in [-8,2,10]: house(x,z,"9fbeb1")
	for i in 54:
		var angle := i*2.39996
		var x := cos(angle)*(18+i%11)
		var z := sin(angle)*(20+i%8)
		rod(self,Vector3(x,0,z),Vector3(x+0.12,2.05,z),0.48,"80624e")
		oval(self,x,2.25,z,2.8,3.5,2.5,["74a47b","639584","90ad77"][i%3])
		for j in 4:
			var angle_j := angle+j*1.59
			var at := Vector3(x+cos(angle_j)*0.95,2.8+0.31*sin(j*2.3),z+sin(angle_j)*0.96)
			part(self,at,Vector3(1.74,1.68,1.83),["7b9d72","709477","8ea675"][j%3],true)
	for x in [-10,10]:
		for z in [-5,5]:
			box(self,x,1.65,z,0.12,3.3,0.12,"765e55")
		for j in 15:
			var z := -5+j*10.0/14
			var y := 3.22-0.52*sin(j*PI/14)
			box(self,x,y,z,0.04,0.04,0.74,"5a6564")
			var flag = box(self,x,y-0.16,z,0.05,0.32,0.31,["f4b856","dc796c","80bdba"][j%3])
			flag.rotation.y = 0.67
			pennants.append(flag)
	for at in [Vector3(-2.7,1.8,2.8),Vector3(2.7,1.8,2.8)]:
		box(self,at.x,0.9,at.z,0.13,1.8,0.13,"69594d")
		oval(self,at.x,1.9,at.z,0.53,0.56,0.53,"ffe3a2")
		var lamp := OmniLight3D.new()
		add_child(lamp)
		lamp.position = at
		lamp.light_color = Color("ffba67")
		lamp.omni_range = 7
		bulbs.append(lamp)

	street_details()
	batch_scenery()
	fair_wheel()
	chimney_smoke()

func lighting(night:float,t:float):
	wheel.rotation.z = t*0.065
	for cabin in gondolas: cabin.rotation.z = -wheel.rotation.z
	sun.light_energy = lerpf(0.65,0.31,night)
	env.ambient_light_energy = lerpf(0.40,0.32,night)
	sky_paint.set_shader_parameter("night",night)
	env.fog_light_color = Color("cea994").lerp(Color("625773"),night)
	env.ambient_light_color = Color("dde4f1").lerp(Color("a0afdc"),night)
	sun.light_color = Color("ffe9d1").lerp(Color("afc9ff"),night)
	for l in bulbs: l.light_energy = night*2.4
	for i in pennants.size(): pennants[i].rotation.x = 0.15*sin(t*2+i)

func actor(role:int,zombie:=false) -> Node3D:
	var a := Node3D.new()
	add_child(a)
	shadow(a,Vector3(0,0.095,0),1.26,0.94)
	var body := Node3D.new()
	body.name = "Body"
	a.add_child(body)
	var coat:String = ["9783a0","ce776a","678987"][role] if zombie else COATS[role]
	var skin:String = "a2c89a" if zombie else ["c88f6c","99684e","e5af87","be845c"][role]
	oval(body,0,0.79,0,0.78,0.95,0.64,coat)
	oval(body,0,1.45,0,0.85,0.78,0.76,skin)
	for side in [-1,1]:
		oval(body,side*0.17,1.48,0.335,0.10,0.14,0.08,"332f40")
		oval(body,side*0.37,1.40,0,0.18,0.25,0.19,skin)
		var arm = oval(body,side*0.39,0.91,0.14,0.24,0.63,0.28,coat)
		arm.rotation.x = -0.9 if zombie else -0.32
		var foot = oval(body,side*0.21,0.25,0.06,0.30,0.5,0.44,"374856")
		foot.name = "Left" if side < 0 else "Right"
	oval(body,0,1.71,-0.03,0.91,0.36,0.81,"51454b" if zombie else coat)
	if zombie:
		var leaf = oval(body,0.14,1.95,0,0.25,0.48,0.16,"9abd7e")
		leaf.rotation.z = -0.6
		box(body,0.1,1.29,0.32,0.11,0.12,0.08,"f5e4bd")
		if role == 2: a.scale *= 1.35
		if role == 1: a.scale *= 0.84
	else:
		box(body,0,1.65,0.39,0.6,0.08,0.27,coat)
		box(body,0.38,0.91,0.43,0.18,0.18,0.42,"93684b")
		rod(body,Vector3(0.38,0.94,0.4),Vector3(0.38,0.94,0.79),0.16,"647b80")
		rod(body,Vector3(0.38,0.94,0.72),Vector3(0.38,0.94,0.83),0.19,"d6ac74")
		rod(body,Vector3(0.38,0.94,0.83),Vector3(0.38,0.94,0.87),0.12,"bd8a59")
	# Model the back as carefully as the face: it is the primary silhouette in play.
	oval(body,0,1.39,0.40,0.18,0.16,0.18,skin)
	for side in [-1,1]:
		oval(body,side*0.18,1.5,0.381,0.034,0.044,0.027,"fff2cf")
		var brow = oval(body,side*0.18,1.595,0.32,0.18,0.055,0.11,"56454a")
		brow.rotation.z = side*(0.32 if zombie else 0.13)
		oval(body,side*0.37,0.76,0.31,0.22,0.24,0.22,skin)
		oval(body,side*0.22,0.12,0.14,0.31,0.21,0.41,"634b46")
	if zombie:
		for j in 4:
			var leaf = oval(body,(j-1.5)*0.13,1.86+0.08*sin(j),-0.03,0.17,0.49,0.19,["6b9163","afbd75"][j%2])
			leaf.rotation.z = (j-1.5)*0.42
		if role == 2:
			for side in [-1,1]: oval(body,side*0.38,1.08,0,0.46,0.38,0.53,"958478")
		if role == 1:
			oval(body,0,1.14,0,0.72,0.17,0.64,"e6b16b")
	else:
		var accent:String = ["d79546","b86365","64849b","68936e"][role]
		oval(body,0,1.13,0,0.71,0.20,0.68,"c46b4e")
		for side in [-1,1]:
			oval(body,side*0.22,0.86,0.24,0.12,0.56,0.12,"735642")
			oval(body,side*0.31,1.63,0.25,0.25,0.24,0.27,"59433c")
		oval(body,0,0.82,-0.32,0.70,0.77,0.39,"71503f")
		box(body,0,0.91,-0.49,0.47,0.30,0.10,accent)
		box(body,0,0.73,-0.56,0.11,0.17,0.06,"e4bc75")
		for side in [-1,1]:
			rod(body,Vector3(side*0.24,0.44,-0.38),Vector3(side*0.24,0.73,-0.38),0.12,"a78562")
		for j in 7:
			var angle:float = PI*0.45+j*PI*1.1/6
			oval(body,sin(angle)*0.34,1.56+0.04*cos(j*2),cos(angle)*0.31,0.26,0.28,0.24,"624739")
		rod(body,Vector3(-0.33,1.08,-0.35),Vector3(0.33,1.08,-0.35),0.22,"9aa790")
		for side in [-1,1]:
			rod(body,Vector3(side*0.23-0.028,1.08,-0.35),Vector3(side*0.23+0.028,1.08,-0.35),0.232,"715542")
		if role == 0:
			for side in [-1,1]:
				oval(body,side*0.17,1.75,0.29,0.30,0.23,0.16,"705345")
				oval(body,side*0.17,1.76,0.36,0.21,0.14,0.09,"9dccce")
			rod(body,Vector3(0.15,0.83,-0.43),Vector3(0.36,1.18,-0.43),0.08,"7f9494")
		elif role == 1:
			box(body,0,0.91,-0.56,0.23,0.08,0.035,"fff2ca")
			box(body,0,0.91,-0.56,0.08,0.23,0.035,"fff2ca")
		elif role == 2:
			oval(body,0,1.74,-0.02,0.96,0.42,0.87,"596f7d")
			oval(body,0,1.67,0,1.02,0.12,0.92,"445660")
		else:
			oval(body,0,1.70,0,1.10,0.11,0.91,"a57e4d")
			rod(body,Vector3(-0.33,1.72,0),Vector3(-0.49,1.99,0.04),0.09,"bd785d")
	return a

func fair_wheel():
	add_child(wheel)
	wheel.position = Vector3(-14,7.9,-32)
	for j in 20:
		var a := Vector3(cos(j*TAU/20),sin(j*TAU/20),0)*5.5
		var b := Vector3(cos((j+1)*TAU/20),sin((j+1)*TAU/20),0)*5.5
		rod(wheel,a,b,0.16,"e5ba8f")
		rod(wheel,Vector3.ZERO,a,0.07,"cc9b83")
		glow(part(wheel,a,Vector3.ONE*0.20,"ffe09a",true),"ffd58b",0.9)
		if j%2 == 0:
			var cabin := Node3D.new()
			wheel.add_child(cabin)
			cabin.position = a
			rod(cabin,Vector3.ZERO,-Vector3.UP*0.52,0.07,"735e65")
			part(cabin,-Vector3.UP*0.72,Vector3(0.9,0.43,0.64),["c96c59","e0ab65","6e9997"][j%3],true)
			gondolas.append(cabin)

func chimney_smoke():
	var smoke := CPUParticles3D.new()
	smoke.amount = 10
	smoke.lifetime = 3.0
	smoke.preprocess = 3.0
	smoke.direction = Vector3(0.42,1,0.08).normalized()
	smoke.spread = 6.0
	smoke.initial_velocity_min = 0.45
	smoke.initial_velocity_max = 0.69
	smoke.gravity = Vector3(0.12,0.12,0.04)
	smoke.scale_amount_min = 0.32
	smoke.scale_amount_max = 0.45
	var growth := Curve.new()
	growth.add_point(Vector2(0,0.32))
	growth.add_point(Vector2(1,1))
	smoke.scale_amount_curve = growth
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(0.8,0.78,0.72,0.27),Color(0.94,0.89,0.85,0)])
	smoke.color_ramp = fade
	var vapor := StandardMaterial3D.new()
	vapor.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vapor.vertex_color_use_as_albedo = true
	smoke.mesh = sphere
	smoke.material_override = vapor
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke)
	smoke.position = Vector3(-1.45,3.85,-1.3)

func street_details():
	var rng := RandomNumberGenerator.new()
	rng.seed = 31742
	# Silhouettes of the old fair and the hills establish a horizon from street level.
	for i in 28:
		var angle := i*TAU/28
		var radius := rng.randf_range(57,72)
		oval(self,cos(angle)*radius,-4,sin(angle)*radius,26,rng.randf_range(15,31),23,["738c91","798599","658f89"][i%3])
	var hub := Vector3(-14,7.9,-32)
	for x in [-3.2,3.2]:
		rod(self,hub+Vector3(x,-7.9,0),hub,0.24,"ad7562")
	# Overhead garlands cross the play space and lead the eye back to the clubhouse.
	for z in [-4.3,4.3]:
		for x in [-4.6,4.6]:
			rod(self,Vector3(x,0,z),Vector3(x,3.7,z),0.11,"6e5140")
			oval(self,x,3.72,z,0.22,0.23,0.22,"d8aa6b")
		strand(Vector3(-4.6,3.65,z),Vector3(4.6,3.65,z),15,0.43)
	for side in [-1,1]:
		strand(Vector3(side*4.6,3.65,-4.3),Vector3(side*4.6,3.65,4.3),11,0.50)
		for z in [-10.5,10.5]:
			var x:float = side*8.8
			rod(self,Vector3(x,0,z),Vector3(x,3.3,z),0.16,"405855")
			rod(self,Vector3(x,3.24,z),Vector3(x-side*0.63,3.24,z),0.11,"405855")
			var shade = oval(self,x-side*0.62,3.11,z,0.66,0.25,0.66,"4d7169")
			glow(oval(self,shade.position.x,2.95,z,0.38,0.30,0.38,"ffe1a4"),"ffd697",1.2)
		for z in range(-14,15,2):
			if abs(z) in [4,6,8]: continue
			surface(box(self,side*9,0.018,z,0.77,0.085,1.92,"d6c8a6"),"stone","c8b6a0",0.43)
		for j in 3:
			var x:float = side*(11+j*1.25)
			for z in [-13,13]:
				box(self,x,0.48,z,0.14,0.96,0.14,"e1c7a4")
				box(self,x+side*0.59,0.63,z,1.25,0.12,0.08,"d2b99d")
	# Flush crosswalks and storm drains give the streets scale without adding cover.
	for z in [-6.0,6.0]:
		for x in [-7.0,7.0]:
			for side in [-1,1]:
				for j in 5:
					box(self,x-1.08+j*0.54,0.032,z+side*1.95,0.29,0.012,0.76,"dacba7")
				var grate_x:float = x+side*1.39
				box(self,grate_x,0.034,z+2.91,0.38,0.018,0.57,"4b5a5b")
				for j in 5: box(self,grate_x,0.045,z+2.71+j*0.1,0.33,0.012,0.037,"7d8580")
	for z in [-11.7,11.7]:
		for x in [-3.2,3.2]:
			var pot = rod(self,Vector3(x,0,z),Vector3(x,0.49,z),0.67,"ad7054")
			rod(self,pot.position+Vector3.UP*0.18,pot.position+Vector3.UP*0.28,0.74,"bc8365")
			for j in 8:
				var at := Vector3(x+0.19*cos(j*2.4),0.65+j%3*0.075,z+0.2*sin(j*2.4))
				part(self,at,Vector3(0.29,0.48,0.26),"5c8369",true)
				part(self,at+Vector3.UP*0.21,Vector3(0.17,0.14,0.16),"d58a81" if j%2 else "edbb65",true)
	for i in 95:
		var x := rng.randf_range(-21,21)
		var z := rng.randf_range(-19,19)
		if absf(x)<9.3 or absf(z)<2.5 or absf(absf(z)-6)<1.6: continue
		for j in 4:
			var offset := Vector3(rng.randf_range(-0.34,0.34),0,rng.randf_range(-0.32,0.32))
			var base := Vector3(x,0,z)+offset
			var tip := base+Vector3(0.06,rng.randf_range(0.15,0.39),0.03)
			rod(self,base,tip,0.028,"497352")
			part(self,tip,Vector3(0.14,0.09,0.14),["eec58a","e0a7ad","afbcca"][i%3],true)
	for i in 20:
		var angle := i*TAU/20
		var x := cos(angle)*rng.randf_range(22,27)
		var z := sin(angle)*rng.randf_range(23,28)
		var ht := rng.randf_range(3.2,5.0)
		rod(self,Vector3(x,0,z),Vector3(x,ht,z),0.42,"825e48")
		for j in 6:
			var crown := Vector3(x+cos(j*2.4)*1.25,ht+j*0.19,z+sin(j*2.4)*1.25)
			rod(self,Vector3(x,ht*0.60,z),crown,0.19,"866b52")
			part(self,crown,Vector3(2.8,2.2,2.6),["6e9676","89a775","829f7c"][j%3],true)
	for x in [-12,12]:
		for z in [-2,2]:
			box(self,x,0.47,z,1.68,0.14,0.55,"b07a50")
			for offset in [-0.58,0.58]: box(self,x+offset,0.24,z,0.12,0.48,0.4,"496565")
			box(self,x,0.83,z-0.24,1.68,0.23,0.11,"c09568")

func batch_scenery():
	# Combine immobile props by mesh, material and street block for instanced drawing.
	var groups := {}
	for n in find_children("*","MeshInstance3D",true,false):
		if n in pennants: continue
		var zone:Vector3 = n.global_position/16.0
		var key := "%d/%d/%d/%d" % [n.mesh.get_instance_id(),n.material_override.get_instance_id(),floori(zone.x),floori(zone.z)]
		if not groups.has(key): groups[key] = []
		groups[key].append(n)
	for nodes in groups.values():
		if nodes.size()<2: continue
		var inst := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = nodes[0].mesh
		mm.instance_count = nodes.size()
		inst.material_override = nodes[0].material_override
		inst.multimesh = mm
		add_child(inst)
		for i in nodes.size():
			var n:MeshInstance3D = nodes[i]
			mm.set_instance_transform(i,global_transform.affine_inverse()*n.global_transform)
			n.free()

func burst(at:Vector3,defeated:bool):
	var sparks := CPUParticles3D.new()
	sparks.amount = 16 if defeated else 7
	sparks.lifetime = 0.52
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.direction = Vector3.UP
	sparks.spread = 80
	sparks.gravity = Vector3(0,-7,0)
	sparks.initial_velocity_min = 1.5
	sparks.initial_velocity_max = 3.7
	sparks.angular_velocity_max = 300
	sparks.scale_amount_min = 0.055
	sparks.scale_amount_max = 0.12
	sparks.mesh = cube
	sparks.material_override = mat("e78870" if defeated else "ffcd73")
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sparks)
	sparks.position = at
	sparks.finished.connect(sparks.queue_free)
	sparks.restart()
