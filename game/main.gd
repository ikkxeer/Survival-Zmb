extends Node3D
## Orchestrates a session: menus, ENet networking, local input with movement
## prediction, the host simulation, camera, and routing of events to effects/audio/UI.

const Match = preload("res://game/match.gd")
const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
const World = preload("res://game/view/world.gd")
const Actors = preload("res://game/view/actors.gd")
const Fx = preload("res://game/view/fx.gd")
const Audio = preload("res://game/audio.gd")
const UI = preload("res://game/interface.gd")
const CameraRig = preload("res://game/view/camera_rig.gd")
const Settings = preload("res://game/settings.gd")
const P := Data.Phase
const PORT := 24680
const SEND_RATE := 1.0 / 20.0

var world := World.new()
var actors := Actors.new()
var fx := Fx.new()
var audio := Audio.new()
var ui := UI.new()
var camera := CameraRig.new()
var prefs := Settings.new()
var listener := AudioListener3D.new()
var screen := ColorRect.new()
var screen_mat := ShaderMaterial.new()

var sim := Match.new()
var state := {}
var mode := ""
var chosen_role := 0
var chosen_name := ""
var net_clock := 0.0
var age := 0.0
var last_ev := 0
var paused := false
var local_pos := Vector2.INF
var local_aim := Vector2(0, 1)
var cursor := Vector2.ZERO
var roll_t := 0.0
var roll_cd := 0.0
var roll_dir := Vector2.ZERO
var stamina := 1.0
var last_fix := 0
var build_kind := -1
var shop_open := false
var map_open := false
var pred_cool := 0.0
var pred_mag := 0
var groan_t := 2.0
var hit_sound_t := 0.0
var zap_sound_t := 0.0
var heal_sound_t := 0.0
var cam_focus := Vector3.ZERO
var menu_t := 0.0
var rmb_down := false
var rmb_t := 0
var rmb_travel := 0.0
var orbiting := false
var saved_cursor := Vector2.ZERO
var map_click := false
var autopilot := {}        # tests and benchmarks: {"move":Vector2, "cursor":Vector2, "buttons":int}
var latency := 0.0          # simulated one-way delay for clients (--latencia=ms)
var lag_in := []
var lag_out := []
var last_phase := -1
var crosshair:ImageTexture

func _ready():
	add_child(world)
	world.build()
	add_child(actors)
	actors.build_static()
	add_child(fx)
	add_child(audio)
	add_child(camera)
	camera.current = true
	prefs.load_file()
	add_child(listener)
	listener.make_current()
	var post := CanvasLayer.new()
	post.layer = 1
	add_child(post)
	screen_mat.shader = load("res://game/shaders/screen.gdshader")
	screen.material = screen_mat
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post.add_child(screen)
	add_child(ui)
	ui.launch.connect(start)
	ui.leave.connect(stop.bind(""))
	ui.resume.connect(func(): set_paused(false))
	ui.prefs = prefs
	ui.settings_changed.connect(func(v):
		apply_settings(v)
		prefs.save_file())
	ui.action.connect(on_ui_action)
	ui.build_pick.connect(func(k): set_build(k))
	multiplayer.peer_disconnected.connect(func(id):
		if mode == "host": sim.leave(id))
	multiplayer.connected_to_server.connect(func(): register.rpc_id(1, chosen_role, chosen_name))
	multiplayer.connection_failed.connect(stop.bind("No se pudo conectar con esa dirección."))
	multiplayer.server_disconnected.connect(stop.bind("El anfitrión ha cerrado la partida."))
	crosshair = make_crosshair()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--latencia="): latency = float(a.substr(11)) / 1000.0
	ui.sync_settings()
	apply_settings(prefs.values)
	ui.show_menu(true)
	audio.set_music(2, 0.0)

func make_crosshair() -> ImageTexture:
	var img := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for a in 64:
		var ang := TAU * a / 64.0
		for r in [10.0, 11.0, 12.0]:
			var p:Vector2 = Vector2(20, 20) + Vector2(cos(ang), sin(ang)) * r
			img.set_pixel(int(p.x), int(p.y), Color(1, 1, 1, 0.95) if r < 12 else Color(0.1, 0.05, 0.15, 0.8))
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for i in range(4, 9):
			img.set_pixel(20 + d.x * i, 20 + d.y * i, Color(1, 0.85, 0.4))
	img.set_pixel(20, 20, Color(1, 1, 1))
	return ImageTexture.create_from_image(img)

# ================================================================== session
func start(which:String, role:int, address:String, player_name:String):
	if mode != "": return
	chosen_role = role
	chosen_name = player_name
	if which != "solo":
		var peer := ENetMultiplayerPeer.new()
		var err:Error
		if which == "host":
			err = peer.create_server(PORT, 3)
		else:
			if address.is_empty():
				ui.status.text = "Introduce la IP del anfitrión."
				return
			err = peer.create_client(address, PORT)
		if err != OK:
			ui.status.text = "No se pudo abrir la conexión: " + error_string(err)
			return
		multiplayer.multiplayer_peer = peer
	mode = which
	last_ev = 0
	local_pos = Vector2.INF
	last_fix = 0
	build_kind = -1
	paused = false
	ui.show_menu(false)
	get_viewport().gui_release_focus()
	Input.set_custom_mouse_cursor(crosshair, Input.CURSOR_ARROW, Vector2(20, 20))
	sim = Match.new()
	if mode == "join":
		ui.big("Conectando…", "Buscando al anfitrión en " + address, Color.WHITE, 30.0)
		return
	sim.join(1, chosen_role, chosen_name)
	state = sim.snapshot()
	if mode == "host":
		var ips := []
		for ip in IP.get_local_addresses():
			if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254"): ips.append(ip)
		ui.say("Partida abierta en el puerto %d. Tus compañeros pueden unirse a: %s" % [PORT, ", ".join(ips) if ips.size() else "tu IP local"], Color("ffd166"))
	ui.big("La última verbena", "Prepara la casa antes del anochecer. Rebusca, construye (B) y conquista (C).", Color("ffd166"), 5.0)

func stop(reason:String):
	if mode == "": return
	mode = ""
	end_orbit()
	camera.reset()
	map_click = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	state = {}
	lag_in.clear()
	lag_out.clear()
	actors.clear_all()
	set_build(-1)
	shop_open = false
	map_open = false
	ui.toggle_shop(false)
	ui.map_panel.visible = false
	set_paused(false)
	ui.status.text = reason
	ui.show_menu(true)
	Input.set_custom_mouse_cursor(null)
	audio.set_music(2, 0.0)

func set_paused(v:bool):
	paused = v
	ui.pause.visible = v
	if not v:
		ui.settings_panel.visible = false
		ui.help_panel.visible = false

@rpc("any_peer", "reliable")
func register(role:int, player_name:String = ""):
	if mode != "host": return
	var id := multiplayer.get_remote_sender_id()
	if not sim.join(id, role, player_name): multiplayer.multiplayer_peer.disconnect_peer(id)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func controls(pos:Vector2, aim:Vector2, buttons:int):
	if mode == "host": sim.drive(multiplayer.get_remote_sender_id(), pos, aim, buttons)

@rpc("any_peer", "call_remote", "reliable")
func interact(what:String, args:Array = []):
	if mode == "host": sim.act(multiplayer.get_remote_sender_id(), what, args)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func receive(payload:PackedByteArray):
	if mode != "join": return
	if latency > 0:
		lag_in.append([Time.get_ticks_msec() + latency * 1000.0, payload])
		return
	unpack(payload)

func unpack(payload:PackedByteArray):
	var data = bytes_to_var(payload.decompress_dynamic(1 << 21, FileAccess.COMPRESSION_DEFLATE))
	if data is Dictionary: on_state(data)

func flush_lag():
	var now := Time.get_ticks_msec()
	while lag_in.size() > 0 and lag_in[0][0] <= now: unpack(lag_in.pop_front()[1])
	while lag_out.size() > 0 and lag_out[0][0] <= now:
		var c:Array = lag_out.pop_front()
		if c[1] == "controls": controls.rpc_id(1, c[2], c[3], c[4])
		else: interact.rpc_id(1, c[2], c[3])

func send_action(what:String, args:Array = []):
	if state.is_empty(): return
	if mode == "join":
		if latency > 0: lag_out.append([Time.get_ticks_msec() + latency * 1000.0, "interact", what, args])
		else: interact.rpc_id(1, what, args)
	else: sim.act(1, what, args)

func my_id() -> int:
	return multiplayer.get_unique_id() if mode != "solo" else 1

# ================================================================== settings
func apply_settings(s:Dictionary):
	world.set_quality(s.quality)
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_4X][s.quality]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if s.quality == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_scale = 0.75 if s.quality == 0 else 1.0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if s.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	audio.master = s.volume
	audio.music_volume = s.music
	audio.sfx = s.sfx
	fx.show_numbers = s.numbers
	fx.bright = s.flashes
	camera.sensitivity = s.sensitivity
	get_tree().root.content_scale_factor = s.ui_scale

func on_ui_action(name:String, args:Array):
	if name == "ui_click":
		audio.play("click", null, -6)
		return
	send_action(name, args)

# ================================================================== input
func set_build(k:int):
	build_kind = k
	if k < 0: actors.show_ghost(-1, Vector3.ZERO, false)

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: end_orbit()

func begin_orbit():
	orbiting = true
	ui.orbit_reticle.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func end_orbit():
	if not orbiting: return
	orbiting = false
	ui.orbit_reticle.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_viewport().warp_mouse(saved_cursor)

func _input(ev:InputEvent):
	## Runs before the interface: map clicks and right-button orbit must win over shooting.
	if mode == "" or state.is_empty() or paused: return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		map_click = false
	if map_open and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var w = ui.bigmap_world(ev.position)
		if w != null:
			send_action("ping", [w])
			map_click = true
			get_viewport().set_input_as_handled()
		return
	if ev is InputEventMouseMotion and rmb_down:
		rmb_travel += ev.relative.length()
		if not orbiting and rmb_travel > 8.0: begin_orbit()
		if orbiting:
			camera.orbit(ev.screen_relative)
			get_viewport().set_input_as_handled()
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT:
		if ev.pressed:
			rmb_down = true
			rmb_travel = 0.0
			rmb_t = Time.get_ticks_msec()
			saved_cursor = ev.position
		elif rmb_down:
			rmb_down = false
			if orbiting: end_orbit()
			elif Time.get_ticks_msec() - rmb_t < 400: right_click()
		get_viewport().set_input_as_handled()

func right_click():
	if build_kind >= 0: set_build(-1)
	else: melee()

func _unhandled_input(ev:InputEvent):
	if mode == "" or state.is_empty(): return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		key(ev.physical_keycode)
	if ev is InputEventMouseButton and ev.pressed:
		if paused: return
		match ev.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if build_kind >= 0: cycle_gun(-1)
				else: camera.zoom(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if build_kind >= 0: cycle_gun(1)
				else: camera.zoom(1)
			MOUSE_BUTTON_MIDDLE: send_action("ping", [cursor])
			MOUSE_BUTTON_LEFT:
				if build_kind >= 0: place()

func key(code:int):
	if ui.capture_key(code): return
	if code == KEY_ESCAPE:
		if shop_open: return toggle_shop()
		if map_open: return toggle_map()
		if build_kind >= 0: return set_build(-1)
		if ui.settings_panel.visible or ui.help_panel.visible:
			ui.settings_panel.visible = false
			ui.help_panel.visible = false
			return
		if state.get("ph", 0) == P.OVER: return
		set_paused(not paused)
		return
	if paused: return
	if code == KEY_F1:
		ui.toggle_panel(ui.help_panel)
		return
	var act := prefs.action_for(code)
	if code == KEY_TAB or act == "map": return toggle_map()
	if act == "shop": return toggle_shop()
	if shop_open: return
	var me := my_state()
	if me.is_empty(): return
	if act == "ping":
		send_action("ping", [me.p])
		return
	if build_kind >= 0 and code >= KEY_1 and code <= KEY_8:
		set_build(code - KEY_1)
		return
	match act:
		"build": set_build(-1 if build_kind >= 0 else 0)
		"reload": send_action("reload")
		"ability": send_action("ability")
		"grenade":
			if build_kind >= 0: send_action("upgrade", [sim.nav.cell_of(cursor)])
			else: send_action("grenade", [cursor])
		"medkit": send_action("medkit")
		"claim": send_action("claim")
		"ready": send_action("ready")
		"melee": melee()
		"demolish":
			if build_kind >= 0: send_action("demolish", [sim.nav.cell_of(cursor)])
		"roll": start_roll()
	if build_kind < 0 and code >= KEY_1 and code <= KEY_7:
		var g := code - KEY_1
		if me.guns.has(g): send_action("switch", [g])

func toggle_shop():
	var me := my_state()
	if not shop_open and (me.is_empty() or me.p.distance_to(Map.BASE_CENTER) > Map.SHOP_RADIUS):
		ui.say("La tienda está junto a la casa de la verbena (T allí).", Color("ffd166"))
		return
	shop_open = not shop_open
	ui.toggle_shop(shop_open)
	if shop_open: set_build(-1)

func toggle_map():
	map_open = not map_open
	ui.map_panel.visible = map_open

func cycle_gun(d:int):
	if build_kind >= 0:
		set_build(posmod(build_kind + d, Data.STRUCTURES.size()))
		return
	var me := my_state()
	if me.is_empty(): return
	var owned:Array = me.guns.keys()
	owned.sort()
	var i := owned.find(me.gun)
	send_action("switch", [owned[posmod(i + d, owned.size())]])

func melee():
	send_action("melee")
	var r = actors.heroes.get(my_id())
	if r: r.swing = 1.0
	audio.play("swing", Vector3(local_pos.x, 1, local_pos.y), -4)

func start_roll():
	if roll_cd > 0 or stamina < 0.25: return
	var me := my_state()
	if me.is_empty() or me.st != 0: return
	var dir := move_input()
	roll_dir = dir if dir != Vector2.ZERO else local_aim
	roll_t = 0.34
	roll_cd = 0.75
	stamina -= 0.25
	audio.play("swing", Vector3(local_pos.x, 1, local_pos.y), -8, 0.7)

func place():
	var me := my_state()
	if me.is_empty(): return
	var cell := sim.nav.cell_of(cursor)
	if cell < 0: return
	if sim.structures.has(cell) or (mode == "join" and sim.nav.skind[cell] >= 0): return
	send_action("build", [build_kind, cell])

func move_input() -> Vector2:
	if autopilot.has("move"): return autopilot.move
	if paused or shop_open: return Vector2.ZERO
	var v := Vector2(int(prefs.pressed("right")) - int(prefs.pressed("left")), int(prefs.pressed("down")) - int(prefs.pressed("up")))
	return camera.movement(v.normalized())

func my_state() -> Dictionary:
	if state.is_empty() or not state.pl.has(my_id()): return {}
	return state.pl[my_id()]

# ================================================================== simulation & networking
func _physics_process(dt:float):
	if mode == "" or paused and mode == "solo": return
	var me := my_state()
	var buttons := 0
	if not me.is_empty():
		local_move(dt, me)
		var mouse := get_viewport().get_mouse_position()
		var over_ui := ui.shop.visible or ui.map_panel.visible or paused or ui.build_bar.get_global_rect().has_point(mouse) and build_kind >= 0
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and build_kind < 0 and not over_ui and not map_click: buttons |= 1
		if prefs.pressed("use") and not shop_open: buttons |= 2
		if roll_t > 0: buttons |= 4
		if autopilot.has("buttons"): buttons = autopilot.buttons
		predict_fire(dt, me, buttons & 1 != 0)
	net_clock -= dt
	if mode == "join":
		flush_lag()
		if not me.is_empty() and net_clock <= 0:
			if latency > 0: lag_out.append([Time.get_ticks_msec() + latency * 1000.0, "controls", local_pos, cursor - local_pos, buttons])
			else: controls.rpc_id(1, local_pos, cursor - local_pos, buttons)
			net_clock = 1.0 / 30.0
		return
	if not me.is_empty(): sim.drive(1, local_pos, cursor - local_pos, buttons)
	sim.tick(dt)
	var snap := sim.snapshot()
	if mode == "host" and net_clock <= 0:
		net_clock = SEND_RATE
		if multiplayer.get_peers().size() > 0:
			receive.rpc(var_to_bytes(snap).compress(FileAccess.COMPRESSION_DEFLATE))
	on_state(snap)

func local_move(dt:float, me:Dictionary):
	if local_pos == Vector2.INF or me.st == 2:
		local_pos = me.p
		last_fix = me.fix
		return
	if me.fix != last_fix:
		last_fix = me.fix
		local_pos = me.p
	if mode == "join" and local_pos.distance_to(me.p) > 4.0: local_pos = me.p
	roll_cd -= dt
	var dir := move_input()
	var speed := sim.player_speed(me)
	var sprint:bool = prefs.pressed("sprint") and dir != Vector2.ZERO and stamina > 0.05 and me.st == 0
	if sprint:
		speed *= 1.35
		stamina = maxf(0.0, stamina - dt * 0.32)
	else:
		stamina = minf(1.0, stamina + dt * 0.22)
	var vel := dir * speed
	if roll_t > 0:
		roll_t -= dt
		vel = roll_dir * 11.0
	var cell := sim.nav.cell_of(local_pos)
	if cell >= 0 and sim.nav.skind[cell] >= 0 and Data.STRUCTURES[sim.nav.skind[cell]].block: vel *= 0.5
	local_pos = sim.nav.move(local_pos, vel * dt, Match.PLAYER_R, 0).clamp(Map.BOUNDS.position, Map.BOUNDS.end)
	var mouse := get_viewport().get_visible_rect().size * 0.5 if orbiting else get_viewport().get_mouse_position()
	var hit = camera.aim_point(mouse, 1.0)
	if hit != null:
		cursor = Vector2(hit.x, hit.z)
	else:
		var ray := camera.project_ray_normal(mouse)
		cursor = local_pos + Vector2(ray.x, ray.z).normalized() * 12.0
	if autopilot.has("cursor"): cursor = autopilot.cursor
	if cursor.distance_to(local_pos) > 0.3: local_aim = (cursor - local_pos).normalized()

func predict_fire(dt:float, me:Dictionary, firing:bool):
	## Clients play their own muzzle flash and sound at once; the host decides the hits.
	pred_cool -= dt
	if mode != "join" or not firing or me.st != 0 or me.rl > 0: return
	if pred_cool > 0: return
	var g:int = me.gun
	var w:Dictionary = Data.WEAPONS[g]
	if me.mag.get(g, 0) <= 0 and not (me.role == 2 and me.buff > 0): return
	pred_cool = w.rate * (0.6 if me.role == 2 and me.buff > 0 else 1.0)
	var origin := Vector3(local_pos.x, 1.1, local_pos.y) + Vector3(local_aim.x, 0, local_aim.y) * 0.7
	fx.muzzle(origin, fx.gun_color(g), 1.0)
	play_gun(g, origin)
	var r = actors.heroes.get(my_id())
	if r: r.recoil = 1.0

func play_gun(g:int, at:Vector3):
	var names := ["cork", "shotgun", "smg", "rifle", "sniper", "launch", "flame", "turret"]
	audio.play(names[clampi(g, 0, 7)], at, [-3.0, 0.0, -6.0, -3.0, 0.0, -2.0, -8.0, -9.0][clampi(g, 0, 7)])

func on_state(s:Dictionary):
	var first := state.is_empty()
	state = s
	var me := my_id()
	if not s.pl.has(me):
		if mode == "join" and not first: ui.big("Partida llena", "", Color.WHITE, 2.0)
		return
	if mode == "join":
		sim.load_structures(s.st)
		for i in s.si.size(): sim.sites[i].claimed = s.si[i][0]
		sim.materials = s.mat
		if first: ui.big("¡Dentro!", "Te has unido a la verbena", Color("ffd166"), 3.0)
	actors.apply(s, me)
	for e in s.fx:
		if e[0] <= last_ev: continue
		last_ev = e[0]
		handle_event(e[2], e.slice(3), me)
	if s.ph != last_phase:
		if last_phase == P.OVER and s.ph != P.OVER: pass
		last_phase = s.ph

# ================================================================== events
func v3(x:float, z:float, y:float = 0.0) -> Vector3:
	return Vector3(x, y, z)

func handle_event(type:String, d:Array, me:int):
	match type:
		"say": ui.say(d[0])
		"shot":
			var owner:int = d[0]
			var g:int = d[1]
			var h := 1.1
			if owner <= -100: h = 1.0
			if owner == -2: h = 6.4
			var a := v3(d[2], d[3], h)
			var b := v3(d[4], d[5], 1.0)
			var mine := owner == me and mode == "join"
			if g != 5: fx.shot(owner, g, a, b, owner == me)
			if not mine: play_gun(7 if owner <= -100 else (0 if owner == -2 else g), a)
			if actors.heroes.has(owner): actors.heroes[owner].recoil = 1.0
		"flame":
			var at := v3(d[1], d[2], 1.1)
			fx.burst("flame", at, Vector3(d[3], 0, d[4]))
			audio.play("flame", at, -10)
		"hit":
			var at := v3(d[0], d[1])
			var crit:bool = d[3] == 1
			fx.number(at, str(d[2]) + ("!" if crit else ""), Color("ffd166") if crit else Color("fff4dc"), crit)
			actors.flash_zombie(d[4])
			hit_sound_t -= 1
			if hit_sound_t <= 0:
				hit_sound_t = 2
				audio.play("hit", at + Vector3(0, 1, 0), -6, randf_range(0.8, 1.2))
		"kill":
			var at := v3(d[0], d[1])
			fx.death(at, d[2])
			audio.play("pop", at + Vector3(0, 1, 0), -2, randf_range(0.9, 1.15))
			if d[3] == me: fx.number(at + Vector3(0, 0.6, 0), "+%d 🪙" % Data.ENEMIES[clampi(d[2], 0, 7)].coins, Color("ffe680"), false)
		"boom":
			fx.explosion(v3(d[0], d[1]), d[2])
			audio.play("explosion", v3(d[0], d[1], 1), 2)
		"zap":
			fx.zap(v3(d[0], d[1], 1.45), v3(d[2], d[3], 1.0))
			zap_sound_t -= 1
			if zap_sound_t <= 0:
				zap_sound_t = 2
				audio.play("zap", v3(d[0], d[1], 1), -6)
		"spit": audio.play("spit", v3(d[0], d[1], 1), -4)
		"splat":
			fx.burst("goo", v3(d[0], d[1], 0.3))
			fx.ring(v3(d[0], d[1]), Color("b86ae8"), 0.4, 2.2, 0.5)
			audio.play("splat", v3(d[0], d[1], 1), -4)
		"fuse":
			if actors.horde.has(d[0]):
				var z:Node3D = actors.horde[d[0]]
				fx.ring(z.position, Color("ff5a5a"), 2.6 * 2.0, 2.6 * 2.0, 0.7, true)
				audio.play("fuse", z.position + Vector3(0, 1, 0), -2)
		"swing":
			if randf() < 0.25 and actors.horde.has(d[0]):
				audio.play("groan%d" % randi_range(0, 2), actors.horde[d[0]].position + Vector3(0, 1.5, 0), -8, randf_range(0.9, 1.2))
		"slam_warn":
			fx.ring(v3(d[0], d[1]), Color("ff5a5a"), 7.2, 7.2, 0.95, true)
			audio.play("groan2", v3(d[0], d[1], 2), 2, 0.6)
		"slam":
			fx.explosion(v3(d[0], d[1]), 3.6)
			audio.play("explosion", v3(d[0], d[1], 1), 0, 0.7)
		"summon":
			fx.burst("puff", v3(d[0], d[1], 0.5))
			fx.burst("leaves", v3(d[0], d[1], 1.0))
		"build", "upgrade":
			var c := sim.nav.center(d[0])
			fx.burst("puff", v3(c.x, c.y, 0.3))
			audio.play("build", v3(c.x, c.y, 0.5), -3)
		"break":
			var c := sim.nav.center(d[0])
			fx.burst("debris", v3(c.x, c.y, 0.6))
			fx.burst("puff", v3(c.x, c.y, 0.4))
			audio.play("crash", v3(c.x, c.y, 0.5), 0)
		"remove":
			var c := sim.nav.center(d[0])
			fx.burst("puff", v3(c.x, c.y, 0.3))
		"sdmg":
			if randf() < 0.3:
				var c := sim.nav.center(d[0])
				fx.burst("debris", v3(c.x, c.y, 0.8))
		"claim":
			var b:Vector2 = Map.SITES[d[0]].beacon
			fx.burst("stars", v3(b.x, b.y, 0.2))
			fx.burst("confetti", v3(b.x, b.y, 3.5))
			fx.ring(v3(b.x, b.y), Color(Data.SITES[d[0]].color), 0.5, Map.SITE_BUILD_RADIUS * 2.0, 1.2)
			audio.play("claim", null, -2)
			ui.big(Data.SITES[d[0]].name.to_upper() + " ES DEL BARRIO", Data.SITES[d[0]].bonus, Color(Data.SITES[d[0]].color).lightened(0.3), 4.0)
		"lost":
			audio.play("alarm", null, -2)
			ui.big("¡%s PERDIDO!" % Data.SITES[d[0]].name.to_upper(), "Reconquistadlo de día", Color("ff6b6b"), 3.5)
		"night":
			audio.play("horn", null, 0)
			var ev:Dictionary = Data.NIGHT_EVENTS[d[1]]
			ui.big("NOCHE %d" % d[0], ev.name + " · " + ev.desc, Color("c9b6ff"), 4.5)
		"dawn":
			audio.play("dawn", null, -2)
			ui.big("¡AMANECE!", "Habéis sobrevivido a la noche %d" % (d[0] - 1), Color("ffd166"), 3.5)
			ui.show_report(state.get("rep", []))
		"over":
			audio.play("down", null, 0, 0.7)
		"down":
			audio.play("down", v3(d[0], d[1], 1), 0)
		"revive":
			fx.burst("heal", v3(d[0], d[1], 1.0))
			fx.burst("stars", v3(d[0], d[1], 0.1))
			audio.play("heal", v3(d[0], d[1], 1), 0)
		"level":
			fx.burst("stars", v3(d[0], d[1], 0.1))
			fx.ring(v3(d[0], d[1]), Color("ffe680"), 0.5, 4.0, 0.8)
			fx.number(v3(d[0], d[1], 0.8), "¡NIVEL %d!" % d[2], Color("ffe680"), true)
			audio.play("levelup", v3(d[0], d[1], 1), 0)
		"ability":
			var col := Color(Data.ROLES[d[2]].color)
			fx.ring(v3(d[0], d[1]), col, 0.5, 14.0 if d[2] < 2 else 3.0, 0.7)
			fx.burst("stars", v3(d[0], d[1], 0.1))
			if d[2] == 1: fx.burst("heal", v3(d[0], d[1], 1.0))
			audio.play("levelup", v3(d[0], d[1], 1), -4, 1.3)
		"heal":
			fx.burst("heal", v3(d[0], d[1], 1.0))
			heal_sound_t -= 1
			if heal_sound_t <= 0:
				heal_sound_t = 3
				audio.play("heal", v3(d[0], d[1], 1), -8)
		"repair":
			fx.burst("puff", v3(d[0], d[1], 0.5))
			audio.play("build", v3(d[0], d[1], 0.5), -12, 1.3)
		"loot":
			fx.burst("confetti", v3(d[0], d[1], 1.0))
			audio.play("coin", v3(d[0], d[1], 1), -2)
		"buy": audio.play("coin", null, -4)
		"melee":
			if d[4] != me: audio.play("swing", v3(d[0], d[1], 1), -6)
			if actors.heroes.has(d[4]) and d[4] != me: actors.heroes[d[4]].swing = 1.0
		"throw": audio.play("swing", v3(d[0], d[1], 1), -4, 0.8)
		"reload": if v3(d[0], d[1]).distance_to(v3(local_pos.x, local_pos.y)) < 3.0: audio.play("reload", v3(d[0], d[1], 1), -4)
		"ping":
			var col := Color(actors.SLOT_COLORS[state.pl[d[2]].slot % 4]) if state.pl.has(d[2]) else Color.WHITE
			fx.ring(v3(d[0], d[1]), col, 0.3, 2.5, 1.2)
			fx.ring(v3(d[0], d[1]), col, 2.0, 2.0, 5.0, true)
			audio.play("click", null, 0, 0.6)
		"warn":
			fx.ring(v3(d[0], d[1]), Color("cfe4ff"), 4.0, 4.0, 1.0, true)
		"bolt":
			fx.bolt(v3(d[0], d[1]))
			if prefs.values.flashes: world.lightning()
			audio.play("thunder", null, 0)
		"survivor": audio.play("alarm", v3(d[0], d[1], 1), -6, 1.3)
		"drop": audio.play("coin", null, -2, 0.7)
		"land":
			fx.burst("puff", v3(d[0], d[1], 0.3))
		"rescue":
			fx.burst("stars", v3(d[0], d[1], 0.1))
		"joined":
			audio.play("claim", null, -4)
			fx.burst("confetti", v3(0, -0.5, 4.0))
		"core_hit":
			if randf() < 0.15: fx.burst("debris", v3(randf_range(-3, 3), randf_range(-3, 2), 1.5))
		"core_up":
			fx.burst("stars", v3(0, -0.5, 0.2))
			audio.play("build", v3(0, -0.5, 1), 0)

# ================================================================== frame
func _process(dt:float):
	age += dt
	if mode == "" or state.is_empty():
		menu_camera(dt)
		return
	var s := state
	var me := my_id()
	var p := my_state()
	var night := clampf(1.0 - smoothstep(0.22, 0.3, world.tod_now) + smoothstep(0.74, 0.82, world.tod_now), 0.0, 1.0)
	world.update_time(s.tod, s.ev if s.ph == P.NIGHT else -1, s.wx, cam_focus, dt, age)
	var lp := Vector3(local_pos.x, 0, local_pos.y) if local_pos != Vector2.INF else Vector3.INF
	actors.update(dt, age, s, lp, local_aim, night, s.ph == P.NIGHT and s.ev == 1)
	# camera
	if not p.is_empty() and local_pos != Vector2.INF:
		var lead := (cursor - local_pos).limit_length(7.0) * 0.28 * camera.zoom_t
		var target := Vector3(local_pos.x + lead.x, 0, local_pos.y + lead.y)
		cam_focus = cam_focus.lerp(target, 1.0 - exp(-6.0 * dt))
	var shake := Vector3.ZERO
	if ui.settings.shake and fx.trauma > 0:
		var tr := fx.trauma * fx.trauma
		shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * tr * 0.7
	camera.follow(cam_focus, dt, shake)
	if actors.heroes.has(me): actors.heroes[me].visible = camera.boom > 1.2
	listener.global_position = cam_focus + Vector3(0, 8, 4)
	listener.global_basis = camera.global_basis
	# audio
	var combat := 0.0
	if s.ph == P.NIGHT: combat = clampf(float(s.en.size() / 8) / 25.0, 0.0, 1.0)
	audio.set_music(1 if s.ph == P.NIGHT else 0, combat)
	audio.set_ambience(1.0 - night, world.cur_wet, true)
	groan_t -= dt
	if groan_t <= 0 and actors.horde.size() > 0:
		groan_t = randf_range(1.2, 3.5)
		var keys := actors.horde.keys()
		var z:Node3D = actors.horde[keys[randi() % keys.size()]]
		if z.position.distance_to(cam_focus) < 18: audio.play("groan%d" % randi_range(0, 2), z.position + Vector3(0, 1.5, 0), -10, randf_range(0.85, 1.2))
	# post
	if not p.is_empty():
		screen_mat.set_shader_parameter("hurt", (1.0 if prefs.values.flashes else 0.4) * clampf(p.dmg * 2.0, 0.0, 0.6) + (0.25 if p.hp < p.hpmax * 0.3 and p.st == 0 else 0.0) * (0.5 + 0.5 * sin(age * 6.0)))
		screen_mat.set_shader_parameter("down", 1.0 if p.st != 0 else 0.0)
	screen_mat.set_shader_parameter("vignette", 0.3 + 0.25 * night)
	# build preview
	var local := {"build": build_kind}
	if build_kind >= 0 and not p.is_empty():
		var cell := sim.nav.cell_of(cursor)
		var c := sim.nav.center(cell) if cell >= 0 else cursor
		var cost := client_cost(p, build_kind)
		var valid:bool = cell >= 0 and sim.nav.is_free_for_build(cell) and sim.in_territory(c) and c.distance_to(local_pos) <= 9.5 and s.mat >= cost and not Map.BASE.grow(0.01).has_point(c)
		actors.show_ghost(build_kind, Vector3(c.x, 0, c.y), valid)
		var costs := []
		for k in Data.STRUCTURES.size(): costs.append(client_cost(p, k))
		local.costs = costs
		var hint := "%s: %s" % [Data.STRUCTURES[build_kind].name, Data.STRUCTURES[build_kind].desc]
		if cell >= 0 and sim.nav.skind[cell] >= 0:
			var info = actors.struct_info.get(cell)
			if info != null:
				var def:Dictionary = Data.STRUCTURES[info[0]]
				var up := "al máximo" if info[1] >= def.hp.size() - 1 else "F mejorar (%d mat.)" % def.up[info[1]]
				hint = "%s nivel %d · %s · X desmontar" % [def.name, info[1] + 1, up]
				actors.show_ghost(-1, Vector3.ZERO, false)
		elif not sim.in_territory(c):
			hint = "Fuera de tu territorio: construye cerca de la casa o de una propiedad conquistada"
		local.build_hint = hint + "\nClic: colocar · 1–8 o rueda: elegir · Clic derecho / B: salir"
	ui.mm_data = {"yaw": camera.yaw, "me": local_pos if local_pos != Vector2.INF else Vector2.ZERO, "indicators": indicators(s, me)}
	ui.render(s, me, local, dt)

func client_cost(p:Dictionary, kind:int) -> int:
	var cost:int = Data.STRUCTURES[kind].cost
	if p.role == 0: cost = maxi(1, roundi(cost * 0.75))
	if state.si[0][0]: cost = maxi(1, cost - 1)
	return cost

func indicators(s:Dictionary, me:int) -> Array:
	var out := []
	var vp := get_viewport().get_visible_rect().size
	var add := func(world_pos:Vector3, col:Color, text:String):
		if camera.is_position_behind(world_pos): return
		var sp := camera.unproject_position(world_pos)
		var on := Rect2(Vector2(30, 30), vp - Vector2(60, 60)).has_point(sp)
		out.append([sp, col, text, on])
	for id in s.pl:
		var q:Dictionary = s.pl[id]
		if id != me and q.st == 1: add.call(v3(q.p.x, q.p.y, 1.0), Color("ff6b6b"), "¡%s!" % q.name)
	for sv in s.sv:
		if sv[4] == 0: add.call(v3(sv[1], sv[2], 2.0), Color("ffd166"), "Vecino")
	for d in s.dr: add.call(v3(d[1], d[2], 1.0), Color("4cc9f0"), "Suministros")
	for id in s.pl:
		var q:Dictionary = s.pl[id]
		if q.ping == null: continue
		var dist := roundi(Vector2(local_pos.x, local_pos.y).distance_to(q.ping)) if local_pos != Vector2.INF else 0
		var col := Color("ff6b6b") if q.st != 0 else Color(actors.SLOT_COLORS[q.slot % 4])
		add.call(v3(q.ping.x, q.ping.y, 1.7), col, "%s · %d m" % [Data.ROLES[q.role].name if id != me else "Tú", dist])
	if s.boss.size() > 0 and actors.horde.has(s.boss[0]): add.call(actors.horde[s.boss[0]].position + Vector3(0, 3, 0), Color("c45ad8"), "Gigantón")
	return out

func menu_camera(dt:float):
	menu_t += dt
	world.update_time(0.735 + 0.03 * sin(menu_t * 0.05), -1, 0, Vector3.ZERO, dt, age)
	var a := menu_t * 0.05
	camera.position = Vector3(sin(a) * 24.0, 12.0, cos(a) * 24.0)
	camera.look_at(Vector3(0, 1.5, 0))
	cam_focus = Vector3.ZERO
	audio.set_ambience(1.0, 0.0, false)
	screen_mat.set_shader_parameter("hurt", 0.0)
	screen_mat.set_shader_parameter("down", 0.0)
	screen_mat.set_shader_parameter("vignette", 0.45)
