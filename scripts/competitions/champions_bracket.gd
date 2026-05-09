class_name ChampionsBracket extends RefCounted

# Estado completo de una edición de Champions League.
# Formato: 16 equipos (4 grupos de 4) + KO de octavos a final.
#
# Fase de grupos: solo IDA (3 jornadas por equipo, 6 partidos por grupo).
# KO: octavos / cuartos / semis / final, partido único.

class GroupStanding:
	var team_id: String
	var team_name: String
	var played: int = 0
	var won: int = 0
	var drawn: int = 0
	var lost: int = 0
	var goals_for: int = 0
	var goals_against: int = 0

	func points() -> int:
		return won * 3 + drawn

	func goal_diff() -> int:
		return goals_for - goals_against


class GroupMatch:
	var jornada: int = 0
	var home_id: String
	var away_id: String
	var home_name: String = ""
	var away_name: String = ""
	var result: MatchResult = null
	var match_date: Dictionary = {}  # { year, month, day }


class Group:
	var letter: String = ""           # "A", "B", "C", "D"
	var team_ids: Array = []          # Array[String] (4 ids)
	var standings: Dictionary = {}    # team_id -> GroupStanding
	var matches: Array = []           # Array[GroupMatch] (6 partidos)

	func sorted_standings() -> Array:
		var arr: Array = standings.values()
		arr.sort_custom(func(a: GroupStanding, b: GroupStanding) -> bool:
			if a.points() != b.points():
				return a.points() > b.points()
			if a.goal_diff() != b.goal_diff():
				return a.goal_diff() > b.goal_diff()
			return a.goals_for > b.goals_for)
		return arr


class KOFixture:
	var home_id: String
	var away_id: String
	var home_name: String = ""
	var away_name: String = ""
	var result: MatchResult = null
	var winner_id: String = ""
	var won_by_reputation: bool = false
	var match_date: Dictionary = {}  # { year, month, day }


class KORound:
	var index: int = 0      # 1=octavos, 2=cuartos, 3=semis, 4=final
	var name: String = ""
	var fixtures: Array = []  # Array[KOFixture]


# Estado
var groups: Array = []        # Array[Group] (4 grupos)
var ko_rounds: Array = []     # Array[KORound] (octavos -> final)
var champion_id: String = ""
var champion_name: String = ""
var runner_up_name: String = ""
var season_year: int = 0
