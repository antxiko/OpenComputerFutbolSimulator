class_name InboxMessage extends Resource

# Mensaje en el inbox del usuario.
# Tipos:
#   "injury"         — parte médico (jugador lesionado)
#   "press"          — resumen de press conference (post)
#   "board_message"  — comunicado del board (objetivos, evaluación, advertencia)
#   "agent_offer"    — agente de jugador rival ofreciéndolo
#   "transfer_rumor" — rumor de mercado
#   "manager_offer"  — oferta de otro club al usuario
#   "coach_award"    — premio entrenador del mes
#   "objective"      — objetivo de temporada generado / evaluado
#   "national_call"  — jugador del usuario convocado por su selección (v0.3.3)
#   "general"        — mensaje genérico

@export var type: String = "general"
@export var title: String = ""
@export var body: String = ""
@export var read: bool = false
@export var year_when: int = 0       # año del juego cuando se generó
@export var jornada_when: int = 0    # jornada Liga al generarse (0 si fuera de temporada)
@export var data: Dictionary = {}    # extra payload (ej. player_id, team_id)


static func make(type_: String, title_: String, body_: String, year_: int, jornada_: int = 0, data_: Dictionary = {}) -> InboxMessage:
	var m := InboxMessage.new()
	m.type = type_
	m.title = title_
	m.body = body_
	m.year_when = year_
	m.jornada_when = jornada_
	m.data = data_.duplicate(true)
	m.read = false
	return m


func to_dict() -> Dictionary:
	return {
		"type": type,
		"title": title,
		"body": body,
		"read": read,
		"year_when": year_when,
		"jornada_when": jornada_when,
		"data": data.duplicate(true),
	}


static func from_dict(d: Dictionary) -> InboxMessage:
	var m := InboxMessage.new()
	m.type = String(d.get("type", "general"))
	m.title = String(d.get("title", ""))
	m.body = String(d.get("body", ""))
	m.read = bool(d.get("read", false))
	m.year_when = int(d.get("year_when", 0))
	m.jornada_when = int(d.get("jornada_when", 0))
	m.data = d.get("data", {}).duplicate(true) if d.get("data") != null else {}
	return m
