class_name Tactics extends Resource

@export var formation: String = "4-3-3"
@export var mentality: String = "equilibrado"
@export var tempo: String = "normal"
@export var pressing: String = "medio"
@export var width: String = "normal"


static func from_dict(d: Dictionary) -> Tactics:
	var t := Tactics.new()
	t.formation = String(d.get("formation", "4-3-3"))
	t.mentality = String(d.get("mentality", "equilibrado"))
	t.tempo = String(d.get("tempo", "normal"))
	t.pressing = String(d.get("pressing", "medio"))
	t.width = String(d.get("width", "normal"))
	return t
