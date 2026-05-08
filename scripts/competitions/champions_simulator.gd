class_name ChampionsSimulator extends RefCounted

# Simula una edición completa de Champions League.
# Entrada: 4 equipos españoles (top 4 Liga año anterior) + 12 europeos = 16.
# Salida: ChampionsBracket con grupos + KO + campeón.
#
# Formato:
#   - 4 grupos de 4 equipos (sorteo determinista por seed).
#   - Fase de grupos: solo IDA → 3 jornadas, 6 partidos por grupo.
#   - Top 2 de cada grupo → octavos.
#   - Octavos / Cuartos / Semis / Final: partido único, empate al 90 → mayor reputación.

# Con 16 equipos (4 grupos de 4) el bracket KO es Cuartos -> Semis -> Final.
# Si subiéramos a 32 equipos (8 grupos), añadir "Octavos" como índice 0.
const KO_ROUND_NAMES := {
	1: "Cuartos", 2: "Semifinales", 3: "Final",
}


static func run(spanish_top4: Array, european_teams: Array, season_year: int, seed_value: int) -> ChampionsBracket:
	var bracket := ChampionsBracket.new()
	bracket.season_year = season_year

	if spanish_top4.size() < 4 or european_teams.size() < 12:
		push_warning("Champions: faltan equipos. Spanish=%d, European=%d" % [
			spanish_top4.size(), european_teams.size()])
		return bracket

	# Construye índice de equipos para lookup rápido por id
	var teams_idx: Dictionary = {}
	for t: Team in spanish_top4:
		teams_idx[t.id] = t
	for t: Team in european_teams:
		teams_idx[t.id] = t

	# Sorteo de grupos (determinista por seed). Los 4 top españoles son cabezas
	# de serie distintas (uno por grupo) — refleja la realidad del bombo.
	var groups: Array = _draw_groups(spanish_top4, european_teams, seed_value)
	bracket.groups = groups

	# Simular fase de grupos
	var match_seed: int = seed_value * 100000
	for group: ChampionsBracket.Group in groups:
		_simulate_group(group, teams_idx, match_seed)
		match_seed += 1000

	# Generar Cuartos: top 2 de cada grupo cruza con otro grupo.
	var ko: ChampionsBracket.KORound = _build_quarterfinals(groups, seed_value)
	bracket.ko_rounds.append(ko)

	# Simular KO
	while bracket.ko_rounds.size() > 0:
		var current: ChampionsBracket.KORound = bracket.ko_rounds[-1]
		_simulate_ko_round(current, teams_idx, match_seed)
		match_seed += 1000
		# Si era la final, terminamos
		if current.fixtures.size() == 1:
			var final_fx: ChampionsBracket.KOFixture = current.fixtures[0]
			bracket.champion_id = final_fx.winner_id
			bracket.champion_name = teams_idx[final_fx.winner_id].name
			var loser_id: String = final_fx.away_id if final_fx.winner_id == final_fx.home_id else final_fx.home_id
			bracket.runner_up_name = teams_idx[loser_id].name
			break
		# Generar siguiente ronda
		var winners: Array = []
		for fx: ChampionsBracket.KOFixture in current.fixtures:
			winners.append(fx.winner_id)
		var next_round: ChampionsBracket.KORound = _build_next_ko(winners, teams_idx,
				current.index + 1, seed_value)
		bracket.ko_rounds.append(next_round)

	return bracket


# ----------------------------------------------------------------------
# Sorteo de grupos
# ----------------------------------------------------------------------
static func _draw_groups(spanish: Array, european: Array, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Cabezas de serie (4 españoles). 12 europeos repartidos como pots.
	var spanish_shuffled: Array = spanish.duplicate()
	_shuffle(spanish_shuffled, rng)
	# Europeos se ordenan por reputación y se reparten en bombos de 4.
	var euro_sorted: Array = european.duplicate()
	euro_sorted.sort_custom(func(a: Team, b: Team) -> bool:
		return a.reputation > b.reputation)
	var pot2: Array = euro_sorted.slice(0, 4)   # top 4 europeos
	var pot3: Array = euro_sorted.slice(4, 8)
	var pot4: Array = euro_sorted.slice(8, 12)
	_shuffle(pot2, rng)
	_shuffle(pot3, rng)
	_shuffle(pot4, rng)

	var groups: Array = []
	for i in 4:
		var g := ChampionsBracket.Group.new()
		g.letter = ["A", "B", "C", "D"][i]
		g.team_ids = [
			spanish_shuffled[i].id,
			pot2[i].id,
			pot3[i].id,
			pot4[i].id,
		]
		# Init standings
		for j in 4:
			var team: Team = [spanish_shuffled[i], pot2[i], pot3[i], pot4[i]][j]
			var st := ChampionsBracket.GroupStanding.new()
			st.team_id = team.id
			st.team_name = team.name
			g.standings[team.id] = st
		groups.append(g)
	return groups


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ----------------------------------------------------------------------
# Fase de grupos
# ----------------------------------------------------------------------
static func _simulate_group(group: ChampionsBracket.Group, teams_idx: Dictionary, seed_base: int) -> void:
	# Calendario solo IDA. 4 equipos -> 3 jornadas, 6 partidos.
	# Pairings (Berger simplificado para 4 equipos):
	# J1: 0v1, 2v3
	# J2: 0v2, 3v1
	# J3: 0v3, 1v2
	var rotations: Array = [
		[[0, 1], [2, 3]],
		[[0, 2], [3, 1]],
		[[0, 3], [1, 2]],
	]
	var match_seed: int = seed_base
	for j_idx in 3:
		for pair: Array in rotations[j_idx]:
			var home_id: String = group.team_ids[pair[0]]
			var away_id: String = group.team_ids[pair[1]]
			var home: Team = teams_idx[home_id]
			var away: Team = teams_idx[away_id]
			var gm := ChampionsBracket.GroupMatch.new()
			gm.jornada = j_idx + 1
			gm.home_id = home_id
			gm.away_id = away_id
			gm.home_name = home.name
			gm.away_name = away.name
			# Restaurar condition/sanciones (Champions tiene su propio rítmo)
			for p: Player in home.players:
				p.condition = 100.0
			for p: Player in away.players:
				p.condition = 100.0
			var home_lineup := AutoLineup.pick(home, home.tactics_default.formation)
			var away_lineup := AutoLineup.pick(away, away.tactics_default.formation)
			match_seed += 1
			gm.result = MatchEngine.simulate(home_lineup, away_lineup, match_seed)
			group.matches.append(gm)
			# Actualizar standings
			if gm.result != null:
				_apply_match_to_standings(group, gm)


static func _apply_match_to_standings(group: ChampionsBracket.Group, gm: ChampionsBracket.GroupMatch) -> void:
	var home_st: ChampionsBracket.GroupStanding = group.standings[gm.home_id]
	var away_st: ChampionsBracket.GroupStanding = group.standings[gm.away_id]
	home_st.played += 1
	away_st.played += 1
	home_st.goals_for += gm.result.score_home
	home_st.goals_against += gm.result.score_away
	away_st.goals_for += gm.result.score_away
	away_st.goals_against += gm.result.score_home
	if gm.result.score_home > gm.result.score_away:
		home_st.won += 1
		away_st.lost += 1
	elif gm.result.score_away > gm.result.score_home:
		away_st.won += 1
		home_st.lost += 1
	else:
		home_st.drawn += 1
		away_st.drawn += 1


# ----------------------------------------------------------------------
# KO
# ----------------------------------------------------------------------
static func _build_quarterfinals(groups: Array, seed_value: int) -> ChampionsBracket.KORound:
	# Top 2 de cada grupo (8 equipos) -> 4 cuartos. Cruces: leader_A vs runnerup_B,
	# leader_B vs runnerup_A, leader_C vs runnerup_D, leader_D vs runnerup_C
	# (evita que 1º y 2º del mismo grupo se vuelvan a cruzar en Cuartos).
	var round_obj := ChampionsBracket.KORound.new()
	round_obj.index = 1
	round_obj.name = KO_ROUND_NAMES[1]
	var leaders: Array = []
	var runners: Array = []
	for g: ChampionsBracket.Group in groups:
		var st: Array = g.sorted_standings()
		if st.size() >= 2:
			leaders.append(st[0].team_id)
			runners.append(st[1].team_id)
	var pairs: Array = [[0, 1], [1, 0], [2, 3], [3, 2]]
	for pair: Array in pairs:
		var fx := ChampionsBracket.KOFixture.new()
		fx.home_id = leaders[pair[0]]
		fx.away_id = runners[pair[1]]
		round_obj.fixtures.append(fx)
	return round_obj


static func _build_next_ko(winner_ids: Array, teams_idx: Dictionary, round_index: int, seed_value: int) -> ChampionsBracket.KORound:
	var round_obj := ChampionsBracket.KORound.new()
	round_obj.index = round_index
	round_obj.name = KO_ROUND_NAMES.get(round_index, "Ronda %d" % round_index)
	# Pareados secuenciales (mantiene el bracket consistente)
	for i in range(0, winner_ids.size(), 2):
		if i + 1 >= winner_ids.size():
			break
		var fx := ChampionsBracket.KOFixture.new()
		fx.home_id = winner_ids[i]
		fx.away_id = winner_ids[i + 1]
		round_obj.fixtures.append(fx)
	return round_obj


static func _simulate_ko_round(round_obj: ChampionsBracket.KORound, teams_idx: Dictionary, seed_base: int) -> void:
	var match_seed: int = seed_base
	for fx: ChampionsBracket.KOFixture in round_obj.fixtures:
		var home: Team = teams_idx[fx.home_id]
		var away: Team = teams_idx[fx.away_id]
		fx.home_name = home.name
		fx.away_name = away.name
		# Restaurar condition
		for p: Player in home.players:
			p.condition = 100.0
		for p: Player in away.players:
			p.condition = 100.0
		var home_lineup := AutoLineup.pick(home, home.tactics_default.formation)
		var away_lineup := AutoLineup.pick(away, away.tactics_default.formation)
		match_seed += 1
		fx.result = MatchEngine.simulate(home_lineup, away_lineup, match_seed)
		# Determinar ganador
		if fx.result == null:
			fx.winner_id = home.id if home.reputation >= away.reputation else away.id
		elif fx.result.score_home > fx.result.score_away:
			fx.winner_id = home.id
		elif fx.result.score_away > fx.result.score_home:
			fx.winner_id = away.id
		else:
			fx.winner_id = home.id if home.reputation >= away.reputation else away.id
			fx.won_by_reputation = true


# ----------------------------------------------------------------------
# Resumen consola
# ----------------------------------------------------------------------
static func summarize(bracket: ChampionsBracket) -> String:
	var lines: Array = []
	lines.append("=== Champions League %d ===" % bracket.season_year)
	for g: ChampionsBracket.Group in bracket.groups:
		lines.append("Grupo %s:" % g.letter)
		for st: ChampionsBracket.GroupStanding in g.sorted_standings():
			lines.append("  %2d pts  %2d-%2d  %s" % [
				st.points(), st.goals_for, st.goals_against, st.team_name])
	for r: ChampionsBracket.KORound in bracket.ko_rounds:
		lines.append("%s:" % r.name)
		for fx: ChampionsBracket.KOFixture in r.fixtures:
			var score: String = "?-?"
			if fx.result != null:
				score = "%d-%d" % [fx.result.score_home, fx.result.score_away]
			var rep: String = " (rep)" if fx.won_by_reputation else ""
			lines.append("  %s %s %s -> %s%s" % [fx.home_name, score, fx.away_name,
					_winner_name(bracket, fx.winner_id), rep])
	if bracket.champion_name != "":
		lines.append("CAMPEÓN: %s (subcampeón: %s)" % [bracket.champion_name, bracket.runner_up_name])
	return "\n".join(lines)


static func _winner_name(bracket: ChampionsBracket, winner_id: String) -> String:
	for r: ChampionsBracket.KORound in bracket.ko_rounds:
		for fx: ChampionsBracket.KOFixture in r.fixtures:
			if fx.home_id == winner_id:
				return fx.home_name
			if fx.away_id == winner_id:
				return fx.away_name
	return winner_id
