extends Node

class_name LLMAgent

@export var ollama: Node
@export var upgrade_manager: Node
@export var sim: Node
@export var console_label: RichTextLabel

var personality: String = ""
var persona_prompt: String = ""
var base_interval: float = 30.0
var _timer: float = 0.0
var _upgrade_chance_denominator: int = 6

func _ready() -> void:
	_choose_personality()
	randomize()

func _process(delta: float) -> void:
	if sim == null or upgrade_manager == null or ollama == null:
		return
	_timer += delta
	var interval = base_interval / max(sim.time_scale, 0.01)
	if _timer >= interval:
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
	_log("[color=gray]Airport CEO persona: %s[/color]" % personality)

func _consider() -> void:
	if ollama == null:
		return
	var bank = sim.sim_state.bank
	var owned: Array = upgrade_manager.owned_upgrades.duplicate()
	var available = upgrade_manager.get_available_upgrades(bank)
	var use_upgrades: bool = false
	if not available.is_empty():
		use_upgrades = _roll_for_upgrades()
	var prompt: String
	if use_upgrades:
		prompt = _build_upgrade_prompt(bank, owned, available)
	else:
		prompt = _build_flavor_prompt(bank, owned, available, _get_recent_console_lines(10))
	var resp = await ollama.generate(prompt, "", 0.2, 200)
	if not resp.get("ok", false):
		_log("[color=gray]Airport CEO error:[/color] upgrade decision fell back to heuristic.")
		if use_upgrades:
			_upgrade_fallback(available, bank)
		return
	var raw_text: String = resp.get("text", "").strip_edges()
	if raw_text == "":
		raw_text = resp.get("raw", "").strip_edges()
	var statement: String = ""
	var action: String = "wait"
	if raw_text != "":
		var parsed = JSON.parse_string(raw_text)
		if typeof(parsed) == TYPE_DICTIONARY:
			statement = str(parsed.get("statement", "")).strip_edges()
			action = str(parsed.get("action", "wait")).strip_edges()
	if statement == "":
		statement = "I'm going to hold funds for now and watch traffic."
	_log("[color=gray]Airport CEO:[/color] %s" % statement)
	# Optional: act on the chosen upgrade if it is valid and affordable.
	if use_upgrades and action != "" and action != "wait":
		var ok = upgrade_manager.execute_choice(action)
		if ok:
			_log("[color=cyan]Airport CEO bought upgrade:[/color] %s" % action)

func _roll_for_upgrades() -> bool:
	var denom: int = _upgrade_chance_denominator
	if denom < 1:
		denom = 1
	var roll: int = randi() % denom
	var success: bool = (roll == 0)
	if success or denom == 1:
		_upgrade_chance_denominator = 6
	else:
		_upgrade_chance_denominator = denom - 1
	return success

func _build_upgrade_prompt(bank: float, owned: Array, available: Array) -> String:
	var avail_str: String = ""
	for a in available:
		avail_str += "- id:%s cost:%d desc:%s\n" % [a.get("id", ""), int(a.get("cost", 0)), a.get("desc", "")]
	var owned_str: String = "none" if owned.is_empty() else ",".join(owned)
	var valid_ids: Array = []
	for a in available:
		valid_ids.append(a.get("id", ""))
	var id_list: String = ",".join(valid_ids)
	return """You are an airport AI manager NPC in an idle game.
Your persona: %s
Current bank balance (whole dollars): %d
Owned upgrades: %s
Available upgrades (id, cost, description):
%s

Think silently and then respond ONLY with a single JSON object on one line.
The JSON must have exactly these keys:
- "statement": one friendly sentence (8-25 words) describing what you decided or are thinking for the player to read.
- "action": either one of [%s] or "wait".

Examples:
{"statement":"We don't have enough cash yet, so I'll wait and watch traffic.","action":"wait"}
{"statement":"Traffic is backing up, so I'll spend on more GA stands now.","action":"ga_pack"}

Now output ONLY the JSON object, with no extra commentary:
""" % [persona_prompt, int(bank), owned_str, avail_str, id_list]

func _build_flavor_prompt(bank: float, owned: Array, available: Array, recent_messages: Array) -> String:
	var events_str: String = ""
	for m in recent_messages:
		events_str += "- %s\n" % m
	var persona: String = persona_prompt
	if persona == "":
		persona = "I run the airport with a balanced, thoughtful style."
	return """You are the Airport CEO NPC in an idle airport game.
Your persona: %s
Current bank balance: %d

Recent events at the airport (most recent first):
%s

For this call, ignore making concrete upgrade decisions and just talk about life as an airport CEO:
airplanes you like, how traffic feels, what you're watching for next, etc.

Respond ONLY with a single JSON object on one line with:
- "statement": one friendly sentence (8-25 words) describing your thoughts for the player to read.
- "action": always "wait".

Example:
{"statement":"I'm enjoying the steady stream of GA traffic while we plan the airport's next big step.","action":"wait"}

Now output ONLY the JSON object, with no extra commentary:
""" % [persona, int(bank), events_str]

func _get_recent_console_lines(max_lines: int) -> Array:
	if console_label == null:
		return []
	var text: String = console_label.get_parsed_text()
	var lines: Array = text.split("\n")
	var result: Array = []
	var start: int = max(0, lines.size() - max_lines)
	for i: int in range(start, lines.size()):
		var s := String(lines[i]).strip_edges()
		if s != "":
			result.append(s)
	return result

func _summarize_statement(full_text: String) -> String:
	# Take the first non-empty, non-prompty line, then first sentence.
	var lines = full_text.split("\n")
	var first_line := ""
	for l in lines:
		var s = String(l).strip_edges()
		if s == "":
			continue
		# Skip lines that look like prompt echo, e.g. "We are given:"
		if s.ends_with(":"):
			continue
		first_line = s
		break
	if first_line == "":
		first_line = full_text.strip_edges()
	var dot_idx = first_line.find(".")
	if dot_idx != -1:
		return first_line.substr(0, dot_idx + 1)
	return first_line

func _strip_think_blocks(text: String) -> String:
	var result := text
	while true:
		var start := result.find("<think>")
		if start == -1:
			break
		var end := result.find("</think>", start)
		if end == -1:
			# No closing tag; drop everything after <think>
			result = result.substr(0, start)
			break
		var after := end + "</think>".length()
		result = result.substr(0, start) + result.substr(after)
	return result.strip_edges()

func _upgrade_fallback(available: Array, bank: float) -> void:
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
