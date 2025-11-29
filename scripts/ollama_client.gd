extends Node

class_name OllamaClient

@export var base_url: String = "http://127.0.0.1:11434"
@export var model: String = "qwen3:1.7b"

var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)

func generate(prompt: String, custom_model: String = "", temperature: float = 0.15, max_tokens: int = 256) -> Dictionary:
	var use_model := custom_model if custom_model != "" else model
	var url := "%s/api/generate" % base_url
	var headers := ["Content-Type: application/json"]
	var body := {
		"model": use_model,
		"prompt": prompt,
		"stream": false,
		"format": "json",
		"think": false,
		"options": {
			"temperature": temperature,
			"num_predict": max_tokens
		}
	}
	var body_str := JSON.stringify(body)
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body_str)
	if err != OK:
		return { "ok": false, "error": "HTTP request error %d" % err }
	var result = await _http.request_completed
	var status: int = result[1]
	var raw_body: PackedByteArray = result[3]
	if status != 200:
		return { "ok": false, "error": "HTTP %d" % status, "status": status }
	var raw_text := raw_body.get_string_from_utf8()
	var thinking_text: String = ""
	var inner_json: Dictionary = {}
	var inner_text: String = ""

	var parsed = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return { "ok": false, "error": "Invalid JSON from Ollama", "raw": raw_text }

	if parsed.has("thinking"):
		thinking_text = str(parsed["thinking"]).strip_edges()

	if not parsed.has("response"):
		return { "ok": false, "error": "No 'response' field in Ollama reply", "raw": raw_text }

	var resp_field = parsed["response"]
	if typeof(resp_field) == TYPE_DICTIONARY:
		inner_json = resp_field
		inner_text = JSON.stringify(resp_field)
	elif typeof(resp_field) == TYPE_STRING:
		inner_text = String(resp_field).strip_edges()
		var inner_parsed = JSON.parse_string(inner_text)
		if typeof(inner_parsed) == TYPE_DICTIONARY:
			inner_json = inner_parsed
	else:
		inner_text = str(resp_field)

	if inner_text == "":
		return { "ok": false, "error": "Empty 'response' field from Ollama", "raw": raw_text }

	return {
		"ok": true,
		"text": inner_text,   # JSON string for the inner object
		"json": inner_json,   # Parsed inner JSON object when available
		"raw": raw_text,
		"thinking": thinking_text
	}
