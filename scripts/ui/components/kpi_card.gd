class_name KpiCard extends PanelContainer

# Tarjeta KPI para el Dashboard. Muestra:
#   - icon (emoji string, ej. "📊") en badge circular con fondo accent translúcido
#   - title pequeño arriba (ej. "Posición Liga")
#   - value grande y prominente (ej. "5º")
#   - subtitle opcional (ej. "32 pts")
#   - trend opcional con flecha (ej. "▲ +2" verde, "▼ -1" rojo)

const CARD_WIDTH: int = 230
const CARD_HEIGHT: int = 124

var _title: String = ""
var _value: String = ""
var _subtitle: String = ""
var _trend: String = ""
var _trend_dir: String = ""  # "up" | "down" | "flat"
var _icon: String = ""
var _accent: Color = Color(0.86, 0.15, 0.15)


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_panel_style()
	_rebuild()


func setup(title: String, value: String, subtitle: String = "", trend: String = "", trend_dir: String = "flat", icon: String = "") -> void:
	_title = title
	_value = value
	_subtitle = subtitle
	_trend = trend
	_trend_dir = trend_dir
	_icon = icon
	if is_inside_tree():
		_rebuild()


func set_accent_color(c: Color) -> void:
	_accent = c
	if is_inside_tree():
		_apply_panel_style()
		_rebuild()


func _apply_panel_style() -> void:
	var theme: UITheme = UIThemeManager.get_current()
	var sb := StyleBoxFlat.new()
	sb.bg_color = theme.bg_card
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.border_width_left = 3
	sb.border_color = _accent
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	# Sombra muy sutil para dar profundidad
	sb.shadow_color = Color(0, 0, 0, 0.18)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	add_theme_stylebox_override("panel", sb)


func _rebuild() -> void:
	var theme: UITheme = UIThemeManager.get_current()
	for c in get_children():
		c.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# === Fila superior: badge icon + title ===
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vbox.add_child(top)

	if _icon != "":
		top.add_child(_build_icon_badge())

	var title_lbl := Label.new()
	title_lbl.text = _title.to_upper()
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", theme.text_secondary)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(title_lbl)

	# === Valor grande ===
	var value_lbl := Label.new()
	value_lbl.text = _value
	value_lbl.add_theme_font_size_override("font_size", 32)
	value_lbl.add_theme_color_override("font_color", theme.text_primary)
	value_lbl.add_theme_constant_override("outline_size", 0)
	# Negrita visual: aumentamos peso simulado con outline del mismo color
	value_lbl.add_theme_color_override("font_outline_color", theme.text_primary)
	value_lbl.add_theme_constant_override("outline_size", 1)
	vbox.add_child(value_lbl)

	# === Línea inferior: subtitle (izq, expand) + trend (der) ===
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom)

	if _subtitle != "":
		var sub_lbl := Label.new()
		sub_lbl.text = _subtitle
		sub_lbl.add_theme_font_size_override("font_size", 12)
		sub_lbl.add_theme_color_override("font_color", theme.text_secondary)
		sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub_lbl.clip_text = true
		bottom.add_child(sub_lbl)
	else:
		# Spacer si no hay subtitle, para empujar trend a la derecha
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(spacer)

	if _trend != "":
		bottom.add_child(_build_trend_pill())


# Badge circular pequeño con el icon, fondo accent translúcido.
func _build_icon_badge() -> Control:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(28, 28)
	var sb := StyleBoxFlat.new()
	var bg: Color = _accent
	bg.a = 0.22
	sb.bg_color = bg
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	badge.add_theme_stylebox_override("panel", sb)

	var icon_lbl := Label.new()
	icon_lbl.text = _icon
	icon_lbl.add_theme_font_size_override("font_size", 16)
	icon_lbl.add_theme_color_override("font_color", _accent)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(icon_lbl)
	return badge


# Pill con flecha direccional + delta (▲ +2, ▼ -1, ▬ 0).
func _build_trend_pill() -> Control:
	var theme: UITheme = UIThemeManager.get_current()
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var trend_color: Color
	var arrow: String
	match _trend_dir:
		"up":
			trend_color = theme.accent_success
			arrow = "▲"
		"down":
			trend_color = theme.accent_danger
			arrow = "▼"
		_:
			trend_color = theme.text_muted
			arrow = "▬"
	var bg: Color = trend_color
	bg.a = 0.18
	sb.bg_color = bg
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	pill.add_child(hbox)
	var arrow_lbl := Label.new()
	arrow_lbl.text = arrow
	arrow_lbl.add_theme_font_size_override("font_size", 11)
	arrow_lbl.add_theme_color_override("font_color", trend_color)
	hbox.add_child(arrow_lbl)
	var delta_lbl := Label.new()
	delta_lbl.text = _trend
	delta_lbl.add_theme_font_size_override("font_size", 12)
	delta_lbl.add_theme_color_override("font_color", trend_color)
	hbox.add_child(delta_lbl)
	return pill
