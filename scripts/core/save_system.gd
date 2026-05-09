class_name SaveSystem extends RefCounted

# Sistema de guardado/carga de partida.
#
# Diseño v1:
#   - Saves van a user://saves/<slot>.json (path persistente, fuera del repo).
#   - Cada save guarda: año actual, estado completo de los 42 equipos
#     (incluyendo divisiones, plantillas, contratos, condition, morale).
#   - El calendario y la tabla de liga se regeneran al cargar usando un seed
#     determinista. Si quieres preservar mid-season, también se guarda la
#     jornada actual + el snapshot de la tabla.
#
# Si en el futuro queremos guardar también los eventos de partidos previos,
# añadiremos un fichero secundario por partido.

const SAVE_DIR := "user://saves/"
const SAVE_VERSION := 1


class SaveData:
	var version: int = 0
	var saved_at: String = ""
	var year: int = 0
	var teams: Array = []  # Array[Team] reconstruidos
	var primera_jornada: int = 0
	var segunda_jornada: int = 0
	var primera_table_snapshot: Dictionary = {}  # team_id -> {played, won, drawn, lost, gf, ga}
	var segunda_table_snapshot: Dictionary = {}
	var user_team_id: String = ""
	var user_lineup_template: Dictionary = {}
	var user_career_history: Array = []
	var user_protagonist_id: String = ""


# ============================================================================
# Save
# ============================================================================
static func save_game(slot_name: String, year: int, all_teams: Array,
		primera_jornada: int, segunda_jornada: int,
		primera_table: LeagueTable, segunda_table: LeagueTable,
		user_team_id: String = "", user_lineup_template: Dictionary = {},
		user_career_history: Array = [], user_protagonist_id: String = "") -> Dictionary:
	# Crear directorio
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		var err: int = DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		if err != OK:
			return { "ok": false, "error": "no se pudo crear %s" % SAVE_DIR }

	var data: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"year": year,
		"primera_jornada": primera_jornada,
		"segunda_jornada": segunda_jornada,
		"primera_table_snapshot": _serialize_table(primera_table),
		"segunda_table_snapshot": _serialize_table(segunda_table),
		"user_team_id": user_team_id,
		"user_lineup_template": user_lineup_template.duplicate(true),
		"user_career_history": user_career_history.duplicate(true),
		"user_protagonist_id": user_protagonist_id,
		"teams": all_teams.map(func(t: Team) -> Dictionary: return _team_to_dict(t)),
	}

	var path: String = "%s%s.json" % [SAVE_DIR, slot_name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return { "ok": false, "error": "no se pudo abrir %s para escritura" % path }
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return { "ok": true, "path": path, "saved_at": data["saved_at"] }


# ============================================================================
# Load
# ============================================================================
static func load_game(slot_name: String) -> SaveData:
	var path: String = "%s%s.json" % [SAVE_DIR, slot_name]
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var content: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Save inválido (no es JSON object): %s" % path)
		return null
	var save_data := SaveData.new()
	save_data.version = int(parsed.get("version", 0))
	save_data.saved_at = String(parsed.get("saved_at", ""))
	save_data.year = int(parsed.get("year", 2026))
	save_data.primera_jornada = int(parsed.get("primera_jornada", 0))
	save_data.segunda_jornada = int(parsed.get("segunda_jornada", 0))
	save_data.primera_table_snapshot = parsed.get("primera_table_snapshot", {}).duplicate()
	save_data.segunda_table_snapshot = parsed.get("segunda_table_snapshot", {}).duplicate()
	save_data.user_team_id = String(parsed.get("user_team_id", ""))
	save_data.user_lineup_template = parsed.get("user_lineup_template", {}).duplicate(true)
	save_data.user_career_history = parsed.get("user_career_history", []).duplicate(true)
	save_data.user_protagonist_id = String(parsed.get("user_protagonist_id", ""))
	# Reconstruir equipos desde el dict
	save_data.teams = []
	for team_dict in parsed.get("teams", []):
		var t: Team = _team_from_dict(team_dict)
		save_data.teams.append(t)
	return save_data


# ============================================================================
# List / Delete
# ============================================================================
static func list_saves() -> Array:
	# Devuelve [{ slot, saved_at, year }, ...]
	var out: Array = []
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return out
	var dir := DirAccess.open(SAVE_DIR)
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var slot: String = fname.substr(0, fname.length() - 5)
			var meta: Dictionary = _peek_save(SAVE_DIR + fname)
			meta["slot"] = slot
			out.append(meta)
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("saved_at", "")) > String(b.get("saved_at", "")))
	return out


static func delete_save(slot_name: String) -> bool:
	var path: String = "%s%s.json" % [SAVE_DIR, slot_name]
	if not FileAccess.file_exists(path):
		return false
	var dir := DirAccess.open(SAVE_DIR)
	return dir.remove(slot_name + ".json") == OK


static func _peek_save(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return { "saved_at": "?", "year": 0, "user_team_id": "", "primera_jornada": 0 }
	var content: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		return { "saved_at": "?", "year": 0, "user_team_id": "", "primera_jornada": 0 }
	return {
		"saved_at": String(parsed.get("saved_at", "")),
		"year": int(parsed.get("year", 2026)),
		"user_team_id": String(parsed.get("user_team_id", "")),
		"primera_jornada": int(parsed.get("primera_jornada", 0)),
		"segunda_jornada": int(parsed.get("segunda_jornada", 0)),
		"career_seasons": int((parsed.get("user_career_history", []) as Array).size()),
	}


# Devuelve true si el slot solicitado existe.
static func slot_exists(slot_name: String) -> bool:
	return FileAccess.file_exists("%s%s.json" % [SAVE_DIR, slot_name])


# Sanea un nombre de slot introducido por el usuario para que sea un nombre
# de fichero seguro: solo letras, números, guión bajo y guión.
static func sanitize_slot_name(raw: String) -> String:
	var s: String = raw.strip_edges().to_lower()
	var out: String = ""
	for i in s.length():
		var ch: String = s[i]
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
		elif ch == " ":
			out += "_"
	if out.is_empty():
		out = "save"
	if out.length() > 32:
		out = out.substr(0, 32)
	return out


# ============================================================================
# Serialización de Team
# ============================================================================
static func _team_to_dict(t: Team) -> Dictionary:
	return {
		"id": t.id,
		"name": t.name,
		"short_name": t.short_name,
		"city": t.city,
		"founded": t.founded,
		"stadium": _stadium_to_dict(t.stadium),
		"colors": t.colors.duplicate(),
		"division": t.division,
		"reputation": t.reputation,
		"signing_policy": t.signing_policy,
		"manager": _manager_to_dict(t.manager),
		"tactics_default": _tactics_to_dict(t.tactics_default),
		"finances": _finances_to_dict(t.finances),
		"staff": _staff_to_dict(t.staff),
		"organigrama": t.organigrama.to_dict() if t.organigrama else {},
		"players": t.players.map(func(p: Player) -> Dictionary: return _player_to_dict(p)),
	}


static func _team_from_dict(d: Dictionary) -> Team:
	var t: Team = Team.from_dict(d)
	# Restaurar campos runtime de jugadores que from_dict no recupera por defecto
	for i in t.players.size():
		var p: Player = t.players[i]
		var pd: Dictionary = d["players"][i]
		p.attributes = pd.get("attributes", {}).duplicate()
		p.potential = int(pd.get("potential", 0))
		p.condition = float(pd.get("condition", 100.0))
		p.morale = float(pd.get("morale", 70.0))
		p.injury = pd.get("injury", {}).duplicate()
		p.yellow_cards_season = int(pd.get("yellow_cards_season", 0))
		p.red_cards_season = int(pd.get("red_cards_season", 0))
		p.suspended_matches = int(pd.get("suspended_matches", 0))
		p.aggression = int(pd.get("aggression", 0))
		p.basque_eligible = bool(pd.get("basque_eligible", false))
		p.loan_origin_team_id = String(pd.get("loan_origin_team_id", ""))
		p.loan_until_year = int(pd.get("loan_until_year", 0))
		p.season_goals = int(pd.get("season_goals", 0))
		p.season_assists = int(pd.get("season_assists", 0))
		p.season_matches = int(pd.get("season_matches", 0))
		p.season_minutes = int(pd.get("season_minutes", 0))
		p.last_match_date = pd.get("last_match_date", {}).duplicate()
		p.history = pd.get("history", []).duplicate()
	return t


static func _player_to_dict(p: Player) -> Dictionary:
	return {
		"id": p.id, "name": p.name,
		"birth_date": p.birth_date.duplicate(),
		"nationality": p.nationality,
		"positions": p.positions.duplicate(),
		"preferred_foot": p.preferred_foot,
		"shirt_number": p.shirt_number, "captain": p.captain,
		"traits": p.traits.duplicate(),
		"joined_year": p.joined_year,
		"tier": p.tier, "potential_tier": p.potential_tier,
		"overrides": p.overrides.duplicate(),
		"attributes": p.attributes.duplicate(),
		"potential": p.potential,
		"condition": p.condition, "morale": p.morale,
		"injury": p.injury.duplicate(),
		"yellow_cards_season": p.yellow_cards_season,
		"red_cards_season": p.red_cards_season,
		"suspended_matches": p.suspended_matches,
		"aggression": p.aggression,
		"basque_eligible": p.basque_eligible,
		"loan_origin_team_id": p.loan_origin_team_id,
		"loan_until_year": p.loan_until_year,
		"season_goals": p.season_goals,
		"season_assists": p.season_assists,
		"season_matches": p.season_matches,
		"season_minutes": p.season_minutes,
		"last_match_date": p.last_match_date.duplicate() if p.last_match_date else {},
		"history": p.history.duplicate(),
		"contract": _contract_to_dict(p.contract),
	}


static func _contract_to_dict(c: ContractInfo) -> Dictionary:
	if c == null:
		return {"until_year": 0, "salary_eur_year": 0, "release_clause_eur": 0}
	return {"until_year": c.until_year, "salary_eur_year": c.salary_eur_year, "release_clause_eur": c.release_clause_eur}


static func _manager_to_dict(m: ManagerInfo) -> Dictionary:
	if m == null:
		return {}
	return {"name": m.name, "nationality": m.nationality, "birth_year": m.birth_year,
			"preferred_formation": m.preferred_formation, "preferred_style": m.preferred_style}


static func _tactics_to_dict(t: Tactics) -> Dictionary:
	if t == null:
		return {}
	return {"formation": t.formation, "mentality": t.mentality, "tempo": t.tempo,
			"pressing": t.pressing, "width": t.width}


static func _finances_to_dict(f: FinancesInfo) -> Dictionary:
	if f == null:
		return {}
	return {"budget_transfers_eur": f.budget_transfers_eur,
			"wage_budget_eur_year": f.wage_budget_eur_year,
			"tv_revenue_eur_year": f.tv_revenue_eur_year,
			"cash_balance": f.cash_balance,
			"last_season_summary": f.last_season_summary.duplicate(true),
			"sponsors": f.sponsors.duplicate(true),
			"ongoing_projects": f.ongoing_projects.duplicate(true)}


static func _staff_to_dict(s: StaffInfo) -> Dictionary:
	if s == null:
		return {}
	return {"fitness_coach": s.fitness_coach, "scout_chief": s.scout_chief,
			"youth_coach": s.youth_coach, "physio": s.physio}


static func _stadium_to_dict(s: StadiumInfo) -> Dictionary:
	if s == null:
		return {}
	return {"name": s.name, "capacity": s.capacity, "tier": s.tier,
			"state": s.state, "upgrades": s.upgrades.duplicate()}


static func _serialize_table(table: LeagueTable) -> Dictionary:
	if table == null:
		return {}
	var out: Dictionary = {}
	for tid in table.rows.keys():
		var r: LeagueTable.TeamRow = table.rows[tid]
		out[tid] = {
			"played": r.played, "won": r.won, "drawn": r.drawn, "lost": r.lost,
			"goals_for": r.goals_for, "goals_against": r.goals_against,
		}
	return out


# Restaura una LeagueTable a partir de un snapshot de save.
static func restore_table(snapshot: Dictionary, teams: Array) -> LeagueTable:
	var table := LeagueTable.new()
	table.init_with_teams(teams)
	for tid in snapshot.keys():
		if not table.rows.has(tid):
			continue
		var r: LeagueTable.TeamRow = table.rows[tid]
		var s: Dictionary = snapshot[tid]
		r.played = int(s.get("played", 0))
		r.won = int(s.get("won", 0))
		r.drawn = int(s.get("drawn", 0))
		r.lost = int(s.get("lost", 0))
		r.goals_for = int(s.get("goals_for", 0))
		r.goals_against = int(s.get("goals_against", 0))
	return table
