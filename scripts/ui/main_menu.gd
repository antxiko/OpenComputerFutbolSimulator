extends Control

# Menú principal del simulador.
# Tres botones: Nueva partida / Continuar / Salir.
# - Nueva partida: muestra selector de equipo, luego va a game_hub con start_mode=new_game.
# - Continuar: abre modal con lista de slots para elegir cuál cargar.
# - Salir: cierra el juego.

var continue_button: Button
var status_label: Label


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()


func _build_ui() -> void:
	# Fondo opaco
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.10, 0.16)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)

	# Título
	var title := Label.new()
	title.text = "OpenComputerFutbolSimulator"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Simulador de La Liga · 20 temporadas"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	vbox.add_child(_make_spacer(20))

	# Botones
	var new_game_btn := _make_button("🆕  Nueva partida", _on_new_game)
	new_game_btn.custom_minimum_size = Vector2(280, 40)
	vbox.add_child(new_game_btn)

	continue_button = _make_button("📂  Continuar partida", _on_continue)
	continue_button.custom_minimum_size = Vector2(280, 40)
	vbox.add_child(continue_button)

	var quit_btn := _make_button("✖  Salir", _on_quit)
	quit_btn.custom_minimum_size = Vector2(280, 40)
	vbox.add_child(quit_btn)

	vbox.add_child(_make_spacer(20))

	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)

	_refresh_continue_state()


func _make_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	return b


func _make_spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _refresh_continue_state() -> void:
	# Desactivar Continuar si no hay ningún save en disco
	var slots: Array = SaveSystem.list_saves()
	if slots.is_empty():
		continue_button.disabled = true
		status_label.text = "(no hay partidas guardadas)"
	else:
		continue_button.disabled = false
		var n: int = slots.size()
		var top: Dictionary = slots[0]
		var label: String = "Última: %s · año %d" % [String(top.get("saved_at", "")), int(top.get("year", 0))]
		if n == 1:
			status_label.text = label
		else:
			status_label.text = "%d slots guardados — %s" % [n, label]


# ============================================================================
# Acciones
# ============================================================================
func _on_new_game() -> void:
	# Cargar datos solo para mostrar la lista de equipos
	var loaded := DataLoader.load_all_teams(2026)
	if loaded.errors.size() > 0:
		status_label.text = "Error cargando equipos."
		return

	var popup := AcceptDialog.new()
	popup.title = "Elige tu club"
	popup.size = Vector2(380, 200)
	add_child(popup)
	var vbox := VBoxContainer.new()
	popup.add_child(vbox)
	var lbl := Label.new()
	lbl.text = "¿A qué equipo vas a dirigir esta temporada?"
	vbox.add_child(lbl)
	var option := OptionButton.new()
	var teams: Array = loaded.teams.values()
	teams.sort_custom(func(a: Team, b: Team) -> bool: return a.name < b.name)
	for i in teams.size():
		var t: Team = teams[i]
		option.add_item("%s (%s)" % [t.name, t.division.capitalize()], i)
	vbox.add_child(option)
	var hint := Label.new()
	hint.text = "(Pulsa OK para confirmar)"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(hint)

	popup.confirmed.connect(func() -> void:
		var sel: int = option.selected
		if sel >= 0 and sel < teams.size():
			GameSession.start_mode = "new_game"
			GameSession.pending_user_team_id = teams[sel].id
			get_tree().change_scene_to_file("res://scenes/game_hub.tscn")
		popup.queue_free()
	)
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()


func _on_continue() -> void:
	var dialog := SaveLoadDialog.new()
	add_child(dialog)
	dialog.open_load(func(slot: String, action: String) -> void:
		dialog.queue_free()
		if action != "load":
			return
		GameSession.start_mode = "load"
		GameSession.pending_user_team_id = ""
		GameSession.pending_load_slot = slot
		get_tree().change_scene_to_file("res://scenes/game_hub.tscn")
	)


func _on_quit() -> void:
	get_tree().quit()
