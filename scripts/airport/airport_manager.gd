extends Node3D

class_name AirportManager

@export var stand_spacing: float = 25.0
@export var stand_row_origin: Vector3 = Vector3(0, 0.15, 0) # base is now computed from runway dims
@export var initial_ga_small: int = 3
@export var stand_scene: PackedScene
@export var heading_choices := PackedFloat32Array()
@export var hangar_spacing: float = 40.0
var _taxiways_enabled: bool = false
var _next_index: int = 1
var _runway: Runway
var _runways: Array = []
var _next_hangar_index: int = 0
var _taxi_material: StandardMaterial3D = null

@onready var stands_container: Node3D = $Stands
@onready var taxiways_container: Node3D = $Taxiways
@onready var hangars_container: Node3D = $Hangars

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
	if hangars_container:
		for h in hangars_container.get_children():
			h.queue_free()
	if taxiways_container:
		for t in taxiways_container.get_children():
			t.queue_free()
	_next_index = 1
	_next_hangar_index = 0
	for i in range(initial_ga_small):
		var pos = _stand_local_position(_next_index)
		_spawn_stand("ga_small", "GA%d" % (_next_index), pos)
		_next_index += 1
	_build_taxiways()

func set_taxiways_enabled(enabled: bool) -> void:
	_taxiways_enabled = enabled
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

func add_hangars(slot_count: int) -> void:
	# Each spawned hangar building represents two service bays by default.
	if slot_count <= 0:
		return
	if hangars_container == null:
		return
	var slots_remaining = slot_count
	var slots_per_building = 2
	while slots_remaining > 0:
		_next_hangar_index += 1
		var local_pos = _hangar_local_position(_next_hangar_index)
		_spawn_hangar_building(local_pos)
		slots_remaining -= slots_per_building

func _spawn_hangar_building(local_offset: Vector3) -> void:
	if _runway == null or hangars_container == null:
		return
	var root := Node3D.new()
	root.position = _pivot_rotate(local_offset)
	# Orient hangars roughly parallel to the runway.
	root.rotation.y = deg_to_rad(_runway.heading_deg)

	# Concrete pad
	var pad := MeshInstance3D.new()
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(22.0, 0.3, 16.0)
	pad.mesh = pad_mesh
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.32, 0.32, 0.35)
	pad_mat.roughness = 0.85
	pad.material_override = pad_mat
	pad.position = Vector3(0, pad_mesh.size.y * 0.5, 0)
	root.add_child(pad)

	# Hangar body
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(18.0, 6.0, 12.0)
	body.mesh = body_mesh
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.65, 0.65, 0.7)
	body_mat.roughness = 0.6
	body.material_override = body_mat
	body.position = Vector3(0, pad_mesh.size.y + body_mesh.size.y * 0.5, -1.0)
	root.add_child(body)

	# Darker roof
	var roof := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(18.5, 0.6, 12.5)
	roof.mesh = roof_mesh
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.2, 0.2, 0.24)
	roof_mat.roughness = 0.4
	roof.material_override = roof_mat
	roof.position = Vector3(0, pad_mesh.size.y + body_mesh.size.y + roof_mesh.size.y * 0.5, -1.0)
	root.add_child(roof)

	hangars_container.add_child(root)

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
	# Place stands further from the runway so they do not overlap
	# the taxiway network that runs between the runway edge and the
	# parking row.
	var z_offset = width * 0.5 + 18.0
	var start_x = -((stand_spacing * (initial_ga_small - 1)) / 2.0)
	var x = start_x + (idx - 1) * stand_spacing
	return Vector3(x, stand_row_origin.y, z_offset)

func _hangar_local_position(idx: int) -> Vector3:
	var width = _runway.width_m if _runway else 30.0
	# Place hangars further away from the runway than stands to
	# avoid overlapping stands and taxiways visually.
	var z_offset = width * 0.5 + 55.0
	var x = -80.0 + float(idx - 1) * hangar_spacing
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
	if not _taxiways_enabled:
		return
	if _runway == null:
		return
	var stands = get_stands()
	if stands.is_empty():
		return

	# Build a multi-segment taxiway network:
	# - A main spine parallel to each runway, part-way between runway and stands.
	# - Short connectors from each stand to the nearest spine.
	# - Entry segments from runway centerline to the spine at a few points.

	var all_runways: Array = []
	all_runways.append(_runway)
	for r in _runways:
		if r != null and r != _runway:
			all_runways.append(r)

	for r in all_runways:
		_build_taxi_for_runway(r, stands)

func _get_taxi_material() -> StandardMaterial3D:
	if _taxi_material == null:
		_taxi_material = StandardMaterial3D.new()
		_taxi_material.albedo_color = Color(0.30, 0.30, 0.32)
		_taxi_material.roughness = 0.8
	return _taxi_material

func _build_taxi_for_runway(runway: Runway, stands: Array) -> void:
	if runway == null:
		return
	# Collect stands closest to this runway so we can size the spine.
	var runway_stands: Array = []
	var up = Vector3.UP
	var stands_min_x := INF
	var stands_max_x := -INF
	var pos_side_count := 0
	var neg_side_count := 0
	for stand in stands:
		if stand == null:
			continue
		var d = stand.global_transform.origin.distance_to(runway.global_transform.origin)
		# Only consider stands within a reasonable band of this runway.
		if d < 400.0:
			runway_stands.append(stand)
			var local = runway.to_local(stand.global_transform.origin)
			if local.x < stands_min_x:
				stands_min_x = local.x
			if local.x > stands_max_x:
				stands_max_x = local.x
			if local.z >= 0.0:
				pos_side_count += 1
			else:
				neg_side_count += 1
	if runway_stands.is_empty():
		return

	# Determine which side of the runway the majority of nearby
	# stands occupy, so the taxi spine is always between the runway
	# edge and those stands (and never on the "far" side).
	var side_sign := 1.0
	if neg_side_count > pos_side_count:
		side_sign = -1.0

	# Determine spine lateral offset between runway edge and stands,
	# using the chosen side. This keeps the taxiway placement
	# consistent with the runway width and orientation even when
	# additional runways are added at angles.
	var width = runway.width_m
	var spine_distance = width * 0.5 + 10.0
	var spine_z_local = spine_distance * side_sign # between runway edge and stands
	var spine_length = runway.length_m

	# Build spine mesh along the runway's length axis.
	var spine = MeshInstance3D.new()
	var spine_mesh = BoxMesh.new()
	# Width of the taxiway scales modestly with runway width so it
	# looks coherent across small and large fields.
	var spine_width = clamp(width * 0.18, 4.0, 10.0)
	spine_mesh.size = Vector3(spine_length, 0.15, spine_width)
	spine.mesh = spine_mesh
	spine.material_override = _get_taxi_material()

	# Place the spine using a transform that is local to the runway,
	# then convert to world space. This guarantees it stays exactly
	# parallel to the runway and uses the same "long axis".
	var spine_local := Transform3D.IDENTITY
	spine_local.origin = Vector3(0, 0.08, spine_z_local)
	spine.global_transform = runway.global_transform * spine_local
	taxiways_container.add_child(spine)

	# Connect each stand to the spine.
	for stand in runway_stands:
		var stand_pos = stand.global_transform.origin
		var local = runway.to_local(stand_pos)
		var spine_point_local = Vector3(local.x, 0, spine_z_local)
		var spine_point_world = runway.to_global(spine_point_local)
		var delta = stand_pos - spine_point_world
		var horiz = Vector3(delta.x, 0, delta.z)
		var length_seg := horiz.length()
		if length_seg < 1.0:
			continue
		var seg = MeshInstance3D.new()
		var seg_mesh = BoxMesh.new()
		seg_mesh.size = Vector3(length_seg, 0.12, spine_width * 0.7)
		seg.mesh = seg_mesh
		seg.material_override = _get_taxi_material()
		var seg_dir = horiz.normalized()
		var seg_right = seg_dir.cross(up).normalized()
		var seg_basis = Basis(seg_dir, up, seg_right)
		seg.transform.basis = seg_basis
		seg.global_transform.origin = spine_point_world + horiz * 0.5 + Vector3(0, 0.08, 0)
		taxiways_container.add_child(seg)

	# Add a few runway-to-spine entry links near the middle and ends.
	var half_len = runway.length_m * 0.5
	var margin = min(80.0, half_len * 0.35)
	var min_x = -half_len + margin
	var max_x = half_len - margin
	if max_x <= min_x:
		min_x = -half_len * 0.5
		max_x = half_len * 0.5
	var entry_offsets_local = [
		Vector3(min_x + spine_length * 0.25, 0, 0),
		Vector3((min_x + max_x) * 0.5, 0, 0),
		Vector3(max_x - spine_length * 0.25, 0, 0)
	]
	for loc in entry_offsets_local:
		# Start from the runway edge on the same side as the taxi spine,
		# so the connector runs from runway pavement out to the parallel
		# taxiway instead of crossing the full runway width.
		var edge_local = Vector3(loc.x, 0, side_sign * width * 0.5)
		var edge_world = runway.to_global(edge_local)
		var spine_world = runway.to_global(Vector3(loc.x, 0, spine_z_local))
		var link_vec = spine_world - edge_world
		var link_horiz = Vector3(link_vec.x, 0, link_vec.z)
		var link_len := link_horiz.length()
		if link_len < 1.0:
			continue
		var link = MeshInstance3D.new()
		var link_mesh = BoxMesh.new()
		link_mesh.size = Vector3(link_len, 0.12, spine_width)
		link.mesh = link_mesh
		link.material_override = _get_taxi_material()
		var link_dir = link_horiz.normalized()
		var link_right = link_dir.cross(up).normalized()
		var link_basis = Basis(link_dir, up, link_right)
		link.transform.basis = link_basis
		link.global_transform.origin = edge_world + link_horiz * 0.5 + Vector3(0, 0.08, 0)
		taxiways_container.add_child(link)
