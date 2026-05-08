class_name DataLoader extends RefCounted

# Carga los JSON de data/teams/ y devuelve Teams con sus jugadores.
# Genera los atributos de los jugadores vía PlayerFactory.
#
# Las rutas usan res:// (raíz del proyecto Godot). En Godot, FileAccess no acepta
# rutas absolutas del SO; siempre se usa res:// para recursos del proyecto y
# user:// para datos del usuario (saves).

const TEAMS_DIRS: Array[String] = [
	"res://data/teams/primera",
	"res://data/teams/segunda",
]


# Resultado de la carga: equipos por id, además de errores y avisos.
class LoadResult:
	var teams: Dictionary = {}  # team_id -> Team
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var player_id_index: Dictionary = {}  # global player_id -> team_id (para detectar colisiones)


# Carga TODOS los equipos de data/teams/{primera,segunda}/.
# season_year se usa para que PlayerFactory calcule la edad correcta.
# seed_base se combina con el id del jugador para generar atributos deterministas.
static func load_all_teams(season_year: int, seed_base: int = 12345) -> LoadResult:
	var result := LoadResult.new()
	for dir_path in TEAMS_DIRS:
		_load_dir(dir_path, result, season_year, seed_base)
	return result


# Carga un solo archivo JSON de equipo (para tests rápidos).
static func load_team_file(path: String, season_year: int, seed_base: int = 12345) -> Team:
	var team := _read_team_json(path)
	if team == null:
		return null
	_generate_team_attributes(team, season_year, seed_base)
	return team


static func _load_dir(dir_path: String, result: LoadResult, season_year: int, seed_base: int) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		result.warnings.append("No se pudo abrir directorio: %s" % dir_path)
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var full: String = "%s/%s" % [dir_path, fname]
			var team := _read_team_json(full)
			if team == null:
				result.errors.append("Falló cargar %s" % full)
			else:
				if result.teams.has(team.id):
					result.errors.append("ID de equipo duplicado: %s (%s)" % [team.id, full])
				else:
					_generate_team_attributes(team, season_year, seed_base)
					result.teams[team.id] = team
					_check_player_ids(team, result)
		fname = dir.get_next()
	dir.list_dir_end()


static func _read_team_json(path: String) -> Team:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("No se pudo abrir %s: %s" % [path, FileAccess.get_open_error()])
		return null
	var content: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if parsed == null:
		push_error("JSON inválido en %s" % path)
		return null
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Se esperaba objeto JSON raíz en %s" % path)
		return null
	return Team.from_dict(parsed)


static func _generate_team_attributes(team: Team, season_year: int, seed_base: int) -> void:
	for p in team.players:
		# Seed determinista por jugador: combinamos seed_base con un hash estable del id.
		var player_seed: int = seed_base ^ hash(p.id)
		PlayerFactory.generate_attributes(p, season_year, player_seed)
		# Marcar basque_eligible:
		# - Todos los jugadores actuales del Athletic se asumen basque (es su filosofía).
		# - Para los demás equipos, heurística por apellido vasco.
		# Solo aplicar si no viene ya marcado en el JSON.
		if not p.basque_eligible:
			if team.signing_policy == "basque_only":
				p.basque_eligible = true
			elif p.nationality == "ES" and BasqueHeuristic.is_basque_name(p.name):
				p.basque_eligible = true


static func _check_player_ids(team: Team, result: LoadResult) -> void:
	for p in team.players:
		if result.player_id_index.has(p.id):
			result.errors.append(
				"ID de jugador duplicado: %s (en %s y %s)" % [
					p.id, result.player_id_index[p.id], team.id
				]
			)
		else:
			result.player_id_index[p.id] = team.id
