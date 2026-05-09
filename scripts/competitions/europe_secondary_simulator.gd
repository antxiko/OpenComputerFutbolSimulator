class_name EuropeSecondarySimulator extends RefCounted

# Europa League / Conference League simplificadas: 16 equipos en KO directo.
# (8 spanish/europeos + 8 europeos del pool secundario)
#
# Formato:
#   - Octavos: 8 partidos
#   - Cuartos: 4 partidos
#   - Semis:   2 partidos
#   - Final:   1 partido
# Empate al 90' → mayor reputación (igual que Champions/Copa).


const KO_ROUND_NAMES := {
	1: "Octavos", 2: "Cuartos", 3: "Semifinales", 4: "Final",
}


# Devuelve un ChampionsBracket (reusamos la estructura de datos para no
# duplicar). Solo se llenan los ko_rounds; los groups se quedan vacíos.
static func run(spanish_qualifiers: Array, european_pool: Array, competition_name: String, season_year: int, seed_value: int) -> ChampionsBracket:
	var bracket := ChampionsBracket.new()
	bracket.season_year = season_year

	# Combinamos spanish + european_pool. Esperamos 8 spanish + 8 europeos = 16.
	# Si vienen menos spanish, se completa con europeos.
	var teams: Array = spanish_qualifiers.duplicate()
	for t in european_pool:
		teams.append(t)
	if teams.size() < 16:
		# No hay suficiente — abortar grácil
		return bracket
	teams = teams.slice(0, 16)

	var teams_idx: Dictionary = {}
	for t: Team in teams:
		teams_idx[t.id] = t

	# Sorteo determinista: orden por seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var shuffled: Array = teams.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp: Variant = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp

	# Octavos: 8 emparejamientos secuenciales
	var ko1 := ChampionsBracket.KORound.new()
	ko1.index = 1
	ko1.name = KO_ROUND_NAMES[1]
	for i in range(0, 16, 2):
		var fx := ChampionsBracket.KOFixture.new()
		fx.home_id = shuffled[i].id
		fx.away_id = shuffled[i + 1].id
		ko1.fixtures.append(fx)
	bracket.ko_rounds.append(ko1)

	# Simular y avanzar
	var match_seed: int = seed_value * 100000
	while bracket.ko_rounds.size() > 0:
		var current: ChampionsBracket.KORound = bracket.ko_rounds[-1]
		_simulate_round(current, teams_idx, match_seed, season_year)
		match_seed += 1000
		if current.fixtures.size() == 1:
			var final_fx: ChampionsBracket.KOFixture = current.fixtures[0]
			bracket.champion_id = final_fx.winner_id
			bracket.champion_name = teams_idx[final_fx.winner_id].name
			var loser_id: String = final_fx.away_id if final_fx.winner_id == final_fx.home_id else final_fx.home_id
			bracket.runner_up_name = teams_idx[loser_id].name
			break
		var winners: Array = []
		for fx: ChampionsBracket.KOFixture in current.fixtures:
			winners.append(fx.winner_id)
		var next_round := ChampionsBracket.KORound.new()
		next_round.index = current.index + 1
		next_round.name = KO_ROUND_NAMES.get(next_round.index, "Ronda %d" % next_round.index)
		for i in range(0, winners.size(), 2):
			if i + 1 >= winners.size(): break
			var fx := ChampionsBracket.KOFixture.new()
			fx.home_id = winners[i]
			fx.away_id = winners[i + 1]
			next_round.fixtures.append(fx)
		bracket.ko_rounds.append(next_round)

	return bracket


static func _simulate_round(round_obj: ChampionsBracket.KORound, teams_idx: Dictionary, seed_base: int, season_year: int = 0) -> void:
	# Europa/Conference: jueves intercalados.
	# Octavos: octubre, Cuartos: febrero, Semis: marzo, Final: mayo.
	var ko_date: Dictionary = {}
	if season_year > 0:
		match round_obj.name:
			"Octavos":     ko_date = DateUtil.next_dow(DateUtil.make(season_year, 10, 22), DateUtil.DOW_JU)
			"Cuartos":     ko_date = DateUtil.next_dow(DateUtil.make(season_year + 1, 2, 19), DateUtil.DOW_JU)
			"Semifinales": ko_date = DateUtil.next_dow(DateUtil.make(season_year + 1, 4, 16), DateUtil.DOW_JU)
			"Final":       ko_date = DateUtil.next_dow(DateUtil.make(season_year + 1, 5, 27), DateUtil.DOW_MI)
			_:             ko_date = {}
	var match_seed: int = seed_base
	for fx: ChampionsBracket.KOFixture in round_obj.fixtures:
		var home: Team = teams_idx[fx.home_id]
		var away: Team = teams_idx[fx.away_id]
		fx.home_name = home.name
		fx.away_name = away.name
		if not ko_date.is_empty():
			fx.match_date = ko_date
		for p: Player in home.players: p.condition = 100.0
		for p: Player in away.players: p.condition = 100.0
		var hl := AutoLineup.pick(home, home.tactics_default.formation)
		var al := AutoLineup.pick(away, away.tactics_default.formation)
		match_seed += 1
		fx.result = MatchEngine.simulate(hl, al, match_seed)
		if fx.result == null:
			fx.winner_id = home.id if home.reputation >= away.reputation else away.id
		elif fx.result.score_home > fx.result.score_away:
			fx.winner_id = home.id
		elif fx.result.score_away > fx.result.score_home:
			fx.winner_id = away.id
		else:
			fx.winner_id = home.id if home.reputation >= away.reputation else away.id
			fx.won_by_reputation = true
