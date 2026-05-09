extends SceneTree

# Debug: simula 1 temporada de Primera y muestra estadísticas de penalties.

func _init() -> void:
	var loaded := DataLoader.load_all_teams(2026)
	if loaded.errors.size() > 0:
		quit(1)
		return
	var primera: Array = loaded.teams.values().filter(func(t: Team) -> bool: return t.division == "primera")
	var ids: Array = primera.map(func(t: Team) -> String: return t.id)
	var calendar: Array = CalendarGenerator.generate(ids, 42)
	var team_index: Dictionary = {}
	for t in primera: team_index[t.id] = t

	var seed_counter: int = 42000
	var match_count: int = 0
	var total_penalties: int = 0
	var penalties_scored: int = 0
	var total_goals: int = 0

	for j in calendar.size():
		var jornada: Array = calendar[j]
		for fixture: Dictionary in jornada:
			var home: Team = team_index[fixture["home_id"]]
			var away: Team = team_index[fixture["away_id"]]
			for p in home.players: p.condition = 100.0
			for p in away.players: p.condition = 100.0
			var hl := AutoLineup.pick(home, home.tactics_default.formation)
			var al := AutoLineup.pick(away, away.tactics_default.formation)
			seed_counter += 1
			CardSystem.decrement_for_team(home)
			CardSystem.decrement_for_team(away)
			var r: MatchResult = MatchEngine.simulate(hl, al, seed_counter)
			if r == null:
				continue
			CardSystem.process_match(r, primera)
			match_count += 1
			total_goals += r.score_home + r.score_away
			# Contar penalties
			for ev: MatchEvent in r.events:
				if ev.type == MatchEvent.T_PENALTY:
					total_penalties += 1
				elif ev.type == MatchEvent.T_GOAL and ev.description.contains("PENALTY"):
					penalties_scored += 1
		InjurySystem.heal_after_days(primera, 7)

	print("Partidos simulados: %d" % match_count)
	print("Goles totales: %d (%.2f por partido — real ~2.5)" % [total_goals, float(total_goals)/float(match_count)])
	print("Penalties señalados: %d (%.2f por partido — real ~0.30)" % [total_penalties, float(total_penalties)/float(match_count)])
	print("Penalties marcados: %d (%.1f%% conversión — real ~78%%)" % [
		penalties_scored,
		100.0 * float(penalties_scored) / float(maxi(total_penalties, 1)),
	])
	quit()
