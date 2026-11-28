extends RefCounted
## Static design data shared by the simulation, the presentation and the interface.
## Everything here is plain constants so host and clients always agree.

enum Phase { PREP, NIGHT, DAWN, OVER }
const PHASE_NAMES = ["Preparación", "Noche", "Amanecer", "Fin"]

# ---------------------------------------------------------------- roles
const ROLES = [
	{"name":"Ingeniera", "color":"f2a93b", "ability":"Remiendo exprés", "cd":28.0,
		"desc":"Construye un 25% más barato, repara el doble y sus defensas aguantan más. Q repara lo cercano.",
		"speed":1.0, "damage":1.0},
	{"name":"Médico", "color":"6cc6b0", "ability":"Ola de tila", "cd":32.0,
		"desc":"Cura sin gastar materiales y reanima el doble de rápido. Q cura y levanta a quien esté cerca.",
		"speed":1.0, "damage":1.0},
	{"name":"Soldado", "color":"6f8fd8", "ability":"Traca final", "cd":30.0,
		"desc":"+25% de daño, recarga rápida y más munición. Q dispara sin parar durante 6 segundos.",
		"speed":1.0, "damage":1.25},
	{"name":"Exploradora", "color":"e46f7a", "ability":"Carrerilla", "cd":20.0,
		"desc":"Corre más, rebusca el doble de rápido y encuentra más botín. Q acelera y protege 5 segundos.",
		"speed":1.18, "damage":1.0},
]
const XP_LEVELS = [0, 30, 80, 160, 280, 450]

# ---------------------------------------------------------------- weapons
# kind: hit = hitscan, lob = arcing explosive, flame = short cone
const WEAPONS = [
	{"name":"Lanzacorchos", "kind":"hit", "dmg":22.0, "rate":0.28, "mag":12, "reserve":-1, "reload":1.0,
		"range":13.0, "spread":0.04, "pellets":1, "pierce":0, "knock":0.35, "price":0, "ammo_price":0,
		"up":[8,14], "req":-1, "color":"f6c75a", "desc":"Pistola de feria fiable con munición infinita."},
	{"name":"Trabuco de confeti", "kind":"hit", "dmg":12.0, "rate":0.78, "mag":6, "reserve":30, "reload":1.6,
		"range":7.5, "spread":0.42, "pellets":7, "pierce":0, "knock":0.9, "price":12, "ammo_price":3,
		"up":[10,16], "req":-1, "color":"e86f8a", "desc":"Escopeta: barre grupos a corta distancia y los empuja."},
	{"name":"Metralleta de petardos", "kind":"hit", "dmg":11.0, "rate":0.085, "mag":32, "reserve":128, "reload":1.4,
		"range":11.0, "spread":0.11, "pellets":1, "pierce":0, "knock":0.12, "price":16, "ammo_price":4,
		"up":[12,18], "req":-1, "color":"8fd06a", "desc":"Subfusil de cadencia altísima. Gasta munición deprisa."},
	{"name":"Carabina de feria", "kind":"hit", "dmg":31.0, "rate":0.16, "mag":24, "reserve":96, "reload":1.6,
		"range":16.0, "spread":0.03, "pellets":1, "pierce":1, "knock":0.25, "price":22, "ammo_price":4,
		"up":[14,20], "req":-1, "color":"6fb6e8", "desc":"Rifle de asalto preciso que atraviesa a un enemigo."},
	{"name":"Rifle de tómbola", "kind":"hit", "dmg":130.0, "rate":1.05, "mag":5, "reserve":20, "reload":2.0,
		"range":28.0, "spread":0.0, "pellets":1, "pierce":5, "knock":0.8, "price":26, "ammo_price":5,
		"up":[16,22], "req":5, "color":"b48be8", "desc":"Francotirador. Atraviesa filas enteras. Requiere la Comisaría."},
	{"name":"Lanzatracas", "kind":"lob", "dmg":95.0, "rate":0.95, "mag":4, "reserve":12, "reload":2.2,
		"range":13.0, "spread":0.0, "pellets":1, "pierce":0, "knock":1.4, "price":30, "ammo_price":6,
		"up":[16,24], "req":5, "color":"f08a4b", "desc":"Explosivos en parábola con daño en área. Requiere la Comisaría."},
	{"name":"Soplete de verbena", "kind":"flame", "dmg":7.0, "rate":0.06, "mag":90, "reserve":180, "reload":1.8,
		"range":5.2, "spread":0.5, "pellets":1, "pierce":99, "knock":0.05, "price":28, "ammo_price":5,
		"up":[14,20], "req":4, "color":"ffb14a", "desc":"Chorro de chispas en cono que quema. Requiere la Gasolinera."},
]
const MELEE = {"name":"Sartén", "dmg":34.0, "rate":0.5, "range":1.9, "arc":1.9, "knock":1.6}
const GRENADE = {"dmg":120.0, "radius":2.9, "range":11.0, "price":4}
const MEDKIT = {"heal":55.0, "price":6}

# ---------------------------------------------------------------- enemies
const ENEMIES = [
	{"name":"Brotado", "hp":50.0, "speed":1.75, "dmg":9.0, "cd":1.1, "struct":1.0, "r":0.38, "coins":1, "xp":2, "from":1},
	{"name":"Corredor", "hp":30.0, "speed":3.4, "dmg":6.0, "cd":0.7, "struct":0.6, "r":0.32, "coins":1, "xp":2, "from":2},
	{"name":"Cabezudo", "hp":230.0, "speed":1.15, "dmg":22.0, "cd":1.6, "struct":1.6, "r":0.62, "coins":4, "xp":6, "from":3},
	{"name":"Derribador", "hp":120.0, "speed":1.55, "dmg":10.0, "cd":1.3, "struct":4.5, "r":0.5, "coins":3, "xp":5, "from":3},
	{"name":"Trepador", "hp":55.0, "speed":2.3, "dmg":8.0, "cd":0.9, "struct":0.5, "r":0.36, "coins":2, "xp":3, "from":4},
	{"name":"Escupidor", "hp":60.0, "speed":1.5, "dmg":13.0, "cd":2.4, "struct":1.0, "r":0.45, "coins":2, "xp":4, "from":4},
	{"name":"Petardero", "hp":45.0, "speed":2.05, "dmg":40.0, "cd":0.7, "struct":2.2, "r":0.4, "coins":2, "xp":4, "from":5},
	{"name":"Gigantón", "hp":2000.0, "speed":1.0, "dmg":34.0, "cd":2.2, "struct":4.0, "r":1.25, "coins":25, "xp":60, "from":5},
	# Only at midnight, from the second night on: wails to send the brotados around her into a frenzy.
	{"name":"Plañidera", "hp":170.0, "speed":1.7, "dmg":7.0, "cd":1.2, "struct":0.3, "r":0.42, "coins":8, "xp":10, "from":2},
]
const BOSS := 7
const CLIMBER := 4
const BREAKER := 3
const SPITTER := 5
const BOOMER := 6
const WAILER := 8
const RISE_TIME := 1.7        # seconds a brotado spends clawing out of the ground
const RISE_TIME_BOSS := 2.6
const WAIL_EVERY := 8.0      # seconds between wails
const WAIL_RADIUS := 6.0
const RAGE_TIME := 4.0       # how long a wail keeps brotados enraged
const RAGE_MAX := 6          # brotados one wail can enrage
const RAGE_SPEED := 1.25

# Difficulty by party size (index = players connected - 1). A small party gets fewer and
# slightly weaker brotados and fewer streets at once, so the load per head stays similar.
const PARTY_COUNT = [1.0, 1.4, 1.8, 2.2]     # multiplies the night's base of 4 + 2 per night
const PARTY_HP = [0.85, 0.92, 1.0, 1.0]
const PARTY_FRONTS = [2, 3, 4, 4]            # most streets attacking at once
const PARTY_BOSS_HP := 450.0                 # extra Gigantón health per player beyond the first
const SOLO_SWITCH := 3.0
const HOUSE_STRUCT_CAP := 2.5    # the breakers' and the Gigantón's wrecking bonus is for defences, not the house
const SLAM_HOUSE := 30.0         # house damage of a Gigantón stomp next to it                     # extra seconds before a group comes down another street when alone

# ---------------------------------------------------------------- structures
# block: zombies (except climbers) must go round or break it. vault: players can hop over.
const STRUCTURES = [
	{"name":"Barricada", "cost":3, "hp":[120.0,220.0,380.0], "up":[4,6], "block":true, "vault":true, "electric":false,
		"desc":"Bloquea el paso. Mejora a tablones y a chapa.", "key":"1"},
	{"name":"Alambrada", "cost":2, "hp":[60.0,100.0,150.0], "up":[3,4], "block":false, "vault":true, "electric":false,
		"desc":"Frena a los brotados y los araña.", "key":"2"},
	{"name":"Bobina", "cost":6, "hp":[70.0,110.0,160.0], "up":[5,7], "block":true, "vault":false, "electric":true,
		"desc":"Descarga eléctrica en cadena. Se apaga en un apagón sin generador.", "key":"3"},
	{"name":"Torreta", "cost":9, "hp":[90.0,140.0,200.0], "up":[6,8], "block":true, "vault":false, "electric":true,
		"desc":"Dispara sola a lo que entre en su radio. Pon otra encima para hacerla doble y triple.", "key":"4"},
	{"name":"Generador", "cost":8, "hp":[150.0,220.0], "up":[6], "block":true, "vault":false, "electric":false,
		"desc":"Mantiene la corriente en un apagón y acelera las torretas cercanas.", "key":"5"},
	{"name":"Foco", "cost":4, "hp":[60.0,90.0], "up":[3], "block":true, "vault":false, "electric":true,
		"desc":"Ilumina y deslumbra: los brotados bajo su luz van lentos y reciben más daño.", "key":"6"},
	{"name":"Banco de taller", "cost":10, "hp":[120.0,180.0], "up":[8], "block":true, "vault":false, "electric":false,
		"desc":"Repara las defensas cercanas poco a poco. Con E fabrica tracas.", "key":"7"},
	{"name":"Mina de petardos", "cost":3, "hp":[1.0], "up":[], "block":false, "vault":true, "electric":false,
		"desc":"Estalla al pisarla. Un solo uso.", "key":"8"},
]
const S_WALL := 0
const S_WIRE := 1
const S_COIL := 2
const S_TURRET := 3
const S_GEN := 4
const S_LIGHT := 5
const S_BENCH := 6
const S_MINE := 7

# ---------------------------------------------------------------- territory
const SITES = [
	{"name":"Taller", "bonus":"Defensas 1 material más baratas. Repara la casa al amanecer.", "color":"e39a4c"},
	{"name":"Dispensario", "bonus":"Cura al equipo y entrega un botiquín al amanecer.", "color":"7cd0c0"},
	{"name":"Economato", "bonus":"+6 fichas para cada vecino al amanecer.", "color":"f0c75c"},
	{"name":"Almacén", "bonus":"+8 materiales al amanecer.", "color":"b88d64"},
	{"name":"Gasolinera", "bonus":"Corriente garantizada y Soplete de verbena en la tienda.", "color":"e86a5c"},
	{"name":"Comisaría", "bonus":"Rifle de tómbola y Lanzatracas en la tienda. Munición y una traca al amanecer.", "color":"6f8fd8"},
]
# The end goal: four pieces hidden in properties, carried to the plaza stage.
const PIECES = [
	{"site":0, "name":"Cuadro eléctrico", "color":"4cc9f0"},
	{"site":3, "name":"Guirnalda maestra", "color":"ffd166"},
	{"site":2, "name":"Altavoces", "color":"f78fb3"},
	{"site":4, "name":"Bidón de gasoil", "color":"e86a5c"},
]
const FINALE_TIME := 120.0
const JOBS = {
	"busqueda": {"name":"Búsqueda", "verb":"Busca", "desc":"Rebusca en el punto marcado"},
	"transporte": {"name":"Transporte", "verb":"Trae", "desc":"Carga la caja marcada y llévala al porche"},
	"defensa": {"name":"Defensa", "verb":"Aguanta", "desc":"Quédate en la zona marcada mientras llegan brotados"},
	"relevo": {"name":"Relevo eléctrico", "verb":"Encuentra", "desc":"Un relevo perdido: la exploradora lo localiza con Q (o búscalo a pie) y la ingeniera lo instala rápido en el cuadro junto a la casa. Da corriente garantizada y torretas más rápidas"},
}
const JOB_DEFENSE_TIME := 25.0
# Optional rule sets, chosen before the match, that change routes and construction.
const VARIANTS = [
	{"name":"Clásica", "desc":"Las reglas de siempre."},
	{"name":"Barrio a oscuras", "desc":"Todas las noches hay apagón, salvo las de gigantes: las defensas eléctricas necesitan generador o la Gasolinera. Cada día cae un globo de suministros y los brotados sueltan un 25 % más de fichas."},
	{"name":"Estampida", "desc":"Un frente más cada noche y el doble de corredores desde la primera. El día dura 45 s, pero cada amanecer trae 4 materiales extra: hay que construir rápido y en varios lados."},
]
const CORE_UPGRADE = {"mat":[10,14,18], "coins":[8,12,16], "hp":50.0}

# ---------------------------------------------------------------- loot nodes
const LOOT = [
	{"name":"Contenedor", "time":1.2, "mat":[2,3], "coins":[0,1]},
	{"name":"Coche abandonado", "time":2.0, "mat":[3,5], "coins":[1,2]},
	{"name":"Palés", "time":1.4, "mat":[4,6], "coins":[0,0]},
	{"name":"Caja de feria", "time":1.2, "mat":[0,1], "coins":[2,4]},
	{"name":"Botiquín de pared", "time":1.5, "mat":[0,0], "coins":[0,1]},
	{"name":"Caja de munición", "time":1.5, "mat":[0,0], "coins":[0,1]},
]

# ---------------------------------------------------------------- events
const NIGHT_EVENTS = [
	{"name":"Serena", "desc":"Una noche tranquila... de momento.", "from":1},
	{"name":"Apagón", "desc":"Sin corriente: las defensas eléctricas necesitan un generador.", "from":2},
	{"name":"Estampida", "desc":"Llegan muchos corredores en tropel.", "from":2},
	{"name":"Niebla", "desc":"Niebla espesa. Los trepadores aprovechan para colarse.", "from":3},
	{"name":"Tormenta", "desc":"Caen rayos al azar. Cuidado con tus defensas.", "from":3},
	{"name":"Verbena roja", "desc":"Luna roja: brotados más rápidos que sueltan más fichas.", "from":4},
	{"name":"Noche de gigantes", "desc":"Un Gigantón encabeza la oleada.", "from":5},
]
const WEATHER = ["Despejado", "Nubes", "Lluvia"]
const SURVIVORS = [
	{"name":"Carpintero", "desc":"+3 materiales cada amanecer."},
	{"name":"Enfermera", "desc":"Cura poco a poco a quien esté en la plaza."},
	{"name":"Vigía", "desc":"Dispara desde el tejado de la casa."},
	{"name":"Panadera", "desc":"Reparte comida al amanecer: +30 de salud para todos."},
	{"name":"Cura", "desc":"Su campana alarga los respiros entre asaltos (+8 s)."},
	{"name":"Feriante", "desc":"Rebaja la tienda un 20 %."},
]
const BAKER_HEAL := 30.0
const PRIEST_RESPITE := 8.0
const FAIR_DISCOUNT := 0.8

static func at_home(cm:Array, cp:Array, kind:int) -> int:
	## Community members of a kind living at the house (not sent to a property).
	var n := 0
	for i in cm.size():
		if int(cm[i]) == kind and (i >= cp.size() or int(cp[i]) < 0): n += 1
	return n

static func shop_price(base:int, cm:Array, cp:Array) -> int:
	## Prices in the shop: the stall-keeper at home takes a fifth off.
	return maxi(1, roundi(base * FAIR_DISCOUNT)) if at_home(cm, cp, 5) > 0 else base

static func level_for(xp:int) -> int:
	var lvl := 1
	for i in XP_LEVELS.size():
		if xp >= XP_LEVELS[i]: lvl = i + 1
	return mini(lvl, XP_LEVELS.size())
