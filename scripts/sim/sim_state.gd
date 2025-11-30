extends Node

class_name SimState

var time_seconds: float = 0.0
var bank: float = 0.0
var aircraft_catalog: Array = []
var upgrade_catalog: Array = []
var income_multiplier: float = 1.0
var nav_capabilities := {}
var progression_tier: int = 0
var traffic_rate_multiplier: float = 1.0
var tier_upgrade_counts := {}
var daily_income: Array = []   # last N days, newest at end
var daily_received: Array = [] # arrivals we handled
var daily_missed: Array = []   # arrivals we diverted/missed
var diversion_reasons: Dictionary = {} # reason -> count; helps AI choose upgrades

var active_arrivals: Array = []
var active_parking: Array = []

const MINUTES_PER_DAY: float = 1440.0
const DAY_START_MIN: float = 6.0 * 60.0   # 06:00
const DAY_END_MIN: float = 20.0 * 60.0    # 20:00
# At time_scale = 1:
# - Day (06:00-20:00, 14 hours / 840 minutes) lasts 10 real minutes -> 840 / 600 = 1.4 min sim-time per sim-second.
# - Night (20:00-06:00, 10 hours / 600 minutes) lasts 2.5 real minutes -> 600 / 150 = 4.0 min sim-time per sim-second.
const DAY_RATE_MIN_PER_SEC: float = 1.4
const NIGHT_RATE_MIN_PER_SEC: float = 4.0              # With runway lighting (night ops unlocked).
const NIGHT_RATE_NO_LIGHTS_MIN_PER_SEC: float = 10.0   # Without night ops: condense night to ~1 real minute.

var clock_minutes: float = DAY_START_MIN   # in-game clock, 0-1440 (wraps each day)
var day_index: int = 1                    # Day 1, 2, 3, ...

func _ready() -> void:
	# Seed the income history with a bucket for day 1 so the
	# charts always have at least one slot to draw into.
	daily_income.append(0.0)
	daily_received.append(0.0)
	daily_missed.append(0.0)

func advance(dt: float) -> void:
	var prev_clock := clock_minutes
	time_seconds += dt
	var rate: float = DAY_RATE_MIN_PER_SEC
	if not is_daytime():
		var has_night_ops := bool(nav_capabilities.get("night_ops", false))
		rate = NIGHT_RATE_MIN_PER_SEC if has_night_ops else NIGHT_RATE_NO_LIGHTS_MIN_PER_SEC
	clock_minutes += dt * rate
	clock_minutes = fposmod(clock_minutes, MINUTES_PER_DAY)
	if clock_minutes < prev_clock:
		day_index += 1
		# Start a new day bucket.
		daily_income.append(0.0)
		daily_received.append(0.0)
		daily_missed.append(0.0)
		# Keep only the last 10 days.
		if daily_income.size() > 10:
			daily_income.pop_front()
		if daily_received.size() > 10:
			daily_received.pop_front()
		if daily_missed.size() > 10:
			daily_missed.pop_front()

func is_daytime() -> bool:
	return clock_minutes >= DAY_START_MIN and clock_minutes < DAY_END_MIN

func get_clock_hhmm() -> String:
	var mins: int = int(clock_minutes) % int(MINUTES_PER_DAY)
	var hh: int = mins / 60
	var mm: int = mins % 60
	return "%02d:%02d" % [hh, mm]

func get_day_index() -> int:
	return day_index

func add_income(amount: float) -> void:
	# Ensure there is at least one bucket for the current day.
	if daily_income.is_empty():
		daily_income.append(0.0)
	daily_income[daily_income.size() - 1] = float(daily_income.back()) + amount

func add_received(count: float = 1.0) -> void:
	if daily_received.is_empty():
		daily_received.append(0.0)
	daily_received[daily_received.size() - 1] = float(daily_received.back()) + count

func add_missed(count: float = 1.0) -> void:
	if daily_missed.is_empty():
		daily_missed.append(0.0)
	daily_missed[daily_missed.size() - 1] = float(daily_missed.back()) + count

func add_diversion_reason(reason: String) -> void:
	var key := reason if reason != "" else "unspecified"
	diversion_reasons[key] = int(diversion_reasons.get(key, 0)) + 1

func get_diversion_reasons() -> Dictionary:
	return diversion_reasons.duplicate()

func get_recent_daily_income() -> Array:
	return daily_income.duplicate()

func get_recent_daily_received() -> Array:
	return daily_received.duplicate()

func get_recent_daily_missed() -> Array:
	return daily_missed.duplicate()
