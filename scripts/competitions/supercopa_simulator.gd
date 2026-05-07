class_name SupercopaSimulator extends RefCounted

# Supercopa de España v1 — formato Final 4 (como en la realidad desde 2020).
#
# 4 equipos: campeón Liga + subcampeón Liga + ganador Copa + finalista Copa.
# 2 semifinales + 1 final, todos a partido único.
# Empate al 90' → gana el de mayor reputación (representando prórroga + penaltis).
#
# Si hay duplicados (p.ej., el campeón Liga también ganó la Copa), se cae al
# 3º clasificado de Liga como sustituto.


class SupercopaResult:
	var year: int = 0
	var champion_id: String = ""
	var champion_name: String = ""
	var runner_up_id: String = ""
	var runner_up_name: String = ""
	var matches: Array = []  # 3 partidos: 2 semis + 1 final

	func has_team(team_id: String) -> bool:
		for m: Dictionary in matches:
			if m.get("home_id", "") == team_id or m.get("away_id", "") == team_id:
				return true
		return false


# qualifiers ordenados: [campeón_liga, sub_liga, ganador_copa, finalista_copa]
# fallback_team usado si hay duplicados (p.ej. campeón Liga = ganador Copa).
static func run(qualifiers: Array, fallback_team: Team, year: int, seed_value: int) -> SupercopaResult:
	# Resolver duplicados
	var teams: Array = []
	var seen_ids: Dictionary = {}
	for t: Team in qualifiers:
		if t == null:
			continue
		if not seen_ids.has(t.id):
			teams.append(t)
			seen_ids[t.id] = true
	while teams.size() < 4 and fallback_team != null and not seen_ids.has(fallback_team.id):
		teams.append(fallback_team)
		seen_ids[fallback_team.id] = true
		break
	if teams.size() < 4:
		push_warning("Supercopa: solo %d equipos clasificados, no se puede jugar Final 4" % teams.size())
		return null

	var result := SupercopaResult.new()
	result.year = year

	# Semis: 1ºLiga vs 2ºCopa, 2ºLiga vs 1ºCopa (cruzados)
	var pairs: Array = [[teams[0], teams[3]], [teams[1], teams[2]]]
	var seed_counter: int = seed_value
	var winners: Array = []
	for pair in pairs:
		var match_record: Dictionary = _play_match(pair[0], pair[1], seed_counter)
		seed_counter += 1
		match_record["round"] = "Semifinal"
		result.matches.append(match_record)
		winners.append(_winner_team(match_record, pair[0], pair[1]))

	# Final
	var fhome: Team = winners[0]
	var faway: Team = winners[1]
	var final_record: Dictionary = _play_match(fhome, faway, seed_counter)
	final_record["round"] = "Final"
	result.matches.append(final_record)
	var champion: Team = _winner_team(final_record, fhome, faway)
	var runner_up: Team = faway if champion == fhome else fhome
	result.champion_id = champion.id
	result.champion_name = champion.name
	result.runner_up_id = runner_up.id
	result.runner_up_name = runner_up.name
	return result


static func _play_match(home: Team, away: Team, seed_value: int) -> Dictionary:
	for p: Player in home.players: p.condition = 100.0
	for p: Player in away.players: p.condition = 100.0
	var hl := AutoLineup.pick(home, home.tactics_default.formation)
	var al := AutoLineup.pick(away, away.tactics_default.formation)
	var result: MatchResult = MatchEngine.simulate(hl, al, seed_value)
	return {
		"home_id": home.id, "home_name": home.name,
		"away_id": away.id, "away_name": away.name,
		"result": result,
	}


static func _winner_team(match_record: Dictionary, home: Team, away: Team) -> Team:
	var r: MatchResult = match_record.get("result")
	if r == null:
		return home
	if r.score_home > r.score_away:
		return home
	if r.score_home < r.score_away:
		return away
	# Empate: por reputación
	return home if home.reputation >= away.reputation else away
