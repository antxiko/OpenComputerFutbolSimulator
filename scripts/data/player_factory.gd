class_name PlayerFactory extends RefCounted

# Traduce (tier + posición + edad + overrides) → 8 atributos concretos.
#
# Atributos B2: ataque, defensa, pase, tiro, fisico, porteria, mentalidad, velocidad.
# El generador es DETERMINISTA dado un seed: re-generar el mismo jugador con el mismo
# seed da exactamente los mismos atributos. Esto es crítico para reproducibilidad.

const ATTRIBUTE_NAMES: Array[String] = [
	"ataque", "defensa", "pase", "tiro", "fisico", "porteria", "mentalidad", "velocidad"
]

# Rango base [min, max] del overall numérico según tier.
# Calibrado para que jugadores S de élite alcancen 90-95 en su atributo principal,
# y para que los atributos no-especialidad estén en el rango realista (40-70).
const TIER_BASE := {
	"S": [78, 83],
	"A": [72, 77],
	"B": [66, 71],
	"C": [60, 65],
	"D": [53, 60],
	"Y": [48, 58],
}

# Modificadores posicionales por atributo (se suman al base).
# Orden: [ataque, defensa, pase, tiro, fisico, porteria, mentalidad, velocidad]
#
# Diseño:
# - Atributo principal de la posición:    +10 a +14
# - Atributos secundarios:                 +3 a +6
# - Atributos no relevantes:               -5 a -15
# - "Anti-especialidad" (defensa en ST):   -15 a -25
# - Porteros: -50 a porteria para outfielders; outfielders: porteria muy baja
const POSITION_MODIFIERS := {
	"GK":  [-50, -30, -20, -50, -10, +12, -10, -30],
	"CB":  [-25, +12,  -3, -25,  +6, -50,  +5, -10],
	"LB":  [-12,  +6,   0, -12,   0, -50,   0,  +6],
	"RB":  [-12,  +6,   0, -12,   0, -50,   0,  +6],
	"LWB":  [-8,  +5,   0, -12,   0, -50,   0,  +8],
	"RWB":  [-8,  +5,   0, -12,   0, -50,   0,  +8],
	"CDM": [-10,  +8,  +6,  -8,  +5, -50,  +5,   0],
	"CM":   [-3,   0,  +8,   0,   0, -50,  +4,   0],
	"CAM":  [+8, -10,  +8,  +5,  -5, -50,  +5,   0],
	"LM":   [+5,   0,  +5,   0,   0, -50,   0,  +5],
	"RM":   [+5,   0,  +5,   0,   0, -50,   0,  +5],
	"LW":  [+10, -10,   0,  +3,  -3, -50,   0, +10],
	"RW":  [+10, -10,   0,  +3,  -3, -50,   0, +10],
	"CF":  [+10, -10,  +3,  +5,   0, -50,   0,  +5],
	"ST":  [+12, -18,  -3, +10,  +5, -50,   0,  +5],
}


# Punto de entrada principal. Llama a esto para llenar attributes/potential de un Player.
# season_year se usa para calcular la edad actual.
static func generate_attributes(player: Player, season_year: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pos: String = player.primary_position()
	var age: int = player.age_at(season_year, 7, 1)  # asumimos start of season
	var modifiers: Array = POSITION_MODIFIERS.get(pos, POSITION_MODIFIERS["CM"])

	# 1) Base actual (overall numérico): aleatorio dentro del rango del tier
	var base_now: int = _tier_overall(player.tier, rng)
	# 2) Base potencial: aleatorio dentro del rango del potential_tier (sirve como techo)
	var base_potential: int = _tier_overall(player.potential_tier, rng)
	if base_potential < base_now:
		base_potential = base_now  # potencial nunca puede ser menor que actual

	# 3) Para cada atributo: base + modificador posicional + ruido (±2)
	var atts: Dictionary = {}
	for i in ATTRIBUTE_NAMES.size():
		var att_name: String = ATTRIBUTE_NAMES[i]
		var modifier: int = int(modifiers[i])
		var noise: int = rng.randi_range(-2, 2)
		var value: int = base_now + modifier + noise
		atts[att_name] = clampi(value, 1, 99)

	# 4) Aplicar curva de edad
	atts = _apply_age_curve(atts, age)

	# 5) Aplicar overrides (mandan sobre todo lo demás)
	for k in player.overrides.keys():
		atts[String(k)] = clampi(int(player.overrides[k]), 1, 99)

	player.attributes = atts
	# Potencial numérico = potencial base + el mejor modificador posicional aplicable
	# (el techo del jugador en su atributo principal)
	player.potential = clampi(base_potential + _best_modifier(modifiers), 1, 99)


# Devuelve un overall numérico aleatorio dentro del rango del tier.
static func _tier_overall(tier: String, rng: RandomNumberGenerator) -> int:
	var rng_range: Array = TIER_BASE.get(tier, TIER_BASE["C"])
	return rng.randi_range(int(rng_range[0]), int(rng_range[1]))


# Curva de edad: jóvenes empiezan más bajos; veteranos pierden físico.
static func _apply_age_curve(atts: Dictionary, age: int) -> Dictionary:
	if age < 19:
		# Muy verde: rebaja general moderada
		var penalty: int = 19 - age  # 1 a 4
		for k in atts.keys():
			atts[k] = clampi(int(atts[k]) - penalty * 2, 1, 99)
	elif age < 22:
		# Aún en desarrollo: pequeña rebaja general
		for k in atts.keys():
			atts[k] = clampi(int(atts[k]) - 2, 1, 99)
	elif age <= 29:
		pass  # peak — sin cambios
	elif age <= 32:
		# Inicio de declive físico
		atts["fisico"] = clampi(int(atts["fisico"]) - 3, 1, 99)
		atts["velocidad"] = clampi(int(atts["velocidad"]) - 3, 1, 99)
	elif age <= 34:
		# Declive físico más marcado, mentalidad/pase aguantan
		atts["fisico"] = clampi(int(atts["fisico"]) - 7, 1, 99)
		atts["velocidad"] = clampi(int(atts["velocidad"]) - 7, 1, 99)
		atts["defensa"] = clampi(int(atts["defensa"]) - 2, 1, 99)
		atts["ataque"] = clampi(int(atts["ataque"]) - 2, 1, 99)
	else:
		# 35+
		atts["fisico"] = clampi(int(atts["fisico"]) - 12, 1, 99)
		atts["velocidad"] = clampi(int(atts["velocidad"]) - 12, 1, 99)
		atts["defensa"] = clampi(int(atts["defensa"]) - 5, 1, 99)
		atts["ataque"] = clampi(int(atts["ataque"]) - 5, 1, 99)
		atts["tiro"] = clampi(int(atts["tiro"]) - 3, 1, 99)
	return atts


# Mejor modificador posicional (el atributo más fuerte de la posición).
static func _best_modifier(modifiers: Array) -> int:
	var best: int = -100
	for m in modifiers:
		if int(m) > best:
			best = int(m)
	return best


# ============================================================================
# Cálculo de overall (rating numérico 0-99) para un jugador.
# Si se proporciona slot, se usan pesos específicos de esa posición.
# Si no, se calcula un overall genérico (excluye porteria salvo si el jugador es GK).
# ============================================================================
const SLOT_WEIGHTS := {
	"GK":  { "porteria": 0.50, "mentalidad": 0.15, "fisico": 0.15, "pase": 0.10, "defensa": 0.10 },
	"CB":  { "defensa": 0.40, "fisico": 0.20, "mentalidad": 0.15, "pase": 0.10, "velocidad": 0.10, "ataque": 0.05 },
	"LB":  { "defensa": 0.30, "velocidad": 0.20, "fisico": 0.15, "pase": 0.15, "ataque": 0.10, "mentalidad": 0.10 },
	"RB":  { "defensa": 0.30, "velocidad": 0.20, "fisico": 0.15, "pase": 0.15, "ataque": 0.10, "mentalidad": 0.10 },
	"LWB": { "defensa": 0.20, "velocidad": 0.25, "fisico": 0.15, "pase": 0.15, "ataque": 0.15, "mentalidad": 0.10 },
	"RWB": { "defensa": 0.20, "velocidad": 0.25, "fisico": 0.15, "pase": 0.15, "ataque": 0.15, "mentalidad": 0.10 },
	"CDM": { "defensa": 0.25, "pase": 0.20, "fisico": 0.15, "mentalidad": 0.15, "tiro": 0.10, "ataque": 0.10, "velocidad": 0.05 },
	"CM":  { "pase": 0.25, "mentalidad": 0.15, "fisico": 0.15, "ataque": 0.15, "defensa": 0.15, "tiro": 0.10, "velocidad": 0.05 },
	"CAM": { "pase": 0.20, "ataque": 0.20, "tiro": 0.20, "mentalidad": 0.15, "velocidad": 0.10, "fisico": 0.10, "defensa": 0.05 },
	"LM":  { "pase": 0.15, "ataque": 0.20, "velocidad": 0.20, "fisico": 0.15, "defensa": 0.15, "tiro": 0.10, "mentalidad": 0.05 },
	"RM":  { "pase": 0.15, "ataque": 0.20, "velocidad": 0.20, "fisico": 0.15, "defensa": 0.15, "tiro": 0.10, "mentalidad": 0.05 },
	"LW":  { "ataque": 0.25, "velocidad": 0.25, "tiro": 0.15, "pase": 0.10, "fisico": 0.10, "mentalidad": 0.10, "defensa": 0.05 },
	"RW":  { "ataque": 0.25, "velocidad": 0.25, "tiro": 0.15, "pase": 0.10, "fisico": 0.10, "mentalidad": 0.10, "defensa": 0.05 },
	"CF":  { "ataque": 0.25, "tiro": 0.20, "pase": 0.15, "velocidad": 0.15, "fisico": 0.10, "mentalidad": 0.10, "defensa": 0.05 },
	"ST":  { "ataque": 0.30, "tiro": 0.30, "fisico": 0.15, "velocidad": 0.10, "mentalidad": 0.10, "pase": 0.05 },
}


static func compute_overall(player: Player, slot: String = "") -> int:
	if player.attributes.is_empty():
		return 0
	if slot != "" and SLOT_WEIGHTS.has(slot):
		return _weighted_overall(player, SLOT_WEIGHTS[slot])
	# Sin slot: media simple, ignorando porteria salvo si es GK
	var is_gk: bool = player.primary_position() == "GK"
	if is_gk:
		return _weighted_overall(player, SLOT_WEIGHTS["GK"])
	var total: float = 0.0
	var count: int = 0
	for k in player.attributes.keys():
		if String(k) == "porteria":
			continue
		total += float(player.attributes[k])
		count += 1
	return roundi(total / count) if count > 0 else 0


static func _weighted_overall(player: Player, weights: Dictionary) -> int:
	var total: float = 0.0
	for k in weights.keys():
		var att_value: float = float(player.attributes.get(k, 0))
		total += att_value * float(weights[k])
	return clampi(roundi(total), 0, 99)

