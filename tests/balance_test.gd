extends SceneTree
## Plays several full matches with the soak bots and reports which night breaks the defence and why.
## godot --headless -s tests/balance_test.gd -- --partidas=5 --jugadores=4 --semilla=1 --noches=8
## Each match uses seed, seed+1, ... so two versions of the game can be compared on the same matches.
## Exits with 1 if any match falls before --objetivo (night 6 by default).
const Match = preload("res://game/match.gd")
const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
const Soak = preload("res://tests/soak_test.gd")

func arg(name:String, fallback:int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return int(a.split("=")[1])
	return fallback

func setup(g):
	## The same ring of defences as the soak test, scaled to the materials of a real first day.
	var spots := [Vector2(-4.5,4.5), Vector2(4.5,4.5), Vector2(-5.5,-1.5), Vector2(5.5,-1.5), Vector2(0.5,6.5), Vector2(-1.5,-5.5)]
	var kinds := [Data.S_TURRET, Data.S_COIL, Data.S_WALL, Data.S_WALL, Data.S_LIGHT, Data.S_GEN]
	g.materials = 100
	var first:int = g.players.keys()[0]
	for i in spots.size():
		g.players[first].p = spots[i] + Vector2(0, 1.2)
		g.act(first, "build", [kinds[i], g.nav.cell_of(spots[i])])
	g.players[first].p = Map.PLAYER_SPAWN
	g.act(first, "build", [Data.S_WIRE, g.nav.cell_of(Vector2(2.5, 8.5))])
	g.act(first, "build", [Data.S_MINE, g.nav.cell_of(Vector2(-2.5, 8.5))])
	g.act(first, "build", [Data.S_BENCH, g.nav.cell_of(Vector2(6.5, 2.5))])

func play(seed:int, players:int, nights:int) -> Dictionary:
	var g := Match.new()
	for i in players: g.join(i + 1, i, "Bot%d" % i)
	g.reseed(seed)
	setup(g)
	var dt := 1.0 / 30.0
	var frames := 0
	var log := []
	var night := {}
	var low := 1e9
	var seen := 0
	var downs := 0
	var all_down := 0.0
	var built:int = g.structures.size()
	while g.wave <= nights and g.phase != Data.Phase.OVER and frames < 30 * 60 * 40:
		for id in g.players: Soak.bot(g, id, dt)
		g.tick(dt)
		if g.phase == Data.Phase.NIGHT:
			low = minf(low, g.core)
			if g.alive_players().is_empty(): all_down += dt
		for ev in g.events:
			if ev[0] <= seen: continue
			seen = ev[0]
			if ev[2] == "down": downs += 1
		for line in g.journal:
			match line.evento:
				"noche": night = {"noche":line.noche, "tipo":line.tipo, "brotados":line.brotados, "frentes":line.frentes.size()}
				"medianoche": night["plañideras"] = line.planideras
				"amanecer", "fin":
					if not night.is_empty():
						night["casa_min"] = int(low)
						night["dano"] = line.dano_casa
						night["cae"] = line.evento == "fin"
						night["caidos"] = downs
						night["sin_nadie"] = all_down
						night["defensas"] = "%d→%d" % [built, g.structures.size()]
						log.append(night)
					night = {}
					low = 1e9
					downs = 0
					all_down = 0.0
					built = g.structures.size()
		g.journal.clear()
		frames += 1
		if g.phase == Data.Phase.PREP and frames % 300 == 0:
			for id in g.players: if g.players[id].st == 0: g.act(id, "ready")
	var reached:int = g.wave if g.phase != Data.Phase.OVER or g.victory else g.wave
	return {"seed":seed, "wave":reached, "over":g.phase == Data.Phase.OVER, "why":g.report[0] if g.phase == Data.Phase.OVER else "", "nights":log}

func describe(n:Dictionary) -> String:
	var hits:Dictionary = n.get("dano", {})
	var keys := hits.keys()
	keys.sort_custom(func(a, b): return hits[a] > hits[b])
	var parts := []
	for k in keys.slice(0, 4): parts.append("%s %d" % [k, hits[k]])
	return "noche %d %-17s %2d brotados %d frente(s)%s · casa mín %3d · %d caídas, %ds sin nadie en pie · defensas %s · %s%s" % [n.noche, n.tipo, n.brotados, n.frentes,
		" +%d plañ." % n["plañideras"] if n.has("plañideras") else "", n.casa_min, n.caidos, int(n.sin_nadie), n.defensas, ", ".join(parts) if parts.size() else "sin daño", "  ← CAE" if n.cae else ""]

func _initialize():
	var count := arg("partidas", 5)
	var players := clampi(arg("jugadores", 4), 1, 4)
	var seed := arg("semilla", 1)
	var nights := arg("noches", 8)
	var goal := arg("objetivo", 6)
	var verbose := arg("detalle", 1)
	var reached := []
	var falls := {}
	var killer := {}
	print("Equilibrio: %d partidas, %d jugador(es), semilla %d" % [count, players, seed])
	for i in count:
		var r := play(seed + i, players, nights)
		reached.append(r.wave)
		print("Partida %d (semilla %d): %s noche %d%s" % [i + 1, r.seed, "cae en la" if r.over else "llega a la", r.wave, " · " + r.why if r.over else ""])
		for n in r.nights:
			if verbose > 0: print("   ", describe(n))
			if n.cae:
				falls[n.noche] = falls.get(n.noche, 0) + 1
				for k in n.dano: killer[k] = killer.get(k, 0) + n.dano[k]
	var ok := reached.filter(func(w): return w >= goal).size()
	print("Noches alcanzadas: %s · %d de %d llegan a la noche %d" % [str(reached), ok, count, goal])
	if not falls.is_empty(): print("Caídas por noche: %s · daño en las noches perdidas: %s" % [str(falls), str(killer)])
	quit(0 if ok == count else 1)
