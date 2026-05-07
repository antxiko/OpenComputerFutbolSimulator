extends Control

# Pantalla principal del simulador (MVP).
#
# Lo que hace:
# - Carga los 42 equipos al iniciar.
# - Muestra la tabla de Primera y la jornada actual.
# - Botones para avanzar 1 jornada o la temporada completa.
# - Botón para resetear y empezar otra temporada.
#
# La UI se construye programáticamente en _build_ui(). Cuando ya tengamos un
# diseño estable la podemos extraer a una .tscn editable en el inspector de Godot.

const SEASON_YEAR_INITIAL := 2026
const SEED_BASE := 42

# Estado del juego
var all_teams: Array = []
var primera: Array = []
var segunda: Array = []
var calendar_primera: Array = []
var current_jornada: int = 0
var league_table: LeagueTable
var year: int = SEASON_YEAR_INITIAL
var match_seed_counter: int = 0
var division_view: String = "primera"  # "primera" | "segunda" — de momento solo Primera

# Referencias UI (asignadas en _build_ui)
var year_label: Label
var jornada_label: Label
var division_label: Label
var status_label: Label
var table_grid: GridContainer
var advance_button: Button
var advance_all_button: Button
var reset_button: Button
var primera_tab_button: Button
var segunda_tab_button: Button


func _ready() -> void:
	_build_ui()
	_load_data()
	_start_season()


# ============================================================================
# Construcción de UI (programática)
# ============================================================================
func _build_ui() -> void:
	# El nodo raíz (este Control) ocupa todo el viewport.
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
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Top bar: título + año + jornada
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 24)
	vbox.add_child(top_bar)

	var title_label := Label.new()
	title_label.text = "OpenComputerFutbolSimulator"
	title_label.add_theme_font_size_override("font_size", 22)
	top_bar.add_child(title_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	year_label = Label.new()
	year_label.add_theme_font_size_override("font_size", 18)
	top_bar.add_child(year_label)

	jornada_label = Label.new()
	jornada_label.add_theme_font_size_override("font_size", 18)
	top_bar.add_child(jornada_label)

	# Separador visual
	var separator := HSeparator.new()
	vbox.add_child(separator)

	# Selector de división (botones tipo tab)
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 4)
	vbox.add_child(tab_bar)

	primera_tab_button = Button.new()
	primera_tab_button.text = "  Primera  "
	primera_tab_button.pressed.connect(_on_select_division.bind("primera"))
	tab_bar.add_child(primera_tab_button)

	segunda_tab_button = Button.new()
	segunda_tab_button.text = "  Segunda  "
	segunda_tab_button.pressed.connect(_on_select_division.bind("segunda"))
	tab_bar.add_child(segunda_tab_button)

	division_label = Label.new()
	division_label.add_theme_font_size_override("font_size", 14)
	division_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	tab_bar.add_child(division_label)

	# Tabla — usamos ScrollContainer + GridContainer
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	table_grid = GridContainer.new()
	table_grid.columns = 10  # Pos, Equipo, PJ, G, E, P, GF, GC, DG, Pts
	table_grid.add_theme_constant_override("h_separation", 18)
	table_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(table_grid)

	# Bottom bar: status + botones
	var bottom_bar := HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 12)
	vbox.add_child(bottom_bar)

	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	bottom_bar.add_child(status_label)

	advance_button = Button.new()
	advance_button.text = "Siguiente jornada"
	advance_button.pressed.connect(_on_advance_jornada)
	bottom_bar.add_child(advance_button)

	advance_all_button = Button.new()
	advance_all_button.text = "Toda la temporada"
	advance_all_button.pressed.connect(_on_advance_full_season)
	bottom_bar.add_child(advance_all_button)

	reset_button = Button.new()
	reset_button.text = "Nueva temporada"
	reset_button.pressed.connect(_on_reset_season)
	bottom_bar.add_child(reset_button)


# ============================================================================
# Carga inicial de datos
# ============================================================================
func _load_data() -> void:
	var loaded := DataLoader.load_all_teams(year)
	if loaded.errors.size() > 0:
		status_label.text = "ERROR: %d errores cargando datos." % loaded.errors.size()
		for e in loaded.errors:
			push_error(e)
		return
	all_teams = loaded.teams.values()
	primera = all_teams.filter(func(t: Team) -> bool: return t.division == "primera")
	segunda = all_teams.filter(func(t: Team) -> bool: return t.division == "segunda")
	status_label.text = "Cargados %d equipos, %d jugadores." % [
		all_teams.size(), loaded.player_id_index.size()]


# ============================================================================
# Gestión de la temporada
# ============================================================================
func _start_season() -> void:
	primera = all_teams.filter(func(t: Team) -> bool: return t.division == "primera")
	segunda = all_teams.filter(func(t: Team) -> bool: return t.division == "segunda")
	var primera_ids: Array = primera.map(func(t: Team) -> String: return t.id)
	calendar_primera = CalendarGenerator.generate(primera_ids, SEED_BASE)
	current_jornada = 0
	league_table = LeagueTable.new()
	league_table.init_with_teams(primera)
	match_seed_counter = SEED_BASE * 1000
	_refresh_ui()


func _on_advance_jornada() -> void:
	if current_jornada >= calendar_primera.size():
		status_label.text = "Temporada completada. Pulsa 'Nueva temporada' para reiniciar."
		return
	_simulate_jornada(current_jornada)
	current_jornada += 1
	_refresh_ui()


func _on_advance_full_season() -> void:
	advance_button.disabled = true
	advance_all_button.disabled = true
	reset_button.disabled = true
	# Yield al refresco cada 3 jornadas para que la UI se actualice durante el cómputo.
	while current_jornada < calendar_primera.size():
		_simulate_jornada(current_jornada)
		current_jornada += 1
		if current_jornada % 3 == 0:
			_refresh_ui()
			await get_tree().process_frame
	_refresh_ui()
	advance_button.disabled = false
	advance_all_button.disabled = false
	reset_button.disabled = false


func _on_reset_season() -> void:
	year += 1
	# Aging + retiros + canteranos antes de la siguiente temporada
	Aging.age_all(all_teams, year, SEED_BASE * 100)
	for t in all_teams:
		Cantera.fill_squad_if_needed(t, year, SEED_BASE * 50)
	# (Por simplicidad v1 no aplicamos asc/desc desde la UI; lo añadimos cuando integremos CareerSimulator)
	_start_season()


func _on_select_division(div: String) -> void:
	division_view = div
	_refresh_ui()


func _simulate_jornada(jornada_idx: int) -> void:
	var jornada: Array = calendar_primera[jornada_idx]
	var team_index: Dictionary = {}
	for t: Team in primera:
		team_index[t.id] = t
		# Restablecer condition antes de cada jornada (simplificación v1)
		for p: Player in t.players:
			p.condition = 100.0

	for fixture: Dictionary in jornada:
		var home: Team = team_index[fixture["home_id"]]
		var away: Team = team_index[fixture["away_id"]]
		var home_lineup := AutoLineup.pick(home, home.tactics_default.formation)
		var away_lineup := AutoLineup.pick(away, away.tactics_default.formation)
		match_seed_counter += 1
		var result: MatchResult = MatchEngine.simulate(home_lineup, away_lineup, match_seed_counter)
		if result != null:
			league_table.record_match(result)


# ============================================================================
# Refresco de UI
# ============================================================================
func _refresh_ui() -> void:
	year_label.text = "Temporada %d-%d" % [year, year + 1]
	jornada_label.text = "Jornada %d / %d" % [current_jornada, calendar_primera.size()]
	division_label.text = "(viendo: %s)" % division_view.capitalize()
	# Estilo botones de tabs activos
	primera_tab_button.disabled = (division_view == "primera")
	segunda_tab_button.disabled = (division_view == "segunda")
	_populate_table()


func _populate_table() -> void:
	# Limpiar contenido previo
	for c in table_grid.get_children():
		c.queue_free()

	# Cabecera
	var headers: Array[String] = ["Pos", "Equipo", "PJ", "G", "E", "P", "GF", "GC", "DG", "Pts"]
	for h in headers:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		l.add_theme_font_size_override("font_size", 13)
		table_grid.add_child(l)

	# Para v1 solo mostramos Primera (la tabla de Segunda la activamos cuando tengamos calendar_segunda)
	if division_view == "segunda":
		# Mostrar mensaje placeholder
		for i in 10:
			var l := Label.new()
			if i == 1:
				l.text = "Vista de Segunda — pendiente. Cambia a Primera por ahora."
			table_grid.add_child(l)
		return

	# Filas Primera ordenadas
	if league_table == null:
		return
	var sorted: Array = league_table.sorted_rows()
	var pos: int = 1
	for row: LeagueTable.TeamRow in sorted:
		_add_row(pos, row)
		pos += 1


func _add_row(pos: int, row: LeagueTable.TeamRow) -> void:
	var cells: Array[String] = [
		str(pos),
		row.team_name,
		str(row.played),
		str(row.won),
		str(row.drawn),
		str(row.lost),
		str(row.goals_for),
		str(row.goals_against),
		"%+d" % row.goal_diff(),
		str(row.points()),
	]
	# Color por posición: verde top 4 (Champions), azul 5-6 (Europa), rojo último 3 (descenso)
	var color: Color = Color(1, 1, 1)
	if pos <= 4:
		color = Color(0.6, 1.0, 0.7)
	elif pos <= 6:
		color = Color(0.6, 0.8, 1.0)
	elif pos >= 18:
		color = Color(1.0, 0.65, 0.65)

	for i in cells.size():
		var l := Label.new()
		l.text = cells[i]
		l.add_theme_color_override("font_color", color)
		# Equipo alineado a la izquierda, números centrados/derecha
		if i == 1:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		table_grid.add_child(l)
