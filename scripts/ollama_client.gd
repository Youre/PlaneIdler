extends Node

class_name OllamaClient

@export var base_url: String = "http://127.0.0.1:11434"
@export var model: String = "qwen3:4b"

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
	var text := raw_body.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("response"):
		return { "ok": false, "error": "Bad payload", "payload": text }
	return { "ok": true, "text": str(parsed["response"]) }
