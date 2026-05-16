class_name LineChart extends Control

# Chart de línea simple con _draw. Usado en Dashboard para mostrar puntos
# acumulados por jornada del user.
#
# Auto-escalado: min/max calculados desde values. Relleno translúcido bajo línea.
# X-axis: index implícito (1..N) o labels custom. Y-axis: min/max ticks.

var _values: Array = []         # Array[float | int]
var _labels_x: Array = []       # Array[String] opcional, len == values.size()
var _title: String = ""
var _y_label: String = ""
var _color_override: Color = Color(0, 0, 0, 0)  # transparente = usar accent_primary del theme


func _ready() -> void:
	custom_minimum_size = Vector2(380, 180)


# values: Array de int/float. Si está vacío, dibuja placeholder.
# labels_x: Array de String paralelo a values (ej. ["J1","J2",...]) — opcional
# title: header del chart
# y_label: leyenda eje Y (ej. "Puntos")
func setup(values: Array, labels_x: Array = [], title: String = "", y_label: String = "") -> void:
	_values = values
	_labels_x = labels_x
	_title = title
	_y_label = y_label
	queue_redraw()


# Cambia color de la línea (default: accent_primary del theme)
func set_line_color(c: Color) -> void:
	_color_override = c
	queue_redraw()


func _draw() -> void:
	var theme: UITheme = UIThemeManager.get_current()
	var rect := Rect2(Vector2.ZERO, size)

	# Fondo glass del chart — mismo look que el resto de paneles del dashboard
	draw_style_box(UIThemeManager.glass_panel_style(), rect)
	# Highlight superior fino (efecto inner-light glass)
	draw_line(Vector2(8, 1), Vector2(size.x - 8, 1), Color(1, 1, 1, 0.14), 1.0)

	var font := ThemeDB.fallback_font
	var pad_top: float = 14.0
	var pad_left: float = 38.0
	var pad_right: float = 14.0
	var pad_bottom: float = 28.0

	# Título
	if _title != "":
		draw_string(font, Vector2(pad_left, pad_top + 12), _title.to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, theme.text_secondary)
		pad_top += 22

	if _values.is_empty():
		draw_string(font, Vector2(size.x * 0.5 - 30, size.y * 0.5), "Sin datos",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, theme.text_muted)
		return

	# Área de plot
	var plot_x: float = pad_left
	var plot_y: float = pad_top
	var plot_w: float = size.x - pad_left - pad_right
	var plot_h: float = size.y - pad_top - pad_bottom

	# Min/max auto
	var v_min: float = INF
	var v_max: float = -INF
	for v in _values:
		var fv: float = float(v)
		v_min = min(v_min, fv)
		v_max = max(v_max, fv)
	if v_min == v_max:
		v_max = v_min + 1.0
	# Margen 10% arriba
	var v_range: float = v_max - v_min
	var draw_max: float = v_max + v_range * 0.10
	var draw_min: float = max(0.0, v_min - v_range * 0.05)
	var dy_range: float = draw_max - draw_min
	if dy_range <= 0.0:
		dy_range = 1.0

	# Gridlines horizontales (3 ticks)
	var ticks := 3
	for i in range(ticks + 1):
		var ty: float = plot_y + plot_h * (1.0 - float(i) / float(ticks))
		draw_line(Vector2(plot_x, ty), Vector2(plot_x + plot_w, ty), theme.border_subtle, 1.0)
		# Label tick
		var tick_value: float = draw_min + (draw_max - draw_min) * (float(i) / float(ticks))
		var tick_str: String = "%d" % int(round(tick_value))
		draw_string(font, Vector2(plot_x - 30, ty + 4), tick_str,
				HORIZONTAL_ALIGNMENT_LEFT, 28, 10, theme.text_muted)

	# Puntos del polyline
	var n: int = _values.size()
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(n):
		var fx: float
		if n == 1:
			fx = plot_x + plot_w * 0.5
		else:
			fx = plot_x + plot_w * (float(i) / float(n - 1))
		var fy: float = plot_y + plot_h * (1.0 - (float(_values[i]) - draw_min) / dy_range)
		pts.append(Vector2(fx, fy))

	# Relleno bajo la línea (polygon)
	var line_color: Color = theme.accent_primary if _color_override.a == 0 else _color_override
	if pts.size() >= 2:
		var fill_pts: PackedVector2Array = PackedVector2Array()
		fill_pts.append(Vector2(pts[0].x, plot_y + plot_h))
		for p in pts:
			fill_pts.append(p)
		fill_pts.append(Vector2(pts[pts.size() - 1].x, plot_y + plot_h))
		var fill_color: Color = line_color
		fill_color.a = 0.15
		draw_colored_polygon(fill_pts, fill_color)

	# Línea
	if pts.size() >= 2:
		for i in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], line_color, 2.0)

	# Puntos
	for p in pts:
		draw_circle(p, 3.0, line_color)

	# Labels X (mostramos máx 6 etiquetas para no saturar)
	if _labels_x.size() == n:
		var step: int = max(1, n / 6)
		for i in range(n):
			if i % step != 0 and i != n - 1:
				continue
			var lbl: String = String(_labels_x[i])
			var sz: Vector2 = font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
			var lx: float = pts[i].x - sz.x * 0.5
			draw_string(font, Vector2(lx, plot_y + plot_h + 16), lbl,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, theme.text_muted)
