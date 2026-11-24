extends Node3D
## Reused meshes and materials keep the small festival props inexpensive.
var materials := {}
var sphere := SphereMesh.new()
var cube := BoxMesh.new()
var pennants := []
var bulbs := []
var sun := DirectionalLight3D.new()
var env := Environment.new()
const COATS = ["e7a34e","e8d7b1","547da0","d46d60"]

func _init():
	sphere.radial_segments = 12
	sphere.rings = 6
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
	box(h,0,1.05,0,4.7,2.1,4.2,color)
	box(h,0,0.17,0,4.9,0.34,4.4,"877977")
	for sign_x in [-1,1]:
		var roof = box(h,sign_x*1.27,2.68,0,3.0,0.26,4.9,"446273" if main else "ad6562")
		roof.rotation.z = -sign_x*0.42
		for zz in [-1.8,-0.9,0,0.9,1.8]:
			var seam = box(h,sign_x*1.27,2.80,zz,3.0,0.08,0.08,"62808a" if main else "c88270")
			seam.rotation.z = roof.rotation.z
		box(h,sign_x*1.48,1.17,2.12,1.07,1.14,0.11,"37535b")
		box(h,sign_x*1.48,1.17,2.2,0.85,0.91,0.08,"ffd380")
		box(h,sign_x*1.48,1.17,2.26,0.06,0.91,0.06,"597074")
		box(h,sign_x*1.48,0.63,2.25,1.22,0.12,0.3,"f6e3b6")
	box(h,0,0.86,2.14,0.9,1.72,0.15,"355b63")
	oval(h,0.29,0.86,2.27,0.12,0.12,0.09,"ffc969")
	box(h,-1.45,3.05,-1.3,0.53,1.3,0.64,"aa655b")
	if main:
		box(h,0,2.02,2.4,2.72,0.58,0.15,"254653")
		label3(h,"LA VERBENA",Vector3(0,2.02,2.50),0.0042)

func build_world():
	var world := WorldEnvironment.new()
	add_child(world)
	world.environment = env
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.91
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("dce7ff")
	add_child(sun)
	sun.rotation_degrees = Vector3(-55,-30,0)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	box(self,0,-0.36,0,95,0.65,85,"8cb38b")
	for x in [-7,7]:
		box(self,x,-0.022,0,3.2,0.07,68,"7b8588")
		for z in range(-30,31,3): box(self,x,0.025,z,0.08,0.025,1.1,"e0ceac")
	for z in [-6,6]:
		box(self,0,-0.016,z,68,0.07,2.6,"859094")
	box(self,0,0.02,0,10.8,0.08,10.8,"ccc69b")
	house(0,0,"e9bd78",true)
	for i in 4:
		var point:Vector2 = preload("res://game/match.gd").CACHES[i]
		var stall := Node3D.new()
		add_child(stall)
		stall.position = Vector3(point.x,0,point.y-2.1)
		var accent:String = ["bd7657","5f998d","c59354","7c82a7"][i]
		box(stall,0,0.48,0,2.5,0.95,1.2,accent)
		for side in [-1,1]: box(stall,side*1.08,1.36,0,0.1,1.8,0.1,"775f50")
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
		box(self,x,0.85,z,0.44,1.7,0.48,"86664e")
		oval(self,x,2.25,z,2.8,3.5,2.5,["74a47b","639584","90ad77"][i%3])
		oval(self,x+0.62,2.85,z,1.6,1.72,1.6,"a6bc7e")
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

func lighting(night:float,t:float):
	sun.light_energy = lerpf(1.05,0.37,night)
	env.ambient_light_energy = lerpf(0.75,0.49,night)
	env.background_color = Color("c1dccc").lerp(Color("384965"),night)
	sun.light_color = Color("fff0ca").lerp(Color("afc9ff"),night)
	for l in bulbs: l.light_energy = night*2.4
	for i in pennants.size(): pennants[i].rotation.x = 0.15*sin(t*2+i)

func actor(role:int,zombie:=false) -> Node3D:
	var a := Node3D.new()
	add_child(a)
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
		box(body,0.38,0.91,0.43,0.18,0.20,0.55,"e4bc77")
	return a
