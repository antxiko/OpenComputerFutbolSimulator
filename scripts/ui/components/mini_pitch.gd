class_name MiniPitch extends Control

# Campo cenital con jugadores distribuidos por LÍNEAS (def/mid/atk) basándose
# en los slots asignados a cada jugador. NO usa posiciones absolutas — calcula
# dinámicamente las líneas activas y reparte uniformemente para que cualquier
# formación (4-3-3, 4-4-2, 4-2-3-1, 3-5-2, 5-3-2, etc.) se vea ordenada.
#
# Mantiene aspect ratio fijo del campo (105m x 68m ≈ 1.54:1) — si el control
# es más ancho/alto, centra y deja márgenes en lugar de estirar.

# Slot → línea funcional. Usado para clasificar a cada jugador en una columna
# vertical del campo (de la portería propia hacia la rival).
const SLOT_TO_LINE := {
	"GK": "gk",
	"CB": "def", "LB": "def", "RB": "def", "LWB": "def", "RWB": "def",
	"CDM": "dm",
	"CM": "mid", "LM": "mid", "RM": "mid",
	"CAM": "am",
	"LW": "fw", "RW": "fw", "CF": "fw", "ST": "fw",
}

# Orden lateral preferido dentro de cada línea (0 = más arriba en pantalla / banda izq,
# 1 = más abajo / banda der). Para slots centrales (CB, CM, ST) usamos 0.5
# y desempata por orden de aparición dentro de la línea.
const SLOT_Y_PREF := {
	"GK": 0.5,
	"LB": 0.05, "LWB": 0.02, "LM": 0.10, "LW": 0.05,
	"CB": 0.5, "CDM": 0.5, "CM": 0.5, "CAM": 0.5, "ST": 0.5, "CF": 0.5,
	"RB": 0.95, "RWB": 0.98, "RM": 0.90, "RW": 0.95,
}

# Orden de profundidad del campo (gk = portería propia, fw = portería rival).
const LINE_ORDER := ["gk", "def", "dm", "mid", "am", "fw"]

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
	# Mantener aspect ratio del campo (105m x 68m ≈ 1.54:1)
	const PITCH_RATIO: float = 1.54
	var rect: Rect2
	var available_ratio: float = size.x / max(1.0, size.y)
	if available_ratio > PITCH_RATIO:
		var w: float = size.y * PITCH_RATIO
		var x: float = (size.x - w) * 0.5
		rect = Rect2(x, 0, w, size.y)
	else:
		var h: float = size.x / PITCH_RATIO
		var y: float = (size.y - h) * 0.5
		rect = Rect2(0, y, size.x, h)

	# Fondo + bordes
	draw_rect(rect, theme.pitch_bg, true)
	var line_w: float = 2.0
	draw_rect(rect, theme.pitch_lines, false, line_w)

	var rx: float = rect.position.x
	var ry: float = rect.position.y
	var rw: float = rect.size.x
	var rh: float = rect.size.y

	# Línea medio campo
	var mid_x: float = rx + rw * 0.5
	draw_line(Vector2(mid_x, ry), Vector2(mid_x, ry + rh), theme.pitch_lines, line_w)
	# Círculo central
	var center := Vector2(mid_x, ry + rh * 0.5)
	var r_center: float = min(rw, rh) * 0.12
	draw_arc(center, r_center, 0.0, TAU, 32, theme.pitch_lines, line_w)
	draw_circle(center, 3.0, theme.pitch_lines)
	# Porterías (área pequeña)
	var goal_w: float = rw * 0.10
	var goal_h: float = rh * 0.50
	var goal_y: float = ry + (rh - goal_h) * 0.5
	draw_rect(Rect2(rx, goal_y, goal_w, goal_h), theme.pitch_lines, false, line_w)
	draw_rect(Rect2(rx + rw - goal_w, goal_y, goal_w, goal_h), theme.pitch_lines, false, line_w)
	# Puntos de penalti
	draw_circle(Vector2(rx + goal_w * 0.7, ry + rh * 0.5), 2.0, theme.pitch_lines)
	draw_circle(Vector2(rx + rw - goal_w * 0.7, ry + rh * 0.5), 2.0, theme.pitch_lines)

	# === Calcular posiciones por LÍNEAS ===
	var positions: Array = _compute_line_positions(_players)
	if positions.is_empty():
		return

	# === Pintar jugadores ===
	# Radius en función del tamaño del rect (campos pequeños = círculos más pequeños)
	var radius: float = clampf(min(rw, rh) * 0.06, 9.0, 16.0)
	var font := ThemeDB.fallback_font
	var font_size_num: int = max(9, int(radius * 0.9))
	var font_size_name: int = max(8, int(radius * 0.75))
	for pos_data: Dictionary in positions:
		var i: int = pos_data["idx"]
		var p: Dictionary = _players[i]
		var x: float = rx + pos_data["x"] * rw
		var y: float = ry + pos_data["y"] * rh
		var center_p := Vector2(x, y)
		var is_gk: bool = bool(p.get("is_gk", false))
		var color: Color = theme.player_gk if is_gk else theme.player_team_a
		# Sombra suave bajo el círculo
		draw_circle(center_p + Vector2(0, 2), radius + 1, Color(0, 0, 0, 0.35))
		draw_circle(center_p, radius, color)
		draw_arc(center_p, radius, 0.0, TAU, 24, theme.text_on_accent, 1.0)

		# Número en el centro
		var num_str: String = String(p.get("number", ""))
		if num_str != "":
			var num_size: Vector2 = font.get_string_size(num_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size_num)
			draw_string(font, center_p - Vector2(num_size.x * 0.5, -num_size.y * 0.30), num_str,
					HORIZONTAL_ALIGNMENT_CENTER, -1, font_size_num, theme.text_on_accent)

		# Nombre debajo
		if _show_names:
			var name_str: String = String(p.get("short_name", ""))
			if name_str != "":
				var name_size: Vector2 = font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size_name)
				var name_pos := Vector2(x - name_size.x * 0.5, y + radius + 11)
				draw_rect(Rect2(name_pos + Vector2(-3, -10), Vector2(name_size.x + 6, 14)),
						theme.player_label_bg, true)
				draw_string(font, name_pos, name_str, HORIZONTAL_ALIGNMENT_LEFT, -1,
						font_size_name, theme.text_primary)


# Clasifica los jugadores en líneas según su slot, calcula la X de cada línea
# repartiendo el campo uniformemente, y dentro de cada línea distribuye los
# jugadores en Y de banda a banda (ordenados por SLOT_Y_PREF).
# Devuelve: Array de Dictionary {idx, x, y} con coords 0..1.
func _compute_line_positions(players: Array) -> Array:
	if players.is_empty():
		return []

	var by_line: Dictionary = {}  # line_key -> Array de {idx, y_pref}
	for i in players.size():
		var slot: String = String(players[i].get("slot", "CM"))
		var line: String = String(SLOT_TO_LINE.get(slot, "mid"))
		var y_pref: float = float(SLOT_Y_PREF.get(slot, 0.5))
		if not by_line.has(line):
			by_line[line] = []
		by_line[line].append({"idx": i, "y_pref": y_pref})

	# Líneas activas en orden de profundidad
	var active_lines: Array = []
	for line_key: String in LINE_ORDER:
		if by_line.has(line_key) and (by_line[line_key] as Array).size() > 0:
			active_lines.append(line_key)
	if active_lines.is_empty():
		return []

	# X de cada línea: repartir uniformemente entre 7% y 86% del campo.
	# Si solo hay 1 línea (raro), centramos.
	var line_x: Dictionary = {}
	var n_lines: int = active_lines.size()
	for i in n_lines:
		var x: float
		if n_lines == 1:
			x = 0.5
		else:
			var t: float = float(i) / float(n_lines - 1)
			x = 0.07 + t * 0.79
		line_x[active_lines[i]] = x

	# Para cada línea, ordenar por y_pref y distribuir Y entre 18% y 82%.
	# Jugadores centrales (y_pref ~0.5) van al medio, laterales (LB/RB) a las bandas.
	var result: Array = []
	for line_key: String in active_lines:
		var line_players: Array = by_line[line_key]
		line_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["y_pref"]) < float(b["y_pref"]))
		var n: int = line_players.size()
		for i in n:
			var y: float
			if n == 1:
				y = 0.5
			else:
				y = 0.18 + float(i) / float(n - 1) * 0.64
			result.append({
				"idx": int(line_players[i]["idx"]),
				"x": line_x[line_key],
				"y": y,
			})
	return result
