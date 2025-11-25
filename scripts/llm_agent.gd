extends Node

class_name LLMAgent

@export var ollama: OllamaClient
@export var upgrade_manager: UpgradeManager
@export var sim: SimController
@export var console_label: RichTextLabel

var personality: String = ""
var persona_prompt: String = ""
var check_interval: float = 20.0
var _timer: float = 0.0

func _ready() -> void:
	_choose_personality()

func _process(delta: float) -> void:
	if sim == null or upgrade_manager == null or ollama == null:
		return
	_timer += delta * sim.time_scale
	if _timer >= check_interval:
		_timer = 0.0
		_consider()

func _choose_personality() -> void:
	var roll = randi() % 3
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
	_log("[color=gray]LLM persona: %s[/color]" % personality)

func _consider() -> void:
	var bank = sim.sim_state.bank
	var owned: Array = upgrade_manager.owned_upgrades.duplicate()
	var available = upgrade_manager.get_available_upgrades(bank)
	if available.is_empty():
		_log("[color=gray]LLM: holding (no available upgrades yet)[/color]")
		return
	var prompt = _build_prompt(bank, owned, available)
	var resp = await ollama.generate(prompt, "", 0.2, 120)
	if not resp.get("ok", false):
		_log("[color=gray]LLM fallback (error)[/color]")
		_upgrade_fallback(available, bank)
		return
	var text: String = resp.get("text", "")
	var choice = _parse_choice(text)
	if choice == "" or choice == "wait":
		_log("[color=gray]LLM waits: %s[/color]" % text.strip_edges())
		return
	var ok = upgrade_manager.execute_choice(choice)
	if ok:
		_log("[color=cyan]LLM bought %s[/color]" % choice)
	else:
		_log("[color=gray]LLM choice unavailable %s[/color]" % choice)

func _build_prompt(bank: float, owned: Array, available: Array) -> String:
	var avail_str = ""
	for a in available:
		avail_str += "- id:%s cost:%d desc:%s\n" % [a.get("id",""), int(a.get("cost",0)), a.get("desc","")]
	return """You are an airport AI manager with persona: %s.
Bank: %d
Owned upgrades: %s
Available upgrades:\n%s
Decide one action: choose an upgrade id to buy now, or 'wait' to save for bigger purchases.
Return a JSON object: {"choice":"<id or wait>","reason":"short reason"}.
""" % [persona_prompt, int(bank), ",".join(owned), avail_str]

func _parse_choice(txt: String) -> String:
	var start = txt.find("{")
	var end = txt.rfind("}")
	if start == -1 or end == -1 or end <= start:
		return ""
	var json_text = txt.substr(start, end - start + 1)
	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("choice"):
		return str(parsed["choice"])
	return ""

func _upgrade_fallback(available: Array, bank: float) -> void:
	# simple fallback: buy cheapest affordable
	var affordable = available.filter(func(a): return a.get("cost", 0) <= bank)
	if affordable.is_empty():
		return
	affordable.sort_custom(func(a,b): return a.get("cost",0) < b.get("cost",0))
	var choice = affordable[0].get("id","")
	var ok = upgrade_manager.execute_choice(choice)
	if ok:
		_log("[color=cyan]Heuristic bought %s[/color]" % choice)

func _log(msg: String) -> void:
	if console_label:
		console_label.append_text(msg + "\n")
		console_label.scroll_to_line(console_label.get_line_count())
	print(msg)
