extends Node3D

@onready var console_label: RichTextLabel = $UI/HUD/Console
@onready var bank_label: Label = $UI/HUD/Bank
@onready var airport_status_label: Label = $UI/HUD/AirportStatus
@onready var upgrades_list: ItemList = $UI/HUD/UpgradesPanel/UpgradesList
@onready var build_list: ItemList = $UI/HUD/BuildQueue/BuildList
@onready var ollama = $OllamaClient
@onready var sim = $Sim
@onready var upgrade_mgr = $Upgrades
@onready var llm_agent = $LLM
@onready var sun: DirectionalLight3D = $Sun
@onready var sun_visual: MeshInstance3D = $SunVisual
@onready var sim_clock_label: Label = $UI/HUD/SimClock
@onready var income_chart: IncomeChart = $UI/HUD/IncomeChart
@onready var traffic_chart: TrafficChart = $UI/HUD/TrafficChart

var aircraft_catalog: Array = []
var upgrade_catalog: Array = []
var _build_queue_accum: float = 0.0
var _cam_time: float = 0.0
var _last_income_chart_data: Array = []
var _last_income_chart_bank: float = -1.0

func _ready() -> void:
	set_process(true)
	_position_camera()
	aircraft_catalog = CatalogLoader.load_aircraft()
	upgrade_catalog = CatalogLoader.load_upgrades()
	_log("[color=lime]Project booted[/color]")
	_log("Aircraft loaded: %d" % aircraft_catalog.size())
	_log("Upgrades loaded: %d" % upgrade_catalog.size())
	if sim:
		sim.console_label = console_label
		sim.set_catalogs(aircraft_catalog, upgrade_catalog)
		var airport_root = get_node_or_null("AirportRoot")
		if airport_root:
			var stands_node = airport_root.get_node_or_null("Stands")
			if stands_node:
				var stands = stands_node.get_children()
				sim.set_stands(stands)
		sim.connect("bank_changed", Callable(self, "_on_bank_changed"))
		_on_bank_changed(sim.sim_state.bank)
	if upgrade_mgr:
		upgrade_mgr.set("sim", sim)
		upgrade_mgr.console_label = console_label
		upgrade_mgr.airport_manager = $AirportRoot
		upgrade_mgr.runway = $AirportRoot/Runway
		_refresh_upgrade_list()
		_refresh_build_queue()
	if llm_agent:
		llm_agent.ollama = ollama
		llm_agent.upgrade_manager = upgrade_mgr
		llm_agent.sim = sim
		llm_agent.console_label = console_label
	# hook time controls
	var time_controls = $UI/HUD/TimeControls
	if time_controls:
		var mapping = {
			"Btn0_5x": 0.5,
			"Btn1x": 1.0,
			"Btn2x": 2.0,
			"Btn4x": 4.0,
			"Btn8x": 8.0,
			"Btn16x": 16.0,
			"Btn32x": 32.0,
			"Btn64x": 64.0,
		}
		for name in mapping.keys():
			var btn: Button = time_controls.get_node_or_null(name)
			if btn:
				var speed: float = mapping[name]
				btn.connect("pressed", Callable(self, "_on_time_button_pressed").bind(speed))
	# hook upgrade UI
	if upgrades_list:
		# Single-click to purchase upgrades for now.
		upgrades_list.connect("item_selected", Callable(self, "_on_upgrade_activated"))
	if $UI/HUD/UpgradesPanelToggle:
		$UI/HUD/UpgradesPanelToggle.connect("pressed", Callable(self, "_on_toggle_upgrades"))
	var debug_btn = $UI/HUD.get_node_or_null("DebugAddCash")
	if debug_btn:
		debug_btn.connect("pressed", Callable(self, "_on_debug_add_cash"))
	# The visible sun sphere is only a sky indicator; it should
	# not cast shadows onto the world.
	if sun_visual:
		sun_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(delta: float) -> void:
	_build_queue_accum += delta
	if _build_queue_accum >= 0.3:
		_build_queue_accum = 0.0
		_refresh_build_queue()
		_refresh_airport_status()
	_update_camera(delta)
	_update_lighting(delta)
	_refresh_clock()
	# Update income chart with latest daily income data.
	if income_chart and sim and sim.sim_state:
		var data: Array = sim.sim_state.get_recent_daily_income()
		var bank: float = sim.sim_state.bank
		if data != _last_income_chart_data or bank != _last_income_chart_bank:
			var last_day: float = data.back() if data.size() > 0 else 0.0
			_log("Income chart updated | days=%d last_day=%.0f bank=%.0f" % [
				data.size(),
				last_day,
				bank
			])
			_last_income_chart_data = data.duplicate()
			_last_income_chart_bank = bank
		income_chart.set_data(data, bank)
	# Update traffic chart with received vs missed counts.
	if traffic_chart and sim and sim.sim_state:
		var received: Array[float] = []
		for v in sim.sim_state.get_recent_daily_received():
			received.append(float(v))
		var missed: Array[float] = []
		for v in sim.sim_state.get_recent_daily_missed():
			missed.append(float(v))
		traffic_chart.set_data(received, missed)

func _log(message: String) -> void:
	if console_label:
		console_label.append_text(message + "\n")
	print(message)

func _position_camera() -> void:
	_cam_time = 0.0
	_update_camera(0.0)

func _update_camera(delta: float) -> void:
	var cam: Camera3D = get_node_or_null("Camera3D")
	if cam == null:
		return
	var airport_root = get_node_or_null("AirportRoot")
	var rw: Runway = null
	if airport_root:
		rw = airport_root.get_node_or_null("Runway")
	var base_size := 180.0
	if rw != null:
		base_size = max(180.0, rw.length_m * 0.7)
	# Keep camera a bit closer than before (60% of prior radius).
	base_size *= 0.6
	_cam_time += delta * 0.15
	var wobble := 1.0 + 0.08 * sin(_cam_time)
	var size := base_size * wobble
	var dist := size * 0.6
	# Slowly rotate camera around the airport center.
	var angle := _cam_time * 0.25
	var x := sin(angle) * dist
	var z := cos(angle) * dist
	# Keep the orbit radius in X/Z but fly a bit lower above the field.
	var height := dist * 0.7
	cam.transform.origin = Vector3(x, height, z)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.size = size

func _update_lighting(delta: float) -> void:
	if sun == null:
		return
	var clock_minutes := 0.0
	if sim != null and sim.sim_state != null:
		clock_minutes = sim.sim_state.clock_minutes
	# Simple smooth blend around sunrise/sunset (approx 60 min window).
	var sunrise_min := 6.0 * 60.0
	var sunset_min := 20.0 * 60.0
	var blend := 0.0
	if clock_minutes >= sunrise_min and clock_minutes <= sunset_min:
		# Daytime core.
		blend = 1.0
	# Fade in at sunrise.
	if clock_minutes >= sunrise_min - 60.0 and clock_minutes < sunrise_min:
		blend = max(0.0, (clock_minutes - (sunrise_min - 60.0)) / 60.0)
	# Fade out after sunset.
	if clock_minutes > sunset_min and clock_minutes <= sunset_min + 60.0:
		blend = max(0.0, 1.0 - ((clock_minutes - sunset_min) / 60.0))
	# If we don't have a clock yet, fall back to day.
	if sim == null or sim.sim_state == null:
		blend = 1.0
	# Daylight: warm, brighter. Night: cool, dim "moonlight".
	var day_color := Color(1.0, 0.96, 0.9)
	var night_color := Color(0.6, 0.7, 1.0)
	var dawn_dusk_color := Color(1.0, 0.8, 0.6)
	var day_energy := 1.3
	var night_energy := 0.25
	var base_color := night_color.lerp(day_color, blend)
	# Add a subtle reddish tint near sunrise (06:00–08:00) and
	# sunset (18:00–20:00) to simulate dawn/dusk.
	var dawn_start := sunrise_min
	var dawn_end := sunrise_min + 120.0  # 06:00–08:00
	var dusk_start := sunset_min - 120.0 # 18:00–20:00
	var dusk_end := sunset_min
	var tint_strength := 0.0
	if clock_minutes >= dawn_start and clock_minutes <= dawn_end:
		tint_strength = 1.0 - abs((clock_minutes - (dawn_start + dawn_end) * 0.5) / 60.0)
	elif clock_minutes >= dusk_start and clock_minutes <= dusk_end:
		tint_strength = 1.0 - abs((clock_minutes - (dusk_start + dusk_end) * 0.5) / 60.0)
	tint_strength = clamp(tint_strength, 0.0, 1.0)
	if tint_strength > 0.0:
		base_color = base_color.lerp(dawn_dusk_color, 0.35 * tint_strength)
	sun.light_color = base_color
	sun.light_energy = lerp(night_energy, day_energy, blend)
	# Animate light direction for sun (06:00�?"20:00) and moon (20:00�?"06:00)
	# so shadows move across the field throughout the full day/night cycle.
	var minutes_per_day := 1440.0
	var day_start := sunrise_min
	var day_end := sunset_min
	var basis := Basis()
	if clock_minutes >= day_start and clock_minutes <= day_end:
		# Day arc: sun rises at 06:00, highest near mid-day, sets at 20:00.
		var day_span: float = float(day_end - day_start) # 14 hours
		var t: float = (clock_minutes - day_start) / max(day_span, 0.001) # 0..1
		var elevation := sin(t * PI) * deg_to_rad(65.0)
		var azimuth := deg_to_rad(60.0) # fixed azimuth for sun
		basis = Basis() # identity
		basis = basis.rotated(Vector3.UP, azimuth)
		# Pitch around the *local* X axis after yaw so the sun
		# rises higher in the sky at mid-day.
		basis = basis.rotated(basis.x, elevation)
	else:
		# Night arc: moon travels during the remaining 10 hours.
		var night_total: float = minutes_per_day - float(day_end - day_start) # 10 hours
		var night_minutes: float
		if clock_minutes > day_end:
			night_minutes = clock_minutes - day_end      # 20:00�?"24:00
		else:
			night_minutes = clock_minutes + (minutes_per_day - day_end) # 00:00�?"06:00
		var t_night: float = night_minutes / max(night_total, 0.001) # 0..1
		var elevation_n := sin(t_night * PI) * deg_to_rad(35.0)
		# Put the moon roughly opposite the sun in the sky box.
		var azimuth_n := deg_to_rad(240.0)
		basis = Basis()
		basis = basis.rotated(Vector3.UP, azimuth_n)
		basis = basis.rotated(basis.x, elevation_n)
	sun.transform.basis = basis
	# Position a visible sun sphere far away in the sky in the
	# opposite direction of the light, so players can see where
	# the sun/moon currently is.
	if sun_visual:
		var dir := -sun.transform.basis.z.normalized()
		var radius := 4000.0
		var origin := dir * radius
		sun_visual.global_transform.origin = origin
	# Override the light orientation and sun visual using a more
	# explicit direction vector so that lighting always comes from
	# above the scene rather than from below or the side.
	_fix_light_direction()

func _fix_light_direction() -> void:
	if sun == null:
		return
	var clock_minutes: float = 0.0
	if sim != null and sim.sim_state != null:
		clock_minutes = sim.sim_state.clock_minutes
	var sunrise_min := 6.0 * 60.0
	var sunset_min := 20.0 * 60.0
	var minutes_per_day := 1440.0
	var day_start := sunrise_min
	var day_end := sunset_min

	var dir: Vector3 = Vector3(0, -1, 0) # default: straight down
	if clock_minutes >= day_start and clock_minutes <= day_end:
		# Daytime sun path.
		var day_span: float = float(day_end - day_start)
		var t_day: float = (clock_minutes - day_start) / max(day_span, 0.001)
		var elevation := sin(t_day * PI) * deg_to_rad(65.0)
		var azimuth := deg_to_rad(60.0)
		dir = _sun_direction_from_angles(azimuth, elevation)
	else:
		# Nighttime moon path.
		var night_total: float = minutes_per_day - float(day_end - day_start)
		var night_minutes: float
		if clock_minutes > day_end:
			night_minutes = clock_minutes - day_end
		else:
			night_minutes = clock_minutes + (minutes_per_day - day_end)
		var t_night: float = night_minutes / max(night_total, 0.001)
		var elevation_n := sin(t_night * PI) * deg_to_rad(35.0)
		var azimuth_n := deg_to_rad(240.0)
		dir = _sun_direction_from_angles(azimuth_n, elevation_n)

	# Ensure light comes from above (negative Y in light direction).
	if dir.y < 0.0:
		dir.y = -dir.y
	dir = dir.normalized()

	# Directional light: -Z is the light direction.
	sun.transform.basis = Basis().looking_at(-dir, Vector3.UP)

	if sun_visual:
		var radius := 4000.0
		sun_visual.global_transform.origin = dir * radius

func _sun_direction_from_angles(azimuth: float, elevation: float) -> Vector3:
	var cos_e := cos(elevation)
	var x := cos(azimuth) * cos_e
	var y := sin(elevation)
	var z := sin(azimuth) * cos_e
	return Vector3(x, y, z).normalized()

func _on_bank_changed(value: float) -> void:
	if bank_label:
		var ts = sim.time_scale if sim != null else 1.0
		bank_label.text = "%s | Bank: $%0.0f" % [_time_scale_label(ts), value]
	_refresh_upgrade_list()

func _on_time_button_pressed(val: float) -> void:
	if sim:
		sim.time_scale = val
	if bank_label:
		var bank_val = sim.sim_state.bank if sim != null else 0
		bank_label.text = "%s | Bank: $%0.0f" % [_time_scale_label(val), bank_val]
	_refresh_airport_status()

func _time_scale_label(val: float) -> String:
	return "Time x%.1f" % val

func _on_toggle_upgrades() -> void:
	var panel = $UI/HUD/UpgradesPanel
	if panel:
		panel.visible = not panel.visible
		$UI/HUD/UpgradesPanelToggle.text = "Upgrades" + (" (open)" if panel.visible else "")

func _on_debug_add_cash() -> void:
	if sim == null:
		return
	var amount: float = 5000.0
	sim.sim_state.bank += amount
	sim.sim_state.add_income(amount)
	sim.emit_signal("bank_changed", sim.sim_state.bank)
	_log("[color=green]+%.0f[/color] debug cash added; bank=%.0f" % [amount, sim.sim_state.bank])
	_refresh_airport_status()

func _refresh_build_queue() -> void:
	if build_list == null or upgrade_mgr == null:
		return
	build_list.clear()
	var entries = upgrade_mgr.get_construction_entries()
	for e in entries:
		var name: String = str(e.get("name", ""))
		var rem: float = float(e.get("remaining", 0.0))
		var secs_left: int = int(ceil(max(rem, 0.0)))
		var label = "%s - %ds" % [name, secs_left]
		build_list.add_item(label)

func _refresh_upgrade_list() -> void:
	if upgrades_list == null or upgrade_mgr == null or sim == null:
		return
	upgrades_list.clear()
	var avail = upgrade_mgr.get_available_upgrades(sim.sim_state.bank, false)
	for u in avail:
		var id: String = str(u.get("id", ""))
		var cost: float = float(u.get("cost", 0.0))
		var desc: String = str(u.get("desc", id))
		var label = "%s ($%d) [%s]" % [desc, int(cost), id]
		var idx = upgrades_list.add_item(label)
		upgrades_list.set_item_metadata(idx, id)
	_refresh_airport_status()

func _refresh_airport_status() -> void:
	if airport_status_label == null:
		return
	var airport_root = get_node_or_null("AirportRoot")
	var rwy: Runway = null
	if airport_root:
		rwy = airport_root.get_node_or_null("Runway")
	var length_text := "--"
	if rwy != null:
		length_text = "%d" % int(rwy.length_m)
	var small_total := 0
	var small_free := 0
	var medium_total := 0
	var medium_free := 0
	var large_total := 0
	var large_free := 0
	if sim != null and sim.stand_manager != null:
		var s_stats = sim.stand_manager.stats_for_class("ga_small")
		small_total = int(s_stats.get("total", 0))
		small_free = int(s_stats.get("free", 0))
		var m_stats = sim.stand_manager.stats_for_class("ga_medium")
		medium_total = int(m_stats.get("total", 0))
		medium_free = int(m_stats.get("free", 0))
		# Treat all non-GA stands as "large" bucket for this summary.
		var regional = sim.stand_manager.stats_for_class("regional")
		var narrow = sim.stand_manager.stats_for_class("narrowbody")
		var wide = sim.stand_manager.stats_for_class("widebody")
		large_total = int(regional.get("total", 0)) + int(narrow.get("total", 0)) + int(wide.get("total", 0))
		large_free = int(regional.get("free", 0)) + int(narrow.get("free", 0)) + int(wide.get("free", 0))
	var stands_text = "S:%d/%d M:%d/%d L:%d/%d" % [
		small_free, small_total,
		medium_free, medium_total,
		large_free, large_total
	]
	airport_status_label.text = "Rwy: %s m | Stands %s" % [length_text, stands_text]

func _refresh_clock() -> void:
	if sim_clock_label == null or sim == null or sim.sim_state == null:
		return
	var day: int = sim.sim_state.get_day_index()
	var time_str: String = sim.sim_state.get_clock_hhmm()
	var total_seconds: float = sim.sim_state.time_seconds
	var total_str: String = _format_total_time(total_seconds)
	sim_clock_label.text = "Day %d | %s | %s" % [day, time_str, total_str]

func _format_total_time(seconds: float) -> String:
	var total_secs := int(seconds)
	var hours := total_secs / 3600
	var minutes := (total_secs / 60) % 60
	var secs := total_secs % 60
	return "T+%02d:%02d:%02d" % [hours, minutes, secs]

func _refresh_income_chart() -> void:
	# No-op: chart is driven directly from _process via set_data.
	pass

func _on_upgrade_activated(index: int) -> void:
	if upgrades_list == null or upgrade_mgr == null:
		return
	var id = upgrades_list.get_item_metadata(index)
	if typeof(id) != TYPE_STRING:
		return
	var ok = upgrade_mgr.purchase(id)
	if ok:
		_refresh_upgrade_list()
		_refresh_build_queue()
