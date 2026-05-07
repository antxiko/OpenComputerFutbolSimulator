class_name ManagerInfo extends Resource

@export var name: String = ""
@export var nationality: String = ""
@export var birth_year: int = 0
@export var preferred_formation: String = "4-3-3"
@export var preferred_style: String = "equilibrado"


static func from_dict(d: Dictionary) -> ManagerInfo:
	var m := ManagerInfo.new()
	m.name = String(d.get("name", ""))
	m.nationality = String(d.get("nationality", ""))
	m.birth_year = int(d.get("birth_year", 0))
	m.preferred_formation = String(d.get("preferred_formation", "4-3-3"))
	m.preferred_style = String(d.get("preferred_style", "equilibrado"))
	return m
