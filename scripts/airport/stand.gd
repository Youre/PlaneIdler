extends Node3D

class_name Stand

@export var stand_class: String = "ga_small" # ga_small, ga_medium, regional, narrowbody, widebody
@export var radius_m: float = 8.0
@export var label: String = "S1"
@export var occupied: bool = false

var _mesh: MeshInstance3D
var _available_mat: StandardMaterial3D
var _occupied_mat: StandardMaterial3D
var _marker: MeshInstance3D

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _build_mesh()
	_available_mat = _material_for_class(stand_class)
	_occupied_mat = _material_for_class(stand_class).duplicate()
	_occupied_mat.albedo_color = _occupied_mat.albedo_color.lerp(Color(1, 0.5, 0.5), 0.6)
	_mesh.material_override = _available_mat
	add_child(_mesh)
	_build_marker()
	_update_occupied()

func _build_mesh() -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = radius_m
	cm.bottom_radius = radius_m
	cm.height = 0.25
	cm.radial_segments = 48
	return cm

func _material_for_class(c: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	match c:
		"ga_small":
			mat.albedo_color = Color(0.1, 0.6, 1.0)
		"ga_medium":
			mat.albedo_color = Color(0.2, 0.7, 0.9)
		"regional":
			mat.albedo_color = Color(0.9, 0.7, 0.2)
		"narrowbody":
			mat.albedo_color = Color(0.9, 0.4, 0.3)
		"widebody":
			mat.albedo_color = Color(0.8, 0.2, 0.8)
		_:
			mat.albedo_color = Color(0.6, 0.6, 0.6)
	mat.metallic = 0.0
	mat.roughness = 0.8
	return mat

func set_occupied(is_occupied: bool) -> void:
	occupied = is_occupied
	_update_occupied()

func _update_occupied() -> void:
	if _mesh == null:
		return
	_mesh.material_override = _occupied_mat if occupied else _available_mat

func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(6, 3, 6)
	_marker.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0.2)
	mat.flags_unshaded = false
	_marker.material_override = mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_marker.position = Vector3(0, 1.8, 0)
	_marker.visible = false
	add_child(_marker)

func set_aircraft_marker(visible: bool, label_text: String = "") -> void:
	if _marker:
		_marker.visible = visible
		_marker.position = Vector3(0, 1.8, 0)
