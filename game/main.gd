extends Node3D
const Match = preload("res://game/match.gd")
const Art = preload("res://game/art.gd")
const UI = preload("res://game/interface.gd")
const PORT := 24680
var art := Art.new()
var ui := UI.new()
var camera := Camera3D.new()
var sim := Match.new()
var state := {}
var heroes := {}
var horde := {}
var pads := []
var loot := []
var signs := []
var effects := []
var lights_out := 0.0
var net_clock := 0.0
var age := 0.0
var mode := ""
var chosen := 0
var sound := AudioStreamPlayer.new()

func _ready():
	add_child(art)
	art.build_world()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 23
	camera.position = Vector3(0,19,22)
	camera.look_at(Vector3(0,0,-1))
	camera.current = true
	for i in 4:
		var pos:Vector2 = Match.GATES[i]
		var pad := Node3D.new()
		art.add_child(pad)
		pad.position = Vector3(pos.x,0,pos.y)
		if i%2 == 1: pad.rotation.y = PI/2
		art.box(pad,0,0.09,0,2.7,0.13,1,"708f88")
		var wall := Node3D.new()
		pad.add_child(wall)
		for x in [-1,1]: art.box(wall,x,0.7,0,0.15,1.35,0.17,"755d4a")
		for y in [0.4,0.92]: art.box(wall,0,y,0,2.55,0.30,0.20,"ce945f")
		var coil := Node3D.new()
		pad.add_child(coil)
		art.box(coil,0,0.6,0,0.45,1,0.45,"4b6270")
		for y in [0.52,0.8,1.08]: art.oval(coil,0,y,0,0.85,0.15,0.85,"8bd6ce")
		art.oval(coil,0,1.35,0,0.58,0.58,0.58,"ffe49d")
		wall.hide()
		coil.hide()
		pads.append([wall,coil])
		var c := Node3D.new()
		art.add_child(c)
		var cp:Vector2 = Match.CACHES[i]
		c.position = Vector3(cp.x,0,cp.y)
		art.box(c,0,0.4,0,1.2,0.75,0.95,"c6854e")
		for x in [-0.35,0.35]: art.box(c,x,0.42,0,0.12,0.83,1,"fbe1a2")
		art.label3(c,"+",Vector3(0,1.4,0),0.012)
		loot.append(c)
		var signpost = art.label3(art,Match.SITES[i],Vector3(cp.x,1.9,cp.y-0.9),0.006)
		signpost.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		signs.append(signpost)
	add_child(ui)
	ui.launch.connect(start)
	ui.leave.connect(stop.bind(""))
	multiplayer.peer_disconnected.connect(func(id): sim.players.erase(id))
	multiplayer.connected_to_server.connect(func(): register.rpc_id(1,chosen))
	multiplayer.connection_failed.connect(stop.bind("No se pudo conectar con esa dirección."))
	multiplayer.server_disconnected.connect(stop.bind("El anfitrión ha cerrado la partida."))
	add_child(sound)
	# Generate a short cork pop locally, keeping the project self-contained.
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 22050
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	var bytes := PackedByteArray()
	bytes.resize(3800)
	for i in 1900:
		var t := i/22050.0
		bytes.encode_s16(i*2,int(11000*exp(-52*t)*sin(TAU*(640*t-2300*t*t))))
	stream.data = bytes
	sound.stream = stream
	sound.volume_db = -12

func start(which:String,role:int,address:String):
	if mode != "": return
	chosen = role
	if which != "solo":
		var peer := ENetMultiplayerPeer.new()
		var err:Error
		if which == "host": err = peer.create_server(PORT,3)
		else:
			if address.is_empty():
				ui.status.text = "Introduce la IP del anfitrión."
				return
			err = peer.create_client(address,PORT)
		if err != OK:
			ui.status.text = error_string(err)
			return
		multiplayer.multiplayer_peer = peer
	mode = which
	ui.menu.hide()
	ui.hud.show()
	if mode == "join":
		ui.banner.text = "Conectando…"
		return
	sim = Match.new()
	sim.join(1,chosen)
	state = sim.snapshot()
	apply_state(state)

func stop(reason:String):
	mode = ""
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	state = {}
	for nodes in [heroes,horde]:
		for n in nodes.values(): n.queue_free()
		nodes.clear()
	for pair in pads:
		for n in pair: n.hide()
	for c in loot: c.show()
	ui.status.text = reason
	ui.hud.hide()
	ui.menu.show()

@rpc("any_peer","reliable")
func register(role:int):
	if mode != "host": return
	var id := multiplayer.get_remote_sender_id()
	sim.join(id,role)
	if not sim.players.has(id): multiplayer.multiplayer_peer.disconnect_peer(id)

@rpc("any_peer","call_remote","unreliable_ordered",1)
func controls(move:Vector2,aim:Vector2,fire:bool):
	if mode == "host": sim.drive(multiplayer.get_remote_sender_id(),move,aim,fire)

@rpc("any_peer","reliable")
func interact(action:String):
	if mode == "host": sim.act(multiplayer.get_remote_sender_id(),action)

@rpc("authority","call_remote","unreliable_ordered",2)
func receive(payload:PackedByteArray):
	if mode == "join":
		state = bytes_to_var(payload.decompress_dynamic(262144,FileAccess.COMPRESSION_DEFLATE))
		apply_state(state)

func _unhandled_key_input(ev:InputEvent):
	if mode == "" or not (ev is InputEventKey and ev.pressed and not ev.echo): return
	if ev.keycode == KEY_F1: ui.help = not ui.help
	var mapping := {KEY_E:"use",KEY_C:"claim",KEY_R:"upgrade",KEY_B:"wall",KEY_T:"coil",KEY_1:"0",KEY_2:"1",KEY_3:"2"}
	if mapping.has(ev.keycode) and not state.is_empty():
		if mode == "join": interact.rpc_id(1,mapping[ev.keycode])
		else: sim.act(1,mapping[ev.keycode])

func _physics_process(dt):
	if mode == "" or state.is_empty(): return
	var id := multiplayer.get_unique_id()
	if not state.players.has(id): return
	var p = state.players[id]
	var cursor := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP,0.8).intersects_ray(camera.project_ray_origin(cursor),camera.project_ray_normal(cursor))
	var aim:Vector2 = p.aim if hit == null else Vector2(hit.x,hit.z)-p.p
	var move := Vector2(int(Input.is_physical_key_pressed(KEY_D))-int(Input.is_physical_key_pressed(KEY_A)),int(Input.is_physical_key_pressed(KEY_S))-int(Input.is_physical_key_pressed(KEY_W)))
	var shoot := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not ui.quit.get_global_rect().has_point(cursor)
	net_clock -= dt
	if mode != "join":
		sim.drive(1,move,aim,shoot)
		sim.tick(dt)
		if net_clock <= 0:
			state = sim.snapshot()
			if mode == "host" and multiplayer.get_peers().size(): receive.rpc(var_to_bytes(state).compress(FileAccess.COMPRESSION_DEFLATE))
			apply_state(state)
			sim.shots.clear()
	elif net_clock <= 0:
		controls.rpc_id(1,move,aim,shoot)
	if net_clock <= 0: net_clock = 1.0/20

func reconcile(models:Dictionary,entities:Dictionary,zombie:bool):
	for key in models.keys():
		if not entities.has(key):
			models[key].queue_free()
			models.erase(key)
	for key in entities:
		if not models.has(key):
			var e = entities[key]
			var n := art.actor(e.kind if zombie else e.role,zombie)
			models[key] = n
			n.position = Vector3(e.p.x,0,e.p.y)
			if not zombie:
				var l = art.label3(n,Match.ROLES[e.role],Vector3(0,2.22,0),0.0045)
				l.billboard = BaseMaterial3D.BILLBOARD_ENABLED

func apply_state(s:Dictionary):
	reconcile(heroes,s.players,false)
	reconcile(horde,s.enemies,true)
	for i in 4:
		for j in 2: pads[i][j].visible = s.gates[i].hp > 0 and s.gates[i].kind == j+1
		loot[i].visible = s.caches[i]
		signs[i].text = Match.SITES[i]+(" ✓" if s.claimed[i] else "")
	for shot in s.shots:
		var a := Vector3(shot[0].x,0.88,shot[0].y)
		var b := Vector3(shot[1].x,0.88,shot[1].y)
		if a.distance_to(b) < 0.02: continue
		var fx = art.part(art,(a+b)/2,Vector3(0.075,0.075,a.distance_to(b)),"89e9da" if shot[2]==3 else "ffdc79")
		fx.look_at(b)
		effects.append([fx,0.10])
	if not s.shots.is_empty():
		sound.pitch_scale = [1.1,0.75,1.35,1.6][s.shots[0][2]]
		sound.play()
	ui.render(s,multiplayer.get_unique_id())

func _process(dt):
	age += dt
	lights_out = move_toward(lights_out,1.0 if state.get("phase","") == "Noche" else 0.0,dt*0.4)
	art.lighting(lights_out,age)
	for i in range(effects.size()-1,-1,-1):
		effects[i][1] -= dt
		if effects[i][1] <= 0:
			effects[i][0].queue_free()
			effects.remove_at(i)
	var focus := Vector3.ZERO
	if not state.is_empty():
		var id := multiplayer.get_unique_id()
		if state.players.has(id):
			var p = state.players[id].p
			focus = Vector3(p.x,0,p.y)
		for set_index in 2:
			var models := heroes if set_index == 0 else horde
			var entities:Dictionary = state.players if set_index == 0 else state.enemies
			for key in models:
				if not entities.has(key): continue
				var e = entities[key]
				var n:Node3D = models[key]
				var to := Vector3(e.p.x,0,e.p.y)
				var delta_pos := to-n.position
				n.position = n.position.lerp(to,1-exp(-18*dt))
				var face := Vector2(delta_pos.x,delta_pos.z) if set_index else Vector2(e.aim)
				var body:Node3D = n.get_node("Body")
				if face.length() > 0.015: body.rotation.y = lerp_angle(body.rotation.y,atan2(face.x,face.y),1-exp(-15*dt))
				var step := sin(age*(10 if set_index==0 else 7)+int(key))*minf(1,delta_pos.length()*5)
				body.position.y = absf(step)*0.11
				body.get_node("Left").rotation.x = step*0.53
				body.get_node("Right").rotation.x = -step*0.53
				if set_index == 0: body.rotation.z = 1.4 if e.hp <= 0 else 0.0
	camera.position = camera.position.lerp(focus+Vector3(0,19,22),1-exp(-5*dt))
