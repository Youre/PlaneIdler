extends Node3D

class_name AircraftActor

@export var speed_mps: float = 25.0
@export var color: Color = Color(1, 1, 0.3)
@export var divert_color: Color = Color(1, 0.4, 0.4)

var path: Array = []
var _mesh: MeshInstance3D
var _current_index: int = 0
var _active: bool = false
var _arrival_done_callback: Callable
var _departure_done_callback: Callable

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(6, 3, 12)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.flags_unshaded = false
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh)

func set_random_color() -> void:
	if _mesh and _mesh.material_override:
		var mat: StandardMaterial3D = _mesh.material_override
		var hue = randf()
		mat.albedo_color = Color.from_hsv(hue, 0.7, 0.9)

func set_color(c: Color) -> void:
	if _mesh and _mesh.material_override:
		var mat: StandardMaterial3D = _mesh.material_override
		mat.albedo_color = c

func start_path(points: Array, on_complete: Callable) -> void:
	if points.size() < 2:
		return
	path = points
	_current_index = 0
	_arrival_done_callback = on_complete
	_active = true
	global_transform.origin = points[0]

func depart(points: Array, on_complete: Callable) -> void:
	if points.size() < 2:
		return
	path = points
	_current_index = 0
	_departure_done_callback = on_complete
	_active = true
	global_transform.origin = points[0]

func set_divert_visual() -> void:
	if _mesh and _mesh.material_override:
		var mat: StandardMaterial3D = _mesh.material_override
		mat.albedo_color = divert_color
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(delta: float) -> void:
	if not _active or path.size() < 2:
		return
	var target = path[_current_index + 1]
	var dir = target - global_transform.origin
	var dist = dir.length()
	if dist < 0.5:
		_current_index += 1
		if _current_index >= path.size() - 1:
			_active = false
			if _arrival_done_callback and _departure_done_callback == null:
				_arrival_done_callback.call()
			elif _departure_done_callback:
				_departure_done_callback.call()
			return
		return
	dir = dir.normalized()
	var step = min(speed_mps * delta, dist)
	global_transform.origin += dir * step
