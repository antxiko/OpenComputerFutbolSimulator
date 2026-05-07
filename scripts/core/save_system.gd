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


# ============================================================================
# Save
# ============================================================================
static func save_game(slot_name: String, year: int, all_teams: Array,
		primera_jornada: int, segunda_jornada: int,
		primera_table: LeagueTable, segunda_table: LeagueTable) -> Dictionary:
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
		return { "saved_at": "?", "year": 0 }
	var content: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		return { "saved_at": "?", "year": 0 }
	return {
		"saved_at": String(parsed.get("saved_at", "")),
		"year": int(parsed.get("year", 0)),
	}


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
		"stadium": {"name": t.stadium.name, "capacity": t.stadium.capacity} if t.stadium else {},
		"colors": t.colors.duplicate(),
		"division": t.division,
		"reputation": t.reputation,
		"signing_policy": t.signing_policy,
		"manager": _manager_to_dict(t.manager),
		"tactics_default": _tactics_to_dict(t.tactics_default),
		"finances": _finances_to_dict(t.finances),
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
			"tv_revenue_eur_year": f.tv_revenue_eur_year}


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
