class_name ContractNegotiation extends RefCounted

# Lógica de negociación manual de renovación de contrato.
# El usuario propone (salario_anual, años) y el jugador acepta, rechaza o
# contraoferta según una función de "satisfacción" basada en:
#   - Ratio salario_ofrecido / salario_justo (MarketValue / 6)
#   - Años ofrecidos vs rango aceptable según edad
#   - Tier del jugador (estrellas piden más sobre el justo)


# Salario "justo" anual en €. Reutiliza la heurística del market (MV/6).
static func fair_salary(player: Player, season_year: int, slot: String = "") -> int:
	var s: String = slot if slot != "" else player.primary_position()
	if s == "":
		s = "MID"
	var mv: int = MarketValue.compute(player, season_year, s)
	return maxi(150_000, int(mv / 6))


# Multiplicador del salario justo según el tier del jugador.
# Las estrellas piden por encima del justo.
static func _tier_demand_multiplier(tier: String) -> float:
	match tier:
		"S": return 1.25
		"A": return 1.10
		"B": return 1.00
		_: return 0.95


# Rango aceptable de años según la edad. Veteranos no firman contratos largos.
static func acceptable_years(player: Player, season_year: int) -> Array:
	var age: int = player.age_at(season_year, 7, 1)
	if age <= 24:
		return [2, 5]
	elif age <= 30:
		return [2, 4]
	elif age <= 33:
		return [1, 3]
	else:
		return [1, 2]


# Evalúa una oferta del usuario. Devuelve un Dictionary:
#   {
#     "accepted": bool,
#     "message": String,        # texto que se muestra al usuario
#     "counter_salary": int,    # propuesta de contraoferta (0 si no aplica)
#     "counter_years": int,     # propuesta de contraoferta (0 si no aplica)
#   }
static func evaluate_offer(player: Player, season_year: int, salary_offer: int, years_offer: int) -> Dictionary:
	var fair: int = fair_salary(player, season_year)
	var demand: float = _tier_demand_multiplier(player.tier)
	var target: int = int(float(fair) * demand)

	var ratio: float = float(salary_offer) / float(maxi(1, target))
	var year_range: Array = acceptable_years(player, season_year)
	var min_years: int = year_range[0]
	var max_years: int = year_range[1]

	# Caso 1: años fuera de rango → contraoferta de años (al borde aceptable)
	if years_offer < min_years or years_offer > max_years:
		var fixed_years: int = clampi(years_offer, min_years, max_years)
		# Si además el salario también es bajo, sube target
		var counter_salary: int = maxi(salary_offer, target)
		return {
			"accepted": false,
			"message": "%s prefiere un contrato de %d años en vez de %d." % [player.name, fixed_years, years_offer],
			"counter_salary": counter_salary,
			"counter_years": fixed_years,
		}

	# Caso 2: salario insuficiente
	if ratio < 0.80:
		return {
			"accepted": false,
			"message": "%s rechaza la oferta. Pide al menos %s€/año." % [player.name, _format_eur(target)],
			"counter_salary": target,
			"counter_years": years_offer,
		}

	# Caso 3: salario aceptable pero por debajo del target → contraoferta
	if ratio < 1.0:
		# Probabilidad de aceptar igual: jugadores jóvenes y de bajo tier son más flexibles
		var age: int = player.age_at(season_year, 7, 1)
		var accept_prob: float = 0.40
		if player.tier == "S": accept_prob -= 0.20
		elif player.tier == "C": accept_prob += 0.15
		if age >= 33: accept_prob += 0.20  # veterano agradece la oferta
		accept_prob = clampf(accept_prob, 0.05, 0.95)

		if randf() < accept_prob:
			return {
				"accepted": true,
				"message": "%s acepta la renovación: %d años, %s€/año." % [player.name, years_offer, _format_eur(salary_offer)],
				"counter_salary": 0,
				"counter_years": 0,
			}
		return {
			"accepted": false,
			"message": "%s pide algo más: %s€/año." % [player.name, _format_eur(target)],
			"counter_salary": target,
			"counter_years": years_offer,
		}

	# Caso 4: salario aceptable o por encima → casi siempre acepta
	return {
		"accepted": true,
		"message": "%s acepta la renovación: %d años, %s€/año." % [player.name, years_offer, _format_eur(salary_offer)],
		"counter_salary": 0,
		"counter_years": 0,
	}


# Aplica una oferta aceptada al contrato del jugador.
static func apply_renewal(player: Player, season_year: int, salary: int, years: int) -> void:
	if player.contract == null:
		player.contract = ContractInfo.new()
	player.contract.until_year = season_year + years
	player.contract.salary_eur_year = salary
	# Cláusula de rescisión = ~2.5x salario anual o el valor actual, lo que sea mayor
	var mv: int = MarketValue.compute(player, season_year, player.primary_position())
	player.contract.release_clause_eur = maxi(int(salary * 2.5), int(mv * 2))


# Lista jugadores del equipo cuyo contrato vence al final de la temporada actual
# o ya está vencido. Estos son los candidatos a renovación manual.
static func players_to_negotiate(team: Team, season_year: int) -> Array:
	var result: Array = []
	for p: Player in team.players:
		if p.contract == null:
			continue
		# Vence este año o ya venció
		if p.contract.until_year <= season_year:
			result.append(p)
	return result


static func _format_eur(amount: int) -> String:
	if amount >= 1_000_000:
		return "%.1fM" % (float(amount) / 1_000_000.0)
	if amount >= 1_000:
		return "%dK" % (amount / 1_000)
	return str(amount)
