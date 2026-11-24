extends SceneTree
## Interrupted sessions: dawn checkpoint, reconnection in another order, ownership of
## tokens and equipment, territory and night, and recovery from a half-written save.
##   godot --headless -s tests/checkpoint_test.gd
const Game = preload("res://game/match.gd")
const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
const Checkpoint = preload("res://game/checkpoint.gd")
const P := Data.Phase
var failed := 0

func check(ok:bool, detail:String):
	if not ok:
		failed += 1
		push_error("FALLO: " + detail)
	else: print("ok  ", detail)

func _initialize():
	call_deferred("run")

func run():
	var keep := [FileAccess.get_file_as_bytes(Checkpoint.PATH) if FileAccess.file_exists(Checkpoint.PATH) else PackedByteArray()]
	Checkpoint.clear()
	var g := Game.new()
	g.join(11, 0, "Ana")
	g.join(12, 2, "Iker")
	g.join(13, 3, "Noa")
	g.enemies.clear()
	g.materials = 40
	g.players[11].p = Map.SITES[0].beacon + Vector2(1.5, 0)
	g.act(11, "claim")
	g.players[11].p = Vector2(4.5, 7.0)
	g.act(11, "build", [Data.S_TURRET, g.nav.cell_of(Vector2(4.5, 5.5))])
	g.players[12].coins = 77
	g.players[12].guns[3] = 2
	g.players[12].mag[3] = 10
	g.players[12].res[3] = 50
	g.players[13].med = 3
	g.players[13].xp = 95
	g.pieces[0].state = 2
	g.pieces[0].carrier = 11
	g.wave = 3
	g.start_dawn()
	var data := g.to_save()
	data["mode"] = "host"
	check(Checkpoint.write(data), "Se guarda un punto de control al amanecer")
	var peek := Checkpoint.peek()
	check(peek.wave == 4 and peek.players.size() == 3 and peek.mode == "host", "El menú puede resumir la partida guardada")
	# reconnect in another order, with a newcomer among them
	var h := Game.new()
	h.from_save(Checkpoint.read_any())
	h.join(1, 3, "Noa")
	h.join(2, 1, "Nuevo")
	h.join(3, 0, "Iker")
	h.join(4, 0, "Ana")
	check(h.wave == 4 and h.phase == P.DAWN, "Se continúa en el amanecer de la misma noche")
	check(h.sites[0].claimed and h.structures.has(h.nav.cell_of(Vector2(4.5, 5.5))), "Se conservan territorio y defensas")
	check(h.materials == g.materials, "Se conservan los materiales comunes")
	check(h.players[3].coins == g.players[12].coins and g.players[12].coins >= 77 and h.players[3].guns.get(3, 0) == 2 and h.players[3].res[3] == 50 and h.players[3].role == 2, "Iker recupera fichas, arma mejorada, munición y oficio aunque entre tercero")
	check(h.players[1].med == g.players[13].med and h.players[1].xp == g.players[13].xp and h.players[1].xp >= 95, "Noa recupera botiquines y experiencia")
	check(h.players[2].coins == 6 and h.players[2].role == 1, "Un vecino nuevo empieza de cero")
	check(h.pieces[0].state == 3, "Una pieza que se cargaba queda en el suelo")
	# a crash while writing: the main file is cut short, the previous copy is used
	data.wave = 9
	Checkpoint.write(data)
	var f := FileAccess.open(Checkpoint.PATH, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([1, 2, 3, 4]))
	f = null
	check(Checkpoint.read_any().wave == 4, "Si el guardado quedó a medias se recupera el anterior")
	Checkpoint.clear()
	check(not Checkpoint.exists(), "Al terminar una partida se borra el punto de control")
	if not keep[0].is_empty(): FileAccess.open(Checkpoint.PATH, FileAccess.WRITE).store_buffer(keep[0])
	print("%d fallos" % failed)
	quit(1 if failed else 0)
