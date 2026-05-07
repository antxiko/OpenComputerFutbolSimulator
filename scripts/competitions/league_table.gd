class_name LeagueTable extends RefCounted

# Tabla de clasificación. Aplica los tiebreakers de La Liga:
#   1. Puntos
#   2. Diferencia de goles general
#   3. Goles a favor general
#   (en La Liga real también: enfrentamientos directos, pero eso requiere head-to-head;
#    para v1 nos quedamos con los tiebreakers globales)

class TeamRow:
	var team_id: String = ""
	var team_name: String = ""
	var played: int = 0
	var won: int = 0
	var drawn: int = 0
	var lost: int = 0
	var goals_for: int = 0
	var goals_against: int = 0

	func points() -> int:
		return won * 3 + drawn

	func goal_diff() -> int:
		return goals_for - goals_against


var rows: Dictionary = {}  # team_id -> TeamRow


func init_with_teams(teams: Array) -> void:
	for t: Team in teams:
		var row := TeamRow.new()
		row.team_id = t.id
		row.team_name = t.name
		rows[t.id] = row


func record_match(result: MatchResult) -> void:
	var home: TeamRow = rows[result.home_team_id]
	var away: TeamRow = rows[result.away_team_id]
	home.played += 1
	away.played += 1
	home.goals_for += result.score_home
	home.goals_against += result.score_away
	away.goals_for += result.score_away
	away.goals_against += result.score_home
	if result.score_home > result.score_away:
		home.won += 1
		away.lost += 1
	elif result.score_home < result.score_away:
		away.won += 1
		home.lost += 1
	else:
		home.drawn += 1
		away.drawn += 1


# Devuelve un Array de TeamRow ordenado descendente.
func sorted_rows() -> Array:
	var arr: Array = rows.values()
	arr.sort_custom(_compare)
	return arr


static func _compare(a: TeamRow, b: TeamRow) -> bool:
	if a.points() != b.points():
		return a.points() > b.points()
	if a.goal_diff() != b.goal_diff():
		return a.goal_diff() > b.goal_diff()
	if a.goals_for != b.goals_for:
		return a.goals_for > b.goals_for
	return a.team_name < b.team_name  # alfabético como último recurso


func print_table(division_label: String = "") -> void:
	var sorted: Array = sorted_rows()
	if division_label != "":
		print("\n" + "═".repeat(80))
		print("Clasificación — %s" % division_label)
		print("═".repeat(80))
	print("  Pos  Equipo                              PJ   G   E   P   GF   GC   DG   Pts")
	print("  ───  ──────────────────────────────────  ──  ──  ──  ──  ───  ───  ───  ───")
	var pos: int = 1
	for row: TeamRow in sorted:
		print("  %3d  %-34s  %2d  %2d  %2d  %2d  %3d  %3d  %+3d  %3d" % [
			pos, row.team_name.left(34),
			row.played, row.won, row.drawn, row.lost,
			row.goals_for, row.goals_against, row.goal_diff(), row.points()
		])
		pos += 1
