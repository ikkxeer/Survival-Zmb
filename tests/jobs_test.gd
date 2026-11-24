extends SceneTree
## Jobs board: generation rules over ten matches and the three kinds of job.
##   godot --headless -s tests/jobs_test.gd
const Game = preload("res://game/match.gd")
const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
const Nav = preload("res://game/nav.gd")
const P := Data.Phase
var failed := 0

func check(ok:bool, detail:String):
	if not ok:
		failed += 1
		push_error("FALLO: " + detail)
	else: print("ok  ", detail)

func hold(g, id:int, frames:int):
	g.drive(id, g.players[id].p, Vector2.DOWN, 2)
	for i in frames: g.tick(1.0 / 30.0)
	g.drive(id, g.players[id].p, Vector2.DOWN, 0)
	g.tick(1.0 / 30.0)

func _initialize():
	# --- generation: ten matches, six days each
	var days := 0
	var bad_reach := 0
	var bad_reward := 0
	var repeats := 0
	var wrong_mix := 0
	var kinds := {}
	for m in 10:
		var g := Game.new()
		var prev := []
		for d in 6:
			g.wave = d + 1
			g.make_jobs()
			days += 1
			if g.jobs.size() != 2 or g.jobs[0].size != "corto" or g.jobs[1].size != "ambicioso": wrong_mix += 1
			for j in g.jobs:
				kinds[j.kind] = true
				if g.nav.distance_at("base", 0, j.p) >= Nav.INF_D or g.nav.solid[g.nav.cell_of(j.p)]: bad_reach += 1
				if j.mat <= 0 or j.coins <= 0: bad_reward += 1
				if [j.kind, j.area] in prev: repeats += 1
			if g.jobs.size() == 2 and g.jobs[0].p.distance_to(Map.BASE_CENTER) >= g.jobs[1].p.distance_to(Map.BASE_CENTER): wrong_mix += 1
			prev = g.jobs.map(func(j): return [j.kind, j.area])
	check(wrong_mix == 0, "Cada día hay un encargo corto cerca y otro ambicioso lejos (%d días)" % days)
	check(bad_reach == 0, "Todos los destinos son alcanzables")
	check(bad_reward == 0, "Todas las recompensas son útiles")
	check(repeats == 0, "Ningún encargo repite tipo y lugar del día anterior")
	check(kinds.has("busqueda") and kinds.has("transporte") and kinds.has("defensa") and kinds.has("relevo"), "Aparecen búsquedas, transportes, defensas y relevos")
	# --- playing the jobs
	var g := Game.new()
	g.join(1, 3, "Noa")
	g.join(2, 1, "Leo")
	g.enemies.clear()
	var a:Dictionary = g.players[1]
	var search := {"id":900, "kind":"busqueda", "size":"corto", "p":Vector2(8.5, 8.5), "state":0, "progress":0.0, "carrier":-1, "mat":5, "coins":3, "risk":"bajo", "area":"la plaza", "spawned":0}
	var crate := {"id":901, "kind":"transporte", "size":"ambicioso", "p":Vector2(0.5, -20.5), "state":0, "progress":0.0, "carrier":-1, "mat":12, "coins":7, "risk":"alto", "area":"el parque", "spawned":0}
	g.jobs = [search, crate]
	a.p = Vector2(20, 20)
	g.act(1, "job_accept", [900])
	check(search.state == 0, "Los encargos se aceptan en el tablón")
	a.p = Map.BOARD + Vector2(0, 1)
	g.act(1, "job_accept", [900])
	g.act(1, "job_accept", [901])
	check(search.state == 1 and crate.state == 1, "Se aceptan en el tablón")
	var mat:int = g.materials
	var coins_b:int = g.players[2].coins
	a.p = search.p
	hold(g, 1, 60)
	check(search.state == 2 and g.materials == mat + 5 and g.players[2].coins == coins_b + 3, "La búsqueda se cumple y la recompensa es para todos")
	a.p = crate.p
	hold(g, 1, 30)
	check(a.cargo == 901 and crate.carrier == 1, "Se carga la caja del transporte")
	g.hurt_player(a, 999.0)
	check(a.cargo == -1 and crate.carrier == -1, "Al caer se suelta la caja")
	g.revive(a, 60.0)
	a.p = crate.p
	hold(g, 1, 30)
	a.p = Map.PORCH + Vector2(0, 1)
	g.tick(0.05)
	hold(g, 1, 30)
	check(crate.state == 2 and a.cargo == -1, "Entregar la caja en el porche cumple el transporte")
	var zone := {"id":902, "kind":"defensa", "size":"corto", "p":Vector2(-8.5, 8.5), "state":1, "progress":0.0, "carrier":-1, "mat":8, "coins":5, "risk":"medio", "area":"la plaza", "spawned":0}
	g.jobs = [zone]
	a.p = zone.p
	g.tick(1.0)
	check(zone.progress > 0.5 and g.enemies.size() > 0, "La defensa avanza en la zona y atrae brotados")
	a.p = Vector2(25, 25)
	var stuck:float = zone.progress
	g.tick(1.0)
	check(is_equal_approx(zone.progress, stuck), "Fuera de la zona la defensa no avanza")
	a.p = zone.p
	for i in 30:
		for q in g.players.values():
			q.hp = q.hpmax
			q.st = 0
		g.tick(1.0)
	check(zone.state == 2, "Aguantar el tiempo cumple la defensa")
	var drop := {"id":903, "kind":"busqueda", "size":"ambicioso", "p":Vector2(20.5, 20.5), "state":1, "progress":0.0, "carrier":-1, "mat":10, "coins":6, "risk":"alto", "area":"las casas", "spawned":0}
	var expire := {"id":904, "kind":"busqueda", "size":"corto", "p":Vector2(8.5, -8.5), "state":1, "progress":0.0, "carrier":-1, "mat":5, "coins":3, "risk":"bajo", "area":"la plaza", "spawned":0}
	g.jobs = [drop, expire]
	g.act(1, "job_abandon", [903])
	check(drop.state == 3, "Un encargo se puede abandonar")
	g.clock = 0.0
	g.tick(0.05)
	check(g.phase == P.NIGHT and expire.state == 3, "Los encargos pendientes caducan al anochecer")
	# --- electric relay: explorer finds, engineer installs, or one player over several visits
	var r := Game.new()
	r.join(1, 3, "Noa")
	r.join(2, 0, "Ana")
	r.enemies.clear()
	var relay := {"id":950, "kind":"relevo", "size":"ambicioso", "p":Vector2(-20.5, 26.5), "state":1, "progress":0.0, "carrier":-1, "found":false, "mat":12, "coins":7, "risk":"alto", "area":"el Almacén", "spawned":0}
	r.jobs = [relay]
	check(not r.snapshot().jobs[0][12], "El relevo empieza sin localizar y no se marca")
	var noa:Dictionary = r.players[1]
	var ana:Dictionary = r.players[2]
	noa.p = relay.p + Vector2(18, 0)
	r.act(1, "ability")
	check(relay.found, "La habilidad de la exploradora localiza el relevo a distancia")
	ana.p = relay.p
	hold(r, 2, 40)
	check(ana.cargo == 950 and relay.carrier == 2, "Se carga con el relevo")
	ana.p = Map.RELAY + Vector2(0, 1.5)
	r.tick(0.05)
	hold(r, 2, 50)
	check(r.relay and relay.state == 2, "La ingeniera lo instala en 1,5 s")
	r.night_event = 1
	r.phase = P.NIGHT
	check(r.powered(r.nav.cell_of(Vector2(5.5, 5.5))), "Con el relevo hay corriente durante el apagón")
	var solo := Game.new()
	solo.join(1, 2, "Iker")
	solo.enemies.clear()
	var relay2 := {"id":951, "kind":"relevo", "size":"ambicioso", "p":Vector2(24.5, 27.5), "state":1, "progress":0.0, "carrier":-1, "found":false, "mat":12, "coins":7, "risk":"alto", "area":"las casas", "spawned":0}
	solo.jobs = [relay2]
	var ik:Dictionary = solo.players[1]
	ik.p = relay2.p + Vector2(3, 0)
	solo.tick(0.05)
	check(relay2.found, "Sin exploradora se encuentra buscando a pie")
	solo.start_night()
	check(relay2.state == 1, "El relevo no caduca al anochecer: se puede terminar otro día")
	solo.wave = 2
	solo.make_jobs()
	check(solo.jobs.has(relay2) and solo.jobs.size() == 2, "Al día siguiente sigue en el tablón junto a un encargo corto")
	solo.phase = P.PREP
	ik.p = relay2.p
	hold(solo, 1, 40)
	ik.p = Map.RELAY + Vector2(0, 1.5)
	solo.tick(0.05)
	hold(solo, 1, 50)
	check(not solo.relay, "Quien no es ingeniera tarda más en instalarlo")
	hold(solo, 1, 160)
	check(solo.relay, "...pero también puede instalarlo")
	print("%d fallos" % failed)
	quit(1 if failed else 0)
