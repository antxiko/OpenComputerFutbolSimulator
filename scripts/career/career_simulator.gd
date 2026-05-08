class_name CareerSimulator extends RefCounted

# Bucle multi-temporada: simula N años consecutivos.
# Por cada año:
#   1. Divide equipos por division actual.
#   2. Simula Primera y Segunda.
#   3. Registra highlights (campeón, pichichi, mayor goleada, etc.).
#   4. Aplica ascensos/descensos.
#   5. Aplica aging + retiros.
#   6. Rellena plantillas con cantera si están bajo el mínimo.
#   7. Ejecuta mercado de fichajes verano.


class SeasonRecord:
	var year: int = 0
	var primera_champion_id: String = ""
	var primera_champion_name: String = ""
	var primera_runner_up_name: String = ""
	var primera_top_scorer_name: String = ""
	var primera_top_scorer_team: String = ""
	var primera_top_scorer_goals: int = 0
	var segunda_champion_name: String = ""
	var copa_champion_name: String = ""
	var copa_runner_up_name: String = ""
	var champions_winner_name: String = ""
	var champions_runner_up_name: String = ""
	var champions_spanish_qualifiers: Array = []  # nombres de los 4 españoles que jugaron
	var promoted_names: Array = []
	var relegated_names: Array = []
	var retirements_count: int = 0
	var notable_retirements: Array = []  # Array de Dictionary { name, age, team }
	var canteranos_added: int = 0
	var transfers_count: int = 0
	var top_transfer: Dictionary = {}  # { player, from, to, fee }
	var primera_simulation_secs: float = 0.0
	var segunda_simulation_secs: float = 0.0
	var copa_simulation_secs: float = 0.0
	var champions_simulation_secs: float = 0.0


class History:
	var start_year: int = 0
	var seasons: Array = []  # Array[SeasonRecord]
	var primera_titles: Dictionary = {}  # team_id -> count
	var segunda_titles: Dictionary = {}
	var copa_titles: Dictionary = {}     # team_name -> count (Copa del Rey)
	var champions_titles: Dictionary = {}  # team_name -> count
	var career_goals: Dictionary = {}  # player_id -> { name, team_short, goals }
	# Bracket completo de la última Champions simulada (para mostrar en UI).
	var last_champions_bracket: ChampionsBracket = null


static func run(all_teams: Array, start_year: int, n_seasons: int, seed_base: int) -> History:
	var history := History.new()
	history.start_year = start_year

	for i in n_seasons:
		var year: int = start_year + i
		var record := SeasonRecord.new()
		record.year = year
		# Reset de amarillas al inicio de la temporada
		CardSystem.reset_yellow_cards(all_teams)

		# 1) Split por división actual
		var primera: Array = []
		var segunda: Array = []
		for t: Team in all_teams:
			if t.division == "primera":
				primera.append(t)
			else:
				segunda.append(t)
		if primera.size() != 20 or segunda.size() != 22:
			push_warning("Año %d: Primera %d / Segunda %d (esperados 20/22)" % [year, primera.size(), segunda.size()])

		# 2) Simular Primera
		var t0: int = Time.get_ticks_msec()
		var p_result := SeasonSimulator.simulate_season(primera, "Primera", year, seed_base + i * 10)
		var t1: int = Time.get_ticks_msec()
		record.primera_simulation_secs = (t1 - t0) / 1000.0

		# 3) Simular Segunda
		var s_result := SeasonSimulator.simulate_season(segunda, "Segunda", year, seed_base + i * 10 + 1)
		var t2: int = Time.get_ticks_msec()
		record.segunda_simulation_secs = (t2 - t1) / 1000.0

		# 4) Registrar campeones y pichichi
		var p_sorted: Array = p_result.table.sorted_rows()
		var s_sorted: Array = s_result.table.sorted_rows()
		if p_sorted.size() > 0:
			record.primera_champion_id = p_sorted[0].team_id
			record.primera_champion_name = p_sorted[0].team_name
			history.primera_titles[p_sorted[0].team_id] = int(history.primera_titles.get(p_sorted[0].team_id, 0)) + 1
		if p_sorted.size() > 1:
			record.primera_runner_up_name = p_sorted[1].team_name
		if s_sorted.size() > 0:
			record.segunda_champion_name = s_sorted[0].team_name
			history.segunda_titles[s_sorted[0].team_id] = int(history.segunda_titles.get(s_sorted[0].team_id, 0)) + 1

		# Pichichi
		var top_arr: Array = p_result.top_scorers.values()
		top_arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["goals"]) > int(b["goals"]))
		if top_arr.size() > 0:
			var top_scorer: Dictionary = top_arr[0]
			record.primera_top_scorer_name = String(top_scorer["name"])
			record.primera_top_scorer_team = String(top_scorer["team_name"])
			record.primera_top_scorer_goals = int(top_scorer["goals"])
		# Acumular goles de carrera
		for pid in p_result.top_scorers.keys():
			var info: Dictionary = p_result.top_scorers[pid]
			if not history.career_goals.has(pid):
				history.career_goals[pid] = {
					"name": String(info["name"]),
					"team_short": String(info["team_name"]),
					"goals": 0,
				}
			history.career_goals[pid]["goals"] += int(info["goals"])
			# Actualizar el equipo "actual" al último visto
			history.career_goals[pid]["team_short"] = String(info["team_name"])

		# 4) Copa del Rey (después de Liga, antes de asc/desc)
		var t_copa_start: int = Time.get_ticks_msec()
		var cup_bracket := CupSimulator.run(all_teams, year, seed_base + i * 10 + 5)
		var t_copa_end: int = Time.get_ticks_msec()
		record.copa_simulation_secs = (t_copa_end - t_copa_start) / 1000.0
		record.copa_champion_name = cup_bracket.champion_name
		record.copa_runner_up_name = cup_bracket.runner_up_name
		if cup_bracket.champion_name != "":
			history.copa_titles[cup_bracket.champion_name] = int(history.copa_titles.get(cup_bracket.champion_name, 0)) + 1

		# 4.2) Champions League (con top 4 Liga de ESTA temporada como clasificados
		# para la temporada europea siguiente; en simulación de carrera larga,
		# representamos la Champions del próximo año aquí mismo).
		var spanish_top4: Array = []
		for k in range(0, min(4, p_sorted.size())):
			var top_team_id: String = p_sorted[k].team_id
			for tt: Team in all_teams:
				if tt.id == top_team_id:
					spanish_top4.append(tt)
					break
		if spanish_top4.size() == 4:
			var t_chl_start: int = Time.get_ticks_msec()
			var euros: Array = EuropeanTeams.generate_all(year + 1, seed_base + i * 13)
			var ch_bracket := ChampionsSimulator.run(spanish_top4, euros, year + 1, seed_base + i * 10 + 7)
			var t_chl_end: int = Time.get_ticks_msec()
			record.champions_simulation_secs = (t_chl_end - t_chl_start) / 1000.0
			record.champions_winner_name = ch_bracket.champion_name
			record.champions_runner_up_name = ch_bracket.runner_up_name
			record.champions_spanish_qualifiers = spanish_top4.map(func(t: Team) -> String: return t.name)
			if ch_bracket.champion_name != "":
				history.champions_titles[ch_bracket.champion_name] = int(history.champions_titles.get(ch_bracket.champion_name, 0)) + 1
			history.last_champions_bracket = ch_bracket

		# 4.5) Actualizar reputaciones según resultados
		ReputationUpdate.apply_after_season(p_result.table, s_result.table, all_teams)

		# 5) Ascensos/descensos
		var movement := PromotionRelegation.apply(p_result.table, s_result.table, all_teams)
		record.promoted_names = movement.promoted_names.duplicate()
		record.relegated_names = movement.relegated_names.duplicate()

		# 6) Aging + retiros
		var retirements: Dictionary = Aging.age_all(all_teams, year + 1, seed_base + i * 100)
		var notable: Array = []
		var total_retired: int = 0
		for team_id in retirements.keys():
			var ret_list: Array = retirements[team_id]
			total_retired += ret_list.size()
			for p: Player in ret_list:
				var ovr: int = PlayerFactory.compute_overall(p, p.primary_position())
				if ovr >= 75:
					notable.append({
						"name": p.name,
						"age": p.age_at(year + 1, 7, 1),
						"team": _short_for_team_id(all_teams, team_id),
						"overall": ovr,
					})
		record.retirements_count = total_retired
		notable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["overall"]) > int(b["overall"]))
		record.notable_retirements = notable

		# 7) Rellenar canteranos
		var total_canteranos: int = 0
		for t: Team in all_teams:
			var added: Array[Player] = Cantera.fill_squad_if_needed(t, year + 1, seed_base + i * 50)
			total_canteranos += added.size()
		record.canteranos_added = total_canteranos

		# 8) Mercado verano
		var market_result := TransferMarket.run(all_teams, year + 1, seed_base + i * 10 + 2)
		record.transfers_count = market_result.transfers.size()
		if market_result.transfers.size() > 0:
			var sorted_t: Array = market_result.transfers.duplicate()
			sorted_t.sort_custom(func(a: TransferMarket.Transfer, b: TransferMarket.Transfer) -> bool:
				return a.fee_eur > b.fee_eur)
			var top: TransferMarket.Transfer = sorted_t[0]
			record.top_transfer = {
				"player": top.player_name,
				"from": top.from_team_name,
				"to": top.to_team_name,
				"fee": top.fee_eur,
			}

		history.seasons.append(record)
		_print_year_summary(record)

	return history


static func _short_for_team_id(teams: Array, team_id: String) -> String:
	for t: Team in teams:
		if t.id == team_id:
			return t.short_name
	return team_id


static func _print_year_summary(r: SeasonRecord) -> void:
	var sim_total: float = r.primera_simulation_secs + r.segunda_simulation_secs + r.copa_simulation_secs + r.champions_simulation_secs
	print("  %d-%d  Liga: %-22s  Copa: %-22s  Champ: %-22s  Pich: %-18s (%2dg)  [%.1fs]" % [
		r.year, r.year + 1,
		r.primera_champion_name.left(22),
		r.copa_champion_name.left(22) if r.copa_champion_name else "(no jugada)",
		r.champions_winner_name.left(22) if r.champions_winner_name else "(no jugada)",
		r.primera_top_scorer_name.left(18),
		r.primera_top_scorer_goals,
		sim_total,
	])


static func _short_arr(arr: Array) -> String:
	var parts: Array = []
	for s in arr:
		parts.append(String(s).substr(0, 3))
	return ",".join(parts)


static func print_history_summary(history: History, all_teams: Array) -> void:
	print("\n" + "═" .repeat(100))
	print("Resumen histórico de la carrera (%d temporadas)" % history.seasons.size())
	print("═" .repeat(100))

	# Títulos por equipo
	print("\n  Títulos de Liga (Primera):")
	var arr: Array = history.primera_titles.keys()
	arr.sort_custom(func(a: String, b: String) -> bool:
		return int(history.primera_titles[a]) > int(history.primera_titles[b]))
	for tid in arr:
		var team_name: String = ""
		for t: Team in all_teams:
			if t.id == tid:
				team_name = t.name
				break
		print("    %3d  %s" % [int(history.primera_titles[tid]), team_name])

	# Títulos de Copa del Rey
	if history.copa_titles.size() > 0:
		print("\n  Títulos de Copa del Rey:")
		var copa_arr: Array = history.copa_titles.keys()
		copa_arr.sort_custom(func(a: String, b: String) -> bool:
			return int(history.copa_titles[a]) > int(history.copa_titles[b]))
		for name in copa_arr:
			print("    %3d  %s" % [int(history.copa_titles[name]), name])

	# Top goleadores de carrera
	print("\n  Máximos goleadores de la carrera:")
	var goal_arr: Array = history.career_goals.values()
	goal_arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["goals"]) > int(b["goals"]))
	print("    Pos  Jugador                           Último equipo  Goles")
	print("    ───  ────────────────────────────────  ─────────────  ─────")
	for i in mini(15, goal_arr.size()):
		print("    %3d  %-32s  %-13s  %5d" % [
			i + 1,
			String(goal_arr[i]["name"]).left(32),
			String(goal_arr[i]["team_short"]),
			int(goal_arr[i]["goals"]),
		])
