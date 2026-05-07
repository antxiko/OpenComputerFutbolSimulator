extends SceneTree

# Generador de plantillas-esqueleto para equipos.
# Lanzar con:
#   godot --path . --headless --script scripts/tools/generate_team_templates.gd
#
# Para cada equipo de TEAM_SPECS:
#   - Si el archivo de destino ya existe, NO se sobrescribe (se imprime aviso).
#   - Si no existe, se genera un JSON con metadatos reales y 25 jugadores
#     placeholder (nombres tipo "FCB Player 12") con tiers/posiciones plausibles
#     según la reputación del equipo. El usuario reemplaza nombres y ajusta.
#
# El campo "_draft_note" del JSON marca el archivo como esqueleto pendiente.


# -------- Plantilla de slots: 25 jugadores con posición y rol --------
# Roles: "starter" | "sub" | "youth" — controla rango de tier y edad.
const SLOTS: Array = [
	["GK",  "starter"],
	["GK",  "sub"],
	["GK",  "youth"],
	["CB",  "starter"],
	["CB",  "starter"],
	["CB",  "sub"],
	["CB",  "youth"],
	["LB",  "starter"],
	["LB",  "sub"],
	["RB",  "starter"],
	["RB",  "sub"],
	["CDM", "starter"],
	["CDM", "sub"],
	["CM",  "starter"],
	["CM",  "starter"],
	["CM",  "sub"],
	["CAM", "starter"],
	["CAM", "sub"],
	["LW",  "starter"],
	["LW",  "sub"],
	["RW",  "starter"],
	["RW",  "sub"],
	["ST",  "starter"],
	["ST",  "sub"],
	["ST",  "youth"],
]

# -------- Banda de tier por reputación del equipo y por rol del slot --------
# Devuelve un Array de 3 strings: [tier_starter, tier_sub, tier_youth_or_squad]
# para indicar el centro de la distribución; añadimos algo de varianza.
static func tier_band(reputation: int, role: String, rng: RandomNumberGenerator) -> Array:
	# Devuelve [tier_actual, tier_potencial]
	var actual: String
	var potential: String
	if reputation >= 92:
		# Élite (Madrid/Barça-tier)
		match role:
			"starter": actual = _pick(rng, ["S", "S", "A", "A", "A"]); potential = _step_up(actual, 1)
			"sub":     actual = _pick(rng, ["A", "B", "B", "C"]);      potential = _step_up(actual, 1)
			"youth":   actual = _pick(rng, ["Y", "C", "Y"]);            potential = _pick(rng, ["A", "B", "S"])
	elif reputation >= 80:
		match role:
			"starter": actual = _pick(rng, ["S", "A", "A", "B", "B"]); potential = _step_up(actual, 1)
			"sub":     actual = _pick(rng, ["B", "B", "C", "D"]);       potential = _step_up(actual, 1)
			"youth":   actual = _pick(rng, ["Y", "Y", "C", "D"]);       potential = _pick(rng, ["B", "C", "A"])
	elif reputation >= 70:
		match role:
			"starter": actual = _pick(rng, ["A", "B", "B", "B", "C"]); potential = _step_up(actual, 1)
			"sub":     actual = _pick(rng, ["B", "C", "C", "D"]);       potential = _step_up(actual, 1)
			"youth":   actual = _pick(rng, ["Y", "Y", "D"]);             potential = _pick(rng, ["B", "C"])
	elif reputation >= 60:
		match role:
			"starter": actual = _pick(rng, ["B", "B", "C", "C", "C"]); potential = _step_up(actual, 1)
			"sub":     actual = _pick(rng, ["C", "C", "D", "D"]);       potential = _step_up(actual, 0)
			"youth":   actual = _pick(rng, ["Y", "Y", "D"]);             potential = _pick(rng, ["B", "C"])
	elif reputation >= 50:
		match role:
			"starter": actual = _pick(rng, ["B", "C", "C", "C", "D"]); potential = _step_up(actual, 0)
			"sub":     actual = _pick(rng, ["C", "D", "D", "D"]);       potential = _step_up(actual, 0)
			"youth":   actual = _pick(rng, ["Y", "Y", "D"]);             potential = _pick(rng, ["C", "D"])
	else:
		match role:
			"starter": actual = _pick(rng, ["C", "C", "D", "D", "D"]); potential = _step_up(actual, 0)
			"sub":     actual = _pick(rng, ["D", "D", "D", "Y"]);       potential = _step_up(actual, 0)
			"youth":   actual = _pick(rng, ["Y", "Y", "D"]);             potential = _pick(rng, ["D", "C"])
	return [actual, potential]


static func _pick(rng: RandomNumberGenerator, options: Array) -> String:
	return options[rng.randi() % options.size()]


# Sube un tier "n" niveles en la jerarquía (Y < D < C < B < A < S).
# n=0 mantiene el tier; n=1 sube uno; etc. Tope en S.
static func _step_up(tier: String, n: int) -> String:
	var ladder: Array = ["Y", "D", "C", "B", "A", "S"]
	var idx: int = ladder.find(tier)
	if idx < 0:
		return tier
	idx = mini(ladder.size() - 1, idx + n)
	return ladder[idx]


# -------- Edad por rol --------
static func age_for_role(role: String, rng: RandomNumberGenerator) -> int:
	match role:
		"starter": return rng.randi_range(24, 32)
		"sub":     return rng.randi_range(22, 30)
		"youth":   return rng.randi_range(16, 21)
		_:         return rng.randi_range(20, 28)


# -------- Salario plausible por tier y reputación del equipo --------
static func salary_eur(tier: String, reputation: int, rng: RandomNumberGenerator) -> int:
	var base: int = 0
	match tier:
		"S": base = rng.randi_range(8_000_000, 15_000_000)
		"A": base = rng.randi_range(4_000_000, 8_000_000)
		"B": base = rng.randi_range(1_500_000, 4_000_000)
		"C": base = rng.randi_range(700_000, 1_800_000)
		"D": base = rng.randi_range(400_000, 800_000)
		"Y": base = rng.randi_range(150_000, 450_000)
		_:   base = 500_000
	# Multiplicador por reputación (clubes ricos pagan más)
	var rep_mult: float = clampf(0.6 + reputation * 0.012, 0.7, 1.6)
	return int(round(base * rep_mult))


# -------- Cláusula plausible por tier y reputación --------
static func clause_eur(tier: String, reputation: int) -> int:
	var base: int = 0
	match tier:
		"S": base = 200_000_000
		"A": base = 80_000_000
		"B": base = 35_000_000
		"C": base = 15_000_000
		"D": base = 7_000_000
		"Y": base = 20_000_000  # promesas suelen tener cláusulas altas
	return base


# -------- Dorsal por slot (sin colisiones intra-equipo) --------
static func shirt_for_slot(slot_index: int, position: String) -> int:
	var preferred: Dictionary = {
		"GK":  [1, 13, 25],
		"CB":  [4, 5, 14, 22],
		"LB":  [3, 17],
		"RB":  [2, 16],
		"CDM": [6, 23],
		"CM":  [8, 18, 21],
		"CAM": [10, 20],
		"LW":  [11, 19],
		"RW":  [7, 15],
		"ST":  [9, 24, 27],
	}
	var seen: Dictionary = {}
	var slot_n: int = 0
	# Cuántas veces hemos visto esta posición hasta este slot
	for i in slot_index:
		if SLOTS[i][0] == position:
			slot_n += 1
	var nums: Array = preferred.get(position, [99])
	if slot_n < nums.size():
		return int(nums[slot_n])
	return 30 + slot_index  # fallback


# ============================================================================
# Especificaciones de equipos a generar
# ============================================================================
const TEAM_SPECS: Array = [
	{
		"id": "fc_barcelona",
		"name": "Fútbol Club Barcelona",
		"short_name": "FCB",
		"city": "Barcelona",
		"founded": 1899,
		"stadium_name": "Spotify Camp Nou",
		"stadium_capacity": 99354,
		"primary_color": "#A50044",
		"secondary_color": "#004D98",
		"division": "primera",
		"reputation": 96,
		"signing_policy": "open",
		"manager_name": "Hansi Flick",
		"manager_nationality": "DE",
		"manager_birth_year": 1965,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": {
			"formation": "4-3-3",
			"mentality": "ofensivo",
			"tempo": "normal",
			"pressing": "alto",
			"width": "ancho",
		},
		"finances": {
			"budget_transfers_eur": 80000000,
			"wage_budget_eur_year": 280000000,
			"tv_revenue_eur_year": 160000000,
		},
	},
	{
		"id": "atletico_madrid",
		"name": "Club Atlético de Madrid",
		"short_name": "ATM",
		"city": "Madrid",
		"founded": 1903,
		"stadium_name": "Cívitas Metropolitano",
		"stadium_capacity": 70460,
		"primary_color": "#CB3524",
		"secondary_color": "#272E61",
		"division": "primera",
		"reputation": 88,
		"signing_policy": "open",
		"manager_name": "Diego Pablo Simeone",
		"manager_nationality": "AR",
		"manager_birth_year": 1970,
		"preferred_formation": "4-4-2",
		"preferred_style": "equilibrado",
		"tactics_default": {
			"formation": "4-4-2",
			"mentality": "equilibrado",
			"tempo": "normal",
			"pressing": "alto",
			"width": "normal",
		},
		"finances": {
			"budget_transfers_eur": 60000000,
			"wage_budget_eur_year": 180000000,
			"tv_revenue_eur_year": 110000000,
		},
	},
	{
		"id": "real_sociedad",
		"name": "Real Sociedad de Fútbol",
		"short_name": "RSO",
		"city": "San Sebastián",
		"founded": 1909,
		"stadium_name": "Reale Arena",
		"stadium_capacity": 39500,
		"primary_color": "#0067B1",
		"secondary_color": "#FFFFFF",
		"division": "primera",
		"reputation": 76,
		"signing_policy": "open",
		"manager_name": "Sergio Francisco",
		"manager_nationality": "ES",
		"manager_birth_year": 1983,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": {
			"formation": "4-3-3",
			"mentality": "equilibrado",
			"tempo": "normal",
			"pressing": "medio",
			"width": "normal",
		},
		"finances": {
			"budget_transfers_eur": 25000000,
			"wage_budget_eur_year": 80000000,
			"tv_revenue_eur_year": 65000000,
		},
	},
	{
		"id": "villarreal_cf",
		"name": "Villarreal Club de Fútbol",
		"short_name": "VIL",
		"city": "Villarreal",
		"founded": 1923,
		"stadium_name": "Estadio de la Cerámica",
		"stadium_capacity": 23500,
		"primary_color": "#FFE667",
		"secondary_color": "#005187",
		"division": "primera",
		"reputation": 75,
		"signing_policy": "open",
		"manager_name": "Marcelino García Toral",
		"manager_nationality": "ES",
		"manager_birth_year": 1965,
		"preferred_formation": "4-4-2",
		"preferred_style": "equilibrado",
		"tactics_default": {
			"formation": "4-4-2",
			"mentality": "equilibrado",
			"tempo": "normal",
			"pressing": "medio",
			"width": "normal",
		},
		"finances": {
			"budget_transfers_eur": 25000000,
			"wage_budget_eur_year": 75000000,
			"tv_revenue_eur_year": 60000000,
		},
	},
	{
		"id": "real_betis",
		"name": "Real Betis Balompié",
		"short_name": "BET",
		"city": "Sevilla",
		"founded": 1907,
		"stadium_name": "Estadio Benito Villamarín",
		"stadium_capacity": 60721,
		"primary_color": "#0BB363",
		"secondary_color": "#FFFFFF",
		"division": "primera",
		"reputation": 72,
		"signing_policy": "open",
		"manager_name": "Manuel Pellegrini",
		"manager_nationality": "CL",
		"manager_birth_year": 1953,
		"preferred_formation": "4-2-3-1",
		"preferred_style": "posesion",
		"tactics_default": {
			"formation": "4-2-3-1",
			"mentality": "equilibrado",
			"tempo": "normal",
			"pressing": "medio",
			"width": "normal",
		},
		"finances": {
			"budget_transfers_eur": 18000000,
			"wage_budget_eur_year": 70000000,
			"tv_revenue_eur_year": 60000000,
		},
	},
	{
		"id": "sevilla_fc",
		"name": "Sevilla Fútbol Club",
		"short_name": "SEV",
		"city": "Sevilla",
		"founded": 1890,
		"stadium_name": "Estadio Ramón Sánchez-Pizjuán",
		"stadium_capacity": 43883,
		"primary_color": "#D5172E",
		"secondary_color": "#FFFFFF",
		"division": "primera",
		"reputation": 75,
		"signing_policy": "open",
		"manager_name": "Francisco Javier García Pimienta",
		"manager_nationality": "ES",
		"manager_birth_year": 1974,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": {
			"formation": "4-3-3",
			"mentality": "equilibrado",
			"tempo": "normal",
			"pressing": "medio",
			"width": "normal",
		},
		"finances": {
			"budget_transfers_eur": 20000000,
			"wage_budget_eur_year": 80000000,
			"tv_revenue_eur_year": 65000000,
		},
	},

	# ---- Primera (13 restantes) ----

	{
		"id": "real_madrid",
		"name": "Real Madrid Club de Fútbol",
		"short_name": "RMA",
		"city": "Madrid",
		"founded": 1902,
		"stadium_name": "Estadio Santiago Bernabéu",
		"stadium_capacity": 84744,
		"primary_color": "#FFFFFF",
		"secondary_color": "#FEBE10",
		"division": "primera",
		"reputation": 99,
		"signing_policy": "open",
		"manager_name": "Xabi Alonso",
		"manager_nationality": "ES",
		"manager_birth_year": 1981,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": { "formation": "4-3-3", "mentality": "ofensivo", "tempo": "normal", "pressing": "alto", "width": "normal" },
		"finances": { "budget_transfers_eur": 200000000, "wage_budget_eur_year": 400000000, "tv_revenue_eur_year": 165000000 },
	},
	{
		"id": "valencia_cf",
		"name": "Valencia Club de Fútbol",
		"short_name": "VAL",
		"city": "Valencia",
		"founded": 1919,
		"stadium_name": "Mestalla",
		"stadium_capacity": 49430,
		"primary_color": "#FF6600",
		"secondary_color": "#000000",
		"division": "primera",
		"reputation": 68,
		"signing_policy": "open",
		"manager_name": "Carlos Corberán",
		"manager_nationality": "ES",
		"manager_birth_year": 1983,
		"preferred_formation": "4-2-3-1",
		"preferred_style": "contraataque",
		"tactics_default": { "formation": "4-2-3-1", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 12000000, "wage_budget_eur_year": 55000000, "tv_revenue_eur_year": 55000000 },
	},
	{
		"id": "girona_fc",
		"name": "Girona Fútbol Club",
		"short_name": "GIR",
		"city": "Girona",
		"founded": 1930,
		"stadium_name": "Estadi Montilivi",
		"stadium_capacity": 14624,
		"primary_color": "#CB051A",
		"secondary_color": "#FFFFFF",
		"division": "primera",
		"reputation": 66,
		"signing_policy": "open",
		"manager_name": "Míchel Sánchez",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": { "formation": "4-3-3", "mentality": "equilibrado", "tempo": "rapido", "pressing": "alto", "width": "ancho" },
		"finances": { "budget_transfers_eur": 15000000, "wage_budget_eur_year": 50000000, "tv_revenue_eur_year": 50000000 },
	},
	{
		"id": "ca_osasuna",
		"name": "Club Atlético Osasuna",
		"short_name": "OSA",
		"city": "Pamplona",
		"founded": 1920,
		"stadium_name": "El Sadar",
		"stadium_capacity": 23576,
		"primary_color": "#C30C24",
		"secondary_color": "#001A47",
		"division": "primera",
		"reputation": 62,
		"signing_policy": "open",
		"manager_name": "Vicente Moreno",
		"manager_nationality": "ES",
		"manager_birth_year": 1974,
		"preferred_formation": "4-2-3-1",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-2-3-1", "mentality": "equilibrado", "tempo": "normal", "pressing": "alto", "width": "normal" },
		"finances": { "budget_transfers_eur": 8000000, "wage_budget_eur_year": 40000000, "tv_revenue_eur_year": 45000000 },
	},
	{
		"id": "rayo_vallecano",
		"name": "Rayo Vallecano de Madrid",
		"short_name": "RAY",
		"city": "Madrid",
		"founded": 1924,
		"stadium_name": "Estadio de Vallecas",
		"stadium_capacity": 14708,
		"primary_color": "#FFFFFF",
		"secondary_color": "#ED1C24",
		"division": "primera",
		"reputation": 60,
		"signing_policy": "open",
		"manager_name": "Íñigo Pérez",
		"manager_nationality": "ES",
		"manager_birth_year": 1988,
		"preferred_formation": "4-2-3-1",
		"preferred_style": "posesion",
		"tactics_default": { "formation": "4-2-3-1", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 6000000, "wage_budget_eur_year": 35000000, "tv_revenue_eur_year": 42000000 },
	},
	{
		"id": "celta_vigo",
		"name": "Real Club Celta de Vigo",
		"short_name": "CEL",
		"city": "Vigo",
		"founded": 1923,
		"stadium_name": "Abanca-Balaídos",
		"stadium_capacity": 28200,
		"primary_color": "#87CEEB",
		"secondary_color": "#FFFFFF",
		"division": "primera",
		"reputation": 62,
		"signing_policy": "open",
		"manager_name": "Claudio Giráldez",
		"manager_nationality": "ES",
		"manager_birth_year": 1987,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": { "formation": "4-3-3", "mentality": "ofensivo", "tempo": "rapido", "pressing": "alto", "width": "ancho" },
		"finances": { "budget_transfers_eur": 10000000, "wage_budget_eur_year": 45000000, "tv_revenue_eur_year": 48000000 },
	},
	{
		"id": "rcd_mallorca",
		"name": "Real Club Deportivo Mallorca",
		"short_name": "MLL",
		"city": "Palma",
		"founded": 1916,
		"stadium_name": "Mallorca Son Moix",
		"stadium_capacity": 23142,
		"primary_color": "#BF1530",
		"secondary_color": "#FFD700",
		"division": "primera",
		"reputation": 58,
		"signing_policy": "open",
		"manager_name": "Jagoba Arrasate",
		"manager_nationality": "ES",
		"manager_birth_year": 1978,
		"preferred_formation": "4-4-2",
		"preferred_style": "contraataque",
		"tactics_default": { "formation": "4-4-2", "mentality": "defensivo", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 6000000, "wage_budget_eur_year": 35000000, "tv_revenue_eur_year": 42000000 },
	},
	{
		"id": "getafe_cf",
		"name": "Getafe Club de Fútbol",
		"short_name": "GET",
		"city": "Getafe",
		"founded": 1983,
		"stadium_name": "Coliseum",
		"stadium_capacity": 17393,
		"primary_color": "#003F87",
		"secondary_color": "#FFFFFF",
		"division": "primera",
		"reputation": 58,
		"signing_policy": "open",
		"manager_name": "José Bordalás",
		"manager_nationality": "ES",
		"manager_birth_year": 1964,
		"preferred_formation": "4-4-2",
		"preferred_style": "directo",
		"tactics_default": { "formation": "4-4-2", "mentality": "defensivo", "tempo": "lento", "pressing": "alto", "width": "estrecho" },
		"finances": { "budget_transfers_eur": 5000000, "wage_budget_eur_year": 32000000, "tv_revenue_eur_year": 40000000 },
	},
	{
		"id": "deportivo_alaves",
		"name": "Deportivo Alavés",
		"short_name": "ALA",
		"city": "Vitoria-Gasteiz",
		"founded": 1921,
		"stadium_name": "Mendizorroza",
		"stadium_capacity": 19840,
		"primary_color": "#1F4998",
		"secondary_color": "#FFFFFF",
		"division": "primera",
		"reputation": 56,
		"signing_policy": "open",
		"manager_name": "Eduardo Coudet",
		"manager_nationality": "AR",
		"manager_birth_year": 1974,
		"preferred_formation": "4-4-2",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-4-2", "mentality": "defensivo", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 4500000, "wage_budget_eur_year": 28000000, "tv_revenue_eur_year": 38000000 },
	},
	{
		"id": "rcd_espanyol",
		"name": "Reial Club Deportiu Espanyol",
		"short_name": "ESP",
		"city": "Cornellà de Llobregat",
		"founded": 1900,
		"stadium_name": "RCDE Stadium",
		"stadium_capacity": 40000,
		"primary_color": "#0066CC",
		"secondary_color": "#FFFFFF",
		"division": "primera",
		"reputation": 60,
		"signing_policy": "open",
		"manager_name": "Manolo González",
		"manager_nationality": "ES",
		"manager_birth_year": 1972,
		"preferred_formation": "4-4-2",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-4-2", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 6000000, "wage_budget_eur_year": 38000000, "tv_revenue_eur_year": 42000000 },
	},
	{
		"id": "levante_ud",
		"name": "Levante Unión Deportiva",
		"short_name": "LEV",
		"city": "Valencia",
		"founded": 1909,
		"stadium_name": "Ciutat de València",
		"stadium_capacity": 26354,
		"primary_color": "#003366",
		"secondary_color": "#BB0011",
		"division": "primera",
		"reputation": 55,
		"signing_policy": "open",
		"manager_name": "Julián Calero",
		"manager_nationality": "ES",
		"manager_birth_year": 1971,
		"preferred_formation": "4-2-3-1",
		"preferred_style": "directo",
		"tactics_default": { "formation": "4-2-3-1", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 5000000, "wage_budget_eur_year": 30000000, "tv_revenue_eur_year": 38000000 },
	},
	{
		"id": "elche_cf",
		"name": "Elche Club de Fútbol",
		"short_name": "ELC",
		"city": "Elche",
		"founded": 1923,
		"stadium_name": "Manuel Martínez Valero",
		"stadium_capacity": 31388,
		"primary_color": "#008000",
		"secondary_color": "#FFFFFF",
		"division": "primera",
		"reputation": 53,
		"signing_policy": "open",
		"manager_name": "Eder Sarabia",
		"manager_nationality": "ES",
		"manager_birth_year": 1980,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": { "formation": "4-3-3", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 4000000, "wage_budget_eur_year": 26000000, "tv_revenue_eur_year": 36000000 },
	},
	{
		"id": "real_oviedo",
		"name": "Real Oviedo",
		"short_name": "OVI",
		"city": "Oviedo",
		"founded": 1926,
		"stadium_name": "Carlos Tartiere",
		"stadium_capacity": 30500,
		"primary_color": "#1057A1",
		"secondary_color": "#FFFFFF",
		"division": "primera",
		"reputation": 52,
		"signing_policy": "open",
		"manager_name": "Veljko Paunović",
		"manager_nationality": "RS",
		"manager_birth_year": 1977,
		"preferred_formation": "4-2-3-1",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-2-3-1", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 5000000, "wage_budget_eur_year": 28000000, "tv_revenue_eur_year": 36000000 },
	},

	# ---- Segunda División (22 equipos, mucha incertidumbre — verificar lista 2025-26 real) ----

	{
		"id": "real_valladolid",
		"name": "Real Valladolid Club de Fútbol",
		"short_name": "VLD",
		"city": "Valladolid",
		"founded": 1928,
		"stadium_name": "Estadio José Zorrilla",
		"stadium_capacity": 27846,
		"primary_color": "#5C2D8C",
		"secondary_color": "#FFFFFF",
		"division": "segunda",
		"reputation": 52,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-2-3-1",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-2-3-1", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 4000000, "wage_budget_eur_year": 24000000, "tv_revenue_eur_year": 12000000 },
	},
	{
		"id": "ud_las_palmas",
		"name": "Unión Deportiva Las Palmas",
		"short_name": "LPA",
		"city": "Las Palmas de Gran Canaria",
		"founded": 1949,
		"stadium_name": "Estadio Gran Canaria",
		"stadium_capacity": 32392,
		"primary_color": "#FFCC00",
		"secondary_color": "#0066CC",
		"division": "segunda",
		"reputation": 50,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": { "formation": "4-3-3", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 3500000, "wage_budget_eur_year": 22000000, "tv_revenue_eur_year": 11000000 },
	},
	{
		"id": "cd_leganes",
		"name": "Club Deportivo Leganés",
		"short_name": "LEG",
		"city": "Leganés",
		"founded": 1928,
		"stadium_name": "Estadio Municipal de Butarque",
		"stadium_capacity": 12450,
		"primary_color": "#003F87",
		"secondary_color": "#FFFFFF",
		"division": "segunda",
		"reputation": 48,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-2-3-1",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-2-3-1", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 3000000, "wage_budget_eur_year": 18000000, "tv_revenue_eur_year": 10000000 },
	},
	{
		"id": "real_sporting",
		"name": "Real Sporting de Gijón",
		"short_name": "SPG",
		"city": "Gijón",
		"founded": 1905,
		"stadium_name": "El Molinón-Enrique Castro Quini",
		"stadium_capacity": 30000,
		"primary_color": "#BF1530",
		"secondary_color": "#FFFFFF",
		"division": "segunda",
		"reputation": 50,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-2-3-1",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-2-3-1", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 2500000, "wage_budget_eur_year": 15000000, "tv_revenue_eur_year": 9000000 },
	},
	{
		"id": "real_zaragoza",
		"name": "Real Zaragoza",
		"short_name": "ZAR",
		"city": "Zaragoza",
		"founded": 1932,
		"stadium_name": "La Romareda",
		"stadium_capacity": 33608,
		"primary_color": "#003F87",
		"secondary_color": "#FFFFFF",
		"division": "segunda",
		"reputation": 50,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-2-3-1",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-2-3-1", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 2500000, "wage_budget_eur_year": 15000000, "tv_revenue_eur_year": 9000000 },
	},
	{
		"id": "granada_cf",
		"name": "Granada Club de Fútbol",
		"short_name": "GRA",
		"city": "Granada",
		"founded": 1931,
		"stadium_name": "Nuevo Los Cármenes",
		"stadium_capacity": 19336,
		"primary_color": "#C00000",
		"secondary_color": "#FFFFFF",
		"division": "segunda",
		"reputation": 48,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": { "formation": "4-3-3", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 2500000, "wage_budget_eur_year": 14000000, "tv_revenue_eur_year": 9000000 },
	},
	{
		"id": "ud_almeria",
		"name": "Unión Deportiva Almería",
		"short_name": "ALM",
		"city": "Almería",
		"founded": 1989,
		"stadium_name": "Power Horse Stadium",
		"stadium_capacity": 18000,
		"primary_color": "#C00000",
		"secondary_color": "#FFFFFF",
		"division": "segunda",
		"reputation": 46,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": { "formation": "4-3-3", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 2000000, "wage_budget_eur_year": 13000000, "tv_revenue_eur_year": 8000000 },
	},
	{
		"id": "sd_eibar",
		"name": "Sociedad Deportiva Eibar",
		"short_name": "EIB",
		"city": "Eibar",
		"founded": 1940,
		"stadium_name": "Ipurua",
		"stadium_capacity": 8050,
		"primary_color": "#B30000",
		"secondary_color": "#1F4998",
		"division": "segunda",
		"reputation": 44,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-2-3-1",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-2-3-1", "mentality": "equilibrado", "tempo": "normal", "pressing": "alto", "width": "normal" },
		"finances": { "budget_transfers_eur": 1500000, "wage_budget_eur_year": 10000000, "tv_revenue_eur_year": 7000000 },
	},
	{
		"id": "burgos_cf",
		"name": "Burgos Club de Fútbol",
		"short_name": "BUR",
		"city": "Burgos",
		"founded": 1994,
		"stadium_name": "El Plantío",
		"stadium_capacity": 12643,
		"primary_color": "#FFFFFF",
		"secondary_color": "#000000",
		"division": "segunda",
		"reputation": 42,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-4-2",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-4-2", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 1200000, "wage_budget_eur_year": 8000000, "tv_revenue_eur_year": 6000000 },
	},
	{
		"id": "fc_cartagena",
		"name": "Fútbol Club Cartagena",
		"short_name": "CAR",
		"city": "Cartagena",
		"founded": 1995,
		"stadium_name": "Estadio Cartagonova",
		"stadium_capacity": 15105,
		"primary_color": "#000000",
		"secondary_color": "#FFD700",
		"division": "segunda",
		"reputation": 40,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-4-2",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-4-2", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 1000000, "wage_budget_eur_year": 7000000, "tv_revenue_eur_year": 6000000 },
	},
	{
		"id": "cadiz_cf",
		"name": "Cádiz Club de Fútbol",
		"short_name": "CAD",
		"city": "Cádiz",
		"founded": 1910,
		"stadium_name": "Nuevo Mirandilla",
		"stadium_capacity": 20724,
		"primary_color": "#FFD700",
		"secondary_color": "#003F87",
		"division": "segunda",
		"reputation": 46,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-4-2",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-4-2", "mentality": "defensivo", "tempo": "lento", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 2000000, "wage_budget_eur_year": 13000000, "tv_revenue_eur_year": 8000000 },
	},
	{
		"id": "cd_tenerife",
		"name": "Club Deportivo Tenerife",
		"short_name": "TEN",
		"city": "Santa Cruz de Tenerife",
		"founded": 1922,
		"stadium_name": "Heliodoro Rodríguez López",
		"stadium_capacity": 22824,
		"primary_color": "#003366",
		"secondary_color": "#FFFFFF",
		"division": "segunda",
		"reputation": 42,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-2-3-1",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-2-3-1", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 1500000, "wage_budget_eur_year": 10000000, "tv_revenue_eur_year": 7000000 },
	},
	{
		"id": "albacete_balompie",
		"name": "Albacete Balompié",
		"short_name": "ALB",
		"city": "Albacete",
		"founded": 1940,
		"stadium_name": "Carlos Belmonte",
		"stadium_capacity": 17524,
		"primary_color": "#FFFFFF",
		"secondary_color": "#000000",
		"division": "segunda",
		"reputation": 38,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-4-2",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-4-2", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 900000, "wage_budget_eur_year": 6500000, "tv_revenue_eur_year": 5500000 },
	},
	{
		"id": "cd_mirandes",
		"name": "Club Deportivo Mirandés",
		"short_name": "MIR",
		"city": "Miranda de Ebro",
		"founded": 1927,
		"stadium_name": "Anduva",
		"stadium_capacity": 5759,
		"primary_color": "#C00000",
		"secondary_color": "#000000",
		"division": "segunda",
		"reputation": 36,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": { "formation": "4-3-3", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 700000, "wage_budget_eur_year": 5000000, "tv_revenue_eur_year": 5000000 },
	},
	{
		"id": "cd_castellon",
		"name": "Club Deportivo Castellón",
		"short_name": "CAS",
		"city": "Castellón de la Plana",
		"founded": 1922,
		"stadium_name": "Castalia",
		"stadium_capacity": 15500,
		"primary_color": "#F1A40C",
		"secondary_color": "#000000",
		"division": "segunda",
		"reputation": 38,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": { "formation": "4-3-3", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 800000, "wage_budget_eur_year": 5500000, "tv_revenue_eur_year": 5000000 },
	},
	{
		"id": "cd_eldense",
		"name": "Club Deportivo Eldense",
		"short_name": "ELD",
		"city": "Elda",
		"founded": 1921,
		"stadium_name": "Pepico Amat",
		"stadium_capacity": 4036,
		"primary_color": "#003366",
		"secondary_color": "#FFD700",
		"division": "segunda",
		"reputation": 36,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-2-3-1",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-2-3-1", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 600000, "wage_budget_eur_year": 4500000, "tv_revenue_eur_year": 4500000 },
	},
	{
		"id": "malaga_cf",
		"name": "Málaga Club de Fútbol",
		"short_name": "MAL",
		"city": "Málaga",
		"founded": 1948,
		"stadium_name": "La Rosaleda",
		"stadium_capacity": 30044,
		"primary_color": "#003366",
		"secondary_color": "#87CEEB",
		"division": "segunda",
		"reputation": 46,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": { "formation": "4-3-3", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 1500000, "wage_budget_eur_year": 11000000, "tv_revenue_eur_year": 7000000 },
	},
	{
		"id": "sd_huesca",
		"name": "Sociedad Deportiva Huesca",
		"short_name": "HUE",
		"city": "Huesca",
		"founded": 1960,
		"stadium_name": "El Alcoraz",
		"stadium_capacity": 9099,
		"primary_color": "#003F87",
		"secondary_color": "#BF1530",
		"division": "segunda",
		"reputation": 42,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-2-3-1",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-2-3-1", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 1200000, "wage_budget_eur_year": 8500000, "tv_revenue_eur_year": 6500000 },
	},
	{
		"id": "cordoba_cf",
		"name": "Córdoba Club de Fútbol",
		"short_name": "COR",
		"city": "Córdoba",
		"founded": 1954,
		"stadium_name": "Nuevo Arcángel",
		"stadium_capacity": 21822,
		"primary_color": "#008000",
		"secondary_color": "#FFFFFF",
		"division": "segunda",
		"reputation": 38,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": { "formation": "4-3-3", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 800000, "wage_budget_eur_year": 6000000, "tv_revenue_eur_year": 5000000 },
	},
	{
		"id": "racing_santander",
		"name": "Real Racing Club de Santander",
		"short_name": "RAC",
		"city": "Santander",
		"founded": 1913,
		"stadium_name": "El Sardinero",
		"stadium_capacity": 22271,
		"primary_color": "#FFFFFF",
		"secondary_color": "#000000",
		"division": "segunda",
		"reputation": 44,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": { "formation": "4-3-3", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 1300000, "wage_budget_eur_year": 9500000, "tv_revenue_eur_year": 6500000 },
	},
	{
		"id": "ad_ceuta",
		"name": "Asociación Deportiva Ceuta FC",
		"short_name": "CEU",
		"city": "Ceuta",
		"founded": 1956,
		"stadium_name": "Alfonso Murube",
		"stadium_capacity": 6500,
		"primary_color": "#FFFFFF",
		"secondary_color": "#000000",
		"division": "segunda",
		"reputation": 32,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-4-2",
		"preferred_style": "equilibrado",
		"tactics_default": { "formation": "4-4-2", "mentality": "defensivo", "tempo": "lento", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 400000, "wage_budget_eur_year": 3500000, "tv_revenue_eur_year": 4000000 },
	},
	{
		"id": "fc_andorra",
		"name": "Fútbol Club Andorra",
		"short_name": "AND",
		"city": "Andorra la Vella",
		"founded": 1942,
		"stadium_name": "Estadi Nacional",
		"stadium_capacity": 3306,
		"primary_color": "#FFFF00",
		"secondary_color": "#BF1530",
		"division": "segunda",
		"reputation": 34,
		"signing_policy": "open",
		"manager_name": "Por confirmar",
		"manager_nationality": "ES",
		"manager_birth_year": 1975,
		"preferred_formation": "4-3-3",
		"preferred_style": "posesion",
		"tactics_default": { "formation": "4-3-3", "mentality": "equilibrado", "tempo": "normal", "pressing": "medio", "width": "normal" },
		"finances": { "budget_transfers_eur": 500000, "wage_budget_eur_year": 4000000, "tv_revenue_eur_year": 4000000 },
	},
]


# ============================================================================
# Entrada
# ============================================================================
const SEED_BASE: int = 0xCAFE  # cualquier número estable; cambia para ver varianza distinta

func _init() -> void:
	print("=" .repeat(70))
	print("Generador de plantillas-esqueleto")
	print("=" .repeat(70))
	for spec in TEAM_SPECS:
		_generate_one(spec)
	print("\nHecho. Revisa los archivos generados, reemplaza nombres placeholder")
	print("por los reales y ajusta tiers cuando convenga.")
	quit(0)


func _generate_one(spec: Dictionary) -> void:
	var team_id: String = String(spec["id"])
	var division: String = String(spec["division"])
	var path: String = "res://data/teams/%s/%s.json" % [division, team_id]
	if FileAccess.file_exists(path):
		print("⏭  %s ya existe, lo respeto." % path)
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_BASE ^ hash(team_id)

	var team_dict: Dictionary = _build_team_dict(spec, rng)
	var json_str: String = JSON.stringify(team_dict, "  ")

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("No se pudo escribir %s" % path)
		return
	file.store_string(json_str)
	file.close()
	print("✓ %s (%d jugadores placeholder)" % [path, team_dict["players"].size()])


func _build_team_dict(spec: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var short: String = String(spec["short_name"])
	var rep: int = int(spec["reputation"])

	var players: Array = []
	for i in SLOTS.size():
		var slot: Array = SLOTS[i]
		var pos: String = slot[0]
		var role: String = slot[1]
		var bands: Array = tier_band(rep, role, rng)
		var tier: String = bands[0]
		var pot_tier: String = bands[1]
		var age: int = age_for_role(role, rng)
		var birth_year: int = 2026 - age
		var birth_month: int = rng.randi_range(1, 12)
		var birth_day: int = rng.randi_range(1, 28)
		var foot: String = "L" if rng.randf() < 0.30 else "R"

		var pid: String = "%s_p%03d" % [short.to_lower(), i + 1]
		var pname: String = "%s Player %d" % [short, i + 1]

		var contract: Dictionary = {
			"until_year": 2026 + rng.randi_range(2, 5),
			"salary_eur_year": salary_eur(tier, rep, rng),
			"release_clause_eur": clause_eur(tier, rep),
		}

		players.append({
			"id": pid,
			"name": pname,
			"birth_date": { "year": birth_year, "month": birth_month, "day": birth_day },
			"nationality": "ES",
			"positions": [pos],
			"preferred_foot": foot,
			"tier": tier,
			"potential_tier": pot_tier,
			"shirt_number": shirt_for_slot(i, pos),
			"captain": false,
			"traits": [],
			"overrides": {},
			"joined_year": 2026 - rng.randi_range(0, 6),
			"contract": contract,
		})

	return {
		"_draft_note": "ESQUELETO generado automáticamente. Reemplazar nombres placeholder por reales y ajustar tiers/dorsales.",
		"id": spec["id"],
		"name": spec["name"],
		"short_name": spec["short_name"],
		"city": spec["city"],
		"founded": spec["founded"],
		"stadium": {
			"name": spec["stadium_name"],
			"capacity": spec["stadium_capacity"],
		},
		"colors": {
			"primary": spec["primary_color"],
			"secondary": spec["secondary_color"],
		},
		"division": spec["division"],
		"reputation": spec["reputation"],
		"signing_policy": spec["signing_policy"],
		"manager": {
			"name": spec["manager_name"],
			"nationality": spec["manager_nationality"],
			"birth_year": spec["manager_birth_year"],
			"preferred_formation": spec["preferred_formation"],
			"preferred_style": spec["preferred_style"],
		},
		"tactics_default": spec["tactics_default"],
		"finances": spec["finances"],
		"players": players,
	}
