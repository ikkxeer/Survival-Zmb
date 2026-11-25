extends SceneTree
## Rule checks for the authoritative simulation: godot --headless -s tests/match_test.gd
const Game = preload("res://game/match.gd")
const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
var failed := 0

func check(condition:bool, detail:String):
	if not condition:
		failed += 1
		push_error("FALLO: " + detail)
	else:
		print("ok  ", detail)

func clear_enemies(g):
	g.enemies.clear()

func _initialize():
	var g := Game.new()
	for i in range(1, 6): g.join(i, (i - 1) % 4, "J%d" % i)
	check(g.players.size() == 4, "Máximo de cuatro jugadores")
	var p:Dictionary = g.players[1]
	# --- construction and territory
	g.materials = 20
	var cell:int = g.nav.cell_of(Vector2(4.5, 5.5))
	p.p = Vector2(4.5, 7.0)
	g.act(1, "build", [Data.S_WALL, cell])
	check(g.structures.has(cell) and g.materials == 18, "La ingeniera construye una barricada con descuento (2 materiales)")
	g.act(1, "build", [Data.S_WALL, cell])
	check(g.materials == 18, "No se puede construir sobre otra defensa")
	var far:int = g.nav.cell_of(Vector2(30.5, 28.5))
	p.p = Vector2(30.5, 27.0)
	g.act(1, "build", [Data.S_WALL, far])
	check(not g.structures.has(far), "Fuera del territorio no se construye")
	p.p = Vector2(4.5, 7.0)
	g.act(1, "upgrade", [cell])
	check(g.structures[cell].lvl == 1 and g.structures[cell].max > 220, "Mejora de barricada a tablones")
	# --- path finding respects walls
	var before:int = g.nav.distance_at("base", 0, Vector2(0.5, 9.5))
	for x in range(-6, 7):
		var c:int = g.nav.cell_of(Vector2(x + 0.5, 8.5))
		g.structures[c] = {"k":Data.S_WALL, "lvl":0, "hp":120.0, "max":120.0, "cool":0.0, "owner":1, "aim":0.0, "on":true}
		g.nav.set_structure(c, Data.S_WALL, 120.0)
	g.nav.delay = 0
	while g.nav.update_one(): pass
	var after:int = g.nav.distance_at("base", 0, Vector2(0.5, 9.5))
	check(after > before, "Un muro alarga el camino de los brotados (%d → %d)" % [before, after])
	var next:int = g.nav.next_cell("base", 0, Vector2(0.5, 9.5))
	check(next >= 0, "Siempre existe una ruta hacia la casa")
	var breaker:int = g.nav.distance_at("base", 1, Vector2(0.5, 9.5))
	check(breaker <= after, "Los derribadores prefieren atravesar muros")
	for c in g.structures.keys():
		if c != cell: g.remove_structure(c, false)
	# --- scavenging (hold E)
	clear_enemies(g)
	var spot:Vector2 = Map.LOOT[0].p
	p.p = spot
	var mat:int = g.materials
	g.drive(1, spot, Vector2.DOWN, 2)
	for i in 60: g.tick(1.0 / 30.0)
	check(not g.loot[0] and g.materials > mat, "Rebuscar da materiales")
	g.drive(1, spot, Vector2.DOWN, 0)
	# --- cars are solid
	var car_c:Vector2 = Map.cars()[1][0]
	var walker := car_c + Vector2(-3.0, 0)
	for i in 120: walker = g.nav.move(walker, Vector2(4.0, 0) / 60.0, Game.PLAYER_R, 0)
	check(walker.x < car_c.x - Map.CAR_HALF.x - Game.PLAYER_R + 0.05 and walker.x > car_c.x - 1.6, "Un coche aparcado no se atraviesa")
	var zwalker := car_c + Vector2(0, -3.0)
	for i in 120: zwalker = g.nav.move(zwalker, Vector2(0, 4.0) / 60.0, 0.38, 1)
	check(zwalker.y < car_c.y - Map.CAR_HALF.y, "Los brotados tampoco atraviesan coches")
	check(g.nav.ray(car_c + Vector2(-5, 0), Vector2.RIGHT, 10.0) < 4.5, "Las balas chocan con los coches")
	# --- stacked turrets
	g.materials = 100
	var tc:int = g.nav.cell_of(Vector2(0.5, 8.5))
	g.players[1].p = Vector2(0.5, 6.0)
	g.act(1, "build", [Data.S_TURRET, tc])
	check(g.structures[tc].lvl == 0, "Una torreta nueva es simple")
	g.act(1, "build", [Data.S_TURRET, tc])
	check(g.structures[tc].lvl == 1, "Otra torreta encima la hace doble")
	g.act(1, "build", [Data.S_TURRET, tc])
	var mat_before:int = g.materials
	g.act(1, "build", [Data.S_TURRET, tc])
	check(g.structures[tc].lvl == 2 and g.materials == mat_before, "La tercera la hace triple y no pasa de ahí")
	g.demolish(g.players[1], tc)
	# --- shop and weapons
	p.p = Map.PLAYER_SPAWN
	p.coins = 40
	g.act(1, "buy_gun", [1])
	check(p.guns.has(1) and p.coins == 28 and p.gun == 1, "Compra del trabuco")
	g.act(1, "buy_gun", [4])
	check(not p.guns.has(4), "El rifle de tómbola exige la Comisaría")
	g.act(1, "up_gun", [1])
	check(p.guns[1] == 2 and p.coins == 18, "Mejora de arma")
	# --- firing and reloading
	clear_enemies(g)
	var e:Dictionary = g.new_enemy(0, p.p + Vector2(0, 3), "base", true)
	e.hp = 5.0
	g.drive(1, p.p, Vector2(0, 1), 1)
	g.tick(1.0 / 60.0)
	check(g.enemies.is_empty(), "El disparo derriba al brotado")
	check(p.mag[1] == 5, "El disparo gasta munición")
	g.drive(1, p.p, Vector2(0, 1), 0)
	g.act(1, "reload")
	for i in 120: g.tick(1.0 / 60.0)
	check(p.mag[1] == 6, "Recarga completa")
	# --- claim a property
	clear_enemies(g)
	g.materials = 30
	p.p = Map.SITES[5].beacon + Vector2(1.5, 0)
	g.act(1, "claim")
	check(g.sites[5].claimed and g.materials == 24, "Conquista de la Comisaría")
	p.p = Map.PLAYER_SPAWN
	p.coins = 30
	g.act(1, "buy_gun", [4])
	check(p.guns.has(4), "La Comisaría desbloquea el rifle de tómbola")
	var before_sell:int = p.coins
	g.act(1, "sell_gun", [4])
	check(not p.guns.has(4) and p.coins == before_sell + 13 and p.guns.has(p.gun), "Vender un arma devuelve la mitad y cambia a otra")
	g.act(1, "sell_gun", [0])
	check(p.guns.has(0), "La pistola de feria no se vende")
	p.tr = 2
	g.act(1, "sell_item", ["traca"])
	check(p.tr == 1 and p.coins == before_sell + 15, "Vender una traca")
	# --- downed and revived
	var mate:Dictionary = g.players[2]
	mate.p = p.p + Vector2(1, 0)
	g.hurt_player(mate, 500.0)
	check(mate.st == 1, "Un compañero cae al perder la salud")
	g.drive(1, p.p, Vector2.DOWN, 2)
	for i in 100: g.tick(1.0 / 30.0)
	check(mate.st == 0 and mate.hp > 0, "Reanimar manteniendo E")
	g.drive(1, p.p, Vector2.DOWN, 0)
	# --- role ability
	g.players[3].p = p.p
	g.act(3, "ability")
	check(g.players[3].buff > 0 and g.players[3].ab > 0, "Habilidad de oficio con recarga")
	# --- night and dawn
	g.clock = 0.0
	g.tick(0.016)
	check(g.phase == Data.Phase.NIGHT and g.queue.size() > 0, "Llega la noche con su oleada")
	check(g.assault_count == 2 and g.assaults.size() == 1, "La noche se divide en asaltos")
	g.queue.clear()
	for k in g.enemies.keys():
		if g.enemies[k].night: g.enemies.erase(k)
	g.tick(0.016)
	check(g.phase == Data.Phase.NIGHT and g.respite > 0, "Tras rechazar un asalto llega un respiro")
	check(g.drops.size() > 0, "El respiro trae una caja que se puede ir a buscar")
	g.tick(Game.RESPITE + 0.1)
	check(g.respite <= 0 and g.queue.size() > 0 and g.assault_index == 2, "Al acabar el respiro empieza el siguiente asalto")
	g.queue.clear()
	g.assaults.clear()
	for k in g.enemies.keys():
		if g.enemies[k].night: g.enemies.erase(k)
	var coins_before:int = p.coins
	g.tick(0.016)
	check(g.phase == Data.Phase.DAWN and g.wave == 2, "Amanece cuando no quedan brotados")
	check(p.coins > coins_before, "Recompensas al amanecer")
	g.tick(15.0)
	check(g.phase == Data.Phase.PREP, "Empieza un nuevo día")
	# --- the plaza bell votes for the night
	g.drops.clear()
	for id in g.players: g.players[id].ready = false
	p.p = Map.BELL + Vector2(0.5, 0)
	g.drive(1, p.p, Vector2.DOWN, 2)
	for i in 30: g.tick(1.0 / 30.0)
	check(p.ready, "Tocar la campana marca al jugador como listo")
	for i in 30: g.tick(1.0 / 30.0)
	check(p.ready, "Mantener E no vuelve a tocarla")
	g.drive(1, p.p, Vector2.DOWN, 0)
	g.tick(0.05)
	g.drive(1, p.p, Vector2.DOWN, 2)
	for i in 30: g.tick(1.0 / 30.0)
	check(not p.ready, "Volver a tocarla cancela el «listo»")
	g.drive(1, p.p, Vector2.DOWN, 0)
	# --- supply bundles for team-mates
	g.materials = 10
	p.p = Map.PLAYER_SPAWN
	g.act(1, "bundle")
	check(g.bundles.size() == 1 and g.materials == 6, "Preparar un lote cuesta materiales comunes")
	var q:Dictionary = g.players[2]
	q.st = 0
	q.med = 0
	q.p = g.bundles[0].p
	g.drive(2, q.p, Vector2.DOWN, 2)
	for i in 30: g.tick(1.0 / 30.0)
	check(g.bundles.is_empty() and q.med == 1 and p.helped == 1, "Un compañero recoge el lote y cuenta como ayuda")
	g.drive(2, q.p, Vector2.DOWN, 0)
	check(g.journal.any(func(e): return e.evento == "lote"), "El registro de la sesión anota el lote")
	# --- being hit interrupts a held action
	var mate2:Dictionary = g.players[3]
	mate2.st = 1
	mate2.hp = 0.0
	mate2.p = p.p + Vector2(1, 0)
	g.drive(1, p.p, Vector2.DOWN, 2)
	for i in 30: g.tick(1.0 / 30.0)
	var progress:float = p.ht
	g.hurt_player(p, 5.0)
	check(progress > 0.5 and p.ht == 0.0, "Recibir un golpe interrumpe la reanimación")
	g.drive(1, p.p, Vector2.DOWN, 0)
	g.revive(mate2, 50.0)
	# --- recovery after a bad night
	g.materials = 2
	var drops_before := g.drops.size()
	g.start_dawn()
	check(g.drops.size() == drops_before + 1 and g.drops[-1].rich, "Tras una mala noche llega un globo con reservas")
	g.drops.clear()
	g.materials = 30
	g.start_dawn()
	check(g.drops.is_empty(), "Si el equipo va bien no hay reservas extra")
	g.start_prep()
	# --- zombies damage what blocks them
	clear_enemies(g)
	var ring := []
	for x in range(-5, 5):
		for zz in range(-5, 4):
			if x == -5 or x == 4 or zz == -5 or zz == 3:
				var c:int = g.nav.cell_of(Vector2(x + 0.5, zz + 0.5))
				if g.nav.is_free_for_build(c):
					g.structures[c] = {"k":Data.S_WALL, "lvl":0, "hp":120.0, "max":120.0, "cool":0.0, "owner":1, "aim":0.0, "on":true}
					g.nav.set_structure(c, Data.S_WALL, 120.0)
					ring.append(c)
	g.nav.delay = 0
	while g.nav.update_one(): pass
	for id in g.players: g.players[id].p = Vector2(25, 25)
	var z:Dictionary = g.new_enemy(3, Vector2(0.5, 6.5), "base", true)
	for i in 600: g.tick(1.0 / 30.0)
	var hurt := 0
	for c in ring:
		if not g.structures.has(c) or g.structures[c].hp < 120.0: hurt += 1
	check(hurt > 0, "Un derribador destroza la barricada que le cierra el paso")
	# --- game over
	g.core = 0
	g.tick(0.016)
	check(g.phase == Data.Phase.OVER, "Derrota si cae la casa")
	g = Game.new()
	g.join(1, 1)
	g.players[1].med = 0
	g.hurt_player(g.players[1], 999)
	g.tick(0.016)
	check(g.phase == Data.Phase.OVER, "Derrota si cae todo el equipo")
	g = Game.new()
	g.join(1, 1)
	g.hurt_player(g.players[1], 999)
	g.tick(0.016)
	check(g.phase != Data.Phase.OVER, "Con botiquín aún se puede levantar en solitario")
	g.act(1, "medkit")
	check(g.players[1].st == 0, "El botiquín levanta al jugador caído")
	print("%d fallos" % failed)
	quit(1 if failed else 0)
