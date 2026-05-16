class_name DataTable extends PanelContainer

# Tabla genérica con headers + rows. Usada en Dashboard para "Clasificación
# Liga" o cualquier listado tabular.
#
# Cada column es un Dictionary: {key: String, label: String, width: float,
# align: "left"|"right"|"center", color_func: Callable (opcional)}.
# Cada row es un Dictionary con claves correspondientes a column.key.
#
# Si una row tiene `highlight: true`, se pinta con fondo accent (útil para
# resaltar la fila del user en la clasificación).

const ROW_HEIGHT: int = 28

var _columns: Array = []     # Array de Dictionary
var _rows: Array = []        # Array de Dictionary
var _title: String = ""
var _max_rows_visible: int = 0  # 0 = sin límite
var _vbox: VBoxContainer


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_panel_style()
	_rebuild()


# columns: [{key, label, width(int, opcional), align(str), color_func(Callable)}]
# rows: [{<col.key>: value, ..., highlight: bool}]
# title: encabezado encima de la tabla. Si "", no se dibuja
# max_rows: si > 0, sólo se renderizan las primeras N filas (usado para top 5)
func setup(columns: Array, rows: Array, title: String = "", max_rows: int = 0) -> void:
	_columns = columns
	_rows = rows
	_title = title
	_max_rows_visible = max_rows
	if is_inside_tree():
		_rebuild()


func _apply_panel_style() -> void:
	var theme: UITheme = UIThemeManager.get_current()
	var sb := StyleBoxFlat.new()
	sb.bg_color = theme.bg_card
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)


func _rebuild() -> void:
	var theme: UITheme = UIThemeManager.get_current()
	for c in get_children():
		c.queue_free()

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 2)
	add_child(_vbox)

	if _title != "":
		var title_lbl := Label.new()
		title_lbl.text = _title.to_upper()
		title_lbl.add_theme_font_size_override("font_size", 11)
		title_lbl.add_theme_color_override("font_color", theme.text_secondary)
		_vbox.add_child(title_lbl)
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 4)
		_vbox.add_child(spacer)

	# Header
	var header_row := _build_row(null, true)
	_vbox.add_child(header_row)

	# Separador
	var sep := ColorRect.new()
	sep.color = theme.border_subtle
	sep.custom_minimum_size = Vector2(0, 1)
	_vbox.add_child(sep)

	# Rows
	var count: int = _rows.size()
	if _max_rows_visible > 0:
		count = min(count, _max_rows_visible)
	for i in range(count):
		_vbox.add_child(_build_row(_rows[i], false))


func _build_row(row_data, is_header: bool) -> Control:
	var theme: UITheme = UIThemeManager.get_current()
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	if not is_header and row_data != null and bool(row_data.get("highlight", false)):
		var sb := StyleBoxFlat.new()
		sb.bg_color = theme.sidebar_active_bg
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		pc.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	pc.add_child(hbox)

	for col: Dictionary in _columns:
		var key: String = String(col.get("key", ""))
		var width: int = int(col.get("width", 0))
		var align: String = String(col.get("align", "left"))
		var lbl := Label.new()
		var txt: String = ""
		if is_header:
			txt = String(col.get("label", "")).to_upper()
		elif row_data != null:
			txt = String(row_data.get(key, ""))
		lbl.text = txt
		lbl.add_theme_font_size_override("font_size", 13 if not is_header else 11)
		var color: Color
		if is_header:
			color = theme.text_secondary
		elif row_data != null and bool(row_data.get("highlight", false)):
			color = theme.sidebar_active_text
		else:
			color = theme.text_primary
		# Override con color_func si existe
		if not is_header and row_data != null and col.has("color_func"):
			var cf: Callable = col["color_func"]
			if cf.is_valid():
				color = cf.call(row_data)
		lbl.add_theme_color_override("font_color", color)

		match align:
			"right": lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			"center": lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_: lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

		if width > 0:
			lbl.custom_minimum_size = Vector2(width, 0)
		else:
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(lbl)

	return pc
