class_name MatchViewer2D extends Control

# Visor 2D del partido — v1 simple.
#
# Renderiza un campo cenital con los 22 jugadores como puntos en sus
# posiciones de formación. La pelota se mueve entre 3 zonas (def/mid/atk)
# según los eventos del partido. Muestra también marcador, reloj y log
# de eventos clave.
#
# Para abrir, llamar set_match_result(result, home_lineup, away_lineup)
# y luego start_playback(). La animación procesa eventos uno a uno con
# un delay configurable.
#
# Coordenadas del campo:
#   - field_rect ocupa el centro del Control. 105m × 68m → escalado a píxeles.
#   - Eje X: 0 (portería home) ... 1 (portería away). Equipo home ataca de izquierda a derecha.
#   - Eje Y: 0 (banda izquierda) ... 1 (banda derecha).
#
# Posiciones por slot (en coords 0..1, desde el POV del equipo home cuando
# defiende a la izquierda y ataca a la derecha):


# Slot -> (x, y) relativo al equipo. x=0 es portería propia, x=1 portería rival.
# Para el equipo away, las x se invierten (1-x) y se sigue mostrando en el mismo campo.
const SLOT_POSITIONS := {
	"GK":  Vector2(0.05, 0.50),
	"CB":  Vector2(0.20, 0.40),  # ajustamos según número de CBs en _build_team_positions
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


# Zonas (de POV del equipo home): x del balón cuando tiene la posesión.
const ZONE_X_HOME := { "def": 0.18, "mid": 0.50, "atk": 0.82 }


var match_result: MatchResult
var home_lineup: Lineup
var away_lineup: Lineup
var event_idx: int = 0
var ball_pos: Vector2 = Vector2(0.50, 0.50)
var current_minute: int = 0
var current_second: int = 0
var score_home: int = 0
var score_away: int = 0
var possession_team: String = "home"  # home | away
var current_zone: String = "mid"
var playing: bool = false
var play_delay_ms: float = 0.4   # segundos entre eventos
var time_acc: float = 0.0

# UI refs
var play_button: Button
var pause_button: Button
var speed_slider: HSlider
var event_log: VBoxContainer
var score_label: Label
var clock_label: Label
var back_button: Button
var on_back: Callable

# Goleadores y eventos clave
var goal_flash_timer: float = 0.0


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	# Fondo opaco que cubre TODO lo que hay detrás (game_hub) para que no se vea solapado
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.10)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # bloquea clicks al UI de detrás
	add_child(bg)
	# Hacemos que el viewer entero también capture input para que no llegue al hub
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func setup(result: MatchResult, hl: Lineup, al: Lineup, back_callback: Callable = Callable()) -> void:
	match_result = result
	home_lineup = hl
	away_lineup = al
	on_back = back_callback
	event_idx = 0
	score_home = 0
	score_away = 0
	current_minute = 0
	current_second = 0
	possession_team = "home"
	current_zone = "mid"
	ball_pos = Vector2(0.50, 0.50)
	_clear_event_log()
	_update_score()
	_update_clock()
	queue_redraw()


# ============================================================================
# UI
# ============================================================================
func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	# Top bar: marcador + reloj + botón volver
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	vbox.add_child(top)

	back_button = Button.new()
	back_button.text = "← Volver"
	back_button.pressed.connect(_on_back_pressed)
	top.add_child(back_button)

	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size", 24)
	top.add_child(score_label)

	clock_label = Label.new()
	clock_label.add_theme_font_size_override("font_size", 18)
	clock_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	top.add_child(clock_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	play_button = Button.new()
	play_button.text = "▶ Play"
	play_button.pressed.connect(_on_play)
	top.add_child(play_button)

	pause_button = Button.new()
	pause_button.text = "❚❚ Pausa"
	pause_button.pressed.connect(_on_pause)
	pause_button.disabled = true
	top.add_child(pause_button)

	var speed_label := Label.new()
	speed_label.text = "Velocidad:"
	top.add_child(speed_label)
	speed_slider = HSlider.new()
	speed_slider.min_value = 0.05
	speed_slider.max_value = 1.5
	speed_slider.step = 0.05
	speed_slider.value = 0.4
	speed_slider.custom_minimum_size.x = 120
	speed_slider.value_changed.connect(func(v: float) -> void: play_delay_ms = v)
	top.add_child(speed_slider)

	vbox.add_child(HSeparator.new())

	# Body: field (izquierda) + event log (derecha)
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	vbox.add_child(body)

	# Field: usa el espacio principal (será dibujado por _draw del Control)
	var field_panel := Control.new()
	field_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field_panel.custom_minimum_size = Vector2(720, 460)
	# El _draw del MatchViewer2D dibuja el campo basado en el bounding rect del field_panel
	field_panel.set_meta("is_field_panel", true)
	field_panel.draw.connect(_draw_field.bind(field_panel))
	body.add_child(field_panel)
	# Update redraw cuando cambia algo del estado
	set_meta("field_panel", field_panel)

	# Event log
	var log_scroll := ScrollContainer.new()
	log_scroll.custom_minimum_size = Vector2(280, 460)
	log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(log_scroll)
	event_log = VBoxContainer.new()
	event_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(event_log)


func _on_back_pressed() -> void:
	playing = false
	if on_back.is_valid():
		on_back.call()


func _on_play() -> void:
	if match_result == null:
		return
	playing = true
	play_button.disabled = true
	pause_button.disabled = false


func _on_pause() -> void:
	playing = false
	play_button.disabled = false
	pause_button.disabled = true


# ============================================================================
# Animación (process)
# ============================================================================
func _process(delta: float) -> void:
	if goal_flash_timer > 0.0:
		goal_flash_timer -= delta
		_get_field_panel().queue_redraw()
	if not playing or match_result == null:
		return
	time_acc += delta
	if time_acc < play_delay_ms:
		return
	time_acc = 0.0
	_advance_one_event()


func _advance_one_event() -> void:
	while event_idx < match_result.events.size():
		var ev: MatchEvent = match_result.events[event_idx]
		event_idx += 1
		# Saltar tipos no interesantes para el log (turnover, etc.)
		current_minute = ev.minute
		current_second = ev.second_in_minute
		_update_clock()
		# Actualizar zona/posesión si el evento da info
		if ev.team_id != "":
			possession_team = "home" if ev.team_id == match_result.home_team_id else "away"
		if ev.zone in ["def", "mid", "atk"]:
			current_zone = ev.zone
		# Actualizar marcador en goles
		if ev.type == MatchEvent.T_GOAL:
			if ev.team_id == match_result.home_team_id:
				score_home += 1
			else:
				score_away += 1
			_update_score()
			goal_flash_timer = 0.6
			_log_event(ev, Color(0.4, 1.0, 0.5))
			_update_ball_position()
			_get_field_panel().queue_redraw()
			return
		if ev.type in [MatchEvent.T_SHOT_ON, MatchEvent.T_SHOT_OFF, MatchEvent.T_SHOT_BLOCKED,
				MatchEvent.T_SAVE, MatchEvent.T_YELLOW, MatchEvent.T_RED, MatchEvent.T_SUBSTITUTION,
				MatchEvent.T_HALFTIME, MatchEvent.T_FULLTIME, MatchEvent.T_KICKOFF,
				MatchEvent.T_CORNER, MatchEvent.T_OFFSIDE]:
			var color: Color = Color(0.85, 0.85, 0.85)
			if ev.type == MatchEvent.T_RED:
				color = Color(1.0, 0.4, 0.4)
			elif ev.type == MatchEvent.T_YELLOW:
				color = Color(1.0, 0.85, 0.2)
			elif ev.type == MatchEvent.T_HALFTIME or ev.type == MatchEvent.T_FULLTIME:
				color = Color(0.6, 0.8, 1.0)
			elif ev.type == MatchEvent.T_SAVE:
				color = Color(0.8, 0.8, 1.0)
			_log_event(ev, color)
			_update_ball_position()
			_get_field_panel().queue_redraw()
			# End playback en FULLTIME
			if ev.type == MatchEvent.T_FULLTIME:
				playing = false
				play_button.disabled = true
				pause_button.disabled = true
			return
	# Si llegamos aquí, no quedan eventos
	playing = false
	play_button.disabled = true
	pause_button.disabled = true


func _update_ball_position() -> void:
	# Posición x según zona y POV del equipo en posesión
	var x: float = ZONE_X_HOME[current_zone]
	if possession_team == "away":
		x = 1.0 - x
	# y aleatorio dentro de un rango razonable
	var y: float = 0.5 + sin(float(event_idx) * 0.7) * 0.2
	ball_pos = Vector2(x, y)


# ============================================================================
# Update labels
# ============================================================================
func _update_score() -> void:
	if match_result == null:
		return
	score_label.text = "%s  %d - %d  %s" % [
		match_result.home_team_name.left(20),
		score_home, score_away,
		match_result.away_team_name.left(20),
	]


func _update_clock() -> void:
	clock_label.text = "%02d:%02d" % [current_minute, current_second]


func _clear_event_log() -> void:
	for c in event_log.get_children():
		c.queue_free()


func _log_event(ev: MatchEvent, color: Color) -> void:
	var l := Label.new()
	l.text = "%s  %s" % [ev.clock_str(), ev.description]
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_log.add_child(l)


# ============================================================================
# Field rendering
# ============================================================================
func _get_field_panel() -> Control:
	return get_meta("field_panel")


func _draw_field(panel: Control) -> void:
	if match_result == null:
		return
	var size: Vector2 = panel.size
	var pad: float = 12.0
	var rect := Rect2(Vector2(pad, pad), size - Vector2(pad * 2, pad * 2))

	# Césped
	var grass_color: Color = Color(0.10, 0.45, 0.18)
	if goal_flash_timer > 0.0:
		grass_color = grass_color.lerp(Color(0.4, 1.0, 0.5), 0.3)
	panel.draw_rect(rect, grass_color, true)

	# Líneas
	var line_color: Color = Color(1, 1, 1, 0.85)
	var lw: float = 2.0
	panel.draw_rect(rect, line_color, false, lw)
	# Línea media
	var mid_x: float = rect.position.x + rect.size.x / 2.0
	panel.draw_line(Vector2(mid_x, rect.position.y), Vector2(mid_x, rect.end.y), line_color, lw)
	# Círculo central
	panel.draw_arc(Vector2(mid_x, rect.position.y + rect.size.y / 2.0), rect.size.y * 0.12, 0, TAU, 32, line_color, lw)
	# Áreas
	var area_w: float = rect.size.x * 0.13
	var area_h: float = rect.size.y * 0.55
	var area_y: float = rect.position.y + (rect.size.y - area_h) / 2.0
	# Local
	panel.draw_rect(Rect2(Vector2(rect.position.x, area_y), Vector2(area_w, area_h)), line_color, false, lw)
	# Visitante
	panel.draw_rect(Rect2(Vector2(rect.end.x - area_w, area_y), Vector2(area_w, area_h)), line_color, false, lw)
	# Punto de penalti
	panel.draw_circle(Vector2(rect.position.x + area_w * 0.7, rect.position.y + rect.size.y / 2.0), 2.5, line_color)
	panel.draw_circle(Vector2(rect.end.x - area_w * 0.7, rect.position.y + rect.size.y / 2.0), 2.5, line_color)
	# Porterías
	var goal_h: float = rect.size.y * 0.18
	var goal_y: float = rect.position.y + (rect.size.y - goal_h) / 2.0
	panel.draw_line(Vector2(rect.position.x, goal_y), Vector2(rect.position.x, goal_y + goal_h), Color(1, 1, 1), 4)
	panel.draw_line(Vector2(rect.end.x, goal_y), Vector2(rect.end.x, goal_y + goal_h), Color(1, 1, 1), 4)

	# Jugadores home (izquierda)
	if home_lineup != null:
		var home_color: Color = _team_color(home_lineup.team, true)
		_draw_team(panel, rect, home_lineup, home_color, false)
	# Jugadores away (derecha, x invertida)
	if away_lineup != null:
		var away_color: Color = _team_color(away_lineup.team, false)
		_draw_team(panel, rect, away_lineup, away_color, true)

	# Pelota
	var bx: float = rect.position.x + ball_pos.x * rect.size.x
	var by: float = rect.position.y + ball_pos.y * rect.size.y
	panel.draw_circle(Vector2(bx, by), 6.0, Color(1, 1, 1))
	panel.draw_circle(Vector2(bx, by), 6.0, Color(0, 0, 0), false, 1.5)


func _draw_team(panel: Control, rect: Rect2, lineup: Lineup, color: Color, mirror: bool) -> void:
	# Conta CBs para layout dinámico
	var cb_count: int = 0
	for s in lineup.slot_assignments:
		if s == "CB":
			cb_count += 1
	var cb_seen: int = 0

	for i in lineup.starting_eleven.size():
		var slot: String = lineup.slot_assignments[i] if i < lineup.slot_assignments.size() else "CM"
		var pos: Vector2 = SLOT_POSITIONS.get(slot, Vector2(0.45, 0.5))

		# Spread CBs verticalmente si hay 3+
		if slot == "CB" and cb_count >= 2:
			var idx: float = float(cb_seen) / float(cb_count - 1)
			pos.y = lerp(0.32, 0.68, idx)
			cb_seen += 1
		# LB/RB: ya tienen y fijos
		# Centrales del medio: spread vertical
		if slot == "CM":
			# si hay 2-3 CMs, repartir verticalmente
			pass

		if mirror:
			pos.x = 1.0 - pos.x

		var px: float = rect.position.x + pos.x * rect.size.x
		var py: float = rect.position.y + pos.y * rect.size.y
		panel.draw_circle(Vector2(px, py), 9.0, color)
		panel.draw_circle(Vector2(px, py), 9.0, Color(0, 0, 0, 0.6), false, 1.5)
		# Dorsal
		var dorsal: int = lineup.starting_eleven[i].shirt_number
		var label_size: int = 10
		panel.draw_string(ThemeDB.fallback_font, Vector2(px - 6, py + 4), str(dorsal),
			HORIZONTAL_ALIGNMENT_CENTER, -1, label_size, Color(1, 1, 1))


func _team_color(team: Team, is_home: bool) -> Color:
	if team == null or team.colors == null:
		return Color(0.6, 0.6, 0.6) if is_home else Color(0.4, 0.4, 0.8)
	var hex: String = String(team.colors.get("primary" if is_home else "secondary", "#888888"))
	return Color.from_string(hex, Color(0.6, 0.6, 0.6))
