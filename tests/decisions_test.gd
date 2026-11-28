extends SceneTree
## Decisions that carry over: where rescued neighbours work, and optional rule sets.
##   godot --headless -s tests/decisions_test.gd
const Game = preload("res://game/match.gd")
const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
const P := Data.Phase
var failed := 0

func check(ok:bool, detail:String):
	if not ok:
		failed += 1
		push_error("FALLO: " + detail)
	else: print("ok  ", detail)

func _initialize():
	var g := Game.new()
	g.join(1, 0, "Ana")
	var a:Dictionary = g.players[1]
	g.enemies.clear()
	g.materials = 60
	a.p = Map.SITES[3].beacon + Vector2(-1.5, 0)
	g.act(1, "claim")
	g.community = [0, 2]
	g.posts = [-1, -1]
	g.materials = 0
	g.start_dawn()
	var home_gain:int = g.materials
	check(home_gain >= 5 + 8 + 3, "El carpintero en casa aporta materiales y el Almacén su bonificación")
	a.p = Map.BOARD + Vector2(0, 1)
	g.act(1, "assign", [0, 3])
	check(g.posts[0] == 3 and g.sites[3].max == 300.0, "El carpintero va al Almacén y refuerza su estandarte")
	g.materials = 0
	g.start_dawn()
	check(g.materials == 5 + 12, "En el Almacén ya no da materiales en casa, pero sube su bonificación un 50 %")
	check(g.report.any(func(r): return r.contains("Carpintero en Almacén")), "El informe del amanecer cuenta dónde trabaja cada vecino")
	g.act(1, "assign", [1, 3])
	check(g.home_count(2) == 0, "El vigía enviado fuera deja de disparar desde el tejado")
	g.damage_site(3, 9999.0)
	check(g.posts == [-1, -1], "Si se pierde la propiedad, sus vecinos vuelven a casa")
	g.act(1, "assign", [0, 0])
	check(g.posts[0] == -1, "No se puede enviar a una propiedad que no es del barrio")
	# rule sets
	var dark := Game.new()
	dark.join(1, 1, "Leo")
	dark.set_variant(1)
	var all_dark := true
	for w in range(2, 10):
		dark.wave = w
		var ev := dark.pick_event()
		if w % 5 != 0 and ev != 1: all_dark = false
	check(all_dark, "Barrio a oscuras: todas las noches son de apagón salvo las de gigantes")
	dark.wave = 2
	dark.plan_day()
	check(dark.day_plan.drop >= 0, "Barrio a oscuras: cada día cae un globo")
	var e:Dictionary = dark.new_enemy(0, Vector2(30, 30), "base", true)
	var before:int = dark.players[1].coins
	dark.kill_enemy(dark.enemies.find_key(e), 1)
	check(dark.players[1].coins == before + 2, "Barrio a oscuras: más fichas por brotado")
	var rush := Game.new()
	rush.join(1, 2, "Iker")
	rush.set_variant(2)
	check(rush.fronts.size() == 2 and rush.phase_len == 60.0, "Estampida: dos frentes y menos tiempo ya el primer día")
	rush.clock = 0.0
	rush.tick(0.05)
	var runners := 0
	for k in rush.queue + rush.assaults.reduce(func(acc, x): return acc + x, []): if k == 1: runners += 1
	check(runners > 0, "Estampida: corredores desde la primera noche")
	rush.queue.clear()
	rush.assaults.clear()
	rush.enemies.clear()
	rush.materials = 0
	rush.tick(0.05)
	check(rush.phase == P.DAWN and rush.materials >= 9, "Estampida: cada amanecer trae materiales extra")
	rush.tick(15.0)
	check(rush.phase_len == 45.0, "Estampida: los días duran 45 s")
	# the baker, the priest and the stall-keeper
	var town := Game.new()
	town.join(1, 2, "Mar")
	var m:Dictionary = town.players[1]
	town.enemies.clear()
	town.community = [0, 1, 2]
	town.posts = [-1, -1, -1]
	var picks := {}
	for i in 20: picks[town.pick_survivor()] = true
	check(picks.keys().all(func(k): return k >= 3), "Un vecino nuevo es de los que aún faltan en la comunidad")
	town.community = [3]
	town.posts = [-1]
	m.hp = 20.0
	town.start_dawn()
	check(m.hp >= 20.0 + 20.0 + Data.BAKER_HEAL - 0.1 and town.report.any(func(r): return r.contains("Panadera")), "La panadera cura a todos al amanecer y lo cuenta el informe")
	town.community = [4]
	town.posts = [-1]
	town.phase = P.NIGHT
	town.queue.clear()
	town.assaults = [[0]]
	town.tick(0.05)
	check(absf(town.respite - (Game.RESPITE + Data.PRIEST_RESPITE)) < 0.2, "El cura alarga el respiro entre asaltos")
	town.respite = 0.0
	town.phase = P.PREP
	town.community = [5]
	town.posts = [-1]
	m.p = Map.PLAYER_SPAWN
	m.coins = 100
	town.act(1, "buy_gun", [3])
	check(m.coins == 100 - roundi(Data.WEAPONS[3].price * Data.FAIR_DISCOUNT), "El feriante en casa rebaja la tienda")
	town.posts = [0]
	check(town.price(10) == 10, "Si el feriante trabaja en una propiedad, la tienda vuelve a su precio")
	print("%d fallos" % failed)
	quit(1 if failed else 0)
