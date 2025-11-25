extends Node

class_name UpgradeManager

@export var sim: SimController
@export var airport_manager: AirportManager
@export var runway: Runway
@export var console_label: RichTextLabel
var owned_upgrades: Array = []

func buy_ga_pack(cost: float = 1800.0, count: int = 2) -> void:
	if not _can_afford(cost):
		_log("[color=yellow]Insufficient funds for GA stand pack[/color]")
		return
	_spend(cost)
	if airport_manager:
		airport_manager.add_stands("ga_small", count)
	_log("[color=lime]Purchased GA stand pack (+%d)[/color]" % count)
	owned_upgrades.append("ga_pack")

func buy_runway_extension(cost: float = 4500.0, extra_m: float = 200.0) -> void:
	if not _can_afford(cost):
		_log("[color=yellow]Insufficient funds for runway extension[/color]")
		return
	_spend(cost)
	if runway:
		runway.set_length(runway.length_m + extra_m)
	_log("[color=lime]Purchased runway extension (+%dm)[/color]" % int(extra_m))
	owned_upgrades.append("rwy_ext")
	_recenter_camera()

func get_available_upgrades(bank: float) -> Array:
	var list: Array = []
	if not owned_upgrades.has("ga_pack"):
		list.append({"id":"ga_pack","cost":1800,"desc":"Add 2 GA stands"})
	if not owned_upgrades.has("rwy_ext"):
		list.append({"id":"rwy_ext","cost":4500,"desc":"Extend runway by 200m"})
	if not owned_upgrades.has("rwy_parallel"):
		list.append({"id":"rwy_parallel","cost":15000,"desc":"Build parallel runway with L/R"})
	if not owned_upgrades.has("rwy_cross"):
		list.append({"id":"rwy_cross","cost":18000,"desc":"Build crossing runway (>=20 deg offset)"})
	return list

func execute_choice(choice: String) -> bool:
	match choice:
		"ga_pack":
			buy_ga_pack()
			return true
		"rwy_ext":
			buy_runway_extension()
			return true
		"rwy_parallel":
			buy_parallel_runway()
			return true
		"rwy_cross":
			buy_cross_runway()
			return true
		_:
			return false

func buy_parallel_runway(cost: float = 15000.0, offset: float = 80.0) -> void:
	if not _can_afford(cost):
		_log("[color=yellow]Insufficient funds for parallel runway[/color]")
		return
	_spend(cost)
	if airport_manager:
		airport_manager.add_parallel_runway(offset)
	_log("[color=lime]Parallel runway built (L/R assigned)[/color]")
	owned_upgrades.append("rwy_parallel")
	_recenter_camera()

func buy_cross_runway(cost: float = 18000.0) -> void:
	if not _can_afford(cost):
		_log("[color=yellow]Insufficient funds for crossing runway[/color]")
		return
	_spend(cost)
	if airport_manager:
		airport_manager.add_cross_runway()
	_log("[color=lime]Crossing runway built[/color]")
	owned_upgrades.append("rwy_cross")
	_recenter_camera()

func _can_afford(cost: float) -> bool:
	return sim != null and sim.sim_state.bank >= cost

func _spend(cost: float) -> void:
	sim.sim_state.bank -= cost
	sim.emit_signal("bank_changed", sim.sim_state.bank)

func _log(msg: String) -> void:
	if console_label:
		console_label.append_text(msg + "\n")
		console_label.scroll_to_line(console_label.get_line_count())
	print(msg)

func _recenter_camera() -> void:
	var root = get_parent()
	if root and root.has_method("_position_camera"):
		root._position_camera()
