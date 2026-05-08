class_name EuropeanTeams extends RefCounted

# Genera los 12 equipos europeos ficticios usados en Champions League.
#
# Los CLUBES son reales (Bayern, City, PSG, etc.) pero las plantillas son
# completamente procedurales con NamePool, para no mantener una segunda BD
# de jugadores reales europeos. La idea es que el meta-juego "Champions"
# tenga rivales con la fuerza esperable, no que sean simulación 1:1.
#
# Cada equipo tiene 22 jugadores generados según su reputación + nacionalidad
# del país (con NamePool internacional, sesgado al país del club).

# Reputación 90+ = élite mundial. 80-89 = top continental. 70-79 = competitivo.
const EUROPEAN_CLUBS := [
	{ "id": "eu_bayern",     "name": "FC Bayern München",  "short": "BAY", "city": "München",   "country": "DE", "reputation": 92, "primary": "#DC052D", "secondary": "#FFFFFF" },
	{ "id": "eu_man_city",   "name": "Manchester City FC", "short": "MCI", "city": "Manchester","country": "GB-ENG", "reputation": 92, "primary": "#6CABDD", "secondary": "#FFFFFF" },
	{ "id": "eu_psg",        "name": "Paris Saint-Germain","short": "PSG", "city": "París",     "country": "FR", "reputation": 90, "primary": "#004170", "secondary": "#DA291C" },
	{ "id": "eu_arsenal",    "name": "Arsenal FC",         "short": "ARS", "city": "Londres",   "country": "GB-ENG", "reputation": 88, "primary": "#EF0107", "secondary": "#FFFFFF" },
	{ "id": "eu_inter",      "name": "FC Internazionale",  "short": "INT", "city": "Milán",     "country": "IT", "reputation": 88, "primary": "#0C2340", "secondary": "#000000" },
	{ "id": "eu_milan",      "name": "AC Milan",           "short": "MIL", "city": "Milán",     "country": "IT", "reputation": 85, "primary": "#FB090B", "secondary": "#000000" },
	{ "id": "eu_liverpool",  "name": "Liverpool FC",       "short": "LIV", "city": "Liverpool", "country": "GB-ENG", "reputation": 88, "primary": "#C8102E", "secondary": "#FFFFFF" },
	{ "id": "eu_chelsea",    "name": "Chelsea FC",         "short": "CHE", "city": "Londres",   "country": "GB-ENG", "reputation": 84, "primary": "#034694", "secondary": "#FFFFFF" },
	{ "id": "eu_dortmund",   "name": "Borussia Dortmund",  "short": "BVB", "city": "Dortmund",  "country": "DE", "reputation": 82, "primary": "#FDE100", "secondary": "#000000" },
	{ "id": "eu_porto",      "name": "FC Porto",           "short": "POR", "city": "Porto",     "country": "PT", "reputation": 78, "primary": "#0066B3", "secondary": "#FFFFFF" },
	{ "id": "eu_benfica",    "name": "SL Benfica",         "short": "BEN", "city": "Lisboa",    "country": "PT", "reputation": 80, "primary": "#E8262A", "secondary": "#FFFFFF" },
	{ "id": "eu_juventus",   "name": "Juventus FC",        "short": "JUV", "city": "Turín",     "country": "IT", "reputation": 84, "primary": "#000000", "secondary": "#FFFFFF" },
]

# Layout estándar 4-3-3 para todos los equipos europeos.
const SQUAD_TEMPLATE := [
	# 11 titulares + 11 suplentes (formación 4-3-3 con sustitutos)
	{ "slots": ["GK"],  "tier_for_rep": ["S","A","A","B","C"] },
	{ "slots": ["GK"],  "tier_for_rep": ["B","B","C","C","D"] },
	{ "slots": ["LB"],  "tier_for_rep": ["A","A","B","C","C"] },
	{ "slots": ["LB"],  "tier_for_rep": ["C","C","C","D","D"] },
	{ "slots": ["CB"],  "tier_for_rep": ["S","A","A","B","C"] },
	{ "slots": ["CB"],  "tier_for_rep": ["A","B","B","C","C"] },
	{ "slots": ["CB"],  "tier_for_rep": ["B","C","C","D","D"] },
	{ "slots": ["RB"],  "tier_for_rep": ["A","A","B","C","C"] },
	{ "slots": ["RB"],  "tier_for_rep": ["C","C","C","D","D"] },
	{ "slots": ["CDM"], "tier_for_rep": ["A","A","B","B","C"] },
	{ "slots": ["CDM"], "tier_for_rep": ["B","C","C","D","D"] },
	{ "slots": ["CM"],  "tier_for_rep": ["S","A","A","B","C"] },
	{ "slots": ["CM"],  "tier_for_rep": ["A","B","B","C","C"] },
	{ "slots": ["CAM"], "tier_for_rep": ["S","A","A","B","C"] },
	{ "slots": ["CAM"], "tier_for_rep": ["B","C","C","D","D"] },
	{ "slots": ["LW"],  "tier_for_rep": ["S","A","A","B","C"] },
	{ "slots": ["LW"],  "tier_for_rep": ["B","C","C","D","D"] },
	{ "slots": ["RW"],  "tier_for_rep": ["S","A","A","B","C"] },
	{ "slots": ["RW"],  "tier_for_rep": ["B","C","C","D","D"] },
	{ "slots": ["ST"],  "tier_for_rep": ["S","A","A","B","C"] },
	{ "slots": ["ST"],  "tier_for_rep": ["A","B","B","C","C"] },
	{ "slots": ["ST"],  "tier_for_rep": ["B","C","C","D","D"] },
]


# Genera los 12 equipos europeos. Cada uno con plantilla procedural según
# su reputación, nombres del NamePool. Determinista por seed_base.
static func generate_all(season_year: int, seed_base: int) -> Array:
	var teams: Array = []
	for i in EUROPEAN_CLUBS.size():
		var club: Dictionary = EUROPEAN_CLUBS[i]
		teams.append(_build_team(club, season_year, seed_base + i * 17))
	return teams


static func _build_team(club: Dictionary, season_year: int, seed_value: int) -> Team:
	var t := Team.new()
	t.id = String(club["id"])
	t.name = String(club["name"])
	t.short_name = String(club["short"])
	t.city = String(club["city"])
	t.founded = 1900
	t.division = "champions"  # tag distintivo
	t.reputation = int(club["reputation"])
	t.signing_policy = "open"
	t.colors = {
		"primary": String(club["primary"]),
		"secondary": String(club["secondary"]),
	}

	t.stadium = StadiumInfo.new()
	t.stadium.name = "%s Stadium" % t.short_name
	t.stadium.capacity = 60000

	t.manager = ManagerInfo.new()
	t.manager.name = "Coach %s" % t.short_name
	t.manager.nationality = String(club["country"])
	t.manager.birth_year = 1970
	t.manager.preferred_formation = "4-3-3"
	t.manager.preferred_style = "posesion"

	t.tactics_default = Tactics.new()
	t.tactics_default.formation = "4-3-3"
	t.tactics_default.mentality = "balanced"
	t.tactics_default.tempo = "normal"
	t.tactics_default.pressing = "medium"
	t.tactics_default.width = "normal"

	t.finances = FinancesInfo.new()
	t.finances.budget_transfers_eur = 50_000_000 * (t.reputation - 60) / 30
	t.finances.wage_budget_eur_year = 100_000_000 * (t.reputation - 60) / 30
	t.finances.tv_revenue_eur_year = 80_000_000

	# Plantilla procedural
	t.players = _build_squad(t, season_year, seed_value)
	return t


static func _build_squad(team: Team, season_year: int, seed_value: int) -> Array[Player]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rep: int = team.reputation
	var rep_tier: int = 0
	if rep >= 90: rep_tier = 0
	elif rep >= 85: rep_tier = 1
	elif rep >= 80: rep_tier = 2
	elif rep >= 75: rep_tier = 3
	else: rep_tier = 4

	var players: Array[Player] = []
	for i in SQUAD_TEMPLATE.size():
		var spec: Dictionary = SQUAD_TEMPLATE[i]
		var slots: Array = spec["slots"]
		var tier_arr: Array = spec["tier_for_rep"]
		var tier: String = String(tier_arr[rep_tier])
		var p := Player.new()
		p.id = "%s_p%03d" % [team.short_name.to_lower(), i + 1]
		var name_data: Dictionary = NamePool.generate(rng)
		p.name = String(name_data["name"])
		p.nationality = String(name_data["nationality"])
		# Edad
		var age: int = rng.randi_range(20, 32)
		p.birth_date = {
			"year": season_year - age,
			"month": rng.randi_range(1, 12),
			"day": rng.randi_range(1, 28),
		}
		var typed_slots: Array[String] = []
		for s: Variant in slots:
			typed_slots.append(String(s))
		p.positions = typed_slots
		p.preferred_foot = "L" if rng.randf() < 0.27 else "R"
		p.tier = tier
		p.potential_tier = tier
		p.shirt_number = i + 1
		p.captain = (i == 11)  # arbitrario: el #12 es capitán
		p.traits = []
		p.overrides = {}
		p.joined_year = season_year - rng.randi_range(0, 5)
		p.contract = ContractInfo.new()
		p.contract.until_year = season_year + rng.randi_range(2, 5)
		p.contract.salary_eur_year = _salary_for_tier(tier)
		p.contract.release_clause_eur = _clause_for_tier(tier)
		p.condition = 100.0
		p.morale = 70.0
		p.injury = {}
		p.history = []
		# Generar atributos
		PlayerFactory.generate_attributes(p, season_year, seed_value ^ hash(p.id))
		players.append(p)
	return players


static func _salary_for_tier(tier: String) -> int:
	match tier:
		"S": return 12_000_000
		"A": return 6_000_000
		"B": return 2_500_000
		"C": return 1_000_000
		"D": return 500_000
		_:   return 800_000


static func _clause_for_tier(tier: String) -> int:
	match tier:
		"S": return 200_000_000
		"A": return 80_000_000
		"B": return 35_000_000
		"C": return 15_000_000
		"D": return 7_000_000
		_:   return 15_000_000
