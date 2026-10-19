extends Node
# Thin WebSocket JSON client for the Graph Duel server.

signal connected
signal closed(reason: String)
signal message(msg: Dictionary)

const CONNECT_TIMEOUT := 8.0

var ws := WebSocketPeer.new()
var active := false
var was_open := false
var waited := 0.0

func open_url(url: String) -> int:
	close_conn()
	ws = WebSocketPeer.new()
	var err := ws.connect_to_url(url)
	if err != OK:
		return err
	active = true
	was_open = false
	waited = 0.0
	return OK

func close_conn() -> void:
	if active:
		ws.close()
	active = false
	was_open = false

func is_open() -> bool:
	return active and ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func send_msg(d: Dictionary) -> void:
	if is_open():
		ws.send_text(JSON.stringify(d))

func _process(delta: float) -> void:
	if not active:
		return
	ws.poll()
	match ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			waited += delta
			if waited > CONNECT_TIMEOUT:
				ws.close()
				active = false
				closed.emit("Could not reach the server (timed out).")
		WebSocketPeer.STATE_OPEN:
			if not was_open:
				was_open = true
				connected.emit()
			while ws.get_available_packet_count() > 0:
				var txt := ws.get_packet().get_string_from_utf8()
				var j = JSON.parse_string(txt)
				if typeof(j) == TYPE_DICTIONARY:
					message.emit(j)
		WebSocketPeer.STATE_CLOSED:
			active = false
			closed.emit("Connection lost." if was_open else "Could not reach the server.")
