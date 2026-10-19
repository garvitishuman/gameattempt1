extends Control
# Main menu: nickname, server, create / join a lobby by name + password.

signal create_requested(server: String, lobby: String, password: String, max_players: int, nick: String)
signal join_requested(server: String, lobby: String, password: String, nick: String)

const UI = preload("res://scripts/ui.gd")
const Invite = preload("res://scripts/invite.gd")
const SETTINGS := "user://settings.cfg"

const ADJ := ["swift", "cosmic", "sharp", "quiet", "radiant", "odd", "prime", "steep", "smooth", "wild", "lucky", "silent"]
const NOUN := ["sine", "vector", "tangent", "limit", "matrix", "asymptote", "integral", "parabola", "axis", "origin", "slope", "root"]

var mode := "create"
var nick_edit: LineEdit
var server_edit: LineEdit
var lobby_edit: LineEdit
var pw_edit: LineEdit
var max_spin: SpinBox
var max_row: HBoxContainer
var go_button: Button
var create_tab: Button
var join_tab: Button
var error_label: Label
var invite_edit: LineEdit
var help_dialog: AcceptDialog

func _ready() -> void:
	UI.full_rect(self)
	var center := CenterContainer.new()
	UI.full_rect(center)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var title := UI.label("GRAPH DUEL", 44, UI.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UI.label("Plot curves. Hide on the plane. Outlast everyone.", 15, UI.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	create_tab = UI.button("Create room")
	join_tab = UI.button("Join room")
	for b in [create_tab, join_tab]:
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
	create_tab.pressed.connect(func(): set_mode("create"))
	join_tab.pressed.connect(func(): set_mode("join"))
	v.add_child(tabs)

	nick_edit = _field(v, "Your name", "e.g. Garvit")
	nick_edit.max_length = 16

	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 6)
	lobby_edit = _field_in(lrow, "Lobby name", "pick one, or roll a random one")
	lobby_edit.max_length = 24
	var rl := UI.button("Random")
	rl.pressed.connect(func(): lobby_edit.text = "%s-%s-%d" % [ADJ.pick_random(), NOUN.pick_random(), randi() % 90 + 10])
	lrow.add_child(rl)
	v.add_child(lrow)

	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 6)
	pw_edit = _field_in(prow, "Password", "shared with the people you invite")
	pw_edit.max_length = 32
	pw_edit.secret = true
	var show := CheckBox.new()
	show.text = "Show"
	show.toggled.connect(func(on: bool): pw_edit.secret = not on)
	prow.add_child(show)
	var rp := UI.button("Random")
	rp.pressed.connect(func():
		var chars := "abcdefghjkmnpqrstuvwxyz23456789"
		var s := ""
		for i in range(6):
			s += chars[randi() % chars.length()]
		pw_edit.text = s
		show.button_pressed = true)
	prow.add_child(rp)
	v.add_child(prow)

	max_row = HBoxContainer.new()
	max_row.add_child(UI.label("Max players (you decide)", 15, UI.MUTED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	max_row.add_child(sp)
	max_spin = SpinBox.new()
	max_spin.min_value = 2
	max_spin.max_value = 8
	max_spin.value = 4
	max_row.add_child(max_spin)
	v.add_child(max_row)

	var sv := HBoxContainer.new()
	server_edit = _field_in(sv, "Server", "wss://your-service.onrender.com (deploy server first)")
	v.add_child(sv)

	go_button = UI.button("Create lobby", 46.0)
	go_button.add_theme_font_size_override("font_size", 20)
	go_button.pressed.connect(_submit)
	v.add_child(go_button)

	error_label = UI.label("", 15, UI.BAD)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(error_label)

	var irow := HBoxContainer.new()
	irow.add_theme_constant_override("separation", 6)
	invite_edit = _field_in(irow, "Have an invite link?", "paste graphduel://join?... here")
	var ib := UI.button("Use link")
	ib.pressed.connect(_use_invite)
	irow.add_child(ib)
	v.add_child(irow)

	var hb := UI.button("How to play")
	hb.pressed.connect(func(): help_dialog.popup_centered())
	v.add_child(hb)

	help_dialog = AcceptDialog.new()
	help_dialog.title = "How to play"
	help_dialog.dialog_text = "THE PLANE\nA cartesian plane, x and y from -10 to 10, four quadrants. Your character is a circle with area 1 unit². Other players' positions are hidden from you, and theirs from everyone else.\n\nSTART\nEveryone secretly places their circle. When all are placed, the game begins.\n\nA ROUND\n1. Turn by turn, each player plants ONE curve y = f(x), designed on the scientific calculator (or typed on the keyboard, or picked from a subject pack). You see a live preview before you plant it. Only you can see your own curves.\n2. After everyone has planted, every player relocates their circle to any spot on the plane.\n3. Anyone whose circle touches a curve planted by someone else takes damage: more the closer the curve passes to the circle's centre. Both attacker and victim learn about the hit.\n\nCurves stay on the plane for 3 rounds, so staying put is risky. You have 100 HP. Last player standing wins."
	help_dialog.min_size = Vector2i(640, 0)
	add_child(help_dialog)

	_load_settings()
	set_mode("create")
	if lobby_edit.text == "":
		lobby_edit.text = "%s-%s-%d" % [ADJ.pick_random(), NOUN.pick_random(), randi() % 90 + 10]

func _field_in(parent: Control, caption: String, placeholder: String) -> LineEdit:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.add_child(UI.label(caption, 13, UI.MUTED))
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 36)
	e.text_submitted.connect(func(_t: String): _submit())
	col.add_child(e)
	parent.add_child(col)
	return e

func _field(parent: Control, caption: String, placeholder: String) -> LineEdit:
	var holder := HBoxContainer.new()
	parent.add_child(holder)
	return _field_in(holder, caption, placeholder)

func set_mode(m: String) -> void:
	mode = m
	create_tab.button_pressed = (m == "create")
	join_tab.button_pressed = (m == "join")
	max_row.visible = (m == "create")
	go_button.text = "Create lobby" if m == "create" else "Join lobby"
	error_label.text = ""

func set_busy(on: bool) -> void:
	go_button.disabled = on
	if on:
		go_button.text = "Connecting..."
	else:
		set_mode(mode)

func show_error(msg: String) -> void:
	set_busy(false)
	error_label.text = msg

func _use_invite() -> void:
	var inv := Invite.parse(invite_edit.text)
	if inv.is_empty():
		error_label.text = "That doesn't look like a Graph Duel invite link."
		return
	lobby_edit.text = inv["lobby"]
	pw_edit.text = inv["pw"]
	if inv["server"] != "":
		server_edit.text = inv["server"]
	set_mode("join")
	invite_edit.text = ""
	if nick_edit.text.strip_edges() == "":
		nick_edit.grab_focus()
		error_label.text = "Invite loaded. Enter your name and press Join."

func apply_invite_text(t: String) -> void:
	invite_edit.text = t
	_use_invite()

func _submit() -> void:
	if go_button.disabled:
		return
	var nick := nick_edit.text.strip_edges()
	var lobby := lobby_edit.text.strip_edges()
	var pw := pw_edit.text
	var server := server_edit.text.strip_edges()
	if nick == "":
		return show_error("Enter your name.")
	if lobby == "":
		return show_error("Enter a lobby name.")
	if pw == "":
		return show_error("Enter a password.")
	if server == "":
		return show_error("Set your multiplayer server address first. For online play, deploy the server and enter its wss:// URL. localhost only works when the server is running on this same device.")
	if not (server.begins_with("ws://") or server.begins_with("wss://")):
		return show_error("Server address must start with ws:// or wss://")
	_save_settings()
	error_label.text = ""
	set_busy(true)
	if mode == "create":
		create_requested.emit(server, lobby, pw, int(max_spin.value), nick)
	else:
		join_requested.emit(server, lobby, pw, nick)

func _load_settings() -> void:
	var cf := ConfigFile.new()
	var ok := cf.load(SETTINGS) == OK
	nick_edit.text = cf.get_value("player", "nick", "") if ok else ""
	server_edit.text = cf.get_value("player", "server", "") if ok else ""

func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "nick", nick_edit.text.strip_edges())
	cf.set_value("player", "server", server_edit.text.strip_edges())
	cf.save(SETTINGS)
