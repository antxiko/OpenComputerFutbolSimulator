class_name MatchState extends RefCounted

# Estado mutable durante un partido. El motor lo recibe y lo modifica tick a tick.

const HALF_DURATION: int = 2700  # 45 minutos en segundos
const FULL_DURATION: int = 5400  # 90 minutos
const MAX_SUBS_PER_TEAM: int = 5

var home_lineup: Lineup
var away_lineup: Lineup
var clock_seconds: int = 0
var half: int = 1
var score_home: int = 0
var score_away: int = 0
var possession_team_id: String = ""
var zone: String = "mid"  # zona desde POV del equipo en posesión

var events: Array[MatchEvent] = []
var rng: RandomNumberGenerator

# Stats por equipo
var stats: Dictionary = {}        # team_id -> Dictionary
# Estado por jugador
var on_pitch: Dictionary = {}     # player_id -> bool
var condition: Dictionary = {}    # player_id -> float (0-100)
var yellow_count: Dictionary = {} # player_id -> int
var red_carded: Dictionary = {}   # player_id -> bool
var goals_scored: Dictionary = {} # player_id -> int

var subs_made: Dictionary = {}    # team_id -> int


func init_from_lineups(home: Lineup, away: Lineup, seed_value: int) -> void:
	home_lineup = home
	away_lineup = away
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	stats[home.team.id] = _empty_stats()
	stats[away.team.id] = _empty_stats()
	for p in home.starting_eleven:
		_init_player(p)
	for p in away.starting_eleven:
		_init_player(p)
	for p in home.subs_available:
		_init_player(p)
	for p in away.subs_available:
		_init_player(p)
	# El equipo que da el saque inicial: home (simplificación)
	possession_team_id = home.team.id
	zone = "mid"
	subs_made[home.team.id] = 0
	subs_made[away.team.id] = 0


func _init_player(p: Player) -> void:
	on_pitch[p.id] = false
	condition[p.id] = p.condition  # arranca con su fatiga acumulada (suele ser 100)
	yellow_count[p.id] = 0
	red_carded[p.id] = false
	goals_scored[p.id] = 0


func _empty_stats() -> Dictionary:
	return {
		"possession_secs": 0,
		"shots": 0,
		"shots_on_target": 0,
		"shots_off_target": 0,
		"shots_blocked": 0,
		"goals": 0,
		"saves": 0,
		"corners": 0,
		"fouls": 0,
		"offsides": 0,
		"yellows": 0,
		"reds": 0,
	}


func lineup_for(team_id: String) -> Lineup:
	if team_id == home_lineup.team.id:
		return home_lineup
	return away_lineup


func other_team_id(team_id: String) -> String:
	if team_id == home_lineup.team.id:
		return away_lineup.team.id
	return home_lineup.team.id


func is_home(team_id: String) -> bool:
	return team_id == home_lineup.team.id


# Marca al inicio del partido los 11 titulares como en pista.
func set_starting_on_pitch() -> void:
	for p in home_lineup.starting_eleven:
		on_pitch[p.id] = true
	for p in away_lineup.starting_eleven:
		on_pitch[p.id] = true


func minute() -> int:
	return clock_seconds / 60


func second_in_minute() -> int:
	return clock_seconds % 60
