extends RefCounted
## All positions use X/Z metres. Only the host advances this simulation.
const GATES = [Vector2(0,5), Vector2(5,0), Vector2(0,-5), Vector2(-5,0)]
const CACHES = [Vector2(-10,8),Vector2(10,-8),Vector2(-10,-8),Vector2(10,8)]
const ROLES = ["Ingeniera","Médico","Soldado","Exploradora"]
const WEAPONS = ["Lanzacorchos","Trabuco de confeti","Carabina de feria"]
const PRICES = [0,9,14]
var players := {}
var enemies := {}
var gates := []
var caches := [true,true,true,true]
const SITES = ["Taller","Dispensario","Economato","Almacén"]
var claimed := [false,false,false,false]
var event := "Serena"
var phase := "Preparación"
var wave := 1
var clock := 55.0
var core := 100.0
var wood := 12
var reserve := 0
var spawn_timer := 0.0
var serial := 0
var shots := []
var rng := RandomNumberGenerator.new()

func _init():
	rng.randomize()
	for i in 4:
		gates.append({"kind":0,"hp":0.0,"max":0.0,"cool":0.0})

func join(id:int, role:int):
	if players.has(id) or players.size() >= 4 or phase == "Fin": return
	players[id] = {"p":Vector2(players.size()-1,3.5),"hp":100.0,"role":clampi(role,0,3),"coins":4,"gun":0,"owned":[0],"aim":Vector2.DOWN,"cool":0.0,"move":Vector2.ZERO,"fire":false,"notice":"","message_time":0.0}

func drive(id:int, move:Vector2, aim:Vector2, fire:bool):
	if not players.has(id) or not move.is_finite() or not aim.is_finite(): return
	var p = players[id]
	p.move = move.limit_length()
	if aim.length_squared() > 0.01: p.aim = aim.normalized()
	p.fire = fire

func say(p:Dictionary, msg:String):
	p.notice = msg
	p.message_time = 2.4

func nearest(pos:Vector2, places:Array, reach:float) -> int:
	var best := -1
	for i in places.size():
		var distance = pos.distance_to(places[i])
		if distance < reach:
			best = i
			reach = distance
	return best

func act(id:int, action:String):
	if not players.has(id) or phase == "Fin": return
	var p = players[id]
	if p.hp <= 0: return
	var gate := nearest(p.p,GATES,2.7)
	if action == "use":
		for mate in players.values():
			if mate != p and p.p.distance_to(mate.p) < 2.6 and (mate.hp <= 0 or (p.role == 1 and mate.hp < 90)):
				if wood < 1: return say(p,"Falta 1 material para curar")
				wood -= 1
				mate.hp = minf(100,mate.hp + (65 if p.role == 1 else 30))
				return say(p,"Compañero atendido")
		var cache := nearest(p.p,CACHES,2.8)
		if cache >= 0 and caches[cache]:
			caches[cache] = false
			wood += 6 if p.role == 3 else 4
			p.coins += 3
			return say(p,"Suministros recogidos")
		if gate >= 0 and gates[gate].hp > 0 and gates[gate].hp < gates[gate].max:
			if wood < 1: return say(p,"Falta 1 material")
			wood -= 1
			gates[gate].hp = minf(gates[gate].max,gates[gate].hp + (48 if p.role == 0 else 30))
			return say(p,"Defensa reparada")
		if p.p.length() < 5 and core < 100:
			if wood < 2: return say(p,"Faltan 2 materiales")
			wood -= 2
			core = minf(100,core + (25 if p.role == 0 else 15))
			return say(p,"Casa reparada")
		return say(p,"Acércate a una caja, defensa dañada o compañero")
	if action == "claim":
		var site := nearest(p.p,CACHES,2.8)
		if site < 0: return say(p,"Acércate al cartel de una propiedad")
		if phase == "Noche": return say(p,"Asegura la propiedad durante el día")
		if claimed[site]: return say(p,"Esta propiedad ya pertenece al barrio")
		if wood < 8: return say(p,"Necesitas 8 materiales para asegurarla")
		wood -= 8
		claimed[site] = true
		return say(p,SITES[site]+" se une al barrio")
	if action == "upgrade":
		if gate < 0 or gates[gate].hp <= 0: return say(p,"Acércate a una defensa construida")
		var g = gates[gate]
		if g.max >= (145 if g.kind == 1 else 98): return say(p,"Defensa al máximo")
		if wood < 4: return say(p,"Necesitas 4 materiales")
		wood -= 4
		g.max += 50
		g.hp = g.max
		return say(p,"Defensa reforzada")
	if action in ["wall","coil"]:
		if gate < 0: return say(p,"Construye en una de las cuatro plataformas")
		var g = gates[gate]
		if g.hp > 0: return say(p,"Plataforma ocupada")
		var cost := (3 if action == "wall" else 7) - (1 if p.role == 0 else 0)
		if wood < cost: return say(p,"Materiales insuficientes")
		wood -= cost
		g.kind = 1 if action == "wall" else 2
		g.max = 95.0 if g.kind == 1 else 48.0
		g.hp = g.max
		return say(p,"Defensa instalada")
	if action in ["0","1","2"]:
		if p.p.length() > 5: return say(p,"La armería está en la casa")
		var index := int(action)
		if not index in p.owned:
			if p.coins < PRICES[index]: return say(p,"Faltan fichas")
			p.coins -= PRICES[index]
			p.owned.append(index)
		p.gun = index
		return say(p,WEAPONS[index])

func hit_enemy(id:int, damage:float, owner:int):
	if not enemies.has(id): return
	enemies[id].hp -= damage
	if enemies[id].hp <= 0:
		enemies.erase(id)
		if players.has(owner): players[owner].coins += 1
		else: wood += 1

func fire_weapon(id:int,p:Dictionary):
	var reach:float = [9,6.5,14][p.gun]
	var damage:float = [20,18,37][p.gun] * (1.25 if p.role == 2 else 1.0)
	p.cool = [0.37,0.85,0.58][p.gun]
	var spread = [-0.19,0,0.19] if p.gun == 1 else [0]
	for angle in spread:
		var direction:Vector2 = p.aim.rotated(angle)
		var target := -1
		var length := reach
		for key in enemies:
			var relative:Vector2 = enemies[key].p-p.p
			var along := relative.dot(direction)
			if along > 0 and along < length and absf(relative.cross(direction)) < 0.72:
				length = along
				target = key
		shots.append([p.p,p.p + direction*length,p.gun])
		hit_enemy(target,damage,id)

func tick(dt:float):
	if phase == "Fin" or players.is_empty(): return
	var alive := false
	for id in players:
		var p = players[id]
		p.message_time = maxf(0,p.message_time-dt)
		if p.hp <= 0: continue
		alive = true
		var next:Vector2 = p.p + p.move * dt * (6.5 if p.role == 3 else 5.3)
		next = next.clamp(Vector2(-15,-13),Vector2(15,13))
		if absf(next.x)<2.65 and absf(next.y)<2.45:
			if absf(p.p.x)>=2.65: next.x=p.p.x
			else: next.y=p.p.y
		p.p = next
		p.cool -= dt
		if p.fire and p.cool <= 0: fire_weapon(id,p)
	if not alive or core <= 0:
		phase = "Fin"
		return
	if phase != "Noche":
		clock -= dt
		if clock <= 0:
			if phase == "Recuperación":
				phase = "Preparación"
				clock = 32
			else:
				phase = "Noche"
				event = ["Serena","Apagón","Estampida"][rng.randi_range(0,2)] if wave > 1 else "Serena"
				reserve = 5 + wave*2 + players.size()*2 + 2*claimed.count(true)
				spawn_timer = 0
		return
	spawn_timer -= dt
	if reserve > 0 and spawn_timer <= 0 and enemies.size() < 48:
		reserve -= 1
		spawn_timer = maxf(0.5,1.65-wave*0.08)
		serial += 1
		var lane := rng.randi_range(0,3)
		var axis:Vector2 = GATES[lane].normalized()
		if event == "Estampida": spawn_timer *= 0.65
		var kind := rng.randi_range(0,mini(2,wave-1))
		enemies[serial] = {"p":axis*15 + axis.orthogonal()*rng.randf_range(-2,2),"kind":kind,"hp":[44,30,95][kind],"lane":lane,"passed":false}
	for lane in gates.size():
		var g = gates[lane]
		g.cool -= dt
		if event == "Apagón" or g.kind != 2 or g.hp <= 0 or g.cool > 0: continue
		for key in enemies.keys():
			if enemies[key].p.distance_to(GATES[lane]) < 5:
				shots.append([GATES[lane],enemies[key].p,3])
				hit_enemy(key,17,-1)
				g.cool = 0.7
				break
	for e in enemies.values():
		var dest:Vector2 = GATES[e.lane]
		var speed:float = [1.45,2.45,1.0][e.kind]
		var dps:float = [5,4,11][e.kind]
		var victim = null
		var near := 3.8
		for p in players.values():
			var dist:float = p.p.distance_to(e.p)
			if p.hp > 0 and dist < near:
				victim = p
				near = dist
		if victim != null:
			dest = victim.p
			if near < 0.95:
				victim.hp = maxf(0,victim.hp-dps*dt)
				continue
		elif not e.passed and e.p.distance_to(dest) < 0.9:
			var g = gates[e.lane]
			if g.hp > 0:
				g.hp = maxf(0,g.hp-dps*dt)
				continue
			e.passed = true
		if victim == null and e.passed:
			dest = Vector2.ZERO
			if e.p.length() < 2.95:
				core = maxf(0,core-dps*dt)
				continue
		e.p = e.p.move_toward(dest,speed*dt)
	if reserve == 0 and enemies.is_empty():
		phase = "Recuperación"
		wave += 1
		clock = 10
		wood += 4 + (4 if claimed[3] else 0)
		if claimed[0]: core = minf(100,core+12)
		caches.fill(true)
		for p in players.values():
			p.coins += 5 + (3 if claimed[2] else 0)
			p.hp = minf(100,maxf(20,p.hp)+(40 if claimed[1] else 15))

func snapshot() -> Dictionary:
	return {"claimed":claimed,"event":event,"players":players,"enemies":enemies,"gates":gates,"caches":caches,"phase":phase,"wave":wave,"clock":clock,"core":core,"wood":wood,"remaining":reserve+enemies.size(),"shots":shots.duplicate()}
