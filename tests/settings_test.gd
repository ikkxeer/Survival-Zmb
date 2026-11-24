extends SceneTree
## Preferences survive a restart, keys swap instead of clashing and the help shows them.
##   godot --headless -s tests/settings_test.gd
const Settings = preload("res://game/settings.gd")
var failed := 0

func check(ok:bool, detail:String):
	if not ok:
		failed += 1
		push_error("FALLO: " + detail)
	else: print("ok  ", detail)

func _initialize():
	call_deferred("run")

func run():
	var backup := FileAccess.get_file_as_bytes(Settings.PATH) if FileAccess.file_exists(Settings.PATH) else PackedByteArray()
	var a := Settings.new()
	a.values.sensitivity = 1.7
	a.values.sfx = 0.3
	a.values.flashes = false
	var swapped := a.rebind("grenade", KEY_Z)
	check(swapped == "" and a.key_of("grenade") == KEY_Z, "Se reasigna una tecla libre")
	swapped = a.rebind("ping", KEY_Q)
	check(swapped == "ability" and a.key_of("ping") == KEY_Q and a.key_of("ability") == KEY_G, "Una tecla ocupada se intercambia")
	check(a.rebind("map", KEY_ESCAPE) == "" and a.key_of("map") == KEY_M, "Esc no se puede asignar")
	check(a.save_file(), "Se guarda sin dejar archivos a medias")
	check(not FileAccess.file_exists(Settings.PATH + ".tmp"), "No queda el archivo temporal")
	var b := Settings.new()
	check(b.load_file(), "Se cargan al reiniciar")
	check(is_equal_approx(b.values.sensitivity, 1.7) and is_equal_approx(b.values.sfx, 0.3) and b.values.flashes == false, "Se conservan sensibilidad, volumen y destellos")
	check(b.key_of("grenade") == KEY_Z and b.key_of("ping") == KEY_Q, "Se conservan las teclas")
	var cfg := ConfigFile.new()
	cfg.load(Settings.PATH)
	cfg.set_value("meta", "version", 99)
	cfg.save(Settings.PATH)
	check(not Settings.new().load_file(), "Un archivo de una versión futura no se aplica")
	# the in-game help lists the chosen keys
	var game = load("res://game/main.tscn").instantiate()
	game.prefs = b
	root.add_child(game)
	game.prefs = b
	game.ui.prefs = b
	game.ui.sync_settings()
	check(game.ui.help_text.text.contains("Z traca") and game.ui.help_text.text.contains("Q pedir apoyo"), "La ayuda muestra las teclas elegidas")
	game.queue_free()
	if backup.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(backup)
	print("%d fallos" % failed)
	quit(1 if failed else 0)
