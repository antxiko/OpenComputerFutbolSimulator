class_name ReputationUpdate extends RefCounted

# Actualiza la reputación de cada club en función de su clasificación de la temporada.
# Llamar al FINAL de cada temporada antes de promotion_relegation para que los datos
# reflejen el rendimiento competitivo real.
#
# Filosofía:
#   - Ganar Liga sube fuerte
#   - Top 6 sube poco
#   - Mitad tabla no cambia
#   - Bottom de Primera baja
#   - Descenso baja fuerte
#   - Ascenso desde Segunda sube
#
# Rango: [10, 99]


static func apply_after_season(primera_table: LeagueTable, segunda_table: LeagueTable, all_teams: Array) -> Dictionary:
	# Devuelve { team_id -> delta_reputation } para logging.
	var deltas: Dictionary = {}

	var p_sorted: Array = primera_table.sorted_rows()
	for i in p_sorted.size():
		var pos: int = i + 1
		var row: LeagueTable.TeamRow = p_sorted[i]
		var team: Team = _find(all_teams, row.team_id)
		if team == null:
			continue
		var d: int = _primera_delta(pos)
		var old: int = team.reputation
		team.reputation = clampi(team.reputation + d, 10, 99)
		deltas[team.id] = team.reputation - old

	var s_sorted: Array = segunda_table.sorted_rows()
	for i in s_sorted.size():
		var pos: int = i + 1
		var row: LeagueTable.TeamRow = s_sorted[i]
		var team: Team = _find(all_teams, row.team_id)
		if team == null:
			continue
		var d: int = _segunda_delta(pos, s_sorted.size())
		var old: int = team.reputation
		team.reputation = clampi(team.reputation + d, 10, 99)
		deltas[team.id] = team.reputation - old

	return deltas


static func _primera_delta(pos: int) -> int:
	if pos == 1: return 4   # Campeón
	if pos <= 4: return 2   # Champions League positions
	if pos <= 7: return 1   # Europa / Conference
	if pos <= 12: return 0  # Mitad tranquila
	if pos <= 15: return -1 # Cerca de descenso
	if pos <= 17: return -2 # Sufre
	return -4  # 18-20 → descenso


static func _segunda_delta(pos: int, total: int) -> int:
	if pos == 1: return 3   # Campeón Segunda → asciende
	if pos == 2: return 2   # Sube
	if pos == 3: return 1   # Sube (en v1 los 3 primeros suben directamente)
	if pos <= 10: return 0
	if pos >= total - 3: return -1  # Cerca de descenso a Primera RFEF (no implementado)
	return 0


static func _find(teams: Array, team_id: String) -> Team:
	for t: Team in teams:
		if t.id == team_id:
			return t
	return null
