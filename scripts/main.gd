extends Node3D

@onready var console_label: RichTextLabel = $UI/HUD/Console
@onready var bank_label: Label = $UI/HUD/Bank
@onready var time_scale_slider: HSlider = $UI/HUD/TimeScale
@onready var ollama: OllamaClient = $OllamaClient
@onready var sim = $Sim
@onready var upgrade_mgr: UpgradeManager = $Upgrades
@onready var llm_agent: LLMAgent = $LLM

var aircraft_catalog: Array = []
var upgrade_catalog: Array = []

func _ready() -> void:
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
	if llm_agent:
		llm_agent.ollama = ollama
		llm_agent.upgrade_manager = upgrade_mgr
		llm_agent.sim = sim
		llm_agent.console_label = console_label
	if time_scale_slider:
		time_scale_slider.value = sim.time_scale if sim != null else 1.0
		time_scale_slider.connect("value_changed", Callable(self, "_on_time_scale_changed"))
	# hook upgrade buttons
	if $UI/HUD/UpgradesPanel/BtnGA:
		$UI/HUD/UpgradesPanel/BtnGA.connect("pressed", Callable(self, "_on_buy_ga"))
	if $UI/HUD/UpgradesPanel/BtnRWY:
		$UI/HUD/UpgradesPanel/BtnRWY.connect("pressed", Callable(self, "_on_buy_rwy"))
	if $UI/HUD/UpgradesPanelToggle:
		$UI/HUD/UpgradesPanelToggle.connect("pressed", Callable(self, "_on_toggle_upgrades"))

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

func _on_time_scale_changed(val: float) -> void:
	if sim:
		sim.time_scale = val
	if bank_label:
		var bank_val = sim.sim_state.bank if sim != null else 0
		bank_label.text = "%s | Bank: $%0.0f" % [_time_scale_label(val), bank_val]

func _time_scale_label(val: float) -> String:
	return "Time x%.1f" % val

func _on_buy_ga() -> void:
	if upgrade_mgr:
		upgrade_mgr.buy_ga_pack()

func _on_buy_rwy() -> void:
	if upgrade_mgr:
		upgrade_mgr.buy_runway_extension()

func _on_toggle_upgrades() -> void:
	var panel = $UI/HUD/UpgradesPanel
	if panel:
		panel.visible = not panel.visible
		$UI/HUD/UpgradesPanelToggle.text = "Upgrades" + (" (open)" if panel.visible else "")
