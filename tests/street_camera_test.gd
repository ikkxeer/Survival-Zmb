extends SceneTree
var failed := false

func check(ok:bool,detail:String):
	if not ok:
		failed = true
		push_error(detail)

func _initialize():
	call_deferred("run")

func run():
	var game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	game.start("solo",0,"")
	var camera = game.camera
	camera.yaw = PI/2
	check(camera.movement(Vector2.UP).is_equal_approx(Vector2.LEFT),"W debe avanzar hacia el fondo de la cámara girada")
	camera.orbit(Vector2(0,400))
	check(camera.elevation <= 0.88,"Límite vertical superior")
	for i in 20: camera.zoom(-1)
	check(is_equal_approx(camera.distance,4.4),"Límite de zoom")
	camera.yaw = PI
	camera.elevation = 0.20
	var pos := Vector3(0,0,3.4)
	camera.follow(pos,game.art.obstacles,1)
	check(camera.position.z>2.46 and camera.boom<2,"La cámara debe detenerse ante la casa")
	camera.yaw = 0
	camera.follow(pos,game.art.obstacles,1)
	check(camera.boom>4,"La cámara debe recuperar la distancia al despejarse")
	var target := Vector3(2.3,0.8,1)
	var screen:Vector2 = camera.unproject_position(target)
	var hit = Plane(Vector3.UP,0.8).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))
	check(hit != null and target.distance_to(hit)<0.002,"El puntero y el plano de tiro coinciden en perspectiva")
	game.stop("")
	check(not camera.tracking,"La cámara vuelve al encuadre del menú")
	quit(1 if failed else 0)
