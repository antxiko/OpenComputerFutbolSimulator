class_name MatchResult extends Resource

@export var home_team_id: String = ""
@export var away_team_id: String = ""
@export var home_team_name: String = ""
@export var away_team_name: String = ""
@export var score_home: int = 0
@export var score_away: int = 0
@export var seed: int = 0

@export var events: Array[MatchEvent] = []
# Stats finales por equipo (mismo formato que MatchState.stats)
@export var stats: Dictionary = {}
# Goleadores: player_id -> número de goles
@export var scorers: Dictionary = {}
# Tarjetas: player_id -> { yellows, red }
@export var cards: Dictionary = {}


func score_str() -> String:
	return "%d-%d" % [score_home, score_away]


func summary_line() -> String:
	return "%s %s %s" % [home_team_name, score_str(), away_team_name]


# Filtra eventos por tipo (acepta lista de tipos).
func events_of_type(types: Array) -> Array[MatchEvent]:
	var out: Array[MatchEvent] = []
	for e in events:
		if e.type in types:
			out.append(e)
	return out


func goals_events() -> Array[MatchEvent]:
	return events_of_type([MatchEvent.T_GOAL])
