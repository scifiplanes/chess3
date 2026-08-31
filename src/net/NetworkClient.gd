extends Node
class_name NetworkClient

signal connected(room_code: String, player: String)
signal disconnected(reason: String)
signal hello_received(msg: Dictionary)
signal state_received(state: Dictionary)
signal patch_received(ops: Array)
signal error_received(err: Dictionary)

@export var http_base_url := "http://localhost:8787"

var room_code: String = ""
var player: String = ""
var token: String = ""

var client_seq: int = 0
var last_server_seq: int = 0
var state_version: int = 0

var net_state: Dictionary = {}

var _http: HTTPRequest
var _ws := WebSocketPeer.new()
var _ws_connected := false

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)

func ws_is_connected() -> bool:
	return _ws_connected and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func create_room() -> void:
	_http_cancel()
	var url := "%s/room/create" % http_base_url
	_http.request(url, [], HTTPClient.METHOD_POST, "")
	_http.request_completed.connect(_on_create_completed, CONNECT_ONE_SHOT)

func join_room(p_room_code: String) -> void:
	_http_cancel()
	var url := "%s/room/join" % http_base_url
	var body := JSON.stringify({"room_code": p_room_code})
	_http.request(url, ["content-type: application/json"], HTTPClient.METHOD_POST, body)
	_http.request_completed.connect(_on_join_completed, CONNECT_ONE_SHOT)

func connect_ws() -> void:
	if token == "":
		emit_signal("disconnected", "missing_token")
		return
	var ws_url := http_base_url.replace("http://", "ws://").replace("https://", "wss://")
	ws_url = "%s/ws?token=%s" % [ws_url, token.uri_encode()]
	var err := _ws.connect_to_url(ws_url)
	if err != OK:
		emit_signal("disconnected", "ws_connect_failed_%d" % int(err))
		return

func send_intent(kind: String, payload: Dictionary = {}) -> void:
	if not ws_is_connected():
		return
	client_seq += 1
	var turn := int(net_state.get("turn", 1))
	var intent := payload.duplicate(true)
	intent["k"] = kind
	var msg := {
		"t": "intent",
		"seq": client_seq,
		"turn": turn,
		"intent": intent,
	}
	_ws.send_text(JSON.stringify(msg))

func _process(_dt: float) -> void:
	if _ws == null:
		return
	_ws.poll()

	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _ws_connected:
		_ws_connected = true
		emit_signal("connected", room_code, player)
	elif st == WebSocketPeer.STATE_CLOSED and _ws_connected:
		_ws_connected = false
		emit_signal("disconnected", "ws_closed")

	while _ws.get_available_packet_count() > 0:
		var raw := _ws.get_packet().get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(raw)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		_on_ws_message(parsed as Dictionary)

func _on_ws_message(msg: Dictionary) -> void:
	var t := str(msg.get("t", ""))
	if msg.has("server_seq"):
		last_server_seq = int(msg.get("server_seq", last_server_seq))
	if msg.has("state_version"):
		state_version = int(msg.get("state_version", state_version))

	match t:
		"hello":
			player = str(msg.get("player", player))
			room_code = str(msg.get("room", room_code))
			emit_signal("hello_received", msg)
		"state":
			room_code = str(msg.get("room", room_code))
			net_state = (msg.get("state", {}) as Dictionary).duplicate(true)
			emit_signal("state_received", net_state)
		"patch":
			var ops: Array = msg.get("ops", [])
			emit_signal("patch_received", ops)
		"error":
			emit_signal("error_received", msg.get("error", {}))
		_:
			pass

func _http_cancel() -> void:
	if _http == null:
		return
	_http.cancel_request()

func _on_create_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_on_room_http_completed(result, response_code, body)

func _on_join_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_on_room_http_completed(result, response_code, body)

func _on_room_http_completed(result: int, response_code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		emit_signal("disconnected", "http_failed_%d" % int(result))
		return
	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		emit_signal("disconnected", "http_bad_json")
		return
	var d: Dictionary = parsed
	if response_code < 200 or response_code >= 300:
		emit_signal("disconnected", "http_%d_%s" % [int(response_code), JSON.stringify(d)])
		return

	room_code = str(d.get("room_code", ""))
	token = str(d.get("token", ""))
	player = str(d.get("player", ""))
	client_seq = 0
	connect_ws()

