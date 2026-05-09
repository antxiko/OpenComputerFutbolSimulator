class_name ClubFinances extends RefCounted

# Sistema de finanzas del club por temporada.
# Calcula ingresos (matchday + TV + sponsors + premios) y gastos (salarios +
# mantenimiento estadio + personal técnico) y los aplica al cash_balance.
#
# Llamado desde game_hub._on_reset_season tras cerrarse la temporada.


# Premios por competición (en euros). Valores realistas reducidos para mantener
# escala con presupuestos del simulador.
const PRIZE_LIGA := [
	50_000_000,  # 1º
	30_000_000,  # 2º
	22_000_000,  # 3º
	18_000_000,  # 4º
	14_000_000,  # 5º
	11_000_000,  # 6º
	9_000_000,   # 7º
	7_500_000,   # 8º
	6_500_000,   # 9º
	5_500_000,   # 10º
	5_000_000,   # 11º
	4_500_000,   # 12º
	4_000_000,   # 13º
	3_500_000,   # 14º
	3_000_000,   # 15º
	2_500_000,   # 16º
	2_000_000,   # 17º
	1_000_000,   # 18º (descenso)
	1_000_000,   # 19º (descenso)
	1_000_000,   # 20º (descenso)
]

const PRIZE_SEGUNDA := [
	18_000_000, 14_000_000, 10_000_000, 8_000_000, 6_000_000, 5_000_000,
	4_000_000, 3_500_000, 3_000_000, 2_500_000, 2_000_000, 1_800_000,
	1_500_000, 1_300_000, 1_000_000, 900_000, 800_000, 700_000,
	600_000, 500_000, 500_000, 500_000,
]

const PRIZE_COPA_CHAMPION := 8_000_000
const PRIZE_COPA_FINALIST := 4_000_000
const PRIZE_COPA_SEMIS := 2_000_000

# Champions League: base + bonus por avanzar
const PRIZE_CHL_BASE := 15_000_000
const PRIZE_CHL_GROUP_PASS := 5_000_000
const PRIZE_CHL_QUARTERS := 8_000_000
const PRIZE_CHL_SEMIS := 12_000_000
const PRIZE_CHL_FINALIST := 16_000_000
const PRIZE_CHL_CHAMPION := 25_000_000

# Europa League (50% de Champions). Conference (25% de Champions).
const EUROPA_FACTOR := 0.50
const CONFERENCE_FACTOR := 0.25


# Inicializa cash_balance al cargar por primera vez (si está a 0).
# Heurística: cash inicial = budget_transfers × 0.6 (efectivo disponible
# tras cierre de mercado verano hipotético).
static func ensure_initialized(team: Team) -> void:
	if team.finances == null:
		return
	if team.finances.cash_balance <= 0:
		team.finances.cash_balance = int(float(team.finances.budget_transfers_eur) * 0.6)
		# Mínimo 5M para no quedarse sin caja
		if team.finances.cash_balance < 5_000_000:
			team.finances.cash_balance = 5_000_000


# Calcula matchday revenue de la temporada para un equipo.
# 19 partidos liga en casa + 1-3 copa + 0-3 europa (estimación)
static func compute_matchday_revenue(team: Team, league_position: int, won_titles: int) -> int:
	if team.stadium == null or team.finances == null:
		return 0
	var price: int = team.stadium.base_ticket_price()
	# Occupancy según rendimiento + estado del estadio
	# Base 60% + bonus por buena posición + bonus por estado del estadio
	var occupancy: float = 0.55
	if league_position <= 4: occupancy += 0.30
	elif league_position <= 8: occupancy += 0.18
	elif league_position <= 12: occupancy += 0.10
	elif league_position >= 18: occupancy -= 0.05
	occupancy += float(team.stadium.state) / 1000.0  # +0.08 si state=80
	occupancy = clampf(occupancy, 0.40, 0.98)

	var per_match: int = int(float(team.stadium.capacity) * occupancy * float(price))
	# 19 partidos liga + 2 copa + estimación europea
	var n_home_matches: int = 19 + 2 + (3 if league_position <= 4 else 0)
	return per_match * n_home_matches


static func compute_sponsor_revenue(team: Team, current_year: int) -> int:
	if team.finances == null or team.finances.sponsors.is_empty():
		return 0
	var total: int = 0
	for s in team.finances.sponsors:
		if int(s.get("until_year", 0)) >= current_year:
			total += int(s.get("amount_per_year", 0))
	return total


# Genera patrocinadores iniciales para un equipo según reputación si no tiene.
static func ensure_initial_sponsors(team: Team, current_year: int) -> void:
	if team.finances == null:
		return
	if team.finances.sponsors.size() > 0:
		return
	var rep: int = team.reputation
	# Patrocinador kit_main (siempre)
	team.finances.sponsors.append({
		"type": "kit_main",
		"sponsor_name": _sponsor_name_for_tier(rep),
		"amount_per_year": _sponsor_amount("kit_main", rep),
		"until_year": current_year + 3,
	})
	# Manga (clubes con rep ≥70)
	if rep >= 70:
		team.finances.sponsors.append({
			"type": "kit_sleeve",
			"sponsor_name": _sponsor_name_for_tier(rep - 5),
			"amount_per_year": _sponsor_amount("kit_sleeve", rep),
			"until_year": current_year + 2,
		})
	# Training (clubes con rep ≥60)
	if rep >= 60:
		team.finances.sponsors.append({
			"type": "training",
			"sponsor_name": _sponsor_name_for_tier(rep - 10),
			"amount_per_year": _sponsor_amount("training", rep),
			"until_year": current_year + 2,
		})


static func _sponsor_amount(type: String, rep: int) -> int:
	var base_factor: float = float(rep - 50) / 50.0  # rep 100 → 1.0, rep 50 → 0.0
	base_factor = clampf(base_factor, 0.1, 1.0)
	var base: int
	match type:
		"kit_main":   base = 30_000_000
		"kit_sleeve": base = 8_000_000
		"training":   base = 5_000_000
		"naming":     base = 12_000_000
		_:            base = 3_000_000
	return int(float(base) * base_factor)


const SPONSORS_TOP := ["Emirates", "Qatar Airways", "Spotify", "Rakuten", "Etihad", "Standard Chartered"]
const SPONSORS_MID := ["Vodafone", "Banco Santander", "Endesa", "BBVA", "Repsol", "Movistar"]
const SPONSORS_LOW := ["Ferrovial", "Indra", "Mahou", "Cabify", "Mediaset", "Caixabank"]
static func _sponsor_name_for_tier(rep: int) -> String:
	if rep >= 85:
		return SPONSORS_TOP[hash("top" + str(rep)) % SPONSORS_TOP.size()]
	elif rep >= 70:
		return SPONSORS_MID[hash("mid" + str(rep)) % SPONSORS_MID.size()]
	else:
		return SPONSORS_LOW[hash("low" + str(rep)) % SPONSORS_LOW.size()]


# Salarios totales del equipo
static func compute_total_salaries(team: Team) -> int:
	var total: int = 0
	for p: Player in team.players:
		if p.contract != null:
			total += p.contract.salary_eur_year
	return total


# Mantenimiento del estadio: capacity × 30€ × factor por estado
static func compute_stadium_maintenance(team: Team) -> int:
	if team.stadium == null:
		return 0
	# Mantener un estadio en mal estado cuesta más (debe rehabilitarse)
	var factor: float = 1.0 + (100.0 - team.stadium.state) / 100.0
	return int(float(team.stadium.capacity) * 30.0 * factor)


# Personal técnico: aprox 5M para clubes top, 1-2M para pequeños
static func compute_staff_cost(team: Team) -> int:
	return 1_000_000 + int(float(team.reputation) * 50_000.0)


# Premio según posición en Liga
static func prize_for_league_position(division: String, position: int) -> int:
	var arr: Array
	if division == "primera": arr = PRIZE_LIGA
	else: arr = PRIZE_SEGUNDA
	if position < 1 or position > arr.size():
		return 0
	return int(arr[position - 1])


# Premio Champions / Europa / Conference según el bracket y team
static func prize_from_european_bracket(bracket: ChampionsBracket, team_id: String, comp_factor: float = 1.0) -> int:
	if bracket == null:
		return 0
	var prize: int = int(PRIZE_CHL_BASE * comp_factor)
	if bracket.champion_id == team_id:
		prize += int(PRIZE_CHL_CHAMPION * comp_factor)
		return prize
	# Buscar en qué ronda fue eliminado
	var furthest_idx: int = -1
	for r_idx in bracket.ko_rounds.size():
		var r: ChampionsBracket.KORound = bracket.ko_rounds[r_idx]
		for fx: ChampionsBracket.KOFixture in r.fixtures:
			if fx.home_id == team_id or fx.away_id == team_id:
				furthest_idx = r_idx
				if fx.winner_id == team_id:
					pass  # avanzó
				else:
					# Se quedó aquí
					if r.name == "Final":
						prize += int(PRIZE_CHL_FINALIST * comp_factor)
					elif r.name == "Semifinales":
						prize += int(PRIZE_CHL_SEMIS * comp_factor)
					elif r.name == "Cuartos":
						prize += int(PRIZE_CHL_QUARTERS * comp_factor)
					elif r.name == "Octavos":
						prize += int(PRIZE_CHL_GROUP_PASS * comp_factor)
					return prize
	# Si no aparece en KO rounds, jugó solo grupos (Champions). Ya tiene PRIZE_CHL_BASE.
	# Si pasó de grupos pero solo aparece como winner una vez, sumar group pass
	if furthest_idx >= 0:
		prize += int(PRIZE_CHL_GROUP_PASS * comp_factor)
	return prize


# Cierra la temporada: calcula ingresos/gastos y los aplica al cash_balance.
# Devuelve el summary que se guardará en finances.last_season_summary.
static func close_season(
	team: Team,
	current_year: int,
	division: String,
	league_position: int,
	cup_status: String,        # "champion"/"finalist"/"semis"/""
	champions_bracket: ChampionsBracket,
	europa_bracket: ChampionsBracket,
	conference_bracket: ChampionsBracket,
	transfers_in_eur: int,
	transfers_out_eur: int
) -> Dictionary:
	if team.finances == null:
		return {}

	# === Ingresos ===
	var matchday: int = compute_matchday_revenue(team, league_position, 0)
	var tv: int = team.finances.tv_revenue_eur_year
	var sponsors_rev: int = compute_sponsor_revenue(team, current_year)
	var prizes: int = 0
	var prize_breakdown: Dictionary = {}
	var liga_prize: int = prize_for_league_position(division, league_position)
	prizes += liga_prize
	prize_breakdown["liga"] = liga_prize
	var copa_prize: int = 0
	match cup_status:
		"champion": copa_prize = PRIZE_COPA_CHAMPION
		"finalist": copa_prize = PRIZE_COPA_FINALIST
		"semis":    copa_prize = PRIZE_COPA_SEMIS
	prizes += copa_prize
	prize_breakdown["copa"] = copa_prize
	var chl_prize: int = prize_from_european_bracket(champions_bracket, team.id, 1.0)
	prizes += chl_prize
	prize_breakdown["champions"] = chl_prize
	var el_prize: int = prize_from_european_bracket(europa_bracket, team.id, EUROPA_FACTOR)
	prizes += el_prize
	prize_breakdown["europa"] = el_prize
	var cf_prize: int = prize_from_european_bracket(conference_bracket, team.id, CONFERENCE_FACTOR)
	prizes += cf_prize
	prize_breakdown["conference"] = cf_prize

	var total_income: int = matchday + tv + sponsors_rev + prizes + transfers_in_eur

	# === Gastos ===
	var salaries: int = compute_total_salaries(team)
	var stadium: int = compute_stadium_maintenance(team)
	var staff: int = compute_staff_cost(team)
	var transfers_out: int = transfers_out_eur
	var total_expense: int = salaries + stadium + staff + transfers_out

	# === Aplicar al balance ===
	var net: int = total_income - total_expense
	team.finances.cash_balance += net

	# === Estadio: degradación si no se mantiene ===
	if team.stadium != null:
		# Se reduce 5 puntos cada año, sube si se hace mejora
		team.stadium.state = clampf(team.stadium.state - 5.0, 10.0, 100.0)

	# === Guardar summary ===
	var summary: Dictionary = {
		"year": current_year,
		"division": division,
		"league_position": league_position,
		"income": {
			"matchday": matchday,
			"tv": tv,
			"sponsors": sponsors_rev,
			"prizes": prizes,
			"prize_breakdown": prize_breakdown,
			"transfers_in": transfers_in_eur,
			"total": total_income,
		},
		"expense": {
			"salaries": salaries,
			"stadium_maintenance": stadium,
			"staff": staff,
			"transfers_out": transfers_out,
			"total": total_expense,
		},
		"net": net,
		"cash_balance_after": team.finances.cash_balance,
	}
	team.finances.last_season_summary = summary
	return summary


# Avanza proyectos en curso (los que terminan este año aplican efecto)
static func tick_projects(team: Team, current_year: int) -> Array:
	var completed: Array = []
	if team.finances == null or team.finances.ongoing_projects.is_empty():
		return completed
	var still_active: Array = []
	for proj in team.finances.ongoing_projects:
		if int(proj.get("completes_year", 0)) <= current_year:
			# Aplicar efecto
			_apply_project_effect(team, proj)
			completed.append(proj)
		else:
			still_active.append(proj)
	team.finances.ongoing_projects = still_active
	return completed


static func _apply_project_effect(team: Team, project: Dictionary) -> void:
	var t: String = String(project.get("type", ""))
	if team.stadium == null:
		return
	match t:
		"stadium_expansion":
			var add: int = int(project.get("capacity_add", 5000))
			team.stadium.capacity += add
		"stadium_tier_up":
			team.stadium.tier = mini(5, team.stadium.tier + 1)
			team.stadium.state = 100.0
		"upgrade_pitch":
			if not "cesped_hibrido" in team.stadium.upgrades:
				team.stadium.upgrades.append("cesped_hibrido")
			team.stadium.state = 100.0
		"upgrade_vip":
			if not "palcos_vip" in team.stadium.upgrades:
				team.stadium.upgrades.append("palcos_vip")
		"upgrade_museum":
			if not "museo" in team.stadium.upgrades:
				team.stadium.upgrades.append("museo")
