class_name ChunkData
extends RefCounted
## Parses a generated chunk file (tools/world/build.py write_chunk) into meshes,
## multimeshes and collision data. Safe to call from a worker thread.

const MAT_COUNT := 10

var meshes: Array[ArrayMesh] = []
var mesh_mats: PackedInt32Array = []
var _mesh_specs: Array = []  # [arrays, material id] decoded off the main thread
var _mm_specs: Array = []  # [asset, count, buffer]
var collide_faces: Array[PackedVector3Array] = []
var multimeshes: Array[MultiMesh] = []
var boxes := PackedFloat32Array()
var ok := false


## Decodes arrays only; call build_resources() on the main thread afterwards.
static func load_file(path: String, want_collision: bool) -> ChunkData:
	var c := ChunkData.new()
	var packed := FileAccess.get_file_as_bytes(path)
	if packed.size() < 8 or packed.slice(0, 4).get_string_from_ascii() != "LKZ1":
		push_error("Bad chunk file " + path)
		return c
	var raw_size := packed.decode_u32(4)
	var data := packed.slice(8).decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if data.size() != raw_size:
		push_error("Chunk decompress failed " + path)
		return c
	var at := 0
	var sections := data.decode_u32(at)
	at += 4
	for _s in sections:
		var kind := data.decode_u32(at)
		if kind == 1:
			var mat := data.decode_u32(at + 4)
			var collide := data.decode_u32(at + 8) == 1
			var nv := data.decode_u32(at + 12)
			var ni := data.decode_u32(at + 16)
			at += 20
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = data.slice(at, at + nv * 12).to_vector3_array()
			at += nv * 12
			arrays[Mesh.ARRAY_NORMAL] = data.slice(at, at + nv * 12).to_vector3_array()
			at += nv * 12
			arrays[Mesh.ARRAY_TEX_UV] = data.slice(at, at + nv * 8).to_vector2_array()
			at += nv * 8
			arrays[Mesh.ARRAY_COLOR] = data.slice(at, at + nv * 16).to_color_array()
			at += nv * 16
			arrays[Mesh.ARRAY_TEX_UV2] = data.slice(at, at + nv * 8).to_vector2_array()
			at += nv * 8
			arrays[Mesh.ARRAY_INDEX] = data.slice(at, at + ni * 4).to_int32_array()
			at += ni * 4
			c._mesh_specs.append([arrays, mat])
			if collide and want_collision:
				c.collide_faces.append(_faces(arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_INDEX]))
		elif kind == 2:
			var asset := data.decode_u32(at + 4)
			var count := data.decode_u32(at + 8)
			at += 12
			c._mm_specs.append([asset, count, data.slice(at, at + count * 64).to_float32_array()])
			at += count * 64
		elif kind == 3:
			var count := data.decode_u32(at + 4)
			at += 8
			c.boxes = data.slice(at, at + count * 28).to_float32_array()
			at += count * 28
		else:
			push_error("Unknown chunk section %d in %s" % [kind, path])
			return c
	c.ok = true
	return c


static func _faces(verts: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(idx.size())
	for k in idx.size():
		out[k] = verts[idx[k]]
	return out


## Creates rendering resources; must run on the main thread.
func build_resources(materials: Array[Material], instance_meshes: Array[Mesh]) -> void:
	for spec in _mesh_specs:
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, spec[0])
		mesh.surface_set_material(0, materials[mini(spec[1], MAT_COUNT - 1)])
		meshes.append(mesh)
		mesh_mats.append(spec[1])
	for spec in _mm_specs:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = instance_meshes[spec[0]]
		mm.instance_count = spec[1]
		mm.buffer = spec[2]
		multimeshes.append(mm)
	_mesh_specs.clear()
	_mm_specs.clear()
