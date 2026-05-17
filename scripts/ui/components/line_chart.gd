class_name LineChart extends Control

# Chart de líneas con _draw. Soporta:
#   - 1 sola serie via setup() (compatibilidad anterior)
#   - N series via setup_multi() — cada una con su color, estilo y nombre
#   - x_max: si > values.size(), los puntos se distribuyen proporcionalmente
#     en plot_w * (n_actual / x_max) en lugar de cubrir el ancho completo
#     (útil para ver progreso real: jornada 5 de 38 ocupa 5/38 del ancho)

# Series multi-line: [{name, values, color, dashed, fill}]
var _series: Array = []
var _labels_x: Array = []
var _title: String = ""
var _y_label: String = ""
var _x_max: int = 0   # 0 = usar values.size() (legacy); >0 = denominador fijo


func _ready() -> void:
	custom_minimum_size = Vector2(280, 200)


# Variante simple: 1 línea. Mantiene compatibilidad.
func setup(values: Array, labels_x: Array = [], title: String = "", y_label: String = "", x_max: int = 0) -> void:
	_series = [{
		"name": "",
		"values": values,
		"color": Color(0, 0, 0, 0),  # default: accent_primary
		"dashed": false,
		"fill": true,
	}]
	_labels_x = labels_x
	_title = title
	_y_label = y_label
	_x_max = x_max
	queue_redraw()


# Variante multi-serie. series: Array de Dictionary con keys:
#   name (String), values (Array[int|float]), color (Color), dashed (bool), fill (bool)
func setup_multi(series: Array, labels_x: Array = [], title: String = "", x_max: int = 0) -> void:
	_series = series
	_labels_x = labels_x
	_title = title
	_x_max = x_max
	queue_redraw()


func _draw() -> void:
	var theme: UITheme = UIThemeManager.get_current()
	var rect := Rect2(Vector2.ZERO, size)

	# Fondo glass del chart
	draw_style_box(UIThemeManager.glass_panel_style(), rect)
	draw_line(Vector2(8, 1), Vector2(size.x - 8, 1), Color(1, 1, 1, 0.14), 1.0)

	var font := ThemeDB.fallback_font
	var pad_top: float = 14.0
	var pad_left: float = 34.0
	var pad_right: float = 14.0
	var pad_bottom: float = 30.0

	if _title != "":
		draw_string(font, Vector2(pad_left, pad_top + 12), _title.to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, theme.text_secondary)
		pad_top += 22

	# Si todas las series están vacías, placeholder
	var max_n: int = 0
	for s in _series:
		max_n = max(max_n, (s as Dictionary).get("values", []).size())
	if max_n == 0:
		draw_string(font, Vector2(size.x * 0.5 - 30, size.y * 0.5), "Sin datos",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, theme.text_muted)
		return

	# Área de plot
	var plot_x: float = pad_left
	var plot_y: float = pad_top
	var plot_w: float = size.x - pad_left - pad_right
	var plot_h: float = size.y - pad_top - pad_bottom

	# Min/max global considerando TODAS las series
	var v_min: float = INF
	var v_max: float = -INF
	for s: Dictionary in _series:
		for v in s.get("values", []):
			var fv: float = float(v)
			v_min = min(v_min, fv)
			v_max = max(v_max, fv)
	if v_min == INF:
		v_min = 0.0
		v_max = 1.0
	if v_min == v_max:
		v_max = v_min + 1.0
	var v_range: float = v_max - v_min
	var draw_max: float = v_max + v_range * 0.10
	var draw_min: float = max(0.0, v_min - v_range * 0.05)
	var dy_range: float = draw_max - draw_min
	if dy_range <= 0.0:
		dy_range = 1.0

	# Denominador X: si _x_max > 0, distribuir puntos proporcionalmente al total
	# esperado (ej. 38 jornadas) en lugar de cubrir todo el ancho con N puntos.
	var x_denom: int = max_n
	if _x_max > 0 and _x_max > max_n:
		x_denom = _x_max

	# Gridlines horizontales (3 ticks)
	var ticks := 3
	for i in range(ticks + 1):
		var ty: float = plot_y + plot_h * (1.0 - float(i) / float(ticks))
		draw_line(Vector2(plot_x, ty), Vector2(plot_x + plot_w, ty), theme.border_subtle, 1.0)
		var tick_value: float = draw_min + (draw_max - draw_min) * (float(i) / float(ticks))
		var tick_str: String = "%d" % int(round(tick_value))
		draw_string(font, Vector2(plot_x - 30, ty + 4), tick_str,
				HORIZONTAL_ALIGNMENT_LEFT, 28, 10, theme.text_muted)

	# Dibujar cada serie
	for s: Dictionary in _series:
		var values: Array = s.get("values", [])
		if values.size() == 0:
			continue
		var color: Color = s.get("color", Color(0, 0, 0, 0))
		if color.a == 0:
			color = theme.accent_primary
		var dashed: bool = bool(s.get("dashed", false))
		var fill: bool = bool(s.get("fill", false))

		var pts: PackedVector2Array = PackedVector2Array()
		for i in range(values.size()):
			var fx: float
			if x_denom <= 1:
				fx = plot_x + plot_w * 0.5
			else:
				# Posición proporcional al total esperado (x_denom)
				fx = plot_x + plot_w * (float(i) / float(x_denom - 1))
			var fy: float = plot_y + plot_h * (1.0 - (float(values[i]) - draw_min) / dy_range)
			pts.append(Vector2(fx, fy))

		# Relleno (solo si fill=true)
		if fill and pts.size() >= 2:
			var fill_pts: PackedVector2Array = PackedVector2Array()
			fill_pts.append(Vector2(pts[0].x, plot_y + plot_h))
			for p in pts:
				fill_pts.append(p)
			fill_pts.append(Vector2(pts[pts.size() - 1].x, plot_y + plot_h))
			var fc: Color = color
			fc.a = 0.18
			draw_colored_polygon(fill_pts, fc)

		# Línea (sólida o discontinua)
		if pts.size() >= 2:
			for i in range(pts.size() - 1):
				if dashed:
					_draw_dashed_line(pts[i], pts[i + 1], color, 2.0)
				else:
					draw_line(pts[i], pts[i + 1], color, 2.0)

		# Puntos solo en la serie principal (la primera, normalmente la del user)
		if not dashed:
			for p in pts:
				draw_circle(p, 3.0, color)

	# Leyenda (esquina superior derecha)
	if _series.size() > 1:
		_draw_legend(font, plot_x + plot_w, plot_y)

	# Labels X — mostrar primer y último número de jornada
	if _x_max > 0:
		draw_string(font, Vector2(plot_x, plot_y + plot_h + 16), "J1",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, theme.text_muted)
		var last_str: String = "J%d" % _x_max
		var last_size: Vector2 = font.get_string_size(last_str, HORIZONTAL_ALIGNMENT_RIGHT, -1, 10)
		draw_string(font, Vector2(plot_x + plot_w - last_size.x, plot_y + plot_h + 16), last_str,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, theme.text_muted)


# Dibuja una línea discontinua entre dos puntos.
func _draw_dashed_line(from_pt: Vector2, to_pt: Vector2, color: Color, width: float) -> void:
	var dash_len: float = 4.0
	var gap_len: float = 3.0
	var total: float = from_pt.distance_to(to_pt)
	if total <= 0.0:
		return
	var dir: Vector2 = (to_pt - from_pt).normalized()
	var traveled: float = 0.0
	var draw_dash: bool = true
	while traveled < total:
		var seg_len: float = dash_len if draw_dash else gap_len
		var end_t: float = min(traveled + seg_len, total)
		if draw_dash:
			draw_line(from_pt + dir * traveled, from_pt + dir * end_t, color, width)
		traveled = end_t
		draw_dash = not draw_dash


# Leyenda en una esquina del chart. Cada serie con un cuadrado de color + nombre.
func _draw_legend(font: Font, right_x: float, top_y: float) -> void:
	var theme: UITheme = UIThemeManager.get_current()
	var line_h: int = 14
	var y: float = top_y + 2
	for s: Dictionary in _series:
		var name: String = String(s.get("name", ""))
		if name == "":
			continue
		var color: Color = s.get("color", Color(0, 0, 0, 0))
		if color.a == 0:
			color = theme.accent_primary
		var name_size: Vector2 = font.get_string_size(name, HORIZONTAL_ALIGNMENT_RIGHT, -1, 10)
		var x: float = right_x - name_size.x - 18
		# Cuadrado de color
		draw_rect(Rect2(x, y + 2, 8, 8), color, true)
		# Nombre
		draw_string(font, Vector2(x + 12, y + 10), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, theme.text_secondary)
		y += line_h
