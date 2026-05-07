class_name SeasonSimulator extends RefCounted

# Orquesta una temporada completa: genera calendario, simula todos los partidos,
# acumula tabla de clasificación y goleadores.
#
# Recuperación de fatiga: por simplicidad v1, entre jornadas todos los jugadores
# recuperan condition a 100. La fatiga sólo opera DENTRO de cada partido.

class SeasonResult:
	var division: String = ""
	var year: int = 0
	var teams: Array = []          # Array[Team]
	var table: LeagueTable
	var calendar: Array = []        # Array[Jornada]
	var match_results: Array = []   # Array[MatchResult]
	var top_scorers: Dictionary = {}  # player_id -> { name, team_name, goals }


static func simulate_season(teams: Array, division_label: String, year: int, seed_base: int = 0) -> SeasonResult:
	var result := SeasonResult.new()
	result.division = division_label
	result.year = year
	result.teams = teams
	result.table = LeagueTable.new()
	result.table.init_with_teams(teams)

	var team_ids: Array = teams.map(func(t: Team) -> String: return t.id)
	result.calendar = CalendarGenerator.generate(team_ids, seed_base)

	var validation: Dictionary = CalendarGenerator.validate(result.calendar, team_ids)
	if not validation["ok"]:
		push_error("Calendario inválido para %s:" % division_label)
		for e in validation["errors"]:
			push_error("  - %s" % e)
		return result
	print("[%s] Calendario: %d jornadas × %d partidos = %d totales" % [
		division_label, validation["jornadas"], validation["matches_per_jornada"], validation["total_matches"]])

	# Crear índice por id para lookup rápido
	var team_index: Dictionary = {}
	for t in teams:
		team_index[t.id] = t

	var match_seed_counter: int = seed_base * 1000
	var jornada_idx: int = 0
	for jornada in result.calendar:
		jornada_idx += 1
		# Restaurar condición de todos los jugadores antes de cada jornada
		for t: Team in teams:
			for p: Player in t.players:
				p.condition = 100.0
		# Simular partidos de la jornada
		for fixture: Dictionary in jornada:
			var home: Team = team_index[fixture["home_id"]]
			var away: Team = team_index[fixture["away_id"]]
			var home_lineup: Lineup = AutoLineup.pick(home, home.tactics_default.formation)
			var away_lineup: Lineup = AutoLineup.pick(away, away.tactics_default.formation)
			match_seed_counter += 1
			var match_result: MatchResult = MatchEngine.simulate(home_lineup, away_lineup, match_seed_counter)
			if match_result == null:
				push_error("Falló partido %s vs %s" % [home.id, away.id])
				continue
			result.table.record_match(match_result)
			result.match_results.append(match_result)
			_record_scorers(match_result, home, away, result.top_scorers)

	return result


static func _record_scorers(mr: MatchResult, home: Team, away: Team, top_scorers: Dictionary) -> void:
	for pid in mr.scorers.keys():
		var goals: int = int(mr.scorers[pid])
		if goals <= 0:
			continue
		var team: Team = home if home.find_player(pid) != null else away
		var player: Player = team.find_player(pid)
		if player == null:
			continue
		if not top_scorers.has(pid):
			top_scorers[pid] = {
				"name": player.name,
				"team_name": team.short_name,
				"goals": 0,
			}
		top_scorers[pid]["goals"] += goals


static func print_top_scorers(top_scorers: Dictionary, limit: int = 15) -> void:
	var arr: Array = top_scorers.values()
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["goals"]) > int(b["goals"]))
	print("\n  Pichichi:")
	print("    Pos  Jugador                           Equipo  Goles")
	print("    ───  ────────────────────────────────  ──────  ─────")
	for i in mini(limit, arr.size()):
		print("    %3d  %-32s  %-6s  %5d" % [
			i + 1, String(arr[i]["name"]).left(32), String(arr[i]["team_name"]), int(arr[i]["goals"])])
