extends RefCounted
## Authoritative match simulation. Only the host advances it; clients receive snapshots.
## Positions are X/Z metres stored as Vector2.

const Data = preload("res://game/data.gd")
const Map = preload("res://game/map.gd")
const Nav = preload("res://game/nav.gd")
const P := Data.Phase

const MAX_ENEMIES := 72
const PLAYER_R := 0.36
const BASE_SPEED := 5.0
const EVENT_KEEP := 0.4

var nav := Nav.new()
var rng := RandomNumberGenerator.new()
var time := 0.0
var phase := P.PREP
var wave := 1
var clock := 80.0
var phase_len := 80.0
var core := 300.0
var core_max := 300.0
var core_level := 0
var materials := 14
var players := {}
var enemies := {}
var structures := {}
var sites := []
var loot := []
var projectiles := []
var survivors := []
var community := []
var drops := []
var strikes := []
var events := []
var ev_serial := 0
var serial := 0
var night_event := 0
var weather := 0
var fronts := [2]
var queue := []
var night_total := 0
var spawn_timer := 0.0
var straggler_timer := 20.0
var day_plan := {}
var lightning_timer := 6.0
var vigia_timer := 0.0
var report := []
var stats := {"kills":0, "built":0, "rescued":0, "nights":0}
var buckets := {}

func _init():
	rng.randomize()
	for i in Map.SITES.size(): sites.append({"claimed":false, "hp":0.0, "max":200.0})
	for l in Map.LOOT: loot.append(true)
	for i in Map.SITES.size():
		for g in (3 if i == 5 else 2): spawn_guard(i)
	plan_day()

# ================================================================== helpers
func emit(type:String, data:Array = []):
	ev_serial += 1
	events.append([ev_serial, time, type] + data)

func say(p:Dictionary, msg:String):
	p.notice = msg
	p.nt = 2.6

func announce(msg:String):
	emit("say", [msg])

func claimed_count() -> int:
	var n := 0
	for s in sites: if s.claimed: n += 1
	return n

func has_site(i:int) -> bool:
	return sites[i].claimed

func alive_players() -> Array:
	var list := []
	for id in players:
		if players[id].st == 0: list.append(players[id])
	return list

func in_territory(p:Vector2) -> bool:
	if p.distance_to(Map.BASE_CENTER) <= Map.BASE_BUILD_RADIUS: return true
	for i in sites.size():
		if sites[i].claimed and p.distance_to(Map.SITES[i].beacon) <= Map.SITE_BUILD_RADIUS: return true
	return false

func rect_distance(r:Rect2, p:Vector2) -> float:
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return q.distance_to(p)

func near_shop(p:Vector2) -> bool:
	return p.distance_to(Map.BASE_CENTER) <= Map.SHOP_RADIUS

func role_level_bonus(p:Dictionary) -> float:
	return 1.0 + 0.06 * (p.lvl - 1)

func build_cost(p:Dictionary, kind:int) -> int:
	var cost:int = Data.STRUCTURES[kind].cost
	if p.role == 0: cost = maxi(1, roundi(cost * 0.75))
	if has_site(0): cost = maxi(1, cost - 1)
	return cost

func max_reserve(p:Dictionary, gun:int) -> int:
	var r:int = Data.WEAPONS[gun].reserve
	if r < 0: return -1
	return int(r * (1.5 if p.role == 2 else 1.0))

func powered(cell:int) -> bool:
	if night_event != 1 or phase != P.NIGHT or has_site(4): return true
	var c := nav.center(cell)
	for k in structures:
		if structures[k].k == Data.S_GEN and nav.center(k).distance_to(c) <= 9.0: return true
	return false

func near_generator(cell:int) -> bool:
	var c := nav.center(cell)
	for k in structures:
		if structures[k].k == Data.S_GEN and nav.center(k).distance_to(c) <= 9.0: return true
	return false

func player_speed(p:Dictionary) -> float:
	## Shared by the host validation and client prediction.
	var s := BASE_SPEED * float(Data.ROLES[p.role].speed)
	if p.role == 3: s *= 1.0 + 0.03 * (p.lvl - 1)
	if p.role == 3 and p.buff > 0: s *= 1.45
	if p.st == 1: s = 0.9
	return s

# ================================================================== players
func join(id:int, role:int, name:String = "") -> bool:
	if players.has(id) or players.size() >= 4 or phase == P.OVER: return false
	role = clampi(role, 0, 3)
	var idx := players.size()
	var p := {
		"name": name.strip_edges().left(14) if name.strip_edges() != "" else "Vecino %d" % (idx + 1),
		"role": role, "slot": idx, "p": Map.PLAYER_SPAWN + Vector2(idx * 1.2 - 1.8, 0), "aim": Vector2(0, 1),
		"hp": 100.0, "hpmax": 100.0, "st": 0, "bleed": 30.0, "coins": 6, "xp": 0, "lvl": 1,
		"gun": 0, "guns": {0:1}, "mag": {0:12}, "res": {0:-1}, "cool": 0.0, "rl": 0.0, "rlmax": 0.0,
		"fire": false, "use": false, "roll": false, "ab": 0.0, "buff": 0.0, "med": 2 if role == 1 else 1,
		"tr": 2, "kills": 0, "notice": "", "nt": 0.0, "hold": "", "ht": 0.0, "hm": 0.0, "hkey": "",
		"prompt": "", "ready": false, "melee": 0.0, "heal": 0.0, "acc": 0.0, "last": time, "fix": 0,
		"ping": 0.0, "dmg": 0.0, "flame": 0.0, "cursor": Vector2.ZERO,
	}
	players[id] = p
	emit("join", [id])
	announce("%s se une como %s" % [p.name, Data.ROLES[role].name])
	return true

func leave(id:int):
	if players.erase(id): emit("leave", [id])

func drive(id:int, pos:Vector2, aim:Vector2, buttons:int):
	if not players.has(id) or not pos.is_finite() or not aim.is_finite(): return
	var p:Dictionary = players[id]
	if aim.length_squared() > 0.0001: p.aim = aim.normalized()
	p.cursor = p.p + aim
	p.fire = buttons & 1 != 0
	p.use = buttons & 2 != 0
	p.roll = buttons & 4 != 0 and p.st == 0
	if p.st == 2: return
	var elapsed := maxf(time - p.last, 0.016)
	var allowed := 12.5 * elapsed + 0.6
	pos = pos.clamp(Map.BOUNDS.position, Map.BOUNDS.end)
	if pos.distance_to(p.p) <= allowed and nav.blocked_cell(pos, PLAYER_R * 0.6, 0) == -1:
		p.p = pos
	else:
		p.fix += 1
	p.last = time

func hurt_player(p:Dictionary, dmg:float, _src:Vector2 = Vector2.ZERO):
	if p.st != 0 or p.roll: return
	if p.role == 3 and p.buff > 0: dmg *= 0.5
	p.hp -= dmg
	p.dmg = 0.35
	if p.hp <= 0:
		p.hp = 0.0
		p.st = 1
		p.bleed = 30.0
		p.rl = 0.0
		emit("down", [p.p.x, p.p.y])
		announce("%s ha caído. ¡Levantadlo con E!" % p.name)

func revive(p:Dictionary, hp:float):
	if p.st == 0: return
	p.st = 0
	p.hp = hp
	emit("revive", [p.p.x, p.p.y])

func give_xp(p:Dictionary, amount:int):
	var before:int = p.lvl
	p.xp += amount
	p.lvl = Data.level_for(p.xp)
	if p.lvl > before:
		p.hpmax = 100.0 + 8.0 * (p.lvl - 1)
		p.hp = minf(p.hpmax, p.hp + 25)
		emit("level", [p.p.x, p.p.y, p.lvl])
		say(p, "¡Nivel %d! Tu oficio mejora." % p.lvl)

# ================================================================== actions
func act(id:int, action:String, args:Array = []):
	if not players.has(id) or phase == P.OVER: return
	var p:Dictionary = players[id]
	if action == "ready":
		p.ready = not p.ready
		return
	if action == "ping" and args.size() > 0 and args[0] is Vector2 and p.ping <= 0:
		p.ping = 0.6
		emit("ping", [args[0].x, args[0].y, id])
		return
	if action == "medkit" and p.st == 1:
		if p.med <= 0: return say(p, "No te quedan botiquines")
		p.med -= 1
		revive(p, 45.0)
		return
	if p.st != 0: return
	match action:
		"reload": start_reload(p)
		"switch":
			var g := int(args[0]) if args.size() > 0 else 0
			if p.guns.has(g) and g != p.gun:
				p.gun = g
				p.rl = 0.0
				p.cool = 0.25
		"melee": melee(id, p)
		"grenade":
			if args.size() > 0 and args[0] is Vector2: throw_grenade(id, p, args[0])
		"ability": ability(id, p)
		"medkit":
			if p.med <= 0: return say(p, "No te quedan botiquines")
			if p.hp >= p.hpmax: return say(p, "Ya estás en plena forma")
			p.med -= 1
			p.heal = 2.0
			emit("heal", [p.p.x, p.p.y])
		"build":
			if args.size() >= 2: build(id, p, int(args[0]), int(args[1]))
		"upgrade":
			if args.size() >= 1: upgrade(id, p, int(args[0]))
		"demolish":
			if args.size() >= 1: demolish(p, int(args[0]))
		"claim": claim(p)
		"buy_gun":
			if args.size() >= 1: buy_gun(p, int(args[0]))
		"up_gun":
			if args.size() >= 1: up_gun(p, int(args[0]))
		"ammo":
			if args.size() >= 1: buy_ammo(p, int(args[0]))
		"buy_medkit":
			if not near_shop(p.p): return say(p, "La tienda está en la casa")
			if p.med >= 3: return say(p, "Llevas el máximo de botiquines")
			if p.coins < Data.MEDKIT.price: return say(p, "Faltan fichas")
			p.coins -= Data.MEDKIT.price
			p.med += 1
			emit("buy", [id])
		"buy_traca":
			if not near_shop(p.p): return say(p, "La tienda está en la casa")
			if p.tr >= 6: return say(p, "Llevas el máximo de tracas")
			if p.coins < Data.GRENADE.price: return say(p, "Faltan fichas")
			p.coins -= Data.GRENADE.price
			p.tr += 1
			emit("buy", [id])
		"core_up": core_upgrade(p)

func start_reload(p:Dictionary):
	var w:Dictionary = Data.WEAPONS[p.gun]
	if p.rl > 0 or p.mag[p.gun] >= w.mag: return
	if p.res[p.gun] == 0: return say(p, "Sin munición: cómprala en la tienda")
	p.rlmax = w.reload * (0.7 if p.role == 2 else 1.0)
	p.rl = p.rlmax
	emit("reload", [p.p.x, p.p.y])

func finish_reload(p:Dictionary):
	var w:Dictionary = Data.WEAPONS[p.gun]
	var need:int = w.mag - p.mag[p.gun]
	if p.res[p.gun] < 0:
		p.mag[p.gun] = w.mag
	else:
		var take := mini(need, p.res[p.gun])
		p.mag[p.gun] += take
		p.res[p.gun] -= take

func build(id:int, p:Dictionary, kind:int, cell:int):
	if kind < 0 or kind >= Data.STRUCTURES.size(): return
	var c := nav.center(cell)
	if cell < 0 or not nav.is_free_for_build(cell): return say(p, "Ahí no se puede construir")
	if not in_territory(c): return say(p, "Solo puedes construir en tu territorio")
	if p.p.distance_to(c) > 9.5: return say(p, "Acércate más para construir")
	if Map.BASE.grow(0.01).has_point(c): return say(p, "Ahí no se puede construir")
	for q in players.values():
		if q.st != 2 and rect_distance(Rect2(c - Vector2(0.5,0.5), Vector2.ONE), q.p) < PLAYER_R and Data.STRUCTURES[kind].block and not Data.STRUCTURES[kind].vault:
			return say(p, "Hay alguien en medio")
	for e in enemies.values():
		if rect_distance(Rect2(c - Vector2(0.5,0.5), Vector2.ONE), e.p) < e.r:
			return say(p, "Hay un brotado en medio")
	var cost := build_cost(p, kind)
	if materials < cost: return say(p, "Faltan materiales (%d)" % cost)
	materials -= cost
	var def:Dictionary = Data.STRUCTURES[kind]
	var hp:float = def.hp[0] * (1.2 if p.role == 0 else 1.0)
	structures[cell] = {"k":kind, "lvl":0, "hp":hp, "max":hp, "cool":0.0, "owner":id, "aim":0.0, "on":true}
	nav.set_structure(cell, kind, hp)
	stats.built += 1
	give_xp(p, 2)
	emit("build", [cell, kind])

func upgrade(_id:int, p:Dictionary, cell:int):
	if not structures.has(cell): return say(p, "No hay nada que mejorar")
	var s:Dictionary = structures[cell]
	var def:Dictionary = Data.STRUCTURES[s.k]
	if p.p.distance_to(nav.center(cell)) > 9.5: return say(p, "Acércate más")
	if s.lvl >= def.hp.size() - 1: return say(p, "%s ya está al máximo" % def.name)
	var cost:int = def.up[s.lvl]
	if p.role == 0: cost = maxi(1, roundi(cost * 0.75))
	if materials < cost: return say(p, "Faltan materiales (%d)" % cost)
	materials -= cost
	s.lvl += 1
	s.max = def.hp[s.lvl] * (1.2 if p.role == 0 else 1.0)
	s.hp = s.max
	nav.set_structure(cell, s.k, s.hp)
	nav.mark_all_dirty()
	give_xp(p, 2)
	emit("upgrade", [cell, s.k, s.lvl])

func demolish(p:Dictionary, cell:int):
	if not structures.has(cell): return
	if p.p.distance_to(nav.center(cell)) > 9.5: return say(p, "Acércate más")
	var s:Dictionary = structures[cell]
	var refund := int(Data.STRUCTURES[s.k].cost * 0.5 * s.hp / s.max)
	materials += refund
	remove_structure(cell, false)
	say(p, "Desmontado: +%d materiales" % refund)

func remove_structure(cell:int, broken:bool):
	if not structures.has(cell): return
	var k:int = structures[cell].k
	structures.erase(cell)
	nav.clear_structure(cell)
	emit("break" if broken else "remove", [cell, k])

func claim(p:Dictionary):
	var site := -1
	for i in Map.SITES.size():
		if p.p.distance_to(Map.SITES[i].beacon) < 3.2: site = i
	if site < 0: return say(p, "Acércate al estandarte de una propiedad")
	if sites[site].claimed: return say(p, "%s ya es del barrio" % Data.SITES[site].name)
	if phase == P.NIGHT: return say(p, "Conquista las propiedades de día")
	for e in enemies.values():
		if e.p.distance_to(Map.SITES[site].beacon) < 10.0: return say(p, "Quedan brotados cerca. Despeja la zona")
	var cost := claim_cost()
	if materials < cost: return say(p, "Necesitas %d materiales" % cost)
	materials -= cost
	sites[site].claimed = true
	sites[site].hp = sites[site].max
	nav.active["site%d" % site] = true
	give_xp(p, 15)
	emit("claim", [site])
	announce("%s se une al barrio: %s" % [Data.SITES[site].name, Data.SITES[site].bonus])

func claim_cost() -> int:
	return 6 + 4 * claimed_count()

func buy_gun(p:Dictionary, g:int):
	if g < 0 or g >= Data.WEAPONS.size(): return
	if not near_shop(p.p): return say(p, "La tienda está en la casa")
	if p.guns.has(g): return act_switch(p, g)
	var w:Dictionary = Data.WEAPONS[g]
	if w.req >= 0 and not has_site(w.req): return say(p, "Necesitas conquistar %s" % Data.SITES[w.req].name)
	if p.coins < w.price: return say(p, "Faltan fichas (%d)" % w.price)
	p.coins -= w.price
	p.guns[g] = 1
	p.mag[g] = w.mag
	p.res[g] = max_reserve(p, g) / 2 if w.reserve > 0 else -1
	p.gun = g
	p.rl = 0.0
	emit("buy", [p.p.x, p.p.y])
	say(p, "%s comprado" % w.name)

func act_switch(p:Dictionary, g:int):
	p.gun = g
	p.rl = 0.0

func up_gun(p:Dictionary, g:int):
	if not near_shop(p.p): return say(p, "La tienda está en la casa")
	if not p.guns.has(g): return say(p, "Primero compra el arma")
	var lvl:int = p.guns[g]
	if lvl >= 3: return say(p, "Ya está al máximo")
	var cost:int = Data.WEAPONS[g].up[lvl - 1]
	if p.coins < cost: return say(p, "Faltan fichas (%d)" % cost)
	p.coins -= cost
	p.guns[g] = lvl + 1
	emit("buy", [p.p.x, p.p.y])
	say(p, "%s mejorado a nivel %d" % [Data.WEAPONS[g].name, lvl + 1])

func buy_ammo(p:Dictionary, g:int):
	if not near_shop(p.p): return say(p, "La tienda está en la casa")
	if not p.guns.has(g) or p.res[g] < 0: return
	var top := max_reserve(p, g)
	if p.res[g] >= top: return say(p, "Munición completa")
	var price:int = Data.WEAPONS[g].ammo_price
	if p.coins < price: return say(p, "Faltan fichas (%d)" % price)
	p.coins -= price
	p.res[g] = top
	emit("buy", [p.p.x, p.p.y])

func core_upgrade(p:Dictionary):
	if not near_shop(p.p): return say(p, "Hazlo desde la casa")
	if core_level >= 3: return say(p, "La casa ya está reforzada al máximo")
	var m:int = Data.CORE_UPGRADE.mat[core_level]
	var c:int = Data.CORE_UPGRADE.coins[core_level]
	if materials < m or p.coins < c: return say(p, "Necesitas %d materiales y %d fichas" % [m, c])
	materials -= m
	p.coins -= c
	core_level += 1
	core_max += Data.CORE_UPGRADE.hp
	core = minf(core_max, core + Data.CORE_UPGRADE.hp * 2)
	emit("core_up", [core_level])
	announce("%s refuerza la casa (nivel %d)" % [p.name, core_level])

func ability(id:int, p:Dictionary):
	if p.ab > 0: return say(p, "Habilidad lista en %ds" % ceili(p.ab))
	var cd:float = Data.ROLES[p.role].cd * (1.0 - 0.06 * (p.lvl - 1))
	p.ab = cd
	emit("ability", [p.p.x, p.p.y, p.role, id])
	match p.role:
		0:
			var fixed := 0
			for cell in structures:
				var s:Dictionary = structures[cell]
				if nav.center(cell).distance_to(p.p) <= 7.0 and s.hp < s.max:
					s.hp = minf(s.max, s.hp + s.max * 0.45)
					fixed += 1
			for i in sites.size():
				if sites[i].claimed and Map.SITES[i].beacon.distance_to(p.p) <= 7.0:
					sites[i].hp = minf(sites[i].max, sites[i].hp + 60)
			if rect_distance(Map.BASE, p.p) <= 7.0: core = minf(core_max, core + 40)
			say(p, "Remiendo exprés: %d defensas" % fixed)
		1:
			for q in players.values():
				if q.p.distance_to(p.p) > 7.0: continue
				if q.st == 1: revive(q, 45.0)
				elif q.st == 0: q.hp = minf(q.hpmax, q.hp + 45)
			give_xp(p, 4)
		2:
			p.buff = 6.0
		3:
			p.buff = 5.0

func melee(id:int, p:Dictionary):
	if p.melee > 0: return
	p.melee = Data.MELEE.rate
	emit("melee", [p.p.x, p.p.y, p.aim.x, p.aim.y, id])
	var dmg:float = Data.MELEE.dmg * Data.ROLES[p.role].damage
	for key in enemies.keys():
		if not enemies.has(key): continue
		var e:Dictionary = enemies[key]
		var rel:Vector2 = e.p - p.p
		var d := rel.length()
		if d > Data.MELEE.range + e.r: continue
		if d > 0.3 and absf(p.aim.angle_to(rel)) > Data.MELEE.arc * 0.5: continue
		damage_enemy(key, dmg, id, rel.normalized(), Data.MELEE.knock, true)

func throw_grenade(id:int, p:Dictionary, target:Vector2):
	if p.tr <= 0: return say(p, "No te quedan tracas")
	p.tr -= 1
	var to := target
	if to.distance_to(p.p) > Data.GRENADE.range: to = p.p + (to - p.p).normalized() * Data.GRENADE.range
	projectiles.append({"from":p.p, "to":to, "t":0.0, "dur":0.8, "kind":1, "dmg":Data.GRENADE.dmg, "r":Data.GRENADE.radius, "owner":id, "h":2.2})
	emit("throw", [p.p.x, p.p.y])

# ================================================================== combat
func fire(id:int, p:Dictionary):
	var w:Dictionary = Data.WEAPONS[p.gun]
	var lvl:int = p.guns[p.gun]
	var frenzy:bool = p.role == 2 and p.buff > 0
	if p.mag[p.gun] <= 0 and not frenzy:
		start_reload(p)
		return
	p.cool = w.rate * (0.6 if frenzy else 1.0)
	if not frenzy: p.mag[p.gun] -= 1
	var dmg:float = w.dmg * (1.0 + 0.25 * (lvl - 1)) * Data.ROLES[p.role].damage
	if p.role == 2: dmg *= role_level_bonus(p)
	var origin:Vector2 = p.p + p.aim * 0.55
	match w.kind:
		"hit":
			var pellets:int = w.pellets
			for i in pellets:
				var off := 0.0
				if pellets > 1: off = (float(i) / (pellets - 1) - 0.5) * w.spread + rng.randf_range(-0.04, 0.04)
				else: off = rng.randf_range(-0.5, 0.5) * w.spread
				hitscan(id, origin, p.aim.rotated(off), w.range, dmg, w.pierce, w.knock, p.gun)
		"lob":
			var to:Vector2 = p.p + p.aim * w.range
			var tgt:Vector2 = p.get("cursor", to)
			if tgt.distance_to(p.p) < w.range: to = tgt
			projectiles.append({"from":origin, "to":to, "t":0.0, "dur":0.55, "kind":2, "dmg":dmg, "r":2.6, "owner":id, "h":1.6})
			emit("shot", [id, p.gun, origin.x, origin.y, to.x, to.y])
		"flame":
			var reach:float = w.range
			for key in enemies.keys():
				if not enemies.has(key): continue
				var e:Dictionary = enemies[key]
				var rel:Vector2 = e.p - origin
				if rel.length() > reach + e.r or absf(p.aim.angle_to(rel)) > w.spread * 0.5: continue
				e.burn = 2.5
				e.burner = id
				damage_enemy(key, dmg, id, rel.normalized(), w.knock, false)
			p.flame -= w.rate
			if p.flame <= 0:
				p.flame = 0.12
				emit("flame", [id, origin.x, origin.y, p.aim.x, p.aim.y])

func hitscan(owner:int, origin:Vector2, dir:Vector2, reach:float, dmg:float, pierce:int, knock:float, gun:int):
	var length := nav.ray(origin, dir, reach)
	var hits := []
	for key in enemies:
		var e:Dictionary = enemies[key]
		var rel:Vector2 = e.p - origin
		var along := rel.dot(dir)
		if along < -e.r or along > length + e.r: continue
		if absf(rel.cross(dir)) < e.r + 0.18: hits.append([along, key])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	var end := origin + dir * length
	for i in mini(hits.size(), pierce + 1):
		damage_enemy(hits[i][1], dmg * (1.0 - 0.15 * i), owner, dir, knock, true)
		if i == pierce: end = origin + dir * maxf(0.2, hits[i][0])
	emit("shot", [owner, gun, origin.x, origin.y, end.x, end.y])

func damage_enemy(key:int, dmg:float, owner:int, dir:Vector2 = Vector2.ZERO, knock:float = 0.0, can_crit:bool = false):
	if not enemies.has(key): return
	var e:Dictionary = enemies[key]
	var crit := can_crit and owner > 0 and rng.randf() < 0.08
	if crit: dmg *= 2.0
	if e.lit: dmg *= 1.25
	e.hp -= dmg
	e.flash = 0.12
	if e.state == 2: wake(e)
	if owner > 0 and players.has(owner) and e.victim < 0 and e.k != Data.BOSS:
		if players[owner].p.distance_to(e.p) < 14.0: e.victim = owner
	if knock > 0 and e.k != Data.BOSS:
		var mass := 2.5 if e.k == 2 else 1.0
		e.kv += dir * knock * 6.0 / mass
		e.stun = maxf(e.stun, 0.08 * knock)
	emit("hit", [e.p.x, e.p.y, int(round(dmg)), 1 if crit else 0, key])
	if e.hp <= 0: kill_enemy(key, owner)

func kill_enemy(key:int, owner:int):
	if not enemies.has(key): return
	var e:Dictionary = enemies[key]
	enemies.erase(key)
	var def:Dictionary = Data.ENEMIES[e.k]
	stats.kills += 1
	emit("kill", [e.p.x, e.p.y, e.k, owner])
	var coins:int = def.coins
	if night_event == 5 and phase == P.NIGHT: coins = ceili(coins * 1.5)
	var credit := owner
	if owner <= 0 and owner != -9 and structures.has(-owner - 100): credit = structures[-owner - 100].owner
	if players.has(credit):
		players[credit].coins += coins
		players[credit].kills += 1
		give_xp(players[credit], def.xp)
	if e.k == Data.BOOMER: explode(e.p, 2.6, 45.0, -9, true, 2.2)
	if e.k == Data.BOSS:
		for q in players.values():
			q.coins += 15
			give_xp(q, 30)
		materials += 12
		announce("¡El Gigantón ha caído! +15 fichas para todos")

func wake(e:Dictionary):
	e.state = 0
	e.guard_alert = 6.0

func explode(at:Vector2, radius:float, dmg:float, owner:int, hostile:bool, struct_mult:float):
	emit("boom", [at.x, at.y, radius])
	for key in enemies.keys():
		if not enemies.has(key): continue
		var e:Dictionary = enemies[key]
		var d:float = e.p.distance_to(at)
		if d > radius + e.r: continue
		var f := 1.0 - 0.5 * clampf(d / radius, 0, 1)
		damage_enemy(key, dmg * f * (1.1 if hostile else 1.0), owner, (e.p - at).normalized(), 1.5, false)
	if not hostile: return
	for p in players.values():
		var d:float = p.p.distance_to(at)
		if d < radius: hurt_player(p, dmg * 0.8 * (1.0 - 0.5 * d / radius), at)
	for cell in structures.keys():
		var c := nav.center(cell)
		if c.distance_to(at) < radius + 0.5: damage_structure(cell, dmg * struct_mult)
	for i in sites.size():
		if sites[i].claimed and Map.SITES[i].beacon.distance_to(at) < radius + 0.5: damage_site(i, dmg * struct_mult)
	if rect_distance(Map.BASE, at) < radius: damage_core(dmg * struct_mult * 0.6)
	for s in survivors:
		if s.state == 1 and s.p.distance_to(at) < radius: s.hp -= dmg

func damage_structure(cell:int, dmg:float):
	if not structures.has(cell): return
	var s:Dictionary = structures[cell]
	s.hp -= dmg
	emit("sdmg", [cell])
	if s.k == Data.S_MINE:
		trigger_mine(cell)
		return
	if s.hp <= 0: remove_structure(cell, true)
	else: nav.shp[cell] = s.hp

func trigger_mine(cell:int):
	if not structures.has(cell): return
	var s:Dictionary = structures[cell]
	remove_structure(cell, true)
	explode(nav.center(cell), 2.5, 115.0, s.owner, false, 0.0)

func damage_core(dmg:float):
	core = maxf(0.0, core - dmg)
	emit("core_hit", [])

func damage_site(i:int, dmg:float):
	if not sites[i].claimed: return
	sites[i].hp -= dmg
	if sites[i].hp <= 0:
		sites[i].claimed = false
		sites[i].hp = 0.0
		nav.active.erase("site%d" % i)
		emit("lost", [i])
		announce("¡Hemos perdido %s!" % Data.SITES[i].name)

# ================================================================== spawning
func new_enemy(kind:int, at:Vector2, goal:String, night:bool) -> Dictionary:
	serial += 1
	var def:Dictionary = Data.ENEMIES[kind]
	var hp:float = def.hp * (1.0 + 0.06 * (wave - 1))
	if kind == Data.BOSS: hp = def.hp + 600.0 * maxi(0, players.size() - 1) + 400.0 * (wave / 5 - 1)
	var e := {"k":kind, "p":at, "hp":hp, "max":hp, "r":def.r, "goal":goal, "mode":1 if kind in [Data.BREAKER, Data.CLIMBER] else 0,
		"cd":rng.randf_range(0.2, 1.0), "wind":0.0, "target":null, "state":0, "stun":0.0, "burn":0.0, "burner":-1,
		"kv":Vector2.ZERO, "night":night, "victim":-1, "retarget":rng.randf(), "face":Vector2.ZERO, "flash":0.0,
		"lit":false, "climb":false, "fuse":0.0, "home":at, "guard":false, "guard_alert":0.0, "summon":8.0, "slam":0.0,
		"atk":0.0, "surv":null, "stuck":0.0, "speed":def.speed * rng.randf_range(0.92, 1.08)}
	enemies[serial] = e
	return e

func spawn_guard(site:int):
	var b:Vector2 = Map.SITES[site].beacon
	for tries in 12:
		var at := b + Vector2(rng.randf_range(-3.5, 3.5), rng.randf_range(-3.5, 3.5))
		if nav.blocked_cell(at, 0.4, 1) == -1:
			var e := new_enemy(0 if rng.randf() < 0.75 else 1, at, "base", false)
			e.state = 2
			e.guard = true
			e.home = at
			return

func front_point(front:int) -> Vector2:
	var pts:Array = Map.FRONTS[front]
	var base:Vector2 = pts[rng.randi_range(0, pts.size() - 1)]
	var side := Vector2(base.y, base.x).normalized() if absf(base.x) > absf(base.y) else Vector2(1, 0)
	return base + side * rng.randf_range(-1.4, 1.4)

func pick_goal() -> String:
	var owned := []
	for i in sites.size():
		if sites[i].claimed: owned.append(i)
	if owned.size() > 0 and rng.randf() < 0.18 + 0.05 * owned.size():
		return "site%d" % owned[rng.randi_range(0, owned.size() - 1)]
	return "base"

# ================================================================== phases
func plan_day():
	## Decide what the coming day and night look like so players can prepare.
	var n := clampi(1 + wave / 2, 1, 4)
	var all := [0, 1, 2, 3]
	all.shuffle()
	fronts = all.slice(0, n)
	if wave == 1: fronts = [2]
	weather = 0 if rng.randf() < 0.55 else (1 if rng.randf() < 0.6 else 2)
	if wave == 1: weather = 0
	night_event = pick_event()
	day_plan = {
		"survivor": rng.randf_range(0.25, 0.6) if (wave >= 2 and rng.randf() < 0.6) or wave == 1 else -1.0,
		"drop": rng.randf_range(0.3, 0.75) if rng.randf() < 0.55 and wave > 1 else -1.0,
		"horde": rng.randf_range(0.2, 0.7) if wave >= 3 and rng.randf() < 0.35 else -1.0,
	}

func pick_event() -> int:
	if wave == 1: return 0
	if wave % 5 == 0: return 6
	var options := [0, 0]
	for i in range(1, 6):
		if Data.NIGHT_EVENTS[i].from <= wave: options.append(i)
	return options[rng.randi_range(0, options.size() - 1)]

func start_night():
	phase = P.NIGHT
	clock = 0.0
	for p in players.values(): p.ready = false
	var count := 6 + wave * 3 + maxi(0, players.size() - 1) * 4 + claimed_count() * 2
	if night_event == 2: count = int(count * 1.35)
	queue.clear()
	var weights := {0:10.0}
	if wave >= 2: weights[1] = 3.0 + wave * 0.5
	if wave >= 3:
		weights[2] = 1.4 + wave * 0.2
		weights[3] = 1.5 + wave * 0.25
	if wave >= 4:
		weights[4] = 2.0
		weights[5] = 1.6
	if wave >= 5: weights[6] = 1.6
	if night_event == 2 and weights.has(1): weights[1] *= 4.0
	if night_event == 3: weights[4] = weights.get(4, 1.0) * 3.0 + 2.0
	var total := 0.0
	for k in weights: total += weights[k]
	for i in count:
		var r := rng.randf() * total
		for k in weights:
			r -= weights[k]
			if r <= 0:
				queue.append(k)
				break
	if night_event == 6:
		queue.insert(mini(4, queue.size()), Data.BOSS)
	night_total = queue.size()
	spawn_timer = 2.0
	lightning_timer = 5.0
	stats.nights += 1
	emit("night", [wave, night_event])

func spawn_tick(dt:float):
	spawn_timer -= dt
	if queue.is_empty() or spawn_timer > 0: return
	var active := 0
	for e in enemies.values(): if e.night: active += 1
	if enemies.size() >= MAX_ENEMIES: return
	var group := mini(queue.size(), rng.randi_range(3, 5 + wave / 3))
	var front:int = fronts[rng.randi_range(0, fronts.size() - 1)]
	for i in group:
		var kind:int = queue.pop_front()
		var e := new_enemy(kind, front_point(front), pick_goal(), true)
		if kind == Data.BOSS:
			e.goal = "base"
			announce("¡Un Gigantón avanza por el %s!" % Map.FRONT_NAMES[front])
	spawn_timer = maxf(2.2, 5.5 - wave * 0.2) * (0.6 if night_event == 2 else 1.0) + active * 0.04

func start_dawn():
	phase = P.DAWN
	clock = 14.0
	phase_len = 14.0
	wave += 1
	report = []
	var gain_mat := 5
	var gain_coin := 5 + wave
	if has_site(3):
		gain_mat += 8
		report.append("Almacén: +8 materiales")
	if has_site(4): gain_mat += 3
	var carp := community.count(0)
	if carp > 0:
		gain_mat += 3 * carp
		report.append("Carpinteros: +%d materiales" % (3 * carp))
	materials += gain_mat
	if has_site(0):
		core = minf(core_max, core + 40)
		report.append("Taller: casa reparada")
	for p in players.values():
		if p.st == 2:
			p.st = 0
			p.hp = 60.0
			p.p = Map.PLAYER_SPAWN
			p.coins = int(p.coins * 0.7)
		elif p.st == 1: revive(p, 40.0)
		p.coins += gain_coin + (6 if has_site(2) else 0)
		p.hp = minf(p.hpmax, p.hp + (p.hpmax * 0.5 if has_site(1) else 20.0))
		if has_site(1): p.med = mini(3, p.med + 1)
		if has_site(5):
			p.tr = mini(6, p.tr + 1)
			for g in p.guns: if p.res[g] >= 0: p.res[g] = max_reserve(p, g)
		give_xp(p, 10)
	if has_site(2): report.append("Economato: +6 fichas")
	if has_site(1): report.append("Dispensario: curas y botiquines")
	if has_site(5): report.append("Comisaría: munición y tracas")
	report.push_front("+%d materiales · +%d fichas" % [gain_mat, gain_coin])
	for i in loot.size():
		if not loot[i] and rng.randf() < 0.85: loot[i] = true
	for i in sites.size():
		if sites[i].claimed:
			sites[i].hp = sites[i].max
			continue
		var guards := 0
		for e in enemies.values(): if e.guard and e.home.distance_to(Map.SITES[i].beacon) < 6: guards += 1
		for g in range(guards, mini(4, 2 + wave / 4)): spawn_guard(i)
	emit("dawn", [wave])
	plan_day()

func start_prep():
	phase = P.PREP
	phase_len = 65.0
	clock = phase_len
	straggler_timer = 18.0

func time_of_day() -> float:
	match phase:
		P.PREP: return lerpf(0.76, 0.30, clock / phase_len)
		P.NIGHT:
			var done := 1.0 - float(queue.size() + night_alive()) / maxf(1.0, night_total)
			return fmod(0.80 + 0.32 * clampf(done, 0, 1), 1.0)
		P.DAWN: return lerpf(0.29, 0.13, clock / phase_len)
	return 0.9

func night_alive() -> int:
	var n := 0
	for e in enemies.values(): if e.night: n += 1
	return n

# ================================================================== tick
func tick(dt:float):
	if phase == P.OVER or players.is_empty(): return
	time += dt
	while events.size() > 0 and events[0][1] < time - EVENT_KEEP: events.pop_front()
	nav.update_one(dt)
	tick_players(dt)
	tick_phase(dt)
	if phase == P.OVER: return
	build_buckets()
	tick_structures(dt)
	tick_enemies(dt)
	tick_projectiles(dt)
	tick_world(dt)
	check_end()

func tick_phase(dt:float):
	match phase:
		P.PREP:
			clock -= dt
			var everyone := true
			for p in players.values(): if p.st == 0 and not p.ready: everyone = false
			if everyone and clock > 4.0:
				clock = 4.0
				announce("Todo el equipo está listo")
			var progress := 1.0 - clock / phase_len
			for key in ["survivor", "drop", "horde"]:
				if day_plan.get(key, -1.0) >= 0 and progress >= day_plan[key]:
					day_plan[key] = -1.0
					call("event_" + key)
			straggler_timer -= dt
			if straggler_timer <= 0 and wave > 1:
				straggler_timer = rng.randf_range(12, 20)
				var day := 0
				for e in enemies.values(): if not e.night and not e.guard: day += 1
				if day < 2 + wave / 2:
					new_enemy(0, front_point(rng.randi_range(0, 3)), "base", false)
			if clock <= 0: start_night()
		P.NIGHT:
			spawn_tick(dt)
			if queue.is_empty() and night_alive() == 0: start_dawn()
		P.DAWN:
			clock -= dt
			if clock <= 0: start_prep()

func check_end():
	if core <= 0:
		end_game("La casa de la verbena ha caído")
		return
	for p in players.values():
		if p.st == 0 or (p.st == 1 and p.med > 0): return
	end_game("Todo el equipo ha caído")

func end_game(reason:String):
	phase = P.OVER
	report = [reason]
	emit("over", [wave])

func tick_players(dt:float):
	for id in players:
		var p:Dictionary = players[id]
		p.nt = maxf(0, p.nt - dt)
		p.ping = maxf(0, p.ping - dt)
		p.dmg = maxf(0, p.dmg - dt)
		p.ab = maxf(0, p.ab - dt)
		p.buff = maxf(0, p.buff - dt)
		p.melee = maxf(0, p.melee - dt)
		p.cool -= dt
		if p.st == 1:
			p.bleed -= dt
			p.prompt = "Has caído. Espera a un compañero%s" % (" o pulsa H para usar un botiquín" if p.med > 0 else "")
			if p.bleed <= 0:
				p.st = 2
				emit("dead", [p.p.x, p.p.y])
				announce("%s no ha aguantado. Volverá al amanecer" % p.name)
			continue
		if p.st == 2:
			p.prompt = "Volverás al amanecer"
			continue
		if p.heal > 0:
			p.heal -= dt
			p.hp = minf(p.hpmax, p.hp + Data.MEDKIT.heal / 2.0 * dt)
		if community.has(1) and p.p.distance_to(Map.BASE_CENTER) < 9.0:
			p.hp = minf(p.hpmax, p.hp + 2.0 * community.count(1) * dt)
		if p.rl > 0:
			p.rl -= dt
			if p.rl <= 0: finish_reload(p)
		elif p.fire and p.cool <= 0:
			fire(id, p)
		interact(id, p, dt)

# ------------------------------------------------------------------ hold-to-use interactions
func interact(id:int, p:Dictionary, dt:float):
	var target := find_use_target(id, p)
	p.prompt = target.get("prompt", "")
	if not p.use or target.is_empty():
		p.hold = ""
		p.ht = 0.0
		p.hkey = ""
		return
	if p.hkey != target.key:
		p.hkey = target.key
		p.ht = 0.0
	p.hold = target.label
	p.hm = target.get("time", 0.0)
	p.ht += dt
	match target.type:
		"revive":
			if p.ht >= p.hm:
				revive(target.mate, 60.0 if p.role == 1 else 35.0)
				give_xp(p, 10)
				p.hkey = ""
		"heal":
			var mate:Dictionary = target.mate
			mate.hp = minf(mate.hpmax, mate.hp + 28.0 * dt)
			if fmod(p.ht, 0.6) < dt: emit("heal", [mate.p.x, mate.p.y])
			if fmod(p.ht, 3.0) < dt: give_xp(p, 1)
		"rescue":
			if p.ht >= p.hm:
				var s:Dictionary = target.surv
				s.state = 1
				p.hkey = ""
				give_xp(p, 12)
				emit("rescue", [s.p.x, s.p.y])
				announce("%s ha liberado a un %s. ¡Acompañadlo a casa!" % [p.name, Data.SURVIVORS[s.kind].name.to_lower()])
		"drop":
			if p.ht >= p.hm:
				open_drop(p, target.drop)
				p.hkey = ""
		"loot":
			if p.ht >= p.hm:
				scavenge(p, target.index)
				p.hkey = ""
		"craft":
			if p.ht >= p.hm:
				p.ht = 0.0
				if materials < 2: return say(p, "Faltan materiales")
				if p.tr >= 6: return say(p, "Llevas el máximo de tracas")
				materials -= 2
				p.tr += 1
				emit("buy", [p.p.x, p.p.y])
				say(p, "Traca fabricada")
		"repair":
			var rate := 32.0 * (2.0 if p.role == 0 else 1.0) * (role_level_bonus(p) if p.role == 0 else 1.0)
			var amount := rate * dt
			if not pay_repair(p, amount): return
			match target.what:
				"struct":
					var s:Dictionary = structures[target.cell]
					s.hp = minf(s.max, s.hp + amount)
					nav.shp[target.cell] = s.hp
				"site": sites[target.site].hp = minf(sites[target.site].max, sites[target.site].hp + amount)
				"core": core = minf(core_max, core + amount * 0.8)
			if fmod(p.ht, 0.45) < dt: emit("repair", [target.at.x, target.at.y])
			if fmod(p.ht, 2.0) < dt: give_xp(p, 1)

func pay_repair(p:Dictionary, amount:float) -> bool:
	p.acc += amount
	if p.acc >= 40.0:
		if materials <= 0:
			say(p, "Sin materiales para reparar")
			p.acc = 40.0
			return false
		materials -= 1
		p.acc -= 40.0
	return true

func find_use_target(id:int, p:Dictionary) -> Dictionary:
	for other in players:
		if other == id: continue
		var q:Dictionary = players[other]
		if q.st == 1 and q.p.distance_to(p.p) < 2.3:
			var t := 2.5 * (0.45 if p.role == 1 else 1.0) * (0.7 if has_site(1) else 1.0)
			return {"type":"revive", "key":"rv%d" % other, "label":"Reanimando a %s" % q.name, "time":t, "mate":q, "prompt":"Mantén E: reanimar a %s" % q.name}
	if p.role == 1:
		for other in players:
			var q:Dictionary = players[other]
			if other != id and q.st == 0 and q.hp < q.hpmax - 1 and q.p.distance_to(p.p) < 2.3:
				return {"type":"heal", "key":"hl%d" % other, "label":"Curando a %s" % q.name, "mate":q, "prompt":"Mantén E: curar a %s" % q.name}
	for s in survivors:
		if s.state == 0 and s.p.distance_to(p.p) < 2.4:
			return {"type":"rescue", "key":"sv%d" % s.id, "label":"Liberando", "time":2.0, "surv":s, "prompt":"Mantén E: liberar al %s" % Data.SURVIVORS[s.kind].name.to_lower()}
	for d in drops:
		if d.t <= 0 and d.p.distance_to(p.p) < 2.2:
			return {"type":"drop", "key":"dr%d" % d.id, "label":"Abriendo suministros", "time":1.0, "drop":d, "prompt":"Mantén E: abrir suministros"}
	var best := -1
	var best_d := 1.9
	for i in loot.size():
		if not loot[i]: continue
		var d:float = Map.LOOT[i].p.distance_to(p.p)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		var def:Dictionary = Data.LOOT[Map.LOOT[best].kind]
		return {"type":"loot", "key":"lo%d" % best, "label":"Rebuscando", "time":def.time * (0.5 if p.role == 3 else 1.0), "index":best, "prompt":"Mantén E: rebuscar en %s" % def.name.to_lower()}
	var near_cell := -1
	var near_d := 2.0
	var bench := -1
	for cell in structures:
		var s:Dictionary = structures[cell]
		var d:float = nav.center(cell).distance_to(p.p)
		if s.k == Data.S_BENCH and d < 2.2: bench = cell
		if s.hp < s.max - 0.5 and d < near_d and s.k != Data.S_MINE:
			near_d = d
			near_cell = cell
	if near_cell >= 0:
		var s:Dictionary = structures[near_cell]
		return {"type":"repair", "what":"struct", "cell":near_cell, "at":nav.center(near_cell), "key":"st%d" % near_cell, "label":"Reparando", "prompt":"Mantén E: reparar %s (%d%%)" % [Data.STRUCTURES[s.k].name.to_lower(), int(100 * s.hp / s.max)]}
	if bench >= 0:
		return {"type":"craft", "key":"cr%d" % bench, "label":"Fabricando traca", "time":1.5, "prompt":"Mantén E: fabricar traca (2 materiales)"}
	for i in sites.size():
		if sites[i].claimed and sites[i].hp < sites[i].max and Map.SITES[i].beacon.distance_to(p.p) < 2.6:
			return {"type":"repair", "what":"site", "site":i, "at":Map.SITES[i].beacon, "key":"si%d" % i, "label":"Reparando estandarte", "prompt":"Mantén E: reparar estandarte"}
	if core < core_max and rect_distance(Map.BASE, p.p) < 1.6:
		return {"type":"repair", "what":"core", "at":p.p, "key":"core", "label":"Reparando la casa", "prompt":"Mantén E: reparar la casa (%d%%)" % int(100 * core / core_max)}
	var hint := ""
	for i in sites.size():
		if not sites[i].claimed and Map.SITES[i].beacon.distance_to(p.p) < 3.2:
			hint = "C: conquistar %s (%d materiales)" % [Data.SITES[i].name, claim_cost()]
	if hint == "" and near_shop(p.p): hint = "T: abrir la tienda"
	return {} if hint == "" else {"type":"hint", "key":"", "label":"", "prompt":hint}

func scavenge(p:Dictionary, i:int):
	if not loot[i]: return
	loot[i] = false
	var kind:int = Map.LOOT[i].kind
	var def:Dictionary = Data.LOOT[kind]
	var bonus := 1.5 if p.role == 3 else 1.0
	var mat := int(round(rng.randi_range(def.mat[0], def.mat[1]) * bonus))
	var coins := int(round(rng.randi_range(def.coins[0], def.coins[1]) * bonus))
	materials += mat
	p.coins += coins
	var parts := []
	if mat > 0: parts.append("+%d materiales" % mat)
	if coins > 0: parts.append("+%d fichas" % coins)
	if kind == 4:
		p.med = mini(3, p.med + 1)
		parts.append("+1 botiquín")
	if kind == 5:
		for g in p.guns: if p.res[g] >= 0: p.res[g] = max_reserve(p, g)
		parts.append("munición")
	if kind == 3 and rng.randf() < 0.5:
		p.tr = mini(6, p.tr + 1)
		parts.append("+1 traca")
	give_xp(p, 3)
	emit("loot", [Map.LOOT[i].p.x, Map.LOOT[i].p.y])
	say(p, ", ".join(parts) if parts.size() else "Nada útil")

func open_drop(p:Dictionary, d:Dictionary):
	drops.erase(d)
	var mat := rng.randi_range(8, 12)
	materials += mat
	p.coins += 6
	p.tr = mini(6, p.tr + 1)
	for g in p.guns: if p.res[g] >= 0: p.res[g] = max_reserve(p, g)
	give_xp(p, 8)
	emit("loot", [d.p.x, d.p.y])
	announce("%s abre los suministros: +%d materiales" % [p.name, mat])

# ------------------------------------------------------------------ day events
func event_survivor():
	if survivors.size() > 0 or community.size() >= 6: return
	var doors := Map.house_doors()
	var at:Vector2 = doors[rng.randi_range(0, doors.size() - 1)]
	serial += 1
	survivors.append({"id":serial, "p":at, "kind":rng.randi_range(0, 2), "state":0, "hp":70.0})
	for i in 2:
		var e := new_enemy(0, at + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)), "base", false)
		if nav.blocked_cell(e.p, e.r, 1) != -1: e.p = at
		e.state = 2
		e.guard = true
		e.home = e.p
	emit("survivor", [at.x, at.y])
	announce("Se oyen gritos: hay un vecino atrapado")

func event_drop():
	var at:Vector2 = Map.DROP_SPOTS[rng.randi_range(0, Map.DROP_SPOTS.size() - 1)]
	serial += 1
	drops.append({"id":serial, "p":at, "t":5.0})
	emit("drop", [at.x, at.y])
	announce("¡Un globo de feria suelta suministros!")

func event_horde():
	var front := rng.randi_range(0, 3)
	for i in 4 + wave / 2:
		new_enemy(0 if rng.randf() < 0.7 else 1, front_point(front), "base", false)
	announce("Una horda errante entra por el %s" % Map.FRONT_NAMES[front])

# ------------------------------------------------------------------ world
func tick_world(dt:float):
	for d in drops:
		if d.t > 0:
			d.t -= dt
			if d.t <= 0: emit("land", [d.p.x, d.p.y])
	for i in range(survivors.size() - 1, -1, -1):
		var s:Dictionary = survivors[i]
		if s.hp <= 0:
			survivors.remove_at(i)
			emit("kill", [s.p.x, s.p.y, -1, -1])
			announce("No hemos podido salvar al vecino")
			continue
		if s.state != 1: continue
		var next := nav.next_cell("base", 0, s.p)
		if next < 0 or nav.distance_at("base", 0, s.p) <= 15:
			survivors.remove_at(i)
			community.append(s.kind)
			stats.rescued += 1
			emit("joined", [s.kind])
			announce("Un %s se une a la comunidad: %s" % [Data.SURVIVORS[s.kind].name.to_lower(), Data.SURVIVORS[s.kind].desc])
			continue
		var dir:Vector2 = (nav.center(next) - s.p).normalized()
		s.p = nav.move(s.p, dir * 2.8 * dt, 0.3, 0)
	if community.has(2) and phase == P.NIGHT:
		vigia_timer -= dt
		if vigia_timer <= 0:
			vigia_timer = 1.0 / community.count(2)
			var best := -1
			var bd := 12.0
			for key in enemies:
				var d:float = enemies[key].p.distance_to(Map.BASE_CENTER)
				if d < bd:
					bd = d
					best = key
			if best >= 0:
				var e:Dictionary = enemies[best]
				emit("shot", [-2, 0, 0.0, -0.5, e.p.x, e.p.y])
				damage_enemy(best, 20.0, -9, (e.p - Map.BASE_CENTER).normalized(), 0.3)
	if phase == P.NIGHT and night_event == 4:
		lightning_timer -= dt
		if lightning_timer <= 0:
			lightning_timer = rng.randf_range(4.0, 8.0)
			var at := Vector2(rng.randf_range(-26, 26), rng.randf_range(-22, 22))
			if enemies.size() > 0 and rng.randf() < 0.6:
				var keys := enemies.keys()
				at = enemies[keys[rng.randi_range(0, keys.size() - 1)]].p
			strikes.append({"p":at, "t":1.0})
			emit("warn", [at.x, at.y])
	for i in range(strikes.size() - 1, -1, -1):
		strikes[i].t -= dt
		if strikes[i].t <= 0:
			var at:Vector2 = strikes[i].p
			strikes.remove_at(i)
			emit("bolt", [at.x, at.y])
			for key in enemies.keys():
				if enemies.has(key) and enemies[key].p.distance_to(at) < 2.2: damage_enemy(key, 90.0, -9)
			for cell in structures.keys():
				if nav.center(cell).distance_to(at) < 2.0: damage_structure(cell, 35.0)
			for p in players.values():
				if p.p.distance_to(at) < 2.0: hurt_player(p, 15.0)

# ------------------------------------------------------------------ structures
func tick_structures(dt:float):
	for cell in structures.keys():
		if not structures.has(cell): continue
		var s:Dictionary = structures[cell]
		var def:Dictionary = Data.STRUCTURES[s.k]
		var c := nav.center(cell)
		s.on = not def.electric or powered(cell)
		s.cool -= dt
		match s.k:
			Data.S_COIL:
				if not s.on or s.cool > 0: continue
				var from := c
				var chained := []
				for j in 1 + s.lvl:
					var best := -1
					var bd := 3.8 if j == 0 else 2.8
					for key in near_enemies(from, bd):
						if key in chained: continue
						var d:float = enemies[key].p.distance_to(from)
						if d < bd:
							bd = d
							best = key
					if best < 0: break
					chained.append(best)
					var to:Vector2 = enemies[best].p
					emit("zap", [from.x, from.y, to.x, to.y])
					enemies[best].stun = maxf(enemies[best].stun, 0.35)
					damage_enemy(best, 24.0 + 8.0 * s.lvl, -100 - cell)
					from = to
				if chained.size() > 0: s.cool = 0.9
			Data.S_TURRET:
				if not s.on or s.cool > 0: continue
				var reach:float = 9.0 + s.lvl
				var best := -1
				var bd := reach
				for key in near_enemies(c, reach):
					var e:Dictionary = enemies[key]
					var d:float = e.p.distance_to(c)
					if d < bd and nav.clear_line(c, e.p):
						bd = d
						best = key
				if best >= 0:
					var e:Dictionary = enemies[best]
					var dir:Vector2 = (e.p - c).normalized()
					s.aim = dir.angle()
					s.cool = 0.36 * (0.78 if near_generator(cell) else 1.0)
					emit("shot", [-100 - cell, 7, c.x + dir.x * 0.4, c.y + dir.y * 0.4, e.p.x, e.p.y])
					damage_enemy(best, 11.0 + 4.0 * s.lvl, -100 - cell, dir, 0.15)
			Data.S_BENCH:
				var rate:float = 3.0 + 1.5 * s.lvl
				for other in structures:
					var o:Dictionary = structures[other]
					if other != cell and o.hp < o.max and nav.center(other).distance_to(c) < 6.0:
						o.hp = minf(o.max, o.hp + rate * dt)

func near_enemies(at:Vector2, radius:float) -> Array:
	var out := []
	var r := ceili(radius / 2.0)
	var bx := floori(at.x / 2.0)
	var bz := floori(at.y / 2.0)
	for x in range(bx - r, bx + r + 1):
		for z in range(bz - r, bz + r + 1):
			var key := Vector2i(x, z)
			if buckets.has(key): out.append_array(buckets[key])
	return out

func build_buckets():
	buckets.clear()
	for key in enemies:
		var p:Vector2 = enemies[key].p
		var b := Vector2i(floori(p.x / 2.0), floori(p.y / 2.0))
		if not buckets.has(b): buckets[b] = []
		buckets[b].append(key)

# ------------------------------------------------------------------ enemies
func tick_enemies(dt:float):
	var lights := []
	if phase == P.NIGHT:
		for cell in structures:
			var s:Dictionary = structures[cell]
			if s.k == Data.S_LIGHT and s.on: lights.append([nav.center(cell), 6.0 + s.lvl])
	var speed_mult := 1.25 if night_event == 5 and phase == P.NIGHT else 1.0
	for key in enemies.keys():
		if not enemies.has(key): continue
		var e:Dictionary = enemies[key]
		var def:Dictionary = Data.ENEMIES[e.k]
		e.flash = maxf(0, e.flash - dt)
		e.stun = maxf(0, e.stun - dt)
		e.cd = maxf(-1.0, e.cd - dt)
		e.atk = maxf(0, e.atk - dt)
		e.kv = e.kv.move_toward(Vector2.ZERO, 22.0 * dt)
		if e.burn > 0:
			e.burn -= dt
			damage_enemy(key, 7.0 * dt, e.burner)
			if not enemies.has(key): continue
		e.lit = false
		for l in lights:
			if e.p.distance_to(l[0]) < l[1]:
				e.lit = true
				break
		if e.state == 2:
			for p in players.values():
				if p.st == 0 and p.p.distance_to(e.p) < 8.0:
					wake(e)
					e.victim = players.find_key(p)
			continue
		# --- pick a victim
		e.retarget -= dt
		if e.retarget <= 0:
			e.retarget = 0.4
			choose_victim(key, e)
		# --- fuse
		if e.fuse > 0:
			e.fuse -= dt
			if e.fuse <= 0:
				enemies.erase(key)
				explode(e.p, 2.6, def.dmg, -9, true, def.struct)
				emit("kill", [e.p.x, e.p.y, e.k, -9])
			continue
		if e.k == Data.BOSS: boss_logic(e, dt)
		# --- ongoing wind-up
		if e.wind > 0:
			e.wind -= dt
			if e.wind <= 0: land_attack(e, def)
			continue
		var dir := Vector2.ZERO
		var target = null
		var victim:Dictionary = victim_of(e)
		if not victim.is_empty():
			var to:Vector2 = victim.p - e.p
			var d := to.length()
			if e.k == Data.SPITTER and d < 7.5:
				e.face = to.normalized()
				if e.cd <= 0: spit(e, victim.p)
				continue
			if d < e.r + 0.55:
				target = {"type":"player" if victim.has("st") else "surv", "ref":victim}
			else:
				dir = to / maxf(d, 0.001)
				var ahead := nav.blocked_cell(e.p + dir * 0.35, e.r * 0.85, 2 if e.k == Data.CLIMBER else 1)
				if ahead >= 0 and structures.has(ahead):
					target = {"type":"struct", "cell":ahead}
		elif e.guard:
			var home:Vector2 = e.home
			if e.p.distance_to(home) < 1.2:
				e.guard_alert -= dt
				if e.guard_alert <= 0: e.state = 2
			else:
				dir = (home - e.p).normalized()
		else:
			var next := nav.next_cell(e.goal, e.mode, e.p)
			if next < 0:
				target = objective_target(e)
				if target == null:
					dir = (goal_point(e.goal) - e.p).normalized()
			else:
				var nc := nav.center(next)
				dir = (nc - e.p).normalized()
				if structures.has(next) and e.k != Data.CLIMBER and Data.STRUCTURES[structures[next].k].block:
					if rect_distance(Rect2(nc - Vector2(0.5, 0.5), Vector2.ONE), e.p) < e.r + 0.3:
						target = {"type":"struct", "cell":next}
				if e.k == Data.SPITTER:
					var gp := goal_point(e.goal)
					if gp.distance_to(e.p) < 6.5 and e.cd <= 0 and nav.clear_line(e.p, gp):
						e.face = (gp - e.p).normalized()
						spit(e, gp)
						continue
		if target != null:
			if e.k == Data.BOOMER:
				e.fuse = 0.7
				emit("fuse", [key])
				continue
			if e.cd <= 0:
				e.wind = 0.32 if e.k != 2 else 0.5
				e.target = target
				e.atk = e.wind + 0.25
				emit("swing", [key])
			e.face = (target_pos(target) - e.p).normalized() if target_pos(target) != e.p else e.face
			continue
		# --- move
		var spd:float = e.speed * speed_mult
		if e.stun > 0: spd = 0.0
		if e.lit: spd *= 0.82
		var cell := nav.cell_of(e.p)
		e.climb = false
		if cell >= 0 and structures.has(cell):
			var s:Dictionary = structures[cell]
			if s.k == Data.S_WIRE:
				spd *= 0.45
				damage_enemy(key, (8.0 + 6.0 * s.lvl) * dt, -100 - cell)
				damage_structure(cell, 3.0 * dt)
				if not enemies.has(key): continue
			elif s.k == Data.S_MINE:
				trigger_mine(cell)
				if not enemies.has(key): continue
			elif e.k == Data.CLIMBER and Data.STRUCTURES[s.k].block:
				spd *= 0.55
				e.climb = true
		var sep := Vector2.ZERO
		for other in near_enemies(e.p, 1.6):
			if other == key or not enemies.has(other): continue
			var o:Dictionary = enemies[other]
			var rel:Vector2 = e.p - o.p
			var min_d:float = e.r + o.r
			var dd := rel.length()
			if dd < min_d and dd > 0.001: sep += rel / dd * (min_d - dd) * 6.0
		if dir != Vector2.ZERO: e.face = e.face.lerp(dir, minf(1.0, 8.0 * dt)).normalized()
		var vel:Vector2 = dir * spd + sep.limit_length(3.0) + e.kv
		var before:Vector2 = e.p
		e.p = nav.move(e.p, vel * dt, minf(e.r * 0.9, 0.42), 2 if e.k == Data.CLIMBER else 1)
		# Unstick: if we wanted to move but could not for a while, squeeze through.
		if spd > 0.1 and dir != Vector2.ZERO and before.distance_squared_to(e.p) < 0.0001:
			e.stuck += dt
			if e.stuck > 1.5:
				e.p = nav.move(e.p, dir * 0.3, 0.2, 2 if e.k == Data.CLIMBER else 1)
				e.stuck = 0.0
		else:
			e.stuck = 0.0

func goal_point(goal:String) -> Vector2:
	if goal.begins_with("site"): return Map.SITES[int(goal.substr(4))].beacon
	return Map.BASE_CENTER

func objective_target(e:Dictionary):
	if e.goal.begins_with("site"):
		var i := int(e.goal.substr(4))
		if not sites[i].claimed:
			e.goal = "base"
			return null
		if Map.SITES[i].beacon.distance_to(e.p) < e.r + 1.3: return {"type":"site", "site":i}
		return null
	if rect_distance(Map.BASE, e.p) < e.r + 0.7: return {"type":"core"}
	return null

func target_pos(t:Dictionary) -> Vector2:
	match t.type:
		"player": return t.ref.p
		"struct": return nav.center(t.cell)
		"site": return Map.SITES[t.site].beacon
		"core":
			return Map.BASE_CENTER
		"surv": return t.ref.p
	return Vector2.ZERO

func land_attack(e:Dictionary, def:Dictionary):
	var t = e.target
	e.cd = def.cd
	if t == null: return
	var dmg:float = def.dmg
	match t.type:
		"player":
			if t.ref.p.distance_to(e.p) < e.r + 1.0: hurt_player(t.ref, dmg, e.p)
		"surv":
			if t.ref.p.distance_to(e.p) < e.r + 1.0: t.ref.hp -= dmg
		"struct":
			damage_structure(t.cell, dmg * def.struct)
		"site": damage_site(t.site, dmg * def.struct)
		"core": damage_core(dmg * def.struct * 0.5)
		"slam": land_slam(e)
	e.target = null

func choose_victim(_key:int, e:Dictionary):
	var aggro := 6.0
	match e.k:
		1: aggro = 9.0
		5: aggro = 10.0
		7: aggro = 7.0
	if e.guard: aggro = 13.0
	if phase != P.NIGHT and not e.guard: aggro += 3.0
	var best := -1
	var bd := aggro
	for id in players:
		var p:Dictionary = players[id]
		if p.st != 0: continue
		var d:float = p.p.distance_to(e.p)
		if d < bd and (d < 2.0 or nav.clear_line(e.p, p.p)):
			bd = d
			best = id
	e.victim = best
	e.surv = null
	if best < 0:
		for s in survivors:
			if s.state == 1 and s.p.distance_to(e.p) < aggro: e.surv = s

func victim_of(e:Dictionary) -> Dictionary:
	if e.victim >= 0 and players.has(e.victim) and players[e.victim].st == 0: return players[e.victim]
	if e.get("surv") != null and survivors.has(e.surv): return e.surv
	return {}

func spit(e:Dictionary, at:Vector2):
	e.cd = Data.ENEMIES[e.k].cd
	e.atk = 0.4
	var lead := at + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
	projectiles.append({"from":e.p, "to":lead, "t":0.0, "dur":0.9, "kind":0, "dmg":Data.ENEMIES[e.k].dmg, "r":1.1, "owner":-1, "h":2.0})
	emit("spit", [e.p.x, e.p.y])

func boss_logic(e:Dictionary, dt:float):
	e.summon -= dt
	if e.summon <= 0:
		e.summon = 11.0
		for i in 3:
			var at:Vector2 = e.p + Vector2.from_angle(TAU * i / 3.0) * 2.2
			if nav.blocked_cell(at, 0.4, 1) == -1: new_enemy(0, at, "base", true)
		emit("summon", [e.p.x, e.p.y])
	e.slam -= dt
	if e.slam <= 0 and e.wind <= 0:
		var close := false
		for p in players.values():
			if p.st == 0 and p.p.distance_to(e.p) < 3.6: close = true
		for cell in structures:
			if nav.center(cell).distance_to(e.p) < 2.6: close = true
		if rect_distance(Map.BASE, e.p) < 2.8: close = true
		if close:
			e.slam = 7.0
			e.wind = 0.95
			e.atk = 1.2
			e.target = {"type":"slam"}
			emit("slam_warn", [e.p.x, e.p.y])

func land_slam(e:Dictionary):
	emit("slam", [e.p.x, e.p.y])
	for p in players.values():
		if p.p.distance_to(e.p) < 3.6: hurt_player(p, 35.0, e.p)
	for cell in structures.keys():
		if nav.center(cell).distance_to(e.p) < 3.0: damage_structure(cell, 140.0)
	if rect_distance(Map.BASE, e.p) < 3.0: damage_core(45.0)

func tick_projectiles(dt:float):
	for i in range(projectiles.size() - 1, -1, -1):
		var pr:Dictionary = projectiles[i]
		pr.t += dt
		if pr.t < pr.dur: continue
		projectiles.remove_at(i)
		var at:Vector2 = pr.to
		if pr.kind == 0:
			emit("splat", [at.x, at.y])
			for p in players.values():
				if p.p.distance_to(at) < pr.r: hurt_player(p, pr.dmg, at)
			var cell := nav.cell_of(at)
			if structures.has(cell): damage_structure(cell, pr.dmg * 1.2)
			if rect_distance(Map.BASE, at) < 0.8: damage_core(pr.dmg * 0.5)
			for s in survivors:
				if s.state == 1 and s.p.distance_to(at) < pr.r: s.hp -= pr.dmg
		else:
			explode(at, pr.r, pr.dmg, pr.owner, false, 0.0)

func projectile_pos(pr:Dictionary) -> Vector3:
	var f:float = clampf(pr.t / pr.dur, 0, 1)
	var flat:Vector2 = pr.from.lerp(pr.to, f)
	return Vector3(flat.x, 0.9 + pr.h * 4.0 * f * (1.0 - f), flat.y)

# ================================================================== snapshot
func snapshot() -> Dictionary:
	var en := PackedFloat32Array()
	en.resize(enemies.size() * 8)
	var i := 0
	for key in enemies:
		var e:Dictionary = enemies[key]
		var flags := 0
		if e.atk > 0: flags |= 1
		if e.climb: flags |= 2
		if e.state == 2: flags |= 4
		if e.lit: flags |= 8
		if e.stun > 0: flags |= 16
		if e.fuse > 0: flags |= 32
		if e.wind > 0: flags |= 64
		if e.burn > 0: flags |= 128
		en[i] = key
		en[i + 1] = e.k
		en[i + 2] = e.p.x
		en[i + 3] = e.p.y
		en[i + 4] = e.hp / e.max
		en[i + 5] = e.face.angle() if e.face != Vector2.ZERO else 0.0
		en[i + 6] = flags
		en[i + 7] = e.flash
		i += 8
	var st := PackedInt32Array()
	for cell in structures:
		var s:Dictionary = structures[cell]
		st.append_array([cell, s.k, s.lvl, int(s.hp), int(s.max), int(rad_to_deg(s.aim)), 1 if s.on else 0, s.owner])
	var pr := PackedFloat32Array()
	for p in projectiles:
		var v := projectile_pos(p)
		pr.append_array([v.x, v.y, v.z, p.kind])
	var pl := {}
	for id in players:
		var p:Dictionary = players[id]
		pl[id] = {"name":p.name, "role":p.role, "slot":p.slot, "p":p.p, "aim":p.aim, "hp":p.hp, "hpmax":p.hpmax, "st":p.st,
			"bleed":p.bleed, "coins":p.coins, "xp":p.xp, "lvl":p.lvl, "gun":p.gun, "guns":p.guns, "mag":p.mag, "res":p.res,
			"rl":p.rl, "rlmax":p.rlmax, "ab":p.ab, "buff":p.buff, "med":p.med, "tr":p.tr, "kills":p.kills,
			"notice":p.notice if p.nt > 0 else "", "hold":p.hold, "ht":p.ht, "hm":p.hm, "prompt":p.prompt, "ready":p.ready,
			"roll":p.roll, "fix":p.fix, "dmg":p.dmg, "fire":p.fire and p.rl <= 0, "use":p.use}
	var si := []
	for s in sites: si.append([s.claimed, s.hp, s.max])
	var sv := []
	for s in survivors: sv.append([s.id, s.p.x, s.p.y, s.kind, s.state])
	var dr := []
	for d in drops: dr.append([d.id, d.p.x, d.p.y, d.t])
	var sk := []
	for s in strikes: sk.append([s.p.x, s.p.y, s.t])
	var boss := []
	for key in enemies:
		if enemies[key].k == Data.BOSS: boss = [key, enemies[key].hp / enemies[key].max]
	return {"ph":phase, "w":wave, "c":clock, "cl":phase_len, "tod":time_of_day(), "core":core, "cmax":core_max, "clvl":core_level,
		"mat":materials, "ev":night_event, "wx":weather, "fr":fronts, "rem":queue.size() + night_alive(), "tot":night_total,
		"pl":pl, "en":en, "st":st, "si":si, "lo":loot.duplicate(), "pr":pr, "sv":sv, "dr":dr, "cm":community.duplicate(),
		"fx":events.duplicate(), "rep":report, "boss":boss, "sk":sk, "stats":stats, "time":time, "cc":claim_cost()}

func load_structures(st:PackedInt32Array):
	## Used by clients so local movement prediction collides with the same structures.
	var seen := {}
	for i in range(0, st.size(), 8):
		var cell := st[i]
		seen[cell] = true
		if nav.skind[cell] != st[i + 1]: nav.set_structure(cell, st[i + 1], st[i + 3])
		nav.shp[cell] = st[i + 3]
	for c in nav.skind.size():
		if nav.skind[c] >= 0 and not seen.has(c): nav.clear_structure(c)
