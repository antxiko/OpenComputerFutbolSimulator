class_name SaveLoadDialog extends AcceptDialog

# Modal de guardar/cargar partida con multi-slot.
#
# Uso:
#   var dialog := SaveLoadDialog.new()
#   add_child(dialog)
#   dialog.open_save(callback)   # callback(slot: String, action: "save"|"cancel")
#   dialog.open_load(callback)   # callback(slot: String, action: "load"|"cancel")
#
# El usuario puede:
#   - SAVE mode: sobrescribir un slot existente, eliminar uno, o crear nuevo con nombre.
#   - LOAD mode: cargar un slot existente o eliminar.

enum Mode { SAVE, LOAD }

const TEAM_NAMES := {
	# Atajo para mostrar nombres legibles sin tener que cargar todo el data
	"athletic_club": "Athletic", "fc_barcelona": "Barça", "real_madrid": "R. Madrid",
	"atletico_madrid": "Atlético", "real_sociedad": "Real Sociedad",
	"villarreal_cf": "Villarreal", "real_betis": "Betis", "sevilla_fc": "Sevilla",
	"valencia_cf": "Valencia", "girona_fc": "Girona", "ca_osasuna": "Osasuna",
	"rayo_vallecano": "Rayo", "celta_vigo": "Celta", "rcd_mallorca": "Mallorca",
	"getafe_cf": "Getafe", "deportivo_alaves": "Alavés", "rcd_espanyol": "Espanyol",
	"levante_ud": "Levante", "elche_cf": "Elche", "real_oviedo": "Oviedo",
}

var _mode: int = Mode.LOAD
var _callback: Callable = Callable()
var _slot_list_container: VBoxContainer
var _new_slot_input: LineEdit
var _new_slot_section: VBoxContainer
var _status_label: Label


func _init() -> void:
	# Defaults para AcceptDialog
	min_size = Vector2(560, 420)
	get_ok_button().visible = false  # No usamos OK; las acciones son por slot.
	add_cancel_button("Cerrar")


func open_save(cb: Callable) -> void:
	_mode = Mode.SAVE
	_callback = cb
	title = "💾 Guardar partida"
	_build_body()
	popup_centered()


func open_load(cb: Callable) -> void:
	_mode = Mode.LOAD
	_callback = cb
	title = "📂 Cargar partida"
	_build_body()
	popup_centered()


func _build_body() -> void:
	# Limpia contenido previo
	for c in get_children():
		if c is VBoxContainer:
			c.queue_free()

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	# Header
	var header := Label.new()
	header.text = ("Selecciona un slot para guardar o crea uno nuevo:" if _mode == Mode.SAVE
			else "Selecciona la partida que quieres cargar:")
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	vbox.add_child(header)

	# Lista de slots (scroll)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 280)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_slot_list_container = VBoxContainer.new()
	_slot_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_list_container.add_theme_constant_override("separation", 4)
	scroll.add_child(_slot_list_container)

	_refresh_slot_list()

	# Nuevo slot (solo en SAVE mode)
	_new_slot_section = VBoxContainer.new()
	if _mode == Mode.SAVE:
		var sep := HSeparator.new()
		_new_slot_section.add_child(sep)
		var new_label := Label.new()
		new_label.text = "Crear nuevo slot:"
		new_label.add_theme_font_size_override("font_size", 14)
		_new_slot_section.add_child(new_label)
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)
		_new_slot_input = LineEdit.new()
		_new_slot_input.placeholder_text = "Nombre del slot (ej: 'campaña athletic')"
		_new_slot_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_new_slot_input.text_submitted.connect(func(_t: String) -> void: _on_create_new_slot())
		hbox.add_child(_new_slot_input)
		var create_btn := Button.new()
		create_btn.text = "💾 Crear"
		create_btn.pressed.connect(_on_create_new_slot)
		hbox.add_child(create_btn)
		_new_slot_section.add_child(hbox)
	vbox.add_child(_new_slot_section)

	# Status
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	vbox.add_child(_status_label)


func _refresh_slot_list() -> void:
	for c in _slot_list_container.get_children():
		c.queue_free()
	var slots: Array = SaveSystem.list_saves()
	if slots.is_empty():
		var empty := Label.new()
		empty.text = "  (no hay partidas guardadas)"
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_slot_list_container.add_child(empty)
		return
	for slot_meta in slots:
		_slot_list_container.add_child(_make_slot_row(slot_meta))


func _make_slot_row(meta: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.18, 0.22)
	bg.border_color = Color(0.3, 0.35, 0.4)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 8
	bg.content_margin_right = 8
	bg.content_margin_top = 6
	bg.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", bg)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	# Info del slot (slot, año, jornada, equipo, fecha)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var slot: String = String(meta.get("slot", "?"))
	var year: int = int(meta.get("year", 0))
	var p_jor: int = int(meta.get("primera_jornada", 0))
	var user_team: String = String(meta.get("user_team_id", ""))
	var saved_at: String = String(meta.get("saved_at", ""))
	var career: int = int(meta.get("career_seasons", 0))

	var team_label: String = TEAM_NAMES.get(user_team, user_team) if user_team != "" else "(sin club)"

	var line1 := Label.new()
	line1.text = "📁 %s" % slot
	line1.add_theme_font_size_override("font_size", 14)
	line1.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	info.add_child(line1)

	var line2 := Label.new()
	line2.text = "Año %d-%d · J%d · %s%s" % [year, year + 1, p_jor, team_label,
			" · %d temp. completas" % career if career > 0 else ""]
	line2.add_theme_font_size_override("font_size", 14)
	line2.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	info.add_child(line2)

	var line3 := Label.new()
	line3.text = "🕒 %s" % saved_at
	line3.add_theme_font_size_override("font_size", 14)
	line3.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	info.add_child(line3)

	# Botones de acción
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	hbox.add_child(actions)

	if _mode == Mode.SAVE:
		var overwrite := Button.new()
		overwrite.text = "💾 Sobrescribir"
		overwrite.pressed.connect(func() -> void: _on_pick_slot(slot, "save"))
		actions.add_child(overwrite)
	else:
		var load_btn := Button.new()
		load_btn.text = "📂 Cargar"
		load_btn.pressed.connect(func() -> void: _on_pick_slot(slot, "load"))
		actions.add_child(load_btn)

	var del_btn := Button.new()
	del_btn.text = "🗑 Eliminar"
	del_btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	del_btn.pressed.connect(func() -> void: _on_delete_slot(slot))
	actions.add_child(del_btn)

	return panel


func _on_pick_slot(slot: String, action: String) -> void:
	if _callback.is_valid():
		_callback.call(slot, action)
	hide()


func _on_create_new_slot() -> void:
	var raw: String = _new_slot_input.text
	var slot: String = SaveSystem.sanitize_slot_name(raw)
	if slot.is_empty():
		_status_label.text = "Nombre inválido."
		return
	if SaveSystem.slot_exists(slot):
		_status_label.text = "Ya existe un slot '%s'. Pulsa 'Sobrescribir' en la lista o usa otro nombre." % slot
		return
	if _callback.is_valid():
		_callback.call(slot, "save")
	hide()


func _on_delete_slot(slot: String) -> void:
	# Confirmación inline en el status
	var confirm := ConfirmationDialog.new()
	confirm.title = "Eliminar slot"
	confirm.dialog_text = "¿Eliminar '%s'? Esta acción no se puede deshacer." % slot
	add_child(confirm)
	confirm.confirmed.connect(func() -> void:
		var ok: bool = SaveSystem.delete_save(slot)
		_status_label.text = ("Slot '%s' eliminado." % slot) if ok else ("No se pudo eliminar '%s'." % slot)
		confirm.queue_free()
		_refresh_slot_list()
	)
	confirm.canceled.connect(func() -> void: confirm.queue_free())
	confirm.popup_centered()
