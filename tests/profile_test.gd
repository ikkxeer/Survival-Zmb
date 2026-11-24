extends SceneTree
## Progress between matches: ranks, unlocks, versioned save and recovery after an interrupted write.
##   godot --headless -s tests/profile_test.gd
const Profile = preload("res://game/profile.gd")
const Game = preload("res://game/match.gd")
var failed := 0

func check(ok:bool, detail:String):
	if not ok:
		failed += 1
		push_error("FALLO: " + detail)
	else: print("ok  ", detail)

func backup(path:String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func restore(path:String, data:PackedByteArray):
	if data.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else: FileAccess.open(path, FileAccess.WRITE).store_buffer(data)

func _initialize():
	var keep := [backup(Profile.PATH), backup(Profile.PATH + ".bak")]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.PATH + ".bak"))
	var a := Profile.new()
	check(a.rank(1) == 1 and a.unlocked(1).is_empty(), "Un perfil nuevo empieza en rango 1")
	check(a.add_xp(1, 130) and a.rank(1) == 2, "La experiencia de un oficio sube su rango")
	check(a.unlocked(1) == [Profile.UNLOCKS[1][0]], "El rango 2 desbloquea la ventaja del oficio")
	a.add_xp(2, 400)
	a.matches = 3
	a.wins = 1
	check(a.save_file(), "Se guarda el perfil")
	a.add_xp(1, 10)
	check(a.save_file(), "Se vuelve a guardar")
	check(FileAccess.file_exists(Profile.PATH + ".bak") and not FileAccess.file_exists(Profile.PATH + ".tmp"), "Se conserva la copia anterior y no queda el temporal")
	var b := Profile.new()
	check(b.load_file() and b.role_xp[1] == 140 and b.rank(2) == 3 and b.matches == 3 and b.wins == 1, "Se recupera tras cerrar el juego")
	# simulate a crash in the middle of writing: the main file is cut short
	var f := FileAccess.open(Profile.PATH, FileAccess.WRITE)
	f.store_string("[meta]\nversion=1\n[perfil]\nexperiencia=[0, 1")
	f = null
	var c := Profile.new()
	check(c.load_file() and c.role_xp[1] == 130, "Si el archivo quedó a medias se usa la copia anterior")
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 99)
	cfg.set_value("perfil", "experiencia", [1, 1, 1, 1])
	cfg.save(Profile.PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.PATH + ".bak"))
	check(not Profile.new().load_file(), "Un perfil de una versión futura no se aplica")
	# perks in a match
	var g := Game.new()
	var mat := g.materials
	g.join(1, 0, "Ana", 2)
	g.join(2, 1, "Leo", 2)
	g.join(3, 2, "Iker", 3)
	g.join(4, 3, "Noa", 2)
	check(g.materials == mat + 4, "Ingeniera de rango 2: materiales extra para el equipo")
	check(g.players[2].med == 3, "Médico de rango 2: tres botiquines")
	check(g.players[3].guns.has(1) and g.players[3].hpmax == 115.0, "Soldado de rango 3: trabuco y más vida")
	check(g.players[4].coins == 14, "Exploradora de rango 2: fichas extra")
	restore(Profile.PATH, keep[0])
	restore(Profile.PATH + ".bak", keep[1])
	print("%d fallos" % failed)
	quit(1 if failed else 0)
