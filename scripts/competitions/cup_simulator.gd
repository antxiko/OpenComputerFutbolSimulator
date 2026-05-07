class_name CupSimulator extends RefCounted

# Simula la Copa del Rey completa para una temporada.
# Empate al 90' → gana el de mayor reputación (representa prórroga + penaltis).


static func run(teams: Array, season_year: int, seed_value: int) -> CupBracket:
	var bracket := CupBracket.generate_initial(teams, seed_value)
	var team_index: Dictionary = {}
	for t: Team in teams:
		team_index[t.id] = t

	var match_seed: int = seed_value * 10000

	while true:
		var round_obj: CupBracket.Round = bracket.current_round()
		if round_obj == null:
			break
		# Simular todos los partidos de esta ronda
		for fx: CupBracket.Fixture in round_obj.fixtures:
			var home: Team = team_index[fx.home_id]
			var away: Team = team_index[fx.away_id]
			# Restaurar condition antes del partido
			for p: Player in home.players:
				p.condition = 100.0
			for p: Player in away.players:
				p.condition = 100.0
			var home_lineup := AutoLineup.pick(home, home.tactics_default.formation)
			var away_lineup := AutoLineup.pick(away, away.tactics_default.formation)
			match_seed += 1
			var result: MatchResult = MatchEngine.simulate(home_lineup, away_lineup, match_seed)
			fx.result = result
			# Determinar ganador
			if result.score_home > result.score_away:
				fx.winner_id = home.id
			elif result.score_away > result.score_home:
				fx.winner_id = away.id
			else:
				# Empate: gana el de mayor reputación (pragmático para penaltis)
				fx.winner_id = home.id if home.reputation >= away.reputation else away.id
				fx.won_by_reputation = true

		# Avanzar a la siguiente ronda si no es final
		var advancing_ids: Array = round_obj.byes.duplicate()
		var advancing_names: Dictionary = {}
		for tid in round_obj.byes:
			advancing_names[tid] = team_index[tid].name
		for fx in round_obj.fixtures:
			advancing_ids.append(fx.winner_id)
			advancing_names[fx.winner_id] = team_index[fx.winner_id].name

		# Si la ronda actual es la final, terminar
		if round_obj.fixtures.size() == 1 and round_obj.byes.is_empty():
			# Acabamos de simular la final
			var final_fx: CupBracket.Fixture = round_obj.fixtures[0]
			bracket.champion_id = final_fx.winner_id
			bracket.champion_name = team_index[final_fx.winner_id].name
			var loser: Team = team_index[final_fx.away_id] if final_fx.winner_id == final_fx.home_id else team_index[final_fx.home_id]
			bracket.runner_up_name = loser.name
			break

		# Generar siguiente ronda
		var ok: bool = bracket.generate_next_round(advancing_ids, advancing_names, seed_value)
		if not ok:
			# Edge case: solo queda 1 equipo (no debería pasar con 42 inicial)
			if advancing_ids.size() == 1:
				bracket.champion_id = advancing_ids[0]
				bracket.champion_name = String(advancing_names.get(advancing_ids[0], ""))
			break

	return bracket


# Helper para resumir la copa por consola.
static func summarize(bracket: CupBracket) -> String:
	var lines: Array[String] = []
	for r: CupBracket.Round in bracket.rounds:
		lines.append("  %s (%d partidos)" % [r.name, r.fixtures.size()])
		for fx: CupBracket.Fixture in r.fixtures:
			var marker: String = " (rep)" if fx.won_by_reputation else ""
			var score: String = "%d-%d" % [fx.result.score_home, fx.result.score_away] if fx.result else "?-?"
			var winner: String = ""
			if fx.winner_id == fx.home_id:
				winner = "→ %s" % fx.home_name
			elif fx.winner_id == fx.away_id:
				winner = "→ %s" % fx.away_name
			lines.append("    %s %s %s%s  %s" % [
				fx.home_name.left(28), score, fx.away_name.left(28), marker, winner])
	if bracket.champion_name != "":
		lines.append("")
		lines.append("  🏆 CAMPEÓN: %s  (subcampeón: %s)" % [bracket.champion_name, bracket.runner_up_name])
	return "\n".join(lines)
