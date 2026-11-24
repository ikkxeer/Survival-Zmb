extends RefCounted
## Static layout of the neighbourhood. X grows east, Z grows south (towards the camera).
## Every solid rectangle is aligned to whole metres so the 1 m navigation grid matches it exactly.

const BOUNDS := Rect2(-35, -31, 70, 62)      # where players can walk
const GRID_ORIGIN := Vector2i(-37, -33)       # navigation grid covers a margin for spawns
const GRID_SIZE := Vector2i(74, 66)

const BASE := Rect2(-3, -3, 6, 5)              # the party house; zombies want it gone
const BASE_CENTER := Vector2(0, -0.5)
const BASE_BUILD_RADIUS := 11.5
const SITE_BUILD_RADIUS := 7.5
const PLAYER_SPAWN := Vector2(0, 4.5)
const SHOP_RADIUS := 7.5
const BELL := Vector2(-4.8, 3.4)                # plaza bell: ring it to bring the night forward
const PORCH := Vector2(1.8, 3.4)                 # where supply bundles are left
const RELAY := Vector2(-3.6, -4.0)               # electric panel where a found relay is installed
const BOARD := Vector2(7.2, 3.4)                # noticeboard with the day's jobs
const LANDMARKS = [
	["la plaza", Vector2(0, 0)], ["el parque", Vector2(0, -22)], ["el aparcamiento", Vector2(0, 17)],
	["el Taller", Vector2(26, -1)], ["el Dispensario", Vector2(26, -23)], ["el Economato", Vector2(0, 25)],
	["el Almacén", Vector2(-26, 24)], ["la Gasolinera", Vector2(-25, -1)], ["la Comisaría", Vector2(-26, -23)],
	["las casas del sureste", Vector2(25, 23)], ["la calle norte", Vector2(0, -12)], ["la calle sur", Vector2(0, 12)],
	["la calle oeste", Vector2(-14, 0)], ["la calle este", Vector2(14, 0)],
]
const STAGE := Vector2(-8.2, -1.0)               # festival stage (west of the plaza, facing the house)

# Roads: purely visual, everything is walkable.
const ROADS_H = [-12.0, 12.0]   # z centres of east-west avenues (4 m wide)
const ROADS_V = [-14.0, 14.0]   # x centres of north-south streets (4 m wide)

const SITES = [
	{"rect":Rect2(22,-4,8,6), "beacon":Vector2(19.5,-0.5), "face":Vector2.LEFT},     # Taller
	{"rect":Rect2(22,-27,9,7), "beacon":Vector2(19.5,-23.5), "face":Vector2.LEFT},   # Dispensario
	{"rect":Rect2(-6,22,12,6), "beacon":Vector2(0.5,18.5), "face":Vector2.UP},       # Economato
	{"rect":Rect2(-31,20,10,8), "beacon":Vector2(-18.5,23.5), "face":Vector2.RIGHT}, # Almacén
	{"rect":Rect2(-33,-5,5,6), "beacon":Vector2(-18.5,-0.5), "face":Vector2.RIGHT},  # Gasolinera
	{"rect":Rect2(-31,-27,9,7), "beacon":Vector2(-18.5,-23.5), "face":Vector2.RIGHT},# Comisaría
]

# Decorative homes: rect and the side their front door faces.
const HOUSES = [
	{"rect":Rect2(-32,5,5,4), "face":Vector2.UP, "style":0},
	{"rect":Rect2(-25,5,5,4), "face":Vector2.DOWN, "style":1},
	{"rect":Rect2(-25,-9,5,4), "face":Vector2.UP, "style":2},
	{"rect":Rect2(18,5,5,4), "face":Vector2.DOWN, "style":1},
	{"rect":Rect2(26,5,5,4), "face":Vector2.DOWN, "style":0},
	{"rect":Rect2(18,-9,5,4), "face":Vector2.UP, "style":2},
	{"rect":Rect2(19,17,5,4), "face":Vector2.UP, "style":0},
	{"rect":Rect2(27,17,5,4), "face":Vector2.UP, "style":2},
	{"rect":Rect2(19,25,5,4), "face":Vector2.DOWN, "style":1},
	{"rect":Rect2(27,25,5,4), "face":Vector2.DOWN, "style":0},
	{"rect":Rect2(-29,-18,5,4), "face":Vector2.UP, "style":1},
	{"rect":Rect2(26,-18,5,4), "face":Vector2.UP, "style":2},
	{"rect":Rect2(-31,15,5,4), "face":Vector2.UP, "style":2},
]

# Small solid props: fountain, kiosk, petrol pumps, parked cars, tree trunks.
const PROPS = [
	{"rect":Rect2(-2,-25,4,4), "kind":"fountain"},
	{"rect":Rect2(6,-22,3,3), "kind":"kiosk"},
	{"rect":Rect2(-25,-3,1,1), "kind":"pump"},
	{"rect":Rect2(-25,0,1,1), "kind":"pump"},
	{"rect":Rect2(-22,-3,1,1), "kind":"pump"},
	{"rect":Rect2(-22,0,1,1), "kind":"pump"},
]
const TREES = [
	Vector2(-9.5,-28.5), Vector2(-6.5,-17.5), Vector2(-9.5,-21.5), Vector2(8.5,-28.5), Vector2(9.5,-17.5),
	Vector2(3.5,-29.5), Vector2(-4.5,-29.5), Vector2(-10.5,17.5), Vector2(10.5,17.5),
	Vector2(-19.5,-9.5), Vector2(33.5,-7.5), Vector2(33.5,1.5), Vector2(-33.5,7.5), Vector2(-20.5,16.5),
	Vector2(33.5,22.5), Vector2(-33.5,29.5), Vector2(24.5,-30.5), Vector2(-24.5,-30.5), Vector2(-9.5,8.5),
	Vector2(9.5,-8.5),
]

# Places worth searching during the day. kind indexes Data.LOOT.
const LOOT = [
	{"p":Vector2(-10.5,7.5), "kind":0}, {"p":Vector2(10.5,7.5), "kind":2}, {"p":Vector2(-10.5,-8.5), "kind":2},
	{"p":Vector2(-8.5,-12.5), "kind":1}, {"p":Vector2(6.5,12.5), "kind":1}, {"p":Vector2(-14.5,4.5), "kind":1},
	{"p":Vector2(14.5,-20.5), "kind":1}, {"p":Vector2(-14.5,24.5), "kind":1}, {"p":Vector2(27.5,12.5), "kind":1},
	{"p":Vector2(-27.5,-12.5), "kind":1},
	{"p":Vector2(-4.5,-19.5), "kind":3}, {"p":Vector2(4.5,-26.5), "kind":3}, {"p":Vector2(-8.5,19.5), "kind":0},
	{"p":Vector2(8.5,19.5), "kind":0}, {"p":Vector2(23.5,10.5), "kind":0}, {"p":Vector2(-22.5,10.5), "kind":0},
	{"p":Vector2(-20.5,29.5), "kind":2}, {"p":Vector2(-18.5,27.5), "kind":2}, {"p":Vector2(-23.5,17.5), "kind":2},
	{"p":Vector2(20.5,-22.5), "kind":4}, {"p":Vector2(32.5,-14.5), "kind":4},
	{"p":Vector2(-20.5,-26.5), "kind":5}, {"p":Vector2(-32.5,-14.5), "kind":5},
	{"p":Vector2(30.5,-10.5), "kind":3}, {"p":Vector2(24.5,29.5), "kind":3}, {"p":Vector2(-1.5,29.5), "kind":2},
	{"p":Vector2(-29.5,2.5), "kind":0}, {"p":Vector2(31.5,3.5), "kind":2},
]

# Zombies arrive along the streets. Fronts: 0 north, 1 east, 2 south, 3 west.
const FRONTS = [
	[Vector2(-14,-32.5), Vector2(14,-32.5)],
	[Vector2(36.5,-12), Vector2(36.5,12)],
	[Vector2(-14,32.5), Vector2(14,32.5)],
	[Vector2(-36.5,-12), Vector2(-36.5,12)],
]
const FRONT_NAMES = ["norte", "este", "sur", "oeste"]

# Open ground where balloons can drop supplies.
const DROP_SPOTS = [
	Vector2(0,-16.5), Vector2(-24.5,13.5), Vector2(24.5,13.5), Vector2(-8.5,-27.5), Vector2(29.5,9.5),
	Vector2(-28.5,-8.5), Vector2(12.5,27.5), Vector2(-12.5,27.5), Vector2(31.5,-29.5), Vector2(-31.5,-29.5),
]

static func landmark(p:Vector2) -> String:
	var best:String = LANDMARKS[0][0]
	var bd := INF
	for l in LANDMARKS:
		var d:float = p.distance_to(l[1])
		if d < bd:
			bd = d
			best = l[0]
	return best

const CAR_HALF := Vector2(0.85, 1.6)   # half width (local x) and half length (local z) of a car

static func loot_yaw(i:int) -> float:
	## Orientation of a loot prop; abandoned cars on the east-west avenue lie along it.
	var l:Dictionary = LOOT[i]
	return fmod(l.p.x * 1.7 + l.p.y, 1.0) - 0.5 + (PI * 0.5 if l.kind == 1 and absf(fmod(l.p.y, 24.0) - 12.0) < 3.0 else 0.0)

static func site_car(i:int, local:Vector2, local_yaw:float) -> Array:
	## A car parked next to property i, given in the property's own frame (as world.gd draws it).
	var s:Dictionary = SITES[i]
	var horizontal := absf(s.face.x) > 0.5
	var yaw := atan2(s.face.x, s.face.y)
	var w:float = (s.rect.size.y if horizontal else s.rect.size.x) - 0.2
	var d:float = (s.rect.size.x if horizontal else s.rect.size.y) - 0.2
	var off := Vector2(local.x * w * 0.5 + signf(local.x) * 1.8, d * 0.5 + local.y)
	return [s.rect.get_center() + off.rotated(-yaw), yaw + local_yaw]

static func cars() -> Array:
	## Every car in the neighbourhood as [centre, yaw]. They are solid: nobody walks or shoots through them.
	var list := []
	for i in 4:
		var x:float = [-7.9, -3.4, 3.4, 7.9][i]
		list.append([Vector2(x, 17.4), 0.04 * (i - 1.5)])
	list.append(site_car(1, Vector2(1, -1.2), 0.0))       # ambulance at the Dispensario
	list.append(site_car(5, Vector2(-1, -1.0), PI * 0.5)) # patrol car at the Comisaría
	for i in LOOT.size():
		if LOOT[i].kind == 1: list.append([LOOT[i].p, loot_yaw(i)])
	return list

static func solids() -> Array:
	var list := [BASE]
	for s in SITES: list.append(s.rect)
	for h in HOUSES: list.append(h.rect)
	for p in PROPS: list.append(p.rect)
	for t in TREES: list.append(Rect2(floorf(t.x), floorf(t.y), 1, 1))
	return list

static func house_doors() -> Array:
	var spots := []
	for h in HOUSES:
		var r:Rect2 = h.rect
		spots.append(r.get_center() + h.face * (r.size.y * 0.5 + 1.2 if h.face.y != 0 else r.size.x * 0.5 + 1.2))
	return spots
