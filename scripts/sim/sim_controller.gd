extends Node

class_name SimController

@export var arrival_generator: ArrivalGenerator
@export var sim_state: SimState
@export var stand_manager: StandManager
@export var console_label: RichTextLabel
@export var runway: Runway
@export var aircraft_scene: PackedScene
signal bank_changed(new_bank: float)
@export var time_scale: float = 1.0

var _dwell_timers: Array = [] # Array of dictionaries: { "stand": Stand, "remaining": float }
var _actors: Array = []
var _flyovers: Array = []
var _flyby_timer: float = 0.0
var _flyby_next: float = 60.0
const CULL_DISTANCE: float = 900.0

func _ready() -> void:
	randomize()
	if arrival_generator == null:
		arrival_generator = ArrivalGenerator.new()
	add_child(arrival_generator)
	if sim_state == null:
		sim_state = SimState.new()
	add_child(sim_state)
	if stand_manager == null:
		stand_manager = StandManager.new()
	add_child(stand_manager)
	arrival_generator.reset()
	_flyby_timer = 0.0
	_flyby_next = randf_range(45.0, 90.0)

func set_catalogs(aircraft: Array, upgrades: Array) -> void:
	sim_state.aircraft_catalog = aircraft
	sim_state.upgrade_catalog = upgrades

func set_stands(stand_nodes: Array) -> void:
	stand_manager.register_stands(stand_nodes)
	# assume main runway is sibling node named Runway under AirportRoot
	if runway == null:
		var airport = get_parent().get_node_or_null("AirportRoot")
		if airport:
			runway = airport.get_node_or_null("Runway")

func _process(delta: float) -> void:
	if sim_state == null:
		return
	var scaled_dt = delta * time_scale
	sim_state.advance(scaled_dt)
	_process_arrivals(scaled_dt)
	_process_dwell(scaled_dt)
	_process_flyby(scaled_dt)
	_cull_far_actors()

func _process_arrivals(delta: float) -> void:
	var spawns = arrival_generator.update(delta, sim_state)
	for aircraft in spawns:
		var stand_class: String = aircraft.get("standClass", "ga_small")
		var stand = stand_manager.find_free(stand_class)
		var runway_ok = Eligibility.runway_ok(runway, aircraft)
		if stand and runway_ok:
			# Reserve and apply effects immediately
			stand_manager.occupy(stand, aircraft.get("dwellMinutes", {}))
			_start_dwell_timer(stand, aircraft.get("dwellMinutes", {}))
			stand.set_aircraft_marker(true, aircraft.get("displayName", "Aircraft"))
			_log_arrival(aircraft, stand)
			_add_income(aircraft)
			# Visual animation
			_spawn_actor_for_arrival(aircraft, stand)
		else:
			var reason = "no %s stand free" % stand_class if stand == null else "runway limits"
			_log("[color=yellow]%s[/color] diverted (%s)" % [aircraft.get("displayName", "Aircraft"), reason], true)
			_spawn_flyover(aircraft)

func _start_dwell_timer(stand: Stand, dwell_minutes: Dictionary) -> void:
	var dur_min = dwell_minutes.get("min", 1)
	var dur_max = dwell_minutes.get("max", 3)
	# Speed up departures for testing (scale down)
	var dwell_seconds = randf_range(float(dur_min) * 15.0, float(dur_max) * 30.0)
	var timer_entry = { "stand": stand, "remaining": dwell_seconds }
	_dwell_timers.append(timer_entry)

func _process_dwell(delta: float) -> void:
	var still_active: Array = []
	for entry in _dwell_timers:
		entry["remaining"] = entry["remaining"] - delta
		if entry["remaining"] <= 0.0:
			var stand: Stand = entry["stand"]
			if stand:
				stand.set_occupied(false)
				stand.set_aircraft_marker(false)
				_log("%s departed from %s" % [stand.label, stand.stand_class])
				_spawn_departure_actor(stand)
		else:
			still_active.append(entry)
	_dwell_timers = still_active

func _process_flyby(delta: float) -> void:
	_flyby_timer += delta
	if _flyby_timer >= _flyby_next:
		_spawn_flyby()
		_flyby_timer = 0.0
		_flyby_next = randf_range(45.0, 90.0)

func _add_income(aircraft: Dictionary) -> void:
	var fees = aircraft.get("fees", {})
	var landing = fees.get("landing", 0.0)
	var dwell = fees.get("parkingPerMinute", 0.0) * float(aircraft.get("dwellMinutes", {}).get("min", 1))
	sim_state.bank += landing + dwell
	emit_signal("bank_changed", sim_state.bank)
	_log("[color=green]+%.0f[/color] bank=%.0f" % [landing + dwell, sim_state.bank])

func _log(msg: String, to_console: bool = true) -> void:
	if to_console and console_label:
		console_label.append_text(msg + "\n")
		console_label.scroll_to_line(console_label.get_line_count())
	print(msg)

func _spawn_actor_for_arrival(aircraft: Dictionary, stand: Stand) -> void:
	if aircraft_scene == null or runway == null:
		return
	var actor = aircraft_scene.instantiate()
	get_parent().add_child(actor)
	actor.set_random_color()
	actor.speed_mps = 40.0
	var fwd = runway.global_transform.basis.x.normalized() # runway length axis
	var right = runway.global_transform.basis.z.normalized()
	var start = runway.global_transform.origin - fwd * 250.0 + Vector3(0, 12, 0)
	var runway_touch = runway.global_transform.origin + Vector3(0, 0.2, 0)
	var stand_pos = stand.global_transform.origin + Vector3(0, 0.7, 0)
	actor.start_path([start, runway_touch, stand_pos], func():
		actor.queue_free()
		_actors.erase(actor)
	)
	_actors.append(actor)

func _spawn_departure_actor(stand: Stand) -> void:
	if aircraft_scene == null or runway == null:
		return
	var actor = aircraft_scene.instantiate()
	get_parent().add_child(actor)
	actor.set_random_color()
	actor.speed_mps = 35.0
	var fwd = runway.global_transform.basis.x.normalized()
	var start = stand.global_transform.origin + Vector3(0, 0.5, 0)
	var runway_point = runway.global_transform.origin + fwd * 15.0
	var exit = runway.global_transform.origin + fwd * 300.0 + Vector3(0, 6, 0)
	actor.depart([start, runway_point, exit], func():
		actor.queue_free()
		_actors.erase(actor)
	)
	_actors.append(actor)

func _log_arrival(aircraft: Dictionary, stand: Stand) -> void:
	_log("[color=cyan]%s[/color] arrived -> %s (dwell %d-%d min)" % [
		aircraft.get("displayName", "Aircraft"),
		stand.label,
		int(aircraft.get("dwellMinutes", {}).get("min", 1)),
		int(aircraft.get("dwellMinutes", {}).get("max", 3))
	])

func _spawn_flyover(aircraft: Dictionary) -> void:
	if aircraft_scene == null or runway == null:
		return
	var actor = aircraft_scene.instantiate()
	get_parent().add_child(actor)
	actor.speed_mps = 60.0
	actor.set_divert_visual()
	actor.set_random_color()
	var dir = 1.0 if randf() > 0.5 else -1.0
	var lateral_sign = 1.0 if randf() > 0.5 else -1.0
	var lateral = randf_range(80.0, 140.0) * lateral_sign
	var alt = randf_range(30.0, 55.0)
	var fwd = runway.global_transform.basis.x.normalized()
	var right = runway.global_transform.basis.z.normalized()
	var start = runway.global_transform.origin - fwd * 450.0 * dir + right * lateral + Vector3(0, alt, 0)
	var mid = runway.global_transform.origin + right * (lateral * 0.35) + Vector3(0, alt - 5, 0)
	var end = runway.global_transform.origin + fwd * 450.0 * dir + right * lateral + Vector3(0, alt + 5, 0)
	actor.start_path([start, mid, end], func():
		actor.queue_free()
		_flyovers.erase(actor)
	)
	_flyovers.append(actor)

func _spawn_flyby() -> void:
	if aircraft_scene == null or runway == null:
		return
	var actor = aircraft_scene.instantiate()
	get_parent().add_child(actor)
	actor.speed_mps = 55.0
	actor.set_random_color()
	var dir = 1.0 if randf() > 0.5 else -1.0
	var lateral_sign = 1.0 if randf() > 0.5 else -1.0
	var lateral = randf_range(200.0, 320.0) * lateral_sign
	var alt = randf_range(70.0, 110.0)
	var fwd = runway.global_transform.basis.x.normalized()
	var right = runway.global_transform.basis.z.normalized()
	var start = runway.global_transform.origin - fwd * 550.0 * dir + right * lateral + Vector3(0, alt, 0)
	var mid = runway.global_transform.origin + right * (lateral * 0.4) + Vector3(0, alt, 0)
	var end = runway.global_transform.origin + fwd * 550.0 * dir + right * lateral + Vector3(0, alt, 0)
	actor.start_path([start, mid, end], func():
		actor.queue_free()
		_flyovers.erase(actor)
	)
	_flyovers.append(actor)

func _cull_far_actors() -> void:
	for actor in _actors.duplicate():
		if actor and actor.is_inside_tree() and actor.global_transform.origin.length() > CULL_DISTANCE:
			actor.queue_free()
			_actors.erase(actor)
	for actor in _flyovers.duplicate():
		if actor and actor.is_inside_tree() and actor.global_transform.origin.length() > CULL_DISTANCE:
			actor.queue_free()
			_flyovers.erase(actor)
