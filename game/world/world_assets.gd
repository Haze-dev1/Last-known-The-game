class_name WorldAssets
extends RefCounted
## Shared materials and reusable low-poly instance meshes for the streamed world.
## Material ids and asset ids match tools/world/build.py (M_* and A_*).

var materials: Array[Material] = []
var instance_meshes: Array[Mesh] = []
var water_material: ShaderMaterial


func _init() -> void:
	var terrain := ShaderMaterial.new()
	terrain.shader = load("res://world/shaders/terrain.gdshader")
	var facade := ShaderMaterial.new()
	facade.shader = load("res://world/shaders/facade.gdshader")
	var surface_shader: Shader = load("res://world/shaders/surface.gdshader")
	# 0 terrain, 1 road, 2 paving, 3 facade, 4 roof, 5 rail, 6 concrete, 7 prop
	materials = [terrain, _surface(surface_shader, 1), _surface(surface_shader, 2), facade,
		_surface(surface_shader, 4), _surface(surface_shader, 5), _surface(surface_shader, 6), _surface(surface_shader, 7)]
	water_material = ShaderMaterial.new()
	water_material.shader = load("res://world/shaders/water.gdshader")
	instance_meshes = [_banyan(), _slender(), _shrub(), _grass(), _lamp(), _car(), _bus(), _blob(), _fern()]


func _surface(shader: Shader, kind: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("kind", kind)
	return m


static func _vertex_material(cull_off: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	if cull_off:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Appends a primitive mesh to a SurfaceTool with a flat colour and transform.
static func _add(st: SurfaceTool, prim: PrimitiveMesh, xf: Transform3D, color: Color) -> void:
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for k in idx:
		# vary shade slightly with height so canopies read as volumes
		var v := verts[k]
		st.set_color(color * (0.8 + 0.25 * clampf(v.y + 0.5, 0.0, 1.0)))
		st.set_normal((xf.basis * normals[k]).normalized())
		st.add_vertex(xf * v)


static func _finish(st: SurfaceTool, mat: Material) -> ArrayMesh:
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh


func _sphere(radius: float, rings: int, segments: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.rings = rings
	s.radial_segments = segments
	return s


func _cyl(r_top: float, r_bot: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Banyan (Ficus microcarpa): short thick trunk, broad layered canopy, hanging roots.
func _banyan() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark := Color(0.33, 0.30, 0.25)
	_add(st, _cyl(0.35, 0.6, 4.0, 7), Transform3D(Basis(), Vector3(0, 2.0, 0)), bark)
	for k in 5:
		var a := k * 1.3
		_add(st, _cyl(0.05, 0.08, 3.0, 4), Transform3D(Basis(), Vector3(cos(a) * 2.2, 2.6, sin(a) * 2.2)), bark * 0.9)
	var leaf := Color(0.20, 0.30, 0.13)
	var blobs := [Vector3(0, 5.6, 0), Vector3(2.6, 5.0, 0.8), Vector3(-2.4, 5.2, -0.6), Vector3(0.5, 5.1, 2.5), Vector3(-0.6, 4.9, -2.6), Vector3(0.2, 6.8, 0.3)]
	for k in blobs.size():
		var xf := Transform3D(Basis().scaled(Vector3(1.0, 0.6, 1.0)), blobs[k])
		_add(st, _sphere(2.6 if k < 5 else 2.0, 5, 8), xf, leaf * (0.9 + 0.05 * k))
	return _finish(st, _vertex_material())


## Slender pioneer tree (Macaranga / Mallotus): tall thin trunk, small high crown.
func _slender() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add(st, _cyl(0.12, 0.22, 7.0, 6), Transform3D(Basis(), Vector3(0, 3.5, 0)), Color(0.40, 0.38, 0.33))
	var leaf := Color(0.27, 0.36, 0.16)
	_add(st, _sphere(2.0, 5, 8), Transform3D(Basis().scaled(Vector3(1.0, 0.75, 1.0)), Vector3(0, 7.6, 0)), leaf)
	_add(st, _sphere(1.5, 4, 7), Transform3D(Basis(), Vector3(1.0, 6.6, -0.6)), leaf * 0.92)
	_add(st, _sphere(1.3, 4, 7), Transform3D(Basis(), Vector3(-0.9, 6.9, 0.7)), leaf * 1.05)
	return _finish(st, _vertex_material())


func _shrub() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf := Color(0.24, 0.33, 0.15)
	_add(st, _sphere(0.9, 4, 7), Transform3D(Basis().scaled(Vector3(1.2, 0.8, 1.0)), Vector3(0, 0.55, 0)), leaf)
	_add(st, _sphere(0.6, 4, 6), Transform3D(Basis(), Vector3(0.6, 0.45, 0.4)), leaf * 1.1)
	return _finish(st, _vertex_material())


## Grass / weed tuft: thin crossed blades, double sided.
func _grass() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 7:
		var a := k * 0.9
		var r := 0.12 + 0.05 * (k % 3)
		var base := Vector3(cos(a) * r, 0, sin(a) * r)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.05
		var tip := base * 2.6 + Vector3(0, 0.45 + 0.12 * (k % 3), 0)
		var c := Color(0.30, 0.38, 0.17) if k % 2 == 0 else Color(0.40, 0.42, 0.22)
		st.set_color(c * 0.7)
		st.set_normal(Vector3.UP)
		st.add_vertex(base - side)
		st.add_vertex(base + side)
		st.set_color(c)
		st.add_vertex(tip)
	return _finish(st, _vertex_material(true))


func _fern() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 9:
		var a := k * TAU / 9.0
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a)) * 0.12
		var mid := dir * 0.5 + Vector3(0, 0.45, 0)
		var tip := dir * 1.0 + Vector3(0, 0.2, 0)
		var c := Color(0.22, 0.34, 0.14)
		st.set_normal(Vector3.UP)
		st.set_color(c * 0.7)
		st.add_vertex(Vector3.ZERO)
		st.set_color(c)
		st.add_vertex(mid - side)
		st.add_vertex(mid + side)
		st.add_vertex(mid - side)
		st.set_color(c * 1.1)
		st.add_vertex(tip)
		st.add_vertex(mid + side)
	return _finish(st, _vertex_material(true))


## Street lamp: pole along +y, arm reaching toward +z (the road side).
func _lamp() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var metal := Color(1, 1, 1)
	_add(st, _cyl(0.07, 0.11, 7.5, 6), Transform3D(Basis(), Vector3(0, 3.75, 0)), metal)
	_add(st, _box(Vector3(0.1, 0.1, 1.8)), Transform3D(Basis(), Vector3(0, 7.4, 0.9)), metal)
	_add(st, _box(Vector3(0.35, 0.18, 0.7)), Transform3D(Basis(), Vector3(0, 7.3, 1.7)), metal * 0.8)
	return _finish(st, _vertex_material())


func _car() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add(st, _box(Vector3(1.75, 0.75, 4.4)), Transform3D(Basis(), Vector3(0, 0.62, 0)), Color(1, 1, 1))
	_add(st, _box(Vector3(1.55, 0.6, 2.2)), Transform3D(Basis(), Vector3(0, 1.25, -0.2)), Color(0.35, 0.37, 0.38))
	for x in [-0.8, 0.8]:
		for z in [-1.4, 1.4]:
			_add(st, _cyl(0.32, 0.32, 0.22, 8), Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(x, 0.3, z)), Color(0.1, 0.1, 0.1))
	return _finish(st, _vertex_material())


## Double-decker bus silhouette.
func _bus() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add(st, _box(Vector3(2.5, 4.1, 11.2)), Transform3D(Basis(), Vector3(0, 2.35, 0)), Color(1, 1, 1))
	for y in [1.9, 3.6]:
		_add(st, _box(Vector3(2.52, 0.9, 10.0)), Transform3D(Basis(), Vector3(0, y, 0)), Color(0.13, 0.15, 0.15))
	return _finish(st, _vertex_material())


## Far-distance tree silhouette.
func _blob() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add(st, _sphere(3.0, 3, 6), Transform3D(Basis().scaled(Vector3(1.0, 0.7, 1.0)), Vector3(0, 5.5, 0)), Color(0.20, 0.28, 0.13))
	return _finish(st, _vertex_material())
