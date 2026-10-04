class_name WorldAssets
extends RefCounted
## Shared materials and reusable instance meshes for the streamed world.
## Material ids and asset ids match tools/world/build.py (M_* and A_*).
## Textures come from CC0 Poly Haven / ambientCG sources (tools/assets/).

const TEX := "res://world/textures/"

var materials: Array[Material] = []
var instance_meshes: Array[Mesh] = []
var water_material: ShaderMaterial
var sky_texture: Texture2D
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	var terrain := _shader("terrain", {
		"grass_albedo": "leafy_grass_diff", "grass_normal": "leafy_grass_nor_gl",
		"forest_albedo": "forest_leaves_02_diff", "forest_normal": "forest_leaves_02_nor_gl",
		"mud_albedo": "brown_mud_leaves_01_diff", "mud_normal": "brown_mud_leaves_01_nor_gl",
		"pavers_albedo": "overgrown_concrete_pavers_diff", "pavers_normal": "overgrown_concrete_pavers_nor_gl",
		"concrete_albedo": "concrete_wall_008_diff", "concrete_normal": "concrete_wall_008_nor_gl",
		"wet_albedo": "concrete_moss_diff"})
	var facade := _shader("facade", {
		"plaster_albedo": "worn_plaster_wall_diff", "plaster_normal": "worn_plaster_wall_nor_gl",
		"tiles_albedo": "rectangular_facade_tiles_diff", "tiles_normal": "rectangular_facade_tiles_nor_gl",
		"concrete_albedo": "painted_concrete_diff", "concrete_normal": "painted_concrete_nor_gl",
		"moss_albedo": "worn_mossy_plasterwall_diff", "moss_normal": "worn_mossy_plasterwall_nor_gl",
		"shutter_albedo": "rusted_shutter_diff", "shutter_normal": "rusted_shutter_nor_gl"})
	var road := _surface(1, "road_damaged", "concrete_moss", 5.0, 3.0)
	var paving := _surface(2, "square_concrete_pavers", "overgrown_concrete_pavers", 2.5, 3.0)
	var roof := _surface(4, "concrete_floor_worn_001", "concrete_moss", 4.0, 3.0)
	var rail := _surface(5, "gravel_ground_01", "leafy_grass", 2.5, 3.0)
	var concrete := _surface(6, "concrete_wall_008", "concrete_moss", 3.0, 3.0)
	var prop := _surface(7, "painted_concrete", "rusty_metal_02", 2.0, 1.5)
	var ivy := _foliage("ivy_curtain", 0.4, 0.3, 4.0)
	# 0 terrain, 1 road, 2 paving, 3 facade, 4 roof, 5 rail, 6 concrete, 7 prop, 8 ivy
	# 9 = building detail (balconies, parapets) sharing the concrete look, culled at 200 m
	materials = [terrain, road, paving, facade, roof, rail, concrete, prop, ivy, concrete]
	water_material = ShaderMaterial.new()
	water_material.shader = load("res://world/shaders/water.gdshader")
	sky_texture = load(TEX + "sky_partly_cloudy.hdr")
	_rng.seed = 7
	var broad := _foliage("canopy_broad", 0.42, 1.0, 8.0)
	var palmate := _foliage("canopy_palmate", 0.42, 1.0, 10.0)
	var fern_mat := _foliage("fern_card", 0.4, 0.6, 1.5)
	var grass_mat := _foliage("grass_card", 0.35, 1.2, 1.0)
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = load(TEX + "japanese_camphor_bark_diff.jpg")
	bark.normal_enabled = true
	bark.normal_texture = load(TEX + "japanese_camphor_bark_nor_gl.jpg")
	bark.roughness = 0.9
	bark.uv1_scale = Vector3(2.0, 3.0, 1.0)
	var metal := StandardMaterial3D.new()
	metal.vertex_color_use_as_albedo = true
	metal.albedo_texture = load(TEX + "rusty_metal_02_diff.jpg")
	metal.normal_enabled = true
	metal.normal_texture = load(TEX + "rusty_metal_02_nor_gl.jpg")
	metal.uv1_triplanar = true
	metal.uv1_scale = Vector3(0.5, 0.5, 0.5)
	metal.metallic = 0.4
	metal.roughness = 0.7
	instance_meshes = [_banyan(bark, broad), _slender(bark, palmate), _shrub(broad), _grass(grass_mat),
		_lamp(metal), _car(metal), _bus(metal), _blob(broad), _fern(fern_mat)]


func _tex(name: String) -> Texture2D:
	return load(TEX + name + ".jpg")


func _shader(name: String, textures: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://world/shaders/%s.gdshader" % name)
	for k in textures:
		m.set_shader_parameter(k, _tex(textures[k]))
	return m


func _surface(kind: int, a: String, b: String, scale_a: float, scale_b: float) -> ShaderMaterial:
	var m := _shader("surface", {"albedo_a": a + "_diff", "normal_a": a + "_nor_gl", "albedo_b": b + "_diff", "normal_b": b + "_nor_gl"})
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("scale_a", scale_a)
	m.set_shader_parameter("scale_b", scale_b)
	return m


func _foliage(texture: String, cut: float, wind: float, sway_height: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://world/shaders/foliage.gdshader")
	m.set_shader_parameter("albedo_tex", load(TEX + texture + ".png"))
	m.set_shader_parameter("alpha_cut", cut)
	m.set_shader_parameter("wind", wind)
	m.set_shader_parameter("sway_height", sway_height)
	return m


# ------------------------------------------------------------------ mesh builders
## Quad card centred at c spanning axes a and b (half extents), normal n for lighting.
func _card(st: SurfaceTool, c: Vector3, a: Vector3, b: Vector3, n: Vector3, color: Color) -> void:
	var p := [c - a - b, c + a - b, c + a + b, c - a + b]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_color(color)
		st.set_normal(n)
		st.set_uv(uv[k])
		st.add_vertex(p[k])


## Leaf-card canopy: cards scattered in an ellipsoid, normals point away from the
## centre so the clump shades like a soft volume rather than flat planes.
func _canopy(st: SurfaceTool, centre: Vector3, radii: Vector3, count: int, card: float, color: Color) -> void:
	for k in count:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 1), _rng.randf_range(-1, 1)).normalized()
		var pos := centre + dir * radii * _rng.randf_range(0.45, 1.0)
		var a := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1, 1)).normalized()
		var b := a.cross(dir).normalized()
		if b.length() < 0.1:
			b = Vector3.UP
		var s := card * _rng.randf_range(0.75, 1.25)
		var shade := 0.75 + 0.35 * clampf((pos.y - centre.y) / radii.y * 0.5 + 0.5, 0.0, 1.0)
		_card(st, pos, a * s, b * s, (pos - centre + Vector3(0, radii.y * 0.5, 0)).normalized(), color * shade)


func _bark_mesh(st: SurfaceTool, base: Vector3, top: Vector3, r0: float, r1: float, sides: int) -> void:
	var axis := (top - base)
	var up := axis.normalized()
	var side := up.cross(Vector3(0.3, 0, 1)).normalized()
	var side2 := up.cross(side).normalized()
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var d0 := side * cos(a0) + side2 * sin(a0)
		var d1 := side * cos(a1) + side2 * sin(a1)
		var quad := [base + d0 * r0, base + d1 * r0, top + d1 * r1, top + d0 * r1]
		var uvs := [Vector2(float(k) / sides, 1), Vector2(float(k + 1) / sides, 1), Vector2(float(k + 1) / sides, 0), Vector2(float(k) / sides, 0)]
		var ns := [d0, d1, d1, d0]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(ns[i])
			st.set_uv(uvs[i] * Vector2(1, axis.length() / 3.0))
			st.add_vertex(quad[i])


func _two_surface(trunk: SurfaceTool, bark: Material, leaves: SurfaceTool, leaf_mat: Material) -> ArrayMesh:
	var mesh := trunk.commit()
	mesh.surface_set_material(0, bark)
	leaves.commit(mesh)
	mesh.surface_set_material(1, leaf_mat)
	return mesh


## Banyan (Ficus microcarpa): buttressed trunk, spreading limbs, broad layered crown, aerial roots.
func _banyan(bark: Material, leaf: Material) -> ArrayMesh:
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bark_mesh(t, Vector3(0, -0.3, 0), Vector3(0.2, 4.2, 0.1), 0.9, 0.45, 9)
	for k in 5:
		var a := k * TAU / 5.0 + 0.4
		var tip := Vector3(cos(a) * 4.5, 6.5 + (k % 2), sin(a) * 4.5)
		_bark_mesh(t, Vector3(0.2, 3.8, 0.1), tip, 0.32, 0.12, 6)
		# aerial roots dropping from the limbs
		for r in 2:
			var p := Vector3(cos(a) * (2.2 + r * 1.3), 0, sin(a) * (2.2 + r * 1.3))
			_bark_mesh(t, p + Vector3(0, -0.2, 0), p + Vector3(0, 5.6 + r * 0.4, 0), 0.07, 0.04, 4)
	var l := SurfaceTool.new()
	l.begin(Mesh.PRIMITIVE_TRIANGLES)
	_canopy(l, Vector3(0, 7.0, 0), Vector3(6.2, 2.6, 6.2), 46, 2.2, Color(0.95, 1.0, 0.9))
	_canopy(l, Vector3(0, 8.8, 0), Vector3(4.0, 1.6, 4.0), 18, 2.0, Color(1.05, 1.08, 0.95))
	return _two_surface(t, bark, l, leaf)


## Slender pioneer tree (Macaranga / Mallotus): thin trunk, open crown of large leaves.
func _slender(bark: Material, leaf: Material) -> ArrayMesh:
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bark_mesh(t, Vector3(0, -0.2, 0), Vector3(0.3, 7.5, 0.2), 0.24, 0.1, 6)
	_bark_mesh(t, Vector3(0.2, 5.0, 0.1), Vector3(1.6, 7.6, -0.6), 0.09, 0.04, 4)
	_bark_mesh(t, Vector3(0.25, 5.8, 0.15), Vector3(-1.2, 8.0, 1.0), 0.08, 0.04, 4)
	var l := SurfaceTool.new()
	l.begin(Mesh.PRIMITIVE_TRIANGLES)
	_canopy(l, Vector3(0.2, 8.0, 0.1), Vector3(2.8, 1.8, 2.8), 22, 1.6, Color(1, 1, 1))
	return _two_surface(t, bark, l, leaf)


func _shrub(leaf: Material) -> ArrayMesh:
	var l := SurfaceTool.new()
	l.begin(Mesh.PRIMITIVE_TRIANGLES)
	_canopy(l, Vector3(0, 0.75, 0), Vector3(1.3, 0.8, 1.3), 14, 0.85, Color(0.95, 1.0, 0.92))
	var mesh := l.commit()
	mesh.surface_set_material(0, leaf)
	return mesh


## Grass/weed tuft: three crossed vertical cards.
func _grass(mat: Material) -> ArrayMesh:
	var l := SurfaceTool.new()
	l.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * PI / 3.0
		var d := Vector3(cos(a), 0, sin(a)) * 0.45
		_card(l, Vector3(0, 0.32, 0), d, Vector3(0, 0.34, 0), Vector3.UP, Color(1, 1, 1))
	var mesh := l.commit()
	mesh.surface_set_material(0, mat)
	return mesh


func _fern(mat: Material) -> ArrayMesh:
	var l := SurfaceTool.new()
	l.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 5:
		var a := k * TAU / 5.0
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		# leaning frond card rising from the centre
		_card(l, out * 0.45 + Vector3(0, 0.45, 0), side * 0.55, (out * 0.45 + Vector3(0, 0.42, 0)), Vector3.UP, Color(1, 1, 1))
	var mesh := l.commit()
	mesh.surface_set_material(0, mat)
	return mesh


## Far-distance tree: a handful of large canopy cards.
func _blob(leaf: Material) -> ArrayMesh:
	var l := SurfaceTool.new()
	l.begin(Mesh.PRIMITIVE_TRIANGLES)
	_canopy(l, Vector3(0, 6.0, 0), Vector3(4.0, 2.2, 4.0), 8, 3.2, Color(0.9, 0.95, 0.85))
	var mesh := l.commit()
	mesh.surface_set_material(0, leaf)
	return mesh


static func _add(st: SurfaceTool, prim: PrimitiveMesh, xf: Transform3D, color: Color) -> void:
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for k in idx:
		st.set_color(color)
		st.set_normal((xf.basis * normals[k]).normalized())
		st.add_vertex(xf * verts[k])


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(r_top: float, r_bot: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _finish(st: SurfaceTool, mat: Material) -> ArrayMesh:
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh


## Street lamp: pole along +y, arm reaching toward +z (the road side).
func _lamp(mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add(st, _cyl(0.07, 0.12, 7.5, 8), Transform3D(Basis(), Vector3(0, 3.75, 0)), Color(0.75, 0.76, 0.72))
	_add(st, _box(Vector3(0.1, 0.1, 1.8)), Transform3D(Basis(), Vector3(0, 7.4, 0.9)), Color(0.75, 0.76, 0.72))
	_add(st, _box(Vector3(0.35, 0.18, 0.7)), Transform3D(Basis(), Vector3(0, 7.3, 1.7)), Color(0.55, 0.56, 0.52))
	return _finish(st, mat)


func _car(mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := BoxMesh.new()
	body.size = Vector3(1.75, 0.7, 4.4)
	_add(st, body, Transform3D(Basis(), Vector3(0, 0.62, 0)), Color(1, 1, 1))
	var cabin := PrismMesh.new()
	cabin.size = Vector3(1.55, 0.6, 2.6)
	cabin.left_to_right = 0.5
	_add(st, cabin, Transform3D(Basis(Vector3.UP, PI / 2).scaled(Vector3(1.6, 1, 0.6)), Vector3(0, 1.25, -0.2)), Color(0.18, 0.2, 0.2))
	for x in [-0.8, 0.8]:
		for z in [-1.4, 1.4]:
			_add(st, _cyl(0.32, 0.32, 0.22, 10), Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(x, 0.24, z)), Color(0.08, 0.08, 0.08))
	return _finish(st, mat)


## Double-decker bus silhouette.
func _bus(mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add(st, _box(Vector3(2.5, 4.1, 11.2)), Transform3D(Basis(), Vector3(0, 2.35, 0)), Color(1, 1, 1))
	for y in [1.9, 3.6]:
		_add(st, _box(Vector3(2.52, 0.9, 10.0)), Transform3D(Basis(), Vector3(0, y, 0)), Color(0.12, 0.14, 0.14))
	return _finish(st, mat)
