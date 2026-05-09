class_name StadiumInfo extends Resource

@export var name: String = ""
@export var capacity: int = 0

# Tier del estadio (1=básico, 5=élite). Determina ticket price base.
@export var tier: int = 1

# Estado de mantenimiento (0-100). 100 = perfecto. Baja sin mantenimiento
# y reduce occupancy.
@export var state: float = 80.0

# Mejoras instaladas (cesped_hibrido, palcos_vip, museo, gym_top, etc.)
@export var upgrades: Array = []


static func from_dict(d: Dictionary) -> StadiumInfo:
	var s := StadiumInfo.new()
	s.name = String(d.get("name", ""))
	s.capacity = int(d.get("capacity", 0))
	s.tier = int(d.get("tier", 0))
	s.state = float(d.get("state", 0.0))
	s.upgrades = d.get("upgrades", []).duplicate(true)
	# Defaults derivados de capacity si no vienen en JSON
	if s.tier <= 0:
		if s.capacity >= 75000: s.tier = 5
		elif s.capacity >= 55000: s.tier = 4
		elif s.capacity >= 35000: s.tier = 3
		elif s.capacity >= 20000: s.tier = 2
		else: s.tier = 1
	if s.state <= 0.0:
		s.state = 80.0
	return s


func base_ticket_price() -> int:
	match tier:
		1: return 22
		2: return 32
		3: return 45
		4: return 58
		5: return 75
		_: return 30
