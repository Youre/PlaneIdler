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
var _idle_time: float = 0.0
var _age: float = 0.0
var _max_lifetime: float = -1.0

func _ready() -> void:
	set_process(true)
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

func set_category_color(category: String) -> void:
	# Small: shades of green, Medium: shades of red, Large: shades of blue.
	var hue: float
	match category:
		"small":
			# Green-ish range.
			hue = randf_range(0.25, 0.38)
		"medium":
			# Red-ish range.
			hue = randf_range(0.0, 0.05)
		"large":
			# Blue-ish range.
			hue = randf_range(0.55, 0.68)
		_:
			hue = randf()
	var sat = randf_range(0.6, 0.9)
	var val = randf_range(0.7, 1.0)
	set_color(Color.from_hsv(hue, sat, val))

func set_visual_profile(category: String, width_class: String) -> void:
	# Adjust the proxy mesh size so different aircraft categories feel distinct.
	var box: BoxMesh = _mesh.mesh if _mesh else null
	if box == null or not (box is BoxMesh):
		return
	var size := _size_for(category, width_class)
	box.size = size

func _size_for(category: String, width_class: String) -> Vector3:
	# Base sizes roughly scaled to category; width class tweaks lateral span.
	var length := 12.0
	var width := 6.0
	var height := 3.0
	match category:
		"medium":
			length = 18.0
			width = 8.0
			height = 3.5
		"large":
			length = 26.0
			width = 12.0
			height = 4.0
		_:
			pass
	match width_class:
		"wide":
			width *= 1.25
			length *= 1.15
		"standard":
			width *= 1.05
			length *= 1.05
		_:
			pass
	return Vector3(width, height, length)

func start_path(points: Array, on_complete: Callable) -> void:
	if points.size() < 2:
		return
	path = points
	_current_index = 0
	_arrival_done_callback = on_complete
	_departure_done_callback = Callable() # clear any old departure callback
	_active = true
	_idle_time = 0.0
	_age = 0.0
	global_transform.origin = points[0]

func depart(points: Array, on_complete: Callable) -> void:
	if points.size() < 2:
		return
	path = points
	_current_index = 0
	_departure_done_callback = on_complete
	_arrival_done_callback = Callable() # clear any old arrival callback
	_active = true
	_idle_time = 0.0
	_age = 0.0
	global_transform.origin = points[0]

func set_lifetime(seconds: float) -> void:
	_max_lifetime = seconds
	_age = 0.0

func set_divert_visual() -> void:
	if _mesh and _mesh.material_override:
		var mat: StandardMaterial3D = _mesh.material_override
		mat.albedo_color = divert_color
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(delta: float) -> void:
	if not _active or path.size() < 2:
		return
	_age += delta
	var prev_pos: Vector3 = global_transform.origin
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
	var moved: float = (global_transform.origin - prev_pos).length()
	if moved < 0.01:
		_idle_time += delta
	else:
		_idle_time = 0.0
	# Safety: if the actor has been "active" but effectively stationary
	# for several seconds, trigger completion so SimController can
	# clean up its references and we don't accumulate stuck aircraft.
	if _idle_time > 5.0:
		_active = false
		if _arrival_done_callback and _departure_done_callback == null:
			_arrival_done_callback.call()
		elif _departure_done_callback:
			_departure_done_callback.call()
		else:
			queue_free()
		return
	# Hard lifetime cap as a safety net in case something else goes wrong.
	if _max_lifetime > 0.0 and _age >= _max_lifetime:
		_active = false
		if _arrival_done_callback and _departure_done_callback == null:
			_arrival_done_callback.call()
		elif _departure_done_callback:
			_departure_done_callback.call()
		else:
			queue_free()
	# Orient aircraft along movement direction (XZ plane).
	var flat_dir = Vector3(dir.x, 0, dir.z).normalized()
	if flat_dir.length() > 0.001:
		look_at(global_transform.origin + flat_dir, Vector3.UP)
