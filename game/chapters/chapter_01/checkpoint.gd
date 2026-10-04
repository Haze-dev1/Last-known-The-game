extends RefCounted

const IDS: Array[String] = ["shop_service_note", "closure_notice", "return_photo", "address_list", "acceptance_letter"]
const LOCATIONS: Array[String] = ["street", "shop", "utility", "apartment", "departure"]
var message: String = ""

func read(path: String) -> Dictionary:
	message = ""
	var state := _read_file(path)
	if not state.is_empty():
		return state
	state = _read_file(path + ".bak")
	if not state.is_empty():
		message = "Recovered the previous checkpoint backup."
	elif FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"):
		message = "Checkpoint is unreadable or incompatible. Files preserved; choose New expedition to reset."
	return state

func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	# A chapter snapshot should stay small; reject oversized/corrupted data.
	if file.get_length() > 16384:
		file.close()
		return {}
	var json := JSON.new()
	var parse_result: Error = json.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		return {}
	var parsed: Variant = json.data
	if parsed is Dictionary and valid(parsed):
		return parsed
	return {}

func valid(state: Dictionary) -> bool:
	var version: Variant = state.get("version")
	var chapter: Variant = state.get("chapter")
	if not (version is int or version is float) or not (chapter is int or chapter is float) or version != 1 or chapter != 1:
		return false
	for flag: String in ["powered", "arrival_seen", "discovery_seen", "chapter_complete"]:
		if not state.get(flag) is bool:
			return false
	if not state.get("evidence") is Array or not state.get("location") is String:
		return false
	if not LOCATIONS.has(state.location):
		return false
	var records: Array = state.evidence
	var seen: Array[String] = []
	for id: Variant in records:
		if not id is String or not IDS.has(id) or seen.has(id):
			return false
		seen.append(id)
	if records.has("shop_service_note") and not state.powered:
		return false
	var corroborated: bool = records.has("shop_service_note") and records.has("closure_notice") and records.has("return_photo")
	if state.discovery_seen and not corroborated:
		return false
	if state.chapter_complete and (not corroborated or not records.has("address_list")):
		return false
	if not state.arrival_seen and (state.powered or not records.is_empty() or state.chapter_complete):
		return false
	var sensitivity: Variant = state.get("sensitivity")
	return (sensitivity is float or sensitivity is int) and is_finite(float(sensitivity)) and float(sensitivity) >= 0.0005 and float(sensitivity) <= 0.008

func write(path: String, state: Dictionary) -> bool:
	message = ""
	if not valid(state):
		message = "Checkpoint rejected: inconsistent state."
		return false
	var folder: String = ProjectSettings.globalize_path(path.get_base_dir())
	var result: Error = DirAccess.make_dir_recursive_absolute(folder)
	if result != OK:
		return _failed(result)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return _failed(FileAccess.get_open_error())
	file.store_string(JSON.stringify(state))
	file.flush()
	result = file.get_error()
	file.close()
	if result != OK:
		return _failed(result)
	if _read_file(path + ".tmp").is_empty():
		message = "Checkpoint verification failed; previous checkpoint preserved."
		return false
	# Never replace a good backup with a damaged primary.
	if not _read_file(path).is_empty():
		result = DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak.tmp"))
		if result == OK:
			result = DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".bak.tmp"), ProjectSettings.globalize_path(path + ".bak"))
		if result != OK:
			return _failed(result)
	result = DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))
	if result != OK:
		return _failed(result)
	message = "Checkpoint saved."
	return true

func clear(path: String) -> bool:
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			var result: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
			if result != OK:
				return _failed(result)
	return true

func _failed(result: Error) -> bool:
	message = "Checkpoint write failed (%s); progress remains in this session. Retry Save checkpoint from pause." % error_string(result)
	return false
