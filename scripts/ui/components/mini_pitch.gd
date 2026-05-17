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

# X de cada tipo de línea en coordenadas 0..1 del campo (0=portería propia,
# 1=portería rival). Las líneas NO se reparten uniformemente — en formaciones
# reales la defensa va cerca de la portería propia y el ataque cerca de la
# rival, mientras que mediocampo y líneas intermedias quedan en posiciones
# específicas. Estos valores reproducen visualmente esquemas tipo FM/FIFA.
const LINE_X := {
	"gk": 0.05,
	"def": 0.22,
	"dm": 0.38,
	"mid": 0.52,
	"am": 0.66,
	"fw": 0.80,
}

# Array de Dictionary: [{slot, number, short_name, is_gk}, ...]
var _players: Array = []
var _show_names: bool = true
# Formación como string ("4-3-3", "3-4-3", "4-2-3-1", "3-5-2", ...). Si está
# presente y es válida, se usa como fuente de verdad para las líneas en lugar
# de clasificar por slot. Esto evita que la representación se desincronice
# cuando el user cambia de formación y el slot_assignments queda con strings
# de la formación anterior.
var _formation: String = ""
# Orientación: false=horizontal (campo a lo ancho), true=vertical (campo a lo
# alto, portería propia abajo, ataque arriba). En vertical el control rota
# las coordenadas internas: lo que era profundidad X pasa a Y inverso.
var _vertical: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(320, 220)


# players: Array de Dictionary {slot, number, short_name, is_gk}
# formation: string opcional "3-4-3", "4-3-3", "4-2-3-1", etc.
func setup(players: Array, show_names: bool = true, formation: String = "") -> void:
	_players = players
	_show_names = show_names
	_formation = formation
	queue_redraw()


# Cambia la orientación. true = campo vertical (portería propia abajo).
func set_vertical(vertical: bool) -> void:
	_vertical = vertical
	queue_redraw()


func _draw() -> void:
	var theme: UITheme = UIThemeManager.get_current()
	# Aspect ratio del campo (105m x 68m ≈ 1.54:1). En vertical se invierte
	# (ancho/alto < 1), en horizontal es > 1.
	const PITCH_RATIO_H: float = 1.54
	var target_ratio: float = (1.0 / PITCH_RATIO_H) if _vertical else PITCH_RATIO_H
	var rect: Rect2
	var available_ratio: float = size.x / max(1.0, size.y)
	if available_ratio > target_ratio:
		var w: float = size.y * target_ratio
		var x: float = (size.x - w) * 0.5
		rect = Rect2(x, 0, w, size.y)
	else:
		var h: float = size.x / target_ratio
		var y: float = (size.y - h) * 0.5
		rect = Rect2(0, y, size.x, h)

	# Fondo + bordes
	draw_rect(rect, theme.pitch_bg, true)
	var line_w: float = 2.0
	draw_rect(rect, theme.pitch_lines, false, line_w)

	# Línea medio campo: profundidad interna 0.5 va de banda a banda
	draw_line(_to_screen(rect, 0.5, 0.0), _to_screen(rect, 0.5, 1.0), theme.pitch_lines, line_w)
	# Círculo central
	var center: Vector2 = _to_screen(rect, 0.5, 0.5)
	var r_center: float = min(rect.size.x, rect.size.y) * 0.12
	draw_arc(center, r_center, 0.0, TAU, 32, theme.pitch_lines, line_w)
	draw_circle(center, 3.0, theme.pitch_lines)
	# Áreas pequeñas (porterías): de profundidad 0..0.10 y 0.90..1.0, banda 0.25..0.75
	_draw_area_rect(rect, 0.0, 0.10, 0.25, 0.75, theme.pitch_lines, line_w)
	_draw_area_rect(rect, 0.90, 1.0, 0.25, 0.75, theme.pitch_lines, line_w)
	# Puntos de penalti
	draw_circle(_to_screen(rect, 0.07, 0.5), 2.0, theme.pitch_lines)
	draw_circle(_to_screen(rect, 0.93, 0.5), 2.0, theme.pitch_lines)

	# === Calcular posiciones por LÍNEAS ===
	var positions: Array = _compute_line_positions(_players)
	if positions.is_empty():
		return

	# === Pintar jugadores ===
	# Radius en función del lado MENOR del rect (en vertical el lado menor es x)
	var radius: float = clampf(min(rect.size.x, rect.size.y) * 0.06, 9.0, 16.0)
	var font := ThemeDB.fallback_font
	var font_size_num: int = max(9, int(radius * 0.9))
	var font_size_name: int = max(8, int(radius * 0.75))
	for pos_data: Dictionary in positions:
		var i: int = pos_data["idx"]
		var p: Dictionary = _players[i]
		var center_p: Vector2 = _to_screen(rect, float(pos_data["x"]), float(pos_data["y"]))
		var x: float = center_p.x
		var y: float = center_p.y
		var line_type: String = String(pos_data.get("line_type", ""))
		var color: Color = _color_for_line(line_type, p, theme)
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


# Si tenemos una formación válida ("3-4-3", "4-3-3", etc.) y los jugadores
# vienen en orden (GK primero, defensas, medios, ataque), usar la formación
# como fuente de verdad para las líneas. Mucho más robusto que clasificar
# por slot (los slot_assignments pueden quedar obsoletos si el user cambia de
# formación sin re-asignar slots).
func _compute_line_positions(players: Array) -> Array:
	if players.is_empty():
		return []
	# Intentar usar la formación si está disponible
	if _formation != "":
		var line_counts: Array = _parse_formation(_formation, players.size())
		if not line_counts.is_empty():
			return _positions_from_formation(players, line_counts)
	# Fallback: clasificar por slots (puede dar resultados raros si los slots
	# no coinciden con la formación seleccionada)
	return _positions_from_slots(players)


# Parsea "3-4-3" -> [1, 3, 4, 3] (incluyendo GK como primera línea).
# Devuelve [] si el string es inválido o no suma N jugadores.
func _parse_formation(formation: String, n_players: int) -> Array:
	var parts: PackedStringArray = formation.split("-")
	if parts.size() < 2:
		return []
	var lines: Array = [1]  # GK siempre primera línea
	var total: int = 1
	for p in parts:
		var n: int = int(p.strip_edges())
		if n <= 0:
			return []
		lines.append(n)
		total += n
	# Tolerar formaciones que no sumen exactamente n_players: si suma 11 OK,
	# si los players son menos asumimos que faltan algunos pero usamos en orden
	if total < 2:
		return []
	return lines


# Distribuye los jugadores en orden secuencial según los counts por línea.
# - line_counts[0] = N jugadores en GK (siempre 1)
# - line_counts[1] = N jugadores en defensa
# - line_counts[2] = N jugadores en mediocampo
# ... etc
# X de cada línea: derivada del TIPO de línea (def cerca de portería propia,
# fw cerca de la rival, intermedias en posiciones específicas) — NO uniforme.
# Y dentro de cada línea: ordenar por SLOT_Y_PREF si los slots son útiles,
# luego distribuir uniformemente 18%..82%.
func _positions_from_formation(players: Array, line_counts: Array) -> Array:
	var n_lines: int = line_counts.size()
	if n_lines <= 0:
		return []
	# Inferir el tipo de cada línea (gk, def, dm, mid, am, fw)
	var line_types: Array = _infer_line_types(n_lines)
	# Asignar players secuencialmente a líneas
	var result: Array = []
	var idx: int = 0
	for line_idx in n_lines:
		var n_in_line: int = int(line_counts[line_idx])
		var line_type_str: String = String(line_types[line_idx])
		var line_x: float = float(LINE_X.get(line_type_str, 0.5))
		# Recoger los players de esta línea con su y_pref por slot
		var line_players: Array = []
		for _i in n_in_line:
			if idx >= players.size():
				break
			var slot: String = String(players[idx].get("slot", "CM"))
			var y_pref: float = float(SLOT_Y_PREF.get(slot, 0.5))
			line_players.append({"idx": idx, "y_pref": y_pref})
			idx += 1
		# Ordenar por y_pref (LB arriba, RB abajo, centrales al medio)
		line_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["y_pref"]) < float(b["y_pref"]))
		# Distribuir Y uniformemente — más juntos si son pocos, más anchos si son muchos
		var n: int = line_players.size()
		var y_top: float = 0.18
		var y_bot: float = 0.82
		# Para 2 jugadores (ej. STs en 4-4-2): menos spread (~30% a ~70%) para que
		# no toquen las bandas
		if n == 2:
			y_top = 0.30
			y_bot = 0.70
		for j in n:
			var y: float
			if n == 1:
				y = 0.5
			else:
				y = y_top + float(j) / float(n - 1) * (y_bot - y_top)
			# Cuña: si hay muchos jugadores en la línea, los laterales se desplazan
			# hacia atrás y el central se adelanta (rompe la "línea horizontal recta")
			var x_off: float = _depth_offset(n, j)
			result.append({
				"idx": int(line_players[j]["idx"]),
				"x": clampf(line_x + x_off, 0.05, 0.92),
				"y": y,
				"line_type": line_type_str,
			})
	return result


# Mapea coordenadas internas del campo (profundidad X 0..1, banda Y 0..1) a
# coordenadas de pantalla dentro del rect dado. En horizontal: X=profundidad,
# Y=banda. En vertical: el campo gira 90° antihorario (portería propia abajo).
func _to_screen(rect: Rect2, internal_x: float, internal_y: float) -> Vector2:
	if _vertical:
		return Vector2(
			rect.position.x + internal_y * rect.size.x,
			rect.position.y + (1.0 - internal_x) * rect.size.y,
		)
	return Vector2(
		rect.position.x + internal_x * rect.size.x,
		rect.position.y + internal_y * rect.size.y,
	)


# Dibuja un rectángulo definido por coordenadas internas (no estiradas).
#   x0, x1: profundidad (0..1, x0 < x1)
#   y0, y1: banda (0..1, y0 < y1)
func _draw_area_rect(rect: Rect2, x0: float, x1: float, y0: float, y1: float, color: Color, line_w: float) -> void:
	var a: Vector2 = _to_screen(rect, x0, y0)
	var b: Vector2 = _to_screen(rect, x1, y1)
	var origin := Vector2(min(a.x, b.x), min(a.y, b.y))
	var dim := Vector2(abs(b.x - a.x), abs(b.y - a.y))
	draw_rect(Rect2(origin, dim), color, false, line_w)


# Color del círculo según el tipo de línea (defensa/medio/ataque/portero).
# Permite distinguir visualmente las líneas sin necesidad de leyenda.
func _color_for_line(line_type: String, p: Dictionary, theme: UITheme) -> Color:
	if bool(p.get("is_gk", false)) or line_type == "gk":
		return theme.player_gk  # amarillo
	match line_type:
		"def":
			return theme.accent_info        # azul
		"dm":
			return Color(0.30, 0.66, 0.90)  # azul más claro
		"mid":
			return theme.accent_success     # verde
		"am":
			return Color(0.95, 0.55, 0.20)  # naranja
		"fw":
			return theme.accent_primary     # rojo
	return theme.player_team_a  # fallback rojo


# Offset en X según la posición del jugador en su línea. Para líneas con muchos
# jugadores (5+), aplica un patrón en CUÑA — central adelantado, laterales
# atrás — para que no parezca que 5 jugadores están a la misma altura.
# Defensas y mediocampos de 3-4 jugadores se mantienen relativamente planos
# (como en formaciones reales).
#   n: número total de jugadores en la línea
#   j: índice del jugador (0 = más arriba en pantalla / banda izq, n-1 = banda der)
# Devuelve offset relativo a la X de la línea (positivo = adelantado, negativo = atrás)
func _depth_offset(n: int, j: int) -> float:
	if n < 3:
		return 0.0
	if n == 3:
		# 3 jugadores: lateral izq atrás, central adelantado, lateral der atrás.
		# Útil para defensas de 3 (sweeper detrás) y ataques de 3 (ST adelantado).
		if j == 0 or j == n - 1:
			return -0.06
		return 0.06
	if n == 4:
		# Defensa o medio de 4: laterales ~10% atrás, centrales planos
		if j == 0 or j == n - 1:
			return -0.10
		return 0.0
	# 5+ jugadores: cuña ANCHA — central claramente adelantado, bandas casi
	# en la línea anterior. Spread total ~60% del salto entre líneas.
	var center: float = float(n - 1) * 0.5
	var dist: float = abs(float(j) - center) / center  # 0 centro .. 1 banda
	return 0.22 - pow(dist, 1.5) * 0.60


# Infiere el TIPO de cada línea según cuántas líneas hay (incluyendo GK).
# Reglas:
#   - Primera línea siempre "gk", segunda siempre "def", última siempre "fw"
#   - Las intermedias se etiquetan según la cantidad:
#       1 intermedia → ["mid"]                    (ej. 4-3-3, 4-4-2, 3-4-3)
#       2 intermedias → ["dm", "am"]              (ej. 4-2-3-1, 4-3-1-2)
#       3 intermedias → ["dm", "mid", "am"]       (ej. 4-1-2-1-2 diamante)
#       4+ intermedias → ["dm", "mid"*N, "am"]
func _infer_line_types(n_lines: int) -> Array:
	if n_lines <= 0:
		return []
	if n_lines == 1:
		return ["gk"]
	if n_lines == 2:
		return ["gk", "def"]
	# n_lines >= 3 → GK + DEF + ...intermedias... + FW
	var types: Array = ["gk", "def"]
	var n_middle: int = n_lines - 3  # entre def y fw
	match n_middle:
		0:
			# Solo gk, def, fw (raro)
			pass
		1:
			types.append("mid")
		2:
			types.append("dm")
			types.append("am")
		3:
			types.append("dm")
			types.append("mid")
			types.append("am")
		_:
			# Más de 3 intermedias: dm + mids + am
			types.append("dm")
			for _i in range(n_middle - 2):
				types.append("mid")
			types.append("am")
	types.append("fw")
	return types


# Clasifica los jugadores en líneas por SLOT (fallback si no hay formación).
func _positions_from_slots(players: Array) -> Array:
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

	# X de cada línea: usar LINE_X (def cerca de portería propia, fw cerca de la
	# rival) en lugar de reparto uniforme — esto produce esquemas realistas.
	# Para cada línea, ordenar por y_pref y distribuir Y entre 18% y 82%.
	# Jugadores centrales (y_pref ~0.5) van al medio, laterales (LB/RB) a las bandas.
	var result: Array = []
	for line_key: String in active_lines:
		var line_players: Array = by_line[line_key]
		line_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["y_pref"]) < float(b["y_pref"]))
		var n: int = line_players.size()
		var y_top: float = 0.18
		var y_bot: float = 0.82
		if n == 2:
			y_top = 0.30
			y_bot = 0.70
		for i in n:
			var y: float
			if n == 1:
				y = 0.5
			else:
				y = y_top + float(i) / float(n - 1) * (y_bot - y_top)
			var x_off: float = _depth_offset(n, i)
			result.append({
				"idx": int(line_players[i]["idx"]),
				"x": clampf(float(LINE_X.get(line_key, 0.5)) + x_off, 0.05, 0.92),
				"y": y,
				"line_type": line_key,
			})
	return result
