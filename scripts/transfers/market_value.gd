class_name MarketValue extends RefCounted

# Cálculo de valor de mercado de un jugador en euros.
# Combina overall, edad, años de contrato restantes, potencial y tier.
# Calibrado para que los rangos coincidan aproximadamente con el mercado real:
#   overall 95 → 130-200M (Mbappé tier)
#   overall 85 → 35-55M
#   overall 75 → 8-15M
#   overall 65 → 2-4M
#   overall 55 → ~500k


# Curva base por overall — interpolación lineal entre puntos clave.
const BASE_VALUES: Dictionary = {
	99: 200_000_000,
	95: 140_000_000,
	90: 75_000_000,
	85: 35_000_000,
	80: 18_000_000,
	75: 9_000_000,
	70: 4_000_000,
	65: 2_000_000,
	60: 1_000_000,
	55: 500_000,
	50: 250_000,
	45: 100_000,
	40: 50_000,
}


static func compute(player: Player, current_year: int, slot: String = "") -> int:
	var ovr: int = PlayerFactory.compute_overall(player, slot if slot != "" else player.primary_position())
	var base: float = _interpolate_base(ovr)

	# Edad: cae en >30, jóvenes valen más
	var age: int = player.age_at(current_year, 7, 1)
	var age_factor: float = _age_factor(age)

	# Contrato: a 0 años (Bosman) vale poco; a 4+ años vale más
	var years_left: int = 0
	if player.contract != null:
		years_left = maxi(0, player.contract.until_year - current_year)
	var contract_factor: float = _contract_factor(years_left)

	# Potencial: si potential >> overall, el jugador es proyecto y vale más
	var potential_gap: int = player.potential - ovr
	var potential_factor: float = _potential_factor(potential_gap, age)

	var raw: float = base * age_factor * contract_factor * potential_factor
	return roundi(raw)


static func _interpolate_base(overall: int) -> float:
	if overall >= 99:
		return float(BASE_VALUES[99])
	if overall <= 40:
		return float(BASE_VALUES[40])
	# Encuentra los dos puntos de la tabla que rodean a overall y se interpolan log-linealmente
	var keys: Array = BASE_VALUES.keys()
	keys.sort()  # ascendente
	var lower: int = 40
	var upper: int = 99
	for k: int in keys:
		if k <= overall:
			lower = k
		if k >= overall and upper == 99 and k != 99:
			upper = k
	# Encontrar el siguiente keypoint por encima
	for k: int in keys:
		if k > overall:
			upper = k
			break
	if upper == lower:
		return float(BASE_VALUES[lower])
	var v_low: float = float(BASE_VALUES[lower])
	var v_high: float = float(BASE_VALUES[upper])
	# Interpolación lineal en log-space (para que la curva sea exponencial)
	var t: float = float(overall - lower) / float(upper - lower)
	var log_low: float = log(v_low)
	var log_high: float = log(v_high)
	return exp(log_low + t * (log_high - log_low))


static func _age_factor(age: int) -> float:
	if age <= 18:
		return 1.30
	elif age <= 21:
		return 1.20
	elif age <= 24:
		return 1.10
	elif age <= 28:
		return 1.00
	elif age <= 30:
		return 0.90
	elif age <= 32:
		return 0.65
	elif age <= 34:
		return 0.40
	elif age <= 36:
		return 0.20
	else:
		return 0.10


static func _contract_factor(years_left: int) -> float:
	match years_left:
		0: return 0.30  # Bosman: gratis al final de temporada
		1: return 0.55
		2: return 0.85
		3: return 1.00
		4: return 1.05
		_: return 1.10  # 5+ años


static func _potential_factor(gap: int, age: int) -> float:
	# Solo aplica bonus a jugadores jóvenes con potencial sin descubrir
	if age > 25 or gap <= 0:
		return 1.0
	if gap <= 5:
		return 1.05 + float(gap) * 0.02
	# gap 6-15: bonus fuerte
	return clampf(1.15 + float(gap) * 0.03, 1.0, 1.6)
