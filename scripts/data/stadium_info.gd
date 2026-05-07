class_name StadiumInfo extends Resource

@export var name: String = ""
@export var capacity: int = 0


static func from_dict(d: Dictionary) -> StadiumInfo:
	var s := StadiumInfo.new()
	s.name = String(d.get("name", ""))
	s.capacity = int(d.get("capacity", 0))
	return s
