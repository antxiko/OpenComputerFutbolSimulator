class_name MiniPitch extends Control

# Campo cenital con jugadores numerados/nombrados. Usado en Dashboard
# para mostrar el Starting XI del user.
#
# Coordenadas internas en (0..1, 0..1) — reutiliza SLOT_POSITIONS
# heredado del visor 2D.

const SLOT_POSITIONS := {
	"GK":  Vector2(0.05, 0.50),
	"CB":  Vector2(0.20, 0.40),
	"LB":  Vector2(0.20, 0.18),
	"RB":  Vector2(0.20, 0.82),
	"LWB": Vector2(0.30, 0.12),
	"RWB": Vector2(0.30, 0.88),
	"CDM": Vector2(0.35, 0.50),
	"CM":  Vector2(0.45, 0.40),
	"CAM": Vector2(0.55, 0.50),
	"LM":  Vector2(0.45, 0.20),
	"RM":  Vector2(0.45, 0.80),
	"LW":  Vector2(0.65, 0.18),
	"RW":  Vector2(0.65, 0.82),
	"CF":  Vector2(0.75, 0.50),
	"ST":  Vector2(0.80, 0.50),
}

# Array de Dictionary: [{slot, number, short_name, is_gk}, ...]
var _players: Array = []
var _show_names: bool = true


func _ready() -> void:
	custom_minimum_size = Vector2(320, 220)


# players: Array de Dictionary {slot, number, short_name, is_gk}
func setup(players: Array, show_names: bool = true) -> void:
	_players = players
	_show_names = show_names
	queue_redraw()


func _draw() -> void:
	var theme: UITheme = UIThemeManager.get_current()
	var rect := Rect2(Vector2.ZERO, size)
	# Agrupar jugadores por slot para spread vertical si hay duplicados.
	# Ej.: 4-3-3 tiene 2 CB y 2 CM compartiendo SLOT_POSITIONS.
	var groups: Dictionary = {}  # slot -> Array[idx en _players]
	for i in _players.size():
		var slot: String = String(_players[i].get("slot", "CM"))
		if not groups.has(slot):
			groups[slot] = []
		groups[slot].append(i)

	# Fondo del campo
	draw_rect(rect, theme.pitch_bg, true)

	# Bordes del campo
	var line_w: float = 2.0
	draw_rect(rect, theme.pitch_lines, false, line_w)

	# Línea de medio campo (vertical)
	var mid_x: float = size.x * 0.5
	draw_line(Vector2(mid_x, 0), Vector2(mid_x, size.y), theme.pitch_lines, line_w)

	# Círculo central
	var center := Vector2(mid_x, size.y * 0.5)
	var r_center: float = min(size.x, size.y) * 0.12
	draw_arc(center, r_center, 0.0, TAU, 32, theme.pitch_lines, line_w)
	draw_circle(center, 3.0, theme.pitch_lines)

	# Áreas pequeñas (porterías)
	var goal_w: float = size.x * 0.10
	var goal_h: float = size.y * 0.50
	var goal_y: float = (size.y - goal_h) * 0.5
	draw_rect(Rect2(0, goal_y, goal_w, goal_h), theme.pitch_lines, false, line_w)
	draw_rect(Rect2(size.x - goal_w, goal_y, goal_w, goal_h), theme.pitch_lines, false, line_w)

	# Punto de penalti
	draw_circle(Vector2(goal_w * 0.7, size.y * 0.5), 2.0, theme.pitch_lines)
	draw_circle(Vector2(size.x - goal_w * 0.7, size.y * 0.5), 2.0, theme.pitch_lines)

	# Jugadores
	var radius: float = 12.0
	var font := ThemeDB.fallback_font
	var font_size_num: int = 11
	var font_size_name: int = 10
	# Spread vertical aplicado a cada slot con > 1 jugador (4-3-3 tiene 2 CB y 2 CM
	# que comparten posición base — sin spread se pisarían y solo se vería uno).
	# Diccionario player_idx -> Vector2 offset relativo (en coords 0..1).
	var offsets_by_idx: Dictionary = {}
	for slot_key in groups.keys():
		var idx_list: Array = groups[slot_key]
		var n: int = idx_list.size()
		if n == 1:
			offsets_by_idx[idx_list[0]] = Vector2.ZERO
		else:
			# Reparto vertical: spread total 0.30 (15% arriba + 15% abajo)
			var spread: float = 0.30
			for j in n:
				var t: float = float(j) / float(n - 1)  # 0..1
				var dy: float = (t - 0.5) * spread
				offsets_by_idx[idx_list[j]] = Vector2(0, dy)
	for i in _players.size():
		var p: Dictionary = _players[i]
		var slot: String = String(p.get("slot", "CM"))
		var slot_pos: Vector2 = SLOT_POSITIONS.get(slot, Vector2(0.45, 0.5))
		var off: Vector2 = offsets_by_idx.get(i, Vector2.ZERO)
		var x: float = (slot_pos.x + off.x) * size.x
		var y: float = clampf(slot_pos.y + off.y, 0.06, 0.94) * size.y
		var center_p := Vector2(x, y)
		var is_gk: bool = bool(p.get("is_gk", false))
		var color: Color = theme.player_gk if is_gk else theme.player_team_a
		draw_circle(center_p, radius, color)
		draw_arc(center_p, radius, 0.0, TAU, 24, theme.text_on_accent, 1.0)

		# Número
		var num_str: String = String(p.get("number", ""))
		if num_str != "":
			var num_size: Vector2 = font.get_string_size(num_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size_num)
			draw_string(font, center_p - Vector2(num_size.x * 0.5, -num_size.y * 0.30), num_str,
					HORIZONTAL_ALIGNMENT_CENTER, -1, font_size_num, theme.text_on_accent)

		# Nombre (debajo del círculo)
		if _show_names:
			var name_str: String = String(p.get("short_name", ""))
			if name_str != "":
				var name_size: Vector2 = font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size_name)
				var name_pos := Vector2(x - name_size.x * 0.5, y + radius + 12)
				# Fondo translúcido para legibilidad
				draw_rect(Rect2(name_pos + Vector2(-3, -10), Vector2(name_size.x + 6, 14)),
						theme.player_label_bg, true)
				draw_string(font, name_pos, name_str, HORIZONTAL_ALIGNMENT_LEFT, -1,
						font_size_name, theme.text_primary)
