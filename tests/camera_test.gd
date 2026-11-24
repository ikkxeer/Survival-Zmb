extends SceneTree
## Camera: movement relative to the orbit, limits, obstacle clearance and pointer accuracy.
##   godot --headless -s tests/camera_test.gd
var failed := 0

func check(ok:bool, detail:String):
	if not ok:
		failed += 1
		push_error("FALLO: " + detail)
	else: print("ok  ", detail)

func _initialize():
	call_deferred("run")

func run():
	var game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	game.start("solo", 0, "", "Prueba")
	var camera = game.camera
	camera.yaw = PI / 2
	check(camera.movement(Vector2.UP).is_equal_approx(Vector2.LEFT), "W avanza hacia el fondo de la cámara girada")
	camera.yaw = 0.0
	check(camera.movement(Vector2.UP).is_equal_approx(Vector2.UP), "Sin giro, W avanza hacia el norte")
	camera.orbit(Vector2(0, 4000))
	check(camera.elevation() <= 1.25, "Límite vertical superior")
	camera.orbit(Vector2(0, -8000))
	check(camera.elevation() >= 0.12, "Límite vertical inferior")
	camera.tilt = 0.0
	for i in 30: camera.zoom(-1)
	check(is_equal_approx(camera.zoom_goal, 0.0), "Límite de acercamiento (tercera persona)")
	for i in 30: camera.zoom(1)
	check(is_equal_approx(camera.zoom_goal, 1.0), "Límite de alejamiento (vista táctica)")
	# third person behind the house: the boom must stop at the wall
	camera.zoom_goal = 0.0
	camera.zoom_t = 0.0
	camera.yaw = 0.0
	camera.tracking = false
	var pos := Vector3(0, 0, -4.5)
	camera.follow(pos, 1.0)
	check(camera.boom < 3.0 and camera.position.z < -3.0, "La cámara se detiene ante la casa (%.2f m)" % camera.boom)
	camera.yaw = PI
	for i in 30: camera.follow(pos, 0.1)
	check(camera.boom > 5.0, "La cámara recupera la distancia al despejarse (%.2f m)" % camera.boom)
	camera.zoom_goal = 1.0
	camera.zoom_t = 1.0
	camera.yaw = 0.0
	camera.tracking = false
	camera.follow(pos, 1.0)
	check(camera.boom > 20.0, "En la vista táctica la casa no empuja la cámara")
	# pointer and firing plane agree in perspective
	camera.zoom_t = 1.0
	camera.zoom_goal = 1.0
	camera.follow(Vector3.ZERO, 1.0)
	var target := Vector3(2.3, 1.0, 1.0)
	var screen:Vector2 = camera.unproject_position(target)
	var hit = camera.aim_point(screen, 1.0)
	check(hit != null and target.distance_to(hit) < 0.01, "El puntero y el plano de tiro coinciden en perspectiva")
	game.stop("")
	check(not camera.tracking and camera.zoom_t == 1.0, "La cámara vuelve al encuadre del menú")
	print("%d fallos" % failed)
	quit(1 if failed else 0)
