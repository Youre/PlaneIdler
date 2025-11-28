extends Node

# These fields allow main.gd to wire references dynamically.
@export var ollama: Node = null
@export var upgrade_manager: Node = null
@export var sim: Node = null
@export var console_label: RichTextLabel = null

var personality: String = ""
var persona_prompt: String = ""
var base_interval: float = 30.0
var _timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _busy: bool = false

func _ready() -> void:
	_rng.randomize()
	_choose_personality()

func _process(delta: float) -> void:
	if sim == null or upgrade_manager == null or ollama == null:
		return
	# CEO is off duty at night; no chatting or purchases.
	if sim.sim_state != null and not sim.sim_state.is_daytime():
		return
	_timer += delta
	var interval: float = base_interval / max(sim.time_scale, 0.01)
	if _timer >= interval and not _busy:
		_timer = 0.0
		_consider()

func _choose_personality() -> void:
	var roll: int = randi() % 3
	match roll:
		0:
			personality = "spender"
			persona_prompt = "I buy upgrades as soon as possible to keep traffic flowing."
		1:
			personality = "planner"
			persona_prompt = "I save for larger impact upgrades and avoid small buys if a big one is close."
		2:
			personality = "quality"
			persona_prompt = "I prioritize infrastructure quality (runway first, then stands) even if slower."
	_log("[color=gray]Airport CEO persona: %s[/color]" % personality)

func _consider() -> void:
	if _busy:
		return
	if sim != null and sim.sim_state != null and not sim.sim_state.is_daytime():
		return
	_busy = true

	if sim == null or sim.sim_state == null or upgrade_manager == null or ollama == null:
		_busy = false
		return

	var bank: float = sim.sim_state.bank
	var owned: Array = upgrade_manager.owned_upgrades.duplicate()
	var available: Array = upgrade_manager.get_available_upgrades(bank, true)

	var do_upgrade_query: bool = not available.is_empty() and _rng.randi_range(0, 2) == 0
	var prompt: String
	if do_upgrade_query:
		prompt = _build_upgrade_prompt(bank, owned, available)
	else:
		prompt = _build_flavor_prompt(bank)

	var resp: Dictionary = await ollama.generate(prompt, "", 0.3, 160)
	if not resp.get("ok", false):
		var err_msg: String = str(resp.get("error", "unknown error"))
		_log("[color=gray]Airport CEO error:[/color] LLM call failed: %s" % err_msg)
		var raw_error: String = String(resp.get("raw", "")).strip_edges()
		if raw_error != "":
			_log("[color=gray]Airport CEO raw (error):[/color] %s" % raw_error)
		_busy = false
		return

	var inner: Dictionary = resp.get("json", {})
	if typeof(inner) != TYPE_DICTIONARY:
		var text_raw: String = String(resp.get("text", "")).strip_edges()
		_log("[color=gray]Airport CEO error:[/color] Invalid JSON payload from LLM: %s" % text_raw)
		_busy = false
		return

	var statement: String = str(inner.get("statement", "")).strip_edges()
	var action: String = str(inner.get("action", "wait")).strip_edges().to_lower()

	_log("[color=gray]Airport CEO:[/color] %s" % statement)

	if do_upgrade_query and action != "" and action != "wait":
		var valid_ids: Array = []
		for a in available:
			valid_ids.append(a.get("id", ""))
		if valid_ids.has(action):
			var ok: bool = upgrade_manager.purchase(action)
			if ok:
				_log("[color=cyan]Airport CEO bought upgrade:[/color] %s" % action)

	_busy = false

func _build_upgrade_prompt(bank: float, owned: Array, available: Array) -> String:
	var avail_str: String = ""
	for a in available:
		avail_str += "- id=%s | cost=%d | desc=%s\n" % [a.get("id", ""), int(a.get("cost", 0)), a.get("desc", "")]
	var owned_str: String = "none" if owned.is_empty() else ",".join(owned)
	var valid_ids: Array = []
	for a in available:
		valid_ids.append(a.get("id", ""))
	var id_list: String = ",".join(valid_ids)
	return """You are the Airport CEO NPC in an idle airport management game.

Persona: %s
Current bank balance (whole dollars): %d
Owned upgrades: %s
Available upgrades (id, cost, description):
%s

Decide whether to buy one upgrade now or WAIT.

Respond ONLY with a single JSON object matching this schema:
{
  "statement": "<one friendly sentence (8-25 words) spoken to the player>",
  "action": "<one of [%s] or 'wait'>"
}

Do not include any extra keys or text.
""" % [persona_prompt, int(bank), owned_str, avail_str, id_list]

func _build_flavor_prompt(bank: float) -> String:
	var persona: String = persona_prompt
	if persona == "":
		persona = "I run the airport with a balanced, thoughtful style."
	return """You are the Airport CEO NPC in an idle airport management game.

Persona: %s
Current bank balance (whole dollars): %d

For this call, ignore upgrade purchases and just talk about life as an airport CEO:
how traffic feels, what you are watching for next, etc.

Respond ONLY with a single JSON object matching this schema:
{
  "statement": "<one friendly sentence (8-25 words) spoken to the player>",
  "action": "wait"
}

Do not include any extra keys or text.
""" % [persona, int(bank)]

func _heuristic_upgrade(available: Array, bank: float) -> void:
	if available.is_empty():
		return
	# Pick the cheapest available upgrade that we can afford.
	var affordable: Array = []
	for a in available:
		if float(a.get("cost", 0.0)) <= bank:
			affordable.append(a)
	if affordable.is_empty():
		return
	affordable.sort_custom(func(a, b): return float(a.get("cost", 0.0)) < float(b.get("cost", 0.0)))
	var choice_id: String = String(affordable[0].get("id", ""))
	if choice_id == "":
		return
	var ok: bool = upgrade_manager.purchase(choice_id)
	if ok:
		_log("[color=cyan]Airport CEO heuristic bought upgrade:[/color] %s" % choice_id)

func _log(msg: String) -> void:
	if console_label:
		console_label.append_text(msg + "\n")
		console_label.scroll_to_line(console_label.get_line_count())
	print(msg)
