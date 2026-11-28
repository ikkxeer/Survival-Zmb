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
const PING_DURATION := 8.0
const PING_INTERVAL := 1.5
const ALERT_TIME := 3.2
const RESPITE := 15.0
const BUNDLE_COST := 4

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
var posts := []           # where each community member works: -1 at home, else a site index
var variant := 0          # optional rule set chosen before the match (Data.VARIANTS)
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
var midnight := false        # the Plañidera has already come tonight
var spawn_timer := 0.0
var front_turn := 0       # which of tonight's streets the next group comes down
var straggler_timer := 20.0
var day_plan := {}
var lightning_timer := 6.0
var vigia_timer := 0.0
var report := []
var stats := {"kills":0, "built":0, "rescued":0, "nights":0}
var buckets := {}
var alerts := []          # per access (norte, este, sur, oeste): {hit, breach, house}
var sector_damage := [0.0, 0.0, 0.0, 0.0]
var site_hit := []
var assaults := []        # remaining assault groups of tonight
var assault_index := 0
var assault_count := 1
var respite := 0.0
var bundles := []         # supply bundles left at the porch for team-mates
var journal := []         # telemetry lines for playtests (read and cleared by the host)
var breach_open := [-1.0, -1.0, -1.0, -1.0]
var pieces := []          # {state:0 locked,1 waiting,2 carried,3 dropped,4 installed, p, carrier}
var finale := false
var finale_t := 0.0
var victory := false
var match_id := 0
var jobs := []            # today's offers: {id,kind,size,p,state(0 offered,1 accepted,2 done,3 failed),mat,coins,progress,carrier,risk,area}
var last_jobs := []
var pending := {}
var best_moment := {"score":0, "text":""}    # the moment the end screen remembers
var night_low := 1e9      # lowest the house has been tonight
var core_by_kind := {}    # tonight's damage to the house by brotado kind, for balance telemetry
var relay := false        # an installed relay: guaranteed power and faster turrets         # players from a checkpoint waiting to reconnect, by name
const KEEP = ["role", "coins", "xp", "lvl", "hpmax", "guns", "mag", "res", "med", "tr", "kills", "helped", "rank", "tally"]

func _init():
	rng.randomize()
	for i in Map.SITES.size():
		sites.append({"claimed":false, "hp":0.0, "max":200.0})
		site_hit.append(0.0)
	for i in 4: alerts.append({"hit":0.0, "breach":false, "house":0.0})
	match_id = rng.randi_range(1, 1 << 30)
	for pc in Data.PIECES:
		pieces.append({"state":0, "p":Map.SITES[pc.site].beacon + Vector2(0, 1.6), "carrier":-1})
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

func party() -> int:
	## Players connected right now, 1 to 4: scales the size, health and spread of the nights.
	return clampi(players.size(), 1, 4)

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
	if night_event != 1 or phase != P.NIGHT or has_site(4) or relay: return true
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
	if p.get("carry", -1) >= 0: s *= 0.8
	if p.get("cargo", -1) >= 0: s *= 0.85
	if p.st == 1: s = 0.9
	return s

# ================================================================== players
func join(id:int, role:int, name:String = "", rank:int = 1) -> bool:
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
		"ping": null, "ping_left": 0.0, "active": time, "last_p": Vector2.ZERO, "helped": 0, "carry": -1, "cargo": -1, "dmg": 0.0, "flame": 0.0, "cursor": Vector2.ZERO,
		"tally": {"shots":0, "hits":0, "built":0, "freed":0, "revived":0}, "streak":0, "streak_t":-9.0,
	}
	players[id] = p
	if pending.has(p.name):
		# a neighbour coming back to a saved match recovers what they had
		var saved:Dictionary = pending[p.name]
		pending.erase(p.name)
		for k in KEEP:
			if saved.has(k): p[k] = saved[k]
		p.hp = p.hpmax
		p.gun = 0
		emit("join", [id])
		announce("%s vuelve a la verbena" % p.name)
		return true
	apply_rank(p, clampi(rank, 1, 4))
	emit("join", [id])
	announce("%s se une como %s" % [p.name, Data.ROLES[role].name])
	return true

func to_save() -> Dictionary:
	## Everything needed to continue at dawn. Enemies are not saved: the day starts clean.
	var pl := {}
	for p in players.values():
		var d := {}
		for k in KEEP: d[k] = p.get(k, null)
		pl[p.name] = d
	for name in pending: pl[name] = pending[name]
	var st := {}
	for cell in structures:
		var x:Dictionary = structures[cell]
		st[cell] = {"k":x.k, "lvl":x.lvl, "hp":x.hp, "max":x.max, "owner":x.owner}
	return {"wave":wave, "core":core, "core_max":core_max, "core_level":core_level, "materials":materials,
		"players":pl, "structures":st, "sites":sites.duplicate(true), "loot":loot.duplicate(), "community":community.duplicate(), "posts":posts.duplicate(), "variant":variant, "relay":relay,
		"pieces":pieces.map(func(pc): return {"state":3 if pc.state == 2 else pc.state, "p":pc.p}), "stats":stats.duplicate(),
		"night_event":night_event, "weather":weather, "fronts":fronts.duplicate()}

func from_save(d:Dictionary):
	wave = d.wave
	core = d.core
	core_max = d.core_max
	core_level = d.core_level
	materials = d.materials
	pending = d.players.duplicate(true)
	structures.clear()
	for cell in d.structures:
		var x:Dictionary = d.structures[cell]
		structures[cell] = {"k":x.k, "lvl":x.lvl, "hp":x.hp, "max":x.max, "cool":0.0, "owner":x.owner, "aim":0.0, "on":true}
		nav.set_structure(cell, x.k, x.hp)
	sites = d.sites.duplicate(true)
	for i in sites.size():
		if sites[i].claimed: nav.active["site%d" % i] = true
	loot = d.loot.duplicate()
	community = d.community.duplicate()
	posts = d.get("posts", community.map(func(_k): return -1)).duplicate()
	variant = d.get("variant", 0)
	relay = d.get("relay", false)
	for i in mini(pieces.size(), d.pieces.size()):
		pieces[i].state = d.pieces[i].state
		pieces[i].p = d.pieces[i].p
		pieces[i].carrier = -1
	stats = d.stats.duplicate()
	enemies.clear()
	for i in sites.size():
		if not sites[i].claimed:
			for g in 2 + mini(2, wave / 4): spawn_guard(i)
	night_event = d.night_event
	weather = d.weather
	fronts = d.fronts.duplicate()
	phase = P.DAWN
	clock = 14.0
	phase_len = 14.0
	report = ["Partida recuperada: amanecer de la noche %d" % (wave - 1)]
	make_jobs()

func home_count(kind:int) -> int:
	var n := 0
	for i in community.size():
		if community[i] == kind and posts[i] < 0: n += 1
	return n

func site_helpers(site:int) -> int:
	return posts.count(site)

func site_boost(site:int, amount:int) -> int:
	## Neighbours working at a property raise its dawn bonus by half each.
	return int(round(amount * (1.0 + 0.5 * site_helpers(site))))

func assign(p:Dictionary, member:int, site:int):
	if member < 0 or member >= community.size(): return
	if p.p.distance_to(Map.BOARD) > 3.0: return say(p, "Organiza a la comunidad desde el tablón")
	if site >= 0 and not sites[site].claimed: return say(p, "Solo en propiedades del barrio")
	posts[member] = site
	var who:String = Data.SURVIVORS[community[member]].name
	if site >= 0:
		sites[site].max = 200.0 + 100.0 * site_helpers(site)
		sites[site].hp = minf(sites[site].max, sites[site].hp + 100.0)
		announce("El %s se va a %s: su bonificación sube un 50%%" % [who.to_lower(), Data.SITES[site].name])
	else:
		announce("El %s vuelve a la casa" % who.to_lower())
	emit("assign", [member, site])
	log_line({"evento":"destino_vecino", "vecino":who, "destino":Data.SITES[site].name if site >= 0 else "casa"})

func apply_rank(p:Dictionary, rank:int):
	## Perks earned between matches (see profile.gd): rank 2 per role, rank 3 more health.
	p.rank = rank
	if rank >= 2:
		match p.role:
			0: materials += 4
			1: p.med = 3
			2:
				p.guns[1] = 1
				p.mag[1] = Data.WEAPONS[1].mag
				p.res[1] = max_reserve(p, 1) / 2
			3: p.coins += 8
	if rank >= 3:
		p.hpmax += 15.0
		p.hp = p.hpmax

func leave(id:int):
	if players.has(id): drop_piece(players[id])
	if players.erase(id): emit("leave", [id])

func drop_piece(p:Dictionary):
	if p.cargo >= 0:
		for j in jobs:
			if j.id == p.cargo:
				j.carrier = -1
				j.p = p.p
		p.cargo = -1
	if p.carry < 0: return
	var pc:Dictionary = pieces[p.carry]
	pc.state = 3
	pc.p = p.p
	pc.carrier = -1
	p.carry = -1
	emit("piece_drop", [pc.p.x, pc.p.y])
	announce("¡%s ha soltado una pieza de la verbena!" % p.name)

func installed_pieces() -> int:
	var n := 0
	for pc in pieces: if pc.state == 4: n += 1
	return n

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
	if p.hkey != "" and p.hm > 0:
		p.ht = 0.0          # being hit interrupts reviving, carrying, scavenging…
		p.hkey = "hit"
	if p.hp <= 0:
		p.hp = 0.0
		p.st = 1
		p.bleed = 30.0
		p.rl = 0.0
		drop_piece(p)
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
	p.active = time
	if action == "ready":
		p.ready = not p.ready
		return
	if action == "ping":
		mark(id, args[0] if args.size() > 0 else p.p)
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
		"sell_gun":
			if args.size() >= 1: sell_gun(p, int(args[0]))
		"sell_item":
			if args.size() >= 1: sell_item(p, str(args[0]))
		"buy_medkit":
			if not near_shop(p.p): return say(p, "La tienda está en la casa")
			if p.med >= 3: return say(p, "Llevas el máximo de botiquines")
			if p.coins < price(Data.MEDKIT.price): return say(p, "Faltan fichas")
			p.coins -= price(Data.MEDKIT.price)
			p.med += 1
			emit("buy", [id])
		"buy_traca":
			if not near_shop(p.p): return say(p, "La tienda está en la casa")
			if p.tr >= 6: return say(p, "Llevas el máximo de tracas")
			if p.coins < price(Data.GRENADE.price): return say(p, "Faltan fichas")
			p.coins -= price(Data.GRENADE.price)
			p.tr += 1
			emit("buy", [id])
		"core_up": core_upgrade(p)
		"bundle": prepare_bundle(id, p)
		"assign":
			if args.size() >= 2: assign(p, int(args[0]), int(args[1]))
		"job_accept":
			if args.size() > 0: job_accept(p, int(args[0]))
		"job_abandon":
			if args.size() > 0: job_abandon(p, int(args[0]))

func mark(id:int, point) -> bool:
	## Team signal: lasts PING_DURATION, one every PING_INTERVAL. Fallen players mark where they lie.
	if phase == P.OVER or not players.has(id): return false
	if not (point is Vector2) or not (point as Vector2).is_finite(): return false
	var p:Dictionary = players[id]
	if p.ping_left > PING_DURATION - PING_INTERVAL: return false
	p.ping = p.p if p.st != 0 else (point as Vector2).clamp(Map.BOUNDS.position, Map.BOUNDS.end)
	p.ping_left = PING_DURATION
	emit("ping", [p.ping.x, p.ping.y, id])
	return true

static func sector_of(at:Vector2) -> int:
	## 0 norte, 1 este, 2 sur, 3 oeste, seen from the party house.
	var d := at - Map.BASE_CENTER
	if absf(d.x) > absf(d.y): return 1 if d.x > 0 else 3
	return 2 if d.y > 0 else 0

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
	if kind == Data.S_TURRET and structures.has(cell) and structures[cell].k == Data.S_TURRET:
		return upgrade(id, p, cell)
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
	p.tally.built += 1
	give_xp(p, 2)
	if def.block or kind == Data.S_WIRE:
		var sec := sector_of(c)
		if alerts[sec].breach and breach_open[sec] >= 0:
			log_line({"evento":"brecha_cerrada", "acceso":Map.FRONT_NAMES[sec], "segundos":snappedf(time - breach_open[sec], 0.1), "por":p.name})
			breach_open[sec] = -1.0
		alerts[sec].breach = false
		alerts[sec].hit = 0.0
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
	if broken and (Data.STRUCTURES[k].block or k == Data.S_WIRE):
		var sec := sector_of(nav.center(cell))
		if not alerts[sec].breach:
			breach_open[sec] = time
			log_line({"evento":"brecha", "acceso":Map.FRONT_NAMES[sec], "defensa":Data.STRUCTURES[k].name})
		alerts[sec].breach = true
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
	for i in Data.PIECES.size():
		if Data.PIECES[i].site == site and pieces[i].state == 0:
			pieces[i].state = 1
			emit("piece", [i])
			announce("En %s espera una pieza de la verbena: %s. ¡Llevadla al escenario!" % [Data.SITES[site].name, Data.PIECES[i].name])
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
	if p.coins < price(w.price): return say(p, "Faltan fichas (%d)" % price(w.price))
	p.coins -= price(w.price)
	p.guns[g] = 1
	p.mag[g] = w.mag
	p.res[g] = max_reserve(p, g) / 2 if w.reserve > 0 else -1
	p.gun = g
	p.rl = 0.0
	emit("buy", [p.p.x, p.p.y])
	say(p, "%s comprado" % w.name)

func sell_value(p:Dictionary, g:int) -> int:
	## Half of what was spent on the weapon: purchase plus upgrades.
	if not p.guns.has(g) or g == 0: return 0
	var w:Dictionary = Data.WEAPONS[g]
	var spent:int = w.price
	for i in int(p.guns[g]) - 1: spent += int(w.up[i])
	return spent / 2

func sell_gun(p:Dictionary, g:int):
	if not near_shop(p.p): return say(p, "La tienda está en la casa")
	if g == 0: return say(p, "La pistola de feria no se vende")
	if not p.guns.has(g): return
	var value := sell_value(p, g)
	p.guns.erase(g)
	p.mag.erase(g)
	p.res.erase(g)
	p.coins += value
	if p.gun == g:
		p.gun = 0
		p.rl = 0.0
	emit("buy", [p.p.x, p.p.y])
	say(p, "%s vendido por %d fichas" % [Data.WEAPONS[g].name, value])

func sell_item(p:Dictionary, what:String):
	if not near_shop(p.p): return say(p, "La tienda está en la casa")
	if what == "medkit" and p.med > 0:
		p.med -= 1
		p.coins += Data.MEDKIT.price / 2
	elif what == "traca" and p.tr > 0:
		p.tr -= 1
		p.coins += Data.GRENADE.price / 2
	else: return
	emit("buy", [p.p.x, p.p.y])

func act_switch(p:Dictionary, g:int):
	p.gun = g
	p.rl = 0.0

func up_gun(p:Dictionary, g:int):
	if not near_shop(p.p): return say(p, "La tienda está en la casa")
	if not p.guns.has(g): return say(p, "Primero compra el arma")
	var lvl:int = p.guns[g]
	if lvl >= 3: return say(p, "Ya está al máximo")
	var cost:int = price(Data.WEAPONS[g].up[lvl - 1])
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
	var cost := price(Data.WEAPONS[g].ammo_price)
	if p.coins < cost: return say(p, "Faltan fichas (%d)" % cost)
	p.coins -= cost
	p.res[g] = top
	emit("buy", [p.p.x, p.p.y])

func prepare_bundle(id:int, p:Dictionary):
	## Someone staying home packs ammo, a medkit and a firecracker for a team-mate.
	if not near_shop(p.p): return say(p, "Prepara el lote en la tienda de la casa")
	if players.size() < 2: return say(p, "Los lotes sirven para tus compañeros")
	if bundles.size() >= 3: return say(p, "Ya hay tres lotes esperando en el porche")
	if materials < BUNDLE_COST: return say(p, "Necesitas %d materiales" % BUNDLE_COST)
	materials -= BUNDLE_COST
	serial += 1
	var spot:Vector2 = Map.PORCH + Vector2(bundles.size() * 0.9, 0)
	bundles.append({"id":serial, "p":spot, "owner":id})
	give_xp(p, 3)
	emit("bundle", [spot.x, spot.y])
	announce("%s deja un lote de suministros en el porche" % p.name)

func take_bundle(p:Dictionary, b:Dictionary):
	bundles.erase(b)
	for g in p.guns: if p.res[g] >= 0: p.res[g] = max_reserve(p, g)
	p.med = mini(3, p.med + 1)
	p.tr = mini(6, p.tr + 1)
	p.hp = minf(p.hpmax, p.hp + 40)
	if players.has(b.owner):
		players[b.owner].helped += 1
		give_xp(players[b.owner], 5)
		announce("%s recoge el lote de %s: munición, botiquín y traca" % [p.name, players[b.owner].name])
	emit("loot", [b.p.x, b.p.y])
	log_line({"evento":"lote", "de":players[b.owner].name if players.has(b.owner) else "?", "para":p.name})

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
			for j in jobs:
				if j.kind == "relevo" and j.state == 1 and not j.found and j.p.distance_to(p.p) < 25.0:
					reveal(j, p)

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
	if not frenzy:
		p.mag[p.gun] -= 1
		if p.mag[p.gun] <= 0: start_reload(p)    # the last round starts the reload at once
	var dmg:float = w.dmg * (1.0 + 0.25 * (lvl - 1)) * Data.ROLES[p.role].damage
	if p.role == 2: dmg *= role_level_bonus(p)
	var origin:Vector2 = p.p + p.aim * 0.55
	match w.kind:
		"hit":
			var pellets:int = w.pellets
			var landed := false
			for i in pellets:
				var off := 0.0
				if pellets > 1: off = (float(i) / (pellets - 1) - 0.5) * w.spread + rng.randf_range(-0.04, 0.04)
				else: off = rng.randf_range(-0.5, 0.5) * w.spread
				if hitscan(id, origin, p.aim.rotated(off), w.range, dmg, w.pierce, w.knock, p.gun): landed = true
			p.tally.shots += 1
			if landed: p.tally.hits += 1
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

func hitscan(owner:int, origin:Vector2, dir:Vector2, reach:float, dmg:float, pierce:int, knock:float, gun:int) -> bool:
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
	var struck := 0
	for i in mini(hits.size(), pierce + 1):
		damage_enemy(hits[i][1], dmg * (1.0 - 0.15 * i), owner, dir, knock, true)
		if i == pierce:
			end = origin + dir * maxf(0.2, hits[i][0])
			struck = 1
	emit("shot", [owner, gun, origin.x, origin.y, end.x, end.y, struck])
	return not hits.is_empty()

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
	emit("hit", [e.p.x, e.p.y, int(round(dmg)), 1 if crit else 0, key, owner])
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
	if variant == 1: coins = ceili(coins * 1.25)
	var credit := owner
	if owner <= 0 and owner != -9 and structures.has(-owner - 100): credit = structures[-owner - 100].owner
	if players.has(credit):
		var q:Dictionary = players[credit]
		q.coins += coins
		q.kills += 1
		give_xp(q, def.xp)
		if credit == owner:
			q.streak = q.streak + 1 if time - q.streak_t < 1.5 else 1
			q.streak_t = time
			if q.streak >= 4: moment(q.streak * 9, "%s derribó %d brotados de un tirón en la noche %d" % [q.name, q.streak, wave])
		if e.k == Data.BOSS: moment(100, "%s dio el golpe final al Gigantón en la noche %d" % [q.name, wave])
		elif e.k == Data.WAILER: moment(40, "%s calló el lamento de la Plañidera en la noche %d" % [q.name, wave])
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
	if rect_distance(Map.BASE, at) < radius: damage_core(dmg * struct_mult * 0.6, at, Data.BOOMER)
	for s in survivors:
		if s.state == 1 and s.p.distance_to(at) < radius: s.hp -= dmg

func damage_structure(cell:int, dmg:float):
	if not structures.has(cell): return
	var s:Dictionary = structures[cell]
	s.hp -= dmg
	var sec := sector_of(nav.center(cell))
	alerts[sec].hit = ALERT_TIME
	if phase == P.NIGHT: sector_damage[sec] += dmg
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

func damage_core(dmg:float, from:Vector2 = Vector2.INF, kind:int = -1, enraged:bool = false):
	var dealt := minf(core, dmg)
	core = maxf(0.0, core - dmg)
	night_low = minf(night_low, core)
	var tag := "%s%s" % [Data.ENEMIES[kind].name if kind >= 0 else "otro", " (rabia)" if enraged else ""]
	core_by_kind[tag] = core_by_kind.get(tag, 0.0) + dealt
	if from.is_finite():
		var sec := sector_of(from)
		alerts[sec].house = ALERT_TIME
		if phase == P.NIGHT: sector_damage[sec] += dmg
	emit("core_hit", [])

func damage_site(i:int, dmg:float):
	if not sites[i].claimed: return
	sites[i].hp -= dmg
	site_hit[i] = ALERT_TIME
	if sites[i].hp <= 0:
		sites[i].claimed = false
		sites[i].hp = 0.0
		nav.active.erase("site%d" % i)
		for m in posts.size():
			if posts[m] == i: posts[m] = -1
		sites[i].max = 200.0
		emit("lost", [i])
		announce("¡Hemos perdido %s!" % Data.SITES[i].name)

# ================================================================== spawning
func new_enemy(kind:int, at:Vector2, goal:String, night:bool) -> Dictionary:
	serial += 1
	var def:Dictionary = Data.ENEMIES[kind]
	var hp:float = def.hp * (1.0 + 0.06 * (wave - 1)) * Data.PARTY_HP[party() - 1]
	if kind == Data.BOSS: hp = def.hp + Data.PARTY_BOSS_HP * (party() - 1) + 400.0 * (wave / 5 - 1)
	var e := {"k":kind, "p":at, "hp":hp, "max":hp, "r":def.r, "goal":goal, "mode":1 if kind in [Data.BREAKER, Data.CLIMBER] else 0,
		"cd":rng.randf_range(0.2, 1.0), "wind":0.0, "target":null, "state":0, "stun":0.0, "burn":0.0, "burner":-1,
		"kv":Vector2.ZERO, "night":night, "victim":-1, "retarget":rng.randf(), "face":Vector2.ZERO, "flash":0.0,
		"lit":false, "climb":false, "fuse":0.0, "home":at, "guard":false, "guard_alert":0.0, "summon":8.0, "slam":0.0,
		"atk":0.0, "surv":null, "stuck":0.0, "speed":def.speed * rng.randf_range(0.92, 1.08),
		"rage":0.0, "wail":Data.WAIL_EVERY * 0.5, "wailing":0.0}
	enemies[serial] = e
	return e

func rise(e:Dictionary) -> Dictionary:
	## Fresh brotados claw out of the ground first: still, harmless, but they can be shot.
	e.rise = Data.RISE_TIME_BOSS if e.k == Data.BOSS else Data.RISE_TIME
	e.face = (Map.BASE_CENTER - e.p).normalized()
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
	var n := clampi(1 + wave / 2, 1, Data.PARTY_FRONTS[party() - 1])
	var all := [0, 1, 2, 3]
	for i in range(3, 0, -1):    # shuffled with the match's own generator so a seed replays the same match
		var j := rng.randi_range(0, i)
		var tmp:int = all[i]
		all[i] = all[j]
		all[j] = tmp
	fronts = all.slice(0, n)
	if wave == 1: fronts = [2]
	if variant == 2:
		for f in all:
			if not f in fronts and fronts.size() < 4:
				fronts.append(f)
				break
	weather = 0 if rng.randf() < 0.55 else (1 if rng.randf() < 0.6 else 2)
	if wave == 1: weather = 0
	night_event = pick_event()
	make_jobs()
	day_plan = {
		"survivor": rng.randf_range(0.25, 0.6) if (wave >= 2 and rng.randf() < 0.6) or wave == 1 else -1.0,
		"drop": rng.randf_range(0.3, 0.75) if (rng.randf() < 0.55 and wave > 1) or variant == 1 else -1.0,
		"horde": rng.randf_range(0.2, 0.7) if wave >= 3 and rng.randf() < 0.35 else -1.0,
	}

func make_jobs():
	## One short job near the plaza and one ambitious job far away. Destinations must be
	## reachable, rewards useful, and a job never repeats yesterday's kind and place.
	last_jobs = jobs.map(func(j): return [j.kind, j.area])
	# an accepted relay is kept until it is installed: it can be done over several visits
	var keep := jobs.filter(func(j): return j.kind == "relevo" and j.state == 1)
	jobs.clear()
	jobs.append_array(keep)
	if keep.size() > 0:
		var near:Array = []
		for attempt in 40:
			var at := Map.BASE_CENTER + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(7.0, 13.0)
			at = Vector2(floorf(at.x) + 0.5, floorf(at.y) + 0.5)
			var c := nav.cell_of(at)
			if c < 0 or nav.solid[c] or nav.blocked_cell(at, 0.5, 0) != -1: continue
			serial += 1
			jobs.append({"id":serial, "kind":"busqueda", "size":"corto", "p":at, "state":0, "progress":0.0, "carrier":-1, "found":true, "mat":5, "coins":3, "risk":"bajo", "area":Map.landmark(at), "spawned":0})
			break
		return
	for size in ["corto", "ambicioso"]:
		for attempt in 40:
			var kind:String = ["busqueda", "transporte", "defensa"][rng.randi_range(0, 2)]
			if size == "ambicioso" and wave >= 2 and not relay and rng.randf() < 0.35: kind = "relevo"
			if size == "corto" and kind == "defensa" and wave < 2: kind = "busqueda"
			var dist := rng.randf_range(7.0, 13.0) if size == "corto" else rng.randf_range(19.0, 33.0)
			var at := Map.BASE_CENTER + Vector2.from_angle(rng.randf() * TAU) * dist
			at = Vector2(floorf(at.x) + 0.5, floorf(at.y) + 0.5)
			if not Map.BOUNDS.grow(-1.5).has_point(at): continue
			var c := nav.cell_of(at)
			if c < 0 or nav.solid[c] or nav.blocked_cell(at, 0.5, 0) != -1: continue
			if nav.distance_at("base", 0, at) >= Nav.INF_D: continue
			var area:String = Map.landmark(at)
			if [kind, area] in last_jobs: continue
			if jobs.any(func(j): return j.area == area): continue
			serial += 1
			var big:bool = size == "ambicioso"
			var risk := "bajo" if dist < 14 else ("medio" if dist < 25 else "alto")
			if kind == "defensa": risk = "medio" if not big else "alto"
			jobs.append({"id":serial, "kind":kind, "size":size, "p":at, "state":0, "progress":0.0, "carrier":-1, "found":kind != "relevo",
				"mat":(rng.randi_range(4, 6) if not big else rng.randi_range(10, 14)) + (3 if kind == "defensa" else 0),
				"coins":(3 if not big else 7) + (2 if kind == "defensa" else 0), "risk":risk, "area":area, "spawned":0})
			break

func job_accept(p:Dictionary, id:int):
	if p.p.distance_to(Map.BOARD) > 3.0: return say(p, "Los encargos se aceptan en el tablón")
	for j in jobs:
		if j.id == id and j.state == 0:
			j.state = 1
			emit("job", [id, 1])
			announce("%s acepta el encargo: %s en %s" % [p.name, Data.JOBS[j.kind].name.to_lower(), j.area])
			log_line({"evento":"encargo_aceptado", "tipo":j.kind, "tamano":j.size, "zona":j.area, "por":p.name})
			return

func job_abandon(p:Dictionary, id:int):
	for j in jobs:
		if j.id == id and j.state == 1:
			finish_job(j, false, "abandonado")
			return

func finish_job(j:Dictionary, ok:bool, why:String = ""):
	j.state = 2 if ok else 3
	for q in players.values():
		if q.cargo == j.id: q.cargo = -1
	if ok:
		materials += j.mat
		for q in players.values():
			q.coins += j.coins
			give_xp(q, 6 if j.size == "corto" else 14)
		announce("¡Encargo cumplido en %s! +%d materiales y +%d fichas para todos" % [j.area, j.mat, j.coins])
	else:
		announce("Encargo de %s %s" % [j.area, why])
	emit("job", [j.id, j.state])
	log_line({"evento":"encargo_cumplido" if ok else "encargo_fallido", "tipo":j.kind, "zona":j.area, "motivo":why, "t_dia":snappedf(phase_len - clock, 0.1)})

func reveal(j:Dictionary, p:Dictionary):
	j.found = true
	emit("found", [j.p.x, j.p.y])
	announce("¡%s ha localizado el relevo eléctrico! Está marcado para todos" % p.name)
	log_line({"evento":"relevo_localizado", "por":p.name, "oficio":Data.ROLES[p.role].name})

func tick_jobs(dt:float):
	for j in jobs:
		if j.state != 1: continue
		if j.kind == "relevo" and not j.found:
			for q in players.values():
				if q.st == 0 and q.p.distance_to(j.p) < 4.0: reveal(j, q)
		if j.kind == "relevo" and j.carrier >= 0:
			if players.has(j.carrier): j.p = players[j.carrier].p
			else: j.carrier = -1
		if j.kind == "transporte" and j.carrier >= 0:
			if players.has(j.carrier): j.p = players[j.carrier].p
			else: j.carrier = -1
		if j.kind == "defensa":
			var inside := false
			for q in players.values():
				if q.st == 0 and q.p.distance_to(j.p) < 4.0: inside = true
			if inside:
				j.progress += dt
				var wave_due := int(j.progress / 8.0)
				if wave_due >= j.spawned and j.spawned < 3:
					j.spawned += 1
					for i in 2 + wave / 2 + (1 if j.size == "ambicioso" else 0):
						var at:Vector2 = j.p + Vector2.from_angle(rng.randf() * TAU) * 11.0
						if nav.blocked_cell(at, 0.4, 1) == -1:
							var e := new_enemy(0 if rng.randf() < 0.7 else 1, at, "base", false)
							e.victim = -1
				if j.progress >= Data.JOB_DEFENSE_TIME: finish_job(j, true)

func set_variant(v:int):
	variant = clampi(v, 0, Data.VARIANTS.size() - 1)
	plan_day()
	if variant == 2:
		phase_len = 60.0
		clock = phase_len
	log_line({"evento":"variante", "reglas":Data.VARIANTS[variant].name})

func pick_event() -> int:
	if wave % 5 == 0 and wave > 0: return 6
	if variant == 1: return 1
	if wave == 1: return 0
	var options := [0, 0]
	for i in range(1, 6):
		if Data.NIGHT_EVENTS[i].from <= wave: options.append(i)
	return options[rng.randi_range(0, options.size() - 1)]

func start_night():
	for j in jobs:
		if j.state == 1 and j.kind != "relevo": finish_job(j, false, "caduca al anochecer")
	phase = P.NIGHT
	clock = 0.0
	for p in players.values(): p.ready = false
	var count := roundi((4 + wave * 2) * Data.PARTY_COUNT[party() - 1]) + claimed_count() * 2
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
	if variant == 2: weights[1] = weights.get(1, 3.0) * 2.0
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
		queue.append(Data.BOSS)
	night_total = queue.size()
	midnight = false
	# Split the night into assaults with a respite between them.
	assault_count = 2 if wave < 3 else 3
	assaults = []
	var per := ceili(float(queue.size()) / assault_count)
	for i in assault_count:
		assaults.append(queue.slice(i * per, mini(queue.size(), (i + 1) * per)))
	if night_event == 6:
		var last:Array = assaults[-1]
		last.erase(Data.BOSS)
		last.insert(0, Data.BOSS)
	queue = assaults.pop_front()
	assault_index = 1
	respite = 0.0
	log_line({"evento":"noche", "noche":wave, "tipo":Data.NIGHT_EVENTS[night_event].name, "frentes":fronts.map(func(f): return Map.FRONT_NAMES[f]), "brotados":night_total, "asaltos":assault_count})
	sector_damage = [0.0, 0.0, 0.0, 0.0]
	core_by_kind = {}
	night_low = 1e9
	spawn_timer = 2.0
	front_turn = rng.randi_range(0, fronts.size() - 1)
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
	# groups take turns between tonight's streets, so every access gets a lull and a lone
	# player has time to run from one side of the house to the other
	front_turn = (front_turn + 1) % fronts.size()
	var front:int = fronts[front_turn]
	log_line({"evento":"grupo", "frente":Map.FRONT_NAMES[front], "tamano":group, "asalto":assault_index})
	for i in group:
		var kind:int = queue.pop_front()
		var e := rise(new_enemy(kind, front_point(front), pick_goal(), true))
		if kind == Data.BOSS:
			e.goal = "base"
			announce("¡Un Gigantón avanza por el %s!" % Map.FRONT_NAMES[front])
	spawn_timer = maxf(2.2, 5.5 - wave * 0.2) * (0.6 if night_event == 2 else 1.0) + active * 0.04
	if party() == 1 and fronts.size() > 1: spawn_timer += Data.SOLO_SWITCH

func check_midnight():
	## Halfway through every night from the second one, the Plañidera arrives.
	if midnight or wave < 2 or night_total <= 0 or night_event == 6: return    # never on a Gigantón night
	var done := 1.0 - float(remaining()) / maxf(1.0, night_total)
	if done < 0.45: return
	midnight = true
	var count := 1 + (1 if players.size() >= 3 else 0) + (1 if wave >= 6 else 0)
	var front:int = fronts[rng.randi_range(0, fronts.size() - 1)]
	for i in count:
		var e := new_enemy(Data.WAILER, front_point(front) + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)), "base", true)
		e.wail = 2.0 + i
	night_total += count
	emit("midnight", [front, count])
	announce("¡Medianoche! %s llora por el %s: callad su lamento" % ["Una plañidera" if count == 1 else "%d plañideras" % count, Map.FRONT_NAMES[front]])
	log_line({"evento":"medianoche", "frente":Map.FRONT_NAMES[front], "planideras":count, "noche":wave})

func wailer_logic(key:int, e:Dictionary, dt:float):
	## Keeps her distance, drifts towards the house and wails to enrage the brotados around her.
	e.wailing = maxf(0.0, e.wailing - dt)
	# she does not hold the night hostage: alone, or after a while, she fades away
	e.life = e.get("life", 0.0) + dt
	var others := 0
	for o in enemies.values(): if o.night and o.k != Data.WAILER: others += 1
	if e.life > 70.0 or (others == 0 and queue.is_empty() and e.life > 6.0):
		enemies.erase(key)
		emit("kill", [e.p.x, e.p.y, e.k, -9])
		announce("La Plañidera se desvanece entre lamentos")
		return
	e.wail -= dt
	if e.wail <= 0 and e.stun <= 0:
		e.wail = Data.WAIL_EVERY
		e.wailing = 1.3
		var touched := 0
		for other in near_enemies(e.p, Data.WAIL_RADIUS):
			if touched >= Data.RAGE_MAX: break
			if other == key or not enemies.has(other): continue
			var o:Dictionary = enemies[other]
			if o.k == Data.WAILER or o.p.distance_to(e.p) > Data.WAIL_RADIUS: continue
			o.rage = Data.RAGE_TIME
			if o.state == 2: wake(o)
			touched += 1
		emit("wail", [e.p.x, e.p.y, touched])
	if e.wailing > 0.5 or e.stun > 0: return
	var dir := Vector2.ZERO
	var near_p:Dictionary = {}
	var nd := 99.0
	for p in players.values():
		if p.st == 0 and p.p.distance_to(e.p) < nd:
			nd = p.p.distance_to(e.p)
			near_p = p
	if not near_p.is_empty() and nd < 5.0:
		dir = (e.p - near_p.p).normalized()
	elif e.p.distance_to(Map.BASE_CENTER) > 9.0:
		var next := nav.next_cell("base", 0, e.p)
		if next >= 0: dir = (nav.center(next) - e.p).normalized()
	else:
		dir = Vector2(cos(time * 0.4 + key), sin(time * 0.4 + key)) * 0.4
	if dir != Vector2.ZERO: e.face = e.face.lerp(dir.normalized(), minf(1.0, 4.0 * dt)).normalized()
	if not near_p.is_empty(): e.face = (near_p.p - e.p).normalized()
	e.p = nav.move(e.p, (dir * e.speed + e.kv) * dt, 0.38, 1)

func start_finale(p:Dictionary):
	## The last night: lights on, every street at once, hold until the final firecracker.
	finale = true
	finale_t = Data.FINALE_TIME
	fronts = [0, 1, 2, 3]
	night_event = 6
	start_night()
	assaults.clear()
	assault_count = 1
	emit("finale", [Data.FINALE_TIME])
	announce("¡%s enciende la verbena! Aguantad %d s hasta la traca final" % [p.name, int(Data.FINALE_TIME)])
	log_line({"evento":"final", "noche":wave})

func finale_tick(dt:float):
	finale_t -= dt
	if queue.is_empty() and night_alive() < 10 + 4 * players.size():
		for i in 6: queue.append(rng.randi_range(0, mini(6, 2 + wave / 2)))
	if finale_t <= 0:
		victory = true
		for key in enemies.keys():
			emit("kill", [enemies[key].p.x, enemies[key].p.y, enemies[key].k, -9])
		enemies.clear()
		queue.clear()
		phase = P.OVER
		report = ["¡La verbena brilla de nuevo! Habéis salvado el barrio en la noche %d" % wave]
		emit("victory", [wave])
		log_line({"evento":"victoria", "noche":wave, "derribos":stats.kills})

func start_dawn():
	phase = P.DAWN
	clock = 14.0
	phase_len = 14.0
	if night_low > 0 and night_low < core_max * 0.2:
		moment(int(70 - night_low / core_max * 100), "La casa aguantó la noche %d con solo %d de resistencia" % [wave, int(night_low)])
	wave += 1
	report = []
	var gain_mat := 5 + (4 if variant == 2 else 0)
	var gain_coin := 5 + wave
	if has_site(3):
		gain_mat += site_boost(3, 8)
		report.append("Almacén: +%d materiales" % site_boost(3, 8))
	if has_site(4): gain_mat += site_boost(4, 3)
	var carp := home_count(0)
	if carp > 0:
		gain_mat += 3 * carp
		report.append("Carpinteros: +%d materiales" % (3 * carp))
	materials += gain_mat
	if has_site(0):
		core = minf(core_max, core + site_boost(0, 40))
		report.append("Taller: casa reparada (+%d)" % site_boost(0, 40))
	for p in players.values():
		if p.st == 2:
			p.st = 0
			p.hp = 60.0
			p.p = Map.PLAYER_SPAWN
			p.coins = int(p.coins * 0.7)
		elif p.st == 1: revive(p, 40.0)
		p.coins += gain_coin + (site_boost(2, 6) if has_site(2) else 0)
		p.hp = minf(p.hpmax, p.hp + (p.hpmax * minf(1.0, 0.5 * (1.0 + 0.5 * site_helpers(1))) if has_site(1) else 20.0))
		if has_site(1): p.med = mini(3, p.med + 1 + (1 if site_helpers(1) > 0 else 0))
		if home_count(3) > 0: p.hp = minf(p.hpmax, p.hp + Data.BAKER_HEAL * home_count(3))
		if has_site(5):
			p.tr = mini(6, p.tr + 1)
			for g in p.guns: if p.res[g] >= 0: p.res[g] = max_reserve(p, g)
		give_xp(p, 10)
	if has_site(2): report.append("Economato: +%d fichas" % site_boost(2, 6))
	for i in community.size():
		if posts[i] >= 0: report.append("%s en %s: bonificación +50%%" % [Data.SURVIVORS[community[i]].name, Data.SITES[posts[i]].name])
	if has_site(1): report.append("Dispensario: curas y botiquines")
	if home_count(3) > 0: report.append("Panadera: +%d de salud para todos" % int(Data.BAKER_HEAL * home_count(3)))
	if has_site(5): report.append("Comisaría: munición y tracas")
	report.push_front("+%d materiales · +%d fichas" % [gain_mat, gain_coin])
	var worst := 0
	for i in 4: if sector_damage[i] > sector_damage[worst]: worst = i
	if sector_damage[worst] > 0:
		report.append("El acceso %s fue el más castigado (%d de daño)%s" % [Map.FRONT_NAMES[worst], int(sector_damage[worst]), " · ¡hay una brecha!" if alerts[worst].breach else ""])
	report.append("Caja común: %d materiales" % materials)
	for i in loot.size():
		if not loot[i] and rng.randf() < 0.85: loot[i] = true
	for i in sites.size():
		if sites[i].claimed:
			sites[i].hp = sites[i].max
			continue
		var guards := 0
		for e in enemies.values(): if e.guard and e.home.distance_to(Map.SITES[i].beacon) < 6: guards += 1
		for g in range(guards, mini(4, 2 + wave / 4)): spawn_guard(i)
	if materials < 8:
		event_drop(Map.PLAYER_SPAWN + Vector2(rng.randf_range(-5, 5), 5.5), true)
		announce("Mala noche: el barrio os manda reservas en un globo junto a la plaza")
		log_line({"evento":"rescate_de_materiales", "materiales":materials})
	emit("dawn", [wave])
	log_line({"evento":"amanecer", "noche":wave - 1, "casa":int(core), "materiales":materials, "danos_por_acceso":{"norte":int(sector_damage[0]), "este":int(sector_damage[1]), "sur":int(sector_damage[2]), "oeste":int(sector_damage[3])}, "dano_casa":rounded_hits(), "informe":report.duplicate()})
	plan_day()

func start_prep():
	phase = P.PREP
	phase_len = 45.0 if variant == 2 else 65.0
	clock = phase_len
	straggler_timer = 18.0

func time_of_day() -> float:
	match phase:
		P.PREP: return lerpf(0.76, 0.30, clock / phase_len)
		P.NIGHT:
			var done := 1.0 - float(remaining()) / maxf(1.0, night_total)
			return fmod(0.80 + 0.32 * clampf(done, 0, 1), 1.0)
		P.DAWN: return lerpf(0.29, 0.13, clock / phase_len)
	return 0.9

func remaining() -> int:
	var n := queue.size() + night_alive()
	for a in assaults: n += a.size()
	return n

func log_line(entry:Dictionary):
	entry["t"] = snappedf(time, 0.1)
	journal.append(entry)

func moment(score:int, text:String):
	if score > best_moment.score: best_moment = {"score":score, "text":text}

func rounded_hits() -> Dictionary:
	var out := {}
	for k in core_by_kind: out[k] = int(core_by_kind[k])
	return out

func reseed(value:int):
	## Replays the same match for a given seed (balance tests compare versions with it).
	rng.seed = value
	for e in enemies.keys(): if enemies[e].guard: enemies.erase(e)
	for i in Map.SITES.size():
		for g in (3 if i == 5 else 2): spawn_guard(i)
	plan_day()

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
	tick_jobs(dt)
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
					rise(new_enemy(0, front_point(rng.randi_range(0, 3)), "base", false))
			if clock <= 0: start_night()
		P.NIGHT:
			if finale:
				finale_tick(dt)
				spawn_tick(dt)
				return
			check_midnight()
			if respite > 0:
				respite -= dt
				if respite <= 0:
					queue = assaults.pop_front()
					assault_index += 1
					spawn_timer = 1.0
					emit("assault", [assault_index, assault_count])
					announce("¡Asalto %d de %d!" % [assault_index, assault_count])
				return
			spawn_tick(dt)
			if queue.is_empty() and night_alive() == 0:
				if assaults.is_empty(): start_dawn()
				else:
					respite = RESPITE + Data.PRIEST_RESPITE * home_count(4)
					emit("respite", [respite])
					announce("Respiro de %d s%s: reparad, reanimad o salid a por la caja del globo" % [int(respite), " (el cura toca la campana)" if home_count(4) > 0 else ""])
					event_drop()
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
	log_line({"evento":"fin", "motivo":reason, "noche":wave, "derribos":stats.kills, "dano_casa":rounded_hits()})
	emit("over", [wave])

func tick_players(dt:float):
	for id in players:
		var p:Dictionary = players[id]
		p.nt = maxf(0, p.nt - dt)
		if p.ping_left > 0:
			p.ping_left -= dt
			if p.ping_left <= 0: p.ping = null
		p.dmg = maxf(0, p.dmg - dt)
		p.ab = maxf(0, p.ab - dt)
		p.buff = maxf(0, p.buff - dt)
		p.melee = maxf(0, p.melee - dt)
		p.cool -= dt
		if p.p.distance_to(p.last_p) > 0.05 or p.fire or p.use:
			if time - p.active > 20.0 and phase != P.OVER:
				log_line({"evento":"espera", "jugador":p.name, "segundos":snappedf(time - p.active, 0.1), "fase":Data.PHASE_NAMES[phase]})
			p.active = time
		p.last_p = p.p
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
		if home_count(1) > 0 and p.p.distance_to(Map.BASE_CENTER) < 9.0:
			p.hp = minf(p.hpmax, p.hp + 2.0 * home_count(1) * dt)
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
				p.tally.revived += 1
				if phase == P.NIGHT and night_alive() >= 6: moment(30 + night_alive(), "%s levantó a %s con %d brotados encima (noche %d)" % [p.name, target.mate.name, night_alive(), wave])
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
				p.tally.freed += 1
				moment(25, "%s liberó a la %s de las garras de los brotados" % [p.name, Data.SURVIVORS[s.kind].name.to_lower()] if s.kind == 1 or s.kind == 3 else "%s liberó al %s de las garras de los brotados" % [p.name, Data.SURVIVORS[s.kind].name.to_lower()])
				announce("%s ha liberado a un %s. ¡Acompañadlo a casa!" % [p.name, Data.SURVIVORS[s.kind].name.to_lower()])
		"drop":
			if p.ht >= p.hm:
				open_drop(p, target.drop)
				p.hkey = ""
		"carry":
			if p.ht >= p.hm:
				var pc:Dictionary = pieces[target.piece]
				pc.state = 2
				pc.carrier = id
				p.carry = target.piece
				p.hkey = ""
				emit("piece_take", [pc.p.x, pc.p.y])
				announce("%s carga con %s" % [p.name, Data.PIECES[target.piece].name])
		"install":
			if p.ht >= p.hm:
				var pc:Dictionary = pieces[p.carry]
				pc.state = 4
				pc.carrier = -1
				pc.p = Map.STAGE
				p.carry = -1
				p.hkey = ""
				give_xp(p, 20)
				moment(15 + 5 * installed_pieces(), "%s instaló %s en el escenario" % [p.name, Data.PIECES[pieces.find(pc)].name.to_lower()])
				emit("install", [installed_pieces()])
				log_line({"evento":"pieza", "jugador":p.name, "instaladas":installed_pieces()})
				announce("Pieza instalada: %d de %d" % [installed_pieces(), pieces.size()] + (". ¡Todo listo para encender la verbena!" if installed_pieces() == pieces.size() else ""))
		"ignite":
			if p.ht >= p.hm:
				p.hkey = ""
				start_finale(p)
		"job_search":
			if p.ht >= p.hm:
				p.hkey = ""
				emit("loot", [target.job.p.x, target.job.p.y])
				finish_job(target.job, true)
		"job_load":
			if p.ht >= p.hm:
				p.hkey = ""
				target.job.carrier = id
				p.cargo = target.job.id
				emit("piece_take", [p.p.x, p.p.y])
				say(p, "Lleva la caja al porche de la casa")
		"job_deliver":
			if p.ht >= p.hm:
				p.hkey = ""
				p.cargo = -1
				if target.job.kind == "relevo":
					relay = true
					target.job.carrier = -1
					target.job.p = Map.RELAY
					log_line({"evento":"relevo_instalado", "por":p.name, "oficio":Data.ROLES[p.role].name})
				finish_job(target.job, true)
		"bundle":
			if p.ht >= p.hm:
				take_bundle(p, target.bundle)
				p.hkey = ""
		"bell":
			if p.ht >= p.hm:
				p.ready = not p.ready
				p.ht = -1000.0  # one toggle per press: release E to ring again
				emit("bell", [Map.BELL.x, Map.BELL.y, 1 if p.ready else 0])
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
	if p.carry >= 0 and Map.STAGE.distance_to(p.p) < 2.8:
		return {"type":"install", "key":"in%d" % p.carry, "label":"Instalando", "time":1.2, "prompt":"Mantén E: instalar %s en el escenario" % Data.PIECES[p.carry].name}
	if p.carry < 0:
		for i in pieces.size():
			var pc:Dictionary = pieces[i]
			if (pc.state == 1 or pc.state == 3) and pc.p.distance_to(p.p) < 2.0:
				return {"type":"carry", "key":"pc%d" % i, "label":"Cargando", "time":0.8, "piece":i, "prompt":"Mantén E: cargar con %s (irás más despacio)" % Data.PIECES[i].name}
	if phase == P.PREP and not finale and installed_pieces() == pieces.size() and Map.STAGE.distance_to(p.p) < 2.8:
		return {"type":"ignite", "key":"ignite", "label":"Encendiendo la verbena", "time":2.0, "prompt":"Mantén E: ¡ENCENDER LA VERBENA! (empieza la noche final)"}
	for j in jobs:
		if j.state != 1: continue
		if j.kind == "busqueda" and j.p.distance_to(p.p) < 2.0:
			return {"type":"job_search", "key":"js%d" % j.id, "label":"Buscando", "time":1.5, "job":j, "prompt":"Mantén E: rebuscar para el encargo"}
		if j.kind == "transporte" and j.carrier < 0 and p.cargo < 0 and p.carry < 0 and j.p.distance_to(p.p) < 2.0:
			return {"type":"job_load", "key":"jl%d" % j.id, "label":"Cargando la caja", "time":0.8, "job":j, "prompt":"Mantén E: cargar la caja del encargo"}
		if j.kind == "transporte" and j.carrier == id and Map.PORCH.distance_to(p.p) < 2.6:
			return {"type":"job_deliver", "key":"jd%d" % j.id, "label":"Entregando", "time":0.8, "job":j, "prompt":"Mantén E: entregar la caja"}
		if j.kind == "relevo" and j.found and j.carrier < 0 and p.cargo < 0 and p.carry < 0 and j.p.distance_to(p.p) < 2.0:
			return {"type":"job_load", "key":"jl%d" % j.id, "label":"Desenganchando el relevo", "time":1.0, "job":j, "prompt":"Mantén E: cargar con el relevo eléctrico"}
		if j.kind == "relevo" and j.carrier == id and Map.RELAY.distance_to(p.p) < 2.6:
			var t := 1.5 if p.role == 0 else 5.0
			return {"type":"job_deliver", "key":"jd%d" % j.id, "label":"Instalando el relevo", "time":t, "job":j, "prompt":"Mantén E: instalar el relevo en el cuadro (%s)" % ("rápido, eres ingeniera" if p.role == 0 else "lento: la ingeniera lo haría en 1,5 s")}
	for b in bundles:
		if b.owner != id and b.p.distance_to(p.p) < 2.0:
			var who:String = players[b.owner].name if players.has(b.owner) else "un vecino"
			return {"type":"bundle", "key":"bu%d" % b.id, "label":"Recogiendo el lote", "time":0.6, "bundle":b, "prompt":"Mantén E: recoger el lote de %s" % who}
	if phase == P.PREP and Map.BELL.distance_to(p.p) < 1.9:
		var txt := "cancelar «listo»" if p.ready else "tocar la campana (listos para la noche)"
		return {"type":"bell", "key":"bell", "label":"Tocando la campana", "time":0.35, "prompt":"Mantén E: " + txt}
	var best := -1
	var best_d := 0.0
	for i in loot.size():
		if not loot[i]: continue
		# cars are solid, so they can be searched from a little further away
		var d:float = Map.LOOT[i].p.distance_to(p.p) - (2.6 if Map.LOOT[i].kind == 1 else 1.9)
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
	if Map.BOARD.distance_to(p.p) < 2.2 and phase != P.NIGHT: hint = "E: ver el tablón de encargos"
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
	var mat := rng.randi_range(8, 12) + (6 if d.get("rich", false) else 0)
	materials += mat
	p.coins += 6
	p.tr = mini(6, p.tr + 1)
	for g in p.guns: if p.res[g] >= 0: p.res[g] = max_reserve(p, g)
	give_xp(p, 8)
	emit("loot", [d.p.x, d.p.y])
	announce("%s abre los suministros: +%d materiales" % [p.name, mat])

# ------------------------------------------------------------------ day events
func pick_survivor() -> int:
	## Someone the community does not have yet, when possible.
	var missing := []
	for k in Data.SURVIVORS.size(): if not k in community: missing.append(k)
	if missing.is_empty(): return rng.randi_range(0, Data.SURVIVORS.size() - 1)
	return missing[rng.randi_range(0, missing.size() - 1)]

func price(base:int) -> int:
	return Data.shop_price(base, community, posts)

func event_survivor():
	if survivors.size() > 0 or community.size() >= 6: return
	var doors := Map.house_doors()
	var at:Vector2 = doors[rng.randi_range(0, doors.size() - 1)]
	serial += 1
	survivors.append({"id":serial, "p":at, "kind":pick_survivor(), "state":0, "hp":70.0})
	for i in 2:
		var e := new_enemy(0, at + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)), "base", false)
		if nav.blocked_cell(e.p, e.r, 1) != -1: e.p = at
		e.state = 2
		e.guard = true
		e.home = e.p
	emit("survivor", [at.x, at.y])
	announce("Se oyen gritos: hay un vecino atrapado")

func event_drop(at:Vector2 = Vector2.INF, rich:bool = false):
	if not at.is_finite(): at = Map.DROP_SPOTS[rng.randi_range(0, Map.DROP_SPOTS.size() - 1)]
	serial += 1
	drops.append({"id":serial, "p":at, "t":5.0, "rich":rich})
	emit("drop", [at.x, at.y])
	announce("¡Un globo de feria suelta suministros!")

func event_horde():
	var front := rng.randi_range(0, 3)
	for i in 4 + wave / 2:
		rise(new_enemy(0 if rng.randf() < 0.7 else 1, front_point(front), "base", false))
	announce("Una horda errante entra por el %s" % Map.FRONT_NAMES[front])

# ------------------------------------------------------------------ world
func tick_world(dt:float):
	for pc in pieces:
		if pc.state == 2 and players.has(pc.carrier): pc.p = players[pc.carrier].p
	for a in alerts:
		a.hit = maxf(0.0, a.hit - dt)
		a.house = maxf(0.0, a.house - dt)
	for i in site_hit.size(): site_hit[i] = maxf(0.0, site_hit[i] - dt)
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
			posts.append(-1)
			stats.rescued += 1
			emit("joined", [s.kind])
			announce("Un %s se une a la comunidad: %s" % [Data.SURVIVORS[s.kind].name.to_lower(), Data.SURVIVORS[s.kind].desc])
			continue
		var dir:Vector2 = (nav.center(next) - s.p).normalized()
		s.p = nav.move(s.p, dir * 2.8 * dt, 0.3, 0)
	if home_count(2) > 0 and phase == P.NIGHT:
		vigia_timer -= dt
		if vigia_timer <= 0:
			vigia_timer = 1.0 / home_count(2)
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
				var cands := []
				for key in near_enemies(c, reach):
					var e:Dictionary = enemies[key]
					var d:float = e.p.distance_to(c)
					if d < reach and nav.clear_line(c, e.p): cands.append([d, key])
				if cands.size() > 0:
					cands.sort_custom(func(x, y): return x[0] < y[0])
					s.cool = 0.36 * (0.78 if near_generator(cell) else 1.0) * (0.85 if relay else 1.0)
					# every stacked turret fires, each at its own target when there are several
					for h in mini(s.lvl + 1, 3):
						var pick:Array = cands[h % cands.size()]
						if not enemies.has(pick[1]): continue
						var e:Dictionary = enemies[pick[1]]
						var dir:Vector2 = (e.p - c).normalized()
						if h == 0: s.aim = dir.angle()
						emit("shot", [-100 - cell, 7, c.x + dir.x * 0.4, c.y + dir.y * 0.4, e.p.x, e.p.y, h])
						damage_enemy(pick[1], 11.0 + 2.0 * s.lvl, -100 - cell, dir, 0.15)
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
			if not buckets.has(key): continue
			for k in buckets[key]:
				if enemies.has(k): out.append(k)  # skip enemies killed earlier this tick
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
		if e.get("rise", 0.0) > 0:
			e.rise -= dt
			continue
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
		e.rage = maxf(0.0, e.rage - dt)
		if e.k == Data.WAILER:
			wailer_logic(key, e, dt)
			continue
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
		if e.rage > 0: spd *= Data.RAGE_SPEED
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
				e.stuck = 0.0
				var here := nav.cell_of(e.p)
				e.jams = e.get("jams", 0) + 1 if e.get("jam_cell", -1) == here else 1
				e.jam_cell = here
				var ahead := nav.next_cell(e.goal, e.mode, e.p) if e.jams >= 3 else -1
				if ahead >= 0 and not (structures.has(ahead) and Data.STRUCTURES[structures[ahead].k].block):
					e.p = nav.center(ahead)    # wedged in a corner too narrow for its size: never hold the night hostage
					e.jams = 0
				else:
					e.p = nav.move(e.p, dir * 0.3, 0.2, 2 if e.k == Data.CLIMBER else 1)
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
		"core": damage_core(dmg * minf(def.struct, Data.HOUSE_STRUCT_CAP) * 0.5, e.p, e.k, e.rage > 0)
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
		var n := 2 if party() <= 2 else 3
		for i in n:
			var at:Vector2 = e.p + Vector2.from_angle(TAU * i / float(n)) * 2.2
			if nav.blocked_cell(at, 0.4, 1) == -1: rise(new_enemy(0, at, "base", true))
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
	if rect_distance(Map.BASE, e.p) < 3.0: damage_core(Data.SLAM_HOUSE, e.p, Data.BOSS)

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
			if rect_distance(Map.BASE, at) < 0.8: damage_core(pr.dmg * 0.5, pr.from, Data.SPITTER)
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
		if e.get("rage", 0.0) > 0: flags |= 256
		if e.get("wailing", 0.0) > 0: flags |= 512
		if e.get("rise", 0.0) > 0: flags |= 1024
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
			"rl":p.rl, "rlmax":p.rlmax, "ab":p.ab, "buff":p.buff, "med":p.med, "tr":p.tr, "kills":p.kills, "helped":p.helped, "carry":p.carry, "cargo":p.cargo, "rank":p.get("rank", 1),
			"notice":p.notice if p.nt > 0 else "", "hold":p.hold, "hk":p.hkey, "ht":p.ht, "hm":p.hm, "prompt":p.prompt, "ready":p.ready,
			"roll":p.roll, "fix":p.fix, "ping":p.ping, "ping_left":p.ping_left, "dmg":p.dmg, "fire":p.fire and p.rl <= 0, "use":p.use}
		if phase == P.OVER: pl[id].tl = p.tally.duplicate()    # the end screen's numbers, only once
	var si := []
	for s in sites: si.append([s.claimed, s.hp, s.max])
	var sv := []
	for s in survivors: sv.append([s.id, s.p.x, s.p.y, s.kind, s.state])
	var dr := []
	for d in drops: dr.append([d.id, d.p.x, d.p.y, d.t])
	var sk := []
	for s in strikes: sk.append([s.p.x, s.p.y, s.t])
	var br := []
	for a in alerts: br.append_array([a.hit, 1 if a.breach else 0, a.house])
	var boss := []
	for key in enemies:
		if enemies[key].k == Data.BOSS: boss = [key, enemies[key].hp / enemies[key].max]
	return {"ph":phase, "w":wave, "c":clock, "cl":phase_len, "tod":time_of_day(), "core":core, "cmax":core_max, "clvl":core_level,
		"mat":materials, "ev":night_event, "wx":weather, "fr":fronts, "rem":remaining(), "rs":respite, "as":[assault_index, assault_count], "bu":bundles.map(func(b): return [b.id, b.p.x, b.p.y, b.owner]), "tot":night_total,
		"pl":pl, "en":en, "st":st, "si":si, "lo":loot.duplicate(), "pr":pr, "sv":sv, "dr":dr, "cm":community.duplicate(), "cp":posts.duplicate(), "var":variant,
		"fx":events.duplicate(), "rep":report, "boss":boss, "sk":sk, "stats":stats, "time":time, "cc":claim_cost(), "br":br, "pc":pieces.map(func(pc): return [pc.state, pc.p.x, pc.p.y, pc.carrier]), "fin":finale_t if finale else -1.0, "vic":victory, "mid":match_id, "jobs":jobs.map(func(j): return [j.id, j.kind, j.size, j.p.x, j.p.y, j.state, j.mat, j.coins, j.progress, j.carrier, j.risk, j.area, j.get("found", true)]), "relay":relay, "sh":site_hit.duplicate(), "best":best_moment.text if phase == P.OVER else ""}

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
