extends SceneTree

# Debug: simula 1 temporada de Primera y muestra distribución de goles por partido.

func _init() -> void:
	print("=" .repeat(80))
	print("Debug: distribución de goles por partido en 1 temporada de Primera")
	print("=" .repeat(80))

	var loaded := DataLoader.load_all_teams(2026)
	if loaded.errors.size() > 0:
		print("Errores de carga, abortando")
		quit(1)
		return
	var primera: Array = loaded.teams.values().filter(func(t: Team) -> bool: return t.division == "primera")
	print("Primera: %d equipos" % primera.size())

	var ids: Array = primera.map(func(t: Team) -> String: return t.id)
	var calendar: Array = CalendarGenerator.generate(ids, 42)
	var team_index: Dictionary = {}
	for t in primera: team_index[t.id] = t

	var seed_counter: int = 42000
	var goal_dist: Dictionary = {}  # int (total goals) -> count
	var biggest: Array = []  # [{home, away, score_h, score_a}]
	var total_goals: int = 0
	var match_count: int = 0
	var jornada1_results: Array = []

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
			# Decrementar sanciones (1 partido por sanción cada vez que el equipo juega)
			CardSystem.decrement_for_team(home)
			CardSystem.decrement_for_team(away)
			var r: MatchResult = MatchEngine.simulate(hl, al, seed_counter)
			if r == null:
				continue
			# Procesar tarjetas para tracking
			CardSystem.process_match(r, primera)
			var t: int = r.score_home + r.score_away
			goal_dist[t] = int(goal_dist.get(t, 0)) + 1
			total_goals += t
			match_count += 1
			# Track top scoreful matches
			biggest.append({
				"home": home.short_name, "away": away.short_name,
				"sh": r.score_home, "sa": r.score_away,
				"jornada": j + 1,
			})
			if j == 0:
				jornada1_results.append({
					"home": home.short_name, "away": away.short_name,
					"sh": r.score_home, "sa": r.score_away,
				})
		# Curar
		InjurySystem.heal_after_days(primera, 7)

	print("\n  Partidos simulados: %d" % match_count)
	print("  Goles totales: %d" % total_goals)
	print("  Promedio goles/partido: %.2f" % (float(total_goals) / float(maxi(match_count, 1))))
	print("\n  Distribución de goles por partido (suma de los dos equipos):")
	var keys: Array = goal_dist.keys()
	keys.sort()
	for k in keys:
		var bar: String = "█".repeat(int(goal_dist[k]) / 2)
		print("    %2d goles: %3d partidos  %s" % [k, int(goal_dist[k]), bar])

	# Top 5 partidos con más goles
	biggest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (int(a["sh"]) + int(a["sa"])) > (int(b["sh"]) + int(b["sa"])))
	print("\n  Top 5 partidos con más goles:")
	for i in mini(5, biggest.size()):
		var b: Dictionary = biggest[i]
		print("    Jornada %d: %s %d-%d %s" % [int(b["jornada"]), String(b["home"]), int(b["sh"]), int(b["sa"]), String(b["away"])])

	print("\n  Resultados de la PRIMERA jornada (los 10 partidos):")
	for b in jornada1_results:
		print("    %s %d-%d %s" % [String(b["home"]), int(b["sh"]), int(b["sa"]), String(b["away"])])

	# Distribución de tarjetas por jugador
	print("\n  Top 15 jugadores con más amarillas tras la temporada:")
	var card_holders: Array = []
	for t: Team in primera:
		for p: Player in t.players:
			if p.yellow_cards_season > 0 or p.red_cards_season > 0:
				card_holders.append({
					"name": p.name,
					"team": t.short_name,
					"yellows": p.yellow_cards_season,
					"reds": p.red_cards_season,
					"agg": p.aggression,
				})
	card_holders.sort_custom(func(a, b): return int(a["yellows"]) > int(b["yellows"]))
	for i in mini(15, card_holders.size()):
		var c: Dictionary = card_holders[i]
		print("    %2dTA + %dTR  agg=%2d  %-25s  %s" % [
			int(c["yellows"]), int(c["reds"]), int(c["agg"]),
			String(c["name"]).left(25), String(c["team"])])

	quit(0)
