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

const VIEW_HUB := "hub"
const VIEW_TABLE := "table"
const VIEW_FIXTURES := "fixtures"
const VIEW_TEAM := "team"
const VIEW_MATCH := "match"
const VIEW_TACTICS := "tactics"
const VIEW_MARKET := "market"
const VIEW_CAREER := "career"
const VIEW_CHAMPIONS := "champions"
const VIEW_FINANCES := "finances"
const VIEW_CALENDAR := "calendar"
const VIEW_RIVAL := "rival"
const VIEW_DECISIONS := "decisions"
const VIEW_EMPLOYEES := "employees"


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
var current_view: String = VIEW_HUB
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
# Flag para saber si el mercado de invierno ya se ha ejecutado esta temporada.
var winter_market_done: bool = false
# Última jornada en la que se evaluó el premio "entrenador del mes" del usuario
var last_coach_award_jornada: int = 0
# Puntos del usuario al final de la última evaluación (para diff de 4 jornadas)
var user_points_at_last_award: int = 0
# Objetivo del club para esta temporada (depende de la reputación + posición previa).
# Estructura: { "type": "liga"/"copa"/"champions", "target_position": int, "description": String }
var season_objective: Dictionary = {}
# Si el objetivo se ha mostrado al usuario al inicio de temporada
var objective_shown: bool = false
# Última edición de competiciones europeas (no se persisten en save).
var champions_state: ChampionsBracket = null
var europa_state: ChampionsBracket = null
var conference_state: ChampionsBracket = null
# Pestaña activa dentro del visor de competiciones europeas.
var selected_european_comp: String = ""

# UI refs (populadas en _build_ui)
var year_label: Label
var jornada_label: Label
var status_label: Label
var div_tabs_box: HBoxContainer
var view_tabs_box: HBoxContainer
var top_header_separator: HSeparator
var top_header_box: HBoxContainer
var footer_global_box: HBoxContainer
var view_title_label: Label  # Título de la vista actual en sub-vistas
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
	status_label.text = "¡Bienvenido como mánager de %s! Pulsa ENTRENADOR → ALINEACIÓN para configurar tu once." % team.name
	# Mantener VIEW_HUB como vista por defecto
	current_view = VIEW_HUB
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
	top_header_box = HBoxContainer.new()
	top_header_box.add_theme_constant_override("separation", 24)
	vbox.add_child(top_header_box)
	var header := top_header_box

	# Botón "🏠 Hub" para volver al dashboard principal
	var hub_btn := Button.new()
	hub_btn.text = "🏠 Hub"
	hub_btn.tooltip_text = "Volver al menú principal"
	hub_btn.pressed.connect(_on_select_view.bind(VIEW_HUB))
	header.add_child(hub_btn)

	view_title_label = Label.new()
	view_title_label.text = ""
	view_title_label.add_theme_font_size_override("font_size", 18)
	view_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	header.add_child(view_title_label)

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
	div_tabs_box = HBoxContainer.new()
	div_tabs_box.add_theme_constant_override("separation", 4)
	vbox.add_child(div_tabs_box)
	var div_tabs := div_tabs_box

	primera_div_button = _make_tab_button("Primera", _on_select_division.bind("primera"))
	div_tabs.add_child(primera_div_button)
	segunda_div_button = _make_tab_button("Segunda", _on_select_division.bind("segunda"))
	div_tabs.add_child(segunda_div_button)

	# --- View tabs ---
	view_tabs_box = HBoxContainer.new()
	view_tabs_box.add_theme_constant_override("separation", 4)
	vbox.add_child(view_tabs_box)
	var view_tabs := view_tabs_box

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
	var view_finances_button := _make_tab_button("💰 Finanzas", _on_select_view.bind(VIEW_FINANCES))
	view_tabs.add_child(view_finances_button)
	var view_calendar_button := _make_tab_button("📅 Calendario", _on_select_view.bind(VIEW_CALENDAR))
	view_tabs.add_child(view_calendar_button)

	# Indicador de "Mi club" (solo lectura — el club se elige en Nueva partida)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_tabs.add_child(spacer2)
	user_team_label = Label.new()
	user_team_label.add_theme_font_size_override("font_size", 12)
	user_team_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	view_tabs.add_child(user_team_label)

	top_header_separator = HSeparator.new()
	vbox.add_child(top_header_separator)

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
	footer_global_box = HBoxContainer.new()
	footer_global_box.add_theme_constant_override("separation", 12)
	vbox.add_child(footer_global_box)
	var footer := footer_global_box

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
	# Inicializar caja + patrocinadores iniciales para todos los clubes
	for t: Team in all_teams:
		ClubFinances.ensure_initialized(t)
		ClubFinances.ensure_initial_sponsors(t, year)
		# Staff por defecto si no viene en el JSON
		if t.staff == null:
			t.staff = StaffInfo.new()
		# Organigrama: generar si no existe (a partir de plantilla por tamaño)
		if t.organigrama == null:
			t.organigrama = OrganigramaFactory.generate(t, year)
			OrganigramaFactory.sync_staff_info(t)
	status_label.text = "Cargados %d equipos, %d jugadores." % [
		all_teams.size(), loaded.player_id_index.size()]


func _start_season() -> void:
	# Re-particionar equipos por división actual
	primera_state.teams = all_teams.filter(func(t: Team) -> bool: return t.division == "primera")
	segunda_state.teams = all_teams.filter(func(t: Team) -> bool: return t.division == "segunda")
	_init_division(primera_state, SEED_BASE)
	_init_division(segunda_state, SEED_BASE + 1)
	current_view = VIEW_HUB
	selected_team = null
	selected_match = null
	winter_market_done = false  # se podrá abrir el mercado invernal otra vez
	last_coach_award_jornada = 0
	user_points_at_last_award = 0
	# Generar objetivo del club para esta temporada
	if user_team_id != "":
		_generate_season_objective()
	# Pre-temporada: 3 amistosos para el equipo del usuario antes de la jornada 1
	if user_team_id != "":
		_run_preseason_friendlies()
		# Mostrar objetivo del club
		_show_season_objective_modal()
	_refresh_ui()


# =========================================================================== #
# Pre-temporada: amistosos antes de empezar la liga
# =========================================================================== #
func _run_preseason_friendlies() -> void:
	var user_team := _find_team_by_id(user_team_id)
	if user_team == null:
		return
	# Elige 3 rivales: uno de Primera (no el del usuario), uno de Segunda y uno europeo si los hay,
	# o si no, 3 de la división contraria a user_team.
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_BASE * 19 + year
	var pool: Array = []
	for t: Team in all_teams:
		if t.id == user_team_id:
			continue
		# Solo rivales con plantilla suficiente
		if t.players.size() >= 11:
			pool.append(t)
	if pool.size() < 3:
		return
	pool.shuffle()
	var rivals: Array = pool.slice(0, 3)

	var results: Array = []
	var match_seed: int = SEED_BASE * 41 + year
	for rival: Team in rivals:
		# Restaurar condition para los amistosos
		for p: Player in user_team.players:
			p.condition = 100.0
		for p: Player in rival.players:
			p.condition = 100.0
		var home_lineup := AutoLineup.pick(user_team, user_team.tactics_default.formation)
		var away_lineup := AutoLineup.pick(rival, rival.tactics_default.formation)
		match_seed += 1
		var result: MatchResult = MatchEngine.simulate(home_lineup, away_lineup, match_seed)
		results.append({"rival": rival.name, "result": result})
	# Reset condition para empezar liga frescos
	for p: Player in user_team.players:
		p.condition = 100.0
	_show_preseason_modal(user_team, results)


func _show_preseason_modal(user_team: Team, results: Array) -> void:
	var popup := AcceptDialog.new()
	popup.title = "🟢 Pre-temporada %d-%d" % [year, year + 1]
	popup.size = Vector2(560, 380)
	popup.ok_button_text = "Empezar Liga"
	add_child(popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	popup.add_child(box)

	var title := Label.new()
	title.text = "Amistosos de %s" % user_team.name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Sin efecto en la clasificación, pero te dan ritmo de cara al primer partido."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	box.add_child(subtitle)

	box.add_child(HSeparator.new())

	var won: int = 0
	var drawn: int = 0
	var lost: int = 0
	for r in results:
		var rival: String = String(r["rival"])
		var res: MatchResult = r["result"]
		if res == null:
			continue
		var line := Label.new()
		var icon: String = "🟰"
		if res.score_home > res.score_away:
			icon = "✅"
			won += 1
		elif res.score_home < res.score_away:
			icon = "❌"
			lost += 1
		else:
			drawn += 1
		line.text = "%s  %s  %d-%d  %s" % [icon, user_team.name, res.score_home, res.score_away, rival]
		line.add_theme_font_size_override("font_size", 13)
		box.add_child(line)

	var summary := Label.new()
	summary.text = "Balance: %d V · %d E · %d D" % [won, drawn, lost]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_theme_font_size_override("font_size", 12)
	summary.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	box.add_child(summary)

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()


# =========================================================================== #
# Mercado de invierno (jornada 19 — mitad de Liga)
# =========================================================================== #
func _run_winter_market() -> void:
	var window: TransferMarket.WindowConfig = TransferMarket.winter_window()
	var market_result := TransferMarket.run(all_teams, year, SEED_BASE * 31 + year, window)
	# Mostrar modal solo si hubo movimiento o si el usuario tiene fichaje/venta
	var user_relevant: bool = false
	for tr: TransferMarket.Transfer in market_result.transfers:
		if tr.to_team_id == user_team_id or tr.from_team_id == user_team_id:
			user_relevant = true
			break
	if market_result.transfers.size() == 0:
		status_label.text = "❄️ Mercado de invierno: sin movimientos relevantes."
		return
	if user_relevant or market_result.transfers.size() >= 5:
		_show_winter_market_modal(market_result)
	else:
		status_label.text = "❄️ Mercado de invierno cerrado: %d operaciones en la liga." % market_result.transfers.size()


func _show_winter_market_modal(market_result: TransferMarket.MarketResult) -> void:
	var popup := AcceptDialog.new()
	popup.title = "❄️ Mercado de invierno %d" % year
	popup.size = Vector2(620, 420)
	popup.ok_button_text = "Continuar"
	add_child(popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	popup.add_child(box)

	var header := Label.new()
	header.text = "Cerró la ventana de invierno con %d operaciones." % market_result.transfers.size()
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	box.add_child(header)

	box.add_child(HSeparator.new())

	# Tu equipo destacado
	var user_signings: Array = []
	var user_departures: Array = []
	for tr: TransferMarket.Transfer in market_result.transfers:
		if tr.to_team_id == user_team_id:
			user_signings.append(tr)
		elif tr.from_team_id == user_team_id:
			user_departures.append(tr)
	if user_signings.size() > 0 or user_departures.size() > 0:
		var your_label := Label.new()
		your_label.text = "🏟 Tu club:"
		your_label.add_theme_font_size_override("font_size", 13)
		your_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
		box.add_child(your_label)
		for tr: TransferMarket.Transfer in user_signings:
			var l := Label.new()
			l.text = "  ✅ Firma: %s (de %s, %s €)" % [tr.player_name, tr.from_team_name, TransferMarket._fmt_eur(tr.fee_eur)]
			l.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
			box.add_child(l)
		for tr: TransferMarket.Transfer in user_departures:
			var l := Label.new()
			l.text = "  ❌ Vende: %s (a %s, %s €)" % [tr.player_name, tr.to_team_name, TransferMarket._fmt_eur(tr.fee_eur)]
			l.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7))
			box.add_child(l)
		box.add_child(HSeparator.new())

	# Resto de transferencias destacadas (top 8 por fee)
	var sorted_t: Array = market_result.transfers.duplicate()
	sorted_t.sort_custom(func(a: TransferMarket.Transfer, b: TransferMarket.Transfer) -> bool:
		return a.fee_eur > b.fee_eur)
	var others_label := Label.new()
	others_label.text = "Top fichajes de la ventana:"
	others_label.add_theme_font_size_override("font_size", 12)
	others_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	box.add_child(others_label)
	var shown: int = 0
	for tr: TransferMarket.Transfer in sorted_t:
		if shown >= 8:
			break
		if tr.to_team_id == user_team_id or tr.from_team_id == user_team_id:
			continue
		var l := Label.new()
		l.text = "  %s · %s → %s · %s €" % [tr.player_name, tr.from_team_name, tr.to_team_name, TransferMarket._fmt_eur(tr.fee_eur)]
		l.add_theme_font_size_override("font_size", 11)
		box.add_child(l)
		shown += 1

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()


# Modal de resumen del mercado de verano (incluye renovaciones, free agents,
# traspasos y libres que se retiraron).
func _show_summer_market_modal(market: TransferMarket.MarketResult) -> void:
	var popup := AcceptDialog.new()
	popup.title = "☀ Mercado de verano %d" % year
	popup.size = Vector2(700, 540)
	popup.ok_button_text = "Continuar"
	add_child(popup)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(680, 480)
	popup.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	# Header con cifras globales
	var stats_label := Label.new()
	stats_label.text = "📊 %d traspasos · %d fichajes libres · %d renovaciones · %d sin equipo (retirados/fuera)" % [
		market.transfers.size(),
		market.free_agent_signings.size(),
		market.renewals.size(),
		market.released.size() - market.free_agent_signings.size(),
	]
	stats_label.add_theme_font_size_override("font_size", 12)
	stats_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	box.add_child(stats_label)

	box.add_child(HSeparator.new())

	# === Tu club ===
	var user_signings: Array = []
	var user_departures: Array = []
	var user_free_signings: Array = []
	var user_released: Array = []
	for tr: TransferMarket.Transfer in market.transfers:
		if tr.to_team_id == user_team_id: user_signings.append(tr)
		elif tr.from_team_id == user_team_id: user_departures.append(tr)
	for fa: Dictionary in market.free_agent_signings:
		if String(fa.get("signing_team_id", "")) == user_team_id:
			user_free_signings.append(fa)

	if user_signings.size() > 0 or user_departures.size() > 0 or user_free_signings.size() > 0:
		var your_label := Label.new()
		your_label.text = "🏟 Tu club:"
		your_label.add_theme_font_size_override("font_size", 14)
		your_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
		box.add_child(your_label)
		for tr: TransferMarket.Transfer in user_signings:
			var l := Label.new()
			l.text = "  ✅ Ficha: %s (%s, %s €)" % [tr.player_name, tr.from_team_name, TransferMarket._fmt_eur(tr.fee_eur)]
			l.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
			box.add_child(l)
		for fa: Dictionary in user_free_signings:
			var l := Label.new()
			l.text = "  🆓 Libre: %s (%s, ovr %d, %s €/año)" % [
				String(fa["player_name"]), String(fa["prev_team_name"]),
				int(fa["overall"]), TransferMarket._fmt_eur(int(fa["salary"])),
			]
			l.add_theme_color_override("font_color", Color(0.85, 1.0, 0.5))
			box.add_child(l)
		for tr: TransferMarket.Transfer in user_departures:
			var l := Label.new()
			l.text = "  ❌ Vende: %s (a %s, %s €)" % [tr.player_name, tr.to_team_name, TransferMarket._fmt_eur(tr.fee_eur)]
			l.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7))
			box.add_child(l)
		box.add_child(HSeparator.new())

	# === Top fichajes (resto liga) ===
	var sorted_t: Array = market.transfers.duplicate()
	sorted_t.sort_custom(func(a: TransferMarket.Transfer, b: TransferMarket.Transfer) -> bool:
		return a.fee_eur > b.fee_eur)
	var top_label := Label.new()
	top_label.text = "💰 Top traspasos:"
	top_label.add_theme_font_size_override("font_size", 13)
	top_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	box.add_child(top_label)
	var shown: int = 0
	for tr: TransferMarket.Transfer in sorted_t:
		if shown >= 8: break
		if tr.to_team_id == user_team_id or tr.from_team_id == user_team_id:
			continue
		var l := Label.new()
		l.text = "  %s · %s → %s · %s €" % [tr.player_name, tr.from_team_name, tr.to_team_name, TransferMarket._fmt_eur(tr.fee_eur)]
		l.add_theme_font_size_override("font_size", 11)
		box.add_child(l)
		shown += 1

	# === Top free agent signings ===
	var sorted_fa: Array = market.free_agent_signings.duplicate()
	sorted_fa.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["overall"]) > int(b["overall"]))
	if sorted_fa.size() > 0:
		var fa_label := Label.new()
		fa_label.text = "🆓 Top fichajes libres:"
		fa_label.add_theme_font_size_override("font_size", 13)
		fa_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.5))
		box.add_child(fa_label)
		shown = 0
		for fa: Dictionary in sorted_fa:
			if shown >= 6: break
			if String(fa.get("signing_team_id", "")) == user_team_id:
				continue
			var l := Label.new()
			l.text = "  %s (ovr %d) %s → %s" % [
				String(fa["player_name"]), int(fa["overall"]),
				String(fa["prev_team_name"]), String(fa["signing_team_name"]),
			]
			l.add_theme_font_size_override("font_size", 11)
			box.add_child(l)
			shown += 1

	# === Notable releases (jugadores top que se quedaron sin equipo) ===
	var sorted_rel: Array = market.released.duplicate()
	sorted_rel.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("ovr", 0)) > int(b.get("ovr", 0)))
	# Filtrar los que SÍ ficharon (excluirlos de "sin equipo")
	var fa_signed_names: Dictionary = {}
	for fa in market.free_agent_signings:
		fa_signed_names[String(fa["player_name"])] = true
	var unsigned: Array = []
	for r: Dictionary in sorted_rel:
		if not fa_signed_names.has(String(r["player_name"])):
			unsigned.append(r)
	if unsigned.size() > 0:
		var rel_label := Label.new()
		rel_label.text = "⚠ Sin equipo (retirados o fuera de la liga):"
		rel_label.add_theme_font_size_override("font_size", 13)
		rel_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7))
		box.add_child(rel_label)
		shown = 0
		for r: Dictionary in unsigned:
			if shown >= 5: break
			if int(r.get("ovr", 0)) < 70: continue  # solo los notables
			var l := Label.new()
			l.text = "  %s (ovr %d, %d años, ex-%s)" % [
				String(r["player_name"]), int(r["ovr"]),
				int(r.get("age", 0)), String(r["team_name"]),
			]
			l.add_theme_font_size_override("font_size", 11)
			box.add_child(l)
			shown += 1

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()


# =========================================================================== #
# Objetivos del club (por temporada)
# =========================================================================== #
# Genera el objetivo de Liga al inicio de cada temporada, basado en la
# reputación del club y su posición la temporada anterior.
func _generate_season_objective() -> void:
	var team := _find_team_by_id(user_team_id)
	if team == null:
		return
	var rep: int = team.reputation
	var target_position: int
	var description: String
	if team.division == "primera":
		# Primera: posición esperada según reputación
		if rep >= 92:
			target_position = 1
			description = "Conquistar la Liga. Esperamos el título."
		elif rep >= 85:
			target_position = 4
			description = "Plaza Champions League (top 4)."
		elif rep >= 78:
			target_position = 7
			description = "Plaza europea (top 7)."
		elif rep >= 70:
			target_position = 12
			description = "Mantener categoría con tranquilidad (top 12)."
		else:
			target_position = 17
			description = "Salvar la categoría."
	else:
		# Segunda: ascender o playoff
		if rep >= 75:
			target_position = 2
			description = "Ascender directo a Primera."
		elif rep >= 65:
			target_position = 6
			description = "Playoff de ascenso."
		else:
			target_position = 14
			description = "Mantener la categoría."
	season_objective = {
		"type": "liga",
		"target_position": target_position,
		"description": description,
	}
	objective_shown = false


# Modal con el objetivo al inicio de la temporada (se llama desde _start_season
# tras los amistosos).
func _show_season_objective_modal() -> void:
	if season_objective.is_empty() or objective_shown:
		return
	objective_shown = true
	var team := _find_team_by_id(user_team_id)
	if team == null:
		return
	var popup := AcceptDialog.new()
	popup.title = "🎯 Objetivo de la temporada"
	popup.size = Vector2(520, 280)
	popup.ok_button_text = "Entendido"
	add_child(popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	popup.add_child(box)

	var header := Label.new()
	header.text = "%s · Temporada %d-%d" % [team.name, year, year + 1]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	box.add_child(header)

	var goal_label := Label.new()
	goal_label.text = "🎯 %s" % String(season_objective.get("description", ""))
	goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal_label.add_theme_font_size_override("font_size", 14)
	goal_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	box.add_child(goal_label)

	var detail := Label.new()
	detail.text = "Posición objetivo: %dº o mejor" % int(season_objective.get("target_position", 1))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	box.add_child(detail)

	var hint := Label.new()
	hint.text = "Si lo cumples, la directiva incrementará el presupuesto.\nSi te quedas muy lejos, podrías recibir críticas."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(hint)

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()


# Evalúa el cumplimiento del objetivo al final de temporada y aplica
# refuerzo / sanción al presupuesto del club.
func _evaluate_season_objective() -> Dictionary:
	if season_objective.is_empty() or user_team_id == "":
		return {}
	var team := _find_team_by_id(user_team_id)
	if team == null or team.finances == null:
		return {}
	var state: DivisionState = primera_state if team.division == "primera" else segunda_state
	if state.league_table == null:
		return {}
	var sorted: Array = state.league_table.sorted_rows()
	var actual_position: int = -1
	for i in sorted.size():
		if sorted[i].team_id == user_team_id:
			actual_position = i + 1
			break
	if actual_position == -1:
		return {}
	var target: int = int(season_objective.get("target_position", 1))
	var description: String = String(season_objective.get("description", ""))
	var verdict: String
	var verdict_color: Color
	var budget_change: float
	if actual_position <= target - 2:
		verdict = "EXCELENTE — superaste con creces el objetivo"
		verdict_color = Color(0.4, 1.0, 0.5)
		budget_change = 0.30  # +30% presupuesto
	elif actual_position <= target:
		verdict = "OBJETIVO CUMPLIDO"
		verdict_color = Color(0.7, 1.0, 0.7)
		budget_change = 0.15  # +15%
	elif actual_position <= target + 3:
		verdict = "PRÓXIMO al objetivo, ligero descontento"
		verdict_color = Color(1.0, 0.85, 0.4)
		budget_change = 0.0
	else:
		verdict = "FRACASO — muy lejos del objetivo"
		verdict_color = Color(1.0, 0.5, 0.5)
		budget_change = -0.20  # -20%
	# Aplicar al presupuesto
	team.finances.budget_transfers_eur = int(float(team.finances.budget_transfers_eur) * (1.0 + budget_change))
	return {
		"actual_position": actual_position,
		"target_position": target,
		"description": description,
		"verdict": verdict,
		"verdict_color": verdict_color,
		"budget_change": budget_change,
	}


func _show_objective_evaluation_modal(eval: Dictionary) -> void:
	if eval.is_empty():
		return
	var popup := AcceptDialog.new()
	popup.title = "🎯 Evaluación del objetivo"
	popup.size = Vector2(540, 320)
	popup.ok_button_text = "Continuar"
	add_child(popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	popup.add_child(box)

	var verdict_label := Label.new()
	verdict_label.text = String(eval["verdict"])
	verdict_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	verdict_label.add_theme_font_size_override("font_size", 17)
	verdict_label.add_theme_color_override("font_color", eval["verdict_color"])
	box.add_child(verdict_label)

	box.add_child(HSeparator.new())

	var detail := Label.new()
	detail.text = "Objetivo: %dº (%s)\nPosición final: %dº" % [
		int(eval["target_position"]),
		String(eval["description"]),
		int(eval["actual_position"]),
	]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	box.add_child(detail)

	var change: float = float(eval["budget_change"])
	if change != 0.0:
		var change_label := Label.new()
		change_label.text = "Presupuesto fichajes: %s%.0f%%" % ["+" if change > 0 else "", change * 100]
		change_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		change_label.add_theme_font_size_override("font_size", 13)
		change_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7) if change > 0 else Color(1.0, 0.7, 0.7))
		box.add_child(change_label)

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()


# Premio "Entrenador del mes": cada 4 jornadas chequeamos cuántos puntos
# sumó el usuario en ese tramo. Si >=8 (de 12 posibles), cobra 750K +
# notificación. >=10 → 1.5M.
func _evaluate_coach_of_the_month() -> void:
	if user_team_id == "" or primera_state.league_table == null:
		return
	var team := _find_team_by_id(user_team_id)
	if team == null or team.division != "primera":
		return
	var rows: Array = primera_state.league_table.sorted_rows()
	var current_pts: int = 0
	for r: LeagueTable.TeamRow in rows:
		if r.team_id == user_team_id:
			current_pts = r.points()
			break
	var diff: int = current_pts - user_points_at_last_award
	user_points_at_last_award = current_pts
	if diff >= 10:
		# Mes excelente: 4 victorias seguidas o casi
		team.finances.cash_balance += 1_500_000
		_show_coach_award_modal("EXCELENTE", diff, 1_500_000)
	elif diff >= 8:
		team.finances.cash_balance += 750_000
		_show_coach_award_modal("MUY BIEN", diff, 750_000)
	# < 8 puntos: nada


func _show_coach_award_modal(verdict: String, points: int, prize: int) -> void:
	var popup := AcceptDialog.new()
	popup.title = "🏅 Entrenador del mes"
	popup.size = Vector2(420, 220)
	popup.ok_button_text = "Continuar"
	add_child(popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	popup.add_child(box)
	var v := Label.new()
	v.text = verdict
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 20)
	v.add_theme_color_override("font_color", Color(0.7, 1.0, 0.6))
	box.add_child(v)
	var detail := Label.new()
	detail.text = "%d puntos en las últimas 4 jornadas\n+%s € de premio" % [points, TransferMarket._fmt_eur(prize)]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	box.add_child(detail)
	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()


func _init_division(state: DivisionState, seed_offset: int) -> void:
	var ids: Array = state.teams.map(func(t: Team) -> String: return t.id)
	# Calendario con fechas reales (temporada año-año+1, agosto a mayo).
	# european_team_ids: top 4 año anterior — pero la primera vez no tenemos
	# tabla previa, así que pasamos vacío. Próximas iteraciones lo calculan.
	state.calendar = CalendarGenerator.generate_with_dates(ids, year, SEED_BASE + seed_offset, [])
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

	# Mercado de invierno: tras la jornada 19 (mitad de Liga), si no se ha
	# ejecutado todavía este año, abrir la mini-ventana invernal.
	if not winter_market_done and primera_state.current_jornada >= 19:
		_run_winter_market()
		winter_market_done = true

	# Premio entrenador del mes: cada 4 jornadas, si el usuario sumó >=8 puntos
	# en sus últimas 4 jornadas de Liga, cobra 750K + reconocimiento.
	if user_team_id != "" and primera_state.current_jornada > 0 \
			and primera_state.current_jornada - last_coach_award_jornada >= 4:
		_evaluate_coach_of_the_month()
		last_coach_award_jornada = primera_state.current_jornada
	if not any_advanced:
		status_label.text = "Temporada completada. Pulsa 'Nueva temporada'."
		return
	# Si el usuario tuvo partido, mostrar resumen post-partido (o abrir 2D
	# directamente si lo pidió en el modal pre-partido).
	var user_result := _find_user_result_in_last_jornada()
	if user_result != null:
		if auto_open_2d_after_match:
			auto_open_2d_after_match = false
			_on_open_2d_viewer(user_result)
		else:
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
	popup.size = Vector2(560, 460)
	popup.ok_button_text = "Continuar"
	# Botón extra: Ver en 2D (replay del partido del usuario)
	var view_2d_btn: Button = popup.add_button("🎬 Ver replay en 2D", true, "view_2d")
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
	# Custom action: ver replay en 2D
	popup.custom_action.connect(func(action: StringName) -> void:
		if String(action) == "view_2d":
			popup.queue_free()
			_on_open_2d_viewer(r)
	)
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
	popup.size = Vector2(560, 360)
	popup.ok_button_text = "▶ Jugar (resultado directo)"
	popup.cancel_button_text = "Configurar alineación"
	# Botón extra: jugar y abrir visor 2D automáticamente al terminar
	popup.add_button("🎬 Jugar y ver en 2D", true, "play_with_2d")
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
		auto_open_2d_after_match = false
		_do_advance_jornada()
	)
	popup.canceled.connect(func() -> void:
		popup.queue_free()
		# Llevar al usuario a la pestaña de alineación para que ajuste
		current_view = VIEW_TACTICS
		_refresh_ui()
	)
	popup.custom_action.connect(func(action: StringName) -> void:
		if String(action) == "play_with_2d":
			popup.queue_free()
			auto_open_2d_after_match = true
			_do_advance_jornada()
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
		# Evaluar objetivo de temporada antes del reset
		if user_team_id != "" and not season_objective.is_empty():
			var eval: Dictionary = _evaluate_season_objective()
			if not eval.is_empty():
				_show_objective_evaluation_modal(eval)
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
	# Reset estadísticas individuales (mantiene history acumulada en Player.history)
	for t: Team in all_teams:
		for p: Player in t.players:
			p.season_goals = 0
			p.season_assists = 0
			p.season_matches = 0
			p.season_minutes = 0
	# Mercado de fichajes (verano)
	var summer_result: TransferMarket.MarketResult = TransferMarket.run(all_teams, year, SEED_BASE * 7)
	# Modal de resumen (solo si hubo movimientos relevantes)
	if user_team_id != "" and (summer_result.transfers.size() > 0 or summer_result.free_agent_signings.size() > 0):
		_show_summer_market_modal(summer_result)
	# Competiciones europeas:
	#   Champions: top 1-4 (4 españoles + 12 europeos = 16, 4 grupos x 4 + KO).
	#   Europa: top 5-8 + 4 más + 8 europeos pool medio = 16, KO directo.
	#   Conference: top 9-16 + 8 europeos pool bajo = 16, KO directo.
	if primera_state.league_table != null:
		var liga_sorted: Array = primera_state.league_table.sorted_rows()
		var spanish_by_pos: Array = []
		for r: LeagueTable.TeamRow in liga_sorted:
			var tt: Team = _find_team_by_id(r.team_id)
			if tt != null:
				spanish_by_pos.append(tt)
		# Champions: 1-4
		var top4: Array = spanish_by_pos.slice(0, 4)
		if top4.size() == 4:
			var euros_ch: Array = EuropeanTeams.generate_all(year, SEED_BASE + year * 13)
			champions_state = ChampionsSimulator.run(top4, euros_ch, year, SEED_BASE * 17 + year)
		# Europa: 5-12 (8 equipos)
		var europa_qual: Array = spanish_by_pos.slice(4, 12)
		if europa_qual.size() == 8:
			var euros_el: Array = EuropeanTeams.generate_europa(year, SEED_BASE + year * 23)
			europa_state = EuropeSecondarySimulator.run(europa_qual, euros_el, "Europa League", year, SEED_BASE * 19 + year)
		# Conference: 13-20 (los 8 últimos de Primera + 8 europeos del pool conference)
		# Estos son simbólicos — clubes "menores" pueden ganar Conference.
		var conf_qual: Array = spanish_by_pos.slice(12, 20)
		if conf_qual.size() == 8:
			var euros_cf: Array = EuropeanTeams.generate_conference(year, SEED_BASE + year * 29)
			conference_state = EuropeSecondarySimulator.run(conf_qual, euros_cf, "Conference League", year, SEED_BASE * 23 + year)

		# Modal Champions si el usuario está en top 4
		if champions_state != null and champions_state.champion_name != "":
			var user_in_ch: bool = false
			for tt: Team in top4:
				if tt.id == user_team_id:
					user_in_ch = true; break
			if user_in_ch:
				_show_champions_modal(champions_state)
			else:
				status_label.text = "🏆 Champions %d: %s campeón" % [year, champions_state.champion_name]
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
	# Cierre financiero de la temporada para todos los equipos
	_close_finances_for_all(cup_bracket, summer_result)
	# Ofertas de cambio de club al usuario tras temporada notable
	if user_team_id != "":
		_evaluate_manager_offers(cup_bracket)
	_start_season()


# Calcula y aplica el cierre financiero de la temporada para todos los teams.
# Muestra modal al usuario con su balance.
func _close_finances_for_all(cup_bracket: CupBracket, summer_result: TransferMarket.MarketResult) -> void:
	# Pre-calcular: posiciones liga, status copa, transfers per team
	var positions: Dictionary = {}  # team_id -> position
	var divisions: Dictionary = {}  # team_id -> division
	if primera_state.league_table != null:
		var sorted_p: Array = primera_state.league_table.sorted_rows()
		for i in sorted_p.size():
			positions[sorted_p[i].team_id] = i + 1
			divisions[sorted_p[i].team_id] = "primera"
	if segunda_state.league_table != null:
		var sorted_s: Array = segunda_state.league_table.sorted_rows()
		for i in sorted_s.size():
			positions[sorted_s[i].team_id] = i + 1
			divisions[sorted_s[i].team_id] = "segunda"
	# Cup status
	var cup_status: Dictionary = {}
	if cup_bracket != null:
		if cup_bracket.champion_id != "":
			cup_status[cup_bracket.champion_id] = "champion"
		if cup_bracket.rounds.size() > 0:
			var final_round: CupBracket.Round = cup_bracket.rounds[-1]
			if final_round.fixtures.size() == 1:
				var ffx: CupBracket.Fixture = final_round.fixtures[0]
				var loser_id: String = ffx.away_id if ffx.winner_id == ffx.home_id else ffx.home_id
				if loser_id != "":
					cup_status[loser_id] = "finalist"
	# Transfers per team
	var transfers_in: Dictionary = {}
	var transfers_out: Dictionary = {}
	if summer_result != null:
		for tr: TransferMarket.Transfer in summer_result.transfers:
			transfers_in[tr.to_team_id] = int(transfers_in.get(tr.to_team_id, 0)) + tr.fee_eur
			transfers_out[tr.from_team_id] = int(transfers_out.get(tr.from_team_id, 0)) + tr.fee_eur

	# Cerrar para cada equipo
	var user_summary: Dictionary = {}
	for t: Team in all_teams:
		var pos: int = int(positions.get(t.id, 20))
		var div: String = String(divisions.get(t.id, t.division))
		var cs: String = String(cup_status.get(t.id, ""))
		var summary: Dictionary = ClubFinances.close_season(
			t, year, div, pos, cs,
			champions_state, europa_state, conference_state,
			int(transfers_in.get(t.id, 0)),
			int(transfers_out.get(t.id, 0))
		)
		# Avanzar proyectos en curso (ej: ampliación que termina este año)
		ClubFinances.tick_projects(t, year + 1)
		if t.id == user_team_id:
			user_summary = summary

	if not user_summary.is_empty():
		_show_finance_balance_modal(user_summary)


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


# =========================================================================== #
# Ofertas de mánager (cambio de club entre temporadas)
# =========================================================================== #
func _evaluate_manager_offers(cup_bracket: CupBracket) -> void:
	var user_team := _find_team_by_id(user_team_id)
	if user_team == null:
		return

	var score: int = _compute_manager_score(user_team, cup_bracket)
	if score < 5:
		return  # rendimiento insuficiente para generar interés

	# Candidatos: clubes de Primera con reputación dentro de un rango razonable
	var candidates: Array = []
	for t: Team in all_teams:
		if t.id == user_team_id:
			continue
		if t.division != "primera":
			continue
		# El usuario solo recibe ofertas de equipos con rep similar o algo mayor
		# (no equipos mucho peores ni mucho mejores que él).
		var rep_diff: int = t.reputation - user_team.reputation
		if rep_diff < -5:
			continue  # equipo muy inferior al actual: no interesa al manager
		if rep_diff > 12 + score:
			continue  # equipo top que solo te ficharía con éxito enorme
		candidates.append(t)

	if candidates.is_empty():
		return

	# Mezclar y elegir 1-3 ofertas según score
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_BASE * 31 + year
	candidates.shuffle()
	var n_offers: int = 1
	if score >= 8:
		n_offers = min(3, candidates.size())
	elif score >= 6:
		n_offers = min(2, candidates.size())
	var offers: Array = candidates.slice(0, n_offers)

	_show_manager_offers_modal(user_team, offers, score)


func _compute_manager_score(user_team: Team, cup_bracket: CupBracket) -> int:
	var score: int = 0
	# Posición Liga
	var state: DivisionState = primera_state if user_team.division == "primera" else segunda_state
	if state.league_table != null:
		var sorted: Array = state.league_table.sorted_rows()
		for i in sorted.size():
			if sorted[i].team_id == user_team_id:
				var pos: int = i + 1
				if user_team.division == "primera":
					if pos == 1: score += 10
					elif pos == 2: score += 8
					elif pos == 3: score += 6
					elif pos == 4: score += 5
					elif pos <= 6: score += 3
					elif pos <= 10: score += 1
					elif pos >= 18: score -= 3
				else:
					# Segunda: ascender es muy notable
					if pos == 1: score += 9
					elif pos == 2: score += 7
					elif pos <= 6: score += 4  # zona playoff
				break
	# Copa
	if cup_bracket != null:
		if cup_bracket.champion_id == user_team_id:
			score += 5
		elif cup_bracket.rounds.size() > 0:
			var final_round: CupBracket.Round = cup_bracket.rounds[-1]
			if final_round.fixtures.size() == 1:
				var fx: CupBracket.Fixture = final_round.fixtures[0]
				if fx.home_id == user_team_id or fx.away_id == user_team_id:
					score += 3  # finalista
	# Champions (si jugó la temporada anterior, que se acaba de simular)
	if champions_state != null:
		if champions_state.champion_id == user_team_id:
			score += 8
		else:
			for r: ChampionsBracket.KORound in champions_state.ko_rounds:
				if r.name == "Final":
					for fx: ChampionsBracket.KOFixture in r.fixtures:
						if (fx.home_id == user_team_id or fx.away_id == user_team_id) and fx.winner_id != user_team_id:
							score += 4  # subcampeón
				elif r.name == "Semifinales":
					for fx: ChampionsBracket.KOFixture in r.fixtures:
						if (fx.home_id == user_team_id or fx.away_id == user_team_id) and fx.winner_id == user_team_id:
							score += 2  # llegó a final
				elif r.name == "Cuartos":
					for fx: ChampionsBracket.KOFixture in r.fixtures:
						if (fx.home_id == user_team_id or fx.away_id == user_team_id) and fx.winner_id == user_team_id:
							score += 1  # llegó a semis
	return score


func _show_manager_offers_modal(current_team: Team, offers: Array, score: int) -> void:
	var popup := AcceptDialog.new()
	popup.title = "📨 Ofertas de mánager"
	popup.size = Vector2(640, 480)
	popup.ok_button_text = "Quedarme en %s" % current_team.short_name
	add_child(popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	popup.add_child(box)

	var header := Label.new()
	header.text = "Tras la temporada en %s, otros clubes se interesan por ti." % current_team.name
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
	box.add_child(header)

	var subheader := Label.new()
	subheader.text = "Puntuación de tu temporada: %d. Cuanto mayor, mejores ofertas." % score
	subheader.add_theme_font_size_override("font_size", 11)
	subheader.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	box.add_child(subheader)

	box.add_child(HSeparator.new())

	for offer_team: Team in offers:
		box.add_child(_make_offer_row(current_team, offer_team, popup))

	box.add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "Si aceptas una oferta, dirigirás al nuevo club desde la próxima temporada.\nSi pulsas 'Quedarme', sigues en %s." % current_team.name
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(hint)

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()


func _make_offer_row(current_team: Team, offer_team: Team, popup: AcceptDialog) -> Control:
	var panel := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.18, 0.22)
	bg.border_color = Color(0.4, 0.45, 0.5)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 8
	bg.content_margin_right = 8
	bg.content_margin_top = 6
	bg.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", bg)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_label := Label.new()
	name_label.text = offer_team.name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	info.add_child(name_label)

	var stars: String = "★".repeat(int(offer_team.reputation / 20))
	var details := Label.new()
	details.text = "%s · %s · Reputación %d %s" % [
		offer_team.city, offer_team.division.capitalize(), offer_team.reputation, stars]
	details.add_theme_font_size_override("font_size", 11)
	details.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	info.add_child(details)

	var rep_diff: int = offer_team.reputation - current_team.reputation
	var diff_str: String = "(+%d rep)" % rep_diff if rep_diff > 0 else (
			"(%d rep)" % rep_diff if rep_diff < 0 else "(misma rep)")
	var diff_label := Label.new()
	diff_label.text = "vs tu club actual: %s" % diff_str
	diff_label.add_theme_font_size_override("font_size", 10)
	diff_label.add_theme_color_override("font_color",
			Color(0.7, 1.0, 0.7) if rep_diff > 0 else (Color(1.0, 0.7, 0.7) if rep_diff < 0 else Color(0.85, 0.85, 0.85)))
	info.add_child(diff_label)

	var accept_btn := Button.new()
	accept_btn.text = "✅ Aceptar"
	accept_btn.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	var offer_id: String = offer_team.id
	var offer_name: String = offer_team.name
	accept_btn.pressed.connect(func() -> void:
		_accept_manager_offer(offer_id, offer_name)
		popup.queue_free()
	)
	hbox.add_child(accept_btn)
	return panel


func _accept_manager_offer(new_team_id: String, new_team_name: String) -> void:
	var old_team := _find_team_by_id(user_team_id)
	user_team_id = new_team_id
	# Resetear alineación personal: el nuevo club tiene jugadores distintos
	user_lineup_template = {}
	_initialize_user_lineup()
	# Forzar refresco UI
	current_view = VIEW_HUB
	selected_team = null
	status_label.text = "✅ Has aceptado dirigir a %s%s" % [
			new_team_name,
			" (dejas %s)" % old_team.short_name if old_team else ""]
	_refresh_ui()


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
	if champions_state == null and europa_state == null and conference_state == null:
		var l := Label.new()
		l.text = "Aún no hay competiciones europeas activas.\nFinaliza una temporada (botón \"🔁 Nueva temp.\") para que se simule la edición siguiente."
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
	vbox.add_theme_constant_override("separation", 16)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Selector de competición (botones simples)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vbox.add_child(tabs)
	for opt in [["🏆 Champions", champions_state], ["⭐ Europa", europa_state], ["🥉 Conference", conference_state]]:
		var label_text: String = String(opt[0])
		var bracket = opt[1]
		var btn := Button.new()
		btn.text = label_text + ("  (%s)" % bracket.champion_name if (bracket != null and bracket.champion_name != "") else "")
		btn.flat = true
		btn.disabled = (bracket == null)
		btn.pressed.connect(func() -> void:
			selected_european_comp = label_text
			_refresh_ui()
		)
		tabs.add_child(btn)

	vbox.add_child(HSeparator.new())

	# Bracket activo: el seleccionado, o el primero disponible (Champions por defecto)
	var active_bracket: ChampionsBracket = champions_state
	if selected_european_comp.contains("Europa"): active_bracket = europa_state
	elif selected_european_comp.contains("Conference"): active_bracket = conference_state
	# Fallback si la seleccionada no existe
	if active_bracket == null:
		active_bracket = champions_state if champions_state != null else (europa_state if europa_state != null else conference_state)

	if active_bracket == null:
		return

	_render_european_bracket(vbox, active_bracket, selected_european_comp if selected_european_comp != "" else "🏆 Champions")


func _render_european_bracket(vbox: VBoxContainer, bracket: ChampionsBracket, comp_name: String) -> void:
	# Título + campeón
	var title := Label.new()
	title.text = "%s · %d-%d" % [comp_name, bracket.season_year, bracket.season_year + 1]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(title)

	if bracket.champion_name != "":
		var champ := Label.new()
		champ.text = "Campeón: %s   ·   Subcampeón: %s" % [bracket.champion_name, bracket.runner_up_name]
		champ.add_theme_color_override("font_color", Color(0.8, 1.0, 0.6))
		vbox.add_child(champ)

	# Fase de grupos (solo en Champions)
	if not bracket.groups.is_empty():
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

		for g: ChampionsBracket.Group in bracket.groups:
			var gbox := VBoxContainer.new()
			var gh := Label.new()
			gh.text = "Grupo %s" % g.letter
			gh.add_theme_font_size_override("font_size", 13)
			gh.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
			gbox.add_child(gh)
			var grid := GridContainer.new()
			grid.columns = 6
			grid.add_theme_constant_override("h_separation", 8)
			for h_text in ["Pos", "Equipo", "PJ", "Pts", "GF", "GC"]:
				var hl := Label.new()
				hl.text = h_text
				hl.add_theme_font_size_override("font_size", 11)
				hl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
				grid.add_child(hl)
			var standings: Array = g.sorted_standings()
			for i in standings.size():
				var st: ChampionsBracket.GroupStanding = standings[i]
				var color: Color = Color(0.7, 1.0, 0.7) if i < 2 else Color(0.85, 0.85, 0.85)
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

	for r: ChampionsBracket.KORound in bracket.ko_rounds:
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
			var date_str: String = ""
			if fx.match_date.size() > 0:
				date_str = "[%s] " % DateUtil.format_short(fx.match_date)
			line.text = "  %s%s %s %s%s%s" % [date_str, fx.home_name, score, fx.away_name, winner_short, rep]
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
# =========================================================================== #
# Vista: 💰 Finanzas (presupuesto, salarios, balance del club del usuario)
# =========================================================================== #
func _render_finances_view() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_area.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	if user_team_id == "":
		var l := Label.new()
		l.text = "No has elegido un club. Vuelve al menú principal y empieza Nueva partida."
		l.add_theme_font_size_override("font_size", 14)
		box.add_child(l)
		return

	var team := _find_team_by_id(user_team_id)
	if team == null or team.finances == null:
		return

	# Cabecera
	var title := Label.new()
	title.text = "💰 Finanzas — %s · Temporada %d-%d" % [team.name, year, year + 1]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	box.add_child(title)

	# Caja actual destacada
	var cash_label := Label.new()
	cash_label.text = "💵 Caja: %s €" % TransferMarket._fmt_eur(team.finances.cash_balance)
	cash_label.add_theme_font_size_override("font_size", 22)
	cash_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7) if team.finances.cash_balance >= 0 else Color(1.0, 0.55, 0.55))
	box.add_child(cash_label)

	# Última temporada (resumen)
	var summary: Dictionary = team.finances.last_season_summary
	if not summary.is_empty():
		_finances_section_header(box, "📊 Última temporada (%d-%d)" % [int(summary.get("year", 0)), int(summary.get("year", 0)) + 1])
		var income: Dictionary = summary.get("income", {})
		var expense: Dictionary = summary.get("expense", {})
		var sub_grid := GridContainer.new()
		sub_grid.columns = 4
		sub_grid.add_theme_constant_override("h_separation", 20)
		box.add_child(sub_grid)
		# Ingresos
		_make_subheader(sub_grid, "Ingresos", Color(0.7, 1.0, 0.7))
		_make_subheader(sub_grid, "", Color.WHITE)
		_make_subheader(sub_grid, "Gastos", Color(1.0, 0.7, 0.7))
		_make_subheader(sub_grid, "", Color.WHITE)
		_finance_pair(sub_grid, "Matchday (entradas)", int(income.get("matchday", 0)),
			"Salarios", int(expense.get("salaries", 0)))
		_finance_pair(sub_grid, "TV", int(income.get("tv", 0)),
			"Mantenimiento estadio", int(expense.get("stadium_maintenance", 0)))
		_finance_pair(sub_grid, "Patrocinadores", int(income.get("sponsors", 0)),
			"Personal técnico", int(expense.get("staff", 0)))
		_finance_pair(sub_grid, "Premios competiciones", int(income.get("prizes", 0)),
			"Fichajes (gasto)", int(expense.get("transfers_out", 0)))
		_finance_pair(sub_grid, "Ventas (ingreso)", int(income.get("transfers_in", 0)),
			"", 0)
		_finance_pair(sub_grid, "TOTAL", int(income.get("total", 0)),
			"TOTAL", int(expense.get("total", 0)))
		var net_label := Label.new()
		var net_v: int = int(summary.get("net", 0))
		net_label.text = "Balance neto: %s €" % TransferMarket._fmt_eur(net_v)
		net_label.add_theme_font_size_override("font_size", 14)
		net_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if net_v >= 0 else Color(1.0, 0.6, 0.6))
		box.add_child(net_label)
		# Premios desglose
		var pb: Dictionary = income.get("prize_breakdown", {})
		if not pb.is_empty():
			var pb_label := Label.new()
			var parts: Array = []
			for k in ["liga", "copa", "champions", "europa", "conference"]:
				var v: int = int(pb.get(k, 0))
				if v > 0:
					parts.append("%s: %s" % [k.capitalize(), TransferMarket._fmt_eur(v)])
			if parts.size() > 0:
				pb_label.text = "  Premios: " + " · ".join(parts)
				pb_label.add_theme_font_size_override("font_size", 11)
				pb_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
				box.add_child(pb_label)

	# Estadio
	_finances_section_header(box, "🏟 Estadio")
	if team.stadium != null:
		var stad_grid := GridContainer.new()
		stad_grid.columns = 2
		stad_grid.add_theme_constant_override("h_separation", 20)
		box.add_child(stad_grid)
		_simple_row(stad_grid, "Nombre", team.stadium.name)
		_simple_row(stad_grid, "Capacidad", "%d asientos" % team.stadium.capacity)
		_simple_row(stad_grid, "Tier", "★".repeat(team.stadium.tier) + " (%d/5)" % team.stadium.tier)
		_simple_row(stad_grid, "Estado", "%.0f / 100" % team.stadium.state)
		_simple_row(stad_grid, "Ticket base", "%d €" % team.stadium.base_ticket_price())
		var upg: String = "ninguna" if team.stadium.upgrades.is_empty() else ", ".join(team.stadium.upgrades)
		_simple_row(stad_grid, "Mejoras", upg)

		# Botones de mejora
		var btn_box := HBoxContainer.new()
		btn_box.add_theme_constant_override("separation", 6)
		box.add_child(btn_box)
		for action in [
			["📐 Ampliar +5000 (30M, 1 temp.)", "stadium_expansion", 30_000_000],
			["⬆ Subir tier (45M, 1 temp.)", "stadium_tier_up", 45_000_000],
			["🌱 Césped híbrido (4M)", "upgrade_pitch", 4_000_000],
			["🥂 Palcos VIP (10M)", "upgrade_vip", 10_000_000],
			["🏛 Museo (3M)", "upgrade_museum", 3_000_000],
			["🎓 Academia premium (50M, 2 temp.)", "academia_premium", 50_000_000],
			["💪 Gimnasio top (15M)", "gimnasio_top", 15_000_000],
		]:
			var b := Button.new()
			b.text = String(action[0])
			b.tooltip_text = "Cuesta %s €" % TransferMarket._fmt_eur(int(action[2]))
			var atype: String = String(action[1])
			var cost: int = int(action[2])
			b.disabled = team.finances.cash_balance < cost or _has_active_project(team, atype) or _has_upgrade(team, atype)
			b.pressed.connect(func() -> void: _on_buy_stadium_upgrade(team, atype, cost))
			btn_box.add_child(b)

		# Proyectos en curso
		if not team.finances.ongoing_projects.is_empty():
			var oproj_label := Label.new()
			oproj_label.text = "Proyectos en curso:"
			oproj_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
			box.add_child(oproj_label)
			for proj in team.finances.ongoing_projects:
				var pl := Label.new()
				pl.text = "  • %s (termina %d)" % [String(proj.get("type", "?")), int(proj.get("completes_year", 0))]
				pl.add_theme_font_size_override("font_size", 11)
				box.add_child(pl)

	# Personal técnico
	_finances_section_header(box, "👔 Cuerpo técnico")
	if team.staff != null:
		var staff_grid := GridContainer.new()
		staff_grid.columns = 4
		staff_grid.add_theme_constant_override("h_separation", 12)
		box.add_child(staff_grid)
		# Cabecera
		for h in ["Rol", "Calidad", "Salario", "Mejorar"]:
			var hl := Label.new()
			hl.text = h
			hl.add_theme_font_size_override("font_size", 11)
			hl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
			staff_grid.add_child(hl)
		var roles := [
			["Preparador físico", "fitness_coach", team.staff.fitness_coach],
			["Jefe de scouting", "scout_chief", team.staff.scout_chief],
			["Coach cantera", "youth_coach", team.staff.youth_coach],
			["Fisioterapeuta", "physio", team.staff.physio],
		]
		for r in roles:
			var role_label: String = String(r[0])
			var role_key: String = String(r[1])
			var q: int = int(r[2])
			var rl := Label.new()
			rl.text = role_label
			rl.add_theme_font_size_override("font_size", 11)
			staff_grid.add_child(rl)
			var ql := Label.new()
			ql.text = "★".repeat(q) + "☆".repeat(5 - q) + "  (%d/5)" % q
			ql.add_theme_font_size_override("font_size", 11)
			ql.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
			staff_grid.add_child(ql)
			var sl := Label.new()
			sl.text = "%s €/año" % TransferMarket._fmt_eur(StaffInfo.salary_for_quality(q))
			sl.add_theme_font_size_override("font_size", 11)
			staff_grid.add_child(sl)
			if q >= 5:
				var maxed := Label.new()
				maxed.text = "MAX"
				maxed.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
				staff_grid.add_child(maxed)
			else:
				var cost: int = StaffInfo.upgrade_cost(q)
				var btn := Button.new()
				btn.text = "↑ %s €" % TransferMarket._fmt_eur(cost)
				btn.disabled = team.finances.cash_balance < cost
				btn.tooltip_text = "Subir a calidad %d" % (q + 1)
				btn.pressed.connect(func() -> void: _on_upgrade_staff(team, role_key, cost))
				staff_grid.add_child(btn)

	# Patrocinadores
	_finances_section_header(box, "💼 Patrocinadores")
	if team.finances.sponsors.is_empty():
		var none_label := Label.new()
		none_label.text = "  (sin patrocinadores activos)"
		none_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		box.add_child(none_label)
	else:
		for sp in team.finances.sponsors:
			var sl := Label.new()
			sl.text = "  • %s — %s — %s €/año (hasta %d)" % [
				String(sp.get("type", "?")).capitalize().replace("_", " "),
				String(sp.get("sponsor_name", "?")),
				TransferMarket._fmt_eur(int(sp.get("amount_per_year", 0))),
				int(sp.get("until_year", 0)),
			]
			sl.add_theme_font_size_override("font_size", 11)
			box.add_child(sl)
	# Botón buscar patrocinador
	if team.finances.sponsors.size() < 4:
		var find_btn := Button.new()
		find_btn.text = "🔍 Buscar nuevo patrocinador"
		find_btn.tooltip_text = "Negocia un patrocinador adicional. Coste: 500K €"
		find_btn.disabled = team.finances.cash_balance < 500_000
		find_btn.pressed.connect(func() -> void: _on_search_sponsor(team))
		box.add_child(find_btn)

	# Plantilla: salarios + valor (compactado)
	_finances_section_header(box, "👥 Plantilla")
	var grid_squad := GridContainer.new()
	grid_squad.columns = 2
	grid_squad.add_theme_constant_override("h_separation", 24)
	box.add_child(grid_squad)
	var total_salary: int = 0
	for p: Player in team.players:
		if p.contract != null:
			total_salary += p.contract.salary_eur_year
	var total_value: int = 0
	for p: Player in team.players:
		total_value += MarketValue.compute(p, year, "")
	_finances_row(grid_squad, "Salarios totales / año", total_salary)
	_finances_row(grid_squad, "Tope salarial", team.finances.wage_budget_eur_year)
	_finances_row(grid_squad, "Margen sobre tope", team.finances.wage_budget_eur_year - total_salary)
	_finances_row(grid_squad, "Valor de mercado total", total_value)
	_finances_row(grid_squad, "Presupuesto fichajes próximo verano", team.finances.budget_transfers_eur)


func _finances_section_header(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	box.add_child(l)


func _make_subheader(grid: GridContainer, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	grid.add_child(l)


func _simple_row(grid: GridContainer, label: String, value: String) -> void:
	var l1 := Label.new()
	l1.text = label
	l1.add_theme_font_size_override("font_size", 12)
	grid.add_child(l1)
	var l2 := Label.new()
	l2.text = value
	l2.add_theme_font_size_override("font_size", 12)
	l2.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	grid.add_child(l2)


func _finance_pair(grid: GridContainer, label_in: String, amount_in: int, label_out: String, amount_out: int) -> void:
	# 4 columnas: label_in | amount_in | label_out | amount_out
	var l1 := Label.new()
	l1.text = label_in
	l1.add_theme_font_size_override("font_size", 11)
	grid.add_child(l1)
	var l2 := Label.new()
	l2.text = "%s €" % TransferMarket._fmt_eur(amount_in) if amount_in > 0 else ""
	l2.add_theme_font_size_override("font_size", 11)
	l2.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(l2)
	var l3 := Label.new()
	l3.text = label_out
	l3.add_theme_font_size_override("font_size", 11)
	grid.add_child(l3)
	var l4 := Label.new()
	l4.text = "%s €" % TransferMarket._fmt_eur(amount_out) if amount_out > 0 else ""
	l4.add_theme_font_size_override("font_size", 11)
	l4.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7))
	l4.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(l4)


func _has_active_project(team: Team, type: String) -> bool:
	for p in team.finances.ongoing_projects:
		if String(p.get("type", "")) == type:
			return true
	return false


func _has_upgrade(team: Team, type: String) -> bool:
	if team.stadium == null:
		return false
	match type:
		"upgrade_pitch": return "cesped_hibrido" in team.stadium.upgrades
		"upgrade_vip":   return "palcos_vip" in team.stadium.upgrades
		"upgrade_museum": return "museo" in team.stadium.upgrades
		"academia_premium": return "academia_premium" in team.stadium.upgrades
		"gimnasio_top": return "gimnasio_top" in team.stadium.upgrades
		_: return false


func _on_buy_stadium_upgrade(team: Team, type: String, cost: int) -> void:
	if team.finances == null or team.finances.cash_balance < cost:
		status_label.text = "❌ No tienes caja suficiente para esta mejora."
		return
	team.finances.cash_balance -= cost
	# Proyectos multi-temporada
	if type == "stadium_expansion" or type == "stadium_tier_up":
		var proj: Dictionary = {
			"type": type,
			"completes_year": year + 1,
			"capacity_add": 5000,
		}
		team.finances.ongoing_projects.append(proj)
		status_label.text = "🏗 Proyecto iniciado: termina la próxima temporada."
	elif type == "academia_premium":
		var proj: Dictionary = {
			"type": type,
			"completes_year": year + 2,
		}
		team.finances.ongoing_projects.append(proj)
		status_label.text = "🎓 Academia premium en construcción (2 temporadas)."
	else:
		# Mejoras inmediatas (cesped/palcos/museo/gimnasio): aplicar ya
		ClubFinances._apply_project_effect(team, { "type": type })
		status_label.text = "✅ Mejora aplicada al estadio."
	_refresh_ui()


func _on_upgrade_staff(team: Team, role: String, cost: int) -> void:
	if team.staff == null or team.finances == null:
		return
	if team.finances.cash_balance < cost:
		status_label.text = "❌ Sin caja para mejorar el staff."
		return
	team.finances.cash_balance -= cost
	match role:
		"fitness_coach": team.staff.fitness_coach += 1
		"scout_chief":   team.staff.scout_chief += 1
		"youth_coach":   team.staff.youth_coach += 1
		"physio":        team.staff.physio += 1
	status_label.text = "✅ Staff mejorado."
	_refresh_ui()


func _on_search_sponsor(team: Team) -> void:
	if team.finances == null or team.finances.cash_balance < 500_000:
		return
	team.finances.cash_balance -= 500_000
	# Buscar un slot libre
	var existing_types: Dictionary = {}
	for sp in team.finances.sponsors:
		existing_types[String(sp.get("type", ""))] = true
	var available_types: Array = ["kit_main", "kit_sleeve", "training", "naming"]
	var chosen_type: String = ""
	for t_type in available_types:
		if not existing_types.has(t_type):
			chosen_type = t_type
			break
	if chosen_type == "":
		# Renovar el de menor amount con mejora 10%
		var lowest_idx: int = 0
		var lowest_amount: int = 999_999_999
		for i in team.finances.sponsors.size():
			var a: int = int(team.finances.sponsors[i].get("amount_per_year", 0))
			if a < lowest_amount:
				lowest_amount = a
				lowest_idx = i
		var sp: Dictionary = team.finances.sponsors[lowest_idx]
		sp["amount_per_year"] = int(float(lowest_amount) * 1.10)
		sp["until_year"] = year + 3
		status_label.text = "✅ Renovado %s con +10%% incremento." % String(sp.get("sponsor_name", "?"))
	else:
		var rep: int = team.reputation
		team.finances.sponsors.append({
			"type": chosen_type,
			"sponsor_name": ClubFinances._sponsor_name_for_tier(rep),
			"amount_per_year": ClubFinances._sponsor_amount(chosen_type, rep),
			"until_year": year + 3,
		})
		status_label.text = "✅ Nuevo patrocinador: %s" % chosen_type.capitalize().replace("_", " ")
	_refresh_ui()


# Modal de balance fin de temporada para el usuario
func _show_finance_balance_modal(summary: Dictionary) -> void:
	var popup := AcceptDialog.new()
	popup.title = "💰 Balance temporada %d-%d" % [int(summary.get("year", 0)), int(summary.get("year", 0)) + 1]
	popup.size = Vector2(620, 460)
	popup.ok_button_text = "Continuar"
	add_child(popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	popup.add_child(box)

	var income: Dictionary = summary.get("income", {})
	var expense: Dictionary = summary.get("expense", {})

	var net_v: int = int(summary.get("net", 0))
	var net_label := Label.new()
	net_label.text = "%s %s €" % ["📈" if net_v >= 0 else "📉", TransferMarket._fmt_eur(net_v)]
	net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	net_label.add_theme_font_size_override("font_size", 22)
	net_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if net_v >= 0 else Color(1.0, 0.6, 0.6))
	box.add_child(net_label)
	var cash_after_label := Label.new()
	cash_after_label.text = "Caja tras la temporada: %s €" % TransferMarket._fmt_eur(int(summary.get("cash_balance_after", 0)))
	cash_after_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cash_after_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	box.add_child(cash_after_label)

	box.add_child(HSeparator.new())

	var income_label := Label.new()
	income_label.text = "📈 Ingresos: %s €" % TransferMarket._fmt_eur(int(income.get("total", 0)))
	income_label.add_theme_font_size_override("font_size", 14)
	income_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	box.add_child(income_label)
	for k in [["Matchday", "matchday"], ["TV", "tv"], ["Patrocinadores", "sponsors"], ["Premios", "prizes"], ["Ventas", "transfers_in"]]:
		var v: int = int(income.get(String(k[1]), 0))
		var l := Label.new()
		l.text = "    %s: %s €" % [String(k[0]), TransferMarket._fmt_eur(v)]
		l.add_theme_font_size_override("font_size", 11)
		box.add_child(l)

	var expense_label := Label.new()
	expense_label.text = "📉 Gastos: %s €" % TransferMarket._fmt_eur(int(expense.get("total", 0)))
	expense_label.add_theme_font_size_override("font_size", 14)
	expense_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7))
	box.add_child(expense_label)
	for k in [["Salarios", "salaries"], ["Mantenimiento estadio", "stadium_maintenance"], ["Personal técnico", "staff"], ["Compras", "transfers_out"]]:
		var v: int = int(expense.get(String(k[1]), 0))
		var l := Label.new()
		l.text = "    %s: %s €" % [String(k[0]), TransferMarket._fmt_eur(v)]
		l.add_theme_font_size_override("font_size", 11)
		box.add_child(l)

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered()


func _finances_row(grid: GridContainer, label: String, amount: int) -> void:
	var l1 := Label.new()
	l1.text = label
	l1.add_theme_font_size_override("font_size", 12)
	grid.add_child(l1)
	var l2 := Label.new()
	l2.text = "%s €" % TransferMarket._fmt_eur(amount)
	l2.add_theme_font_size_override("font_size", 12)
	l2.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7) if amount >= 0 else Color(1.0, 0.7, 0.7))
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(l2)


# =========================================================================== #
# Vista: 📅 Calendario (todas las jornadas con resultados)
# =========================================================================== #
func _render_calendar_view() -> void:
	var st := _current_state()
	if st.calendar.is_empty():
		var l := Label.new()
		l.text = "No hay calendario disponible."
		content_area.add_child(l)
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_area.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "📅 Calendario %s · Temporada %d-%d" % [
		selected_division.capitalize(), year, year + 1]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(title)

	# Por cada jornada: encabezado + 10 partidos
	for j_idx in st.calendar.size():
		var jornada: Array = st.calendar[j_idx]
		var played: bool = j_idx < st.current_jornada
		# Rango de fechas de la jornada (primer y último fixture por fecha)
		var date_range: String = ""
		if jornada.size() > 0 and jornada[0].has("match_date"):
			var first_date: Dictionary = jornada[0]["match_date"]
			var last_date: Dictionary = jornada[-1]["match_date"]
			if DateUtil.compare(first_date, last_date) == 0:
				date_range = " · %s" % DateUtil.format_short(first_date)
			else:
				date_range = " · %s — %s" % [
					DateUtil.format_short(first_date),
					DateUtil.format_short(last_date),
				]
		var header := Label.new()
		header.text = "── Jornada %d%s %s──" % [j_idx + 1, date_range, "(jugada) " if played else ""]
		header.add_theme_font_size_override("font_size", 13)
		var hdr_color: Color = Color(0.85, 0.85, 0.85) if played else Color(0.5, 0.5, 0.5)
		# Marcar jornada actual
		if j_idx == st.current_jornada:
			hdr_color = Color(1.0, 0.85, 0.2)
			header.text = "── Jornada %d%s (próxima) ──" % [j_idx + 1, date_range]
		header.add_theme_color_override("font_color", hdr_color)
		vbox.add_child(header)

		for fixture: Dictionary in jornada:
			var home_id: String = String(fixture["home_id"])
			var away_id: String = String(fixture["away_id"])
			var home: Team = _find_team_by_id(home_id)
			var away: Team = _find_team_by_id(away_id)
			if home == null or away == null:
				continue
			var line := Label.new()
			var is_user: bool = home_id == user_team_id or away_id == user_team_id
			var prefix: String = "▶ " if is_user else "  "
			# Fecha real del partido
			var date_str: String = ""
			if fixture.has("match_date"):
				date_str = "[%s] " % DateUtil.format_short(fixture["match_date"])
			line.text = "%s%s%-28s vs %-28s" % [prefix, date_str, home.name.left(28), away.name.left(28)]
			line.add_theme_font_size_override("font_size", 11)
			if is_user:
				line.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
			elif played:
				line.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			vbox.add_child(line)


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
			# Stats de jugador por temporada: matches + minutos (titulares = 90 min)
			for p: Player in home_lineup.starting_eleven:
				p.season_matches += 1
				p.season_minutes += 90
			for p: Player in away_lineup.starting_eleven:
				p.season_matches += 1
				p.season_minutes += 90
			# Goles
			for pid in result.scorers.keys():
				var goals: int = int(result.scorers[pid])
				var pgoal: Player = _find_player_globally(pid)
				if pgoal != null:
					pgoal.season_goals += goals
				if not state.season_scorers.has(pid):
					var team_short: String = ""
					for t: Team in state.teams:
						if t.find_player(pid) != null:
							team_short = t.short_name
							break
					state.season_scorers[pid] = {
						"name": pgoal.name if pgoal else pid,
						"team_short": team_short,
						"goals": 0,
					}
				state.season_scorers[pid]["goals"] += goals
			# Asistencias (de los eventos GOAL con secondary_player_id)
			for ev: MatchEvent in result.events:
				if ev.type == MatchEvent.T_GOAL and ev.secondary_player_id != "":
					var passist: Player = _find_player_globally(ev.secondary_player_id)
					if passist != null:
						passist.season_assists += 1
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
	primera_state.calendar = CalendarGenerator.generate_with_dates(primera_ids, year, SEED_BASE, [])
	segunda_state.calendar = CalendarGenerator.generate_with_dates(segunda_ids, year, SEED_BASE + 1, [])
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
	# Si la save está mid-season tras la jornada 19, asumimos que el winter
	# market ya se ejecutó. Evita disparo duplicado al avanzar jornadas.
	winter_market_done = (save_data.primera_jornada >= 19)

	current_view = VIEW_HUB
	selected_team = null
	selected_match = null
	status_label.text = "Partida cargada — %s, jornada %d" % [save_data.saved_at, save_data.primera_jornada]
	_refresh_ui()


# =========================================================================== #
# Navegación
# =========================================================================== #
func _on_select_division(div: String) -> void:
	selected_division = div
	# Si estábamos en una vista contextual a un equipo/partido, volvemos al hub
	if current_view in [VIEW_TEAM, VIEW_MATCH]:
		current_view = VIEW_HUB
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

	# Modo HUB: ocultar TODA la chrome antigua (header, tabs, footer global)
	# — el hub tiene su propia cabecera/centro/footer.
	# Sub-vistas: header reducido (botón Hub + título de la vista) + footer
	# global con status + acciones. Las tabs viejas se ocultan SIEMPRE.
	var in_hub: bool = (current_view == VIEW_HUB)
	if top_header_box != null:
		top_header_box.visible = not in_hub
	if div_tabs_box != null:
		div_tabs_box.visible = false  # las tabs se eliminan del flujo
	if view_tabs_box != null:
		view_tabs_box.visible = false
	if top_header_separator != null:
		top_header_separator.visible = not in_hub
	if footer_global_box != null:
		footer_global_box.visible = not in_hub
	if view_title_label != null:
		view_title_label.text = _view_title_for(current_view)

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
		VIEW_HUB: _render_hub_view()
		VIEW_TABLE: _render_table_view()
		VIEW_FIXTURES: _render_fixtures_view()
		VIEW_TEAM: _render_team_view()
		VIEW_MATCH: _render_match_view()
		VIEW_TACTICS: _render_tactics_view()
		VIEW_MARKET: _render_market_view()
		VIEW_CAREER: _render_career_view()
		VIEW_CHAMPIONS: _render_champions_view()
		VIEW_FINANCES: _render_finances_view()
		VIEW_CALENDAR: _render_calendar_view()
		VIEW_RIVAL: _render_rival_view()
		VIEW_DECISIONS: _render_decisions_view()
		VIEW_EMPLOYEES: _render_employees_view()


# --------------------------------------------------------------------------- #
# Vista: Clasificación
# --------------------------------------------------------------------------- #
# =========================================================================== #
# Vista: 🏠 HUB principal estilo PC Manager
# =========================================================================== #
# 4 cuadrantes: Seguimiento (verde) | Entrenador (azul)
#               Mercado    (rojo)   | Finanzas   (marrón)
# Centro: tu equipo + próximo rival
func _render_hub_view() -> void:
	var team := _find_team_by_id(user_team_id) if user_team_id != "" else null

	# Layout principal: VBox con header + (HBox con cuadrantes) + footer
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	content_area.add_child(root)

	# === HEADER ===
	var header := PanelContainer.new()
	var header_bg := StyleBoxFlat.new()
	header_bg.bg_color = Color(0.10, 0.13, 0.18)
	header_bg.border_color = Color(0.4, 0.5, 0.6)
	header_bg.set_border_width_all(1)
	header_bg.content_margin_left = 12
	header_bg.content_margin_right = 12
	header_bg.content_margin_top = 8
	header_bg.content_margin_bottom = 8
	header.add_theme_stylebox_override("panel", header_bg)
	root.add_child(header)
	var header_h := HBoxContainer.new()
	header_h.add_theme_constant_override("separation", 16)
	header.add_child(header_h)
	# Logo + nombre equipo
	var team_box := HBoxContainer.new()
	team_box.add_theme_constant_override("separation", 8)
	header_h.add_child(team_box)
	if team != null:
		var logo := _make_team_logo(team, 48)
		team_box.add_child(logo)
		var team_label := Label.new()
		team_label.text = team.name
		team_label.add_theme_font_size_override("font_size", 18)
		team_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
		team_box.add_child(team_label)
	else:
		var team_label := Label.new()
		team_label.text = "(sin club)"
		team_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		team_box.add_child(team_label)
	# Spacer
	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_h.add_child(sp1)
	# Título
	var title := Label.new()
	title.text = "MENU PROMANAGER"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	header_h.add_child(title)
	# Spacer 2
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_h.add_child(sp2)
	# Toggle de división (Primera / Segunda) — para ver clasificación de la otra
	var div_toggle := HBoxContainer.new()
	div_toggle.add_theme_constant_override("separation", 4)
	header_h.add_child(div_toggle)
	for div_data in [["1ª", "primera"], ["2ª", "segunda"]]:
		var div_label: String = String(div_data[0])
		var div_id: String = String(div_data[1])
		var b := Button.new()
		b.text = div_label
		b.flat = (selected_division != div_id)
		b.disabled = (selected_division == div_id)
		b.tooltip_text = "Ver datos de %s división" % ("Primera" if div_id == "primera" else "Segunda")
		b.pressed.connect(_on_select_division.bind(div_id))
		div_toggle.add_child(b)

	# Fecha + jornada + competición
	var info_v := VBoxContainer.new()
	header_h.add_child(info_v)
	var jornada_lbl := Label.new()
	jornada_lbl.text = "Liga %s · Jornada %d" % [
		"1ª" if selected_division == "primera" else "2ª",
		_current_state().current_jornada + 1,
	]
	jornada_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	jornada_lbl.add_theme_font_size_override("font_size", 13)
	jornada_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	info_v.add_child(jornada_lbl)
	var year_lbl := Label.new()
	year_lbl.text = "Temporada %d-%d" % [year, year + 1]
	year_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	year_lbl.add_theme_font_size_override("font_size", 11)
	year_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	info_v.add_child(year_lbl)

	# === CUERPO: 4 cuadrantes + centro ===
	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	# Columna izquierda
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 0)
	body.add_child(left_col)
	# Cuadrante: SEGUIMIENTO (verde)
	left_col.add_child(_make_quadrant("SEGUIMIENTO", Color(0.32, 0.62, 0.30), [
		["📊", "RESULTADOS", "Última jornada con resultados", _on_select_view.bind(VIEW_FIXTURES)],
		["🏆", "CLASIFICACIÓN", "Tabla actual de Liga", _on_select_view.bind(VIEW_TABLE)],
		["📅", "CALENDARIO", "Calendario completo de la temporada", _on_select_view.bind(VIEW_CALENDAR)],
	]))
	# Cuadrante: MERCADO (rojo)
	left_col.add_child(_make_quadrant("MERCADO", Color(0.75, 0.25, 0.25), [
		["💸", "FICHAR", "Mercado de fichajes", _on_select_view.bind(VIEW_MARKET)],
		["👥", "PLANTILLA", "Tu plantilla con stats", _on_select_view.bind(VIEW_TEAM)],
		["👔", "EMPLEADOS", "Organigrama del club (cuerpo técnico, ojeo, médico, cantera, dirección)", _on_select_view.bind(VIEW_EMPLOYEES)],
	]))

	# Columna central — escudo grande + próximo rival
	var center_col := VBoxContainer.new()
	center_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_col.alignment = BoxContainer.ALIGNMENT_CENTER
	center_col.custom_minimum_size = Vector2(200, 0)
	body.add_child(center_col)
	if team != null:
		# Tu equipo: escudo grande
		center_col.add_child(_make_spacer(20))
		var your_logo := _make_team_logo(team, 96)
		var your_logo_box := CenterContainer.new()
		your_logo_box.add_child(your_logo)
		center_col.add_child(your_logo_box)
		var your_name := Label.new()
		your_name.text = team.short_name
		your_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		your_name.add_theme_font_size_override("font_size", 14)
		your_name.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
		center_col.add_child(your_name)
		# Próximo rival
		var rival: Team = _find_next_rival(team)
		if rival != null:
			# Fecha del próximo partido del usuario
			var next_date_str: String = _user_next_match_date_str(team)
			var vs_label := Label.new()
			vs_label.text = "── próximo rival%s ──" % (" · " + next_date_str if next_date_str != "" else "")
			vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vs_label.add_theme_font_size_override("font_size", 11)
			vs_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			center_col.add_child(vs_label)
			var rival_logo := _make_team_logo(rival, 64)
			var rival_logo_box := CenterContainer.new()
			rival_logo_box.add_child(rival_logo)
			center_col.add_child(rival_logo_box)
			var rival_name := Label.new()
			rival_name.text = rival.short_name
			rival_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rival_name.add_theme_font_size_override("font_size", 12)
			center_col.add_child(rival_name)
		# Caja
		if team.finances != null:
			center_col.add_child(_make_spacer(10))
			var cash_label := Label.new()
			cash_label.text = "💵 %s €" % TransferMarket._fmt_eur(team.finances.cash_balance)
			cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cash_label.add_theme_font_size_override("font_size", 13)
			cash_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7) if team.finances.cash_balance >= 0 else Color(1.0, 0.6, 0.6))
			center_col.add_child(cash_label)

	# Columna derecha
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 0)
	body.add_child(right_col)
	# Cuadrante: ENTRENADOR (azul)
	right_col.add_child(_make_quadrant("ENTRENADOR", Color(0.25, 0.45, 0.80), [
		["🎯", "ALINEACIÓN", "Define tu once y formación", _on_select_view.bind(VIEW_TACTICS)],
		["📋", "TÁCTICAS", "Mentalidad, presión, tempo", _on_select_view.bind(VIEW_TACTICS)],
		["🔍", "VER RIVAL", "Información del próximo rival", _on_select_view.bind(VIEW_RIVAL)],
	]))
	# Cuadrante: FINANZAS (marrón/dorado)
	right_col.add_child(_make_quadrant("FINANZAS", Color(0.65, 0.45, 0.20), [
		["💰", "CAJA", "Balance, ingresos, gastos", _on_select_view.bind(VIEW_FINANCES)],
		["⚖", "DECISIONES", "Objetivo, sponsors, carrera", _on_select_view.bind(VIEW_DECISIONS)],
		["🏟", "ESTADIO", "Mejoras y ampliaciones", _on_select_view.bind(VIEW_FINANCES)],
	]))

	# === STATUS BAR (encima del footer) ===
	# Muestra el último mensaje de status_label (compartido con sub-vistas).
	var status_panel := PanelContainer.new()
	var status_bg := StyleBoxFlat.new()
	status_bg.bg_color = Color(0.08, 0.10, 0.14)
	status_bg.content_margin_left = 12
	status_bg.content_margin_right = 12
	status_bg.content_margin_top = 4
	status_bg.content_margin_bottom = 4
	status_panel.add_theme_stylebox_override("panel", status_bg)
	root.add_child(status_panel)
	var status_mirror := Label.new()
	status_mirror.text = status_label.text if status_label != null else ""
	status_mirror.add_theme_font_size_override("font_size", 11)
	status_mirror.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	status_panel.add_child(status_mirror)

	# === FOOTER ===
	var footer_p := PanelContainer.new()
	var footer_bg := StyleBoxFlat.new()
	footer_bg.bg_color = Color(0.10, 0.13, 0.18)
	footer_bg.set_border_width_all(1)
	footer_bg.border_color = Color(0.4, 0.5, 0.6)
	footer_bg.content_margin_left = 8
	footer_bg.content_margin_right = 8
	footer_bg.content_margin_top = 6
	footer_bg.content_margin_bottom = 6
	footer_p.add_theme_stylebox_override("panel", footer_bg)
	root.add_child(footer_p)
	var footer_h := HBoxContainer.new()
	footer_h.add_theme_constant_override("separation", 8)
	footer_p.add_child(footer_h)
	# Botones izquierda
	for b_data in [
		["🚪 SALIR", _on_back_to_menu],
		["💾 GUARDAR", _on_save_game],
		["📂 CARGAR", _on_load_game],
		["📰 NOTICIAS", _on_select_view.bind(VIEW_CAREER)],
	]:
		var b := Button.new()
		b.text = String(b_data[0])
		b.pressed.connect(Callable(b_data[1]))
		footer_h.add_child(b)
	# Spacer
	var sp_f := Control.new()
	sp_f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_h.add_child(sp_f)
	# Boton SEGUIR (avanzar jornada) destacado
	var seguir_btn := Button.new()
	seguir_btn.text = "▶ SEGUIR"
	seguir_btn.add_theme_font_size_override("font_size", 16)
	seguir_btn.custom_minimum_size = Vector2(140, 0)
	seguir_btn.pressed.connect(_on_advance_jornada)
	footer_h.add_child(seguir_btn)
	# Saltar temporada completa
	var skip_btn := Button.new()
	skip_btn.text = "▶▶ TEMPORADA"
	skip_btn.tooltip_text = "Simular toda la temporada sin pausas"
	skip_btn.pressed.connect(_on_advance_full_season)
	footer_h.add_child(skip_btn)
	# Reset season
	var rs_btn := Button.new()
	rs_btn.text = "🔁 NUEVA TEMP."
	rs_btn.tooltip_text = "Cierra esta temporada y empieza la siguiente"
	rs_btn.pressed.connect(_on_reset_season)
	footer_h.add_child(rs_btn)


# Crea un panel de cuadrante con título y 3 botones (icono + label + tooltip).
func _make_quadrant(title: String, accent_color: Color, actions: Array) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.13, 0.16, 0.22)
	bg.border_color = accent_color
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 8
	bg.content_margin_right = 8
	bg.content_margin_top = 6
	bg.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	# Título del cuadrante
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", accent_color.lightened(0.4))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	# Botones
	for action in actions:
		var icon: String = String(action[0])
		var label: String = String(action[1])
		var tooltip: String = String(action[2])
		var callback: Callable = action[3]
		var b := Button.new()
		b.text = "  %s   %s" % [icon, label]
		b.tooltip_text = tooltip
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 38)
		b.pressed.connect(callback)
		v.add_child(b)
	return panel


# Carga el escudo del equipo desde assets/logos/<team_id>.png. Si no existe,
# muestra fallback con las iniciales sobre fondo del color del equipo.
func _make_team_logo(team: Team, size: int) -> Control:
	# Probar extensiones en orden: png, jpg, jpeg
	for ext in ["png", "jpg", "jpeg"]:
		var logo_path: String = "res://assets/logos/%s.%s" % [team.id, ext]
		if ResourceLoader.exists(logo_path):
			var tex: Texture2D = load(logo_path)
			if tex != null:
				var rect := TextureRect.new()
				rect.texture = tex
				rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				rect.custom_minimum_size = Vector2(size, size)
				return rect
	# Fallback: panel con color del equipo + short_name
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(size, size)
	var bg := StyleBoxFlat.new()
	var color_hex: String = String(team.colors.get("primary", "#888888"))
	bg.bg_color = Color.from_string(color_hex, Color(0.5, 0.5, 0.5))
	bg.set_corner_radius_all(int(size / 4))
	p.add_theme_stylebox_override("panel", bg)
	var l := Label.new()
	l.text = team.short_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(size / 3.5))
	l.add_theme_color_override("font_color", Color.from_string(String(team.colors.get("secondary", "#FFFFFF")), Color.WHITE))
	p.add_child(l)
	return p


func _user_next_match_date_str(team: Team) -> String:
	var st: DivisionState = primera_state if team.division == "primera" else segunda_state
	if st.calendar.is_empty() or st.current_jornada >= st.calendar.size():
		return ""
	var jornada: Array = st.calendar[st.current_jornada]
	for fixture: Dictionary in jornada:
		if fixture["home_id"] == team.id or fixture["away_id"] == team.id:
			if fixture.has("match_date"):
				return DateUtil.format_short(fixture["match_date"])
			return ""
	return ""


func _find_next_rival(team: Team) -> Team:
	var st: DivisionState = primera_state if team.division == "primera" else segunda_state
	if st.calendar.is_empty():
		return null
	if st.current_jornada >= st.calendar.size():
		return null
	var jornada: Array = st.calendar[st.current_jornada]
	for fixture: Dictionary in jornada:
		if fixture["home_id"] == team.id:
			return _find_team_by_id(String(fixture["away_id"]))
		if fixture["away_id"] == team.id:
			return _find_team_by_id(String(fixture["home_id"]))
	return null


# =========================================================================== #
# Vista: 🔍 VER RIVAL — info del próximo oponente
# =========================================================================== #
func _render_rival_view() -> void:
	var team := _find_team_by_id(user_team_id)
	if team == null:
		var l := Label.new()
		l.text = "Sin club seleccionado."
		content_area.add_child(l)
		return
	var rival: Team = _find_next_rival(team)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	content_area.add_child(box)

	if rival == null:
		var l := Label.new()
		l.text = "No hay próximo partido (¿temporada terminada?)."
		box.add_child(l)
		return

	# Cabecera con escudos
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(header)
	header.add_child(_make_team_logo(team, 80))
	var vs := Label.new()
	vs.text = "VS"
	vs.add_theme_font_size_override("font_size", 28)
	vs.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	header.add_child(vs)
	header.add_child(_make_team_logo(rival, 80))

	# Info del rival
	var name_label := Label.new()
	name_label.text = rival.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
	box.add_child(name_label)

	# Datos clave
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	box.add_child(grid)
	_simple_row(grid, "Ciudad", rival.city)
	_simple_row(grid, "Estadio", rival.stadium.name if rival.stadium else "?")
	_simple_row(grid, "Aforo", "%d asientos" % (rival.stadium.capacity if rival.stadium else 0))
	_simple_row(grid, "Reputación", "%d / 100" % rival.reputation)
	_simple_row(grid, "División", rival.division.capitalize())
	_simple_row(grid, "Entrenador", rival.manager.name if rival.manager else "?")
	_simple_row(grid, "Formación habitual", rival.tactics_default.formation if rival.tactics_default else "?")

	# Posición liga del rival
	var st: DivisionState = primera_state if rival.division == "primera" else segunda_state
	if st.league_table != null:
		var sorted_rows: Array = st.league_table.sorted_rows()
		for i in sorted_rows.size():
			if sorted_rows[i].team_id == rival.id:
				_simple_row(grid, "Posición Liga", "%dº con %d pts" % [i + 1, sorted_rows[i].points()])
				break

	# Top 5 jugadores rival por overall
	var top_label := Label.new()
	top_label.text = "── Jugadores destacados ──"
	top_label.add_theme_font_size_override("font_size", 14)
	top_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	box.add_child(top_label)
	var rivals_sorted: Array = rival.players.duplicate()
	rivals_sorted.sort_custom(func(a: Player, b: Player) -> bool:
		return PlayerFactory.compute_overall(a, "") > PlayerFactory.compute_overall(b, ""))
	for i in mini(5, rivals_sorted.size()):
		var p: Player = rivals_sorted[i]
		var ovr: int = PlayerFactory.compute_overall(p, "")
		var line := Label.new()
		line.text = "  %s — %s — ovr %d (%s)" % [p.name, _position_label(p), ovr, p.tier]
		line.add_theme_font_size_override("font_size", 12)
		box.add_child(line)


# =========================================================================== #
# Vista: ⚖ DECISIONES — objetivo, sponsors, carrera
# =========================================================================== #
func _render_decisions_view() -> void:
	var team := _find_team_by_id(user_team_id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	content_area.add_child(box)
	# (el botón 🏠 Hub está en el header global; no añadimos otro aquí)

	# Objetivo
	if not season_objective.is_empty():
		var obj_label := Label.new()
		obj_label.text = "🎯 Objetivo: %s (posición %dº)" % [
			String(season_objective.get("description", "")),
			int(season_objective.get("target_position", 0)),
		]
		obj_label.add_theme_font_size_override("font_size", 13)
		obj_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
		box.add_child(obj_label)

	# Sponsors actuales
	if team != null and team.finances != null:
		var sp_header := Label.new()
		sp_header.text = "💼 Patrocinadores"
		sp_header.add_theme_font_size_override("font_size", 14)
		sp_header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		box.add_child(sp_header)
		if team.finances.sponsors.is_empty():
			var n := Label.new()
			n.text = "  (sin patrocinadores activos)"
			box.add_child(n)
		for sp in team.finances.sponsors:
			var l := Label.new()
			l.text = "  • %s — %s — %s €/año (hasta %d)" % [
				String(sp.get("type", "?")).capitalize().replace("_", " "),
				String(sp.get("sponsor_name", "?")),
				TransferMarket._fmt_eur(int(sp.get("amount_per_year", 0))),
				int(sp.get("until_year", 0)),
			]
			l.add_theme_font_size_override("font_size", 11)
			box.add_child(l)
		if team.finances.sponsors.size() < 4:
			var find_btn := Button.new()
			find_btn.text = "🔍 Buscar nuevo patrocinador (500K)"
			find_btn.disabled = team.finances.cash_balance < 500_000
			find_btn.pressed.connect(func() -> void: _on_search_sponsor(team))
			box.add_child(find_btn)

	# Acceso a carrera
	box.add_child(HSeparator.new())
	var career_btn := Button.new()
	career_btn.text = "📈 Histórico de carrera"
	career_btn.pressed.connect(_on_select_view.bind(VIEW_CAREER))
	box.add_child(career_btn)
	var ch_btn := Button.new()
	ch_btn.text = "🏆 Champions / Europa / Conference"
	ch_btn.pressed.connect(_on_select_view.bind(VIEW_CHAMPIONS))
	box.add_child(ch_btn)


func _view_title_for(view: String) -> String:
	match view:
		VIEW_TABLE:     return "🏆 Clasificación"
		VIEW_FIXTURES:  return "📊 Resultados última jornada"
		VIEW_TEAM:      return "👥 Plantilla"
		VIEW_TACTICS:   return "🎯 Mi alineación"
		VIEW_MARKET:    return "💸 Mercado"
		VIEW_CAREER:    return "📈 Carrera"
		VIEW_CHAMPIONS: return "🏆 Competiciones europeas"
		VIEW_FINANCES:  return "💰 Finanzas"
		VIEW_CALENDAR:  return "📅 Calendario"
		VIEW_RIVAL:     return "🔍 Ver rival"
		VIEW_DECISIONS: return "⚖ Decisiones"
		VIEW_EMPLOYEES: return "👔 Empleados"
		VIEW_MATCH:     return "📺 Detalle de partido"
		_: return ""


# =========================================================================== #
# Vista: 👔 EMPLEADOS — organigrama del club
# =========================================================================== #
func _render_employees_view() -> void:
	var team := _find_team_by_id(user_team_id)
	if team == null:
		var l := Label.new()
		l.text = "Sin club seleccionado."
		content_area.add_child(l)
		return
	if team.organigrama == null:
		team.organigrama = OrganigramaFactory.generate(team, year)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_area.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	# Header con resumen
	var size_label: String = OrganigramaFactory.size_for(team)
	var pretty_size: String = "GRANDE" if size_label == "grande" else ("MEDIANO" if size_label == "mediano" else "PEQUEÑO")
	var header := Label.new()
	header.text = "👔 Organigrama de %s — Club %s (%d empleados, %s €/año en salarios)" % [
		team.name, pretty_size,
		team.organigrama.employees.size(),
		TransferMarket._fmt_eur(team.organigrama.total_salary()),
	]
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(header)

	# Secciones
	var sections := [
		["direccion", "🏛 Dirección", Color(1.0, 0.85, 0.4)],
		["tecnico", "🎯 Cuerpo técnico", Color(0.5, 0.85, 1.0)],
		["ojeo", "🔍 Ojeo / Scouting", Color(0.7, 1.0, 0.7)],
		["medico", "⚕ Servicios médicos", Color(1.0, 0.7, 0.7)],
		["cantera", "🌱 Cantera", Color(0.85, 1.0, 0.5)],
	]
	for sec_data in sections:
		var sec_id: String = String(sec_data[0])
		var sec_label: String = String(sec_data[1])
		var sec_color: Color = sec_data[2]
		var sec_employees: Array = team.organigrama.by_section(sec_id)
		if sec_employees.is_empty():
			continue
		# Cabecera
		var sec_header := Label.new()
		sec_header.text = "%s (%d)" % [sec_label, sec_employees.size()]
		sec_header.add_theme_font_size_override("font_size", 13)
		sec_header.add_theme_color_override("font_color", sec_color)
		box.add_child(sec_header)
		# Tabla
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 16)
		box.add_child(grid)
		for h in ["Nombre", "Rol", "Calidad", "Salario", "Acción"]:
			var hl := Label.new()
			hl.text = h
			hl.add_theme_font_size_override("font_size", 11)
			hl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
			grid.add_child(hl)
		for emp: Employee in sec_employees:
			var l_name := Label.new()
			l_name.text = emp.name
			l_name.add_theme_font_size_override("font_size", 11)
			grid.add_child(l_name)
			var l_role := Label.new()
			l_role.text = emp.role_label
			l_role.add_theme_font_size_override("font_size", 11)
			l_role.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
			grid.add_child(l_role)
			var l_q := Label.new()
			l_q.text = "★".repeat(emp.quality) + "☆".repeat(5 - emp.quality)
			l_q.add_theme_font_size_override("font_size", 11)
			l_q.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
			grid.add_child(l_q)
			var l_sal := Label.new()
			l_sal.text = "%s €" % TransferMarket._fmt_eur(emp.salary_eur_year)
			l_sal.add_theme_font_size_override("font_size", 11)
			grid.add_child(l_sal)
			# Acción: subir calidad si <5
			if emp.quality >= 5:
				var maxed := Label.new()
				maxed.text = "MAX"
				maxed.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
				grid.add_child(maxed)
			else:
				var btn := Button.new()
				var upgrade_cost: int = (emp.quality + 1) * (emp.quality + 1) * 100_000
				btn.text = "↑ %s" % TransferMarket._fmt_eur(upgrade_cost)
				btn.tooltip_text = "Mejorar a calidad %d" % (emp.quality + 1)
				btn.disabled = team.finances == null or team.finances.cash_balance < upgrade_cost
				btn.pressed.connect(func() -> void: _on_upgrade_employee(team, emp, upgrade_cost))
				grid.add_child(btn)


func _on_upgrade_employee(team: Team, emp: Employee, cost: int) -> void:
	if team.finances == null or team.finances.cash_balance < cost:
		status_label.text = "❌ Sin caja para mejorar a %s." % emp.name
		return
	team.finances.cash_balance -= cost
	emp.quality += 1
	# Reajustar salario al nuevo nivel
	# emp.salary = factor × calidad²; reconstruir factor
	var old_q: int = emp.quality - 1
	if old_q > 0:
		var factor: int = emp.salary_eur_year / (old_q * old_q * 10_000)
		emp.salary_eur_year = factor * emp.quality * emp.quality * 10_000
	# Sincronizar StaffInfo (compatible con el sistema antiguo)
	OrganigramaFactory.sync_staff_info(team)
	status_label.text = "✅ %s mejorado a calidad %d." % [emp.name, emp.quality]
	_refresh_ui()


func _make_spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


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
	var icon: String = ""
	# Solo Primera tiene plazas europeas
	var is_primera: bool = (selected_division == "primera")
	if is_primera and pos <= 4:
		color = Color(0.6, 1.0, 0.7)
		icon = "🏆 "
	elif is_primera and pos <= 6:
		color = Color(0.6, 0.8, 1.0)
		icon = "⭐ "
	elif is_primera and pos == 7:
		color = Color(0.6, 0.8, 1.0)
		icon = "🥉 "
	elif pos <= 2 and not is_primera:
		# Segunda: top 2 ascienden directos
		color = Color(0.6, 1.0, 0.7)
		icon = "⬆ "
	elif pos <= 6 and not is_primera:
		# Segunda: 3-6 zona playoff de ascenso
		color = Color(0.7, 0.85, 1.0)
		icon = "↑ "
	elif pos > n_teams - 3:
		color = Color(1.0, 0.65, 0.65)
		icon = "⬇ "

	# Ajustamos el ancho del botón de equipo para que el resto de columnas quepan
	var team_button := Button.new()
	team_button.text = "%s%s" % [icon, row.team_name]
	team_button.tooltip_text = _table_row_tooltip(pos, n_teams, is_primera)
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


# =========================================================================== #
# Helpers visuales para posiciones
# =========================================================================== #
# Categoria por slot: POR / DEF / MED / DEL
static func _position_category(slot: String) -> String:
	match slot:
		"GK": return "POR"
		"LB", "RB", "CB", "LWB", "RWB": return "DEF"
		"CDM", "CM", "CAM", "LM", "RM": return "MED"
		"LW", "RW", "ST", "CF": return "DEL"
		_: return "—"


# Devuelve un string compacto con icono + categoría + slot, ej: "🛡 DEF (CB)"
func _position_label(p: Player) -> String:
	if p.positions.is_empty():
		return "—"
	var primary: String = String(p.positions[0])
	var cat: String = _position_category(primary)
	var icon: String = ""
	match cat:
		"POR": icon = "🥅"
		"DEF": icon = "🛡"
		"MED": icon = "🎯"
		"DEL": icon = "⚽"
	# Si tiene varias posiciones, las añade entre paréntesis
	if p.positions.size() == 1:
		return "%s %s (%s)" % [icon, cat, primary]
	var rest: Array = []
	for i in range(p.positions.size()):
		rest.append(String(p.positions[i]))
	return "%s %s (%s)" % [icon, cat, ", ".join(rest)]


# Color asociado a la categoría (consistente con UI clásica de FM)
static func _position_color(slot: String) -> Color:
	var cat: String = _position_category(slot)
	match cat:
		"POR": return Color(1.0, 0.85, 0.4)   # amarillo claro
		"DEF": return Color(0.5, 0.85, 1.0)   # azul
		"MED": return Color(0.7, 1.0, 0.7)    # verde
		"DEL": return Color(1.0, 0.7, 0.7)    # rojo claro
		_:     return Color(0.8, 0.8, 0.8)


func _table_row_tooltip(pos: int, n_teams: int, is_primera: bool) -> String:
	if is_primera:
		if pos <= 4:
			return "Clasificado a Champions League"
		if pos <= 6:
			return "Clasificado a Europa League (v2)"
		if pos == 7:
			return "Clasificado a Conference League (v2)"
		if pos > n_teams - 3:
			return "Zona de descenso a Segunda"
		return ""
	else:
		if pos <= 2:
			return "Asciende directo a Primera"
		if pos <= 6:
			return "Zona de playoff de ascenso"
		if pos > n_teams - 3:
			return "Zona de descenso a Tercera"
		return ""


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
	grid.columns = 13
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	content_area.add_child(grid)

	var headers: Array[String] = ["#", "Nombre", "Pos", "Edad", "Nac", "Tier", "Pot", "Ovr", "PJ", "G", "A", "Estado", "Cont"]
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
		var pos_str: String = _position_label(p)
		var until_year: int = p.contract.until_year if p.contract != null else 0
		var injury_str: String = InjurySystem.injury_summary(p)
		var status_str: String = "—"
		if p.loan_origin_team_id != "":
			status_str = "🤝 cedido (vuelve %d)" % p.loan_until_year
		elif injury_str != "":
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
			str(p.season_matches),
			str(p.season_goals),
			str(p.season_assists),
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
		# Cedido: color violeta para diferenciar
		if p.loan_origin_team_id != "":
			color = Color(0.85, 0.7, 1.0)
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
# Flag: si el usuario eligió "Jugar y ver en 2D", abrir el visor automáticamente
# tras simular su partido (en _show_post_match_modal).
var auto_open_2d_after_match: bool = false

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
		_market_add_label(buy_grid, _position_label(p), _position_color(p.positions[0] if p.positions.size() > 0 else ""))
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
		_market_add_label(sell_grid, _position_label(p), _position_color(p.positions[0] if p.positions.size() > 0 else ""))
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
		option.add_item("%s — %s — ovr %d" % [p.name, _position_label(p), int(fit)], i)
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
