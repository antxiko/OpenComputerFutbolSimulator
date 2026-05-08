extends Control

# Pantalla principal del simulador — Iteración 2.
#
# Layout:
#   ┌─────────────────────────────────────────────────────┐
#   │  TITLE                  YEAR · JORNADA               │
#   ├─────────────────────────────────────────────────────┤
#   │  [Primera] [Segunda]   ← tabs de división           │
#   │  [Tabla] [Última jornada] [Plantilla]  ← tabs vista │
#   ├─────────────────────────────────────────────────────┤
#   │                                                       │
#   │            CONTENT AREA (cambia con la pestaña)      │
#   │                                                       │
#   ├─────────────────────────────────────────────────────┤
#   │  STATUS               [Siguiente] [Toda] [Nueva]      │
#   └─────────────────────────────────────────────────────┘
#
# Notas Godot:
# - Construcción programática (sin .tscn editable) por simplicidad de iteración.
# - "VIEW_*" constantes para identificar la vista activa.
# - El último set de resultados se guarda por división para click-to-view.

const SEASON_YEAR_INITIAL := 2026
const SEED_BASE := 42

const VIEW_TABLE := "table"
const VIEW_FIXTURES := "fixtures"
const VIEW_TEAM := "team"
const VIEW_MATCH := "match"
const VIEW_TACTICS := "tactics"
const VIEW_MARKET := "market"
const VIEW_CAREER := "career"
const VIEW_CHAMPIONS := "champions"


# --------------------------------------------------------------------------- #
# Estado por división
# --------------------------------------------------------------------------- #
class DivisionState:
	var division: String  # "primera" | "segunda"
	var teams: Array = []
	var calendar: Array = []  # Array[Jornada]
	var current_jornada: int = 0  # próxima a jugarse
	var league_table: LeagueTable
	var last_jornada_results: Array = []  # Array[MatchResult] de la última jugada
	var seed_counter: int = 0
	# Goleadores acumulados de la temporada en curso: player_id -> { name, team_short, goals }
	var season_scorers: Dictionary = {}


# --------------------------------------------------------------------------- #
# Estado del juego
# --------------------------------------------------------------------------- #
var all_teams: Array = []
var primera_state: DivisionState = DivisionState.new()
var segunda_state: DivisionState = DivisionState.new()
var year: int = SEASON_YEAR_INITIAL
var selected_division: String = "primera"
var current_view: String = VIEW_TABLE
var selected_team: Team = null
var selected_match: MatchResult = null

# "Mi club" — el equipo que dirige el usuario (si lo hay).
# Cuando se establece, el usuario puede personalizar la alineación.
var user_team_id: String = ""
# Alineación personalizada del usuario, dict con keys:
#   formation, eleven_ids (Array[String]), slot_assignments (Array[String]),
#   tactics: { mentality, tempo, pressing, width }
var user_lineup_template: Dictionary = {}
# Histórico: una entrada por temporada completada. Cada entrada:
# { year, division, position, played, won, drawn, lost, gf, ga, points,
#   top_scorer_name, top_scorer_goals, cup_progress }
var user_career_history: Array = []
# Última edición de Champions League simulada (no se persiste en save).
var champions_state: ChampionsBracket = null

# UI refs (populadas en _build_ui)
var year_label: Label
var jornada_label: Label
var status_label: Label
var primera_div_button: Button
var segunda_div_button: Button
var view_table_button: Button
var view_fixtures_button: Button
var view_team_button: Button
var view_tactics_button: Button
var view_market_button: Button
var market_filter_position: String = "ALL"  # filtro actual de posición en mercado
var user_team_label: Label
var content_area: VBoxContainer
var advance_button: Button
var advance_all_button: Button
var reset_button: Button
var save_button: Button
var load_button: Button


func _ready() -> void:
	primera_state.division = "primera"
	segunda_state.division = "segunda"
	_build_ui()
	_load_data()
	# Aplicar configuración de GameSession (si venimos del menú principal)
	if GameSession.start_mode == "new_game":
		user_team_id = GameSession.pending_user_team_id
		_initialize_user_lineup()
		GameSession.consume()
		_start_season()
		_show_welcome_message()
	elif GameSession.start_mode == "load":
		var slot: String = GameSession.pending_load_slot
		if slot.is_empty():
			slot = "autosave"
		GameSession.consume()
		_start_season()
		_load_from_slot(slot)
	else:
		# Modo default: arrancar nueva temporada sin equipo seleccionado
		_start_season()


func _show_welcome_message() -> void:
	var team := _find_team_by_id(user_team_id)
	if team == null:
		return
	status_label.text = "¡Bienvenido como mánager de %s! Configura 'Mi alineación' antes de empezar." % team.name
	# Forzar pestaña Mi alineación de bienvenida
	current_view = VIEW_TACTICS
	_refresh_ui()


# =========================================================================== #
# UI: construcción
# =========================================================================== #
func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# --- Header ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "OpenComputerFutbolSimulator"
	title.add_theme_font_size_override("font_size", 22)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	year_label = Label.new()
	year_label.add_theme_font_size_override("font_size", 16)
	header.add_child(year_label)

	jornada_label = Label.new()
	jornada_label.add_theme_font_size_override("font_size", 16)
	header.add_child(jornada_label)

	vbox.add_child(HSeparator.new())

	# --- División tabs ---
	var div_tabs := HBoxContainer.new()
	div_tabs.add_theme_constant_override("separation", 4)
	vbox.add_child(div_tabs)

	primera_div_button = _make_tab_button("Primera", _on_select_division.bind("primera"))
	div_tabs.add_child(primera_div_button)
	segunda_div_button = _make_tab_button("Segunda", _on_select_division.bind("segunda"))
	div_tabs.add_child(segunda_div_button)

	# --- View tabs ---
	var view_tabs := HBoxContainer.new()
	view_tabs.add_theme_constant_override("separation", 4)
	vbox.add_child(view_tabs)

	view_table_button = _make_tab_button("Clasificación", _on_select_view.bind(VIEW_TABLE))
	view_tabs.add_child(view_table_button)
	view_fixtures_button = _make_tab_button("Última jornada", _on_select_view.bind(VIEW_FIXTURES))
	view_tabs.add_child(view_fixtures_button)
	view_team_button = _make_tab_button("Plantilla", _on_select_view.bind(VIEW_TEAM))
	view_tabs.add_child(view_team_button)
	view_tactics_button = _make_tab_button("Mi alineación", _on_select_view.bind(VIEW_TACTICS))
	view_tabs.add_child(view_tactics_button)
	view_market_button = _make_tab_button("Mercado", _on_select_view.bind(VIEW_MARKET))
	view_tabs.add_child(view_market_button)
	var view_career_button := _make_tab_button("📈 Carrera", _on_select_view.bind(VIEW_CAREER))
	view_career_button.name = "ViewCareerButton"
	view_tabs.add_child(view_career_button)
	var view_champions_button := _make_tab_button("🏆 Champions", _on_select_view.bind(VIEW_CHAMPIONS))
	view_champions_button.name = "ViewChampionsButton"
	view_tabs.add_child(view_champions_button)

	# Indicador de "Mi club" (solo lectura — el club se elige en Nueva partida)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_tabs.add_child(spacer2)
	user_team_label = Label.new()
	user_team_label.add_theme_font_size_override("font_size", 12)
	user_team_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	view_tabs.add_child(user_team_label)

	vbox.add_child(HSeparator.new())

	# --- Content area (cambia según la vista) ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	content_area = VBoxContainer.new()
	content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content_area)

	vbox.add_child(HSeparator.new())

	# --- Footer: status + botones ---
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	vbox.add_child(footer)

	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	footer.add_child(status_label)

	advance_button = Button.new()
	advance_button.text = "▶ Jornada"
	advance_button.tooltip_text = "Simular siguiente jornada (con modal pre-partido si juega tu equipo)"
	advance_button.pressed.connect(_on_advance_jornada)
	footer.add_child(advance_button)

	advance_all_button = Button.new()
	advance_all_button.text = "▶▶ Temporada"
	advance_all_button.tooltip_text = "Simular toda la temporada sin pausas"
	advance_all_button.pressed.connect(_on_advance_full_season)
	footer.add_child(advance_all_button)

	reset_button = Button.new()
	reset_button.text = "🔁 Nueva temp."
	reset_button.tooltip_text = "Aplicar asc/desc + aging + cantera + mercado IA, empezar nueva temporada"
	reset_button.pressed.connect(_on_reset_season)
	footer.add_child(reset_button)

	save_button = Button.new()
	save_button.text = "💾"
	save_button.tooltip_text = "Guardar partida (multi-slot)"
	save_button.pressed.connect(_on_save_game)
	footer.add_child(save_button)

	load_button = Button.new()
	load_button.text = "📂"
	load_button.tooltip_text = "Cargar partida (multi-slot)"
	load_button.pressed.connect(_on_load_game)
	footer.add_child(load_button)

	var menu_button := Button.new()
	menu_button.text = "🏠"
	menu_button.tooltip_text = "Volver al menú principal"
	menu_button.pressed.connect(_on_back_to_menu)
	footer.add_child(menu_button)


func _make_tab_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = "  %s  " % text
	b.pressed.connect(callback)
	return b


# =========================================================================== #
# Carga + temporada
# =========================================================================== #
func _load_data() -> void:
	var loaded := DataLoader.load_all_teams(year)
	if loaded.errors.size() > 0:
		status_label.text = "ERROR: %d errores cargando datos." % loaded.errors.size()
		for e in loaded.errors:
			push_error(e)
		return
	all_teams = loaded.teams.values()
	status_label.text = "Cargados %d equipos, %d jugadores." % [
		all_teams.size(), loaded.player_id_index.size()]


func _start_season() -> void:
	# Re-particionar equipos por división actual
	primera_state.teams = all_teams.filter(func(t: Team) -> bool: return t.division == "primera")
	segunda_state.teams = all_teams.filter(func(t: Team) -> bool: return t.division == "segunda")
	_init_division(primera_state, SEED_BASE)
	_init_division(segunda_state, SEED_BASE + 1)
	current_view = VIEW_TABLE
	selected_team = null
	selected_match = null
	_refresh_ui()


func _init_division(state: DivisionState, seed_offset: int) -> void:
	var ids: Array = state.teams.map(func(t: Team) -> String: return t.id)
	state.calendar = CalendarGenerator.generate(ids, SEED_BASE + seed_offset)
	state.current_jornada = 0
	state.league_table = LeagueTable.new()
	state.league_table.init_with_teams(state.teams)
	state.last_jornada_results = []
	state.season_scorers = {}
	state.seed_counter = (SEED_BASE + seed_offset) * 1000


# =========================================================================== #
# Acciones de simulación
# =========================================================================== #
func _on_advance_jornada() -> void:
	# Si el usuario tiene un partido en esta jornada, mostrar modal de pre-partido
	if user_team_id != "":
		var user_fx: Dictionary = _find_user_fixture_in_current_jornada()
		if not user_fx.is_empty():
			_show_pre_match_modal(user_fx)
			return  # esperamos a que el modal continúe
	_do_advance_jornada()


func _do_advance_jornada() -> void:
	var any_advanced := false
	if primera_state.current_jornada < primera_state.calendar.size():
		_simulate_jornada(primera_state)
		any_advanced = true
	if segunda_state.current_jornada < segunda_state.calendar.size():
		_simulate_jornada(segunda_state)
		any_advanced = true
	if not any_advanced:
		status_label.text = "Temporada completada. Pulsa 'Nueva temporada'."
		return
	# Si el usuario tuvo partido, mostrar resumen post-partido
	var user_result := _find_user_result_in_last_jornada()
	if user_result != null:
		_show_post_match_modal(user_result)
	_refresh_ui()


func _find_user_result_in_last_jornada() -> MatchResult:
	if user_team_id == "":
		return null
	for st in [primera_state, segunda_state]:
		for r: MatchResult in st.last_jornada_results:
			if r.home_team_id == user_team_id or r.away_team_id == user_team_id:
				return r
	return null


func _show_post_match_modal(r: MatchResult) -> void:
	var popup := AcceptDialog.new()
	popup.title = "Resultado de tu partido"
	popup.size = Vector2(540, 420)
	popup.ok_button_text = "Continuar"
	add_child(popup)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	popup.add_child(box)

	# Marcador
	var is_user_home: bool = r.home_team_id == user_team_id
	var user_scored: int = r.score_home if is_user_home else r.score_away
	var rival_scored: int = r.score_away if is_user_home else r.score_home
	var verdict: String = "EMPATE"
	var verdict_color: Color = Color(0.85, 0.85, 0.85)
	if user_scored > rival_scored:
		verdict = "VICTORIA"
		verdict_color = Color(0.4, 1.0, 0.5)
	elif user_scored < rival_scored:
		verdict = "DERROTA"
		verdict_color = Color(1.0, 0.5, 0.5)

	var verdict_label := Label.new()
	verdict_label.text = verdict
	verdict_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	verdict_label.add_theme_font_size_override("font_size", 22)
	verdict_label.add_theme_color_override("font_color", verdict_color)
	box.add_child(verdict_label)

	var score_label := Label.new()
	score_label.text = "%s   %d - %d   %s" % [r.home_team_name, r.score_home, r.score_away, r.away_team_name]
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 16)
	box.add_child(score_label)

	box.add_child(HSeparator.new())

	# Goleadores
	var goal_evs: Array = r.events.filter(func(e: MatchEvent) -> bool: return e.type == MatchEvent.T_GOAL)
	if goal_evs.size() > 0:
		var goals_title := Label.new()
		goals_title.text = "⚽ Goleadores:"
		goals_title.add_theme_font_size_override("font_size", 13)
		goals_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		box.add_child(goals_title)
		for ev: MatchEvent in goal_evs:
			var team_short: String = ""
			if ev.team_id == r.home_team_id:
				team_short = "[" + r.home_team_name.substr(0, 3).to_upper() + "]"
			else:
				team_short = "[" + r.away_team_name.substr(0, 3).to_upper() + "]"
			var l := Label.new()
			l.text = "  %s %s %s" % [ev.clock_str(), team_short, ev.description]
			box.add_child(l)
	else:
		var no_goals := Label.new()
		no_goals.text = "(Sin goles)"
		no_goals.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		box.add_child(no_goals)

	# MVP
	var mvp_id: String = _compute_mvp(r)
	if mvp_id != "":
		box.add_child(HSeparator.new())
		var mvp_player: Player = _find_player_globally(mvp_id)
		var mvp_team: String = ""
		# Encontrar a qué equipo pertenece
		for t: Team in all_teams:
			if t.find_player(mvp_id) != null:
				mvp_team = t.short_name
				break
		var mvp_label := Label.new()
		if mvp_player:
			mvp_label.text = "🏆 MVP del partido: %s (%s)" % [mvp_player.name, mvp_team]
		else:
			mvp_label.text = "🏆 MVP: -"
		mvp_label.add_theme_font_size_override("font_size", 13)
		mvp_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		box.add_child(mvp_label)

	# Stats compactos
	box.add_child(HSeparator.new())
	for tid in r.stats.keys():
		var s: Dictionary = r.stats[tid]
		var team_name: String = r.home_team_name if tid == r.home_team_id else r.away_team_name
		var emoji: String = "🏠" if tid == user_team_id else "⚔️"
		var stats_label := Label.new()
		stats_label.text = "%s %s: %d tiros (%d a puerta) · %d corners · %d faltas · %d 🟨 · %d 🟥" % [
			emoji,
			team_name.left(20),
			int(s.get("shots", 0)), int(s.get("shots_on_target", 0)),
			int(s.get("corners", 0)), int(s.get("fouls", 0)),
			int(s.get("yellows", 0)), int(s.get("reds", 0)),
		]
		stats_label.add_theme_font_size_override("font_size", 11)
		box.add_child(stats_label)

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()


# Calcula el MVP del partido. Heurística simple:
#   +5 puntos por gol, +3 por asistencia, +2 por parada (GK), -3 por roja, -1 por amarilla.
# Devuelve player_id del que más puntos.
func _compute_mvp(r: MatchResult) -> String:
	var scores: Dictionary = {}
	for ev: MatchEvent in r.events:
		match ev.type:
			MatchEvent.T_GOAL:
				scores[ev.player_id] = float(scores.get(ev.player_id, 0)) + 5.0
				if ev.secondary_player_id != "":
					scores[ev.secondary_player_id] = float(scores.get(ev.secondary_player_id, 0)) + 3.0
			MatchEvent.T_SAVE:
				scores[ev.player_id] = float(scores.get(ev.player_id, 0)) + 2.0
			MatchEvent.T_RED:
				scores[ev.player_id] = float(scores.get(ev.player_id, 0)) - 3.0
			MatchEvent.T_YELLOW:
				scores[ev.player_id] = float(scores.get(ev.player_id, 0)) - 1.0
	if scores.is_empty():
		return ""
	var best_id: String = ""
	var best_score: float = -100.0
	for pid in scores.keys():
		if float(scores[pid]) > best_score:
			best_score = float(scores[pid])
			best_id = String(pid)
	return best_id


func _find_player_globally(player_id: String) -> Player:
	for t: Team in all_teams:
		var p: Player = t.find_player(player_id)
		if p != null:
			return p
	return null


func _find_user_fixture_in_current_jornada() -> Dictionary:
	for st in [primera_state, segunda_state]:
		if st.current_jornada >= st.calendar.size():
			continue
		var jornada: Array = st.calendar[st.current_jornada]
		for fixture: Dictionary in jornada:
			if fixture["home_id"] == user_team_id or fixture["away_id"] == user_team_id:
				return { "fixture": fixture, "jornada_num": st.current_jornada + 1, "division": st.division }
	return {}


func _show_pre_match_modal(user_fx_data: Dictionary) -> void:
	var fixture: Dictionary = user_fx_data["fixture"]
	var is_home: bool = fixture["home_id"] == user_team_id
	var opponent_id: String = fixture["away_id"] if is_home else fixture["home_id"]
	var user_team := _find_team_by_id(user_team_id)
	var opponent := _find_team_by_id(opponent_id)
	if user_team == null or opponent == null:
		_do_advance_jornada()
		return

	var popup := ConfirmationDialog.new()
	popup.title = "Pre-partido — Jornada %d (%s)" % [user_fx_data["jornada_num"], String(user_fx_data["division"]).capitalize()]
	popup.size = Vector2(540, 320)
	popup.ok_button_text = "▶ Jugar partido"
	popup.cancel_button_text = "Configurar alineación"
	add_child(popup)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	popup.add_child(content)

	# Cabecera del partido
	var header := Label.new()
	header.text = "%s   vs   %s" % [user_team.name, opponent.name]
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(header)

	var loc := Label.new()
	loc.text = "Juegas como %s · Estadio: %s" % [
		"LOCAL" if is_home else "VISITANTE",
		(user_team.stadium.name if is_home else opponent.stadium.name) if user_team.stadium else "?",
	]
	loc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loc.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	content.add_child(loc)

	content.add_child(HSeparator.new())

	# Resumen alineación
	if user_lineup_template.is_empty():
		_initialize_user_lineup()
	var l_form := Label.new()
	l_form.text = "Tu formación: %s" % user_lineup_template.get("formation", "4-3-3")
	content.add_child(l_form)
	var tactics: Dictionary = user_lineup_template.get("tactics", {})
	var l_tact := Label.new()
	l_tact.text = "Mentalidad: %s · Pressing: %s · Tempo: %s · Anchura: %s" % [
		tactics.get("mentality", "equilibrado"),
		tactics.get("pressing", "medio"),
		tactics.get("tempo", "normal"),
		tactics.get("width", "normal"),
	]
	l_tact.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	content.add_child(l_tact)

	# Once inicial (compactado)
	var eleven_ids: Array = user_lineup_template.get("eleven_ids", [])
	var slot_assignments: Array = user_lineup_template.get("slot_assignments", [])
	var lineup_text: Array[String] = []
	for i in eleven_ids.size():
		var p: Player = user_team.find_player(String(eleven_ids[i]))
		var slot: String = String(slot_assignments[i]) if i < slot_assignments.size() else "?"
		var name: String = p.name if p else "?"
		lineup_text.append("%s:%s" % [slot, name.split(" ")[-1]])  # solo apellido para que quepa
	var l_eleven := Label.new()
	l_eleven.text = "Once: " + ", ".join(lineup_text)
	l_eleven.autowrap_mode = TextServer.AUTOWRAP_WORD
	l_eleven.add_theme_font_size_override("font_size", 11)
	content.add_child(l_eleven)

	popup.confirmed.connect(func() -> void:
		popup.queue_free()
		_do_advance_jornada()
	)
	popup.canceled.connect(func() -> void:
		popup.queue_free()
		# Llevar al usuario a la pestaña de alineación para que ajuste
		current_view = VIEW_TACTICS
		_refresh_ui()
	)
	popup.popup_centered()


func _on_advance_full_season() -> void:
	_set_buttons_disabled(true)
	while primera_state.current_jornada < primera_state.calendar.size() \
			or segunda_state.current_jornada < segunda_state.calendar.size():
		if primera_state.current_jornada < primera_state.calendar.size():
			_simulate_jornada(primera_state)
		if segunda_state.current_jornada < segunda_state.calendar.size():
			_simulate_jornada(segunda_state)
		# Yield a la UI cada 3 jornadas para refrescar progreso
		if primera_state.current_jornada % 3 == 0:
			_refresh_ui()
			await get_tree().process_frame
	_refresh_ui()
	_set_buttons_disabled(false)


func _on_reset_season() -> void:
	# Antes de avanzar: si hay datos de liga, simular Copa y capturar histórico del usuario
	var cup_bracket: CupBracket = null
	var sc_qualifiers: Array = []
	if primera_state.league_table != null and segunda_state.league_table != null:
		cup_bracket = CupSimulator.run(all_teams, year, SEED_BASE + year * 7)
		if user_team_id != "":
			_capture_career_record(cup_bracket)
		# Capturar clasificados a Supercopa: top 2 Liga + finalistas Copa
		var liga_sorted: Array = primera_state.league_table.sorted_rows()
		if liga_sorted.size() >= 1:
			sc_qualifiers.append(_find_team_by_id(liga_sorted[0].team_id))
		if liga_sorted.size() >= 2:
			sc_qualifiers.append(_find_team_by_id(liga_sorted[1].team_id))
		if cup_bracket and cup_bracket.champion_id != "":
			sc_qualifiers.append(_find_team_by_id(cup_bracket.champion_id))
		# Finalista de Copa = el perdedor de la final
		if cup_bracket and cup_bracket.rounds.size() > 0:
			var final_round: CupBracket.Round = cup_bracket.rounds[-1]
			if final_round.fixtures.size() == 1:
				var ffx: CupBracket.Fixture = final_round.fixtures[0]
				var loser_id: String = ffx.away_id if ffx.winner_id == ffx.home_id else ffx.home_id
				sc_qualifiers.append(_find_team_by_id(loser_id))
		# Reputación dinámica con la temporada que acaba de terminar
		ReputationUpdate.apply_after_season(primera_state.league_table, segunda_state.league_table, all_teams)
		PromotionRelegation.apply(primera_state.league_table, segunda_state.league_table, all_teams)
	year += 1
	# Aging + retiros + canteranos
	Aging.age_all(all_teams, year, SEED_BASE * 100)
	for t: Team in all_teams:
		Cantera.fill_squad_if_needed(t, year, SEED_BASE * 50)
	# Update aggression según tarjetas de la temporada que acaba
	AggressionSystem.update_after_season(all_teams)
	# Reset de amarillas/rojas para la nueva temporada (mantiene sanciones)
	CardSystem.reset_yellow_cards(all_teams)
	# Mercado de fichajes
	TransferMarket.run(all_teams, year, SEED_BASE * 7)
	# Champions League: top 4 españoles del año que acaba (basado en p_table snapshot
	# previo) vs 12 europeos generados procedurally.
	if primera_state.league_table != null:
		var top4_rows: Array = primera_state.league_table.sorted_rows().slice(0, 4)
		var top4_teams: Array = []
		for r: LeagueTable.TeamRow in top4_rows:
			var t: Team = _find_team_by_id(r.team_id)
			if t != null:
				top4_teams.append(t)
		if top4_teams.size() == 4:
			var euros: Array = EuropeanTeams.generate_all(year, SEED_BASE + year * 13)
			champions_state = ChampionsSimulator.run(top4_teams, euros, year, SEED_BASE * 17 + year)
			if champions_state != null and champions_state.champion_name != "":
				var qualified_user: bool = false
				for tt: Team in top4_teams:
					if tt.id == user_team_id:
						qualified_user = true
						break
				if qualified_user:
					_show_champions_modal(champions_state)
				else:
					status_label.text = "🏆 Champions %d: %s campeón (final vs %s)" % [year, champions_state.champion_name, champions_state.runner_up_name]
	# Supercopa de España (con clasificados de la temporada que acaba de terminar)
	if sc_qualifiers.size() >= 4:
		var fallback: Team = null
		var liga_sorted2: Array = primera_state.league_table.sorted_rows() if primera_state.league_table else []
		if liga_sorted2.size() >= 3:
			fallback = _find_team_by_id(liga_sorted2[2].team_id)
		var sc_result: SupercopaSimulator.SupercopaResult = SupercopaSimulator.run(sc_qualifiers, fallback, year, SEED_BASE * 11)
		if sc_result != null and user_team_id != "" and sc_result.has_team(user_team_id):
			_show_supercopa_modal(sc_result)
		elif sc_result != null:
			status_label.text = "🏆 Supercopa %d: %s campeón (final vs %s)" % [year, sc_result.champion_name, sc_result.runner_up_name]
	_start_season()


func _show_supercopa_modal(sc: SupercopaSimulator.SupercopaResult) -> void:
	var popup := AcceptDialog.new()
	popup.title = "🏆 Supercopa de España %d" % sc.year
	popup.size = Vector2(520, 360)
	popup.ok_button_text = "Continuar"
	add_child(popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	popup.add_child(box)

	var champ_label := Label.new()
	champ_label.text = "Campeón: %s" % sc.champion_name
	champ_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	champ_label.add_theme_font_size_override("font_size", 18)
	champ_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	box.add_child(champ_label)

	var sub_label := Label.new()
	sub_label.text = "Subcampeón: %s" % sc.runner_up_name
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	box.add_child(sub_label)

	box.add_child(HSeparator.new())

	for m: Dictionary in sc.matches:
		var r: MatchResult = m.get("result")
		var round_name: String = String(m.get("round", "Partido"))
		var l := Label.new()
		var marker: String = ""
		if m.get("home_id") == user_team_id or m.get("away_id") == user_team_id:
			marker = " 🌟"
		l.text = "%s%s: %s %d-%d %s" % [
			round_name, marker,
			String(m.get("home_name", "?")),
			r.score_home if r else 0,
			r.score_away if r else 0,
			String(m.get("away_name", "?")),
		]
		box.add_child(l)

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()


# Captura un snapshot del rendimiento del usuario en la temporada que acaba de terminar.
func _capture_career_record(cup_bracket: CupBracket) -> void:
	var user_team := _find_team_by_id(user_team_id)
	if user_team == null:
		return
	# Estado de liga del usuario (busca en su división)
	var state: DivisionState = primera_state if user_team.division == "primera" else segunda_state
	var sorted: Array = state.league_table.sorted_rows()
	var record: Dictionary = {
		"year": year,
		"division": user_team.division,
		"position": 0,
		"played": 0, "won": 0, "drawn": 0, "lost": 0,
		"gf": 0, "ga": 0, "points": 0,
		"top_scorer_name": "—",
		"top_scorer_goals": 0,
		"cup_progress": "—",
	}
	for i in sorted.size():
		if sorted[i].team_id == user_team_id:
			record["position"] = i + 1
			record["played"] = sorted[i].played
			record["won"] = sorted[i].won
			record["drawn"] = sorted[i].drawn
			record["lost"] = sorted[i].lost
			record["gf"] = sorted[i].goals_for
			record["ga"] = sorted[i].goals_against
			record["points"] = sorted[i].points()
			break
	# Pichichi del usuario: top scorer del equipo
	var team_scorers: Array = []
	for pid in state.season_scorers.keys():
		var info: Dictionary = state.season_scorers[pid]
		if user_team.find_player(pid) != null:
			team_scorers.append(info)
	team_scorers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["goals"]) > int(b["goals"]))
	if team_scorers.size() > 0:
		record["top_scorer_name"] = String(team_scorers[0]["name"])
		record["top_scorer_goals"] = int(team_scorers[0]["goals"])
	# Progreso en Copa
	if cup_bracket != null:
		record["cup_progress"] = _compute_user_cup_progress(cup_bracket)
	user_career_history.append(record)


func _compute_user_cup_progress(bracket: CupBracket) -> String:
	if bracket.champion_id == user_team_id:
		return "🏆 Campeón"
	# Buscar la última ronda donde el usuario perdió
	var furthest_round: String = "Eliminado en 1ª"
	for round_obj: CupBracket.Round in bracket.rounds:
		# ¿bye?
		if user_team_id in round_obj.byes:
			furthest_round = "Bye en %s" % round_obj.name
			continue
		for fx: CupBracket.Fixture in round_obj.fixtures:
			if fx.home_id == user_team_id or fx.away_id == user_team_id:
				if fx.winner_id == user_team_id:
					furthest_round = "Pasó %s" % round_obj.name
				else:
					furthest_round = "Eliminado en %s" % round_obj.name
				break
	return furthest_round


# =========================================================================== #
# Vista: Champions League
# =========================================================================== #
func _render_champions_view() -> void:
	if champions_state == null:
		var l := Label.new()
		l.text = "Aún no hay edición de Champions League activa.\nFinaliza una temporada (botón \"🔁 Nueva temp.\") para que se simule la siguiente edición."
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content_area.add_child(l)
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_area.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Título + campeón
	var title := Label.new()
	title.text = "🏆 Champions League %d-%d" % [champions_state.season_year, champions_state.season_year + 1]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(title)

	if champions_state.champion_name != "":
		var champ := Label.new()
		champ.text = "Campeón: %s   ·   Subcampeón: %s" % [
			champions_state.champion_name, champions_state.runner_up_name]
		champ.add_theme_color_override("font_color", Color(0.8, 1.0, 0.6))
		vbox.add_child(champ)

	# Fase de grupos
	var groups_label := Label.new()
	groups_label.text = "── Fase de grupos ──"
	groups_label.add_theme_font_size_override("font_size", 14)
	groups_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox.add_child(groups_label)

	var groups_grid := GridContainer.new()
	groups_grid.columns = 2
	groups_grid.add_theme_constant_override("h_separation", 24)
	groups_grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(groups_grid)

	for g: ChampionsBracket.Group in champions_state.groups:
		var gbox := VBoxContainer.new()
		var gh := Label.new()
		gh.text = "Grupo %s" % g.letter
		gh.add_theme_font_size_override("font_size", 13)
		gh.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
		gbox.add_child(gh)
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 8)
		# header
		for h_text in ["Pos", "Equipo", "PJ", "Pts", "GF", "GC"]:
			var hl := Label.new()
			hl.text = h_text
			hl.add_theme_font_size_override("font_size", 11)
			hl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
			grid.add_child(hl)
		var standings: Array = g.sorted_standings()
		for i in standings.size():
			var st: ChampionsBracket.GroupStanding = standings[i]
			var color: Color = Color(1, 1, 1)
			if i < 2:
				color = Color(0.7, 1.0, 0.7)  # clasificados
			else:
				color = Color(0.85, 0.85, 0.85)
			grid.add_child(_make_label("%d" % (i + 1), 11, color))
			grid.add_child(_make_label(st.team_name, 11, color))
			grid.add_child(_make_label("%d" % st.played, 11, color))
			grid.add_child(_make_label("%d" % st.points(), 11, color))
			grid.add_child(_make_label("%d" % st.goals_for, 11, color))
			grid.add_child(_make_label("%d" % st.goals_against, 11, color))
		gbox.add_child(grid)
		groups_grid.add_child(gbox)

	# Eliminatorias
	var ko_label := Label.new()
	ko_label.text = "── Eliminatorias ──"
	ko_label.add_theme_font_size_override("font_size", 14)
	ko_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox.add_child(ko_label)

	for r: ChampionsBracket.KORound in champions_state.ko_rounds:
		var rh := Label.new()
		rh.text = r.name
		rh.add_theme_font_size_override("font_size", 13)
		rh.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
		vbox.add_child(rh)
		for fx: ChampionsBracket.KOFixture in r.fixtures:
			var line := Label.new()
			var score: String = "?-?"
			if fx.result != null:
				score = "%d-%d" % [fx.result.score_home, fx.result.score_away]
			var rep: String = "  (rep)" if fx.won_by_reputation else ""
			var winner_short: String = ""
			if fx.winner_id == fx.home_id:
				winner_short = " → " + fx.home_name
			elif fx.winner_id == fx.away_id:
				winner_short = " → " + fx.away_name
			line.text = "  %s %s %s%s%s" % [fx.home_name, score, fx.away_name, winner_short, rep]
			line.add_theme_font_size_override("font_size", 11)
			vbox.add_child(line)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


# Modal "Has jugado la Champions" cuando el equipo del usuario clasificó.
func _show_champions_modal(bracket: ChampionsBracket) -> void:
	var popup := AcceptDialog.new()
	popup.title = "🏆 Champions League %d" % bracket.season_year
	popup.size = Vector2(560, 380)
	popup.ok_button_text = "Continuar"
	add_child(popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	popup.add_child(box)

	# Resultado del usuario en la competición
	var user_path: String = _user_champions_path(bracket)
	var path_label := Label.new()
	path_label.text = "Tu trayectoria: %s" % user_path
	path_label.add_theme_font_size_override("font_size", 14)
	path_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
	box.add_child(path_label)

	box.add_child(HSeparator.new())

	if bracket.champion_name != "":
		var champ := Label.new()
		champ.text = "Campeón: %s" % bracket.champion_name
		champ.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		champ.add_theme_font_size_override("font_size", 16)
		champ.add_theme_color_override("font_color", Color(0.7, 1.0, 0.6))
		box.add_child(champ)
		var sub := Label.new()
		sub.text = "Subcampeón: %s" % bracket.runner_up_name
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		box.add_child(sub)

	var hint := Label.new()
	hint.text = "Pulsa la pestaña 🏆 Champions para ver el bracket completo."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(hint)

	popup.popup_centered()
	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())


func _user_champions_path(bracket: ChampionsBracket) -> String:
	if bracket.champion_id == user_team_id:
		return "🏆 CAMPEÓN"
	if bracket.runner_up_name != "":
		# Buscar si fuiste subcampeón
		for r: ChampionsBracket.KORound in bracket.ko_rounds:
			if r.name == "Final":
				for fx: ChampionsBracket.KOFixture in r.fixtures:
					if (fx.home_id == user_team_id or fx.away_id == user_team_id) and fx.winner_id != user_team_id:
						return "Subcampeón (perdió la Final)"
	# Buscar la última ronda donde el usuario perdió
	var last_status: String = "Eliminado en Fase de grupos"
	for r: ChampionsBracket.KORound in bracket.ko_rounds:
		for fx: ChampionsBracket.KOFixture in r.fixtures:
			if fx.home_id == user_team_id or fx.away_id == user_team_id:
				if fx.winner_id == user_team_id:
					last_status = "Pasó %s" % r.name
				else:
					last_status = "Eliminado en %s" % r.name
	# Si no aparece en KO, ver si pasó de grupos
	for g: ChampionsBracket.Group in bracket.groups:
		if user_team_id in g.team_ids:
			var sorted: Array = g.sorted_standings()
			for i in sorted.size():
				if sorted[i].team_id == user_team_id:
					if i >= 2:
						return "Eliminado en Fase de grupos (%dº del grupo %s)" % [i + 1, g.letter]
					break
	return last_status


# =========================================================================== #
# Vista: Mi carrera (histórico)
# =========================================================================== #
func _render_career_view() -> void:
	if user_team_id == "":
		var l := Label.new()
		l.text = "Sin club seleccionado."
		content_area.add_child(l)
		return
	var user_team := _find_team_by_id(user_team_id)

	var header := Label.new()
	header.text = "📈 Carrera como mánager de %s" % user_team.name
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	content_area.add_child(header)

	if user_career_history.is_empty():
		var no_data := Label.new()
		no_data.text = "Aún no has completado ninguna temporada. Pulsa 'Nueva temp.' al final."
		content_area.add_child(no_data)
		return

	# Stats agregados
	var total_titles: int = 0
	var total_cup: int = 0
	var best_pos: int = 999
	var best_pos_year: int = 0
	var total_points: int = 0
	var total_played: int = 0
	var total_won: int = 0
	var total_drawn: int = 0
	var total_lost: int = 0
	var total_gf: int = 0
	var total_ga: int = 0
	for r: Dictionary in user_career_history:
		var pos: int = int(r["position"])
		if pos == 1 and r["division"] == "primera":
			total_titles += 1
		if String(r.get("cup_progress", "")).contains("Campeón"):
			total_cup += 1
		if pos > 0 and pos < best_pos:
			best_pos = pos
			best_pos_year = int(r["year"])
		total_points += int(r["points"])
		total_played += int(r["played"])
		total_won += int(r["won"])
		total_drawn += int(r["drawn"])
		total_lost += int(r["lost"])
		total_gf += int(r["gf"])
		total_ga += int(r["ga"])

	var stats := Label.new()
	stats.text = "Temporadas: %d  ·  🏆 Ligas: %d  ·  Copas: %d  ·  Mejor posición: #%d (%d-%d)" % [
		user_career_history.size(), total_titles, total_cup,
		best_pos if best_pos != 999 else 0,
		best_pos_year, best_pos_year + 1,
	]
	content_area.add_child(stats)
	var stats2 := Label.new()
	stats2.text = "Total: %d PJ · %d G · %d E · %d P · GF %d · GC %d · DG %+d" % [
		total_played, total_won, total_drawn, total_lost,
		total_gf, total_ga, total_gf - total_ga,
	]
	stats2.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	content_area.add_child(stats2)

	content_area.add_child(HSeparator.new())

	# Tabla por temporada
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 3)
	content_area.add_child(grid)
	for h in ["Año", "Div", "Pos", "PJ-G-E-P", "GF/GC", "Pts", "Pichichi", "Copa"]:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		l.add_theme_font_size_override("font_size", 12)
		grid.add_child(l)
	# Ordenar por año descendente
	var sorted_history: Array = user_career_history.duplicate()
	sorted_history.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["year"]) > int(b["year"]))
	for r: Dictionary in sorted_history:
		var pos: int = int(r["position"])
		var color: Color = Color(0.85, 0.85, 0.85)
		if pos == 1 and r["division"] == "primera":
			color = Color(1.0, 0.85, 0.2)  # oro: campeón
		elif pos <= 4 and r["division"] == "primera":
			color = Color(0.6, 1.0, 0.7)  # verde: top 4
		elif pos <= 6 and r["division"] == "primera":
			color = Color(0.6, 0.8, 1.0)
		var cells: Array[String] = [
			"%d-%d" % [int(r["year"]), int(r["year"]) + 1 - 2000],
			"1ª" if r["division"] == "primera" else "2ª",
			"#%d" % pos,
			"%d-%d-%d-%d" % [int(r["played"]), int(r["won"]), int(r["drawn"]), int(r["lost"])],
			"%d/%d" % [int(r["gf"]), int(r["ga"])],
			str(int(r["points"])),
			"%s (%d)" % [String(r["top_scorer_name"]).left(20), int(r["top_scorer_goals"])],
			String(r["cup_progress"]),
		]
		for c in cells:
			var l := Label.new()
			l.text = c
			l.add_theme_color_override("font_color", color)
			l.add_theme_font_size_override("font_size", 11)
			grid.add_child(l)


func _simulate_jornada(state: DivisionState) -> void:
	# Curar lesiones (7 días entre jornadas) antes de empezar
	InjurySystem.heal_after_days(all_teams, 7)
	var jornada: Array = state.calendar[state.current_jornada]
	var team_index: Dictionary = {}
	for t: Team in state.teams:
		team_index[t.id] = t
		# Restablecer condición antes de la jornada
		for p: Player in t.players:
			p.condition = 100.0

	state.last_jornada_results = []
	for fixture: Dictionary in jornada:
		var home: Team = team_index[fixture["home_id"]]
		var away: Team = team_index[fixture["away_id"]]
		# Decrementar sanciones (los suspendidos cumplen ESTE partido)
		CardSystem.decrement_for_team(home)
		CardSystem.decrement_for_team(away)
		# Si el usuario dirige uno de los equipos, usar su alineación personalizada
		var home_lineup: Lineup = null
		var away_lineup: Lineup = null
		if home.id == user_team_id:
			home_lineup = _build_user_lineup(home)
		if away.id == user_team_id:
			away_lineup = _build_user_lineup(away)
		# Fallback a AutoLineup
		if home_lineup == null:
			home_lineup = AutoLineup.pick(home, home.tactics_default.formation)
		if away_lineup == null:
			away_lineup = AutoLineup.pick(away, away.tactics_default.formation)
		state.seed_counter += 1
		var result: MatchResult = MatchEngine.simulate(home_lineup, away_lineup, state.seed_counter)
		if result != null:
			state.league_table.record_match(result)
			state.last_jornada_results.append(result)
			# Procesar tarjetas → posibles sanciones para el próximo partido
			CardSystem.process_match(result, all_teams)
			# Acumular goleadores de la temporada
			for pid in result.scorers.keys():
				var goals: int = int(result.scorers[pid])
				if not state.season_scorers.has(pid):
					var p: Player = _find_player_globally(pid)
					var team_short: String = ""
					for t: Team in state.teams:
						if t.find_player(pid) != null:
							team_short = t.short_name
							break
					state.season_scorers[pid] = {
						"name": p.name if p else pid,
						"team_short": team_short,
						"goals": 0,
					}
				state.season_scorers[pid]["goals"] += goals
	state.current_jornada += 1


func _set_buttons_disabled(d: bool) -> void:
	advance_button.disabled = d
	advance_all_button.disabled = d
	reset_button.disabled = d
	save_button.disabled = d
	load_button.disabled = d


# =========================================================================== #
# Save / Load
# =========================================================================== #
func _on_save_game() -> void:
	var dialog := SaveLoadDialog.new()
	add_child(dialog)
	dialog.open_save(func(slot: String, action: String) -> void:
		dialog.queue_free()
		if action != "save":
			return
		_save_to_slot(slot)
	)


func _save_to_slot(slot: String) -> void:
	var result: Dictionary = SaveSystem.save_game(
		slot, year, all_teams,
		primera_state.current_jornada, segunda_state.current_jornada,
		primera_state.league_table, segunda_state.league_table,
		user_team_id, user_lineup_template, user_career_history)
	if result.get("ok", false):
		status_label.text = "Partida guardada en '%s' — %s" % [slot, result["saved_at"]]
	else:
		status_label.text = "ERROR al guardar: %s" % result.get("error", "?")


func _on_load_game() -> void:
	var dialog := SaveLoadDialog.new()
	add_child(dialog)
	dialog.open_load(func(slot: String, action: String) -> void:
		dialog.queue_free()
		if action != "load":
			return
		_load_from_slot(slot)
	)


func _load_from_slot(slot: String) -> void:
	var save_data: SaveSystem.SaveData = SaveSystem.load_game(slot)
	if save_data == null:
		status_label.text = "No se pudo cargar el slot '%s'." % slot
		return

	# Reemplazar estado del juego con los datos cargados
	all_teams = save_data.teams
	year = save_data.year
	primera_state.teams = all_teams.filter(func(t: Team) -> bool: return t.division == "primera")
	segunda_state.teams = all_teams.filter(func(t: Team) -> bool: return t.division == "segunda")
	# Regenerar calendarios desde el seed (deterministas)
	var primera_ids: Array = primera_state.teams.map(func(t: Team) -> String: return t.id)
	var segunda_ids: Array = segunda_state.teams.map(func(t: Team) -> String: return t.id)
	primera_state.calendar = CalendarGenerator.generate(primera_ids, SEED_BASE)
	segunda_state.calendar = CalendarGenerator.generate(segunda_ids, SEED_BASE + 1)
	primera_state.current_jornada = save_data.primera_jornada
	segunda_state.current_jornada = save_data.segunda_jornada
	primera_state.league_table = SaveSystem.restore_table(save_data.primera_table_snapshot, primera_state.teams)
	segunda_state.league_table = SaveSystem.restore_table(save_data.segunda_table_snapshot, segunda_state.teams)
	primera_state.last_jornada_results = []
	segunda_state.last_jornada_results = []
	primera_state.seed_counter = SEED_BASE * 1000 + primera_state.current_jornada * 100
	segunda_state.seed_counter = (SEED_BASE + 1) * 1000 + segunda_state.current_jornada * 100

	# Restaurar selección de "mi club" + alineación personal + carrera
	user_team_id = save_data.user_team_id
	user_lineup_template = save_data.user_lineup_template.duplicate(true)
	user_career_history = save_data.user_career_history.duplicate(true)

	current_view = VIEW_TABLE
	selected_team = null
	selected_match = null
	status_label.text = "Partida cargada — %s, jornada %d" % [save_data.saved_at, save_data.primera_jornada]
	_refresh_ui()


# =========================================================================== #
# Navegación
# =========================================================================== #
func _on_select_division(div: String) -> void:
	selected_division = div
	# Si estábamos en una vista contextual a un equipo/partido, volvemos a la tabla
	if current_view in [VIEW_TEAM, VIEW_MATCH]:
		current_view = VIEW_TABLE
	_refresh_ui()


func _on_select_view(view: String) -> void:
	current_view = view
	if view == VIEW_TEAM and selected_team == null:
		# Por defecto el primero de la división
		var st := _current_state()
		if st.teams.size() > 0:
			selected_team = st.teams[0]
	_refresh_ui()


func _current_state() -> DivisionState:
	return primera_state if selected_division == "primera" else segunda_state


# =========================================================================== #
# Refresco
# =========================================================================== #
func _refresh_ui() -> void:
	year_label.text = "Temporada %d-%d" % [year, year + 1]
	var st := _current_state()
	jornada_label.text = "Jornada %d / %d (%s)" % [
		st.current_jornada, st.calendar.size(), selected_division.capitalize()]

	primera_div_button.disabled = (selected_division == "primera")
	segunda_div_button.disabled = (selected_division == "segunda")
	view_table_button.disabled = (current_view == VIEW_TABLE)
	view_fixtures_button.disabled = (current_view == VIEW_FIXTURES)
	view_team_button.disabled = (current_view == VIEW_TEAM)
	view_tactics_button.disabled = (current_view == VIEW_TACTICS)
	view_tactics_button.visible = user_team_id != ""
	view_market_button.disabled = (current_view == VIEW_MARKET)
	view_market_button.visible = user_team_id != ""
	# Career button (find by name)
	var career_btn: Button = find_child("ViewCareerButton", true, false)
	if career_btn:
		career_btn.disabled = (current_view == VIEW_CAREER)
		career_btn.visible = user_team_id != ""

	# User team label (short_name para que quepa)
	if user_team_id != "":
		var ut := _find_team_by_id(user_team_id)
		user_team_label.text = "🌟 %s" % (ut.short_name if ut else user_team_id)
	else:
		user_team_label.text = ""

	# Limpiar contenido
	for c in content_area.get_children():
		c.queue_free()

	match current_view:
		VIEW_TABLE: _render_table_view()
		VIEW_FIXTURES: _render_fixtures_view()
		VIEW_TEAM: _render_team_view()
		VIEW_MATCH: _render_match_view()
		VIEW_TACTICS: _render_tactics_view()
		VIEW_MARKET: _render_market_view()
		VIEW_CAREER: _render_career_view()
		VIEW_CHAMPIONS: _render_champions_view()


# --------------------------------------------------------------------------- #
# Vista: Clasificación
# --------------------------------------------------------------------------- #
func _render_table_view() -> void:
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	content_area.add_child(grid)

	var headers: Array[String] = ["Pos", "Equipo", "PJ", "G", "E", "P", "GF", "GC", "DG", "Pts"]
	for i in headers.size():
		var l := Label.new()
		l.text = headers[i]
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		l.add_theme_font_size_override("font_size", 12)
		# Header de Equipo alineado izquierda; resto centrado/derecha
		if i == 0 or i >= 2:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.custom_minimum_size = Vector2(28, 0)
		grid.add_child(l)

	var st := _current_state()
	if st.league_table == null:
		return
	var sorted: Array = st.league_table.sorted_rows()
	var pos: int = 1
	var n_teams := sorted.size()
	for row: LeagueTable.TeamRow in sorted:
		_add_table_row(grid, pos, row, n_teams)
		pos += 1


func _add_table_row(grid: GridContainer, pos: int, row: LeagueTable.TeamRow, n_teams: int) -> void:
	var color: Color = Color(1, 1, 1)
	if pos <= 4:
		color = Color(0.6, 1.0, 0.7)
	elif pos <= 6:
		color = Color(0.6, 0.8, 1.0)
	elif pos > n_teams - 3:
		color = Color(1.0, 0.65, 0.65)

	# Ajustamos el ancho del botón de equipo para que el resto de columnas quepan
	var team_button := Button.new()
	team_button.text = row.team_name
	team_button.flat = true
	team_button.add_theme_color_override("font_color", color)
	team_button.add_theme_font_size_override("font_size", 12)
	team_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	team_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_button.custom_minimum_size = Vector2(220, 0)  # ancho fijo: nombre cabe pero no domina
	team_button.clip_text = true
	team_button.pressed.connect(_on_team_clicked.bind(row.team_id))

	var cells_post: Array[String] = [
		str(row.played), str(row.won), str(row.drawn), str(row.lost),
		str(row.goals_for), str(row.goals_against),
		"%+d" % row.goal_diff(), str(row.points()),
	]
	# Pos
	var l_pos := Label.new()
	l_pos.text = str(pos)
	l_pos.add_theme_color_override("font_color", color)
	l_pos.add_theme_font_size_override("font_size", 12)
	l_pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l_pos.custom_minimum_size = Vector2(28, 0)
	grid.add_child(l_pos)
	# Equipo (botón clickable)
	grid.add_child(team_button)
	# Resto (compacto, ancho fijo)
	for c in cells_post:
		var l := Label.new()
		l.text = c
		l.add_theme_color_override("font_color", color)
		l.add_theme_font_size_override("font_size", 12)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.custom_minimum_size = Vector2(32, 0)
		grid.add_child(l)


func _on_team_clicked(team_id: String) -> void:
	var st := _current_state()
	for t: Team in st.teams:
		if t.id == team_id:
			selected_team = t
			current_view = VIEW_TEAM
			_refresh_ui()
			return


# --------------------------------------------------------------------------- #
# Vista: Última jornada (fixtures con resultados)
# --------------------------------------------------------------------------- #
func _render_fixtures_view() -> void:
	var st := _current_state()
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 16)
	if st.last_jornada_results.is_empty():
		title.text = "No hay resultados todavía. Pulsa 'Siguiente jornada'."
		content_area.add_child(title)
		return
	title.text = "Resultados de la jornada %d" % st.current_jornada
	content_area.add_child(title)
	content_area.add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "(Pulsa cualquier partido para ver eventos y abrir el visor 2D)"
	hint.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	hint.add_theme_font_size_override("font_size", 12)
	content_area.add_child(hint)
	content_area.add_child(HSeparator.new())

	for r: MatchResult in st.last_jornada_results:
		var btn := Button.new()
		btn.flat = false  # con borde para que se vea claro que es clickable
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.text = "  %-30s   %d   -   %d   %s   →" % [
			r.home_team_name.left(30),
			r.score_home, r.score_away,
			r.away_team_name,
		]
		btn.pressed.connect(_on_match_clicked.bind(r))
		content_area.add_child(btn)


func _on_match_clicked(result: MatchResult) -> void:
	selected_match = result
	current_view = VIEW_MATCH
	_refresh_ui()


# --------------------------------------------------------------------------- #
# Vista: Detalle de partido
# --------------------------------------------------------------------------- #
func _render_match_view() -> void:
	if selected_match == null:
		var l := Label.new()
		l.text = "No hay partido seleccionado."
		content_area.add_child(l)
		return
	var r: MatchResult = selected_match

	# Botones de acción ARRIBA (siempre visibles sin scroll)
	var top_btns := HBoxContainer.new()
	top_btns.add_theme_constant_override("separation", 8)
	content_area.add_child(top_btns)
	var back_btn_top := Button.new()
	back_btn_top.text = "← Volver a resultados"
	back_btn_top.pressed.connect(_on_select_view.bind(VIEW_FIXTURES))
	top_btns.add_child(back_btn_top)
	var view2d_btn_top := Button.new()
	view2d_btn_top.text = "▶ Ver partido en 2D"
	view2d_btn_top.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	view2d_btn_top.pressed.connect(_on_open_2d_viewer.bind(r))
	top_btns.add_child(view2d_btn_top)

	content_area.add_child(HSeparator.new())

	# Header con marcador
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
	content_area.add_child(hbox)

	var home_label := Label.new()
	home_label.text = r.home_team_name
	home_label.add_theme_font_size_override("font_size", 18)
	hbox.add_child(home_label)

	var score_label := Label.new()
	score_label.text = " %d - %d " % [r.score_home, r.score_away]
	score_label.add_theme_font_size_override("font_size", 22)
	score_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	hbox.add_child(score_label)

	var away_label := Label.new()
	away_label.text = r.away_team_name
	away_label.add_theme_font_size_override("font_size", 18)
	hbox.add_child(away_label)

	content_area.add_child(HSeparator.new())

	# Stats compactos
	var stats_row := HBoxContainer.new()
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_row.add_theme_constant_override("separation", 30)
	content_area.add_child(stats_row)
	for tid in [r.home_team_id, r.away_team_id]:
		var s: Dictionary = r.stats.get(tid, {})
		var team_name: String = r.home_team_name if tid == r.home_team_id else r.away_team_name
		var stats_label := Label.new()
		stats_label.text = "%s — Tiros %d (%d a puerta) · Corners %d · Faltas %d · TA %d TR %d" % [
			team_name.left(30),
			int(s.get("shots", 0)), int(s.get("shots_on_target", 0)),
			int(s.get("corners", 0)), int(s.get("fouls", 0)),
			int(s.get("yellows", 0)), int(s.get("reds", 0)),
		]
		stats_label.add_theme_font_size_override("font_size", 12)
		content_area.add_child(stats_label)

	content_area.add_child(HSeparator.new())

	# Eventos cronológicos
	var events_title := Label.new()
	events_title.text = "Eventos del partido"
	events_title.add_theme_font_size_override("font_size", 14)
	content_area.add_child(events_title)

	var key_types: Array[String] = [
		MatchEvent.T_GOAL, MatchEvent.T_SHOT_ON, MatchEvent.T_SHOT_OFF,
		MatchEvent.T_SHOT_BLOCKED, MatchEvent.T_SAVE,
		MatchEvent.T_YELLOW, MatchEvent.T_RED,
		MatchEvent.T_SUBSTITUTION,
		MatchEvent.T_HALFTIME, MatchEvent.T_FULLTIME,
	]
	for ev: MatchEvent in r.events:
		if not (ev.type in key_types):
			continue
		var l := Label.new()
		var color: Color = Color(0.85, 0.85, 0.85)
		if ev.type == MatchEvent.T_GOAL:
			color = Color(0.4, 1.0, 0.5)
		elif ev.type == MatchEvent.T_RED:
			color = Color(1.0, 0.4, 0.4)
		elif ev.type == MatchEvent.T_YELLOW:
			color = Color(1.0, 0.85, 0.2)
		elif ev.type == MatchEvent.T_HALFTIME or ev.type == MatchEvent.T_FULLTIME:
			color = Color(0.6, 0.8, 1.0)
		l.text = "  %s   %s" % [ev.clock_str(), ev.description]
		l.add_theme_color_override("font_color", color)
		content_area.add_child(l)

	# (Los botones de acción ya están arriba, no hace falta repetirlos.)


# --------------------------------------------------------------------------- #
# Vista: Plantilla
# --------------------------------------------------------------------------- #
func _render_team_view() -> void:
	# Selector de equipo (OptionButton)
	var selector_row := HBoxContainer.new()
	selector_row.add_theme_constant_override("separation", 12)
	content_area.add_child(selector_row)

	var label := Label.new()
	label.text = "Equipo:"
	selector_row.add_child(label)

	var option := OptionButton.new()
	var st := _current_state()
	for i in st.teams.size():
		option.add_item(st.teams[i].name, i)
		if selected_team != null and selected_team.id == st.teams[i].id:
			option.selected = i
	option.item_selected.connect(_on_team_selector_changed.bind(st))
	selector_row.add_child(option)

	if selected_team == null and st.teams.size() > 0:
		selected_team = st.teams[0]
	if selected_team == null:
		return

	content_area.add_child(HSeparator.new())

	# Cabecera del equipo
	var header := Label.new()
	header.text = "%s · Manager: %s · Reputación: %d · %d jugadores" % [
		selected_team.name,
		selected_team.manager.name if selected_team.manager else "",
		selected_team.reputation,
		selected_team.players.size(),
	]
	header.add_theme_font_size_override("font_size", 14)
	content_area.add_child(header)

	# Tabla de plantilla
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	content_area.add_child(grid)

	var headers: Array[String] = ["#", "Nombre", "Pos", "Edad", "Nac", "Tier", "Pot", "Ovr", "Estado", "Cont"]
	for h in headers:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		l.add_theme_font_size_override("font_size", 12)
		grid.add_child(l)

	# Ordenar por overall descendente
	var sorted_players: Array[Player] = selected_team.players.duplicate()
	sorted_players.sort_custom(func(a: Player, b: Player) -> bool:
		return PlayerFactory.compute_overall(a, "") > PlayerFactory.compute_overall(b, ""))

	for p: Player in sorted_players:
		var ovr: int = PlayerFactory.compute_overall(p, "")
		var age: int = p.age_at(year, 7, 1)
		var pos_str: String = ", ".join(p.positions)
		var until_year: int = p.contract.until_year if p.contract != null else 0
		var injury_str: String = InjurySystem.injury_summary(p)
		var status_str: String = "—"
		if injury_str != "":
			status_str = "🏥 " + injury_str
		elif CardSystem.is_suspended(p):
			status_str = "🟥 sancionado %d" % p.suspended_matches
		elif p.yellow_cards_season >= 4:
			status_str = "🟨×%d (riesgo)" % p.yellow_cards_season
		elif p.yellow_cards_season > 0:
			status_str = "🟨×%d" % p.yellow_cards_season
		var cells: Array[String] = [
			str(p.shirt_number),
			p.name,
			pos_str,
			str(age),
			p.nationality,
			p.tier,
			p.potential_tier,
			str(ovr),
			status_str,
			str(until_year),
		]
		# Color por tier
		var color: Color = Color(0.85, 0.85, 0.85)
		match p.tier:
			"S": color = Color(1.0, 0.85, 0.2)  # oro
			"A": color = Color(0.6, 1.0, 0.7)
			"B": color = Color(0.6, 0.8, 1.0)
			"Y": color = Color(0.9, 0.7, 1.0)
		# Si está lesionado o sancionado, color rojo (sobreescribe)
		var is_inj: bool = InjurySystem.is_injured(p)
		var is_susp: bool = CardSystem.is_suspended(p)
		if is_inj or is_susp:
			color = Color(1.0, 0.5, 0.5)
		for i in cells.size():
			var l := Label.new()
			l.text = cells[i]
			l.add_theme_color_override("font_color", color)
			if i == 1:
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			elif i == 0 or i >= 3:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(l)


func _on_team_selector_changed(idx: int, st: DivisionState) -> void:
	if idx >= 0 and idx < st.teams.size():
		selected_team = st.teams[idx]
		_refresh_ui()


# =========================================================================== #
# Visor 2D del partido (overlay)
# =========================================================================== #
var match_viewer_overlay: Node = null

func _on_open_2d_viewer(result: MatchResult) -> void:
	if match_viewer_overlay != null:
		match_viewer_overlay.queue_free()
		match_viewer_overlay = null
	# Reconstruir lineups (el resultado no los guarda explícitamente)
	var home_team := _find_team_by_id(result.home_team_id)
	var away_team := _find_team_by_id(result.away_team_id)
	if home_team == null or away_team == null:
		status_label.text = "No se pudieron reconstruir los lineups del partido."
		return
	# Restaurar condition para que AutoLineup escoja a los que jugaron (aprox)
	for p: Player in home_team.players: p.condition = 100.0
	for p: Player in away_team.players: p.condition = 100.0
	var home_lineup: Lineup = null
	var away_lineup: Lineup = null
	if home_team.id == user_team_id:
		home_lineup = _build_user_lineup(home_team)
	if away_team.id == user_team_id:
		away_lineup = _build_user_lineup(away_team)
	if home_lineup == null:
		home_lineup = AutoLineup.pick(home_team, home_team.tactics_default.formation)
	if away_lineup == null:
		away_lineup = AutoLineup.pick(away_team, away_team.tactics_default.formation)

	var scene: PackedScene = load("res://scenes/match_viewer_2d.tscn")
	var viewer: MatchViewer2D = scene.instantiate()
	add_child(viewer)
	match_viewer_overlay = viewer
	viewer.setup(result, home_lineup, away_lineup, _on_close_2d_viewer)


func _on_close_2d_viewer() -> void:
	if match_viewer_overlay != null:
		match_viewer_overlay.queue_free()
		match_viewer_overlay = null


func _on_back_to_menu() -> void:
	# Volver al menú principal sin guardar (si quieres guardar pulsa antes 💾)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# =========================================================================== #
# "Mi club" + Mi alineación
# =========================================================================== #
func _find_team_by_id(team_id: String) -> Team:
	for t: Team in all_teams:
		if t.id == team_id:
			return t
	return null


func _on_pick_user_team() -> void:
	# Diálogo: lista de equipos con OptionButton.
	# Para v1 simple, abrimos un Popup con OptionButton.
	var popup := AcceptDialog.new()
	popup.title = "Elige tu club"
	popup.size = Vector2(320, 180)
	add_child(popup)
	var vbox := VBoxContainer.new()
	popup.add_child(vbox)
	var lbl := Label.new()
	lbl.text = "Selecciona el club que vas a dirigir:"
	vbox.add_child(lbl)
	var option := OptionButton.new()
	option.add_item("(ninguno)", -1)
	# Equipos ordenados alfabéticamente
	var sorted_teams: Array = all_teams.duplicate()
	sorted_teams.sort_custom(func(a: Team, b: Team) -> bool: return a.name < b.name)
	for i in sorted_teams.size():
		var t: Team = sorted_teams[i]
		option.add_item("%s (%s)" % [t.name, t.division.capitalize()], i)
		if t.id == user_team_id:
			option.selected = i + 1  # +1 porque el primer item es "(ninguno)"
	if user_team_id == "":
		option.selected = 0
	vbox.add_child(option)
	popup.confirmed.connect(func() -> void:
		var sel: int = option.selected
		if sel <= 0:
			user_team_id = ""
		else:
			user_team_id = sorted_teams[sel - 1].id
			# Inicializar la alineación con auto-pick para el club elegido
			_initialize_user_lineup()
		_refresh_ui()
		popup.queue_free()
	)
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()


func _initialize_user_lineup() -> void:
	if user_team_id == "":
		user_lineup_template = {}
		return
	var team := _find_team_by_id(user_team_id)
	if team == null:
		return
	var auto := AutoLineup.pick(team, team.tactics_default.formation)
	user_lineup_template = {
		"formation": auto.formation,
		"eleven_ids": auto.starting_eleven.map(func(p: Player) -> String: return p.id),
		"slot_assignments": auto.slot_assignments.duplicate(),
		"tactics": {
			"mentality": auto.tactics.mentality,
			"tempo": auto.tactics.tempo,
			"pressing": auto.tactics.pressing,
			"width": auto.tactics.width,
		},
	}


func _build_user_lineup(team: Team) -> Lineup:
	# Construye un Lineup objeto a partir del template guardado, asociado al equipo.
	if user_lineup_template.is_empty() or team.id != user_team_id:
		return null
	var lineup := Lineup.new()
	lineup.team = team
	lineup.formation = String(user_lineup_template.get("formation", "4-3-3"))
	var eleven_ids: Array = user_lineup_template.get("eleven_ids", [])
	var slot_assignments: Array = user_lineup_template.get("slot_assignments", [])
	var starting: Array[Player] = []
	var slots_typed: Array[String] = []
	for i in eleven_ids.size():
		var p: Player = team.find_player(String(eleven_ids[i]))
		if p == null:
			# Jugador eliminado del equipo (vendido/retirado): regenerar lineup
			return null
		# Si está lesionado, también fallamos al user lineup (para que use AutoLineup que excluye lesionados)
		if InjurySystem.is_injured(p):
			return null
		starting.append(p)
		slots_typed.append(String(slot_assignments[i]) if i < slot_assignments.size() else "CM")
	if starting.size() != 11:
		return null
	lineup.starting_eleven = starting
	lineup.slot_assignments = slots_typed
	# Banquillo: el resto del equipo, hasta 7
	var bench: Array[Player] = []
	for p: Player in team.players:
		if p in starting:
			continue
		if p.injury != null and not p.injury.is_empty() and int(p.injury.get("dias_restantes", 0)) > 0:
			continue
		bench.append(p)
		if bench.size() >= 7:
			break
	lineup.subs_available = bench
	# Tácticas
	var tactics_dict: Dictionary = user_lineup_template.get("tactics", {})
	var t := Tactics.new()
	t.formation = lineup.formation
	t.mentality = String(tactics_dict.get("mentality", "equilibrado"))
	t.tempo = String(tactics_dict.get("tempo", "normal"))
	t.pressing = String(tactics_dict.get("pressing", "medio"))
	t.width = String(tactics_dict.get("width", "normal"))
	lineup.tactics = t
	lineup.auto_picked = false  # ¡no penalización!
	return lineup


# Render de la vista "Mi alineación".
func _render_tactics_view() -> void:
	if user_team_id == "":
		var l := Label.new()
		l.text = "No has seleccionado un club. Pulsa 'Cambiar mi club' arriba."
		content_area.add_child(l)
		return
	var team := _find_team_by_id(user_team_id)
	if team == null:
		var l := Label.new()
		l.text = "Club %s no encontrado." % user_team_id
		content_area.add_child(l)
		return
	if user_lineup_template.is_empty():
		_initialize_user_lineup()

	# Cabecera
	var header := Label.new()
	header.text = "Alineación de %s" % team.name
	header.add_theme_font_size_override("font_size", 16)
	content_area.add_child(header)

	# Formación + tácticas
	var grid_top := GridContainer.new()
	grid_top.columns = 2
	grid_top.add_theme_constant_override("h_separation", 16)
	content_area.add_child(grid_top)
	_add_option_row(grid_top, "Formación:", Lineup.FORMATIONS.keys(), user_lineup_template["formation"], func(val: String) -> void:
		user_lineup_template["formation"] = val
		# Reasignar slots: como cambia la formación, re-auto-pick
		_initialize_user_lineup()
		# Pero preservar la formación elegida
		user_lineup_template["formation"] = val
		var auto := AutoLineup.pick(team, val)
		user_lineup_template["eleven_ids"] = auto.starting_eleven.map(func(p: Player) -> String: return p.id)
		user_lineup_template["slot_assignments"] = auto.slot_assignments.duplicate()
		_refresh_ui()
	)
	var tactics: Dictionary = user_lineup_template["tactics"]
	_add_option_row(grid_top, "Mentalidad:", ["muy_defensivo","defensivo","equilibrado","ofensivo","muy_ofensivo"], tactics["mentality"], func(v: String) -> void: user_lineup_template["tactics"]["mentality"] = v)
	_add_option_row(grid_top, "Tempo:", ["lento","normal","rapido"], tactics["tempo"], func(v: String) -> void: user_lineup_template["tactics"]["tempo"] = v)
	_add_option_row(grid_top, "Presión:", ["bajo","medio","alto"], tactics["pressing"], func(v: String) -> void: user_lineup_template["tactics"]["pressing"] = v)
	_add_option_row(grid_top, "Anchura:", ["estrecho","normal","ancho"], tactics["width"], func(v: String) -> void: user_lineup_template["tactics"]["width"] = v)

	content_area.add_child(HSeparator.new())

	# Once inicial
	var subhead := Label.new()
	subhead.text = "Once inicial — pulsa un slot para cambiar el jugador"
	content_area.add_child(subhead)

	var slots: Array = Lineup.FORMATIONS[user_lineup_template["formation"]]
	var slot_grid := GridContainer.new()
	slot_grid.columns = 3
	slot_grid.add_theme_constant_override("h_separation", 14)
	slot_grid.add_theme_constant_override("v_separation", 4)
	content_area.add_child(slot_grid)

	var eleven_ids: Array = user_lineup_template["eleven_ids"]
	for i in slots.size():
		var slot: String = slots[i]
		var lbl := Label.new()
		lbl.text = "%s:" % slot
		lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		slot_grid.add_child(lbl)

		var current_id: String = String(eleven_ids[i]) if i < eleven_ids.size() else ""
		var current_player: Player = team.find_player(current_id)
		var name_lbl := Label.new()
		name_lbl.text = current_player.name if current_player else "(vacío)"
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_grid.add_child(name_lbl)

		var pick_btn := Button.new()
		pick_btn.text = "Cambiar"
		pick_btn.pressed.connect(_on_change_slot_player.bind(i, slot, team))
		slot_grid.add_child(pick_btn)


func _add_option_row(grid: GridContainer, label_text: String, options: Array, current: String, callback: Callable) -> void:
	var l := Label.new()
	l.text = label_text
	grid.add_child(l)
	var opt := OptionButton.new()
	for i in options.size():
		opt.add_item(String(options[i]), i)
		if String(options[i]) == String(current):
			opt.selected = i
	opt.item_selected.connect(func(idx: int) -> void:
		callback.call(String(options[idx])))
	grid.add_child(opt)


# =========================================================================== #
# Vista: Mercado de fichajes
# =========================================================================== #
func _render_market_view() -> void:
	if user_team_id == "":
		var l := Label.new()
		l.text = "Selecciona un club para usar el mercado."
		content_area.add_child(l)
		return
	var user_team := _find_team_by_id(user_team_id)
	if user_team == null:
		return

	# Header: presupuesto + filtros
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	content_area.add_child(header)
	var budget_label := Label.new()
	var budget: int = user_team.finances.budget_transfers_eur if user_team.finances else 0
	budget_label.text = "Presupuesto: %s" % TransferMarket._fmt_eur(budget)
	budget_label.add_theme_font_size_override("font_size", 16)
	budget_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	header.add_child(budget_label)

	var filter_label := Label.new()
	filter_label.text = " · Filtro pos:"
	header.add_child(filter_label)
	var filter_opt := OptionButton.new()
	var positions: Array[String] = ["ALL", "GK", "CB", "LB", "RB", "CDM", "CM", "CAM", "LM", "RM", "LW", "RW", "ST"]
	for i in positions.size():
		filter_opt.add_item(positions[i], i)
		if positions[i] == market_filter_position:
			filter_opt.selected = i
	filter_opt.item_selected.connect(func(idx: int) -> void:
		market_filter_position = positions[idx]
		_refresh_ui())
	header.add_child(filter_opt)

	content_area.add_child(HSeparator.new())

	# Sección: comprar
	var buy_title := Label.new()
	buy_title.text = "💰 Buscar fichajes"
	buy_title.add_theme_font_size_override("font_size", 16)
	content_area.add_child(buy_title)

	var buy_grid := GridContainer.new()
	buy_grid.columns = 6
	buy_grid.add_theme_constant_override("h_separation", 14)
	buy_grid.add_theme_constant_override("v_separation", 3)
	content_area.add_child(buy_grid)
	for h in ["Jugador", "Equipo", "Pos", "Edad", "Ovr", "Valor / acción"]:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		l.add_theme_font_size_override("font_size", 12)
		buy_grid.add_child(l)

	# Recopilar candidatos: top 30 por overall (filtrado por posición si aplica)
	var candidates: Array = []
	for t: Team in all_teams:
		if t.id == user_team_id:
			continue
		for p: Player in t.players:
			if InjurySystem.is_injured(p):
				continue
			if market_filter_position != "ALL" and not (market_filter_position in p.positions):
				continue
			var ovr: int = PlayerFactory.compute_overall(p, "")
			candidates.append({ "player": p, "team": t, "ovr": ovr })
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["ovr"]) > int(b["ovr"]))

	for i in mini(30, candidates.size()):
		var c: Dictionary = candidates[i]
		var p: Player = c["player"]
		var t: Team = c["team"]
		var ovr: int = c["ovr"]
		var value: int = MarketValue.compute(p, year, "")
		var age: int = p.age_at(year, 7, 1)
		_market_add_label(buy_grid, p.name, _player_color(p))
		_market_add_label(buy_grid, t.short_name, _player_color(p))
		_market_add_label(buy_grid, ", ".join(p.positions).left(15), _player_color(p))
		_market_add_label(buy_grid, str(age), _player_color(p))
		_market_add_label(buy_grid, str(ovr), _player_color(p))
		var btn := Button.new()
		btn.text = "Ofertar %s" % TransferMarket._fmt_eur(value)
		btn.disabled = (value > budget)
		btn.pressed.connect(_on_attempt_buy.bind(p, t, value))
		buy_grid.add_child(btn)

	content_area.add_child(HSeparator.new())

	# Sección: vender
	var sell_title := Label.new()
	sell_title.text = "💸 Mi plantilla — vender"
	sell_title.add_theme_font_size_override("font_size", 16)
	content_area.add_child(sell_title)

	var sell_grid := GridContainer.new()
	sell_grid.columns = 6
	sell_grid.add_theme_constant_override("h_separation", 14)
	sell_grid.add_theme_constant_override("v_separation", 3)
	content_area.add_child(sell_grid)
	for h in ["Jugador", "Pos", "Edad", "Tier", "Ovr", "Valor / acción"]:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		l.add_theme_font_size_override("font_size", 12)
		sell_grid.add_child(l)
	var my_players: Array[Player] = user_team.players.duplicate()
	my_players.sort_custom(func(a: Player, b: Player) -> bool:
		return PlayerFactory.compute_overall(a, "") > PlayerFactory.compute_overall(b, ""))
	for p in my_players:
		var ovr: int = PlayerFactory.compute_overall(p, "")
		var age: int = p.age_at(year, 7, 1)
		var value: int = MarketValue.compute(p, year, "")
		_market_add_label(sell_grid, p.name, _player_color(p))
		_market_add_label(sell_grid, ", ".join(p.positions).left(15), _player_color(p))
		_market_add_label(sell_grid, str(age), _player_color(p))
		_market_add_label(sell_grid, p.tier, _player_color(p))
		_market_add_label(sell_grid, str(ovr), _player_color(p))
		var btn := Button.new()
		btn.text = "Vender %s" % TransferMarket._fmt_eur(value)
		btn.pressed.connect(_on_attempt_sell.bind(p, value))
		sell_grid.add_child(btn)


func _market_add_label(grid: GridContainer, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	grid.add_child(l)


func _player_color(p: Player) -> Color:
	if InjurySystem.is_injured(p):
		return Color(1.0, 0.5, 0.5)
	match p.tier:
		"S": return Color(1.0, 0.85, 0.2)
		"A": return Color(0.6, 1.0, 0.7)
		"B": return Color(0.6, 0.8, 1.0)
		"Y": return Color(0.9, 0.7, 1.0)
	return Color(0.85, 0.85, 0.85)


func _on_attempt_buy(player: Player, seller_team: Team, fee: int) -> void:
	var user_team := _find_team_by_id(user_team_id)
	if user_team == null:
		return
	var budget: int = user_team.finances.budget_transfers_eur
	if fee > budget:
		status_label.text = "Presupuesto insuficiente."
		return
	# Probabilidad de aceptación del vendedor (misma lógica del mercado IA)
	var rng := RandomNumberGenerator.new()
	rng.seed = year * 1000 + hash(player.id)
	var accept_p: float = TransferMarket._seller_acceptance_prob(player, seller_team, fee, year)
	var popup := ConfirmationDialog.new()
	popup.title = "Oferta por %s" % player.name
	popup.size = Vector2(420, 200)
	add_child(popup)
	var box := VBoxContainer.new()
	popup.add_child(box)
	var info := Label.new()
	info.text = "%s (%s, ovr %d, edad %d)\nClub actual: %s\nValor: %s\nProbabilidad de aceptación: %d%%" % [
		player.name, ", ".join(player.positions),
		PlayerFactory.compute_overall(player, ""),
		player.age_at(year, 7, 1),
		seller_team.name,
		TransferMarket._fmt_eur(fee),
		int(accept_p * 100),
	]
	box.add_child(info)
	popup.ok_button_text = "Hacer oferta"
	popup.cancel_button_text = "Cancelar"
	popup.confirmed.connect(func() -> void:
		popup.queue_free()
		_resolve_buy(player, seller_team, fee, accept_p, rng))
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()


func _resolve_buy(player: Player, seller_team: Team, fee: int, accept_p: float, rng: RandomNumberGenerator) -> void:
	var user_team := _find_team_by_id(user_team_id)
	if user_team == null:
		return
	if rng.randf() > accept_p:
		status_label.text = "❌ %s rechaza la oferta por %s." % [seller_team.short_name, player.name]
		return
	# Transfer
	seller_team.players.erase(player)
	user_team.players.append(player)
	player.joined_year = year
	user_team.finances.budget_transfers_eur -= fee
	if seller_team.finances:
		seller_team.finances.budget_transfers_eur += fee
	status_label.text = "✓ %s fichado por %s. Coste: %s" % [player.name, user_team.short_name, TransferMarket._fmt_eur(fee)]
	_refresh_ui()


func _on_attempt_sell(player: Player, fee: int) -> void:
	var popup := ConfirmationDialog.new()
	popup.title = "Vender a %s" % player.name
	popup.size = Vector2(380, 160)
	add_child(popup)
	var box := VBoxContainer.new()
	popup.add_child(box)
	var info := Label.new()
	info.text = "Vendes a %s por %s.\n\nConfirmas?" % [player.name, TransferMarket._fmt_eur(fee)]
	box.add_child(info)
	popup.ok_button_text = "Vender"
	popup.cancel_button_text = "Cancelar"
	popup.confirmed.connect(func() -> void:
		popup.queue_free()
		_resolve_sell(player, fee))
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()


func _resolve_sell(player: Player, fee: int) -> void:
	var user_team := _find_team_by_id(user_team_id)
	if user_team == null:
		return
	user_team.players.erase(player)
	if user_team.finances:
		user_team.finances.budget_transfers_eur += fee
	# Quitar del lineup template si está
	if user_lineup_template.has("eleven_ids"):
		var ids: Array = user_lineup_template["eleven_ids"]
		var idx: int = ids.find(player.id)
		if idx >= 0:
			# Re-init lineup tras vender un titular
			_initialize_user_lineup()
	status_label.text = "✓ %s vendido. Ingresos: %s" % [player.name, TransferMarket._fmt_eur(fee)]
	_refresh_ui()


func _on_change_slot_player(slot_idx: int, slot: String, team: Team) -> void:
	# Diálogo con candidatos compatibles
	var popup := AcceptDialog.new()
	popup.title = "Elige jugador para slot %s" % slot
	popup.size = Vector2(420, 240)
	add_child(popup)
	var vbox := VBoxContainer.new()
	popup.add_child(vbox)
	var lbl := Label.new()
	lbl.text = "Candidatos para %s (ordenados por overall):" % slot
	vbox.add_child(lbl)
	var option := OptionButton.new()
	# Excluir al jugador que YA está en el slot (no, sí lo incluimos por si quieren mantenerlo)
	var taken_ids: Dictionary = {}
	var eleven_ids: Array = user_lineup_template["eleven_ids"]
	for j in eleven_ids.size():
		if j != slot_idx:
			taken_ids[String(eleven_ids[j])] = true
	# Listar candidatos (cualquier jugador del team que no sea ya titular en otro slot)
	var candidates: Array = []
	for p: Player in team.players:
		if taken_ids.has(p.id):
			continue
		candidates.append({ "player": p, "fit": PlayerFactory.compute_overall(p, slot) * Lineup.position_familiarity(p, slot) })
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["fit"]) > float(b["fit"]))
	for i in mini(40, candidates.size()):
		var p: Player = candidates[i]["player"]
		var fit: float = candidates[i]["fit"]
		option.add_item("%s (%s, ovr %d)" % [p.name, ", ".join(p.positions), int(fit)], i)
	vbox.add_child(option)
	popup.confirmed.connect(func() -> void:
		var sel: int = option.selected
		if sel >= 0 and sel < candidates.size():
			var chosen: Player = candidates[sel]["player"]
			user_lineup_template["eleven_ids"][slot_idx] = chosen.id
		_refresh_ui()
		popup.queue_free()
	)
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()
