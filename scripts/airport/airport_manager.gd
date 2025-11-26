extends Node3D

class_name AirportManager

@export var stand_spacing: float = 25.0
@export var stand_row_origin: Vector3 = Vector3(0, 0.15, 0) # base is now computed from runway dims
@export var initial_ga_small: int = 3
@export var stand_scene: PackedScene
@export var heading_choices := PackedFloat32Array()
var _next_index: int = 1
var _runway: Runway
var _runways: Array = []

@onready var stands_container: Node3D = $Stands
@onready var taxiways_container: Node3D = $Taxiways

func _ready() -> void:
	randomize()
	_runway = get_node_or_null("Runway")
	if _runway != null:
		_randomize_heading()
		_runways.append(_runway)
	_build_initial_layout()

func _build_initial_layout() -> void:
	if stands_container:
		for c in stands_container.get_children():
			c.queue_free()
	if taxiways_container:
		for t in taxiways_container.get_children():
			t.queue_free()
	_next_index = 1
	for i in range(initial_ga_small):
		var pos = _stand_local_position(_next_index)
		_spawn_stand("ga_small", "GA%d" % (_next_index), pos)
		_next_index += 1
	_build_taxiways()

func add_stands(stand_class: String, count: int) -> void:
	for i in range(count):
		var pos = _stand_local_position(_next_index)
		_spawn_stand(stand_class, "%s%d" % [stand_class.to_upper().substr(0,2), _next_index], pos)
		_next_index += 1
	_build_taxiways()

func get_stands() -> Array:
	if stands_container == null:
		return []
	return stands_container.get_children()

func _randomize_heading() -> void:
	if _runway == null:
		return
	var primary_num = (randi() % 36) + 1 # 1..36
	var recip = primary_num + 18
	if recip > 36:
		recip -= 36
	var heading_deg = float(primary_num) * 10.0
	_runway.set_heading(heading_deg)

func add_parallel_runway(offset: float = 80.0) -> Runway:
	if _runway == null:
		return null
	var new_rwy := Runway.new()
	new_rwy.length_m = _runway.length_m
	new_rwy.width_m = _runway.width_m
	new_rwy.surface = _runway.surface
	# Create a crossing runway 45 degrees offset from the primary.
	new_rwy.set_heading(_runway.heading_deg + 45.0)
	# Offset laterally from the existing runway (cross-track) so the new
	# runway does not overlap the original too heavily.
	var right = _runway.global_transform.basis.z.normalized()
	new_rwy.transform.origin = _runway.global_transform.origin + right * offset
	get_parent().add_child(new_rwy)
	_runways.append(new_rwy)
	_assign_parallel_suffixes()
	return new_rwy

func add_cross_runway() -> Runway:
	if _runway == null:
		return null
	var base_heading = _runway.heading_deg
	var heading = base_heading
	var attempts = 0
	while attempts < 10:
		heading = float((randi() % 36) + 1) * 10.0
		var diff = abs(fmod(heading - base_heading + 360.0, 360.0))
		if diff > 20.0 and diff < 340.0:
			break
		attempts += 1
	var cross := Runway.new()
	cross.length_m = _runway.length_m
	cross.width_m = _runway.width_m
	cross.surface = _runway.surface
	cross.set_heading(heading)
	cross.transform.origin = _runway.global_transform.origin
	get_parent().add_child(cross)
	_runways.append(cross)
	_clear_suffixes() # crossing runways typically don't use L/R
	return cross

func _assign_parallel_suffixes() -> void:
	if _runways.size() < 2:
		return
	# pick two runways with closest heading difference <10 deg to tag L/R
	var primary_heading = _runway.heading_deg
	var candidates = []
	for r in _runways:
		if abs(fmod(r.heading_deg - primary_heading + 360.0, 360.0)) < 10.0:
			candidates.append(r)
	if candidates.size() >= 2:
		# decide based on world X offset: negative gets L, positive gets R
		for r in candidates:
			var offset = r.global_transform.origin.x - _runway.global_transform.origin.x
			r.set_suffix("L" if offset < 0 else "R")

func _clear_suffixes() -> void:
	for r in _runways:
		r.set_suffix("")


func _spawn_stand(stand_class: String, label: String, position: Vector3) -> void:
	var stand: Stand = null
	if stand_scene:
		stand = stand_scene.instantiate()
	else:
		stand = Stand.new()
	if stand == null:
		return
	stand.stand_class = stand_class
	stand.label = label
	stand.position = _pivot_rotate(position)
	if _runway != null:
		stand.rotation.y = deg_to_rad(_runway.heading_deg)
	stands_container.add_child(stand)

func _pivot_rotate(local_offset: Vector3) -> Vector3:
	if _runway == null:
		return local_offset
	return _runway.global_transform.origin + _runway.global_transform.basis * local_offset

func _stand_local_position(idx: int) -> Vector3:
	var width = _runway.width_m if _runway else 30.0
	var z_offset = width * 0.5 + 12.0
	var start_x = -((stand_spacing * (initial_ga_small - 1)) / 2.0)
	var x = start_x + (idx - 1) * stand_spacing
	return Vector3(x, stand_row_origin.y, z_offset)

func widen_runways(min_width: float) -> void:
	if _runway != null and _runway.width_m < min_width:
		_runway.set_width(min_width)
	for r in _runways:
		if r != null and r != _runway and r.width_m < min_width:
			r.set_width(min_width)
	_build_taxiways()

func _build_taxiways() -> void:
	if taxiways_container == null:
		return
	for t in taxiways_container.get_children():
		t.queue_free()
	if _runway == null:
		return
	var stands = get_stands()
	if stands.is_empty():
		return
	var all_runways = []
	all_runways.append(_runway)
	for r in _runways:
		if r != null and r != _runway:
			all_runways.append(r)
	for stand in stands:
		if stand == null:
			continue
		var best_runway: Runway = null
		var best_dist := INF
		var stand_pos = stand.global_transform.origin
		for r in all_runways:
			if r == null:
				continue
			var d = stand_pos.distance_to(r.global_transform.origin)
			if d < best_dist:
				best_dist = d
				best_runway = r
		if best_runway == null:
			continue
		var local = best_runway.to_local(stand_pos)
		var center_local = Vector3(local.x, 0, 0)
		var center_world = best_runway.to_global(center_local)
		var delta = stand_pos - center_world
		var horiz = Vector3(delta.x, 0, delta.z)
		var length := horiz.length()
		if length < 1.0:
			continue
		var taxi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(length, 0.15, 4.0)
		taxi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.25, 0.25)
		mat.roughness = 0.8
		taxi.material_override = mat
		var dir = horiz.normalized()
		var up = Vector3.UP
		var right = dir.cross(up).normalized()
		var basis = Basis(dir, up, right)
		taxi.transform.basis = basis
		taxi.global_transform.origin = center_world + horiz * 0.5 + Vector3(0, 0.08, 0)
		taxiways_container.add_child(taxi)
