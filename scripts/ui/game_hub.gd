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
const VIEW_INBOX := "inbox"
const VIEW_AGENTS := "agents"
const VIEW_SETTINGS := "settings"


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
# Camera A2 light: id del jugador "protagonista" del usuario. Se setea desde
# la vista Plantilla. Si está vacío, no hay protagonista. Persiste en save.
var user_protagonist_id: String = ""
# v0.3.1 — profundidad mánager
# Inbox del usuario: lista de InboxMessage (más reciente primero al renderizar)
var user_inbox: Array = []  # Array[InboxMessage]
# Reputación del mánager (separada del club). Default = team.reputation cuando se elige equipo.
var manager_reputation: int = 0
# Expectativas del board para la temporada actual del usuario
var board_expectations: BoardExpectations = null
# Plantillas de press conference cargadas de data/press_conferences/templates.json
var press_templates: Array = []
# Última jornada en que se mostró press conference (para evitar duplicados)
var last_press_jornada: int = 0
# v0.3.2 — pool de agentes que representan a los jugadores de la liga
var agents_pool: Array = []  # Array[Agent]
# v0.3.2 — plantillas de speech persuasivo (cargadas de data/talks/templates.json)
var talk_templates: Array = []
# Modifier transitorio: si el usuario hizo speech persuasivo, este número se
# aplica a la siguiente acceptance (y se resetea). Solo aplica a una operación.
var pending_persuasion_modifier: float = 0.0
# v0.3.2 — TED: team talks en momentos de crisis
var team_talk_templates: Array = []  # cargadas de data/talks/team_talks.json
var last_team_talk_jornada: int = -10  # cooldown — no team talks consecutivas
# Bonus temporal para el próximo partido del usuario tras team talk exitosa.
# Se consume al simular el partido y se resetea.
var team_talk_form_bonus: float = 0.0
# Histórico ligero: últimos 5 resultados del usuario {won, lost, diff, jornada}
# para detectar rachas de derrotas (trigger TED).
var user_recent_results: Array = []
# v0.4.0 — Dashboard data
# Puntos acumulados por jornada (paralelo a primera_jornada del user). Crece tras
# cada simulación de jornada para el line chart del Dashboard.
var user_points_per_jornada: Array = []  # Array[int]
# Lista de player_ids marcados por el user desde Mercado (Scout Shortlist).
var user_shortlist: Array = []  # Array[String]
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
# v0.4.0 Fase B — nuevo shell
var sidebar_nav: SidebarNav
var balance_label: Label
var next_match_button: Button
var header_subtitle: Label


func _ready() -> void:
	primera_state.division = "primera"
	segunda_state.division = "segunda"
	# v0.4.0 Fase A: cargar tema persistido antes de construir UI
	UIThemeManager.apply(UserSettings.get_theme_name())
	_build_ui()
	_load_data()
	_load_press_templates()
	_load_talk_templates()
	_load_team_talk_templates()
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
# UI: construcción (v0.4.0 Fase B — shell con sidebar + main_area)
# =========================================================================== #
func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	var th: UITheme = UIThemeManager.get_current()

	# Background del root
	var bg := ColorRect.new()
	bg.color = th.bg_primary
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Layout raíz: HBox sidebar + main_area
	var root_hbox := HBoxContainer.new()
	root_hbox.anchor_right = 1.0
	root_hbox.anchor_bottom = 1.0
	root_hbox.add_theme_constant_override("separation", 0)
	add_child(root_hbox)

	# === SIDEBAR ===
	sidebar_nav = SidebarNav.new()
	sidebar_nav.view_selected.connect(_on_sidebar_view_selected)
	root_hbox.add_child(sidebar_nav)

	# === MAIN AREA ===
	var main_area := VBoxContainer.new()
	main_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_area.add_theme_constant_override("separation", 0)
	root_hbox.add_child(main_area)

	# --- Header del main_area ---
	var header_panel := PanelContainer.new()
	var header_sb := StyleBoxFlat.new()
	header_sb.bg_color = th.bg_secondary
	header_sb.border_width_bottom = 1
	header_sb.border_color = th.border_subtle
	header_sb.content_margin_left = 24
	header_sb.content_margin_right = 24
	header_sb.content_margin_top = 14
	header_sb.content_margin_bottom = 14
	header_panel.add_theme_stylebox_override("panel", header_sb)
	main_area.add_child(header_panel)

	var header_h := HBoxContainer.new()
	header_h.add_theme_constant_override("separation", 12)
	header_panel.add_child(header_h)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_h.add_child(title_box)
	view_title_label = Label.new()
	view_title_label.text = "Dashboard"
	view_title_label.add_theme_font_size_override("font_size", 22)
	view_title_label.add_theme_color_override("font_color", th.text_primary)
	title_box.add_child(view_title_label)
	header_subtitle = Label.new()
	header_subtitle.text = ""
	header_subtitle.add_theme_font_size_override("font_size", 13)
	header_subtitle.add_theme_color_override("font_color", th.text_secondary)
	title_box.add_child(header_subtitle)

	# Year / Jornada (compactos, junto al subtítulo en el header pero como vars
	# separadas para que el resto del código siga setando .text como antes)
	year_label = Label.new()
	year_label.visible = false
	header_h.add_child(year_label)
	jornada_label = Label.new()
	jornada_label.visible = false
	header_h.add_child(jornada_label)

	# Notif (campana → Inbox)
	var notif_btn := Button.new()
	notif_btn.text = "🔔"
	notif_btn.flat = true
	notif_btn.tooltip_text = "Inbox"
	notif_btn.pressed.connect(_on_select_view.bind(VIEW_INBOX))
	header_h.add_child(notif_btn)

	# Balance pill
	balance_label = Label.new()
	balance_label.text = "€ —"
	balance_label.add_theme_font_size_override("font_size", 14)
	balance_label.add_theme_color_override("font_color", th.accent_warning)
	header_h.add_child(balance_label)

	# Next match button (acción primaria)
	next_match_button = Button.new()
	next_match_button.text = "▶ Sgte. partido"
	next_match_button.add_theme_font_size_override("font_size", 13)
	next_match_button.pressed.connect(_on_advance_jornada)
	var nm_sb := StyleBoxFlat.new()
	nm_sb.bg_color = th.accent_primary
	nm_sb.corner_radius_top_left = 6
	nm_sb.corner_radius_top_right = 6
	nm_sb.corner_radius_bottom_left = 6
	nm_sb.corner_radius_bottom_right = 6
	nm_sb.content_margin_left = 16
	nm_sb.content_margin_right = 16
	nm_sb.content_margin_top = 8
	nm_sb.content_margin_bottom = 8
	next_match_button.add_theme_stylebox_override("normal", nm_sb)
	next_match_button.add_theme_stylebox_override("hover", nm_sb)
	next_match_button.add_theme_stylebox_override("pressed", nm_sb)
	next_match_button.add_theme_color_override("font_color", th.text_on_accent)
	next_match_button.add_theme_color_override("font_hover_color", th.text_on_accent)
	header_h.add_child(next_match_button)

	# --- Content area (cambia por vista) ---
	var content_scroll := ScrollContainer.new()
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_area.add_child(content_scroll)

	var content_pad := MarginContainer.new()
	content_pad.add_theme_constant_override("margin_left", 24)
	content_pad.add_theme_constant_override("margin_right", 24)
	content_pad.add_theme_constant_override("margin_top", 18)
	content_pad.add_theme_constant_override("margin_bottom", 18)
	content_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(content_pad)

	content_area = VBoxContainer.new()
	content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_area.add_theme_constant_override("separation", 10)
	content_pad.add_child(content_area)

	# --- Status bar (footer mínimo: solo status_label + acciones extra) ---
	var status_panel := PanelContainer.new()
	var status_sb := StyleBoxFlat.new()
	status_sb.bg_color = th.bg_secondary
	status_sb.border_width_top = 1
	status_sb.border_color = th.border_subtle
	status_sb.content_margin_left = 24
	status_sb.content_margin_right = 24
	status_sb.content_margin_top = 6
	status_sb.content_margin_bottom = 6
	status_panel.add_theme_stylebox_override("panel", status_sb)
	main_area.add_child(status_panel)

	var status_h := HBoxContainer.new()
	status_h.add_theme_constant_override("separation", 8)
	status_panel.add_child(status_h)

	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.add_theme_color_override("font_color", th.text_secondary)
	status_label.add_theme_font_size_override("font_size", 13)
	status_h.add_child(status_label)

	# Acciones secundarias: ▶▶ Temporada, 🔁 Nueva temp.
	advance_all_button = Button.new()
	advance_all_button.text = "▶▶ Temporada"
	advance_all_button.flat = true
	advance_all_button.add_theme_font_size_override("font_size", 13)
	advance_all_button.tooltip_text = "Simular toda la temporada sin pausas"
	advance_all_button.pressed.connect(_on_advance_full_season)
	status_h.add_child(advance_all_button)

	reset_button = Button.new()
	reset_button.text = "🔁 Nueva temp."
	reset_button.flat = true
	reset_button.add_theme_font_size_override("font_size", 13)
	reset_button.tooltip_text = "Cerrar temporada y empezar la siguiente"
	reset_button.pressed.connect(_on_reset_season)
	status_h.add_child(reset_button)

	save_button = Button.new()
	save_button.text = "💾"
	save_button.flat = true
	save_button.tooltip_text = "Guardar partida"
	save_button.pressed.connect(_on_save_game)
	status_h.add_child(save_button)

	load_button = Button.new()
	load_button.text = "📂"
	load_button.flat = true
	load_button.tooltip_text = "Cargar partida"
	load_button.pressed.connect(_on_load_game)
	status_h.add_child(load_button)

	var menu_btn := Button.new()
	menu_btn.text = "🚪"
	menu_btn.flat = true
	menu_btn.tooltip_text = "Volver al menú principal"
	menu_btn.pressed.connect(_on_back_to_menu)
	status_h.add_child(menu_btn)

	# === DUMMY: variables del layout viejo (mantenerlas para no romper _refresh_ui) ===
	# Estas vars siguen siendo referenciadas por _refresh_ui y otras funciones.
	# Son nodos sin parent (sí se garbage-collect-able) con visible=false donde aplica.
	top_header_box = HBoxContainer.new()
	top_header_box.visible = false
	div_tabs_box = HBoxContainer.new()
	div_tabs_box.visible = false
	view_tabs_box = HBoxContainer.new()
	view_tabs_box.visible = false
	top_header_separator = HSeparator.new()
	top_header_separator.visible = false
	footer_global_box = HBoxContainer.new()
	footer_global_box.visible = false
	primera_div_button = Button.new()
	segunda_div_button = Button.new()
	view_table_button = Button.new()
	view_fixtures_button = Button.new()
	view_team_button = Button.new()
	view_tactics_button = Button.new()
	view_market_button = Button.new()
	user_team_label = Label.new()
	user_team_label.visible = false
	advance_button = Button.new()  # reemplazado por next_match_button


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
	# v0.3.2: generar pool de agentes y asignarlos a jugadores si no están ya asignados
	_ensure_agents_initialized()
	# v0.3.2: asignar personality a jugadores que no la tengan (defaults "")
	_ensure_personalities_initialized()
	status_label.text = "Cargados %d equipos, %d jugadores, %d agentes." % [
		all_teams.size(), loaded.player_id_index.size(), agents_pool.size()]


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
	# v0.4.0: reset puntos por jornada del Dashboard (cada temporada acumula desde 0)
	user_points_per_jornada = []
	user_points_at_last_award = 0
	# Generar objetivo del club para esta temporada
	if user_team_id != "":
		_generate_season_objective()
	# v0.3.1: inicializar manager_reputation y generar BoardExpectations
	if user_team_id != "":
		_initialize_manager_reputation_from_team()
		_ensure_board_expectations()
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
	popup.min_size = Vector2(560, 380)
	popup.max_size = Vector2(840, 570)
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
	subtitle.add_theme_font_size_override("font_size", 13)
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
	summary.add_theme_font_size_override("font_size", 13)
	summary.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	box.add_child(summary)

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered(Vector2(560, 380))


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
	popup.min_size = Vector2(620, 420)
	popup.max_size = Vector2(930, 630)
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
	others_label.add_theme_font_size_override("font_size", 13)
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
		l.add_theme_font_size_override("font_size", 13)
		box.add_child(l)
		shown += 1

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered(Vector2(620, 420))


# Modal de resumen del mercado de verano (incluye renovaciones, free agents,
# traspasos y libres que se retiraron).
func _show_summer_market_modal(market: TransferMarket.MarketResult) -> void:
	var popup := AcceptDialog.new()
	popup.title = "☀ Mercado de verano %d" % year
	popup.min_size = Vector2(700, 540)
	popup.max_size = Vector2(1050, 810)
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
	stats_label.add_theme_font_size_override("font_size", 13)
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
		l.add_theme_font_size_override("font_size", 13)
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
			l.add_theme_font_size_override("font_size", 13)
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
			l.add_theme_font_size_override("font_size", 13)
			box.add_child(l)
			shown += 1

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered(Vector2(700, 540))


# =========================================================================== #
# Renovaciones manuales de contrato (vista que se muestra entre temporadas)
# =========================================================================== #
# Devuelve un Dictionary[player_id, "renewed"|"released"] con la decisión
# tomada por el usuario para cada jugador con contrato vencido. Los jugadores
# sobre los que el usuario no decida nada quedan como "released" automático
# (sin chance de auto-renew, porque el usuario ya conoció la lista).
func _show_renewals_view_modal(team: Team, pending: Array, season_year: int) -> Dictionary:
	var decisions: Dictionary = {}

	var popup := AcceptDialog.new()
	popup.title = "📝 Renovaciones de contrato — %s" % team.name
	popup.dialog_close_on_escape = false
	popup.unresizable = false
	popup.min_size = Vector2(720, 540)
	popup.max_size = Vector2(1080, 810)
	add_child(popup)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	popup.add_child(root)

	var intro := Label.new()
	intro.text = "Tus jugadores con contrato vencido al final de la temporada %d.\nDecide a quién renovar y a quién dejar marchar." % season_year
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(intro)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 420)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var list_box := VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)

	var status_labels: Dictionary = {}  # player_id -> Label

	for p: Player in pending:
		var row := PanelContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		row.add_child(hbox)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var primary: String = p.primary_position()
		var ovr: int = PlayerFactory.compute_overall(p, primary)
		var age: int = p.age_at(season_year, 7, 1)
		var name_l := Label.new()
		name_l.text = "%s (%s, %d años) · OVR %d · Tier %s" % [p.name, primary, age, ovr, p.tier]
		name_l.add_theme_font_size_override("font_size", 14)
		info.add_child(name_l)

		var fair: int = ContractNegotiation.fair_salary(p, season_year)
		var current_salary: int = p.contract.salary_eur_year if p.contract else 0
		var detail_l := Label.new()
		detail_l.text = "Salario actual: %s€/año · Justo estimado: %s€/año" % [_fmt_eur(current_salary), _fmt_eur(fair)]
		detail_l.add_theme_font_size_override("font_size", 13)
		detail_l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		info.add_child(detail_l)

		var status_l := Label.new()
		status_l.text = "⏳ Pendiente"
		status_l.add_theme_font_size_override("font_size", 13)
		status_l.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
		info.add_child(status_l)
		status_labels[p.id] = status_l

		hbox.add_child(info)

		var renew_btn := Button.new()
		renew_btn.text = "Renovar"
		renew_btn.custom_minimum_size = Vector2(100, 40)
		var captured_player: Player = p
		var captured_status: Label = status_l
		renew_btn.pressed.connect(_on_renew_player_pressed.bind(captured_player, season_year, decisions, captured_status))
		hbox.add_child(renew_btn)

		var release_btn := Button.new()
		release_btn.text = "Liberar"
		release_btn.custom_minimum_size = Vector2(100, 40)
		release_btn.pressed.connect(_on_release_player_pressed.bind(captured_player.id, decisions, captured_status))
		hbox.add_child(release_btn)

		list_box.add_child(row)

	popup.ok_button_text = "Aplicar y continuar al verano"
	popup.popup_centered(Vector2(720, 540))
	# Espera a que el usuario confirme. dialog_close_on_escape deshabilitado
	# y sin botón cancel — el único exit es la señal confirmed.
	await popup.confirmed
	# Los pendientes sin decisión los marcamos como "released" — el usuario
	# tuvo la oportunidad y la dejó pasar.
	for pp: Player in pending:
		if not decisions.has(pp.id):
			decisions[pp.id] = "released"
	popup.queue_free()
	return decisions


# Sub-modal para proponer una oferta de renovación al jugador.
func _open_renewal_offer_modal(player: Player, season_year: int, decisions: Dictionary, status_label: Label) -> void:
	var popup := AcceptDialog.new()
	popup.title = "Oferta de renovación — %s" % player.name
	popup.min_size = Vector2(440, 320)
	popup.max_size = Vector2(660, 480)
	add_child(popup)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	popup.add_child(box)

	var fair: int = ContractNegotiation.fair_salary(player, season_year)
	var year_range: Array = ContractNegotiation.acceptable_years(player, season_year)

	var info := Label.new()
	info.text = "Salario justo estimado: %s€/año\nAños aceptables: %d–%d" % [_fmt_eur(fair), int(year_range[0]), int(year_range[1])]
	info.add_theme_font_size_override("font_size", 13)
	box.add_child(info)

	# Salario propuesto en €/año (en miles de €)
	var sal_label := Label.new()
	sal_label.text = "Salario propuesto (€/año):"
	box.add_child(sal_label)
	var sal_spin := SpinBox.new()
	sal_spin.min_value = 100_000
	sal_spin.max_value = 50_000_000
	sal_spin.step = 50_000
	sal_spin.value = fair
	box.add_child(sal_spin)

	var years_label := Label.new()
	years_label.text = "Años de contrato:"
	box.add_child(years_label)
	var years_spin := SpinBox.new()
	years_spin.min_value = 1
	years_spin.max_value = 6
	years_spin.step = 1
	years_spin.value = clampi(int(year_range[1]), 1, 6)
	box.add_child(years_spin)

	var feedback := Label.new()
	feedback.text = ""
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size", 13)
	box.add_child(feedback)

	# Botón de envío
	var send_btn := Button.new()
	send_btn.text = "Enviar oferta"
	send_btn.pressed.connect(_on_send_renewal_offer.bind(player, season_year, sal_spin, years_spin, feedback, status_label, decisions, popup))
	box.add_child(send_btn)

	popup.ok_button_text = "Cerrar sin oferta"
	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered(Vector2(440, 320))


func _fmt_eur(amount: int) -> String:
	if amount >= 1_000_000:
		return "%.1fM" % (float(amount) / 1_000_000.0)
	if amount >= 1_000:
		return "%dK" % (amount / 1_000)
	return str(amount)


func _on_renew_player_pressed(player: Player, season_year: int, decisions: Dictionary, status_label: Label) -> void:
	_open_renewal_offer_modal(player, season_year, decisions, status_label)


func _on_release_player_pressed(player_id: String, decisions: Dictionary, status_label: Label) -> void:
	decisions[player_id] = "released"
	status_label.text = "❌ Liberado"
	status_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))


func _on_send_renewal_offer(player: Player, season_year: int, sal_spin: SpinBox, years_spin: SpinBox, feedback: Label, status_label: Label, decisions: Dictionary, popup: AcceptDialog) -> void:
	var salary: int = int(sal_spin.value)
	var years: int = int(years_spin.value)
	var agent: Agent = _agent_of(player)
	var eval: Dictionary = ContractNegotiation.evaluate_offer(player, season_year, salary, years, agent, user_team_id)
	if bool(eval.get("accepted", false)):
		ContractNegotiation.apply_renewal(player, season_year, salary, years)
		decisions[player.id] = "renewed"
		# v0.3.2: relación del agente +5 con el club al cerrar trato
		if agent != null:
			agent.adjust_relation(user_team_id, 5)
		status_label.text = "✅ Renovado (%d años, %s€/año)" % [years, _fmt_eur(salary)]
		status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
		popup.queue_free()
		return
	feedback.text = String(eval.get("message", "Rechaza la oferta."))
	feedback.add_theme_color_override("font_color", Color(0.95, 0.6, 0.5))
	var counter_sal: int = int(eval.get("counter_salary", 0))
	var counter_yrs: int = int(eval.get("counter_years", 0))
	if counter_sal > 0:
		sal_spin.value = counter_sal
	if counter_yrs > 0:
		years_spin.value = counter_yrs


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
	popup.ok_button_text = "Entendido"
	popup.min_size = Vector2(520, 260)
	popup.max_size = Vector2(640, 360)
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
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(hint)

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered(Vector2(520, 280))


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
	# v0.3.1: registrar en inbox
	_inbox_add("objective", "🎯 Objetivo de temporada: %s" % String(eval.get("verdict", "")),
		"Objetivo: %dº (%s). Posición final: %dº." % [
			int(eval.get("target_position", 0)),
			String(eval.get("description", "")),
			int(eval.get("actual_position", 0))])
	var popup := AcceptDialog.new()
	popup.title = "🎯 Evaluación del objetivo"
	popup.min_size = Vector2(540, 320)
	popup.max_size = Vector2(810, 480)
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
	popup.popup_centered(Vector2(540, 320))


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
	popup.min_size = Vector2(420, 220)
	popup.max_size = Vector2(630, 330)
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
	popup.popup_centered(Vector2(420, 220))
	# v0.3.1: registrar en inbox
	_inbox_add("coach_award", "🏅 Entrenador del mes",
		"%s — %d puntos en las últimas 4 jornadas. Premio: %s€." % [
			verdict, points, TransferMarket._fmt_eur(prize)])
	# Bonus a manager_reputation por premio (cosmético, +1)
	manager_reputation = clampi(manager_reputation + 1, 0, 99)


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
			# v0.3.1: press conference 50% prob (no jornada 1, no si ya hubo en esta jornada)
			if primera_state.current_jornada >= 1 \
					and last_press_jornada != primera_state.current_jornada \
					and randf() < 0.50:
				last_press_jornada = primera_state.current_jornada
				await _show_press_conference_modal()
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

	# v0.3.1: evaluación mid-season del board (tras jornada 19+)
	if user_team_id != "" and primera_state.current_jornada >= 19 \
			and board_expectations != null and not board_expectations.mid_season_evaluated:
		_evaluate_board_mid_season()
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
	# v0.3.2 TED: detectar momentos de crisis y disparar team talk
	await _maybe_trigger_team_talk(true)
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
	popup.min_size = Vector2(560, 460)
	popup.max_size = Vector2(840, 690)
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
		stats_label.add_theme_font_size_override("font_size", 13)
		box.add_child(stats_label)

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	# Custom action: ver replay en 2D
	popup.custom_action.connect(func(action: StringName) -> void:
		if String(action) == "view_2d":
			popup.queue_free()
			_on_open_2d_viewer(r)
	)
	popup.popup_centered(Vector2(560, 460))


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
	popup.min_size = Vector2(560, 420)
	popup.max_size = Vector2(840, 630)
	popup.ok_button_text = "▶ Jugar (resultado directo)"
	popup.cancel_button_text = "Configurar alineación"
	# Botón extra: jugar y abrir visor 2D automáticamente al terminar
	popup.add_button("🎬 Jugar y ver en 2D", true, "play_with_2d")
	# v0.3.1: pre-match bloqueante. ESC no cierra; el usuario debe elegir botón.
	popup.dialog_close_on_escape = false
	popup.exclusive = true
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
	l_eleven.add_theme_font_size_override("font_size", 13)
	content.add_child(l_eleven)

	# v0.3.1: team news (lesionados/sancionados) + manager rep
	content.add_child(HSeparator.new())
	var news_text: Array[String] = []
	var inj_count: int = 0
	var susp_count: int = 0
	for p: Player in user_team.players:
		if InjurySystem.is_injured(p):
			inj_count += 1
			if news_text.size() < 4:
				news_text.append("🏥 %s (%s)" % [p.name, InjurySystem.injury_summary(p)])
		elif CardSystem.is_suspended(p):
			susp_count += 1
			if news_text.size() < 6:
				news_text.append("🟥 %s (sancionado %d)" % [p.name, p.suspended_matches])
	var news_l := Label.new()
	if news_text.is_empty():
		news_l.text = "Sin lesiones ni sancionados — plantilla disponible al 100%."
		news_l.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	else:
		news_l.text = "Bajas (%d lesionados, %d sancionados):\n  " % [inj_count, susp_count] + "\n  ".join(news_text)
		news_l.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	news_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	news_l.add_theme_font_size_override("font_size", 13)
	content.add_child(news_l)

	var rep_l := Label.new()
	rep_l.text = "Tu reputación de mánager: %d  ·  Reputación del club: %d" % [manager_reputation, user_team.reputation]
	rep_l.add_theme_font_size_override("font_size", 13)
	rep_l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.4))
	content.add_child(rep_l)

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
	popup.popup_centered(Vector2(560, 420))


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
		# v0.3.1: evaluación final del board + bonus por títulos en manager_reputation
		if user_team_id != "":
			_evaluate_board_final()
			# Bonus por campeón Liga
			var liga_sorted_eval: Array = primera_state.league_table.sorted_rows()
			if liga_sorted_eval.size() > 0 and (liga_sorted_eval[0] as LeagueTable.TeamRow).team_id == user_team_id:
				manager_reputation = clampi(manager_reputation + 5, 0, 99)
				_inbox_add("board_message", "¡CAMPEÓN DE LIGA!", "Has ganado la Liga. Reputación de mánager +5 (ahora %d)." % manager_reputation)
			# Bonus por Copa
			if cup_bracket != null and cup_bracket.champion_id == user_team_id:
				manager_reputation = clampi(manager_reputation + 3, 0, 99)
				_inbox_add("board_message", "¡CAMPEÓN DE COPA!", "Has ganado la Copa del Rey. Reputación de mánager +3 (ahora %d)." % manager_reputation)
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
		var movement: PromotionRelegation.Movement = PromotionRelegation.apply(primera_state.league_table, segunda_state.league_table, all_teams)
		# Si hubo playoff y el usuario participó, mostrar modal
		if movement != null and not movement.playoff_results.is_empty():
			var user_team := _find_team_by_id(user_team_id)
			var user_name: String = user_team.name if user_team else ""
			var user_in_playoff: bool = false
			if user_name != "":
				for r in movement.playoff_results:
					if String(r.get("home_name", "")) == user_name \
							or String(r.get("away_name", "")) == user_name:
						user_in_playoff = true
						break
			if user_in_playoff:
				_show_playoff_modal(movement)
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
	# Renovaciones manuales del usuario antes del verano
	var user_decisions: Dictionary = {}
	if user_team_id != "":
		var user_team_for_renewals: Team = _find_team_by_id(user_team_id)
		if user_team_for_renewals != null:
			var pending: Array = ContractNegotiation.players_to_negotiate(user_team_for_renewals, year - 1)
			if pending.size() > 0:
				user_decisions = await _show_renewals_view_modal(user_team_for_renewals, pending, year - 1)
	# Mercado de fichajes (verano)
	var summer_result: TransferMarket.MarketResult = TransferMarket.run(all_teams, year, SEED_BASE * 7, null, user_decisions)
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


func _show_playoff_modal(movement: PromotionRelegation.Movement) -> void:
	var popup := AcceptDialog.new()
	popup.title = "🎟 Playoff de ascenso a Primera"
	popup.min_size = Vector2(540, 360)
	popup.max_size = Vector2(810, 540)
	popup.ok_button_text = "Continuar"
	add_child(popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	popup.add_child(box)

	var user_team := _find_team_by_id(user_team_id)
	var user_name: String = user_team.name if user_team else ""

	# Resultado del usuario
	var user_promoted: bool = movement.playoff_winner_name == user_name
	var user_finalist: bool = false
	# Si está como home/away en la final pero no ganó
	for r in movement.playoff_results:
		if String(r.get("stage", "")) == "Final":
			if (String(r.get("home_name", "")) == user_name or String(r.get("away_name", "")) == user_name) \
					and not user_promoted:
				user_finalist = true
				break
	var verdict: String
	var color: Color
	if user_promoted:
		verdict = "🎉 ASCENSO A PRIMERA"
		color = Color(0.6, 1.0, 0.6)
	elif user_finalist:
		verdict = "FINAL PERDIDA — un año más en Segunda"
		color = Color(1.0, 0.85, 0.4)
	else:
		verdict = "ELIMINADO EN SEMIFINALES"
		color = Color(1.0, 0.6, 0.6)
	var verdict_lbl := Label.new()
	verdict_lbl.text = verdict
	verdict_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	verdict_lbl.add_theme_font_size_override("font_size", 18)
	verdict_lbl.add_theme_color_override("font_color", color)
	box.add_child(verdict_lbl)

	box.add_child(HSeparator.new())

	# Lista de partidos
	for r in movement.playoff_results:
		var line := Label.new()
		var rep: String = " (rep)" if bool(r.get("won_by_reputation", false)) else ""
		line.text = "%s — %s %d-%d %s → %s%s" % [
			String(r.get("stage", "?")),
			String(r.get("home_name", "?")),
			int(r.get("score_home", 0)),
			int(r.get("score_away", 0)),
			String(r.get("away_name", "?")),
			String(r.get("winner_name", "?")),
			rep,
		]
		line.add_theme_font_size_override("font_size", 13)
		# Marcar partidos del usuario
		var is_user_match: bool = String(r.get("home_name", "")) == user_name \
				or String(r.get("away_name", "")) == user_name
		if is_user_match:
			line.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
		box.add_child(line)

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered(Vector2(540, 360))


func _show_supercopa_modal(sc: SupercopaSimulator.SupercopaResult) -> void:
	var popup := AcceptDialog.new()
	popup.title = "🏆 Supercopa de España %d" % sc.year
	popup.min_size = Vector2(520, 360)
	popup.max_size = Vector2(780, 540)
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
	popup.popup_centered(Vector2(520, 360))


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
	# v0.3.1: registrar en inbox
	if not offers.is_empty():
		var offer_names: Array[String] = []
		for o: Team in offers:
			offer_names.append(o.short_name)
		_inbox_add("manager_offer", "📨 Ofertas de mánager (%d)" % offers.size(),
			"Tras tu temporada en %s, te buscan: %s." % [current_team.short_name, ", ".join(offer_names)])
	var popup := AcceptDialog.new()
	popup.title = "📨 Ofertas de mánager"
	popup.min_size = Vector2(640, 480)
	popup.max_size = Vector2(960, 720)
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
	subheader.add_theme_font_size_override("font_size", 13)
	subheader.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	box.add_child(subheader)

	box.add_child(HSeparator.new())

	for offer_team: Team in offers:
		box.add_child(_make_offer_row(current_team, offer_team, popup))

	box.add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "Si aceptas una oferta, dirigirás al nuevo club desde la próxima temporada.\nSi pulsas 'Quedarme', sigues en %s." % current_team.name
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(hint)

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered(Vector2(640, 480))


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
	details.add_theme_font_size_override("font_size", 13)
	details.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	info.add_child(details)

	var rep_diff: int = offer_team.reputation - current_team.reputation
	var diff_str: String = "(+%d rep)" % rep_diff if rep_diff > 0 else (
			"(%d rep)" % rep_diff if rep_diff < 0 else "(misma rep)")
	var diff_label := Label.new()
	diff_label.text = "vs tu club actual: %s" % diff_str
	diff_label.add_theme_font_size_override("font_size", 13)
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
	# v0.3.1: reset protagonist (nuevo equipo) y board expectations (se regenerará en _start_season)
	user_protagonist_id = ""
	board_expectations = null
	# Manager reputation se mantiene (es del entrenador, no del club)
	_inbox_add("manager_offer", "Nuevo destino: %s" % new_team_name,
		"Has aceptado dirigir a %s%s. Tu reputación de mánager (%d) se mantiene." % [
			new_team_name,
			" (dejas %s)" % old_team.short_name if old_team else "",
			manager_reputation])
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
		"champions_progress": "—",
		"europa_progress": "—",
		"conference_progress": "—",
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
	# Progreso europeo (si el usuario clasificó la temporada anterior)
	if champions_state != null:
		record["champions_progress"] = _compute_user_european_progress(champions_state)
	if europa_state != null:
		record["europa_progress"] = _compute_user_european_progress(europa_state)
	if conference_state != null:
		record["conference_progress"] = _compute_user_european_progress(conference_state)
	user_career_history.append(record)


# Devuelve "—" si el usuario no jugó esa competición; si jugó, dice hasta
# qué ronda llegó (Campeón, Subcampeón, Semis, Cuartos, Octavos, Grupos).
func _compute_user_european_progress(bracket: ChampionsBracket) -> String:
	if bracket == null or user_team_id == "":
		return "—"
	# Verificar si el usuario participó
	var participated: bool = false
	if not bracket.groups.is_empty():
		for g: ChampionsBracket.Group in bracket.groups:
			if user_team_id in g.team_ids:
				participated = true
				break
	if not participated:
		# Buscar también en KO rounds (Europa/Conference no tienen grupos)
		for r: ChampionsBracket.KORound in bracket.ko_rounds:
			for fx: ChampionsBracket.KOFixture in r.fixtures:
				if fx.home_id == user_team_id or fx.away_id == user_team_id:
					participated = true
					break
			if participated:
				break
	if not participated:
		return "—"
	# Campeón / subcampeón
	if bracket.champion_id == user_team_id:
		return "🏆 Campeón"
	# Buscar última ronda donde apareció
	var last_round: String = "Fase de grupos"
	for r: ChampionsBracket.KORound in bracket.ko_rounds:
		for fx: ChampionsBracket.KOFixture in r.fixtures:
			if fx.home_id == user_team_id or fx.away_id == user_team_id:
				if fx.winner_id == user_team_id:
					last_round = "Pasó %s" % r.name
				else:
					if r.name == "Final":
						return "🥈 Subcampeón"
					last_round = "Eliminado en %s" % r.name
				break
	return last_round


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

	# content_area ya está dentro de un ScrollContainer.
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_area.add_child(vbox)

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
				hl.add_theme_font_size_override("font_size", 13)
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
			line.add_theme_font_size_override("font_size", 13)
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
	popup.min_size = Vector2(560, 380)
	popup.max_size = Vector2(840, 570)
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
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(hint)

	popup.popup_centered(Vector2(560, 380))
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
	# content_area ya está dentro de un ScrollContainer en _build_ui.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_area.add_child(box)

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
				pb_label.add_theme_font_size_override("font_size", 13)
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
				pl.add_theme_font_size_override("font_size", 13)
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
			hl.add_theme_font_size_override("font_size", 13)
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
			rl.add_theme_font_size_override("font_size", 13)
			staff_grid.add_child(rl)
			var ql := Label.new()
			ql.text = "★".repeat(q) + "☆".repeat(5 - q) + "  (%d/5)" % q
			ql.add_theme_font_size_override("font_size", 13)
			ql.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
			staff_grid.add_child(ql)
			var sl := Label.new()
			sl.text = "%s €/año" % TransferMarket._fmt_eur(StaffInfo.salary_for_quality(q))
			sl.add_theme_font_size_override("font_size", 13)
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
			sl.add_theme_font_size_override("font_size", 13)
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
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	grid.add_child(l)


func _simple_row(grid: GridContainer, label: String, value: String) -> void:
	var l1 := Label.new()
	l1.text = label
	l1.add_theme_font_size_override("font_size", 13)
	grid.add_child(l1)
	var l2 := Label.new()
	l2.text = value
	l2.add_theme_font_size_override("font_size", 13)
	l2.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	grid.add_child(l2)


func _finance_pair(grid: GridContainer, label_in: String, amount_in: int, label_out: String, amount_out: int) -> void:
	# 4 columnas: label_in | amount_in | label_out | amount_out
	var l1 := Label.new()
	l1.text = label_in
	l1.add_theme_font_size_override("font_size", 13)
	grid.add_child(l1)
	var l2 := Label.new()
	l2.text = "%s €" % TransferMarket._fmt_eur(amount_in) if amount_in > 0 else ""
	l2.add_theme_font_size_override("font_size", 13)
	l2.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(l2)
	var l3 := Label.new()
	l3.text = label_out
	l3.add_theme_font_size_override("font_size", 13)
	grid.add_child(l3)
	var l4 := Label.new()
	l4.text = "%s €" % TransferMarket._fmt_eur(amount_out) if amount_out > 0 else ""
	l4.add_theme_font_size_override("font_size", 13)
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
	popup.min_size = Vector2(620, 460)
	popup.max_size = Vector2(930, 690)
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
		l.add_theme_font_size_override("font_size", 13)
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
		l.add_theme_font_size_override("font_size", 13)
		box.add_child(l)

	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered(Vector2(620, 460))


func _finances_row(grid: GridContainer, label: String, amount: int) -> void:
	var l1 := Label.new()
	l1.text = label
	l1.add_theme_font_size_override("font_size", 13)
	grid.add_child(l1)
	var l2 := Label.new()
	l2.text = "%s €" % TransferMarket._fmt_eur(amount)
	l2.add_theme_font_size_override("font_size", 13)
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
		l.text = "No hay calendario disponible. Empieza una temporada primero."
		l.add_theme_font_size_override("font_size", 14)
		content_area.add_child(l)
		return

	# content_area ya está dentro de un ScrollContainer.
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_area.add_child(vbox)

	var user_team := _find_team_by_id(user_team_id) if user_team_id != "" else null
	var title := Label.new()
	if user_team != null:
		title.text = "📅 Calendario %s · Temporada %d-%d" % [user_team.name, year, year + 1]
	else:
		title.text = "📅 Calendario %s · Temporada %d-%d" % [
			selected_division.capitalize(), year, year + 1]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(title)

	# Si hay equipo del usuario: solo sus partidos. Si no: calendario completo.
	if user_team != null:
		_render_calendar_user_only(vbox, st, user_team)
	else:
		_render_calendar_full(vbox, st)


# Calendario filtrado: solo partidos del usuario, una línea por jornada.
func _render_calendar_user_only(vbox: VBoxContainer, st: DivisionState, user_team: Team) -> void:
	for j_idx in st.calendar.size():
		var jornada: Array = st.calendar[j_idx]
		var played: bool = j_idx < st.current_jornada
		# Buscar el fixture del usuario en esta jornada
		var user_fixture: Dictionary = {}
		for fixture: Dictionary in jornada:
			if fixture["home_id"] == user_team.id or fixture["away_id"] == user_team.id:
				user_fixture = fixture
				break
		if user_fixture.is_empty():
			continue
		var home_id: String = String(user_fixture["home_id"])
		var away_id: String = String(user_fixture["away_id"])
		var home: Team = _find_team_by_id(home_id)
		var away: Team = _find_team_by_id(away_id)
		if home == null or away == null:
			continue
		var date_str: String = ""
		if user_fixture.has("match_date"):
			date_str = DateUtil.format_short(user_fixture["match_date"])
		var is_home: bool = home_id == user_team.id
		var rival_name: String = away.name if is_home else home.name
		var loc: String = "(L)" if is_home else "(V)"
		var line := Label.new()
		var status: String = ""
		if played:
			status = " · jugado"
		elif j_idx == st.current_jornada:
			status = " · próximo"
		line.text = "J%-2d  [%s] %s vs %s %s%s" % [
			j_idx + 1, date_str,
			user_team.short_name if is_home else rival_name.left(20),
			rival_name.left(20) if is_home else user_team.short_name,
			loc, status,
		]
		line.add_theme_font_size_override("font_size", 13)
		var color: Color = Color(0.85, 0.9, 1.0)
		if j_idx == st.current_jornada:
			color = Color(1.0, 0.95, 0.5)
		elif played:
			color = Color(0.7, 0.7, 0.7)
		line.add_theme_color_override("font_color", color)
		vbox.add_child(line)


# Calendario completo (todos los partidos de la división) — fallback sin user_team
func _render_calendar_full(vbox: VBoxContainer, st: DivisionState) -> void:
	for j_idx in st.calendar.size():
		var jornada: Array = st.calendar[j_idx]
		var played: bool = j_idx < st.current_jornada
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
			var date_str: String = ""
			if fixture.has("match_date"):
				date_str = "[%s] " % DateUtil.format_short(fixture["match_date"])
			line.text = "  %s%-28s vs %-28s" % [date_str, home.name.left(28), away.name.left(28)]
			line.add_theme_font_size_override("font_size", 13)
			if played:
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

	# Tabla por temporada con columnas extras de competiciones europeas
	var grid := GridContainer.new()
	grid.columns = 11
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	content_area.add_child(grid)
	for h in ["Año", "Div", "Pos", "PJ-G-E-P", "GF/GC", "Pts", "Pichichi", "Copa", "🏆 Champ", "⭐ Europa", "🥉 Conf"]:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		l.add_theme_font_size_override("font_size", 13)
		grid.add_child(l)
	# Ordenar por año descendente
	var sorted_history: Array = user_career_history.duplicate()
	sorted_history.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["year"]) > int(b["year"]))
	for r: Dictionary in sorted_history:
		var pos: int = int(r["position"])
		var color: Color = Color(0.85, 0.85, 0.85)
		if pos == 1 and r["division"] == "primera":
			color = Color(1.0, 0.85, 0.2)
		elif pos <= 4 and r["division"] == "primera":
			color = Color(0.6, 1.0, 0.7)
		elif pos <= 6 and r["division"] == "primera":
			color = Color(0.6, 0.8, 1.0)
		var cells: Array[String] = [
			"%d-%d" % [int(r["year"]), int(r["year"]) + 1 - 2000],
			"1ª" if r["division"] == "primera" else "2ª",
			"#%d" % pos,
			"%d-%d-%d-%d" % [int(r["played"]), int(r["won"]), int(r["drawn"]), int(r["lost"])],
			"%d/%d" % [int(r["gf"]), int(r["ga"])],
			str(int(r["points"])),
			"%s (%d)" % [String(r["top_scorer_name"]).left(18), int(r["top_scorer_goals"])],
			String(r.get("cup_progress", "—")),
			String(r.get("champions_progress", "—")),
			String(r.get("europa_progress", "—")),
			String(r.get("conference_progress", "—")),
		]
		for c in cells:
			var l := Label.new()
			l.text = c
			l.add_theme_color_override("font_color", color)
			l.add_theme_font_size_override("font_size", 13)
			grid.add_child(l)


func _simulate_jornada(state: DivisionState) -> void:
	# Curar lesiones según días reales transcurridos desde la última jornada.
	# Si tenemos calendario con fechas, calculamos diff exacto. Fallback: 7 días.
	var days_since_last: int = 7
	if state.current_jornada > 0:
		var prev_j: Array = state.calendar[state.current_jornada - 1]
		var curr_j: Array = state.calendar[state.current_jornada]
		if not prev_j.is_empty() and not curr_j.is_empty() \
				and prev_j[0].has("match_date") and curr_j[0].has("match_date"):
			days_since_last = max(1, DateUtil.diff_days(prev_j[0]["match_date"], curr_j[0]["match_date"]))
	InjurySystem.heal_after_days(all_teams, days_since_last)
	var jornada: Array = state.calendar[state.current_jornada]
	var team_index: Dictionary = {}
	for t: Team in state.teams:
		team_index[t.id] = t

	state.last_jornada_results = []
	# Acumulador de lesiones graves del usuario para modal post-jornada
	var user_grave_injuries: Array = []
	for fixture: Dictionary in jornada:
		var home: Team = team_index[fixture["home_id"]]
		var away: Team = team_index[fixture["away_id"]]
		# Recuperación parcial de condition basada en los días desde su
		# último partido individual (rota titulares más realista cuando
		# hay partidos seguidos).
		var match_date: Dictionary = fixture.get("match_date", {})
		ConditionRecovery.apply_to_team(home, match_date)
		ConditionRecovery.apply_to_team(away, match_date)
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
		# v0.3.2 TED: aplicar form_bonus temporal a los titulares del usuario
		# si hubo team talk con efecto. Se consume al simular.
		if team_talk_form_bonus != 0.0:
			var user_lineup: Lineup = home_lineup if home.id == user_team_id else (away_lineup if away.id == user_team_id else null)
			if user_lineup != null:
				for p: Player in user_lineup.starting_eleven:
					p.form = clampf(p.form + team_talk_form_bonus, FormTracker.FORM_MIN, FormTracker.FORM_MAX)
				team_talk_form_bonus = 0.0  # consumido
		state.seed_counter += 1
		var result: MatchResult = MatchEngine.simulate(home_lineup, away_lineup, state.seed_counter)
		if result != null:
			state.league_table.record_match(result)
			state.last_jornada_results.append(result)
			# v0.3.2: histórico de resultados del usuario para TED (rachas)
			if result.home_team_id == user_team_id or result.away_team_id == user_team_id:
				var is_h: bool = result.home_team_id == user_team_id
				var u_s: int = result.score_home if is_h else result.score_away
				var r_s: int = result.score_away if is_h else result.score_home
				user_recent_results.append({
					"won": u_s > r_s,
					"lost": u_s < r_s,
					"diff": u_s - r_s,
					"jornada": state.current_jornada + 1,
				})
				while user_recent_results.size() > 5:
					user_recent_results.pop_front()
				# v0.4.0 Dashboard: puntos acumulados por jornada del user
				var prev_points: int = user_points_per_jornada.back() if not user_points_per_jornada.is_empty() else 0
				var pts_this: int = 3 if u_s > r_s else (1 if u_s == r_s else 0)
				user_points_per_jornada.append(prev_points + pts_this)
			# Procesar tarjetas → posibles sanciones para el próximo partido
			CardSystem.process_match(result, all_teams)
			# Stats de jugador por temporada: matches + minutos (titulares = 90 min)
			for p: Player in home_lineup.starting_eleven:
				p.season_matches += 1
				p.season_minutes += 90
			for p: Player in away_lineup.starting_eleven:
				p.season_matches += 1
				p.season_minutes += 90
			# Registrar fecha del último partido (para recovery próximo)
			ConditionRecovery.record_match_played(home_lineup, match_date)
			ConditionRecovery.record_match_played(away_lineup, match_date)
			# Detectar lesiones graves del equipo del usuario en este partido
			if home.id == user_team_id or away.id == user_team_id:
				for ev: MatchEvent in result.events:
					if ev.type != MatchEvent.T_INJURY:
						continue
					var inj_player: Player = _find_player_globally(ev.player_id)
					if inj_player == null or inj_player.injury == null:
						continue
					var dias: int = int(inj_player.injury.get("dias_restantes", 0))
					if dias >= 21:  # media-larga o grave
						user_grave_injuries.append({
							"name": inj_player.name,
							"tipo": String(inj_player.injury.get("tipo", "?")),
							"dias": dias,
							"match_date": match_date,
						})
						# v0.3.1: registrar en inbox
						_inbox_add("injury", "🏥 Lesión grave: %s" % inj_player.name,
							"%s sufre una lesión %s. Baja estimada: %d días." % [
								inj_player.name, String(inj_player.injury.get("tipo", "?")), dias])
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
			# v0.3.2: actualizar FORM de los jugadores que jugaron este partido
			_update_form_for_match(home_lineup, away_lineup, result)
	state.current_jornada += 1
	# Modal de lesiones graves del usuario en esta jornada
	if user_grave_injuries.size() > 0:
		_show_grave_injuries_modal(user_grave_injuries)


func _show_grave_injuries_modal(injuries: Array) -> void:
	var popup := AcceptDialog.new()
	popup.title = "🏥 Parte médico"
	popup.min_size = Vector2(500, 280)
	popup.max_size = Vector2(750, 420)
	popup.ok_button_text = "Continuar"
	add_child(popup)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	popup.add_child(box)
	var header := Label.new()
	header.text = "%d lesión%s preocupante%s en tu equipo:" % [
		injuries.size(),
		"" if injuries.size() == 1 else "es",
		"" if injuries.size() == 1 else "s",
	]
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
	box.add_child(header)
	for inj in injuries:
		var match_date: Dictionary = inj.get("match_date", {})
		var return_date: Dictionary = DateUtil.add_days(match_date, int(inj.get("dias", 0))) if not match_date.is_empty() else {}
		var return_str: String = DateUtil.format_short(return_date) if not return_date.is_empty() else "?"
		var l := Label.new()
		l.text = "  %s — lesión %s, %d días (vuelve aprox. %s)" % [
			String(inj["name"]), String(inj["tipo"]), int(inj["dias"]), return_str,
		]
		l.add_theme_font_size_override("font_size", 13)
		box.add_child(l)
	popup.confirmed.connect(func() -> void: popup.queue_free())
	popup.canceled.connect(func() -> void: popup.queue_free())
	popup.popup_centered(Vector2(500, 280))


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
		user_team_id, user_lineup_template, user_career_history, user_protagonist_id,
		user_inbox, manager_reputation, board_expectations, agents_pool, user_recent_results,
		user_points_per_jornada, user_shortlist)
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
	user_protagonist_id = save_data.user_protagonist_id
	# v0.3.1 — profundidad mánager (defaults tolerantes para saves de v0.3.0)
	user_inbox = save_data.inbox_messages.duplicate()
	manager_reputation = save_data.manager_reputation
	if not save_data.board_expectations_dict.is_empty():
		board_expectations = BoardExpectations.from_dict(save_data.board_expectations_dict)
	else:
		board_expectations = null
	# v0.3.2: pool de agentes (si no hay en save, dejar vacío y _ensure_agents_initialized
	# lo regenerará al volver a _load_data)
	agents_pool = save_data.agents_pool.duplicate()
	user_recent_results = save_data.user_recent_results.duplicate(true)
	# v0.4.0 — Dashboard data
	user_points_per_jornada = save_data.user_points_per_jornada.duplicate()
	user_shortlist = save_data.user_shortlist.duplicate()
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


# v0.4.0 Fase B: handler de selección desde la sidebar
func _on_sidebar_view_selected(view: String) -> void:
	_on_select_view(view)


# v0.4.0 Fase B: rebuild de items de la sidebar según user_team_id
func _refresh_sidebar() -> void:
	if sidebar_nav == null:
		return
	var club_name: String = ""
	var club_short: String = ""
	if user_team_id != "":
		var t := _find_team_by_id(user_team_id)
		if t != null:
			club_name = t.name
			club_short = t.short_name
	var items: Array = [
		{"icon": "📊", "label": "Dashboard", "view": VIEW_HUB},
		{"icon": "👥", "label": "Plantilla", "view": VIEW_TEAM},
		{"icon": "🎯", "label": "Tácticas", "view": VIEW_TACTICS},
		{"icon": "💸", "label": "Mercado", "view": VIEW_MARKET},
		{"icon": "🤝", "label": "Agentes", "view": VIEW_AGENTS},
		{"icon": "👔", "label": "Empleados", "view": VIEW_EMPLOYEES},
		{"icon": "📅", "label": "Calendario", "view": VIEW_CALENDAR},
		{"icon": "🏆", "label": "Clasificación", "view": VIEW_TABLE},
		{"icon": "🏅", "label": "Champions", "view": VIEW_CHAMPIONS},
		{"icon": "📬", "label": "Inbox", "view": VIEW_INBOX, "badge_count": _inbox_unread_count()},
		{"icon": "📈", "label": "Carrera", "view": VIEW_CAREER},
		{"icon": "💰", "label": "Finanzas", "view": VIEW_FINANCES},
		{"icon": "⚙", "label": "Ajustes", "view": VIEW_SETTINGS},
	]
	sidebar_nav.setup(club_name, club_short, items, "Mánager")
	sidebar_nav.set_active(current_view)


# v0.4.0 Fase B: sincroniza header (título, subtítulo, balance) con la vista
func _refresh_header() -> void:
	if view_title_label == null:
		return
	view_title_label.text = _view_title_for(current_view)
	if header_subtitle != null:
		var jornada_text: String = ""
		if primera_state != null and primera_state.calendar != null:
			jornada_text = "Jornada %d / %d" % [primera_state.current_jornada, primera_state.calendar.size()]
		header_subtitle.text = "Temporada %d-%d  ·  %s" % [year, year + 1, jornada_text]
	# Balance
	if balance_label != null:
		var balance_text: String = "€ —"
		if user_team_id != "":
			var t := _find_team_by_id(user_team_id)
			if t != null and t.finances != null:
				balance_text = "€ %s" % _fmt_eur(t.finances.cash_balance)
		balance_label.text = balance_text


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

	# v0.4.0 Fase B: actualizar sidebar + header del nuevo layout
	_refresh_sidebar()
	_refresh_header()

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
		VIEW_HUB: _render_dashboard_view()
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
		VIEW_INBOX: _render_inbox_view()
		VIEW_AGENTS: _render_agents_view()
		VIEW_SETTINGS: _render_settings_view()


# --------------------------------------------------------------------------- #
# Vista: Clasificación
# --------------------------------------------------------------------------- #
# =========================================================================== #
# Vista: Dashboard (v0.4.0) — NUEVO estilo dashboard moderno
# =========================================================================== #
# Layout:
#   - Fila superior: 4 KPI cards (Posición liga, Forma 5 últimos, Morale, Próximo rival)
#   - Fila media: MiniPitch (once) | LineChart (puntos por jornada)
#   - Fila inferior: DataTable (top 5 Liga) | Shortlist
func _render_dashboard_view() -> void:
	var team := _find_team_by_id(user_team_id) if user_team_id != "" else null
	var theme: UITheme = UIThemeManager.get_current()

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 14)
	content_area.add_child(root)

	# ============ FILA 1: 4 KPI cards ============
	var kpi_row := HBoxContainer.new()
	kpi_row.add_theme_constant_override("separation", 12)
	kpi_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(kpi_row)

	# KPI 1: Posición liga
	var liga_pos: int = 0
	var liga_pts: int = 0
	if team != null:
		var st: DivisionState = primera_state if team.division == "primera" else segunda_state
		if st.league_table != null:
			var sorted_rows: Array = st.league_table.sorted_rows()
			for i in sorted_rows.size():
				var r: LeagueTable.TeamRow = sorted_rows[i]
				if r.team_id == team.id:
					liga_pos = i + 1
					liga_pts = r.won * 3 + r.drawn
					break
	var kpi_liga := KpiCard.new()
	kpi_row.add_child(kpi_liga)
	kpi_liga.set_accent_color(theme.accent_primary)
	kpi_liga.setup("Posición Liga", "%dº" % liga_pos if liga_pos > 0 else "—",
			"%d pts" % liga_pts, "", "flat", "📊")

	# KPI 2: Forma últimos 5
	var form_str: String = ""
	var form_wins: int = 0
	var form_losses: int = 0
	for r: Dictionary in user_recent_results:
		if bool(r.get("won", false)):
			form_str += "V"; form_wins += 1
		elif bool(r.get("lost", false)):
			form_str += "D"; form_losses += 1
		else:
			form_str += "E"
	if form_str.is_empty():
		form_str = "—"
	var form_trend_dir: String = "up" if form_wins > form_losses else ("down" if form_losses > form_wins else "flat")
	var form_trend: String = "+%dV" % form_wins if form_wins > 0 else ""
	var kpi_form := KpiCard.new()
	kpi_row.add_child(kpi_form)
	kpi_form.set_accent_color(theme.accent_success)
	kpi_form.setup("Forma últimos 5", form_str, "%d V · %d D" % [form_wins, form_losses],
			form_trend, form_trend_dir, "📈")

	# KPI 3: Morale promedio
	var morale_avg: float = 0.0
	if team != null and team.players.size() > 0:
		var total: float = 0.0
		for p: Player in team.players:
			total += p.morale
		morale_avg = total / float(team.players.size())
	var morale_str: String = "%d%%" % int(round(morale_avg))
	var morale_dir: String = "up" if morale_avg >= 70 else ("flat" if morale_avg >= 50 else "down")
	var kpi_morale := KpiCard.new()
	kpi_row.add_child(kpi_morale)
	kpi_morale.set_accent_color(theme.accent_warning)
	kpi_morale.setup("Morale plantilla", morale_str, "Promedio %d jugadores" % (team.players.size() if team else 0),
			"", morale_dir, "🟢" if morale_avg >= 70 else ("🟡" if morale_avg >= 50 else "🔴"))

	# KPI 4: Próximo rival
	var rival_name: String = "—"
	var rival_short: String = ""
	if team != null:
		var rival: Team = _find_next_rival(team)
		if rival != null:
			# Recortar sufijos/prefijos genéricos para tener un nombre corto
			# pero LEGIBLE en lugar del code de 3 letras.
			rival_name = _trim_club_name(rival.name)
			rival_short = "Rep %d" % rival.reputation
	var kpi_rival := KpiCard.new()
	kpi_row.add_child(kpi_rival)
	kpi_rival.set_accent_color(theme.accent_info)
	kpi_rival.setup("Próximo rival", rival_name, rival_short, "", "flat", "⚽")

	# ============ FILA 2: MiniPitch | LineChart ============
	var mid_row := HBoxContainer.new()
	mid_row.add_theme_constant_override("separation", 12)
	mid_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(mid_row)

	# Mini pitch con titulares — glass panel
	var pitch_panel := PanelContainer.new()
	pitch_panel.add_theme_stylebox_override("panel", UIThemeManager.glass_panel_style())
	pitch_panel.custom_minimum_size = Vector2(420, 260)
	mid_row.add_child(pitch_panel)
	var pitch_box := VBoxContainer.new()
	pitch_box.add_theme_constant_override("separation", 6)
	pitch_panel.add_child(pitch_box)
	var pitch_title := Label.new()
	pitch_title.text = "STARTING XI"
	pitch_title.add_theme_font_size_override("font_size", 11)
	pitch_title.add_theme_color_override("font_color", theme.text_secondary)
	pitch_box.add_child(pitch_title)
	var mini_pitch := MiniPitch.new()
	mini_pitch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mini_pitch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pitch_box.add_child(mini_pitch)
	var pitch_players: Array = []
	if team != null and not user_lineup_template.is_empty():
		var eleven_ids: Array = user_lineup_template.get("eleven_ids", [])
		var slot_assigns: Array = user_lineup_template.get("slot_assignments", [])
		for i in eleven_ids.size():
			var p: Player = team.find_player(String(eleven_ids[i]))
			if p == null:
				continue
			var slot: String = String(slot_assigns[i]) if i < slot_assigns.size() else "CM"
			pitch_players.append({
				"slot": slot,
				"number": str(p.shirt_number) if p.shirt_number > 0 else "",
				"short_name": _short_name(p.name),
				"is_gk": slot == "GK",
			})
	# Si no hay user lineup, intentar AutoLineup
	if pitch_players.is_empty() and team != null:
		var auto: Lineup = AutoLineup.pick(team, team.tactics_default.formation)
		if auto != null:
			for i in auto.starting_eleven.size():
				var p: Player = auto.starting_eleven[i]
				var slot: String = auto.slot_assignments[i] if i < auto.slot_assignments.size() else "CM"
				pitch_players.append({
					"slot": slot,
					"number": str(p.shirt_number) if p.shirt_number > 0 else "",
					"short_name": _short_name(p.name),
					"is_gk": slot == "GK",
				})
	mini_pitch.setup(pitch_players, true)

	# Line chart: puntos por jornada
	var chart := LineChart.new()
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_row.add_child(chart)
	var labels: Array = []
	for i in user_points_per_jornada.size():
		labels.append("J%d" % (i + 1))
	chart.setup(user_points_per_jornada, labels, "Puntos acumulados (Liga)", "Pts")

	# ============ FILA 3: Tabla Liga (top 5) | Shortlist ============
	var bot_row := HBoxContainer.new()
	bot_row.add_theme_constant_override("separation", 12)
	bot_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(bot_row)

	# Tabla Liga top 5 — menos peso horizontal que el shortlist
	var table_widget := DataTable.new()
	table_widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_widget.size_flags_stretch_ratio = 1.0
	bot_row.add_child(table_widget)
	var columns: Array = [
		{"key": "pos", "label": "#", "width": 30, "align": "right"},
		{"key": "team", "label": "Equipo"},
		{"key": "pj", "label": "PJ", "width": 36, "align": "right"},
		{"key": "pts", "label": "Pts", "width": 44, "align": "right"},
		{"key": "dif", "label": "DG", "width": 40, "align": "right"},
	]
	var rows: Array = []
	if team != null:
		var st_t: DivisionState = primera_state if team.division == "primera" else segunda_state
		if st_t.league_table != null:
			var sorted_rows: Array = st_t.league_table.sorted_rows()
			var max_n: int = min(7, sorted_rows.size())
			for i in range(max_n):
				var r: LeagueTable.TeamRow = sorted_rows[i]
				var t_obj: Team = _find_team_by_id(r.team_id)
				rows.append({
					"pos": "%d" % (i + 1),
					"team": t_obj.name if t_obj else r.team_id,
					"pj": "%d" % r.played,
					"pts": "%d" % (r.won * 3 + r.drawn),
					"dif": "%+d" % (r.goals_for - r.goals_against),
					"highlight": r.team_id == user_team_id,
				})
	var liga_label: String = "Clasificación Liga"
	if team != null:
		liga_label = "Clasificación %s" % ("Primera" if team.division == "primera" else "Segunda")
	table_widget.setup(columns, rows, liga_label, 7)

	# Shortlist — glass panel, más espacio horizontal que la tabla
	var shortlist_panel := PanelContainer.new()
	shortlist_panel.size_flags_stretch_ratio = 1.4
	shortlist_panel.add_theme_stylebox_override("panel", UIThemeManager.glass_panel_style())
	shortlist_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_row.add_child(shortlist_panel)
	var sl_vbox := VBoxContainer.new()
	sl_vbox.add_theme_constant_override("separation", 6)
	shortlist_panel.add_child(sl_vbox)
	var sl_title := Label.new()
	sl_title.text = "SCOUT SHORTLIST"
	sl_title.add_theme_font_size_override("font_size", 11)
	sl_title.add_theme_color_override("font_color", theme.text_secondary)
	sl_vbox.add_child(sl_title)
	if user_shortlist.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Sin jugadores marcados.\nVe al Mercado y pulsa el ✚ para añadir."
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.add_theme_color_override("font_color", theme.text_muted)
		sl_vbox.add_child(empty_lbl)
	else:
		var count_shown: int = 0
		for pid: String in user_shortlist:
			if count_shown >= 8:
				break
			var info: Dictionary = _find_player_dashboard_info(pid)
			if info.is_empty():
				continue
			var row := ShortlistRow.new()
			row.setup(info)
			row.remove_requested.connect(_on_shortlist_remove)
			sl_vbox.add_child(row)
			count_shown += 1


# Devuelve {id, name, pos, age, club, value_eur, tier} para shortlist row
func _find_player_dashboard_info(player_id: String) -> Dictionary:
	for t: Team in all_teams:
		for p: Player in t.players:
			if p.id != player_id:
				continue
			var age: int = p.age_at(year, 7, 1)
			var pos: String = String(p.positions[0]) if p.positions.size() > 0 else "?"
			var val: int = MarketValue.compute(p, year, "")
			return {
				"id": p.id, "name": p.name, "pos": pos, "age": age,
				"club": t.short_name, "value_eur": val, "tier": p.tier,
			}
	return {}


func _on_shortlist_remove(player_id: String) -> void:
	user_shortlist.erase(player_id)
	_refresh_ui()


# Toggle: añade o quita el player_id de user_shortlist. Llamado desde Mercado.
func _on_toggle_shortlist(player_id: String) -> void:
	if player_id in user_shortlist:
		user_shortlist.erase(player_id)
	else:
		user_shortlist.append(player_id)
	_refresh_ui()


# Helper: nombre corto "Lionel Messi" -> "Messi"
func _short_name(full: String) -> String:
	var parts: PackedStringArray = full.split(" ")
	if parts.size() <= 1:
		return full
	return parts[parts.size() - 1]


# Helper: limpia sufijos/prefijos genéricos del nombre oficial de un club
# para mostrarlo en el Dashboard. Mejor que short_name 3-letras y mejor que
# nombre completo largo.
#   "Villarreal Club de Fútbol"     -> "Villarreal"
#   "Real Club Deportivo Mallorca"  -> "Real Mallorca"  (corta solo "Club Deportivo")
#   "Fútbol Club Barcelona"         -> "Barcelona"
#   "Real Madrid Club de Fútbol"    -> "Real Madrid"
#   "Athletic Club"                 -> "Athletic Club"  (no toca, ya es corto)
#   "Club Atlético de Madrid"       -> "Atlético Madrid"
func _trim_club_name(full: String) -> String:
	if full.length() <= 16:
		return full
	var trimmed: String = full
	# Sufijos comunes (orden importa: probar el más largo primero)
	var suffixes: Array = [
		" Club de Fútbol", " Fútbol Club",
		" Club Deportivo", " Club Atlético",
		" CF", " CD", " FC",
	]
	for sfx: String in suffixes:
		if trimmed.ends_with(sfx):
			trimmed = trimmed.substr(0, trimmed.length() - sfx.length()).strip_edges()
			break
	# Prefijos comunes
	var prefixes: Array = [
		"Fútbol Club ", "Club Atlético de ",
		"Club Deportivo ",
	]
	for pfx: String in prefixes:
		if trimmed.begins_with(pfx):
			trimmed = trimmed.substr(pfx.length()).strip_edges()
			break
	# Caso especial: "Real Club Deportivo X" -> "Real X" (más compacto)
	if trimmed.begins_with("Real Club Deportivo "):
		trimmed = "Real " + trimmed.substr("Real Club Deportivo ".length())
	# Fallback: si después de todo sigue siendo absurdamente largo, dejar como está
	# (el auto-shrink del font_size de KpiCard se encarga).
	return trimmed


# Legacy hub view (mantenida temporalmente como reserva — no se renderiza)
# =========================================================================== #
# Vista: 🏠 HUB principal estilo PC Manager (LEGACY — pre-v0.4.0)
# =========================================================================== #
func _render_hub_view_legacy() -> void:
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
	year_lbl.add_theme_font_size_override("font_size", 13)
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
	var unread_inbox: int = _inbox_unread_count()
	var inbox_text: String = "INBOX (%d)" % unread_inbox if unread_inbox > 0 else "INBOX"
	left_col.add_child(_make_quadrant("SEGUIMIENTO", Color(0.32, 0.62, 0.30), [
		["📬", inbox_text, "Mensajes de board, prensa, agentes y eventos del club", _on_select_view.bind(VIEW_INBOX)],
		["📊", "RESULTADOS", "Última jornada con resultados", _on_select_view.bind(VIEW_FIXTURES)],
		["🏆", "CLASIFICACIÓN", "Tabla actual de Liga", _on_select_view.bind(VIEW_TABLE)],
		["📅", "CALENDARIO", "Calendario completo de la temporada", _on_select_view.bind(VIEW_CALENDAR)],
	]))
	# Cuadrante: MERCADO (rojo)
	left_col.add_child(_make_quadrant("MERCADO", Color(0.75, 0.25, 0.25), [
		["💸", "FICHAR", "Mercado de fichajes", _on_select_view.bind(VIEW_MARKET)],
		["👥", "PLANTILLA", "Tu plantilla con stats", _on_select_view.bind(VIEW_TEAM),],
		["🤝", "AGENTES", "Agentes que representan a los jugadores de la liga", _on_select_view.bind(VIEW_AGENTS)],
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
			vs_label.add_theme_font_size_override("font_size", 13)
			vs_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			center_col.add_child(vs_label)
			var rival_logo := _make_team_logo(rival, 64)
			var rival_logo_box := CenterContainer.new()
			rival_logo_box.add_child(rival_logo)
			center_col.add_child(rival_logo_box)
			var rival_name := Label.new()
			rival_name.text = rival.short_name
			rival_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rival_name.add_theme_font_size_override("font_size", 13)
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
	status_mirror.add_theme_font_size_override("font_size", 13)
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
		["AJUSTES", _on_select_view.bind(VIEW_SETTINGS)],
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
		line.add_theme_font_size_override("font_size", 13)
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
			l.add_theme_font_size_override("font_size", 13)
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
		VIEW_INBOX: return "📬 Inbox"
		VIEW_AGENTS: return "🤝 Agentes"
		VIEW_SETTINGS: return "⚙ Settings"
		VIEW_MATCH:     return "📺 Detalle de partido"
		_: return ""


# =========================================================================== #
# Vista: 👔 EMPLEADOS — organigrama del club
# =========================================================================== #
func _render_employees_view() -> void:
	var team := _find_team_by_id(user_team_id)
	if team == null:
		var l := Label.new()
		l.text = "Sin club seleccionado. Inicia 'Nueva partida' desde el menú principal y elige tu club."
		l.add_theme_font_size_override("font_size", 14)
		content_area.add_child(l)
		return
	if team.organigrama == null:
		team.organigrama = OrganigramaFactory.generate(team, year)

	# content_area ya está dentro de un ScrollContainer (en _build_ui),
	# por eso no añadimos otro scroll aquí (causaba doble-scroll y altura 0).
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_area.add_child(box)

	# Header con resumen
	var size_label: String = OrganigramaFactory.size_for(team)
	var pretty_size: String = "GRANDE" if size_label == "grande" else ("MEDIANO" if size_label == "mediano" else "PEQUEÑO")
	var header := Label.new()
	header.text = "👔 Organigrama de %s — Club %s · %d empleados (%d entradas) · %s €/año en salarios" % [
		team.name, pretty_size,
		team.organigrama.total_headcount(),
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
			hl.add_theme_font_size_override("font_size", 13)
			hl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
			grid.add_child(hl)
		for emp: Employee in sec_employees:
			var l_name := Label.new()
			l_name.text = emp.name if emp.count == 1 else "%s ×%d" % [emp.role_label, emp.count]
			l_name.add_theme_font_size_override("font_size", 13)
			grid.add_child(l_name)
			var l_role := Label.new()
			# Si es individual, mostrar el rol; si es grupal, mostrar "—"
			l_role.text = emp.role_label if emp.count == 1 else "—"
			l_role.add_theme_font_size_override("font_size", 13)
			l_role.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
			grid.add_child(l_role)
			var l_q := Label.new()
			l_q.text = "★".repeat(emp.quality) + "☆".repeat(5 - emp.quality)
			l_q.add_theme_font_size_override("font_size", 13)
			l_q.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
			grid.add_child(l_q)
			var l_sal := Label.new()
			if emp.count == 1:
				l_sal.text = "%s €" % TransferMarket._fmt_eur(emp.salary_eur_year)
			else:
				l_sal.text = "%s × %d = %s €" % [
					TransferMarket._fmt_eur(emp.salary_eur_year), emp.count,
					TransferMarket._fmt_eur(emp.total_salary()),
				]
			l_sal.add_theme_font_size_override("font_size", 13)
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
		l.add_theme_font_size_override("font_size", 13)
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
	team_button.add_theme_font_size_override("font_size", 13)
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
	l_pos.add_theme_font_size_override("font_size", 13)
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
		l.add_theme_font_size_override("font_size", 13)
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
	hint.add_theme_font_size_override("font_size", 13)
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
		stats_label.add_theme_font_size_override("font_size", 13)
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

	# Camera A2 light: selector de jugador protagonista (solo en equipo del usuario)
	if selected_team.id == user_team_id and user_team_id != "":
		_render_protagonist_selector()

	# Tabla de plantilla
	var grid := GridContainer.new()
	grid.columns = 14
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	content_area.add_child(grid)

	var headers: Array[String] = ["#", "Nombre", "Pos", "Edad", "Nac", "Tier", "Pot", "Ovr", "Form", "PJ", "G", "A", "Estado", "Cont"]
	for h in headers:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		l.add_theme_font_size_override("font_size", 13)
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
		var form_data: Dictionary = FormTracker.icon_for(p.form)
		var cells: Array[String] = [
			str(p.shirt_number),
			p.name,
			pos_str,
			str(age),
			p.nationality,
			p.tier,
			p.potential_tier,
			str(ovr),
			String(form_data["icon"]),
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


func _render_protagonist_selector() -> void:
	var user_team := _find_team_by_id(user_team_id)
	if user_team == null:
		return
	var box := PanelContainer.new()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	box.add_child(hbox)
	content_area.add_child(box)

	var lbl := Label.new()
	lbl.text = "⭐ Jugador protagonista (Camera A2):"
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(lbl)

	var opt := OptionButton.new()
	opt.add_item("(ninguno)", -1)
	var current_idx: int = 0
	# Lista los jugadores válidos (no lesionados, no cedidos fuera)
	var idx_to_id: Array[String] = [""]
	for i in user_team.players.size():
		var p: Player = user_team.players[i]
		if InjurySystem.is_injured(p):
			continue
		if p.loan_origin_team_id != "" and p.loan_until_year > year:
			continue  # cedido FUERA
		var ovr: int = PlayerFactory.compute_overall(p, p.primary_position())
		var label: String = "%s (%s · OVR %d)" % [p.name, p.primary_position(), ovr]
		opt.add_item(label, opt.item_count - 1)
		idx_to_id.append(p.id)
		if p.id == user_protagonist_id:
			current_idx = idx_to_id.size() - 1
	opt.selected = current_idx
	opt.item_selected.connect(func(idx: int) -> void:
		user_protagonist_id = idx_to_id[idx] if idx < idx_to_id.size() else "")
	hbox.add_child(opt)

	var info := Label.new()
	info.text = "  +30%% probabilidad de ser shooter/asistente · destacado en visor 2D"
	info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info.add_theme_font_size_override("font_size", 13)
	hbox.add_child(info)


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
	popup.min_size = Vector2(320, 180)
	popup.max_size = Vector2(480, 270)
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
	popup.popup_centered(Vector2(320, 180))


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
	# Camera A2 light: pasar el protagonista del usuario si lo hay y está en pista
	if user_protagonist_id != "" and not InjurySystem.is_injured(team.find_player(user_protagonist_id)):
		# Verifica que el protagonista esté en starting_eleven (no en banquillo/lesionado)
		for p in starting:
			if p.id == user_protagonist_id:
				lineup.protagonist_id = user_protagonist_id
				break
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

	# v0.3.2: focus de entrenamiento semanal — bonus al atributo en aging
	var focus_options: Array[String] = ["general", "ataque", "defensa", "fisico", "porteria"]
	_add_option_row(grid_top, "Entrenamiento:", focus_options, team.training_focus, func(v: String) -> void:
		team.training_focus = v)
	var focus_hint := Label.new()
	focus_hint.text = "Entrenamiento aplica +1 al atributo focus de cada jugador (titulares y suplentes) al avanzar de temporada."
	focus_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	focus_hint.add_theme_font_size_override("font_size", 13)
	focus_hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	content_area.add_child(focus_hint)

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
		l.add_theme_font_size_override("font_size", 13)
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
		var action_box := HBoxContainer.new()
		action_box.add_theme_constant_override("separation", 4)
		var btn := Button.new()
		btn.text = "Ofertar %s" % TransferMarket._fmt_eur(value)
		btn.disabled = (value > budget)
		btn.pressed.connect(_on_attempt_buy.bind(p, t, value))
		action_box.add_child(btn)
		var sl_btn := Button.new()
		var in_shortlist: bool = p.id in user_shortlist
		sl_btn.text = "✓" if in_shortlist else "✚"
		sl_btn.tooltip_text = "Quitar de Shortlist" if in_shortlist else "Añadir a Shortlist"
		sl_btn.custom_minimum_size = Vector2(28, 0)
		sl_btn.pressed.connect(_on_toggle_shortlist.bind(p.id))
		action_box.add_child(sl_btn)
		buy_grid.add_child(action_box)

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
		l.add_theme_font_size_override("font_size", 13)
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
	popup.min_size = Vector2(420, 200)
	popup.max_size = Vector2(630, 300)
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
	# v0.3.2: info del agente
	var ag: Agent = _agent_of(player)
	if ag != null:
		var ag_info := Label.new()
		var rel: int = int(ag.relations.get(user_team_id, 0))
		ag_info.text = "🤝 Agente: %s ★%d (%s) — Relación: %+d  ·  Comisión: %d%%" % [
			ag.name, ag.reputation, ag.personality, rel, int(ag.commission_percentage() * 100)]
		ag_info.add_theme_font_size_override("font_size", 13)
		ag_info.add_theme_color_override("font_color", _agent_personality_color(ag.personality))
		box.add_child(ag_info)
	# v0.3.2: persuasion modifier visible si está activo
	if pending_persuasion_modifier != 0.0:
		var mod_info := Label.new()
		mod_info.text = "💬 Charla previa aplicará: %+.0f%% accept" % (pending_persuasion_modifier * 100)
		mod_info.add_theme_color_override("font_color",
			Color(0.5, 0.95, 0.6) if pending_persuasion_modifier > 0 else Color(1.0, 0.5, 0.5))
		mod_info.add_theme_font_size_override("font_size", 13)
		box.add_child(mod_info)
	popup.ok_button_text = "Hacer oferta"
	popup.cancel_button_text = "Cancelar"
	# Botón extra: hablar con el jugador antes de ofertar
	popup.add_button("💬 Convencer primero", true, "talk_first")
	popup.confirmed.connect(func() -> void:
		popup.queue_free()
		_resolve_buy(player, seller_team, fee, accept_p, rng))
	popup.canceled.connect(func() -> void:
		popup.queue_free()
		# Reset persuasion si cancela sin ofertar
		pending_persuasion_modifier = 0.0)
	popup.custom_action.connect(func(action: StringName) -> void:
		if String(action) == "talk_first":
			popup.queue_free()
			_run_persuasion_then_retry_buy(player, seller_team, fee))
	popup.popup_centered(Vector2(420, 200))


func _run_persuasion_then_retry_buy(player: Player, seller_team: Team, fee: int) -> void:
	await _show_persuasion_modal(player)
	# Tras hablar, volver a abrir el modal de oferta (pending_persuasion_modifier
	# está seteado y se aplicará al accept_p)
	_on_attempt_buy(player, seller_team, fee)


func _resolve_buy(player: Player, seller_team: Team, fee: int, accept_p: float, rng: RandomNumberGenerator) -> void:
	var user_team := _find_team_by_id(user_team_id)
	if user_team == null:
		return
	# v0.3.2: aplicar modifier de persuasion (charla previa) y de agente
	accept_p += pending_persuasion_modifier
	pending_persuasion_modifier = 0.0  # se consume
	var ag_eff: Agent = _agent_of(player)
	if ag_eff != null:
		accept_p += ag_eff.accept_prob_modifier(user_team_id)
	accept_p = clampf(accept_p, 0.02, 0.98)
	if rng.randf() > accept_p:
		# Rechazo inicial. Si la oferta estaba en zona "seria" (≥70% MV),
		# el vendedor emite contraoferta pidiendo +15-25%.
		var slot: String = player.primary_position()
		var mv: int = MarketValue.compute(player, year, slot)
		if mv > 0:
			var ratio: float = float(fee) / float(mv)
			if ratio >= 0.7 and ratio < 1.1:
				var bump: float = lerpf(0.25, 0.15, clampf((ratio - 0.7) / 0.4, 0.0, 1.0))
				var counter_fee: int = int(float(fee) * (1.0 + bump))
				_show_counter_offer_modal(player, seller_team, fee, counter_fee)
				return
		status_label.text = "❌ %s rechaza la oferta por %s." % [seller_team.short_name, player.name]
		return
	# Transfer
	seller_team.players.erase(player)
	user_team.players.append(player)
	player.joined_year = year
	user_team.finances.budget_transfers_eur -= fee
	if seller_team.finances:
		seller_team.finances.budget_transfers_eur += fee
	# v0.3.2: agente del jugador gana relación con el club comprador (+8) y
	# pierde con el vendedor (-3). También cobra comisión sobre el fee.
	var ag_buy: Agent = _agent_of(player)
	if ag_buy != null:
		ag_buy.adjust_relation(user_team_id, 8)
		ag_buy.adjust_relation(seller_team.id, -3)
		var commission: int = int(float(fee) * ag_buy.commission_percentage())
		if commission > 0 and user_team.finances != null:
			user_team.finances.cash_balance -= commission
		_inbox_add("agent_offer", "Comisión del agente",
			"%s (★%d %s) cobra %s€ de comisión por el fichaje de %s." % [
				ag_buy.name, ag_buy.reputation, ag_buy.personality,
				TransferMarket._fmt_eur(commission), player.name])
	status_label.text = "✓ %s fichado por %s. Coste: %s" % [player.name, user_team.short_name, TransferMarket._fmt_eur(fee)]
	_refresh_ui()


func _show_counter_offer_modal(player: Player, seller_team: Team, original_fee: int, counter_fee: int) -> void:
	var user_team := _find_team_by_id(user_team_id)
	if user_team == null:
		return
	var popup := ConfirmationDialog.new()
	popup.title = "Contraoferta de %s" % seller_team.short_name
	popup.min_size = Vector2(440, 220)
	popup.max_size = Vector2(660, 330)
	add_child(popup)
	var box := VBoxContainer.new()
	popup.add_child(box)
	var info := Label.new()
	info.text = "%s rechaza tu oferta de %s por %s.\n\nPide %s para aceptar la venta." % [
		seller_team.short_name, TransferMarket._fmt_eur(original_fee), player.name,
		TransferMarket._fmt_eur(counter_fee),
	]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	var budget: int = user_team.finances.budget_transfers_eur if user_team.finances else 0
	if counter_fee > budget:
		var warn := Label.new()
		warn.text = "⚠ Excede tu presupuesto (%s)." % TransferMarket._fmt_eur(budget)
		warn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
		box.add_child(warn)
		popup.get_ok_button().disabled = true
	popup.ok_button_text = "Pagar %s" % TransferMarket._fmt_eur(counter_fee)
	popup.cancel_button_text = "Rechazar"
	popup.confirmed.connect(_on_accept_counter_offer.bind(player, seller_team, counter_fee, popup))
	popup.canceled.connect(_on_reject_counter_offer.bind(player, seller_team, popup))
	popup.popup_centered(Vector2(440, 220))


func _on_accept_counter_offer(player: Player, seller_team: Team, counter_fee: int, popup: ConfirmationDialog) -> void:
	popup.queue_free()
	var user_team := _find_team_by_id(user_team_id)
	if user_team == null or user_team.finances == null:
		return
	if counter_fee > user_team.finances.budget_transfers_eur:
		status_label.text = "Presupuesto insuficiente para la contraoferta."
		return
	seller_team.players.erase(player)
	user_team.players.append(player)
	player.joined_year = year
	user_team.finances.budget_transfers_eur -= counter_fee
	if seller_team.finances:
		seller_team.finances.budget_transfers_eur += counter_fee
	# v0.3.2: agente
	var ag_acc: Agent = _agent_of(player)
	if ag_acc != null:
		ag_acc.adjust_relation(user_team_id, 12)  # más relación que oferta normal
		var commission: int = int(float(counter_fee) * ag_acc.commission_percentage())
		if commission > 0 and user_team.finances != null:
			user_team.finances.cash_balance -= commission
		_inbox_add("agent_offer", "Comisión del agente",
			"%s cobra %s€ por el fichaje de %s tras contraoferta." % [
				ag_acc.name, TransferMarket._fmt_eur(commission), player.name])
	status_label.text = "✓ %s fichado por %s tras contraoferta. Coste: %s" % [
		player.name, user_team.short_name, TransferMarket._fmt_eur(counter_fee),
	]
	_refresh_ui()


func _on_reject_counter_offer(player: Player, seller_team: Team, popup: ConfirmationDialog) -> void:
	popup.queue_free()
	# v0.3.2: rechazar contraoferta enfada al agente. Y todos sus otros clientes
	# son más reticentes a fichar contigo.
	var ag_rej: Agent = _agent_of(player)
	if ag_rej != null:
		ag_rej.adjust_relation(user_team_id, -10)
		_inbox_add("agent_offer", "Agente molesto",
			"%s (representa a %d jugadores) está molesto contigo tras rechazar la contraoferta por %s. Su relación: %d." % [
				ag_rej.name, ag_rej.client_ids.size(), player.name,
				int(ag_rej.relations.get(user_team_id, 0))])
	status_label.text = "❌ Rechazaste la contraoferta de %s por %s." % [seller_team.short_name, player.name]


func _on_attempt_sell(player: Player, fee: int) -> void:
	var popup := ConfirmationDialog.new()
	popup.title = "Vender a %s" % player.name
	popup.min_size = Vector2(380, 160)
	popup.max_size = Vector2(570, 240)
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
	popup.popup_centered(Vector2(380, 160))


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
	popup.min_size = Vector2(420, 240)
	popup.max_size = Vector2(630, 360)
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
	popup.popup_centered(Vector2(420, 240))


# =========================================================================== #
# v0.3.1 — Profundidad mánager: Inbox, Press Conferences, Board, Manager Rep
# =========================================================================== #

func _load_press_templates() -> void:
	var path := "res://data/press_conferences/templates.json"
	if not FileAccess.file_exists(path):
		press_templates = []
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		press_templates = []
		return
	var content := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		press_templates = []
		return
	press_templates = parsed.get("templates", [])


# Añade un mensaje al inbox del usuario (solo si user_team_id está seteado).
func _inbox_add(type_: String, title: String, body: String, data: Dictionary = {}) -> void:
	if user_team_id == "":
		return
	var jornada: int = primera_state.current_jornada if primera_state != null else 0
	var msg: InboxMessage = InboxMessage.make(type_, title, body, year, jornada, data)
	user_inbox.append(msg)
	while user_inbox.size() > 200:
		user_inbox.pop_front()


func _inbox_unread_count() -> int:
	var c: int = 0
	for m in user_inbox:
		if not (m as InboxMessage).read:
			c += 1
	return c


# --------------------------------------------------------------------------- #
# Vista: Inbox
# --------------------------------------------------------------------------- #
func _render_inbox_view() -> void:
	if user_team_id == "":
		var l := Label.new()
		l.text = "Selecciona un club para ver el inbox."
		content_area.add_child(l)
		return

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content_area.add_child(header)

	var title := Label.new()
	title.text = "📬 Inbox del mánager  ·  %d mensajes (%d sin leer)" % [user_inbox.size(), _inbox_unread_count()]
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var mark_btn := Button.new()
	mark_btn.text = "Marcar todo como leído"
	mark_btn.pressed.connect(_on_mark_all_inbox_read)
	header.add_child(mark_btn)

	content_area.add_child(HSeparator.new())

	if user_inbox.is_empty():
		var empty := Label.new()
		empty.text = "(sin mensajes)"
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		content_area.add_child(empty)
		return

	# Más recientes primero
	for i in range(user_inbox.size() - 1, -1, -1):
		var m: InboxMessage = user_inbox[i]
		content_area.add_child(_make_inbox_row(m))


func _on_mark_all_inbox_read() -> void:
	for m in user_inbox:
		(m as InboxMessage).read = true
	_refresh_ui()


func _make_inbox_row(m: InboxMessage) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 10)
	box.add_child(hdr)

	var icon := Label.new()
	icon.text = _inbox_type_icon(m.type)
	icon.add_theme_font_size_override("font_size", 16)
	hdr.add_child(icon)

	var title := Label.new()
	title.text = m.title if m.title != "" else "(sin título)"
	title.add_theme_font_size_override("font_size", 14)
	if not m.read:
		title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	hdr.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(spacer)

	var when_l := Label.new()
	var jornada_text: String = "j%d" % m.jornada_when if m.jornada_when > 0 else "—"
	when_l.text = "[%d · %s]" % [m.year_when, jornada_text]
	when_l.add_theme_font_size_override("font_size", 13)
	when_l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hdr.add_child(when_l)

	if not m.body.is_empty():
		var body_l := Label.new()
		body_l.text = m.body
		body_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_l.add_theme_font_size_override("font_size", 13)
		body_l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		box.add_child(body_l)

	if not m.read:
		var btn := Button.new()
		btn.text = "Marcar como leído"
		btn.flat = true
		btn.pressed.connect(_on_mark_inbox_message_read.bind(m))
		box.add_child(btn)

	return panel


func _on_mark_inbox_message_read(m: InboxMessage) -> void:
	m.read = true
	_refresh_ui()


func _inbox_type_icon(t: String) -> String:
	match t:
		"injury": return "🏥"
		"press": return "🎤"
		"board_message": return "📋"
		"agent_offer": return "🤝"
		"transfer_rumor": return "💬"
		"manager_offer": return "📨"
		"coach_award": return "🏅"
		"objective": return "🎯"
		"national_call": return "🌍"
	return "📩"


# --------------------------------------------------------------------------- #
# Press conference modal (asíncrono)
# --------------------------------------------------------------------------- #
func _show_press_conference_modal() -> bool:
	if press_templates.is_empty() or user_team_id == "":
		return false
	var ctx: String = _press_context()
	var pool: Array = []
	for t in press_templates:
		var tctx: String = String((t as Dictionary).get("context", "always"))
		if tctx == "always" or tctx == ctx:
			pool.append(t)
	if pool.is_empty():
		return false
	var template: Dictionary = pool[randi() % pool.size()]
	var question: String = String(template.get("question", "")).format(_press_placeholders())
	var answers: Array = template.get("answers", [])
	if answers.is_empty():
		return false

	var popup := AcceptDialog.new()
	popup.title = "🎤 Rueda de prensa"
	popup.dialog_close_on_escape = false
	popup.min_size = Vector2(560, 360)
	popup.max_size = Vector2(840, 540)
	add_child(popup)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	popup.add_child(box)

	var q_label := Label.new()
	q_label.text = question
	q_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q_label.add_theme_font_size_override("font_size", 14)
	box.add_child(q_label)

	box.add_child(HSeparator.new())

	var feedback_label := Label.new()
	feedback_label.text = ""
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.add_theme_font_size_override("font_size", 13)
	feedback_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))

	var btn_group := ButtonGroup.new()
	var picked: Array = [-1]
	for i in answers.size():
		var ans: Dictionary = answers[i]
		var btn := Button.new()
		btn.text = "%d. %s" % [i + 1, String(ans.get("label", ""))]
		btn.toggle_mode = true
		btn.button_group = btn_group
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_press_answer_picked.bind(i, answers, feedback_label, picked))
		box.add_child(btn)

	box.add_child(HSeparator.new())
	box.add_child(feedback_label)

	popup.ok_button_text = "Cerrar"
	popup.popup_centered(Vector2(560, 360))
	await popup.confirmed
	popup.queue_free()
	return true


func _on_press_answer_picked(idx: int, answers: Array, feedback_label: Label, picked: Array) -> void:
	if int(picked[0]) >= 0:
		var ans2: Dictionary = answers[idx]
		feedback_label.text = "(Ya respondiste — solo cuenta la primera elección.) %s" % String(ans2.get("feedback", ""))
		return
	picked[0] = idx
	var ans: Dictionary = answers[idx]
	var effects: Dictionary = ans.get("effects", {})
	var team := _find_team_by_id(user_team_id)
	if team != null:
		var morale_delta: int = int(effects.get("morale", 0))
		if morale_delta != 0:
			for p: Player in team.players:
				p.morale = clampf(p.morale + float(morale_delta), 0.0, 100.0)
	manager_reputation = clampi(manager_reputation + int(effects.get("manager_rep", 0)), 0, 99)
	_inbox_add("press", "Rueda de prensa: respuesta",
		"Respuesta: %s\n%s" % [String(ans.get("label", "")), String(ans.get("feedback", ""))])
	feedback_label.text = String(ans.get("feedback", ""))


func _press_context() -> String:
	var st := primera_state
	if st.last_jornada_results.is_empty():
		return "always"
	for r: MatchResult in st.last_jornada_results:
		if r.home_team_id == user_team_id or r.away_team_id == user_team_id:
			var user_won: bool = (r.home_team_id == user_team_id and r.score_home > r.score_away) \
					or (r.away_team_id == user_team_id and r.score_away > r.score_home)
			var user_lost: bool = (r.home_team_id == user_team_id and r.score_home < r.score_away) \
					or (r.away_team_id == user_team_id and r.score_away < r.score_home)
			if user_won: return "after_win"
			if user_lost: return "after_loss"
	return "always"


func _press_placeholders() -> Dictionary:
	var rival_name: String = "el próximo rival"
	var ut := _find_team_by_id(user_team_id)
	var rival_team: Team = _find_next_rival(ut) if ut != null else null
	if rival_team != null:
		rival_name = rival_team.short_name
	var pos_text: String = "?"
	if primera_state.league_table != null:
		var sorted: Array = primera_state.league_table.sorted_rows()
		for i in sorted.size():
			if (sorted[i] as LeagueTable.TeamRow).team_id == user_team_id:
				pos_text = str(i + 1)
				break
	return {
		"rival": rival_name,
		"jornada": primera_state.current_jornada + 1,
		"pos": pos_text,
	}


# --------------------------------------------------------------------------- #
# Board expectations
# --------------------------------------------------------------------------- #
func _ensure_board_expectations() -> void:
	if user_team_id == "":
		return
	if board_expectations != null and board_expectations.year == year:
		return
	var team := _find_team_by_id(user_team_id)
	if team == null:
		return
	board_expectations = BoardExpectations.generate_for_team(team, year)
	_inbox_add("board_message", "Objetivos de temporada %d-%d" % [year, year + 1],
		board_expectations.summary_text(team.name))


func _evaluate_board_mid_season() -> void:
	if board_expectations == null or board_expectations.mid_season_evaluated:
		return
	if user_team_id == "" or primera_state.league_table == null:
		return
	var sorted: Array = primera_state.league_table.sorted_rows()
	var user_pos: int = -1
	for i in sorted.size():
		if (sorted[i] as LeagueTable.TeamRow).team_id == user_team_id:
			user_pos = i + 1
			break
	if user_pos < 0:
		return
	var verdict: String = "ok"
	var msg: String = ""
	if user_pos > board_expectations.target_liga_pos + 4:
		verdict = "failing"
		msg = "Llevas el equipo en posición %d, lejos del objetivo de %d. La paciencia del board es limitada." % [
			user_pos, board_expectations.target_liga_pos]
	elif user_pos > board_expectations.target_liga_pos:
		verdict = "warning"
		msg = "Estás en posición %d, por debajo del objetivo de %d. Hay que mejorar." % [
			user_pos, board_expectations.target_liga_pos]
	else:
		msg = "Vas en posición %d, dentro de lo esperado. Sigue así." % user_pos
	board_expectations.mid_season_evaluated = true
	board_expectations.mid_season_verdict = verdict
	_inbox_add("board_message", "Evaluación de mitad de temporada", msg)


func _evaluate_board_final() -> int:
	if board_expectations == null or user_team_id == "" or primera_state.league_table == null:
		return 0
	var sorted: Array = primera_state.league_table.sorted_rows()
	var user_pos: int = -1
	for i in sorted.size():
		if (sorted[i] as LeagueTable.TeamRow).team_id == user_team_id:
			user_pos = i + 1
			break
	if user_pos < 0:
		return 0
	var delta: int = 0
	var verdict: String = ""
	if user_pos < board_expectations.target_liga_pos:
		verdict = "exceeded"
		delta = 3
	elif user_pos == board_expectations.target_liga_pos:
		verdict = "met"
		delta = 1
	elif user_pos <= board_expectations.target_liga_pos + 3:
		verdict = "missed"
		delta = -2
	else:
		verdict = "failed"
		delta = -5
	board_expectations.final_verdict = verdict
	manager_reputation = clampi(manager_reputation + delta, 0, 99)
	var verdict_text: Dictionary = {
		"exceeded": "¡Has SUPERADO las expectativas! Excelente temporada.",
		"met": "Has cumplido las expectativas. Buen trabajo.",
		"missed": "Has quedado por debajo de las expectativas. Toca mejorar.",
		"failed": "Temporada muy decepcionante. El board está furioso.",
	}
	_inbox_add("board_message", "Evaluación final de temporada",
		"%s\nManager reputation: %+d (ahora %d)." % [verdict_text.get(verdict, "?"), delta, manager_reputation])
	return delta


func _initialize_manager_reputation_from_team() -> void:
	var team := _find_team_by_id(user_team_id)
	if team != null and manager_reputation == 0:
		manager_reputation = team.reputation


# =========================================================================== #
# v0.3.2 — Profundidad jugadores: agentes, form, personality, training focus
# =========================================================================== #

# Genera el pool de agentes la primera vez que se cargan datos. Si ya hay
# agentes (porque viene de un save), respeta esos.
func _ensure_agents_initialized() -> void:
	if agents_pool.size() > 0:
		return
	agents_pool = AgentFactory.generate_and_assign(all_teams, SEED_BASE * 9)


# Lookup helper: agente de un jugador
func _agent_of(player: Player) -> Agent:
	if player == null or player.agent_id == "":
		return null
	return AgentFactory.find_by_player(agents_pool, player)


# Lookup helper: agente por id
func _find_agent(agent_id: String) -> Agent:
	if agent_id == "":
		return null
	return AgentFactory.find_by_id(agents_pool, agent_id)


# --------------------------------------------------------------------------- #
# Vista: Agentes
# --------------------------------------------------------------------------- #
func _render_agents_view() -> void:
	if agents_pool.is_empty():
		var l := Label.new()
		l.text = "Aún no hay agentes generados. Empieza una partida para inicializarlos."
		content_area.add_child(l)
		return

	var header := Label.new()
	header.text = "🤝 Agentes de la liga · %d agentes representan a %d jugadores" % [
		agents_pool.size(), _count_represented_players()]
	header.add_theme_font_size_override("font_size", 16)
	content_area.add_child(header)

	var hint := Label.new()
	hint.text = "Ordenados por reputación (★) y número de clientes. Si tienes mala relación con un agente, sus jugadores son más caros/difíciles de fichar para ti."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	content_area.add_child(hint)

	content_area.add_child(HSeparator.new())

	# Ordenar agentes: rep desc, luego nº clientes desc
	var sorted: Array = agents_pool.duplicate()
	sorted.sort_custom(func(a: Agent, b: Agent) -> bool:
		if a.reputation != b.reputation:
			return a.reputation > b.reputation
		return a.client_ids.size() > b.client_ids.size())

	for a: Agent in sorted:
		content_area.add_child(_make_agent_row(a))

	# Spacer al final para que el último agente no quede pegado al footer
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, 80)
	content_area.add_child(bottom_spacer)


func _count_represented_players() -> int:
	var c: int = 0
	for a: Agent in agents_pool:
		c += a.client_ids.size()
	return c


func _make_agent_row(a: Agent) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 12)
	box.add_child(hdr)

	var name_l := Label.new()
	name_l.text = "%s %s" % ["★".repeat(a.reputation), a.name]
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.add_theme_color_override("font_color", _agent_personality_color(a.personality))
	hdr.add_child(name_l)

	var personality_l := Label.new()
	personality_l.text = "[%s]" % a.personality
	personality_l.add_theme_font_size_override("font_size", 13)
	personality_l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hdr.add_child(personality_l)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(spacer)

	var clients_l := Label.new()
	clients_l.text = "%d clientes" % a.client_ids.size()
	clients_l.add_theme_font_size_override("font_size", 13)
	clients_l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	hdr.add_child(clients_l)

	# Relación con el club del usuario
	if user_team_id != "":
		var rel: int = int(a.relations.get(user_team_id, 0))
		var rel_l := Label.new()
		var rel_color: Color = Color(0.7, 0.7, 0.7)
		var rel_text: String = "neutro"
		if rel >= 30:
			rel_color = Color(0.4, 0.9, 0.5)
			rel_text = "amistoso (%+d)" % rel
		elif rel >= 5:
			rel_color = Color(0.6, 0.85, 0.6)
			rel_text = "cordial (%+d)" % rel
		elif rel <= -30:
			rel_color = Color(0.95, 0.5, 0.4)
			rel_text = "hostil (%d)" % rel
		elif rel <= -5:
			rel_color = Color(0.95, 0.7, 0.5)
			rel_text = "frío (%d)" % rel
		rel_l.text = rel_text
		rel_l.add_theme_color_override("font_color", rel_color)
		rel_l.add_theme_font_size_override("font_size", 13)
		hdr.add_child(rel_l)

	# Lista compacta de clientes (máx 8 visibles)
	if a.client_ids.size() > 0:
		var clients_text: Array[String] = []
		var shown: int = 0
		for cid in a.client_ids:
			if shown >= 8:
				clients_text.append("... y %d más" % (a.client_ids.size() - 8))
				break
			var p: Player = _find_player_globally(cid)
			if p != null:
				var team_short: String = ""
				for t: Team in all_teams:
					if t.find_player(cid) != null:
						team_short = t.short_name
						break
				clients_text.append("%s (%s)" % [p.name, team_short])
				shown += 1
		var clients_label := Label.new()
		clients_label.text = "Representa a: " + ", ".join(clients_text)
		clients_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		clients_label.add_theme_font_size_override("font_size", 13)
		clients_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		box.add_child(clients_label)

	return panel


func _agent_personality_color(personality: String) -> Color:
	match personality:
		"tough": return Color(1.0, 0.5, 0.5)
		"greedy": return Color(1.0, 0.85, 0.4)
		"flexible": return Color(0.5, 0.9, 0.6)
		_: return Color(0.85, 0.85, 0.85)


# --------------------------------------------------------------------------- #
# Talks: speech persuasivo (pre-fichaje) + team talks TED (crisis)
# --------------------------------------------------------------------------- #
func _load_talk_templates() -> void:
	var path := "res://data/talks/templates.json"
	if not FileAccess.file_exists(path):
		talk_templates = []
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		talk_templates = []
		return
	var content := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		talk_templates = []
		return
	talk_templates = parsed.get("templates", [])


func _load_team_talk_templates() -> void:
	var path := "res://data/talks/team_talks.json"
	if not FileAccess.file_exists(path):
		team_talk_templates = []
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		team_talk_templates = []
		return
	var content := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		team_talk_templates = []
		return
	team_talk_templates = parsed.get("templates", [])


# Speech persuasivo pre-fichaje. Setea pending_persuasion_modifier que se
# aplica a la siguiente acceptance check y luego se resetea.
func _show_persuasion_modal(player: Player) -> void:
	if talk_templates.is_empty():
		return
	var template: Dictionary = talk_templates[randi() % talk_templates.size()]
	var topic: String = String(template.get("topic", ""))
	var options: Array = (template.get("options", []) as Array).duplicate()
	options.shuffle()
	if options.is_empty():
		return

	var popup := AcceptDialog.new()
	popup.title = "💬 Convencer a %s" % player.name
	popup.dialog_close_on_escape = false
	popup.min_size = Vector2(560, 400)
	popup.max_size = Vector2(840, 600)
	add_child(popup)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	popup.add_child(box)

	var topic_l := Label.new()
	topic_l.text = topic
	topic_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	topic_l.add_theme_font_size_override("font_size", 14)
	box.add_child(topic_l)

	box.add_child(HSeparator.new())

	var feedback_label := Label.new()
	feedback_label.text = ""
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.add_theme_font_size_override("font_size", 13)

	var picked: Array = [-1]
	for i in options.size():
		var opt: Dictionary = options[i]
		var btn := Button.new()
		btn.text = "%d. %s" % [i + 1, String(opt.get("label", ""))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(_on_persuasion_picked.bind(i, options, feedback_label, picked))
		box.add_child(btn)

	box.add_child(HSeparator.new())
	box.add_child(feedback_label)

	popup.ok_button_text = "Continuar"
	popup.popup_centered(Vector2(560, 400))
	await popup.confirmed
	popup.queue_free()


func _on_persuasion_picked(idx: int, options: Array, feedback_label: Label, picked: Array) -> void:
	if int(picked[0]) >= 0:
		feedback_label.text = "(Solo cuenta la primera elección.)"
		return
	picked[0] = idx
	var opt: Dictionary = options[idx]
	var tone: String = String(opt.get("tone", "neutral"))
	match tone:
		"good": pending_persuasion_modifier = 0.10
		"bad": pending_persuasion_modifier = -0.08
		_: pending_persuasion_modifier = 0.0
	feedback_label.text = String(opt.get("feedback", ""))
	if tone == "good":
		feedback_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6))
	elif tone == "bad":
		feedback_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))


# Team talks (TED): detecta momentos de crisis y dispara modal.
# Se llama tras cada jornada con post_match=true.
func _maybe_trigger_team_talk(post_match: bool = true) -> void:
	if user_team_id == "" or team_talk_templates.is_empty():
		return
	var current_j: int = primera_state.current_jornada
	if current_j - last_team_talk_jornada < 4:
		return
	var trigger: String = _detect_team_talk_trigger(post_match)
	if trigger == "":
		return
	var template: Dictionary = _find_team_talk_template(trigger)
	if template.is_empty():
		return
	last_team_talk_jornada = current_j
	await _show_team_talk_modal(template)


func _detect_team_talk_trigger(post_match: bool) -> String:
	# Solo en crisis (la "concha azul"): humillación o vestuario hundido.
	# No dispara en buenos momentos — es una OPORTUNIDAD para el mánager Ted
	# Lasso que va mal. Le permite levantar al equipo si elige bien.
	var user_team := _find_team_by_id(user_team_id)
	if user_team == null:
		return ""
	if post_match:
		var last_result: MatchResult = _find_user_result_in_last_jornada()
		if last_result != null:
			var is_user_home: bool = last_result.home_team_id == user_team_id
			var user_score: int = last_result.score_home if is_user_home else last_result.score_away
			var rival_score: int = last_result.score_away if is_user_home else last_result.score_home
			# Humillación: derrota por ≥4 goles de diferencia (puntual)
			if rival_score - user_score >= 4:
				return "derrota_4_o_mas_diferencia"
		# Racha de derrotas: 3 últimas seguidas en user_recent_results
		if user_recent_results.size() >= 3:
			var last3: Array = user_recent_results.slice(user_recent_results.size() - 3)
			var all_lost: bool = true
			for r: Dictionary in last3:
				if not bool(r.get("lost", false)):
					all_lost = false
					break
			if all_lost:
				return "3_derrotas_seguidas"
		# Morale promedio bajo (vestuario tenso) — concha azul cuando vas mal
		var morale_sum: float = 0.0
		var morale_count: int = 0
		for p: Player in user_team.players:
			morale_sum += p.morale
			morale_count += 1
		if morale_count > 0 and (morale_sum / morale_count) < 50.0:
			return "morale_promedio_bajo"
	return ""


func _is_top4_team(team_id: String) -> bool:
	if primera_state.league_table == null:
		return false
	var sorted: Array = primera_state.league_table.sorted_rows()
	for i in mini(4, sorted.size()):
		if (sorted[i] as LeagueTable.TeamRow).team_id == team_id:
			return true
	return false


func _find_team_talk_template(trigger: String) -> Dictionary:
	for t in team_talk_templates:
		if String((t as Dictionary).get("trigger", "")) == trigger:
			return t
	return {}


func _show_team_talk_modal(template: Dictionary) -> void:
	var popup := AcceptDialog.new()
	popup.title = "💚 CHARLA DEL VESTUARIO — momento corazón abierto"
	popup.dialog_close_on_escape = false
	popup.min_size = Vector2(640, 520)
	popup.max_size = Vector2(960, 780)
	add_child(popup)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	popup.add_child(box)

	var note := Label.new()
	note.text = "Estás en un momento difícil. Tienes una oportunidad. Elige tus palabras: una de las opciones es la más sincera y humana — sin gritar ni exigir, hablando de tú a tú."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.6, 0.95, 0.7))
	box.add_child(note)

	var intro_l := Label.new()
	intro_l.text = String(template.get("intro", ""))
	intro_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_l.add_theme_font_size_override("font_size", 14)
	intro_l.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	box.add_child(intro_l)

	# Hint sutil: describe el lenguaje corporal de un líder de la plantilla.
	# Da pistas sobre el TONO que espera el vestuario, sin marcar la opción.
	var hint_text: String = _build_team_talk_hint(String(template.get("trigger", "")))
	if hint_text != "":
		var hint_l := Label.new()
		hint_l.text = "✦ " + hint_text
		hint_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint_l.add_theme_font_size_override("font_size", 13)
		hint_l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
		box.add_child(hint_l)

	box.add_child(HSeparator.new())

	var feedback_label := Label.new()
	feedback_label.text = ""
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.add_theme_font_size_override("font_size", 13)

	var options: Array = (template.get("options", []) as Array).duplicate()
	options.shuffle()
	var picked: Array = [-1]
	for i in options.size():
		var opt: Dictionary = options[i]
		var btn := Button.new()
		btn.text = "%d. %s" % [i + 1, String(opt.get("label", ""))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(_on_team_talk_picked.bind(i, options, feedback_label, picked))
		box.add_child(btn)

	box.add_child(HSeparator.new())
	box.add_child(feedback_label)

	popup.ok_button_text = "Cerrar"
	popup.popup_centered(Vector2(640, 520))
	await popup.confirmed
	popup.queue_free()


# Devuelve un líder de la plantilla del usuario para usar en hints. Prioriza
# capitán + líder; si no hay, cualquier líder; si no, el veterano (≥30 años).
# null si no hay nadie destacable.
func _get_team_leader_for_hint() -> Player:
	var team := _find_team_by_id(user_team_id)
	if team == null:
		return null
	# Prioridad 1: capitán + líder
	for p: Player in team.players:
		if p.captain and p.personality == "lider":
			return p
	# Prioridad 2: cualquier líder
	for p: Player in team.players:
		if p.personality == "lider":
			return p
	# Prioridad 3: el más veterano
	var oldest: Player = null
	var oldest_age: int = 0
	for p: Player in team.players:
		var a: int = p.age_at(year, 7, 1)
		if a > oldest_age:
			oldest_age = a
			oldest = p
	return oldest


# Genera el texto del hint según el trigger. Apunta al tono que espera el
# vestuario sin marcar literalmente cuál opción es la "correcta".
func _build_team_talk_hint(trigger: String) -> String:
	var leader: Player = _get_team_leader_for_hint()
	if leader == null:
		return ""
	var ref: String = leader.name
	# Si no es líder explícito, se referencia como "el veterano"
	var role_word: String = "tu capitán" if leader.captain else ("tu líder del vestuario" if leader.personality == "lider" else "el veterano del vestuario")
	match trigger:
		"derrota_4_o_mas_diferencia":
			return "%s (%s) mantiene la mirada baja. No quiere broncas. Necesita oír algo verdadero, no un sermón." % [ref, role_word]
		"3_derrotas_seguidas":
			return "%s (%s) cruza los brazos. Está cansado de discursos vacíos. Si vas a hablar, que sea de tú a tú." % [ref, role_word]
		"morale_promedio_bajo":
			return "%s (%s) te mira directamente. El vestuario espera una mano abierta, no un puño cerrado." % [ref, role_word]
		"vs_top4", "antes_partido_vs_top4":
			return "%s (%s) está nervioso pero no quiere parecerlo. Prefiere quitar presión a sumar exigencia." % [ref, role_word]
		"victoria_vs_top4":
			return "%s (%s) sonríe pero te observa: le importa que reconozcas el mérito de TODOS, no de ti mismo." % [ref, role_word]
	return "%s (%s) te observa. Será sensible al tono que elijas." % [ref, role_word]


func _on_team_talk_picked(idx: int, options: Array, feedback_label: Label, picked: Array) -> void:
	if int(picked[0]) >= 0:
		feedback_label.text = "(Solo cuenta la primera elección.)"
		return
	picked[0] = idx
	var opt: Dictionary = options[idx]
	var tone: String = String(opt.get("tone", "neutral"))
	var morale_delta: int = int(opt.get("morale_delta", 0))
	var form_bonus: float = float(opt.get("form_bonus", 0.0))
	var team := _find_team_by_id(user_team_id)
	if team != null and morale_delta != 0:
		for p: Player in team.players:
			# Personality amplifica/amortigua el impacto
			var personal_mod: float = 1.0
			if p.personality == "lider":
				personal_mod = 1.20
			elif p.personality == "flojo":
				personal_mod = 0.70
			elif p.personality == "temperamental":
				personal_mod = 1.40
			p.morale = clampf(p.morale + float(morale_delta) * personal_mod, 0.0, 100.0)
	team_talk_form_bonus = form_bonus
	_inbox_add("press", "Charla de vestuario",
		"%s\nMorale plantilla %+d, form bonus %+.2f para próximo partido." % [
			String(opt.get("feedback", "")), morale_delta, form_bonus])
	feedback_label.text = String(opt.get("feedback", ""))
	if tone == "good":
		feedback_label.add_theme_color_override("font_color", Color(0.5, 0.95, 0.6))
	elif tone == "bad":
		feedback_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))


# Asigna personality a los jugadores que la tienen vacía (carga inicial).
# Distribución: 20% líder, 55% equilibrado, 15% temperamental, 10% flojo.
# Líderes son más probables en tier S/A; flojos más en C/Y.
func _ensure_personalities_initialized() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_BASE * 11
	for t: Team in all_teams:
		for p: Player in t.players:
			if p.personality != "":
				continue
			var roll: float = rng.randf()
			# Bias por tier
			var lider_thr: float = 0.20
			var temp_thr: float = 0.85  # 0.20+0.55=0.75 base, +0.10 = temp
			var flojo_thr: float = 0.95  # +0.10 = flojo last
			if p.tier == "S":
				lider_thr = 0.40
			elif p.tier == "A":
				lider_thr = 0.30
			elif p.tier == "C" or p.tier == "Y":
				lider_thr = 0.10
				flojo_thr = 0.90  # más flojos en bottom tiers
			if roll < lider_thr:
				p.personality = "lider"
			elif roll < 0.75:
				p.personality = "equilibrado"
			elif roll < flojo_thr:
				p.personality = "temperamental"
			else:
				p.personality = "flojo"


# Tras un partido: actualiza form de los 22 titulares según rating individual.
func _update_form_for_match(home_lineup: Lineup, away_lineup: Lineup, result: MatchResult) -> void:
	var home_won: bool = result.score_home > result.score_away
	var home_lost: bool = result.score_home < result.score_away
	# Mapas de stats por player_id en este partido
	var goals_by_id: Dictionary = {}  # pid -> int
	var assists_by_id: Dictionary = {}
	for pid in result.scorers.keys():
		goals_by_id[pid] = int(result.scorers[pid])
	for ev: MatchEvent in result.events:
		if ev.type == MatchEvent.T_GOAL and ev.secondary_player_id != "":
			assists_by_id[ev.secondary_player_id] = int(assists_by_id.get(ev.secondary_player_id, 0)) + 1
	# Tarjetas
	var yellows_by_id: Dictionary = {}
	var reds_by_id: Dictionary = {}
	for pid in result.cards.keys():
		var c: Dictionary = result.cards[pid]
		yellows_by_id[pid] = int(c.get("yellows", 0))
		if bool(c.get("red", false)):
			reds_by_id[pid] = 1
	var away_won: bool = result.score_away > result.score_home
	var away_lost: bool = result.score_away < result.score_home
	var team_data: Array = [
		{"lineup": home_lineup, "won": home_won, "lost": home_lost},
		{"lineup": away_lineup, "won": away_won, "lost": away_lost},
	]
	for td: Dictionary in team_data:
		var lineup: Lineup = td["lineup"]
		if lineup == null:
			continue
		var won: bool = bool(td["won"])
		var lost: bool = bool(td["lost"])
		for p: Player in lineup.starting_eleven:
			var rating: float = FormTracker.compute_rating(
				int(goals_by_id.get(p.id, 0)),
				int(assists_by_id.get(p.id, 0)),
				int(yellows_by_id.get(p.id, 0)),
				int(reds_by_id.get(p.id, 0)),
				won, lost)
			FormTracker.update_after_match(p, rating)
		# Suplentes que NO entraron: leve regresión a la media
		for p2: Player in lineup.subs_available:
			FormTracker.update_no_play(p2)


# =========================================================================== #
# v0.4.0 Fase A — Vista Settings (toggle dark/light)
# =========================================================================== #
func _render_settings_view() -> void:
	var header := Label.new()
	header.text = "⚙ Ajustes"
	header.add_theme_font_size_override("font_size", 18)
	content_area.add_child(header)
	content_area.add_child(HSeparator.new())

	# Sección: Tema visual
	var theme_section := Label.new()
	theme_section.text = "Tema visual"
	theme_section.add_theme_font_size_override("font_size", 14)
	theme_section.add_theme_color_override("font_color", UIThemeManager.get_current().accent_warning)
	content_area.add_child(theme_section)

	var theme_hint := Label.new()
	theme_hint.text = "Elige entre tema oscuro (default, mejor para sesiones largas) o tema claro (estilo dashboard moderno)."
	theme_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	theme_hint.add_theme_font_size_override("font_size", 13)
	theme_hint.add_theme_color_override("font_color", UIThemeManager.get_current().text_secondary)
	content_area.add_child(theme_hint)

	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 10)
	content_area.add_child(theme_row)

	var current_name: String = UIThemeManager.get_current_name()

	var dark_btn := Button.new()
	dark_btn.text = "🌙 Oscuro" + ("  ✓" if current_name == UIThemeManager.THEME_DARK else "")
	dark_btn.toggle_mode = true
	dark_btn.button_pressed = (current_name == UIThemeManager.THEME_DARK)
	dark_btn.pressed.connect(_on_theme_selected.bind(UIThemeManager.THEME_DARK))
	theme_row.add_child(dark_btn)

	var light_btn := Button.new()
	light_btn.text = "☀ Claro" + ("  ✓" if current_name == UIThemeManager.THEME_LIGHT else "")
	light_btn.toggle_mode = true
	light_btn.button_pressed = (current_name == UIThemeManager.THEME_LIGHT)
	light_btn.pressed.connect(_on_theme_selected.bind(UIThemeManager.THEME_LIGHT))
	theme_row.add_child(light_btn)

	content_area.add_child(HSeparator.new())

	# Sección: persistencia
	var note := Label.new()
	note.text = "Los ajustes se guardan en user://settings.json y persisten al reiniciar el juego."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", UIThemeManager.get_current().text_muted)
	content_area.add_child(note)

	# v0.4.0 fases B-E: aquí irán más opciones (volumen, idioma, etc.)
	content_area.add_child(HSeparator.new())
	var future := Label.new()
	future.text = "Más opciones disponibles en próximas versiones (volumen, idioma, animaciones)."
	future.add_theme_font_size_override("font_size", 13)
	future.add_theme_color_override("font_color", UIThemeManager.get_current().text_muted)
	content_area.add_child(future)


func _on_theme_selected(theme_name: String) -> void:
	if UIThemeManager.apply(theme_name):
		UserSettings.set_theme_name(theme_name)
		status_label.text = "Tema cambiado a '%s'. Recarga la partida o reabre el juego para ver los cambios completos." % theme_name
	_refresh_ui()
