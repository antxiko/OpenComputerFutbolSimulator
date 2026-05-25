class_name SidebarNav extends PanelContainer

# Sidebar de navegación vertical estilo dashboard moderno.
# Estructura:
#   - Header con logo + nombre del club
#   - (Opcional) SearchBar global (placeholder, implementado en Fase E)
#   - Lista de items de navegación (icono + label)
#   - Footer con avatar + nombre user mánager
#
# Emite signal `view_selected(view_name: String)` cuando el user pulsa un item.

signal view_selected(view_name: String)
# Emitido cuando el user envía una búsqueda desde el campo del sidebar.
# El game_hub se encarga de buscar y mostrar resultados.
signal search_requested(query: String)

const SIDEBAR_WIDTH: int = 230

# Items definidos: cada uno es { icon, label, view, badge_count }
# El badge_count se actualiza desde fuera con set_badge(view, n)
var _items: Array = []
var _active_view: String = ""
var _items_box: VBoxContainer
var _badges: Dictionary = {}  # view -> Label (referencia para actualizar)


func _ready() -> void:
	custom_minimum_size = Vector2(SIDEBAR_WIDTH, 0)
	size_flags_horizontal = 0  # NO expand
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_theme()


# Inicializa la sidebar con club + items + user info. Llamar tras construirla.
#   items: Array de Dictionary [{icon, label, view}, ...]
func setup(club_name: String, club_short: String, items: Array, user_name: String) -> void:
	_items = items
	var theme: UITheme = UIThemeManager.get_current()

	# Limpiar
	for c in get_children():
		c.queue_free()

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	# Header: logo + nombre club
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var pad_header := MarginContainer.new()
	pad_header.add_theme_constant_override("margin_left", 14)
	pad_header.add_theme_constant_override("margin_right", 10)
	pad_header.add_theme_constant_override("margin_top", 14)
	pad_header.add_theme_constant_override("margin_bottom", 12)
	pad_header.add_child(header)
	root.add_child(pad_header)

	var logo_circle := ColorRect.new()
	logo_circle.color = theme.accent_primary
	logo_circle.custom_minimum_size = Vector2(28, 28)
	header.add_child(logo_circle)

	var club_label := Label.new()
	club_label.text = club_short if club_short != "" else club_name
	club_label.add_theme_font_size_override("font_size", 15)
	club_label.add_theme_color_override("font_color", theme.text_primary)
	club_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(club_label)

	# Separador sutil
	var sep := ColorRect.new()
	sep.color = theme.border_subtle
	sep.custom_minimum_size = Vector2(0, 1)
	root.add_child(sep)

	# Campo de búsqueda global (jugadores + equipos)
	var search_pad := MarginContainer.new()
	search_pad.add_theme_constant_override("margin_left", 10)
	search_pad.add_theme_constant_override("margin_right", 10)
	search_pad.add_theme_constant_override("margin_top", 10)
	search_pad.add_theme_constant_override("margin_bottom", 4)
	root.add_child(search_pad)
	var search_edit := LineEdit.new()
	search_edit.placeholder_text = "Buscar jugador o equipo..."
	search_edit.add_theme_font_size_override("font_size", 13)
	search_edit.text_submitted.connect(func(text: String) -> void:
		var q: String = text.strip_edges()
		if q.length() >= 2:
			search_requested.emit(q)
			search_edit.text = "")
	var sb_search := StyleBoxFlat.new()
	sb_search.bg_color = theme.bg_secondary
	sb_search.corner_radius_top_left = 4
	sb_search.corner_radius_top_right = 4
	sb_search.corner_radius_bottom_left = 4
	sb_search.corner_radius_bottom_right = 4
	sb_search.content_margin_left = 8
	sb_search.content_margin_right = 8
	sb_search.content_margin_top = 4
	sb_search.content_margin_bottom = 4
	search_edit.add_theme_stylebox_override("normal", sb_search)
	search_edit.add_theme_stylebox_override("focus", sb_search)
	search_pad.add_child(search_edit)

	# Separador sutil tras búsqueda
	var sep_search := ColorRect.new()
	sep_search.color = theme.border_subtle
	sep_search.custom_minimum_size = Vector2(0, 1)
	root.add_child(sep_search)

	# Items box
	var items_pad := MarginContainer.new()
	items_pad.add_theme_constant_override("margin_left", 8)
	items_pad.add_theme_constant_override("margin_right", 8)
	items_pad.add_theme_constant_override("margin_top", 10)
	items_pad.add_theme_constant_override("margin_bottom", 10)
	items_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(items_pad)
	_items_box = VBoxContainer.new()
	_items_box.add_theme_constant_override("separation", 2)
	items_pad.add_child(_items_box)
	_badges.clear()
	for it: Dictionary in items:
		_items_box.add_child(_build_item_row(it))

	# Footer del sidebar: avatar + user name
	var sep2 := ColorRect.new()
	sep2.color = theme.border_subtle
	sep2.custom_minimum_size = Vector2(0, 1)
	root.add_child(sep2)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	var pad_footer := MarginContainer.new()
	pad_footer.add_theme_constant_override("margin_left", 14)
	pad_footer.add_theme_constant_override("margin_right", 10)
	pad_footer.add_theme_constant_override("margin_top", 12)
	pad_footer.add_theme_constant_override("margin_bottom", 14)
	pad_footer.add_child(footer)
	root.add_child(pad_footer)

	var avatar := ColorRect.new()
	avatar.color = theme.accent_info
	avatar.custom_minimum_size = Vector2(28, 28)
	footer.add_child(avatar)

	var user_box := VBoxContainer.new()
	user_box.add_theme_constant_override("separation", 0)
	user_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(user_box)
	var user_label := Label.new()
	user_label.text = user_name if user_name != "" else "Mánager"
	user_label.add_theme_font_size_override("font_size", 14)
	user_label.add_theme_color_override("font_color", theme.text_primary)
	user_box.add_child(user_label)
	var club_sub := Label.new()
	club_sub.text = club_name if club_name != "" else "Sin club"
	club_sub.add_theme_font_size_override("font_size", 14)
	club_sub.add_theme_color_override("font_color", theme.text_secondary)
	user_box.add_child(club_sub)


# Marca un item como activo (resalta visualmente). Llama tras navegar.
func set_active(view_name: String) -> void:
	_active_view = view_name
	if _items_box == null:
		return
	# Rebuild items para refrescar estilos
	for c in _items_box.get_children():
		c.queue_free()
	_badges.clear()
	for it: Dictionary in _items:
		_items_box.add_child(_build_item_row(it))


# Actualiza el badge de un item (ej. inbox count). Si n <= 0, oculta el badge.
func set_badge(view_name: String, n: int) -> void:
	for it: Dictionary in _items:
		if String(it.get("view", "")) == view_name:
			it["badge_count"] = n
	if _badges.has(view_name):
		var lbl: Label = _badges[view_name]
		if n > 0:
			lbl.text = "(%d)" % n
			lbl.visible = true
		else:
			lbl.visible = false


func _build_item_row(it: Dictionary) -> Control:
	var theme: UITheme = UIThemeManager.get_current()
	var view_name: String = String(it.get("view", ""))
	var is_active: bool = (_active_view == view_name)

	var btn := Button.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 36)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var icon: String = String(it.get("icon", ""))
	var label: String = String(it.get("label", ""))
	var badge_count: int = int(it.get("badge_count", 0))
	var bc_str: String = "  (%d)" % badge_count if badge_count > 0 else ""
	btn.text = "  %s  %s%s" % [icon, label, bc_str]

	if is_active:
		btn.add_theme_color_override("font_color", theme.sidebar_active_text)
		# Background activo via stylebox
		var sb_active := StyleBoxFlat.new()
		sb_active.bg_color = theme.sidebar_active_bg
		sb_active.corner_radius_top_left = 6
		sb_active.corner_radius_top_right = 6
		sb_active.corner_radius_bottom_left = 6
		sb_active.corner_radius_bottom_right = 6
		btn.add_theme_stylebox_override("normal", sb_active)
		btn.add_theme_stylebox_override("hover", sb_active)
		btn.add_theme_stylebox_override("pressed", sb_active)
	else:
		btn.add_theme_color_override("font_color", theme.sidebar_text)
		var sb_hover := StyleBoxFlat.new()
		sb_hover.bg_color = theme.sidebar_hover_bg
		sb_hover.corner_radius_top_left = 6
		sb_hover.corner_radius_top_right = 6
		sb_hover.corner_radius_bottom_left = 6
		sb_hover.corner_radius_bottom_right = 6
		btn.add_theme_stylebox_override("hover", sb_hover)

	btn.pressed.connect(func() -> void:
		view_selected.emit(view_name))
	return btn


func _apply_theme() -> void:
	var theme: UITheme = UIThemeManager.get_current()
	var sb := StyleBoxFlat.new()
	sb.bg_color = theme.sidebar_bg
	sb.border_width_right = 1
	sb.border_color = theme.border_subtle
	add_theme_stylebox_override("panel", sb)
