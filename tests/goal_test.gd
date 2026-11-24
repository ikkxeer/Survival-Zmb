extends SceneTree
## End goal "Encender la verbena": pieces, carrying, installing, final night, victory and rematch.
##   godot --headless -s tests/goal_test.gd
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

func hold(g, id:int, frames:int):
	g.drive(id, g.players[id].p, Vector2.DOWN, 2)
	for i in frames: g.tick(1.0 / 30.0)
	g.drive(id, g.players[id].p, Vector2.DOWN, 0)
	g.tick(1.0 / 30.0)

func _initialize():
	call_deferred("run")

func run():
	var g := Game.new()
	g.join(1, 0, "Ana")
	g.join(2, 1, "Leo")
	var a:Dictionary = g.players[1]
	g.enemies.clear()
	check(g.pieces.size() == 4 and g.pieces.all(func(pc): return pc.state == 0), "Las cuatro piezas empiezan bloqueadas")
	g.materials = 50
	a.p = Map.SITES[0].beacon + Vector2(1.5, 0)
	g.act(1, "claim")
	check(g.pieces[0].state == 1, "Conquistar el Taller descubre su pieza")
	a.p = g.pieces[0].p
	var base_speed:float = g.player_speed(a)
	hold(g, 1, 30)
	check(a.carry == 0 and g.pieces[0].state == 2, "Mantener E carga con la pieza")
	check(g.player_speed(a) < base_speed, "Quien carga va más despacio")
	g.hurt_player(a, 999.0)
	check(a.carry == -1 and g.pieces[0].state == 3, "Al caer se suelta la pieza donde estaba")
	g.revive(a, 50.0)
	a.p = g.pieces[0].p
	hold(g, 1, 30)
	a.p = Map.STAGE + Vector2(0, 1.5)
	g.tick(0.05)
	hold(g, 1, 45)
	check(g.pieces[0].state == 4 and a.carry == -1 and g.installed_pieces() == 1, "La pieza se instala en el escenario")
	a.p = Map.STAGE + Vector2(0, 1.5)
	g.drive(1, a.p, Vector2.DOWN, 2)
	g.tick(0.05)
	check(a.prompt.find("ENCENDER") < 0, "No se puede encender con piezas pendientes")
	g.drive(1, a.p, Vector2.DOWN, 0)
	for i in range(1, 4): g.pieces[i].state = 4
	hold(g, 1, 70)
	check(g.finale and g.phase == P.NIGHT and g.fronts.size() == 4, "Con las cuatro piezas se enciende la noche final por todas las calles")
	g.tick(1.0)
	check(g.finale_t < Data.FINALE_TIME and not g.victory, "La noche final tiene cuenta atrás")
	g.core = 9999.0
	g.core_max = 9999.0
	for q in g.players.values(): q.med = 9
	var steps := 0
	while g.phase != P.OVER and steps < 4000:
		for q in g.players.values():
			q.hp = q.hpmax
			q.st = 0
		g.tick(1.0 / 20.0)
		steps += 1
	check(g.victory and g.phase == P.OVER, "Aguantar hasta la traca final da la victoria")
	check(g.enemies.is_empty(), "Los brotados restantes desaparecen en la celebración")
	# defeat during the finale
	var h := Game.new()
	h.join(1, 2, "Iker")
	for pc in h.pieces: pc.state = 4
	h.start_finale(h.players[1])
	h.core = 0
	h.tick(0.05)
	check(h.phase == P.OVER and not h.victory, "Si cae la casa durante el final, se pierde")
	# rematch from the game scene keeps the group and resets the neighbourhood
	var game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	game.start("solo", 3, "", "Noa")
	game.sim.materials = 99
	game.sim.wave = 4
	var mid:int = game.sim.match_id
	game.rematch()
	check(game.sim.wave == 1 and game.sim.materials != 99 and game.sim.players.has(1) and game.sim.players[1].role == 3 and game.sim.players[1].name == "Noa", "La revancha conserva al grupo y reinicia el barrio")
	check(game.sim.match_id != mid, "La revancha es una partida nueva para los clientes")
	game.stop("")
	print("%d fallos" % failed)
	quit(1 if failed else 0)
