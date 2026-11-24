extends Control
## North is -Z, independent of each player's orbit camera.
const Rules = preload("res://game/match.gd")
const ACCESS = ["sur","este","norte","oeste"]
const HALF_EXTENT := 17.0
const INK := Color("#172f38")
const PAPER := Color("#fff0cd")
const MINT := Color("#92ddba")
const AMBER := Color("#ffd17c")
const DANGER := Color("#fa9180")
var state:Dictionary = {}
var local_id := 0
var camera:Camera3D
var expanded := false
var previous_hp:Array[float] = []
var access_alerts := {}

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func update_state(snapshot:Dictionary,peer_id:int):
	var now := Time.get_ticks_msec()
	for i in snapshot.gates.size():
		var hp:float = snapshot.gates[i].hp
		if previous_hp.size() <= i:
			previous_hp.append(hp)
		else:
			if hp < previous_hp[i]: access_alerts[i] = now+3200
			elif hp > previous_hp[i]: access_alerts.erase(i)
			previous_hp[i] = hp
		if access_alerts.get(i,0) <= now: access_alerts.erase(i)
	state = snapshot
	local_id = peer_id
	queue_redraw()

func reset():
	state = {}
	previous_hp.clear()
	access_alerts.clear()
	expanded = false
	queue_redraw()

func card() -> Rect2:
	var side := minf(348,minf(size.x*0.46,size.y-236))
	side = maxf(80,side)
	return Rect2(size.x-side-44,90,side+28,side+106)

func plot() -> Rect2:
	var bounds := card()
	return Rect2(bounds.position+Vector2(14,36),Vector2.ONE*(bounds.size.x-28))

func map_point(world:Vector2) -> Vector2:
	var r := plot()
	return r.get_center()+world*r.size.x/(2*HALF_EXTENT)

func world_point(pixel:Vector2) -> Vector2:
	var r := plot()
	return (pixel-r.get_center())*(2*HALF_EXTENT)/r.size.x

func covers(pixel:Vector2) -> bool:
	return expanded and not state.is_empty() and card().has_point(pixel)

func caption(pos:Vector2,value:String,tint:Color,font_size:int):
	draw_string(ThemeDB.fallback_font,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,tint)

func diamond(p:Vector2,r:float,tint:Color):
	draw_colored_polygon(PackedVector2Array([p+Vector2.UP*r,p+Vector2.RIGHT*r,p+Vector2.DOWN*r,p+Vector2.LEFT*r]),tint)

func cross_at(p:Vector2,r:float,tint:Color):
	draw_line(p-Vector2.RIGHT*r,p+Vector2.RIGHT*r,tint,3,true)
	draw_line(p-Vector2.DOWN*r,p+Vector2.DOWN*r,tint,3,true)

func _draw():
	if state.is_empty() or not state.players.has(local_id): return
	if state.phase != "Fin" and not access_alerts.is_empty():
		var urgent:int = access_alerts.keys()[0]
		for i in access_alerts:
			if state.gates[i].hp < state.gates[urgent].hp: urgent = i
		var warning := "Brecha al %s" % ACCESS[urgent] if state.gates[urgent].hp<=0 else "Defensa %s bajo ataque" % ACCESS[urgent]
		var width := ThemeDB.fallback_font.get_string_size(warning,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x
		draw_rect(Rect2(Vector2(18,102),Vector2(width+22,31)),INK)
		caption(Vector2(29,124),warning,DANGER,17)
	if not expanded:
		draw_beacons()
		return
	var bounds := card()
	var r := plot()
	draw_rect(bounds,INK)
	draw_rect(bounds,Color("#70938c"),false,1)
	caption(bounds.position+Vector2(14,24),"Plano del barrio",PAPER,18)
	caption(Vector2(r.end.x-27,r.position.y-11),"N ↑",MINT,13)
	draw_rect(r,Color("#35594f"))
	for x in [-7,7]:
		draw_line(map_point(Vector2(x,-HALF_EXTENT)),map_point(Vector2(x,HALF_EXTENT)),Color("#637575"),r.size.x*0.068)
	for z in [-6,6]:
		draw_line(map_point(Vector2(-HALF_EXTENT,z)),map_point(Vector2(HALF_EXTENT,z)),Color("#637575"),r.size.x*0.058)
	var base := Rect2(map_point(Vector2(-2.35,-2.1)),Vector2(4.7,4.2)*r.size.x/(2*HALF_EXTENT))
	draw_rect(base,Color("#c8865e"))
	caption(base.get_center()+Vector2(-14,4),"Casa",PAPER,13)
	for i in Rules.GATES.size():
		var gate = state.gates[i]
		var at := map_point(Rules.GATES[i])
		var footprint := Rect2(at-Vector2(5,5),Vector2(10,10))
		if gate.hp>0: draw_rect(footprint,AMBER)
		else: draw_rect(footprint,PAPER,false,1.0)
		if access_alerts.has(i): draw_arc(at,10,0,TAU,24,DANGER,2,true)
	for i in Rules.CACHES.size():
		var pos := map_point(Rules.CACHES[i])
		diamond(pos,7,MINT if state.claimed[i] else PAPER)
		if state.caches[i]: draw_circle(pos,2.5,INK)
		var name_size:int = 13
		var label_width := ThemeDB.fallback_font.get_string_size(Rules.SITES[i],HORIZONTAL_ALIGNMENT_LEFT,-1,name_size).x
		caption(pos+Vector2(-label_width/2,21),Rules.SITES[i],PAPER,name_size)
	for enemy in state.enemies.values(): draw_circle(map_point(enemy.p),2.8,DANGER,true,-1,true)
	for id in state.players:
		var player = state.players[id]
		var pos := map_point(player.p)
		if player.hp <= 0: cross_at(pos,6,DANGER)
		else:
			draw_circle(pos,5,MINT if id!=local_id else PAPER,true,-1,true)
			draw_line(pos,pos+player.aim*9,INK,2,true)
		if id==local_id: draw_arc(pos,8,0,TAU,24,PAPER,1.5,true)
		if player.has("ping"):
			var pin := map_point(player.ping)
			draw_arc(pin,10,0,TAU,24,AMBER,2,true)
			if player.hp>0: diamond(pin,4,AMBER)
	var y := r.end.y+19
	caption(Vector2(r.position.x,y),"◇ Propiedad    • Intruso    + Aliado caído",PAPER,13)
	caption(Vector2(r.position.x,y+20),"Clic para señalar   ·   G para pedir apoyo",AMBER,14)
	caption(Vector2(r.position.x,y+39),"M para cerrar",MINT,13)

func draw_beacons():
	if not is_instance_valid(camera): return
	var area := Rect2(Vector2(90,120),size-Vector2(180,250))
	if area.size.x <= 0 or area.size.y <= 0: return
	for id in state.players:
		var player = state.players[id]
		if not player.has("ping"): continue
		var point := Vector3(player.ping.x,1.7,player.ping.y)
		var projected := camera.unproject_position(point)
		var local := camera.to_local(point)
		if local.z >= -camera.near:
			var side := -1.0 if local.x < 0 else 1.0
			projected = Vector2(area.get_center().x+side*area.size.x,area.end.y)
		var pos := projected.clamp(area.position,area.end)
		var tint := DANGER if player.hp<=0 else AMBER
		draw_circle(pos,10,INK,true,-1,true)
		if player.hp<=0: cross_at(pos,5,tint)
		else: diamond(pos,5,tint)
		var distance := roundi(state.players[local_id].p.distance_to(player.ping))
		var title := "%s · %d m" % [Rules.ROLES[player.role],distance]
		var width := ThemeDB.fallback_font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		draw_rect(Rect2(pos+Vector2(-width/2-5,11),Vector2(width+10,20)),INK)
		caption(pos+Vector2(-width/2,26),title,PAPER,14)
