extends Node3D

@onready var console_label: RichTextLabel = $UI/HUD/Console
@onready var bank_label: Label = $UI/HUD/Bank
@onready var time_scale_slider: HSlider = $UI/HUD/TimeScale
@onready var upgrades_list: ItemList = $UI/HUD/UpgradesPanel/UpgradesList
@onready var build_list: ItemList = $UI/HUD/BuildQueue/BuildList
@onready var ollama: OllamaClient = $OllamaClient
@onready var sim = $Sim
@onready var upgrade_mgr: UpgradeManager = $Upgrades
@onready var llm_agent = $LLM

var aircraft_catalog: Array = []
var upgrade_catalog: Array = []
var _build_queue_accum: float = 0.0

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
		var stands = $AirportRoot/Stands.get_children()
		sim.set_stands(stands)
		sim.connect("bank_changed", Callable(self, "_on_bank_changed"))
		_on_bank_changed(sim.sim_state.bank)
	if upgrade_mgr:
		upgrade_mgr.sim = sim
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
	if time_scale_slider:
		time_scale_slider.value = sim.time_scale if sim != null else 1.0
		time_scale_slider.connect("value_changed", Callable(self, "_on_time_scale_changed"))
	# hook upgrade UI
	if upgrades_list:
		# Single-click to purchase upgrades for now.
		upgrades_list.connect("item_selected", Callable(self, "_on_upgrade_activated"))
	if $UI/HUD/UpgradesPanelToggle:
		$UI/HUD/UpgradesPanelToggle.connect("pressed", Callable(self, "_on_toggle_upgrades"))
	var debug_btn = $UI/HUD.get_node_or_null("DebugAddCash")
	if debug_btn:
		debug_btn.connect("pressed", Callable(self, "_on_debug_add_cash"))

func _process(delta: float) -> void:
	_build_queue_accum += delta
	if _build_queue_accum >= 0.3:
		_build_queue_accum = 0.0
		_refresh_build_queue()

func _log(message: String) -> void:
	if console_label:
		console_label.append_text(message + "\n")
	print(message)

func _position_camera() -> void:
	var cam: Camera3D = $Camera3D
	var rw: Runway = $AirportRoot/Runway
	var base_size := 180.0
	if rw != null:
		base_size = max(180.0, rw.length_m * 0.7)
	if cam:
		var dist = base_size * 0.8
		cam.transform.origin = Vector3(0, dist, dist)
		cam.look_at(Vector3.ZERO, Vector3.UP)
		cam.size = base_size

func _on_bank_changed(value: float) -> void:
	if bank_label:
		var ts = sim.time_scale if sim != null else 1.0
		bank_label.text = "%s | Bank: $%0.0f" % [_time_scale_label(ts), value]
	_refresh_upgrade_list()

func _on_time_scale_changed(val: float) -> void:
	if sim:
		sim.time_scale = val
	if bank_label:
		var bank_val = sim.sim_state.bank if sim != null else 0
		bank_label.text = "%s | Bank: $%0.0f" % [_time_scale_label(val), bank_val]

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
	sim.emit_signal("bank_changed", sim.sim_state.bank)
	_log("[color=green]+%.0f[/color] debug cash added; bank=%.0f" % [amount, sim.sim_state.bank])

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
