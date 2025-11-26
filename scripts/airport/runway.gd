extends Node3D

class_name Runway

@export var length_m: float = 800.0
@export var width_m: float = 30.0
@export var heading_deg: float = 90.0
@export var surface: String = "grass" # grass | asphalt | concrete
@export var label: String = "09/27"
@export var suffix: String = "" # L/R/C etc

var _mesh: MeshInstance3D
var _label_a: MeshInstance3D
var _label_b: MeshInstance3D

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _build_mesh()
	_mesh.material_override = _material_for_surface(surface)
	add_child(_mesh)
	_add_numbers()
	_apply_heading()

func supports(length_req: float, surface_req: String, width_class_req: String) -> bool:
	if length_m < length_req:
		return false
	var surface_rank = _surface_rank(surface)
	var req_rank = _surface_rank(surface_req)
	if surface_rank < req_rank:
		return false
	if width_class_req == "wide" and width_m < 45.0:
		return false
	return true

func _build_mesh() -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = Vector3(length_m, 0.5, width_m)
	return bm

func set_width(new_width: float) -> void:
	width_m = new_width
	if _mesh:
		var bm := _build_mesh()
		_mesh.mesh = bm

func set_length(new_length: float) -> void:
	length_m = new_length
	if _mesh:
		var bm := _build_mesh()
		_mesh.mesh = bm
	# reposition labels near the new runway ends
	if _label_a:
		_label_a.position.x = -length_m * 0.45
	if _label_b:
		_label_b.position.x = length_m * 0.45

func set_heading(new_heading: float) -> void:
	heading_deg = fposmod(new_heading, 360.0)
	_update_labels()
	_apply_heading()

func set_suffix(new_suffix: String) -> void:
	suffix = new_suffix
	_update_labels()

func _apply_heading() -> void:
	rotation.y = deg_to_rad(-heading_deg)

func _material_for_surface(s: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	match s:
		"grass":
			mat.albedo_color = Color(0.2, 0.5, 0.25)
		"asphalt":
			mat.albedo_color = Color(0.15, 0.15, 0.15)
		"concrete":
			mat.albedo_color = Color(0.45, 0.45, 0.45)
		_:
			mat.albedo_color = Color(0.15, 0.15, 0.15)
	mat.roughness = 0.9
	return mat

func update_surface(new_surface: String) -> void:
	surface = new_surface
	_mesh.material_override = _material_for_surface(surface)

func _surface_rank(s: String) -> int:
	match s:
		"grass":
			return 0
		"asphalt":
			return 1
		"concrete":
			return 2
		_:
			return -1

func _add_numbers() -> void:
	var parts = label.split("/")
	var left_num = parts[0] if parts.size() > 0 else label
	var right_num = parts[1] if parts.size() > 1 else left_num
	_label_a = _make_text_mesh(left_num)
	_label_b = _make_text_mesh(right_num)
	_label_a.position = Vector3(-length_m * 0.35, 1.8, 0)
	_label_b.position = Vector3(length_m * 0.35, 1.8, 0)
	add_child(_label_a)
	add_child(_label_b)
	_update_labels()

func _update_labels() -> void:
	var primary = int(round(heading_deg / 10.0))
	if primary <= 0:
		primary = 36
	if primary > 36:
		primary = ((primary - 1) % 36) + 1
	var reciprocal = (primary + 18)
	if reciprocal > 36:
		reciprocal -= 36
	if _label_a:
		_label_a.mesh.text = "%02d%s" % [primary, suffix]
		# top points toward negative X end (local left)
		_label_a.rotation_degrees = Vector3(-90, -90, 0)
	if _label_b:
		_label_b.mesh.text = "%02d%s" % [reciprocal, suffix]
		# top points toward positive X end (local right)
		_label_b.rotation_degrees = Vector3(-90, 90, 0)

func _make_text_mesh(txt: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TextMesh.new()
	tm.text = txt
	tm.font = ThemeDB.fallback_font
	tm.font_size = 320
	tm.depth = 0.05
	tm.horizontal_alignment = 1 # center
	mi.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.flags_unshaded = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.scale = Vector3(6, 6, 6)
	return mi
