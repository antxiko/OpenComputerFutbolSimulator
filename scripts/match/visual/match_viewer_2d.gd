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
var ball_target: Vector2 = Vector2(0.50, 0.50)
# El balón usa interpolación basada en tiempo: recorre la distancia hacia el
# target en `BALL_TRANSIT_TIME` segundos para movimientos normales y en
# `SHOT_TRANSIT_TIME` segundos para tiros (más rápido pero VISIBLE).
const BALL_TRANSIT_TIME: float = 0.55
const SHOT_TRANSIT_TIME: float = 0.30
const PASS_TRANSIT_TIME: float = 0.28  # pases granulares: balón viaja rápido entre jugadores
var ball_trail: Array = []           # Vector2[] últimas posiciones para dibujar estela
var ball_anim_total: float = BALL_TRANSIT_TIME  # tiempo total para cruzar la distancia actual
var ball_anim_remaining: float = 0.0
var ball_anim_origin: Vector2 = Vector2(0.50, 0.50)
var current_minute: int = 0
var current_second: int = 0
var score_home: int = 0
var score_away: int = 0
var possession_team: String = "home"  # home | away
var current_zone: String = "mid"
var playing: bool = false
var play_delay_ms: float = 0.7   # segundos entre eventos (>= BALL_TRANSIT_TIME para que la animación complete)
# Modo highlights: skip eventos triviales (turnover/keep/lose), solo anima
# eventos clave (goles, tiros, paradas, tarjetas, córner, falta, kickoff/halftime/fulltime).
var highlights_only: bool = false
var time_acc: float = 0.0

# Movimiento de jugadores: offsets dinámicos sobre la posición de formación.
# Calculados cada frame en función de zona/posesión/cercanía al balón.
var home_player_offsets: Array = []   # Vector2[] (current)
var away_player_offsets: Array = []
var home_player_targets: Array = []   # Vector2[] (target — hacia donde se interpola)
var away_player_targets: Array = []

# Animación especial de tiro/parada
var shot_animation_active: bool = false
var shot_animation_remaining: float = 0.0   # cuenta atrás durante la animación
var last_event_type: String = ""
# Animaciones de eventos granulares puntuales
var fallen_player_id: String = ""           # jugador "tirado" tras T_TACKLE_FAIL
var fallen_timer: float = 0.0
var foul_shake_player_id: String = ""       # jugador con shake tras T_TACTICAL_FOUL
var foul_shake_timer: float = 0.0

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
	ball_target = ball_pos
	ball_trail.clear()
	last_event_type = ""
	shot_animation_active = false
	shot_animation_remaining = 0.0
	# Inicializar offsets de jugadores a cero
	home_player_offsets = []
	home_player_targets = []
	away_player_offsets = []
	away_player_targets = []
	if home_lineup != null:
		for i in home_lineup.starting_eleven.size():
			home_player_offsets.append(Vector2.ZERO)
			home_player_targets.append(Vector2.ZERO)
	if away_lineup != null:
		for i in away_lineup.starting_eleven.size():
			away_player_offsets.append(Vector2.ZERO)
			away_player_targets.append(Vector2.ZERO)
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
	speed_slider.min_value = 0.10
	speed_slider.max_value = 2.0
	speed_slider.step = 0.05
	speed_slider.value = 0.7
	speed_slider.custom_minimum_size.x = 120
	speed_slider.tooltip_text = "Tiempo entre eventos. Menor = más rápido."
	speed_slider.value_changed.connect(func(v: float) -> void: play_delay_ms = v)
	top.add_child(speed_slider)

	# Toggle: modo highlights (skip eventos triviales)
	var highlights_btn := CheckBox.new()
	highlights_btn.text = "🎬 Solo highlights"
	highlights_btn.tooltip_text = "Salta posesiones intermedias y muestra solo eventos clave (goles, tiros, tarjetas, córners)."
	highlights_btn.button_pressed = false
	highlights_btn.toggled.connect(func(p: bool) -> void: highlights_only = p)
	top.add_child(highlights_btn)

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
	if shot_animation_remaining > 0.0:
		shot_animation_remaining -= delta
		if shot_animation_remaining <= 0.0:
			shot_animation_active = false
	if fallen_timer > 0.0:
		fallen_timer -= delta
		if fallen_timer <= 0.0:
			fallen_player_id = ""
	if foul_shake_timer > 0.0:
		foul_shake_timer -= delta
		if foul_shake_timer <= 0.0:
			foul_shake_player_id = ""

	# Animación continua: balón y jugadores se interpolan suavemente cada frame
	if match_result != null:
		_update_ball_smooth(delta)
		_update_players_smooth(delta)
		_get_field_panel().queue_redraw()

	if not playing or match_result == null:
		return
	time_acc += delta
	# En modo highlights, reducir delay efectivo (más ágil entre highlights).
	var effective_delay: float = play_delay_ms * (0.55 if highlights_only else 1.0)
	if time_acc < effective_delay:
		return
	time_acc = 0.0
	_advance_one_event()


func _update_ball_smooth(delta: float) -> void:
	# Interpolación basada en tiempo: el balón llega al target en
	# ball_anim_total segundos (sea cual sea la distancia). Esto hace que
	# tiros cortos no sean teletransporte y movimientos largos no eternos.
	if ball_anim_remaining <= 0.0:
		return
	ball_anim_remaining = max(0.0, ball_anim_remaining - delta)
	var t_elapsed: float = ball_anim_total - ball_anim_remaining
	var t_norm: float = clamp(t_elapsed / max(0.001, ball_anim_total), 0.0, 1.0)
	# Curva de easing: smooth-in-out para movimientos normales, ease-out para tiros (sale rápido y se frena al final)
	var eased: float
	if shot_animation_active:
		# ease-out cubic: arrancada explosiva, frenada al impactar
		eased = 1.0 - pow(1.0 - t_norm, 3)
	else:
		# smoothstep clásico
		eased = t_norm * t_norm * (3.0 - 2.0 * t_norm)
	ball_pos = ball_anim_origin.lerp(ball_target, eased)
	# Trail
	ball_trail.append(ball_pos)
	while ball_trail.size() > 8:
		ball_trail.pop_front()


# Llamada cuando ball_target cambia. Resetea animación con duración apropiada.
func _kick_off_ball_animation() -> void:
	ball_anim_origin = ball_pos
	if shot_animation_active:
		ball_anim_total = SHOT_TRANSIT_TIME
	elif last_event_type in [MatchEvent.T_PASS, MatchEvent.T_LONG_BALL, MatchEvent.T_DRIBBLE, MatchEvent.T_INTERCEPT]:
		ball_anim_total = PASS_TRANSIT_TIME
	else:
		ball_anim_total = BALL_TRANSIT_TIME
	ball_anim_remaining = ball_anim_total


func _update_players_smooth(delta: float) -> void:
	# Cada jugador tiene un offset target calculado según el contexto del juego.
	# Después se interpola el offset actual hacia el target con velocidad rápida
	# para que el movimiento sea visible.
	if home_lineup == null or away_lineup == null:
		return
	_compute_player_targets(home_lineup, home_player_targets, false)
	_compute_player_targets(away_lineup, away_player_targets, true)
	# alpha alto = respuesta rápida; los jugadores llegan al target en ~0.3-0.4s
	var alpha: float = clamp(delta * 4.0, 0.0, 1.0)
	for i in home_player_offsets.size():
		home_player_offsets[i] = home_player_offsets[i].lerp(home_player_targets[i], alpha)
	for i in away_player_offsets.size():
		away_player_offsets[i] = away_player_offsets[i].lerp(away_player_targets[i], alpha)


func _compute_player_targets(lineup: Lineup, targets: Array, mirror: bool) -> void:
	var team_id: String = lineup.team.id if lineup.team else ""
	var has_possession: bool = (team_id == match_result.home_team_id and possession_team == "home") \
			or (team_id == match_result.away_team_id and possession_team == "away")

	# Tiempo relativo para "breathing" (oscilación natural de jugadores)
	var t_now: float = float(Time.get_ticks_msec()) / 1000.0

	for i in lineup.starting_eleven.size():
		var slot: String = lineup.slot_assignments[i] if i < lineup.slot_assignments.size() else "CM"
		var base_pos: Vector2 = SLOT_POSITIONS.get(slot, Vector2(0.45, 0.5))
		if mirror:
			base_pos.x = 1.0 - base_pos.x

		# Distancia del jugador al balón en coords del campo
		var to_ball: Vector2 = ball_pos - base_pos
		var dist: float = to_ball.length()

		# Offset target inicial: cero
		var off: Vector2 = Vector2.ZERO

		# 1) Movimiento global del bloque hacia el balón / repliegue.
		# Bloque entero se desplaza según la zona X actual del balón (-0.5 a +0.5).
		# El equipo en posesión empuja MÁS hacia adelante; el otro repliega hacia atrás.
		var ball_x_signed: float = ball_pos.x - 0.5  # negativo = balón en mitad propia, positivo = mitad rival
		# Para el equipo away (mirror), invertimos
		if mirror:
			ball_x_signed = -ball_x_signed
		var block_shift: float = 0.0
		if has_possession:
			# Empujamos según rol y dirección del balón
			if slot in ["ST", "LW", "RW", "CF"]:
				block_shift = 0.18 + max(0.0, ball_x_signed) * 0.10  # atacantes adelantadísimos
			elif slot == "CAM":
				block_shift = 0.14
			elif slot in ["CM", "CDM", "LM", "RM"]:
				block_shift = 0.10
			elif slot in ["LB", "RB", "LWB", "RWB"]:
				block_shift = 0.13  # laterales se incorporan al ataque
			elif slot == "CB":
				block_shift = 0.06  # CBs adelantan línea
		else:
			# Sin posesión: presionar adelante o replegar
			if slot in ["ST", "LW", "RW"]:
				block_shift = 0.04  # presión en la salida pero no demasiado
			elif slot == "CAM":
				block_shift = 0.06
			elif slot in ["CM", "CDM"]:
				block_shift = 0.05
			elif slot in ["LB", "RB"]:
				block_shift = -0.04  # laterales replegados
			elif slot == "CB":
				block_shift = -0.06

		# Aplicar block_shift en dirección hacia portería rival
		var attack_dir: float = -1.0 if mirror else 1.0
		off.x += block_shift * attack_dir

		# 2) Movimiento lateral del bloque siguiendo Y del balón (compactación)
		# Los jugadores del medio + defensa se desplazan ligeramente hacia el lado del balón.
		if slot != "GK":
			var ball_y_signed: float = ball_pos.y - 0.5
			off.y += ball_y_signed * 0.12

		# 3) Atracción AL balón para los jugadores cercanos (excluye GK).
		# Mucho más fuerte que antes: si estás a < 0.25 te acercas activamente.
		if dist < 0.35 and slot != "GK":
			var pull_strength: float = (0.35 - dist) * 1.3   # más fuerte cuanto más cerca
			off += to_ball.normalized() * pull_strength * 0.18

		# 4) GK: sigue la altura del balón con más amplitud y se adelanta si el balón está lejos
		if slot == "GK":
			off.y = (ball_pos.y - 0.5) * 0.30
			# si el balón está en la mitad rival, el GK se adelanta un poco
			var half_x: float = 0.5 if not mirror else 0.5
			var ball_in_my_half: float = (0.5 - ball_pos.x) if not mirror else (ball_pos.x - 0.5)
			if ball_in_my_half < 0:  # balón en campo rival
				off.x += 0.04 * attack_dir

		# 5) Breathing: oscilación constante para que se vea que están vivos
		var phase: float = t_now * 1.5 + float(i) * 0.7 + (3.14 if mirror else 0.0)
		off.x += sin(phase) * 0.012
		off.y += cos(phase * 1.3) * 0.012

		# 6) Limitar offset total (rangos amplios para movimiento visible)
		off.x = clamp(off.x, -0.22, 0.22)
		off.y = clamp(off.y, -0.18, 0.18)

		if i < targets.size():
			targets[i] = off
		else:
			targets.append(off)


func _advance_one_event() -> void:
	while event_idx < match_result.events.size():
		var ev: MatchEvent = match_result.events[event_idx]
		event_idx += 1
		current_minute = ev.minute
		current_second = ev.second_in_minute
		_update_clock()
		# Actualizar zona/posesión si el evento da info
		if ev.team_id != "":
			possession_team = "home" if ev.team_id == match_result.home_team_id else "away"
		if ev.zone in ["def", "mid", "atk"]:
			current_zone = ev.zone
		last_event_type = ev.type
		# Eventos granulares (pases, regates, intercepciones): el balón viaja al
		# jugador receptor pero NO se loggea ni cuenta como highlight.
		if ev.type in [MatchEvent.T_PASS, MatchEvent.T_LONG_BALL, MatchEvent.T_CROSS,
				MatchEvent.T_DRIBBLE, MatchEvent.T_INTERCEPT,
				MatchEvent.T_TACKLE_FAIL, MatchEvent.T_TACTICAL_FOUL,
				MatchEvent.T_THROW_IN, MatchEvent.T_GK_DIST,
				MatchEvent.T_HEADER, MatchEvent.T_VOLLEY]:
			if highlights_only:
				continue  # skip en modo highlights
			_set_ball_for_event(ev)
			# Delay reducido para que los pases pasen rápido y no eternicen el partido
			time_acc = -play_delay_ms * 0.55  # próxima animación en ~45% del delay normal
			return
		# Actualizar marcador en goles
		if ev.type == MatchEvent.T_GOAL:
			if ev.team_id == match_result.home_team_id:
				score_home += 1
			else:
				score_away += 1
			_update_score()
			goal_flash_timer = 0.6
			_log_event(ev, Color(0.4, 1.0, 0.5))
			_set_ball_for_event(ev)
			return
		if ev.type in [MatchEvent.T_SHOT_ON, MatchEvent.T_SHOT_OFF, MatchEvent.T_SHOT_BLOCKED,
				MatchEvent.T_SAVE, MatchEvent.T_YELLOW, MatchEvent.T_RED, MatchEvent.T_SUBSTITUTION,
				MatchEvent.T_HALFTIME, MatchEvent.T_FULLTIME, MatchEvent.T_KICKOFF,
				MatchEvent.T_CORNER, MatchEvent.T_OFFSIDE, MatchEvent.T_PENALTY,
				MatchEvent.T_FREE_KICK]:
			var color: Color = Color(0.85, 0.85, 0.85)
			if ev.type == MatchEvent.T_RED:
				color = Color(1.0, 0.4, 0.4)
			elif ev.type == MatchEvent.T_YELLOW:
				color = Color(1.0, 0.85, 0.2)
			elif ev.type == MatchEvent.T_HALFTIME or ev.type == MatchEvent.T_FULLTIME:
				color = Color(0.6, 0.8, 1.0)
			elif ev.type == MatchEvent.T_SAVE:
				color = Color(0.8, 0.8, 1.0)
			elif ev.type == MatchEvent.T_PENALTY:
				color = Color(1.0, 0.6, 0.4)
			elif ev.type == MatchEvent.T_FREE_KICK:
				color = Color(0.85, 0.95, 0.6)
			_log_event(ev, color)
			_set_ball_for_event(ev)
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


# Calcula el target del balón según el evento. La interpolación posterior
# produce el movimiento suave en _update_ball_smooth.
func _set_ball_for_event(ev: MatchEvent) -> void:
	# Atacante: equipo en posesión. Goal_x: portería a la que se ataca.
	var attacking_home: bool = (possession_team == "home")
	var goal_x: float = 0.97 if attacking_home else 0.03

	if ev.type == MatchEvent.T_GOAL or ev.type == MatchEvent.T_SHOT_ON or ev.type == MatchEvent.T_SAVE:
		# Tiro a portería: balón vuela hacia el palo
		shot_animation_active = true
		shot_animation_remaining = play_delay_ms * 0.85
		var goal_y: float = 0.5 + (randf() - 0.5) * 0.18
		ball_target = Vector2(goal_x, goal_y)
		_kick_off_ball_animation()
		return
	if ev.type == MatchEvent.T_SHOT_OFF:
		# Disparo fuera: balón pasa por encima/al lado de la portería
		shot_animation_active = true
		shot_animation_remaining = play_delay_ms * 0.85
		var off_y: float = 0.5 + (randf() - 0.5) * 0.50
		var off_x: float = goal_x + (0.04 if attacking_home else -0.04)
		ball_target = Vector2(off_x, clamp(off_y, 0.05, 0.95))
		_kick_off_ball_animation()
		return
	if ev.type == MatchEvent.T_SHOT_BLOCKED:
		# Bloqueado: balón rebota en zona de remate
		shot_animation_active = true
		shot_animation_remaining = play_delay_ms * 0.5
		var bx: float = 0.78 if attacking_home else 0.22
		var by: float = 0.5 + (randf() - 0.5) * 0.25
		ball_target = Vector2(bx, by)
		_kick_off_ball_animation()
		return
	if ev.type == MatchEvent.T_CORNER:
		# Saque de esquina: en la esquina del campo atacante
		var cx: float = 0.99 if attacking_home else 0.01
		var cy: float = 0.05 if randf() < 0.5 else 0.95
		ball_target = Vector2(cx, cy)
		_kick_off_ball_animation()
		return
	if ev.type == MatchEvent.T_KICKOFF or ev.type == MatchEvent.T_HALFTIME:
		ball_target = Vector2(0.50, 0.50)
		_kick_off_ball_animation()
		return
	if ev.type == MatchEvent.T_PENALTY:
		# Balón al punto de penalty del equipo defensor
		var px: float = 0.88 if attacking_home else 0.12
		ball_target = Vector2(px, 0.50)
		_kick_off_ball_animation()
		return
	if ev.type == MatchEvent.T_FREE_KICK:
		# Balón al jugador que saca la falta
		var server_pos: Vector2 = _get_player_field_pos(ev.player_id)
		if server_pos != Vector2.ZERO:
			ball_target = server_pos
			_kick_off_ball_animation()
			return
	# Eventos granulares: balón hacia el receptor (pase) o actor (regate/intercept)
	if ev.type == MatchEvent.T_PASS or ev.type == MatchEvent.T_LONG_BALL or ev.type == MatchEvent.T_CROSS:
		var receiver_pos: Vector2 = _get_player_field_pos(ev.secondary_player_id)
		if receiver_pos != Vector2.ZERO:
			ball_target = receiver_pos
			_kick_off_ball_animation()
			return
	if ev.type == MatchEvent.T_DRIBBLE:
		# El balón se queda con el regateador, pequeña oscilación en el sitio
		var actor_pos: Vector2 = _get_player_field_pos(ev.player_id)
		if actor_pos != Vector2.ZERO:
			ball_target = actor_pos + Vector2(randf_range(-0.03, 0.03), randf_range(-0.03, 0.03))
			_kick_off_ball_animation()
			return
	if ev.type == MatchEvent.T_INTERCEPT:
		var int_pos: Vector2 = _get_player_field_pos(ev.player_id)
		if int_pos != Vector2.ZERO:
			ball_target = int_pos
			_kick_off_ball_animation()
			return
	if ev.type == MatchEvent.T_TACKLE_FAIL:
		# Regate fallido: balón rebota lejos del regateador. Marcar al jugador como caído.
		var fallen_pos: Vector2 = _get_player_field_pos(ev.player_id)
		if fallen_pos != Vector2.ZERO:
			fallen_player_id = ev.player_id
			fallen_timer = 0.6  # ~0.6s "tirado" en el suelo
			# Balón rebota en dirección aleatoria a 0.08-0.12 de distancia
			var dir: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
			ball_target = fallen_pos + dir * 0.10
			_kick_off_ball_animation()
			return
	if ev.type == MatchEvent.T_TACTICAL_FOUL:
		# Falta táctica: balón se detiene cerca del fouler. Pequeño shake del que comete falta.
		var foul_pos: Vector2 = _get_player_field_pos(ev.player_id)
		if foul_pos != Vector2.ZERO:
			foul_shake_player_id = ev.player_id
			foul_shake_timer = 0.5
			ball_target = foul_pos
			_kick_off_ball_animation()
			return
	if ev.type == MatchEvent.T_THROW_IN:
		# Saque de banda: balón a la banda más cercana al jugador
		var thrower_pos: Vector2 = _get_player_field_pos(ev.player_id)
		if thrower_pos != Vector2.ZERO:
			# Subir el balón a la línea de banda (y ≈ 0.02 o 0.98 según lado)
			var sideline_y: float = 0.02 if thrower_pos.y < 0.5 else 0.98
			ball_target = Vector2(thrower_pos.x, sideline_y)
			_kick_off_ball_animation()
			return
	if ev.type == MatchEvent.T_GK_DIST:
		# Portero saca: balón al GK
		var gk_pos: Vector2 = _get_player_field_pos(ev.player_id)
		if gk_pos != Vector2.ZERO:
			ball_target = gk_pos
			_kick_off_ball_animation()
			return
	if ev.type == MatchEvent.T_HEADER or ev.type == MatchEvent.T_VOLLEY:
		# Cabezazo / volea: balón al shooter (ya suele estar ahí)
		var shooter_pos: Vector2 = _get_player_field_pos(ev.player_id)
		if shooter_pos != Vector2.ZERO:
			ball_target = shooter_pos
			_kick_off_ball_animation()
			return
	# Resto de eventos (foul, yellow, red, etc): posición por zona estándar
	_update_ball_position()


# Devuelve la posición del jugador en coordenadas del campo (0..1) incluyendo
# el offset dinámico actual. Vector2.ZERO si no se encuentra (id vacío o
# jugador no está en pista).
func _get_player_field_pos(player_id: String) -> Vector2:
	if player_id == "" or home_lineup == null or away_lineup == null:
		return Vector2.ZERO
	# Buscar en home
	for i in home_lineup.starting_eleven.size():
		if home_lineup.starting_eleven[i].id == player_id:
			var slot: String = home_lineup.slot_assignments[i] if i < home_lineup.slot_assignments.size() else "CM"
			var base: Vector2 = SLOT_POSITIONS.get(slot, Vector2(0.5, 0.5))
			var off: Vector2 = home_player_offsets[i] if i < home_player_offsets.size() else Vector2.ZERO
			return base + off
	# Buscar en away (mirror)
	for i in away_lineup.starting_eleven.size():
		if away_lineup.starting_eleven[i].id == player_id:
			var slot: String = away_lineup.slot_assignments[i] if i < away_lineup.slot_assignments.size() else "CM"
			var base: Vector2 = SLOT_POSITIONS.get(slot, Vector2(0.5, 0.5))
			base.x = 1.0 - base.x  # mirror
			var off: Vector2 = away_player_offsets[i] if i < away_player_offsets.size() else Vector2.ZERO
			return base + off
	return Vector2.ZERO


func _update_ball_position() -> void:
	# Target según zona y POV del equipo en posesión (movimiento "normal" del balón).
	# Añadimos algo de jitter en y proporcional al evento para que el balón se
	# mueva por toda la zona, no en línea recta.
	var x: float = ZONE_X_HOME[current_zone]
	if possession_team == "away":
		x = 1.0 - x
	# Pequeño jitter en x dentro de la zona (distintos pases en la misma zona)
	x += (randf() - 0.5) * 0.10
	var y: float = 0.30 + randf() * 0.40   # entre 0.30 y 0.70
	ball_target = Vector2(clamp(x, 0.05, 0.95), y)
	_kick_off_ball_animation()


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
		var home_has_poss: bool = (possession_team == "home")
		_draw_team(panel, rect, home_lineup, home_color, false, home_has_poss, home_player_offsets)
	# Jugadores away (derecha, x invertida)
	if away_lineup != null:
		var away_color: Color = _team_color(away_lineup.team, false)
		var away_has_poss: bool = (possession_team == "away")
		_draw_team(panel, rect, away_lineup, away_color, true, away_has_poss, away_player_offsets)

	# Trail del balón (solo si está moviéndose)
	for i in ball_trail.size():
		var alpha: float = float(i) / float(ball_trail.size())
		var tp: Vector2 = ball_trail[i]
		var tx: float = rect.position.x + tp.x * rect.size.x
		var ty: float = rect.position.y + tp.y * rect.size.y
		panel.draw_circle(Vector2(tx, ty), 3.0 * alpha + 1.0, Color(1, 1, 1, alpha * 0.4))

	# Pelota
	var bx: float = rect.position.x + ball_pos.x * rect.size.x
	var by: float = rect.position.y + ball_pos.y * rect.size.y
	var ball_radius: float = 7.0 if shot_animation_active else 6.0
	panel.draw_circle(Vector2(bx, by), ball_radius, Color(1, 1, 1))
	panel.draw_circle(Vector2(bx, by), ball_radius, Color(0, 0, 0), false, 1.5)


func _draw_team(panel: Control, rect: Rect2, lineup: Lineup, color: Color, mirror: bool,
		has_possession: bool, offsets: Array) -> void:
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

		if mirror:
			pos.x = 1.0 - pos.x

		# Offset dinámico (movimiento hacia balón / repliegue)
		if i < offsets.size():
			pos += offsets[i]

		var px: float = rect.position.x + pos.x * rect.size.x
		var py: float = rect.position.y + pos.y * rect.size.y

		# Aro de posesión (suave) bajo el jugador del equipo en posesión
		if has_possession:
			panel.draw_circle(Vector2(px, py), 12.0, Color(1.0, 1.0, 0.4, 0.18))

		# Camera A2 light: anillo destacado para el protagonista del usuario
		var pid: String = lineup.starting_eleven[i].id
		var is_protagonist: bool = (lineup.protagonist_id != "" and pid == lineup.protagonist_id)
		if is_protagonist:
			# Aro exterior pulsante (oscilación con el reloj)
			var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 250.0)
			var ring_alpha: float = 0.55 + pulse * 0.30
			panel.draw_arc(Vector2(px, py), 14.0, 0, TAU, 32, Color(1.0, 0.85, 0.2, ring_alpha), 2.5)

		# Efecto T_TACKLE_FAIL: jugador "tirado" — círculo aplastado + spark
		var is_fallen: bool = (fallen_player_id != "" and pid == fallen_player_id)
		# Efecto T_TACTICAL_FOUL: shake horizontal del que comete falta
		var shake_off: Vector2 = Vector2.ZERO
		if foul_shake_player_id != "" and pid == foul_shake_player_id:
			var t_shake: float = float(Time.get_ticks_msec()) / 30.0
			shake_off = Vector2(sin(t_shake) * 2.5, 0)

		var draw_pos: Vector2 = Vector2(px, py) + shake_off
		if is_fallen:
			# Elipse aplastada (jugador tirado en el suelo)
			panel.draw_circle(draw_pos, 9.0, color)  # base
			panel.draw_arc(draw_pos, 14.0, 0, TAU, 16, Color(1.0, 0.5, 0.5, 0.7), 1.8)
			# X encima para indicar caída
			panel.draw_line(draw_pos + Vector2(-5, -5), draw_pos + Vector2(5, 5), Color(1, 0.4, 0.4), 1.5)
			panel.draw_line(draw_pos + Vector2(5, -5), draw_pos + Vector2(-5, 5), Color(1, 0.4, 0.4), 1.5)
		else:
			panel.draw_circle(draw_pos, 9.0, color)
			panel.draw_circle(draw_pos, 9.0, Color(0, 0, 0, 0.6), false, 1.5)

		# Dorsal
		var dorsal: int = lineup.starting_eleven[i].shirt_number
		var label_size: int = 10
		panel.draw_string(ThemeDB.fallback_font, draw_pos + Vector2(-6, 4), str(dorsal),
			HORIZONTAL_ALIGNMENT_CENTER, -1, label_size, Color(1, 1, 1))
		# Nombre del protagonista visible sobre su jugador
		if is_protagonist:
			var pname: String = lineup.starting_eleven[i].name
			panel.draw_string(ThemeDB.fallback_font, Vector2(px - 30, py - 14), pname,
				HORIZONTAL_ALIGNMENT_CENTER, 60, 9, Color(1.0, 0.85, 0.2))


func _team_color(team: Team, is_home: bool) -> Color:
	if team == null or team.colors == null:
		return Color(0.6, 0.6, 0.6) if is_home else Color(0.4, 0.4, 0.8)
	var hex: String = String(team.colors.get("primary" if is_home else "secondary", "#888888"))
	return Color.from_string(hex, Color(0.6, 0.6, 0.6))
