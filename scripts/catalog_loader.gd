extends Node

class_name CatalogLoader

static func load_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open %s: %s" % [path, FileAccess.get_open_error()])
		return []
	var text := file.get_as_text()
	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK:
		push_error("JSON parse error in %s: %s" % [path, json.get_error_message()])
		return []
	var data = json.get_data()
	if typeof(data) != TYPE_ARRAY:
		push_error("Expected array in %s" % path)
		return []
	return data

static func load_aircraft() -> Array:
	return load_json_array("res://data/aircraft.json")

static func load_upgrades() -> Array:
	return load_json_array("res://data/upgrades.json")
