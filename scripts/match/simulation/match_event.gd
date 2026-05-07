class_name MatchEvent extends Resource

# Tipos de evento. Mantenerlos como string facilita serialización y filtros.
const T_KICKOFF      := "kickoff"
const T_HALFTIME     := "halftime"
const T_FULLTIME     := "fulltime"
const T_GOAL         := "goal"
const T_SHOT_ON      := "shot_on_target"
const T_SHOT_OFF     := "shot_off_target"
const T_SHOT_BLOCKED := "shot_blocked"
const T_SAVE         := "save"
const T_FOUL         := "foul"
const T_YELLOW       := "yellow_card"
const T_RED          := "red_card"
const T_CORNER       := "corner"
const T_OFFSIDE      := "offside"
const T_INJURY       := "injury"
const T_SUBSTITUTION := "substitution"
const T_CHANCE       := "chance"
const T_TURNOVER     := "turnover"   # poco interesante, normalmente filtrado del log

@export var minute: int = 0
@export var second_in_minute: int = 0
@export var type: String = ""
@export var team_id: String = ""
@export var player_id: String = ""
@export var secondary_player_id: String = ""  # asistente, sustituido, faltado, etc.
@export var zone: String = ""                  # "def" | "mid" | "atk"
@export var description: String = ""
@export var meta: Dictionary = {}              # contenido específico por tipo


static func make(
	minute: int,
	second: int,
	type: String,
	team_id: String,
	player_id: String,
	zone: String = "",
	description: String = "",
	secondary_player_id: String = "",
	meta: Dictionary = {}
) -> MatchEvent:
	var e := MatchEvent.new()
	e.minute = minute
	e.second_in_minute = second
	e.type = type
	e.team_id = team_id
	e.player_id = player_id
	e.zone = zone
	e.description = description
	e.secondary_player_id = secondary_player_id
	e.meta = meta
	return e


func clock_str() -> String:
	return "%02d:%02d" % [minute, second_in_minute]
