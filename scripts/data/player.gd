class_name Player extends Resource

# Identidad
@export var id: String = ""
@export var name: String = ""
@export var birth_date: Dictionary = { "year": 1990, "month": 1, "day": 1 }
@export var nationality: String = ""
@export var positions: Array[String] = []
@export var preferred_foot: String = "R"
@export var shirt_number: int = 0
@export var captain: bool = false
@export var traits: Array[String] = []
@export var joined_year: int = 0

# Tier (sistema simplificado de captura)
@export var tier: String = "C"
@export var potential_tier: String = "C"
@export var overrides: Dictionary = {}

# Atributos generados (B2 extensible) — se rellenan vía PlayerFactory
@export var attributes: Dictionary = {}
@export var potential: int = 0  # techo numérico (oculto al manager)

# Estado runtime — cambia durante la temporada
@export var condition: float = 100.0  # fatiga 0-100, 100 = fresco
@export var morale: float = 70.0  # moral 0-100
@export var injury: Dictionary = {}  # vacío = sano; si no { tipo, dias_restantes }
@export var yellow_cards_season: int = 0  # acumuladas en la temporada actual
@export var red_cards_season: int = 0  # acumuladas en la temporada actual
@export var suspended_matches: int = 0  # partidos pendientes de sanción
@export var aggression: int = 0  # 0-100. Si 0, AggressionSystem la inicializa al cargar.

# Historial estadístico por temporada — se rellena al final de cada temporada
@export var history: Array = []

# Datos de contrato
@export var contract: ContractInfo = null


func age_at(year: int, month: int, day: int) -> int:
	var by: int = int(birth_date.get("year", 0))
	var bm: int = int(birth_date.get("month", 1))
	var bd: int = int(birth_date.get("day", 1))
	var a: int = year - by
	if month < bm or (month == bm and day < bd):
		a -= 1
	return a


func primary_position() -> String:
	return positions[0] if positions.size() > 0 else ""


static func from_dict(d: Dictionary) -> Player:
	var p := Player.new()
	p.id = String(d.get("id", ""))
	p.name = String(d.get("name", ""))
	var bd: Dictionary = d.get("birth_date", {})
	p.birth_date = {
		"year": int(bd.get("year", 1990)),
		"month": int(bd.get("month", 1)),
		"day": int(bd.get("day", 1)),
	}
	p.nationality = String(d.get("nationality", ""))
	var pos_in: Array = d.get("positions", [])
	p.positions = []
	for x in pos_in:
		p.positions.append(String(x))
	p.preferred_foot = String(d.get("preferred_foot", "R"))
	p.shirt_number = int(d.get("shirt_number", 0))
	p.captain = bool(d.get("captain", false))
	var tr_in: Array = d.get("traits", [])
	p.traits = []
	for x in tr_in:
		p.traits.append(String(x))
	p.joined_year = int(d.get("joined_year", 0))
	p.tier = String(d.get("tier", "C"))
	p.potential_tier = String(d.get("potential_tier", p.tier))
	p.overrides = d.get("overrides", {}).duplicate()
	if d.has("contract"):
		p.contract = ContractInfo.from_dict(d.get("contract", {}))
	else:
		p.contract = ContractInfo.new()
	return p
