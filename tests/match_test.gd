extends SceneTree
const Game = preload("res://game/match.gd")
var failed := false
func check(condition:bool,detail:String):
	if not condition:
		failed = true
		push_error(detail)

func _initialize():
	var g := Game.new()
	for i in range(1,6): g.join(i,i-1)
	check(g.players.size()==4,"Límite de jugadores")
	var p = g.players[1]
	p.p = Game.GATES[0]
	g.act(1,"wall")
	check(g.wood==10 and g.gates[0].hp==95,"Construcción con descuento")
	g.gates[0].hp = 20
	g.act(1,"use")
	check(g.wood==9 and g.gates[0].hp==68,"Reparación")
	p.p = Game.CACHES[0]
	g.act(1,"use")
	g.act(1,"use")
	check(g.wood==13 and p.coins==7,"Recogida única")
	g.players[2].hp = 0
	g.players[2].p = p.p
	g.act(1,"use")
	check(g.players[2].hp==30,"Reanimación")
	p.p = Vector2(0,3)
	p.coins = 10
	g.act(1,"1")
	g.act(1,"1")
	check(p.gun==1 and p.coins==1,"Compra y cambio sin doble cobro")
	g.clock = 0
	g.tick(0.016)
	g.tick(0.016)
	check(g.phase=="Noche" and g.enemies.size()==1,"Llegada de la primera oleada")
	g.reserve = 0
	var e = g.enemies.values()[0]
	e.p = Vector2(0,5.1)
	e.hp = 10
	g.drive(1,Vector2.ZERO,Vector2.DOWN,true)
	g.tick(0.016)
	check(g.phase=="Recuperación" and g.wave==2 and g.shots.size()==3,"Disparo y recompensa de oleada")
	g.tick(11)
	check(g.phase=="Preparación" and g.caches[0],"Inicio del siguiente día")
	g.core = 0
	g.tick(0.016)
	check(g.phase=="Fin","Derrota por pérdida de casa")
	g = Game.new()
	g.join(1,1)
	g.players[1].hp = 0
	g.tick(0.016)
	check(g.phase=="Fin","Derrota por equipo caído")
	quit(1 if failed else 0)
