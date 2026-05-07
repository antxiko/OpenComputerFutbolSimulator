class_name PromotionRelegation extends RefCounted

# Aplica ascensos y descensos al final de temporada.
# v1: 3 directos en cada sentido (en La Liga real son 2 directos + 1 por play-off; simplificamos).

const N_SWAPS: int = 3


class Movement:
	var promoted_ids: Array[String] = []
	var promoted_names: Array[String] = []
	var relegated_ids: Array[String] = []
	var relegated_names: Array[String] = []


static func apply(primera_table: LeagueTable, segunda_table: LeagueTable, all_teams: Array) -> Movement:
	var movement := Movement.new()
	var primera_sorted: Array = primera_table.sorted_rows()
	var segunda_sorted: Array = segunda_table.sorted_rows()

	# Bottom N de Primera bajan
	var bottom_count: int = mini(N_SWAPS, primera_sorted.size())
	for i in range(primera_sorted.size() - bottom_count, primera_sorted.size()):
		var row: LeagueTable.TeamRow = primera_sorted[i]
		movement.relegated_ids.append(row.team_id)
		movement.relegated_names.append(row.team_name)

	# Top N de Segunda suben
	var top_count: int = mini(N_SWAPS, segunda_sorted.size())
	for i in top_count:
		var row: LeagueTable.TeamRow = segunda_sorted[i]
		movement.promoted_ids.append(row.team_id)
		movement.promoted_names.append(row.team_name)

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
