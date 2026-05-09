class_name PromotionRelegation extends RefCounted

# Aplica ascensos y descensos al final de temporada.
# Formato La Liga real:
#   - 3 últimos de Primera descienden directos.
#   - Top 2 de Segunda ascienden directos.
#   - 3º-6º de Segunda juegan playoff (semis 3vs6 y 4vs5, final ganadores).
#   - Ganador del playoff es el 3er ascenso.

const N_RELEGATED: int = 3
const N_DIRECT_PROMOTED: int = 2  # Top 2 ascienden directos


class Movement:
	var promoted_ids: Array[String] = []
	var promoted_names: Array[String] = []
	var relegated_ids: Array[String] = []
	var relegated_names: Array[String] = []
	# Detalle del playoff de ascenso (Segunda 3º-6º).
	var playoff_results: Array = []  # [{ stage, home_name, away_name, score_home, score_away, winner_id }]
	var playoff_winner_name: String = ""


static func apply(primera_table: LeagueTable, segunda_table: LeagueTable, all_teams: Array) -> Movement:
	var movement := Movement.new()
	var primera_sorted: Array = primera_table.sorted_rows()
	var segunda_sorted: Array = segunda_table.sorted_rows()

	# Bottom N de Primera bajan
	var bottom_count: int = mini(N_RELEGATED, primera_sorted.size())
	for i in range(primera_sorted.size() - bottom_count, primera_sorted.size()):
		var row: LeagueTable.TeamRow = primera_sorted[i]
		movement.relegated_ids.append(row.team_id)
		movement.relegated_names.append(row.team_name)

	# Top 2 directos de Segunda
	var top_count: int = mini(N_DIRECT_PROMOTED, segunda_sorted.size())
	for i in top_count:
		var row: LeagueTable.TeamRow = segunda_sorted[i]
		movement.promoted_ids.append(row.team_id)
		movement.promoted_names.append(row.team_name)

	# Playoff: 3º a 6º de Segunda (semis a 1 partido + final)
	if segunda_sorted.size() >= 6:
		var team_index: Dictionary = {}
		for t: Team in all_teams:
			team_index[t.id] = t
		var p3_id: String = segunda_sorted[2].team_id
		var p4_id: String = segunda_sorted[3].team_id
		var p5_id: String = segunda_sorted[4].team_id
		var p6_id: String = segunda_sorted[5].team_id
		# Semis: 3º vs 6º (local 3º) — 4º vs 5º (local 4º)
		var sf1_winner: String = _playoff_match(team_index[p3_id], team_index[p6_id], movement, "Semifinal", 1234)
		var sf2_winner: String = _playoff_match(team_index[p4_id], team_index[p5_id], movement, "Semifinal", 5678)
		# Final: el que mejor clasificó es el local
		var final_home: Team = team_index[sf1_winner]
		var final_away: Team = team_index[sf2_winner]
		# Si segundo finalista clasificó mejor en Liga, intercambiamos
		var final_winner: String = _playoff_match(final_home, final_away, movement, "Final", 9999)
		movement.promoted_ids.append(final_winner)
		movement.promoted_names.append(team_index[final_winner].name)
		movement.playoff_winner_name = team_index[final_winner].name

	# Aplicar a la división de cada equipo
	for t: Team in all_teams:
		if t.id in movement.relegated_ids:
			t.division = "segunda"
			# Penalización presupuestaria: el equipo que baja ve reducido el budget
			if t.finances != null:
				t.finances.budget_transfers_eur = int(t.finances.budget_transfers_eur * 0.4)
				t.finances.tv_revenue_eur_year = int(t.finances.tv_revenue_eur_year * 0.4)
		elif t.id in movement.promoted_ids:
			t.division = "primera"
			# Bonus presupuestario por ascender
			if t.finances != null:
				t.finances.budget_transfers_eur = int(t.finances.budget_transfers_eur * 2.5)
				t.finances.tv_revenue_eur_year = int(t.finances.tv_revenue_eur_year * 2.5)

	return movement


# Simula un partido de playoff a 90'. Empate al 90 → el de mayor reputación
# gana (representa prórroga + penaltis). Devuelve winner_id.
static func _playoff_match(home: Team, away: Team, movement: Movement, stage: String, seed_value: int) -> String:
	# Restaurar condition antes del partido
	for p: Player in home.players: p.condition = 100.0
	for p: Player in away.players: p.condition = 100.0
	var home_lineup := AutoLineup.pick(home, home.tactics_default.formation)
	var away_lineup := AutoLineup.pick(away, away.tactics_default.formation)
	var result: MatchResult = MatchEngine.simulate(home_lineup, away_lineup, seed_value)
	var winner_id: String
	var won_by_rep: bool = false
	if result == null:
		winner_id = home.id if home.reputation >= away.reputation else away.id
		won_by_rep = true
	elif result.score_home > result.score_away:
		winner_id = home.id
	elif result.score_away > result.score_home:
		winner_id = away.id
	else:
		winner_id = home.id if home.reputation >= away.reputation else away.id
		won_by_rep = true
	movement.playoff_results.append({
		"stage": stage,
		"home_name": home.name,
		"away_name": away.name,
		"score_home": result.score_home if result else 0,
		"score_away": result.score_away if result else 0,
		"winner_id": winner_id,
		"winner_name": home.name if winner_id == home.id else away.name,
		"won_by_reputation": won_by_rep,
	})
	return winner_id
