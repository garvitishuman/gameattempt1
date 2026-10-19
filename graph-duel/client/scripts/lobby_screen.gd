extends Control
# Waiting room: shows who joined, password + invite link, host can start.

signal start_requested
signal leave_requested

const UI = preload("res://scripts/ui.gd")
const Invite = preload("res://scripts/invite.gd")

var title_label: Label
var count_label: Label
var pw_label: Label
var invite_edit: LineEdit
var list_box: VBoxContainer
var start_button: Button
var hint_label: Label
var copy_button: Button

var lobby_name := ""
var password := ""
var server_url := ""
var my_id := 0
var max_players := 2
var creator := 0
var players: Array = []

func _ready() -> void:
	UI.full_rect(self)
	var center := CenterContainer.new()
	UI.full_rect(center)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	v.add_child(UI.label("LOBBY", 14, UI.MUTED))
	title_label = UI.label("", 34, UI.ACCENT)
	v.add_child(title_label)
	pw_label = UI.label("", 16, UI.TEXT)
	v.add_child(pw_label)

	v.add_child(UI.label("Invite link (lobby + password + server)", 13, UI.MUTED))
	var irow := HBoxContainer.new()
	irow.add_theme_constant_override("separation", 6)
	invite_edit = LineEdit.new()
	invite_edit.editable = false
	invite_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	irow.add_child(invite_edit)
	copy_button = UI.button("Copy link")
	copy_button.pressed.connect(func():
		DisplayServer.clipboard_set(invite_edit.text)
		copy_button.text = "Copied!"
		get_tree().create_timer(1.5).timeout.connect(func(): copy_button.text = "Copy link"))
	irow.add_child(copy_button)
	v.add_child(irow)

	count_label = UI.label("", 16, UI.MUTED)
	v.add_child(count_label)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 4)
	v.add_child(list_box)

	hint_label = UI.label("", 15, UI.MUTED)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint_label)

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	var leave := UI.button("Leave", 44.0)
	leave.pressed.connect(func(): leave_requested.emit())
	brow.add_child(leave)
	start_button = UI.button("Start game", 44.0)
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.add_theme_font_size_override("font_size", 20)
	start_button.pressed.connect(func(): start_requested.emit())
	brow.add_child(start_button)
	v.add_child(brow)
	_render()

func set_info(lobby: String, pw: String, server: String, you: int) -> void:
	lobby_name = lobby
	password = pw
	server_url = server
	my_id = you
	if is_node_ready():
		_render()

func update_players(max_p: int, creator_id: int, plist: Array) -> void:
	max_players = max_p
	creator = creator_id
	players = plist
	if is_node_ready():
		_render()

func _render() -> void:
	title_label.text = lobby_name
	pw_label.text = "Password:  " + password
	invite_edit.text = Invite.build(server_url, lobby_name, password)
	count_label.text = "Players  %d / %d" % [players.size(), max_players]
	for ch in list_box.get_children():
		ch.queue_free()
	var order: Array = []
	for p in players:
		order.append(int(p["id"]))
	for p in players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := ColorRect.new()
		dot.color = UI.color_for(order, int(p["id"]))
		dot.custom_minimum_size = Vector2(14, 14)
		var dc := CenterContainer.new()
		dc.add_child(dot)
		row.add_child(dc)
		var txt: String = p["name"]
		if int(p["id"]) == my_id:
			txt += "  (you)"
		if int(p["id"]) == creator:
			txt += "  - host"
		row.add_child(UI.label(txt, 18))
		list_box.add_child(row)
	var is_host := my_id == creator
	start_button.visible = is_host
	start_button.disabled = players.size() < 2
	if is_host:
		hint_label.text = "Share the invite link (or lobby name + password). Start whenever at least 2 players are in." if players.size() < 2 else "Ready when you are. You can also wait for more players (up to %d)." % max_players
	else:
		hint_label.text = "Waiting for the host to start the game..."
