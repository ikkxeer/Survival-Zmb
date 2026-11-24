extends SceneTree
## Compares three uses of the same opening budget over the first three nights with bots:
## personal weapons, automatic defences, or conquering properties.
##   godot --headless -s tests/strategy_compare.gd [-- --semillas=8]
## Bots are a rough proxy for players: the report flags a strategy that wins every run.
const Match = preload("res://game/match.gd")
const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
const P := Data.Phase
const STRATS = ["Armas personales", "Defensas automáticas", "Conquistar propiedades"]

func bot(g, id:int, dt:float):
	var p:Dictionary = g.players[id]
	if p.st != 0:
		if p.st == 1 and p.med > 0: g.act(id, "medkit")
		g.drive(id, p.p, p.aim, 0)
		return
	var posts := [Vector2(0, 4.5), Vector2(4.6, -0.5), Vector2(0, -5.4), Vector2(-4.6, -0.5)]
	var target := Vector2.INF
	var best := 13.0
	for e in g.enemies.values():
		if e.state == 2: continue
		var d:float = e.p.distance_to(p.p)
		if d < best:
			best = d
			target = e.p
	var buttons := 0
	var move := Vector2.ZERO
	var aim:Vector2 = p.aim
	if target != Vector2.INF:
		aim = target - p.p
		buttons = 1
		if best < 3.0: move = -aim.normalized()
	else:
		# like a player reading the breach warning: go towards the brotado closest to the house
		var post:Vector2 = posts[(id - 1) % 4]
		var threat := Vector2.INF
		var td := 26.0
		for e in g.enemies.values():
			if e.state == 2: continue
			var d:float = e.p.distance_to(Map.BASE_CENTER)
			if d < td:
				td = d
				threat = e.p
		if threat != Vector2.INF: post = Map.BASE_CENTER + (threat - Map.BASE_CENTER).normalized() * 5.5
		move = (post - p.p).limit_length(1.0)
		if g.core < g.core_max - 30 and p.p.distance_to(post) < 1: buttons = 2
	if p.mag[p.gun] == 0: g.act(id, "reload")
	g.drive(id, g.nav.move(p.p, move * g.player_speed(p) * dt, Match.PLAYER_R, 0), aim, buttons)

func run(strategy:int, seed:int) -> Dictionary:
	var g := Match.new()
	g.rng.seed = seed
	g.enemies.clear()
	g.plan_day()
	g.join(1, 2, "A")
	g.join(2, 3, "B")
	g.materials = 18
	for p in g.players.values(): p.coins = 24
	match strategy:
		0:
			for id in g.players:
				g.players[id].p = Map.PLAYER_SPAWN
				g.act(id, "buy_gun", [3])
		1:
			for spot in [Vector2(-2.5, 5.5), Vector2(2.5, 5.5)]:
				g.players[1].p = spot + Vector2(0, 1.2)
				g.act(1, "build", [Data.S_TURRET, g.nav.cell_of(spot)])
		2:
			for site in [3, 0]:
				g.players[1].p = Map.SITES[site].beacon + Vector2(-1.5 if site == 3 else 1.5, 0)
				g.act(1, "claim")
	var dt := 1.0 / 30.0
	var frames := 0
	var low_core := g.core
	while g.wave <= 3 and g.phase != P.OVER and frames < 30 * 60 * 12:
		for id in g.players: bot(g, id, dt)
		g.tick(dt)
		low_core = minf(low_core, g.core)
		if g.phase == P.PREP and frames % 60 == 0:
			for id in g.players:
				if not g.players[id].ready: g.act(id, "ready")
		frames += 1
	var coins := 0
	for p in g.players.values(): coins += p.coins
	return {"survived": g.phase != P.OVER, "core": g.core / g.core_max, "low": low_core / g.core_max, "mat": g.materials, "coins": coins, "kills": g.stats.kills}

func _initialize():
	var seeds := 8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--semillas="): seeds = int(a.substr(11))
	var table := []
	var wins := [0, 0, 0]
	var per_seed := []
	for s in seeds: per_seed.append([])
	for k in STRATS.size():
		var agg := {"survived":0, "core":0.0, "low":0.0, "mat":0.0, "coins":0.0, "kills":0.0}
		for s in seeds:
			var r := run(k, 1000 + s)
			per_seed[s].append(r)
			agg.survived += 1 if r.survived else 0
			for key in ["core", "low", "mat", "coins", "kills"]: agg[key] += r[key]
		table.append(agg)
	# a strategy "wins" a seed when it ends with the healthiest house plus resources
	for s in seeds:
		var best := 0
		for k in STRATS.size():
			var r:Dictionary = per_seed[s][k]
			var b:Dictionary = per_seed[s][best]
			if r.low + 0.002 * (r.mat + r.coins) > b.low + 0.002 * (b.mat + b.coins): best = k
		wins[best] += 1
	print("| Estrategia | Sobreviven | Casa al final | Casa mínima | Materiales | Fichas | Derribos | Mejor en |")
	print("| --- | --- | --- | --- | --- | --- | --- | --- |")
	for k in STRATS.size():
		var a:Dictionary = table[k]
		print("| %s | %d/%d | %d %% | %d %% | %.1f | %.1f | %.0f | %d/%d |" % [STRATS[k], a.survived, seeds, int(100 * a.core / seeds), int(100 * a.low / seeds), a.mat / seeds, a.coins / seeds, a.kills / seeds, wins[k], seeds])
	var dominant := wins.find(seeds)
	print("Ninguna estrategia domina en todas las semillas" if dominant < 0 else "DOMINA: %s" % STRATS[dominant])
	quit(0)
