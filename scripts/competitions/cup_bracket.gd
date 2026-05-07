class_name CupBracket extends RefCounted

# Bracket de Copa del Rey simplificado.
# 42 equipos → 6 rondas single-elim con byes en la 1ª ronda para que el bracket
# sea potencia de 2 a partir de la 2ª ronda.
#
# Round 1 (Eliminatoria previa):  20 equipos peor clasificados juegan, 22 byes.
# Round 2 (Dieciseisavos):        32 equipos, 16 partidos.
# Round 3 (Octavos):              16 equipos, 8 partidos.
# Round 4 (Cuartos):               8 equipos, 4 partidos.
# Round 5 (Semis):                 4 equipos, 2 partidos.
# Round 6 (Final):                 2 equipos, 1 partido.


class Fixture:
	var home_id: String
	var away_id: String
	var home_name: String = ""
	var away_name: String = ""
	var result: MatchResult = null  # rellenado tras simular
	var winner_id: String = ""
	# Si el partido acabó en empate y resolvimos por reputación
	var won_by_reputation: bool = false


class Round:
	var index: int = 0
	var name: String = ""
	var fixtures: Array = []  # Array[Fixture]
	var byes: Array = []      # Array[String] team_ids con bye en esta ronda


var rounds: Array = []  # Array[Round]
var champion_id: String = ""
var champion_name: String = ""
var runner_up_name: String = ""


# Genera el bracket inicial. Solo crea Round 1; las siguientes se generan tras
# resolver la previa.
static func generate_initial(teams: Array, seed_value: int) -> CupBracket:
	var bracket := CupBracket.new()

	# Ordenar por reputación desc
	var sorted_teams: Array = teams.duplicate()
	sorted_teams.sort_custom(func(a: Team, b: Team) -> bool:
		return a.reputation > b.reputation)

	var n: int = sorted_teams.size()
	# Para llegar a 32 en Round 2: necesitamos 32 - n_byes = pares-de-juego en Round 1
	# n_byes = max(64 - n, 0) si n <= 64; pero queremos 32 en Round 2.
	# Si n = 42: byes = 22, jugadores = 20 → 10 partidos → 10 ganadores + 22 byes = 32 ✓
	var byes_count: int = 32 - (n - 32)  # byes_count = 64 - n; for n=42 → 22
	if n <= 32:
		# Si entran 32 o menos, bracket directo de 16avos
		byes_count = n  # todos byes (ronda 1 vacía)
	if n > 64:
		byes_count = 0  # demasiados, todos juegan (no usado en v1)

	var bye_teams: Array = sorted_teams.slice(0, byes_count)
	var playing: Array = sorted_teams.slice(byes_count)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Shuffle determinista (sort por hash combinado con seed)
	playing.sort_custom(func(a: Team, b: Team) -> bool:
		return hash(a.id + str(seed_value)) < hash(b.id + str(seed_value)))

	# Round 1
	var round1 := Round.new()
	round1.index = 1
	round1.name = "Eliminatoria preliminar"
	round1.byes = bye_teams.map(func(t: Team) -> String: return t.id)
	for i in range(0, playing.size(), 2):
		if i + 1 >= playing.size():
			break
		var fx := Fixture.new()
		# Local: el de mayor reputación de los dos (los buenos en casa)
		if playing[i].reputation >= playing[i+1].reputation:
			fx.home_id = playing[i].id; fx.home_name = playing[i].name
			fx.away_id = playing[i+1].id; fx.away_name = playing[i+1].name
		else:
			fx.home_id = playing[i+1].id; fx.home_name = playing[i+1].name
			fx.away_id = playing[i].id; fx.away_name = playing[i].name
		round1.fixtures.append(fx)
	bracket.rounds.append(round1)
	return bracket


# Genera la siguiente ronda dado los ganadores de la actual.
# Si ya estamos en la final, no hace nada.
static func ROUND_NAMES() -> Dictionary:
	return {
		32: "Dieciseisavos",
		16: "Octavos",
		8:  "Cuartos",
		4:  "Semifinales",
		2:  "Final",
	}


func generate_next_round(advancing_team_ids: Array, advancing_team_names: Dictionary, seed_value: int) -> bool:
	var n: int = advancing_team_ids.size()
	if n < 2:
		return false  # ya tenemos campeón
	var next_round := Round.new()
	next_round.index = rounds.size() + 1
	next_round.name = ROUND_NAMES().get(n, "Ronda %d" % next_round.index)

	# Shuffle determinista
	var ids: Array = advancing_team_ids.duplicate()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return hash(a + str(seed_value) + str(next_round.index)) < hash(b + str(seed_value) + str(next_round.index)))

	for i in range(0, ids.size(), 2):
		if i + 1 >= ids.size():
			break
		var fx := Fixture.new()
		fx.home_id = ids[i]
		fx.away_id = ids[i+1]
		fx.home_name = String(advancing_team_names.get(fx.home_id, fx.home_id))
		fx.away_name = String(advancing_team_names.get(fx.away_id, fx.away_id))
		next_round.fixtures.append(fx)

	rounds.append(next_round)
	return true


func current_round() -> Round:
	return rounds[-1] if rounds.size() > 0 else null


func is_final() -> bool:
	return rounds.size() > 0 and rounds[-1].fixtures.size() == 1
