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
	_start_season()


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

	# Indicador de "Mi club"
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_tabs.add_child(spacer2)
	user_team_label = Label.new()
	user_team_label.add_theme_font_size_override("font_size", 13)
	user_team_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	view_tabs.add_child(user_team_label)
	var pick_user_button := Button.new()
	pick_user_button.text = "Cambiar mi club"
	pick_user_button.pressed.connect(_on_pick_user_team)
	view_tabs.add_child(pick_user_button)

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
	advance_button.text = "Siguiente jornada"
	advance_button.pressed.connect(_on_advance_jornada)
	footer.add_child(advance_button)

	advance_all_button = Button.new()
	advance_all_button.text = "Toda la temporada"
	advance_all_button.pressed.connect(_on_advance_full_season)
	footer.add_child(advance_all_button)

	reset_button = Button.new()
	reset_button.text = "Nueva temporada"
	reset_button.pressed.connect(_on_reset_season)
	footer.add_child(reset_button)

	save_button = Button.new()
	save_button.text = "💾 Guardar"
	save_button.pressed.connect(_on_save_game)
	footer.add_child(save_button)

	load_button = Button.new()
	load_button.text = "📂 Cargar"
	load_button.pressed.connect(_on_load_game)
	footer.add_child(load_button)


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
	state.seed_counter = (SEED_BASE + seed_offset) * 1000


# =========================================================================== #
# Acciones de simulación
# =========================================================================== #
func _on_advance_jornada() -> void:
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
	_refresh_ui()


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
	year += 1
	# Reputación dinámica con la temporada que acaba de terminar
	if primera_state.league_table != null and segunda_state.league_table != null:
		ReputationUpdate.apply_after_season(primera_state.league_table, segunda_state.league_table, all_teams)
		PromotionRelegation.apply(primera_state.league_table, segunda_state.league_table, all_teams)
	# Aging + retiros + canteranos
	Aging.age_all(all_teams, year, SEED_BASE * 100)
	for t: Team in all_teams:
		Cantera.fill_squad_if_needed(t, year, SEED_BASE * 50)
	# Mercado de fichajes
	TransferMarket.run(all_teams, year, SEED_BASE * 7)
	_start_season()


func _simulate_jornada(state: DivisionState) -> void:
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
	var result: Dictionary = SaveSystem.save_game(
		"autosave", year, all_teams,
		primera_state.current_jornada, segunda_state.current_jornada,
		primera_state.league_table, segunda_state.league_table,
		user_team_id, user_lineup_template)
	if result.get("ok", false):
		status_label.text = "Partida guardada (autosave) — %s" % result["saved_at"]
	else:
		status_label.text = "ERROR al guardar: %s" % result.get("error", "?")


func _on_load_game() -> void:
	var save_data: SaveSystem.SaveData = SaveSystem.load_game("autosave")
	if save_data == null:
		status_label.text = "No hay partida guardada (slot 'autosave')."
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

	# Restaurar selección de "mi club" + alineación personal
	user_team_id = save_data.user_team_id
	user_lineup_template = save_data.user_lineup_template.duplicate(true)

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

	# User team label
	if user_team_id != "":
		var ut := _find_team_by_id(user_team_id)
		user_team_label.text = "Mi club: %s" % (ut.name if ut else user_team_id)
	else:
		user_team_label.text = "Sin club seleccionado"

	# Limpiar contenido
	for c in content_area.get_children():
		c.queue_free()

	match current_view:
		VIEW_TABLE: _render_table_view()
		VIEW_FIXTURES: _render_fixtures_view()
		VIEW_TEAM: _render_team_view()
		VIEW_MATCH: _render_match_view()
		VIEW_TACTICS: _render_tactics_view()


# --------------------------------------------------------------------------- #
# Vista: Clasificación
# --------------------------------------------------------------------------- #
func _render_table_view() -> void:
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	content_area.add_child(grid)

	var headers: Array[String] = ["Pos", "Equipo", "PJ", "G", "E", "P", "GF", "GC", "DG", "Pts"]
	for h in headers:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		l.add_theme_font_size_override("font_size", 13)
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

	var team_button := Button.new()
	team_button.text = row.team_name
	team_button.flat = true
	team_button.add_theme_color_override("font_color", color)
	team_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	team_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_button.pressed.connect(_on_team_clicked.bind(row.team_id))

	var cells_pre: Array[String] = [str(pos)]
	var cells_post: Array[String] = [
		str(row.played), str(row.won), str(row.drawn), str(row.lost),
		str(row.goals_for), str(row.goals_against),
		"%+d" % row.goal_diff(), str(row.points()),
	]
	# Pos
	var l_pos := Label.new()
	l_pos.text = cells_pre[0]
	l_pos.add_theme_color_override("font_color", color)
	l_pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(l_pos)
	# Equipo (botón clickable)
	grid.add_child(team_button)
	# Resto
	for c in cells_post:
		var l := Label.new()
		l.text = c
		l.add_theme_color_override("font_color", color)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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

	for r: MatchResult in st.last_jornada_results:
		var btn := Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.text = "  %-30s   %d   -   %d   %s  " % [
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
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	content_area.add_child(grid)

	var headers: Array[String] = ["#", "Nombre", "Pos", "Edad", "Nac", "Tier", "Pot", "Ovr", "Cont"]
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
		var cells: Array[String] = [
			str(p.shirt_number),
			p.name,
			pos_str,
			str(age),
			p.nationality,
			p.tier,
			p.potential_tier,
			str(ovr),
			str(until_year),
		]
		# Color por tier
		var color: Color = Color(0.85, 0.85, 0.85)
		match p.tier:
			"S": color = Color(1.0, 0.85, 0.2)  # oro
			"A": color = Color(0.6, 1.0, 0.7)
			"B": color = Color(0.6, 0.8, 1.0)
			"Y": color = Color(0.9, 0.7, 1.0)
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
