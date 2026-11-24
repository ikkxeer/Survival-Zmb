extends RefCounted
## Procedural "toy" mesh builder. Appends bevelled boxes, cylinders, ellipsoids and roofs
## with vertex colours into one buffer and commits them as a single ArrayMesh.
## Vertex colour alpha < 1 marks parts that glow at night (see toon.gdshader).

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()

static func glow(c:Color, amount:float = 1.0) -> Color:
	return Color(c.r, c.g, c.b, 1.0 - clampf(amount, 0.0, 1.0) * 0.999)

func is_empty() -> bool:
	return verts.is_empty()

func clear():
	verts.clear()
	norms.clear()
	cols.clear()
	idx.clear()

func commit(mesh:ArrayMesh = null) -> ArrayMesh:
	if mesh == null: mesh = ArrayMesh.new()
	if verts.is_empty(): return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	# Godot treats clockwise triangles as front faces; the builders emit counter-clockwise.
	var flipped := idx.duplicate()
	for i in range(0, flipped.size(), 3):
		var t := flipped[i + 1]
		flipped[i + 1] = flipped[i + 2]
		flipped[i + 2] = t
	arrays[Mesh.ARRAY_INDEX] = flipped
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _shade(c:Color, y01:float, grad:float) -> Color:
	if grad <= 0.0: return c
	var f := lerpf(1.0 - grad, 1.0, clampf(y01, 0.0, 1.0))
	return Color(c.r * f, c.g * f, c.b * f, c.a)

# ------------------------------------------------------------------ box
func box(xf:Transform3D, size:Vector3, c:Color, r:float = 0.06, grad:float = 0.0, seg:int = 1):
	var h := size * 0.5
	r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.98)
	if r < 0.005:
		_flat_box(xf, h, c, grad)
		return
	var inner := h - Vector3(r, r, r)
	var nb := xf.basis.orthonormalized()
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var cu := _coords(h[u], inner[u], seg)
			var cv := _coords(h[v], inner[v], seg)
			var base := verts.size()
			var n := cu.size()
			for i in n:
				for j in n:
					var p := Vector3()
					p[axis] = sgn * h[axis]
					p[u] = cu[i]
					p[v] = cv[j]
					var cl := p.clamp(-inner, inner)
					var d := (p - cl)
					var nn := d.normalized() if d.length_squared() > 1e-9 else Vector3.ZERO
					if nn == Vector3.ZERO: nn[axis] = sgn
					var pos := cl + nn * r
					verts.append(xf * pos)
					norms.append((nb * nn).normalized())
					cols.append(_shade(c, (pos.y + h.y) / (2.0 * h.y), grad))
			for i in n - 1:
				for j in n - 1:
					var a := base + i * n + j
					var b := a + n
					if sgn > 0:
						idx.append_array([a, b, a + 1, a + 1, b, b + 1])
					else:
						idx.append_array([a, a + 1, b, a + 1, b + 1, b])

func _coords(hh:float, ii:float, seg:int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in seg + 1: out.append(lerpf(-hh, -ii, float(k) / seg))
	for k in seg + 1: out.append(lerpf(ii, hh, float(k) / seg))
	return out

func _flat_box(xf:Transform3D, h:Vector3, c:Color, grad:float):
	var nb := xf.basis.orthonormalized()
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var base := verts.size()
			var nn := Vector3()
			nn[axis] = sgn
			for k in 4:
				var p := Vector3()
				p[axis] = sgn * h[axis]
				p[u] = h[u] * (-1.0 if k < 2 else 1.0)
				p[v] = h[v] * (-1.0 if k % 2 == 0 else 1.0)
				verts.append(xf * p)
				norms.append((nb * nn).normalized())
				cols.append(_shade(c, (p.y + h.y) / (2.0 * h.y), grad))
			if sgn > 0: idx.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3])
			else: idx.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])

# ------------------------------------------------------------------ cylinder / cone
func cylinder(xf:Transform3D, r_bottom:float, r_top:float, height:float, c:Color, sides:int = 12, caps:bool = true, grad:float = 0.0):
	var nb := xf.basis.orthonormalized()
	var hh := height * 0.5
	var base := verts.size()
	var slope := (r_bottom - r_top) / maxf(height, 0.0001)
	for i in sides + 1:
		var a := TAU * i / sides
		var dir := Vector3(cos(a), 0, sin(a))
		var n := Vector3(dir.x, slope, dir.z).normalized()
		verts.append(xf * (dir * r_bottom + Vector3(0, -hh, 0)))
		norms.append((nb * n).normalized())
		cols.append(_shade(c, 0.0, grad))
		verts.append(xf * (dir * r_top + Vector3(0, hh, 0)))
		norms.append((nb * n).normalized())
		cols.append(_shade(c, 1.0, grad))
	for i in sides:
		var a := base + i * 2
		idx.append_array([a, a + 1, a + 2, a + 2, a + 1, a + 3])
	if not caps: return
	for top in [false, true]:
		var rr := r_top if top else r_bottom
		if rr < 0.001: continue
		var y := hh if top else -hh
		var n := Vector3(0, 1 if top else -1, 0)
		var center := verts.size()
		verts.append(xf * Vector3(0, y, 0))
		norms.append((nb * n).normalized())
		cols.append(_shade(c, 1.0 if top else 0.0, grad))
		for i in sides + 1:
			var a := TAU * i / sides
			verts.append(xf * Vector3(cos(a) * rr, y, sin(a) * rr))
			norms.append((nb * n).normalized())
			cols.append(_shade(c, 1.0 if top else 0.0, grad))
		for i in sides:
			if top: idx.append_array([center, center + i + 2, center + i + 1])
			else: idx.append_array([center, center + i + 1, center + i + 2])

# ------------------------------------------------------------------ ellipsoid
func sphere(xf:Transform3D, radii:Vector3, c:Color, lon:int = 12, lat:int = 8, grad:float = 0.0, squash_bottom:float = 1.0):
	var nb := xf.basis.orthonormalized()
	var base := verts.size()
	for j in lat + 1:
		var t := PI * j / lat
		var y := cos(t)
		var ring := sin(t)
		for i in lon + 1:
			var a := TAU * i / lon
			var unit := Vector3(cos(a) * ring, y, sin(a) * ring)
			var p := unit * radii
			if p.y < 0: p.y *= squash_bottom
			var n := Vector3(unit.x / radii.x, unit.y / radii.y, unit.z / radii.z).normalized()
			verts.append(xf * p)
			norms.append((nb * n).normalized())
			cols.append(_shade(c, (y + 1.0) * 0.5, grad))
	for j in lat:
		for i in lon:
			var a := base + j * (lon + 1) + i
			var b := a + lon + 1
			idx.append_array([a, a + 1, b, a + 1, b + 1, b])

# ------------------------------------------------------------------ gable roof
func roof(xf:Transform3D, width:float, height:float, depth:float, c:Color, thick:float = 0.14, r:float = 0.05):
	## Two bevelled slabs meeting at a ridge along local Z, plus a ridge cap.
	var half := width * 0.5
	var slope := sqrt(half * half + height * height)
	var ang := atan2(height, half)
	for side in [-1.0, 1.0]:
		var t := Transform3D(Basis(Vector3(0, 0, 1), -side * ang), Vector3(side * half * 0.5, height * 0.5, 0))
		box(xf * t, Vector3(slope + 0.2, thick, depth), c, r, 0.0, 1)
		var rows := int(slope / 0.45)
		for i in rows:
			var off := -slope * 0.5 + (i + 0.6) * slope / rows
			box(xf * t * Transform3D(Basis(), Vector3(off, thick * 0.5, 0)), Vector3(0.07, 0.05, depth - 0.1), c.darkened(0.12), 0.0)
	box(xf * Transform3D(Basis(), Vector3(0, height + thick * 0.15, 0)), Vector3(0.22, 0.16, depth + 0.06), c.darkened(0.12), 0.06)

func gable(xf:Transform3D, width:float, height:float, depth:float, c:Color):
	## Solid triangular prism used to fill the wall under a roof.
	var nb := xf.basis.orthonormalized()
	var h := width * 0.5
	var d := depth * 0.5
	var pts := [Vector3(-h, 0, 0), Vector3(h, 0, 0), Vector3(0, height, 0)]
	for zs in [-1.0, 1.0]:
		var base := verts.size()
		for p in pts:
			verts.append(xf * (p + Vector3(0, 0, zs * d)))
			norms.append((nb * Vector3(0, 0, zs)).normalized())
			cols.append(c)
		if zs > 0: idx.append_array([base, base + 1, base + 2])
		else: idx.append_array([base, base + 2, base + 1])

func quad(xf:Transform3D, size:Vector2, c:Color):
	## Flat horizontal quad (y up), centred.
	var nb := xf.basis.orthonormalized()
	var base := verts.size()
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	for p in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz)]:
		verts.append(xf * p)
		norms.append((nb * Vector3.UP).normalized())
		cols.append(c)
	idx.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])

func blade(xf:Transform3D, width:float, height:float, bottom:Color, top:Color):
	## Tapered double-sided triangle for grass; normals point up so it shades like the ground.
	var n := (xf.basis.orthonormalized() * Vector3.UP).normalized()
	var pts := [xf * Vector3(-width * 0.5, 0, 0), xf * Vector3(width * 0.5, 0, 0), xf * Vector3(0, height, 0)]
	var cs := [bottom, bottom, top]
	for side in 2:
		var base := verts.size()
		for i in 3:
			verts.append(pts[i])
			norms.append(n)
			cols.append(cs[i])
		if side == 0: idx.append_array([base, base + 1, base + 2])
		else: idx.append_array([base, base + 2, base + 1])

func disc(xf:Transform3D, radius:float, sides:int, c:Color, center:Color):
	## Flat double-sided fan (flower heads, lily pads).
	var n := (xf.basis.orthonormalized() * Vector3.UP).normalized()
	for side in 2:
		var base := verts.size()
		verts.append(xf * Vector3.ZERO)
		norms.append(n)
		cols.append(center)
		for i in sides:
			var a := TAU * i / sides
			verts.append(xf * Vector3(cos(a) * radius, 0, sin(a) * radius))
			norms.append(n)
			cols.append(c)
		for i in sides:
			var j := (i + 1) % sides
			if side == 0: idx.append_array([base, base + 1 + j, base + 1 + i])
			else: idx.append_array([base, base + 1 + i, base + 1 + j])

# ------------------------------------------------------------------ helpers
static func at(x:float, y:float, z:float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))

static func rot(x:float, y:float, z:float, ry:float, rx:float = 0.0, rz:float = 0.0) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(rx, ry, rz)), Vector3(x, y, z))
