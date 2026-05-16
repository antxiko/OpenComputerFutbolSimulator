class_name ShortlistRow extends PanelContainer

# Fila compacta para Scout Shortlist en el Dashboard.
# Muestra: tier badge + nombre + pos/edad + club + valor + botón quitar.
# Emite signal `remove_requested(player_id)`.

signal remove_requested(player_id: String)

var _player_id: String = ""


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 36)


# data: {id, name, pos, age, club, value_eur, tier}
func setup(data: Dictionary) -> void:
	_player_id = String(data.get("id", ""))
	var theme: UITheme = UIThemeManager.get_current()
	for c in get_children():
		c.queue_free()

	var sb := StyleBoxFlat.new()
	sb.bg_color = theme.bg_secondary
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	add_child(hbox)

	# Tier badge
	var tier: String = String(data.get("tier", "C"))
	var tier_color: Color = theme.color_for_tier(tier)
	var tier_pc := PanelContainer.new()
	var tier_sb := StyleBoxFlat.new()
	tier_sb.bg_color = tier_color
	tier_sb.corner_radius_top_left = 3
	tier_sb.corner_radius_top_right = 3
	tier_sb.corner_radius_bottom_left = 3
	tier_sb.corner_radius_bottom_right = 3
	tier_sb.content_margin_left = 6
	tier_sb.content_margin_right = 6
	tier_sb.content_margin_top = 2
	tier_sb.content_margin_bottom = 2
	tier_pc.add_theme_stylebox_override("panel", tier_sb)
	var tier_lbl := Label.new()
	tier_lbl.text = tier
	tier_lbl.add_theme_font_size_override("font_size", 11)
	tier_lbl.add_theme_color_override("font_color", Color.BLACK)
	tier_pc.add_child(tier_lbl)
	hbox.add_child(tier_pc)

	# Nombre
	var name_lbl := Label.new()
	name_lbl.text = String(data.get("name", "—"))
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", theme.text_primary)
	name_lbl.custom_minimum_size = Vector2(140, 0)
	hbox.add_child(name_lbl)

	# Pos / edad
	var meta_lbl := Label.new()
	meta_lbl.text = "%s · %d a" % [String(data.get("pos", "?")), int(data.get("age", 0))]
	meta_lbl.add_theme_font_size_override("font_size", 12)
	meta_lbl.add_theme_color_override("font_color", theme.text_secondary)
	meta_lbl.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(meta_lbl)

	# Club
	var club_lbl := Label.new()
	club_lbl.text = String(data.get("club", ""))
	club_lbl.add_theme_font_size_override("font_size", 12)
	club_lbl.add_theme_color_override("font_color", theme.text_secondary)
	club_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(club_lbl)

	# Valor
	var val_lbl := Label.new()
	val_lbl.text = _format_eur(int(data.get("value_eur", 0)))
	val_lbl.add_theme_font_size_override("font_size", 13)
	val_lbl.add_theme_color_override("font_color", theme.accent_success)
	val_lbl.custom_minimum_size = Vector2(70, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(val_lbl)

	# Botón quitar
	var btn_remove := Button.new()
	btn_remove.text = "✗"
	btn_remove.flat = true
	btn_remove.custom_minimum_size = Vector2(24, 24)
	btn_remove.add_theme_color_override("font_color", theme.text_muted)
	btn_remove.pressed.connect(func() -> void:
		remove_requested.emit(_player_id))
	hbox.add_child(btn_remove)


static func _format_eur(eur: int) -> String:
	if eur >= 1_000_000:
		return "%.1fM€" % (eur / 1_000_000.0)
	if eur >= 1_000:
		return "%dK€" % int(eur / 1_000.0)
	return "%d€" % eur
